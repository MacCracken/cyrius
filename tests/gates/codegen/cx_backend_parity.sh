#!/bin/sh
# cx_backend_parity.sh — 6.7.6 (Break 1, lane F). Values the cx bytecode backend got wrong while
# every native backend got them right, each run NATIVELY (x86, the oracle) and on cxvm.
#
# THE DEFECTS (measured on cycc 6.7.5 with this tree's cycc_cx + cxvm):
#   A  `~x` was `x` on cx. ENOTR emitted `xor r0, r0, r31` on the word of a comment that r31 held
#      all-ones; nothing ever set it and cxvm zeroes its registers. `var x = 6; return ~x + 10;`
#      exited 16 on cx, 3 on x86 / aarch64 / PE; bitclr / bitset complement their mask, so they
#      kept the bits they were asked to clear (bitclr(0xFF, 4, 4) = 0xF0, want 0x0F).
#   B  lib/fnptr.cyr had no CYRIUS_TARGET_CX arm. A direct `fncallN(..)` is lowered by the
#      compiler, but an ADDRESS-TAKEN `&fncallN` called through another indirect call runs the
#      library body, whose per-target asm arms matched nothing on cx: `fncall2(&fncall1, &add1, 41)`
#      exited 0 on cx, 42 natively. Each fncallN now ends in `#ifdef CYRIUS_TARGET_CX` `result =
#      callptr(fp, ..)`.
#   C  a call of more than 248 arguments. ECALLPOPS popped argument k into r(3 + k) for every k, in
#      a 256-register file: argument 248 landed in r251 (the call-boundary scratch), 250 in fp, 251
#      in sp, and from 253 the operand byte wrapped to r0. 249..251 arguments returned a wrong value
#      (`f(1..250)` returning p250 - p246 exited 2, want 4) and 252+ trapped "cxvm: guest stack
#      overflow". Integer arguments past the register window (232 since D) now ride the guest
#      stack: the caller lowers sp by 8 per argument and stores them there, the callee (fp = that
#      sp) copies them into its slots, ECALLCLEAN raises sp again.
#   D  value-form vector arguments rode a register band at r16..r31 — integer argument registers
#      from the 14th on. The caller loaded the vector after popping the integers, over a13..; the
#      callee stored the pair from the same registers: `g14(v, a0..a13)` read a13 as the vector's
#      low lane (the probe exited 1 on cx, 7 natively). The band is now r235..r250
#      (_CX_VEC_BASE), and the integer window r3..r234 (_CX_ARG_REGS = 232).
#
# ROWS
#   T  tests/tcyr/codegen/cx_backend_parity.tcyr: native x86 and cxvm must each print
#      "<N> passed, 0 failed (<N> total)" and exit 0, N = the assertions counted in the source
#      (floor below) — on cx every one, natively those outside `#ifdef CYRIUS_TARGET_CX` blocks (none
#      since 6.7.6 lane E2 fixed x86-SysV's fncall8, which passed args 7/8 in the C order: the
#      &fncall8 row, cx-only until then, now runs everywhere — floor 57 -> 58).
#      The same file on aarch64 (qemu-aarch64) and PE (wine, a private prefix torn down on exit) is
#      the other ABIs' oracle; either leg is a named SKIP when its tool is absent.
#   A1 the filed repro, inline: native and cxvm both exit 3.
#   B1 the filed repro, inline: native and cxvm both exit 42.
#   C1 the filed repro's shape, generated: `f(p1..p250)` returning p250 - p246 exits 4 (cx gave 2);
#      C2 the same at 260 arguments (cx trapped); C3 260 arguments through callptr, 2000 times in a
#      loop, and the caller's sp the same afterwards (exit 8 when a call does not take its block back).
#   D1 the probe, inline: g13 / g14 / g16 (a vector beside 13, 14 and 16 ints) — bits 1|2|4, exit 7
#      natively and on cxvm (cx gave 1: g13 was right, g14 and g16 were not).
#
# COMPILERS. CC=${CYCC:-build/cycc} builds the native legs and the cx compiler from THIS tree's
# src/main_cx.cyr, and cxvm from programs/cxvm.cyr. A cx-backend mutation is therefore picked up
# by running the gate from a mutated COPY of the tree, with the real build/cycc.
#
# MUTATION LEDGER (6.7.6, each in a scratch copy of the tree, the gate run from that copy with the
# real build/cycc; measured on the final tree — 58 cx rows, 57 native — which is green, 10 / 10):
#   M1 ENOTR back to `CX_EMIT(S, 34, 0, 0, 31)`      -> T cx RED (50 passed, 8 failed: every A row)
#                                                       + A1 RED (cx 16)
#   M2 lib/fnptr.cyr's nine CYRIUS_TARGET_CX arms gone -> T cx RED (47 passed, 11 failed: every B row)
#                                                       + B1 RED (cx 0)
#   M3 `_CX_ARG_REGS` = 1000000 (every argument a register again, the pre-6.7.6 ABI)
#                                                    -> T cx RED (the 249 row wrong, then a trap) +
#                                                       C1 (cx 2) + C2 (trap) + C3 RED; and
#                                                       wide_call_stack_unwind.sh axis 4 RED
#   M4 ECALLCLEAN never takes the block back          -> T cx RED (46 passed, 12 failed: every sp row
#                                                       past the window, -8 at 233) + C3 RED (exit 8)
#   M5 ESTOREPARM's guest-stack branch dropped        -> T cx RED (42 passed, 16 failed) + C1 (cx 248)
#   M6 `_CX_VEC_BASE` = 16 (the vector band back at r16..r31)
#                                                    -> T cx RED (50 passed, 8 failed: every D row;
#                                                       d14 1882, want 2022) + D1 RED (cx 1)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: cx_backend_parity — no compiler at $CC (exit 77: a SKIP, not a PASS)"; exit 77; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP: cx_backend_parity — no timeout(1) (exit 77)"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
# A PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper.
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

