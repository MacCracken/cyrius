#!/bin/sh
# tests/gates/frontend/generic_t_return_decl.sh — 6.7.15
#
# A `: T` GENERIC WHOSE T BINDS NO STRUCT AT THE CALL, RECEIVED INTO A STRUCT-ANNOTATED LOCAL, IS A HANDLE, as the
# non-generic word-returning call is (the user's decision D13 (a), 2026-10-18). With `fn gid<T>(x: T): T`,
# `var a: P3 = gid(5);` reaches gid's i64 base, which returns a word: `a` holds it as the struct's address, as
# `var b: P3 = wid(5);` with `fn wid(x): i64` does (the guide's handle line, 6.7.10) — `gid(alloc(24))` reads and
# writes the record, and `a.z` of `gid(5)` reads address 5 + 16 at run time, the fault `wid(5)` gives.
# ⛔ THROUGH 6.7.14 PARSE_VAR's reset (`_gen_decl_reset`, src/frontend/parse_decl.cyr) dropped the annotation for a
# `: T` callee whatever T bound, so a scalar instance left `a` an untyped word: `a.z` was refused "no struct type in
# scope for 'a'" at the use (the filed repro 1, `gid(w.v)` — i64 by the whole-argument rule), and with no field use
# the annotation was dropped in silence (repro 2, exit 5). The reset now asks what the reached fn returns: a T bound
# to a struct returns it by value (GFRS > 0) and is received as before — a copy, another struct refused at the
# declaration — while a word (its base, a scalar or f64 instance) keeps the annotation, a handle.
# Filed: docs/development/issues/2026-10-17-generic-t-return-scalar-instance-into-struct-local-reported-at-use.md
#
#   R1  the filed repro 1, verbatim (`gid(w.v)`, then `a.z`): compiles (refused at `a.z` before), and runs as its
#       non-generic twin `wid(w.v)` does — the handle holds w.v's first word, so `a.z` faults on every leg alike
#   R2  the filed repro 2, verbatim (`gid(5)`, `return a;`): 5, the word the handle holds (5 before, untyped)
#   T1  `gid(alloc(24))` with a field write and read: 4 (refused before)
#   T2  `gid(5)` then `a.z`: compiles, and exits as `wid(5)`'s twin does (the read of address 5 + 16)
#   T3  `gid<i32>(0 - 3)`, its word: 7 (+ 10), as `fn wi(x: i32): i32`'s twin; T4 `gid(h)` with h: f64, its word's top
#       byte: 63, as `fn wf(x: f64): f64`'s twin; T5 `gid(w.v)`'s word: 7 (w.v.x), as `wid(w.v)`'s twin
#   K1  `gid(p3)` with p3: P3 receives the struct, a copy: 9 (unchanged); K2 `gid(q)` with q: Pt is refused at the
#       declaration, once (unchanged); K3 `gid<P3>(p3)`: a copy, 8 (unchanged); K4 a refused call — a stub's scalar
#       binding, `gs(5)` — keeps the annotation too: its one refusal, no "no struct type in scope for 'a'" at `a.z`
#       (6.7.14 printed both)
#   TV  tests/tcyr/crossos/generic_t_return_handle.tcyr (9 rows) passes
#   Every run row on x86_64, x86_64 CYRIUS_IR=3, aarch64 (qemu), cx (cxvm) and PE (wine); MO the tcyr and T1 compile
#   as Mach-O (CYRIUS_MACHO=1, and CYRIUS_MACHO_ARM=1 through the aarch64 compiler) — the binaries run on macOS only.
#
# MUTATION LEDGER (2026-10-18; a scratch copy of src/ with the one change, its 2-stage cycc as CYCC — the aarch64 /
# cx legs build from the tree's own src, so the mutant shows on x86_64 / IR / PE):
#   MT1 `_gen_decl_reset` as 6.7.14 left it (the reset for every `: T`) -> RED R1 T1 T2 (refused at the use), K4
#       (the cascade), TV and MO (the file does not build) on x86 / IR / PE — as the lane's previous compiler; R2,
#       T3-T5 green (an untyped word holds the same value)
#   MT2 `_gen_decl_reset` answering 0 throughout -> GREEN here: K1-K3 take the struct by value from gid's struct
#       instance either way (the reset re-derives an explicit instance annotation's receive, 6.6.11 / 6.7.14 — the
#       gates of those releases carry it)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_t_return_decl
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
WP="$D/wine"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null
unset CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_BOUNDS

fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

TC=tests/tcyr/crossos/generic_t_return_handle.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=9
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi

# The legs this box can run: aarch64 under qemu, cx under the tree's own cxvm, PE under wine.
A64=""; CXCC=""; WINE=0
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then chmod +x "$D/cc_a64"
else bad "aarch64: src/main_aarch64.cyr did not build"; fi
if command -v qemu-aarch64 > /dev/null 2>&1; then [ -s "$D/cc_a64" ] && A64="$D/cc_a64"
else echo "  SKIP: aarch64 legs (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: PE legs (wine not installed)"; skips=$((skips + 1)); fi

# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build), LAST (the last
# line of its output, CR stripped).
run_leg() {
    RC=-1; LAST=''
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        ir3)   CYRIUS_IR=3 "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3.exe" 2> "$3.err" || return 0 ;;
    esac
    RC=0
    case "$1" in
        x86|ir3) chmod +x "$3"; { timeout 60 "$3" > "$3.out" 2>&1; } 2> /dev/null || RC=$? ;;   # a fault is a row's answer
        a64)  chmod +x "$3"; { timeout 300 qemu-aarch64 "$3" > "$3.out" 2>&1; } 2> /dev/null || RC=$? ;;
        cx)   timeout 300 "$D/cxvm" < "$3" > "$3.out" 2>&1 || RC=$? ;;
        pe)   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$3.exe" > "$3.out" 2> /dev/null) || RC=$? ;;
    esac
    LAST=$(tail -1 "$3.out" | tr -d '\r')
}
LEGS="x86 ir3"
[ -n "$A64" ] && LEGS="$LEGS a64"
[ -n "$CXCC" ] && LEGS="$LEGS cx"
[ "$WINE" = 1 ] && LEGS="$LEGS pe"

# xrow <id> <src> <want-exit> <what>: on every leg, compiles and exits <want-exit>
xrow() {
    for leg in $LEGS; do
        run_leg "$leg" "$2" "$D/$1.$leg"
        if [ "$RC" = -1 ]; then bad "$1 $leg: $4 did not compile: $(grep -m1 '^error' "$D/$1.$leg.err")"
        elif [ "$RC" -ne "$3" ]; then bad "$1 $leg: $4 exited $RC, want $3"
        else ok "$1 $leg: $4 ($3)"; fi
    done
}
# twin <id> <src> <twin-src> <what>: on every leg, both compile and exit alike (the generic and its non-generic twin)
twin() {
    for leg in $LEGS; do
        run_leg "$leg" "$3" "$D/$1t.$leg"
        trc=$RC
        run_leg "$leg" "$2" "$D/$1.$leg"
        if [ "$RC" = -1 ]; then bad "$1 $leg: $4 did not compile: $(grep -m1 '^error' "$D/$1.$leg.err")"
        elif [ "$trc" = -1 ]; then bad "$1 $leg: the twin did not compile: $(grep -m1 '^error' "$D/$1t.$leg.err")"
        elif [ "$RC" -ne "$trc" ]; then bad "$1 $leg: $4 exited $RC, its non-generic twin $trc"
        else ok "$1 $leg: $4 exits as its non-generic twin ($RC)"; fi
    done
}
# prog <file> <body of f>: P3, Pt, W, gid and its twins, and f
prog() {
    printf 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\nstruct P3 { x; y; z; }\nstruct Pt { a; b; }\nstruct W { n; v: P3; }\nfn gid<T>(x: T): T { return x; }\nfn wid(x): i64 { return x; }\nfn wi(x: i32): i32 { return x; }\nfn wf(x: f64): f64 { return x; }\nfn f(): i64 { alloc_init(); %s }\nsyscall(60, f());\n' "$2" > "$1"
}

