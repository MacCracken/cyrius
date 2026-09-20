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
#     fn bad(): f64v2 { return (41, 7); }                         -> caller read 0 (X10-X12)
#
# ROOT CAUSE. PARSE_RETURN's `_is_simd128` / `_is_simd256` branches handle exactly
# `return IDENT;` for a local of the matching class and fall through to the scalar PCMPE path
# for everything else, so rax held whatever the expression left there and rdx was never written.
# The v6.4.31 `_TARGET_PE` arm covers only `return <simd_call>(..)`. This is the same shape as
# bite 16c's 9-16 byte struct pair, one type class over.
#
# ⚠ THREE SITES, AND ONLY ONE OF THEM IS THE PARSE_RETURN REFUSAL. Two earlier arms of
# PARSE_RETURN handle a `return` themselves and `return 0` out of the function, so the refusal
# ~330 lines down never sees them:
#   * the TAIL-CALL path takes `return f(args);` and a `jmp` hands the callee's return
#     convention straight back to OUR caller — rows X6 and X7. Mutant m3.
#   * the MULTI-RETURN path takes `return (a, b);` and hands the values back in the ret2/ret3
#     INT convention (rax:rdx[:r3]), which is not the vector ABI on any target — rows X10-X12,
#     added by bite 21's review, which found the first refusal shipped with this hole open.
#     Mutant m4. The PAIR class is untouched (rax:rdx IS its ABI) and so is the scalar
#     multi-return: rows A7 (pair, host + win64) and A8/A9 (scalar, all four legs) are exactly
#     those, and they must stay GREEN under m4 as well as on the real tree.
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
#   m1 all three sites reverted             -> RED, all 12 refusal rows (host)
#   m2 PARSE_RETURN refusal only reverted   -> RED, the 9 rows X1-X9 (host); X10-X12 stay green
#   m3 tail-call guard only reverted        -> RED, rows X6 and X7 only — the two CALL-form
#                                              rows, which the tail path takes before the
#                                              vector branch can see them
#   m4 multi-return guard only reverted     -> RED, rows X10, X11 and X12 only — the tuple
#                                              rows, which the multi-return arm takes before
#                                              the vector branch can see them. A7/A8/A9 stay
#                                              GREEN under m4, which is what proves the guard
#                                              is keyed on the vector classes and not on the
#                                              tuple syntax.
#   real tree                               -> GREEN (82 rows: 48 refusals, 34 acceptances —
#                                              12 refusal rows x 4 legs, 9 acceptance rows x 4
#                                              minus A7's two skipped legs, see a_legs —
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
    X10) printf '%s' 'fn bad(): f64v2 { return (41, 7); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X11) printf '%s' 'fn bad(): i64v2 { return (41, 7); }
fn main(): i64 { var v: i64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X12) printf '%s' 'fn bad(): f64v4 { return (41, 7, 9); }
fn main(): i64 { var v: f64v4 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    esac
}
REFUSE_ROWS="X1 X2 X3 X4 X5 X6 X7 X8 X9 X10 X11 X12"

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
    # A7-A9: the tuple return is refused for the VECTOR classes ONLY. These three are the
    # shapes X10-X12 sit next to and must not take with them — the rax:rdx pair struct, whose
    # ABI the ret2 convention IS, and the scalar arity-2/arity-3 multi-return. Each packs its
    # values into distinct decimal digits so a row cannot pass with the operands swapped or
    # with one register left unwritten.
    A7) printf '%s' 'struct P2 { a; b; }
fn good(): P2 { return (41, 7); }
fn main(): i64 { var p: P2 = good(); return p.a + p.b; }
var r = main(); syscall(60, r);
' ;;
    A8) printf '%s' 'fn two(): i64 { return (5, 6); }
fn main(): i64 { var a, b = two(); return a * 10 + b; }
var r = main(); syscall(60, r);
' ;;
    A9) printf '%s' 'fn three(): i64 { return (1, 2, 3); }
fn main(): i64 { var a, b, c = three(); return a * 100 + b * 10 + c; }
var r = main(); syscall(60, r);
' ;;
    esac
}
ACCEPT_ROWS="A1 A2 A3 A4 A5 A6 A7 A8 A9"
# Which legs an acceptance row RUNS on. Everything runs everywhere except A7, whose int-class
# 16-byte pair return is a per-target ABI the tuple guard has nothing to do with:
#   cx      — refuses it outright with its own diagnostic (`cx: int-class 16B struct pair-return
#             ABI not supported`), which is itself the proof the FRONTEND passed the tuple
#             through; the vector refusal would have stopped it before the backend saw it.
#   aarch64 — silently loses the second register: 41 for 48. PRE-EXISTING — measured identical
#             on this lane's parent compiler (701fb02f), so it is not this bite's and not this
#             gate's to turn red. Reported by bite 21's review for a later bite.
# A8 and A9 (the SCALAR arity-2/arity-3 multi-return) run on all four legs and are green on all
# four, so the "tuple syntax still works" property is not host-only.
a_legs() { case "$1" in A7) echo "host win64";; *) echo "host cx aarch64 win64";; esac; }
# Every expectation is derived a different way from the program that produces it: the vector
# rows read a lane the source stored a literal into, A7 sums two distinct fields (41+7=48, and
# 7+41 is the same — so A7 is paired with X10, which has the same operands and must be REFUSED),
# A8/A9 pack each return slot into its own decimal digit so a swap or an unwritten register
# cannot land on the expected number.
a_want() {
    case "$1" in
    A1) echo 41;; A2) echo 7;; A3) echo 41;; A4) echo 7;; A5) echo 41;; A6) echo 33;;
    A7) echo 48;; A8) echo 56;; A9) echo 123;;
    esac
}

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
        case " $(a_legs "$row") " in *" $1 "*) ;; *) echo "  skip: $1 $row (see a_legs)"; continue;; esac
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

# Anti-vacuous. The floor is DERIVED from the row tables (every row on host + cx, the two legs
# that are always present) so adding a row cannot leave a stale hard-coded number behind.
nr_rows=$(set -- $REFUSE_ROWS; echo $#)
[ "$nrefuse" -ge $((nr_rows * 2)) ] || bad "only $nrefuse refusal rows ran (floor $((nr_rows * 2)) = $nr_rows rows x host + cx)"
# The acceptance floor sums a_legs over the two always-present legs rather than multiplying, so
# a row excluded from a leg is subtracted here automatically and an over-broad exclusion lowers
# the floor visibly instead of silently passing.
na_floor=0
for row in $ACCEPT_ROWS; do
    for leg in host cx; do
        case " $(a_legs "$row") " in *" $leg "*) na_floor=$((na_floor + 1));; esac
    done
done
[ "$naccept" -ge "$na_floor" ] || bad "only $naccept acceptance rows ran (floor $na_floor = a_legs summed over host + cx)"
# And every row id in both tables must actually produce a source — a typo'd id would otherwise
# compile an EMPTY program, which cycc accepts (exit 0, runnable binary) and would score a row.
for row in $REFUSE_ROWS $ACCEPT_ROWS; do
    if [ "$(r_src "$row"; a_src "$row")" = "" ]; then bad "row $row has no source in either table"; fi
done
# And the message this gate greps for must still be the one the compiler emits.
n=$(grep -c "$MSG" src/frontend/parse_fn.cyr || true)
[ "$n" -ge 1 ] || bad "src/frontend/parse_fn.cyr no longer spells '$MSG' — reworded?"

echo "simd_return_shapes: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$fail" -eq 0 ]