"$CC" < src/main_cx.cyr > "$D/cc" 2> "$D/cc.err"; [ -s "$D/cc" ] || { echo "FAIL: cannot build the cx compiler from src/main_cx.cyr"; exit 1; }
"$CC" < programs/cxvm.cyr > "$D/vm" 2> "$D/vm.err"; [ -s "$D/vm" ] || { echo "FAIL: cannot build cxvm from programs/cxvm.cyr"; exit 1; }
chmod +x "$D/cc" "$D/vm"

pass=0; fail=0
ok()  { printf '  ok: %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail+1)); }

# cx_file FILE [secs] -> CXRC, CXERR (stderr's first line), CXOUT (stdout's last line)
cx_file() {
    CXRC=255; CXERR=''; CXOUT=''
    "$D/cc" < "$1" > "$D/c.cyx" 2> "$D/c.cerr" || { CXERR="cx compile failed: $(grep -v '^note' "$D/c.cerr" | head -1)"; CXRC=-1; return; }
    CXRC=0; ( ulimit -c 0; timeout "${2:-60}" "$D/vm" < "$D/c.cyx" ) > "$D/c.out" 2> "$D/c.verr" || CXRC=$?
    CXERR=$(head -1 "$D/c.verr"); CXOUT=$(tail -1 "$D/c.out")
}
nat_file() {
    NATRC=-1; NATOUT=''
    "$CC" < "$1" > "$D/n.bin" 2> "$D/n.err" || return
    chmod +x "$D/n.bin"; NATRC=0
    { ( ulimit -c 0; timeout 60 "$D/n.bin" ) > "$D/n.out" 2>&1 || NATRC=$?; } 2> /dev/null
    NATOUT=$(tail -1 "$D/n.out")
}
# both LABEL SRC WANT [secs]: cx and native must both exit WANT
both() {
    printf '%s\n' "$2" > "$D/s.cyr"
    nat_file "$D/s.cyr"; cx_file "$D/s.cyr" "${4:-60}"
    if [ "$NATRC" != "$3" ]; then bad "$1: native exits $NATRC, want $3 (the expectation itself is wrong)"; return; fi
    if [ "$CXRC" = "$3" ]; then ok "$1 (cx $CXRC = native)"; else bad "$1: cx exits $CXRC (want $3, native $NATRC)${CXERR:+ — $CXERR}"; fi
}

echo "T. tests/tcyr/codegen/cx_backend_parity.tcyr, native and on cxvm"
TC=tests/tcyr/codegen/cx_backend_parity.tcyr
# NCX: every assertion; N: those outside `#ifdef CYRIUS_TARGET_CX` ... `#endif` (cx-only rows).
NCX=$(grep -c '^[[:space:]]*assert_[a-z]*(' "$TC")
N=$(awk '/^[[:space:]]*#ifdef CYRIUS_TARGET_CX/{s=1; next} /^[[:space:]]*#endif/{s=0; next} !s && /^[[:space:]]*assert_[a-z]*\(/{n++} END{print n+0}' "$TC")
FLOOR=58
if [ "$N" -lt "$FLOOR" ]; then bad "T: only $N assertions outside the cx-only blocks of $TC (floor $FLOOR) — rows were lost"
else
    nat_file "$TC"
    if [ "$NATRC" = 0 ] && [ "$NATOUT" = "$N passed, 0 failed ($N total)" ]; then ok "T native: $NATOUT"
    else bad "T native: exit $NATRC, '$NATOUT' (want '$N passed, 0 failed ($N total)')"; fi
    cx_file "$TC" 120
    if [ "$CXRC" = 0 ] && [ "$CXOUT" = "$NCX passed, 0 failed ($NCX total)" ]; then ok "T cx: $CXOUT"
    else bad "T cx: exit $CXRC, '$CXOUT' (want '$NCX passed, 0 failed ($NCX total)')${CXERR:+ — $CXERR} $(grep -m3 'FAIL' "$D/c.out" | tr '\n' ' ')"; fi
    if command -v qemu-aarch64 > /dev/null 2>&1; then
        "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null; chmod +x "$D/cc_a64" 2> /dev/null
        if [ -s "$D/cc_a64" ] && "$D/cc_a64" < "$TC" > "$D/t.a" 2> "$D/t.aerr" && [ -s "$D/t.a" ]; then
            chmod +x "$D/t.a"; got=0; (cd "$D" && ulimit -c 0; timeout 300 qemu-aarch64 ./t.a > "$D/t.aout" 2>&1) || got=$?
            last=$(tail -1 "$D/t.aout")
            if [ "$got" = 0 ] && [ "$last" = "$N passed, 0 failed ($N total)" ]; then ok "T aarch64 (qemu): $last"
            else bad "T aarch64 (qemu): exit $got, '$last' $(grep -m3 'FAIL' "$D/t.aout" | tr '\n' ' ')"; fi
        else bad "T aarch64: could not build src/main_aarch64.cyr or the tcyr: $(grep '^error' "$D/t.aerr" 2> /dev/null | head -1)"; fi
    else echo "  SKIP: T aarch64 — qemu-aarch64 not installed"; fi
    if command -v wine > /dev/null 2>&1; then
        if CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$D/t.exe" 2> "$D/t.werr" && [ -s "$D/t.exe" ]; then
            got=0
            (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine ./t.exe > "$D/t.wout" 2> /dev/null) || got=$?
            last=$(tail -1 "$D/t.wout" | tr -d '\r')
            if [ "$got" = 0 ] && [ "$last" = "$N passed, 0 failed ($N total)" ]; then ok "T PE (wine): $last"
            else bad "T PE (wine): exit $got, '$last' $(grep -m3 'FAIL' "$D/t.wout" | tr '\n' ' ')"; fi
        else bad "T PE: the tcyr did not compile: $(grep '^error' "$D/t.werr" | head -1)"; fi
    else echo "  SKIP: T PE — wine not installed"; fi
fi

echo "A. ~x"
both "A1 var x = 6; return ~x + 10; (the filed repro; cx gave 16)" 'fn main() { var x = 6; return ~x + 10; }
var r = main();
syscall(60, r);
' 3

echo "B. an address-taken &fncallN"
both "B1 fncall2(&fncall1, &add1, 41) (the filed repro; cx gave 0)" 'include "lib/fnptr.cyr"
fn add1(x) { return x + 1; }
fn main() { return fncall2(&fncall1, &add1, 41); }
var r = main();
syscall(60, r);
' 42

echo "C. calls past the register window (the filed 250 / 260)"
# wide N MODE: f(p1..pN) returns pN - p(N-4); MODE direct | loop (2000 callptr calls: exit 4 only
# when every one returned 4 AND the caller's sp — the address of a local in a fresh frame — is the
# same after the loop as before it; 9 = a wrong value, 8 = sp moved).
wide() {
    awk -v n="$1" -v m="$2" 'BEGIN {
        printf "fn spp() { var x = 1; return &x; }\n";
        printf "fn f(";
        for (i = 1; i <= n; i++) { if (i > 1) printf ", "; printf "p%d", i; }
        printf ") { return p%d - p%d; }\n", n, n - 4;
        a = ""; for (i = 1; i <= n; i++) { if (i > 1) a = a ", "; a = a i; }
        if (m == "direct") printf "fn main() { return f(%s); }\n", a;
        if (m == "loop") printf "fn main() { var s0 = spp(); var i = 0; var bad = 0; while (i < 2000) { if (callptr(&f, %s) != 4) { bad = bad + 1; } i = i + 1; } if (bad != 0) { return 9; } if (spp() != s0) { return 8; } return 4; }\n", a;
        printf "var r = main();\nsyscall(60, r);\n";
    }'
}
both "C1 f(1..250) returns p250 - p246 (the filed repro's shape; cx gave 2)" "$(wide 250 direct)" 4
both "C2 f(1..260) (the filed repro; cx trapped 'guest stack overflow')" "$(wide 260 direct)" 4
both "C3 260 arguments through callptr, 2000 calls in a loop, sp the same after it" "$(wide 260 loop)" 4 120

