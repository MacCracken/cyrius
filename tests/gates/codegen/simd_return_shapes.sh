#!/bin/sh
# Gate: a vector-returning fn `return`s only what the vector return ABI can carry (6.6.6).
#
# THE DEFECT (measured at 6.6.5 and at this lane's parent, x86_64 Linux, NO diagnostic, exit 0):
#
#     fn bad(): f64v2 { return 5; }        -> compiled clean, the caller read 0
#     fn bad(): f64v2 { var s = 5; return s; }                    -> same
#     fn bad(): f64v2 { return; }                                 -> same
#     fn bad(x: f64v2, y: f64v2): f64v2 { return x + y; }         -> returned Y UNCHANGED
#     fn bad(): f64v2 { var v: f64v2 = mkv(41,7); return load64(&v); }  -> lo right, hi stale
#     fn sc(): i64 { return 5; }  fn bad(): f64v2 { return sc(); }      -> garbage
#     fn mk4(): f64v4 { ... }     fn bad(): f64v2 { return mk4(); }     -> 32 B into a 16 B return
#
# ROOT CAUSE. PARSE_RETURN's `_is_simd128` / `_is_simd256` branches handle exactly
# `return IDENT;` for a local of the matching class and fall through to the scalar PCMPE path
# for everything else, so rax held whatever the expression left there and rdx was never written.
# The v6.4.31 `_TARGET_PE` arm covers only `return <simd_call>(..)`. This is the same shape as
# bite 16c's 9-16 byte struct pair, one type class over.
#
# ⚠ TWO SITES, AND THE TAIL-CALL ONE IS NOT OPTIONAL. `return f(args);` is taken by the tail
# path BEFORE the vector branch sees it, and a `jmp` hands the callee's return convention
# straight back to OUR caller — so the two CALL-form rows (X6 `return sc();` and X7
# `return mk4();`) are invisible to the PARSE_RETURN refusal alone. Mutant m3 is that half
# reverted, and it reddens exactly those two.
#
# ⚠ THE CALL FORM IS TESTED ON THE EXACT DECLARED TYPE while `return IDENT;` accepts any local
# of the same CLASS. Deliberate: the IDENT branches byte-copy 16/32 bytes (right whatever the
# lane type), but the PE arm keys on `GFRS(callee) == _cur_fn_ret_scalar`, so a same-class call
# of a different declared type would miss that arm and land on the generic path on Windows.
#
# LEGS: host x86_64 (refusals + acceptances), the tree's own cx compiler under cxvm, aarch64
# under qemu-aarch64 and Win64 PE under wine when installed. qemu and wine are EMULATION, NOT
# hardware — the ecb/ach/cass/pi legs of the release gate are what verify the real thing.
# Refusal is a compile-time property, so every compiler is asked; only acceptances need a runner.
#
# EXPECTED VALUES. Refusals are checked on the MESSAGE, not just a non-zero exit, so a row
# cannot pass on an unrelated syntax error. Acceptances check BOTH lanes of the vector, by two
# separate programs, so a path that carries only the low half (exactly what the defect did)
# fails — and the values are re-derived per leg by the same program built by that leg's compiler.
#
# MUTATION LEDGER (6.6.6 — each mutant is a scratch tree from `git archive HEAD` with the named
# hunk of src/frontend/parse_fn.cyr reverted, rebuilt with build/cycc, run as CYCC=<mutant>):
#   m1 both sites reverted                  -> RED, all 9 refusal rows (host)
#   m2 PARSE_RETURN refusal only reverted   -> RED, all 9 refusal rows (host)
#   m3 tail-call guard only reverted        -> RED, rows X6 and X7 only — the two CALL-form
#                                              rows, which the tail path takes before the
#                                              vector branch can see them
#   real tree                               -> GREEN (60 rows: 36 refusals, 24 acceptances,
#                                              across host + cx + qemu-aarch64 + wine-PE)
# Mutants were measured on a host-only copy of this file; the other legs share the frontend.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-$ROOT/build/cycc}
[ -x "$CC" ] || { echo "FAIL: compiler $CC missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$W"; wineserver -k >/dev/null 2>&1 || true' EXIT

MSG="a vector-returning fn carries its result"
pass=0; fail=0; nrefuse=0; naccept=0

bad() { echo "  FAIL: $*"; fail=$((fail+1)); }
good() { echo "  ok: $*"; pass=$((pass+1)); }

MKV='fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
'
MK4='fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, a + 1); return v; }
'

# ---- the row tables -------------------------------------------------------------------------
# One fn per table, `case` on the row id — the sources embed quotes and braces, so a here-doc
# list or an eval'd array would be the fragile spelling.
r_src() {  # $1 row id -> source on stdout
    case "$1" in
    X1) printf '%s' "$MKV"'fn bad(): f64v2 { return 5; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X2) printf '%s' "$MKV"'fn bad(): f64v2 { var s = 5; return s; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X3) printf '%s' "$MKV"'fn bad(): f64v2 { return; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X4) printf '%s' "$MKV"'fn bad(x: f64v2, y: f64v2): f64v2 { return x + y; }
fn main(): i64 { var a: f64v2 = mkv(10,11); var b: f64v2 = mkv(20,21); var c: f64v2 = bad(a,b); return load64(&c); }
var r = main(); syscall(60, r);
' ;;
    X5) printf '%s' "$MKV"'fn bad(): f64v2 { var v: f64v2 = mkv(41,7); return load64(&v); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X6) printf '%s' "$MKV"'fn sc(): i64 { return 5; }