echo "R. the filed repros, verbatim"
cat > "$D/r1.cyr" <<'XEOF'
struct P3 { x; y; z; }
struct W { n; v: P3; }
fn gid<T>(x: T): T { return x; }
fn f(): i64 { var w: W; var a: P3 = gid(w.v); return a.z; }
syscall(60, f());
XEOF
cat > "$D/r1t.cyr" <<'XEOF'
struct P3 { x; y; z; }
struct W { n; v: P3; }
fn wid(x): i64 { return x; }
fn f(): i64 { var w: W; var a: P3 = wid(w.v); return a.z; }
syscall(60, f());
XEOF
twin R1 "$D/r1.cyr" "$D/r1t.cyr" "var a: P3 = gid(w.v); return a.z; (refused at a.z before)"
cat > "$D/r2.cyr" <<'XEOF'
struct P3 { x; y; z; }
fn gid<T>(x: T): T { return x; }
fn f(): i64 { var a: P3 = gid(5); return a; }
syscall(60, f());
XEOF
xrow R2 "$D/r2.cyr" 5 "var a: P3 = gid(5); return a;"

echo "T. a scalar binding of T: the annotated local is a handle"
prog "$D/t1.cyr" 'var a: P3 = gid(alloc(24)); a.z = 4; return a.z;'
xrow T1 "$D/t1.cyr" 4 "gid(alloc(24)), a.z = 4 then a.z"
prog "$D/t2.cyr" 'var a: P3 = gid(5); return a.z;'
prog "$D/t2t.cyr" 'var a: P3 = wid(5); return a.z;'
twin T2 "$D/t2.cyr" "$D/t2t.cyr" "var a: P3 = gid(5); return a.z;"
prog "$D/t3.cyr" 'var a: P3 = gid<i32>(0 - 3); var k: i64 = a; return k + 10;'
prog "$D/t3t.cyr" 'var a: P3 = wi(0 - 3); var k: i64 = a; return k + 10;'
twin T3 "$D/t3.cyr" "$D/t3t.cyr" "gid<i32>(0 - 3)'s word"
prog "$D/t4.cyr" 'var h: f64 = 1.5; var a: P3 = gid(h); var k: i64 = a; return k >> 56;'
prog "$D/t4t.cyr" 'var h: f64 = 1.5; var a: P3 = wf(h); var k: i64 = a; return k >> 56;'
twin T4 "$D/t4.cyr" "$D/t4t.cyr" "gid(h) with h: f64, its word's top byte"
prog "$D/t5.cyr" 'var w: W; w.v.x = 7; w.v.z = 3; var a: P3 = gid(w.v); var k: i64 = a; return k;'
prog "$D/t5t.cyr" 'var w: W; w.v.x = 7; w.v.z = 3; var a: P3 = wid(w.v); var k: i64 = a; return k;'
twin T5 "$D/t5.cyr" "$D/t5t.cyr" "gid(w.v)'s word (w.v.x, 7)"