echo "D. a value-form vector beside 14+ integer arguments"
both "D1 g13 / g14 / g16: a vector beside 13, 14, 16 ints (cx gave 1)" 'include "lib/alloc.cyr"
include "lib/simd.cyr"
fn g13(v: f64v2, a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12): i64 {
    return a12 * 1000 + a11 * 100 + load64(&v) * 10 + load64(&v + 8);
}
fn g14(v: f64v2, a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13): i64 {
    return a13 * 10000 + a12 * 1000 + a11 * 100 + load64(&v) * 10 + load64(&v + 8);
}
fn g16(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, v: f64v2): i64 {
    return a15 * 100000 + a14 * 10000 + a13 * 1000 + a12 * 100 + load64(&v) * 10 + load64(&v + 8);
}
fn main(): i64 {
    alloc_init();
    var v = f64v2_make(7, 8);
    var r = 0;
    if (g13(v, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 6) == 6578) { r = r + 1; }
    if (g14(v, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 5, 6) == 65478) { r = r + 2; }
    if (g16(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 4, 5, v) == 543278) { r = r + 4; }
    return r;
}
syscall(60, main());
' 7

echo
echo "cx_backend_parity: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
echo "PASS cx_backend_parity: ~x is the complement on cx (bitset / bitclr with it), an address-taken &fncallN runs its callee there, a call of more than 232 arguments passes every one, and a vector argument beside 14+ ints arrives intact, as on every native backend"