fn bad(): f64v2 { return sc(); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X7) printf '%s' "$MKV$MK4"'fn bad(): f64v2 { return mk4(77); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X8) printf '%s' 'fn bad(): f64v4 { return 5; }
fn main(): i64 { var v: f64v4 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X9) printf '%s' 'fn bad(): f64v2 { var v: f64v4; store64(&v, 41); return v; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    esac
}
REFUSE_ROWS="X1 X2 X3 X4 X5 X6 X7 X8 X9"

a_src() {  # $1 row id -> source on stdout
    case "$1" in
    A1) printf '%s' "$MKV"'fn good(): f64v2 { var v: f64v2 = mkv(41, 7); return v; }
fn main(): i64 { var v: f64v2 = good(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    A2) printf '%s' "$MKV"'fn good(): f64v2 { var v: f64v2 = mkv(41, 7); return v; }
fn main(): i64 { var v: f64v2 = good(); return load64(&v + 8); }
var r = main(); syscall(60, r);
' ;;
    A3) printf '%s' "$MKV"'fn good(): f64v2 { return mkv(41, 7); }
fn main(): i64 { var v: f64v2 = good(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    A4) printf '%s' "$MKV"'fn good(): f64v2 { return mkv(41, 7); }
fn main(): i64 { var v: f64v2 = good(); return load64(&v + 8); }
var r = main(); syscall(60, r);
' ;;
    A5) printf '%s' "$MK4"'fn good(): f64v4 { var v: f64v4 = mk4(41); return v; }
fn main(): i64 { var v: f64v4 = good(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    A6) printf '%s' 'fn sc(): i64 { return 33; }
fn main(): i64 { return sc(); }
var r = main(); syscall(60, r);
' ;;
    esac
}
ACCEPT_ROWS="A1 A2 A3 A4 A5 A6"
a_want() { case "$1" in A1) echo 41;; A2) echo 7;; A3) echo 41;; A4) echo 7;; A5) echo 41;; A6) echo 33;; esac; }