echo "K. a struct binding of T: unchanged"
prog "$D/k1.cyr" 'var p3: P3; p3.z = 9; var a: P3 = gid(p3); p3.z = 1; return a.z;'
xrow K1 "$D/k1.cyr" 9 "gid(p3) receives the struct: a copy"
prog "$D/k3.cyr" 'var p3: P3; p3.y = 8; var a: P3 = gid<P3>(p3); p3.y = 2; return a.y;'
xrow K3 "$D/k3.cyr" 8 "gid<P3>(p3): a copy"
prog "$D/k2.cyr" 'var q: Pt; var a: P3 = gid(q); return 0;'
k2rc=0; "$CC" < "$D/k2.cyr" > "$D/k2" 2> "$D/k2.err" || k2rc=$?
ne=$(grep -c '^error' "$D/k2.err" || true)
if [ "$k2rc" -eq 0 ]; then bad "K2: var a: P3 = gid(q) with q: Pt compiled (want it refused)"
elif [ "$ne" -eq 1 ] && grep -q '^error:<source>:10:.*fn return struct-id differs from declared var type' "$D/k2.err"; then ok "K2: gid(q) with q: Pt is refused at the declaration, once"
else bad "K2: not one refusal at the declaration: $(grep '^error' "$D/k2.err" | tr '\n' ' ')"; fi

cat > "$D/k4.cyr" <<'XEOF'
struct P3 { x; y; z; }
struct A { a; b; }
fn gs<T>(x: T): T { var k = x.a; return x; }
fn f(): i64 { var a: P3 = gs(5); return a.z; }
syscall(60, f());
XEOF
k4rc=0; "$CC" < "$D/k4.cyr" > "$D/k4" 2> "$D/k4.err" || k4rc=$?
ne=$(grep -c '^error' "$D/k4.err" || true)
if [ "$k4rc" -eq 0 ]; then bad "K4: var a: P3 = gs(5) of a stub compiled (want it refused)"
elif [ "$ne" -eq 1 ] && grep -q "^error:<source>:4:30: generic 'gs' has no i64" "$D/k4.err"; then ok "K4: a stub's scalar call into P3: its one refusal, no cascade at a.z"
else bad "K4: not one refusal: $(grep '^error' "$D/k4.err" | tr '\n' ' ')"; fi

echo "TV. $TC"
for leg in $LEGS; do
    run_leg "$leg" "$TC" "$D/tv.$leg"
    if [ "$RC" = -1 ]; then bad "TV $leg: $TC did not compile: $(grep -m1 '^error' "$D/tv.$leg.err")"
    elif [ "$RC" -ne 0 ]; then bad "TV $leg: exited $RC: $LAST"
    else
        case "$LAST" in
            "$N passed, 0 failed ($N total)") ok "TV $leg: $LAST" ;;
            *) bad "TV $leg: '$LAST', want '$N passed, 0 failed ($N total)'" ;;
        esac
    fi
done

echo "MO. Mach-O: the tcyr and T1 compile (the binaries run on macOS only)"
for f in "$TC" "$D/t1.cyr"; do
    mrc=0; CYRIUS_MACHO=1 "$CC" < "$f" > "$D/mo.x86" 2> "$D/mo.x86.err" || mrc=$?
    if [ "$mrc" -eq 0 ] && [ -s "$D/mo.x86" ]; then ok "MO x86_64 Mach-O: $(basename "$f") compiles"
    else bad "MO x86_64 Mach-O: $(basename "$f"): rc $mrc $(grep -m1 '^error' "$D/mo.x86.err")"; fi
    if [ -s "$D/cc_a64" ]; then
        mrc=0; CYRIUS_MACHO_ARM=1 "$D/cc_a64" < "$f" > "$D/mo.arm" 2> "$D/mo.arm.err" || mrc=$?
        if [ "$mrc" -eq 0 ] && [ -s "$D/mo.arm" ]; then ok "MO arm64 Mach-O: $(basename "$f") compiles"
        else bad "MO arm64 Mach-O: $(basename "$f"): rc $mrc $(grep -m1 '^error' "$D/mo.arm.err")"; fi
    fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a \`: T\` generic whose T binds no struct is a handle in a struct-annotated local (the user's D13 (a)): the filed repros (R1 R2), gid(alloc(24)) read and written (T1), each scalar binding as its non-generic twin (T2-T5), the struct bindings unchanged (K1-K3), and the tcyr (TV) on x86_64 / IR / aarch64 / cx / PE; Mach-O compiles (MO)"