# ---- legs ------------------------------------------------------------------------------------
refuse_all() {  # $1 leg label  $2 compiler
    for row in $REFUSE_ROWS; do
        r_src "$row" > "$W/r.cyr"
        rc=0
        cat "$W/r.cyr" | "$2" > "$W/r.out" 2>"$W/r.err" || rc=$?
        nrefuse=$((nrefuse+1))
        if ! grep -q "$MSG" "$W/r.err" 2>/dev/null; then
            bad "$1 $row: not refused (rc=$rc, first line: $(head -1 "$W/r.err" 2>/dev/null))"
        elif [ -s "$W/r.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused"
        fi
    done
}

accept_all() {  # $1 leg label  $2 compiler  $3 runner fn name
    for row in $ACCEPT_ROWS; do
        a_src "$row" > "$W/a.cyr"
        cat "$W/a.cyr" | "$2" > "$W/a.out" 2>/dev/null || true
        naccept=$((naccept+1))
        if ! [ -s "$W/a.out" ]; then bad "$1 $row: produced no artifact"; continue; fi
        chmod +x "$W/a.out"
        got=0
        ( ulimit -c 0; "$3" "$W/a.out" ) >/dev/null 2>&1 || got=$?
        want=$(a_want "$row")
        if [ "$got" = "$want" ]; then good "$1 $row = $got"; else bad "$1 $row = $got, want $want"; fi
    done
}

hostr() { timeout 60 "$1"; }
echo "host x86_64:"
refuse_all host "$CC"
accept_all host "$CC" hostr

echo "cx (cxvm):"
if cat src/main_cx.cyr | "$CC" > "$W/cycc_cx" 2>/dev/null && [ -s "$W/cycc_cx" ] \
   && cat programs/cxvm.cyr | "$CC" > "$W/cxvm" 2>/dev/null && [ -s "$W/cxvm" ]; then
    chmod +x "$W/cycc_cx" "$W/cxvm"
    cxr() { timeout 60 "$W/cxvm" < "$1"; }
    refuse_all cx "$W/cycc_cx"
    accept_all cx "$W/cycc_cx" cxr
else
    bad "cx leg: could not build src/main_cx.cyr / programs/cxvm.cyr"
fi

if command -v qemu-aarch64 > /dev/null 2>&1; then
    echo "aarch64 (qemu-aarch64 — EMULATION, not hardware):"
    if cat src/main_aarch64.cyr | "$CC" > "$W/cycc_a64" 2>/dev/null && [ -s "$W/cycc_a64" ]; then
        chmod +x "$W/cycc_a64"
        a64r() { timeout 120 qemu-aarch64 "$1"; }
        refuse_all aarch64 "$W/cycc_a64"
        accept_all aarch64 "$W/cycc_a64" a64r
    else
        bad "aarch64 leg: could not build src/main_aarch64.cyr"
    fi
else
    echo "  SKIP: qemu-aarch64 not installed (the pi hardware leg still covers it)"
fi

if command -v wine > /dev/null 2>&1; then
    echo "win64 (wine — EMULATION, not hardware; the PE arm is the one this refusal sits in front of):"
    export WINEPREFIX="$W/wine" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    if cat src/main_win.cyr | "$CC" > "$W/cycc_win" 2>/dev/null && [ -s "$W/cycc_win" ]; then
        chmod +x "$W/cycc_win"
        wr_() { cp "$1" "$1.exe"; timeout 180 wine "$1.exe"; }
        refuse_all win64 "$W/cycc_win"
        accept_all win64 "$W/cycc_win" wr_
    else
        bad "win64 leg: could not build src/main_win.cyr"
    fi
    wineserver -k > /dev/null 2>&1 || true
else
    echo "  SKIP: wine not installed (the cass hardware leg still covers it)"
fi

# Anti-vacuous: 9 refusals + 6 acceptances on host and on cx even with qemu and wine absent.
[ "$nrefuse" -ge 18 ] || bad "only $nrefuse refusal rows ran (floor 18 = 9 rows x host + cx)"
[ "$naccept" -ge 12 ] || bad "only $naccept acceptance rows ran (floor 12 = 6 rows x host + cx)"
# And the message this gate greps for must still be the one the compiler emits.
n=$(grep -c "$MSG" src/frontend/parse_fn.cyr || true)
[ "$n" -ge 1 ] || bad "src/frontend/parse_fn.cyr no longer spells '$MSG' — reworded?"

echo "simd_return_shapes: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$fail" -eq 0 ]
