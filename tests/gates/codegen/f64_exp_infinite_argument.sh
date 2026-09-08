#!/bin/sh
# f64_exp_infinite_argument.sh — v6.6.1. `f64_exp`/`f64_exp2` must agree with C and IEEE-754 at
# ±inf: exp(+inf) = +inf, exp(-inf) = +0, and the same for exp2.
#
# ⛔ WHY THIS EXISTS. Both implementations range-reduce by SUBTRACTING a multiple of the argument
# from itself — `x - round(x*log2e)*ln2` — which for ±inf is `inf - inf`, i.e. NaN, and every
# term downstream inherits it. There is a SECOND, independent break in the same function: the
# `2^n` bit-pack reads `f64_to(inf)`, which SATURATES to i64::MIN, so `(n + 1023) << 52` is not
# an exponent at all. Any fix has to guard BEFORE the reduction, not patch the subtraction.
#
# ⚠ IT WAS BROKEN ON BOTH PATHS, WHICH IS WHY THE GATE TESTS BOTH. The aarch64 polyfills
# (`_f64_exp_polyfill`, `_f64_exp2_polyfill` in lib/math.cyr) and the x86 NATIVE x87 sequences
# (`EF64_EXP`/`EF64_EXP2`, which split with `frndint` and subtract) fail identically. Fixing only
# the polyfill would leave every x86 build wrong while the repro's polyfill row went green.
#
# Filed 2026-09-08 from ganita's 1.2.3 P(-1) audit, where `ganita_f64_sinh(+inf)` and
# `ganita_f64_cosh(±inf)` returned NaN and the audit could not tell whose bug it was from the
# outside — the real cost of a NaN with no diagnostic. It propagates through every identity
# containing an exponential.
#
# ⭐ AXIS 3 IS THE ANTI-VACUOUS ONE: the ordinary range must be untouched. A "fix" that returned
# early too often, or clobbered the argument, would pass axes 1-2 and silently break exp itself.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL f64_exp_infinite_argument: no build/cycc"; exit 1; }

run() {   # run <label> <expected-exit>; source on stdin
  cat > "$T/p.cyr"
  "$CC" < "$T/p.cyr" > "$T/p" 2>"$T/p.err" || {
    echo "FAIL f64_exp_infinite_argument: $1 did not compile"
    grep -E '^error' "$T/p.err" | head -3 | sed 's/^/    /'; exit 1; }
  chmod +x "$T/p"; "$T/p"; got=$?
  [ "$got" -eq "$2" ] || { echo "FAIL f64_exp_infinite_argument: $1 -> $got, expected $2"; exit 1; }
}

PRE='include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/math.cyr"
include "lib/syscalls.cyr"
var INF = 0x7FF0000000000000;
var NINF = 0xFFF0000000000000;
'

# ── axis 1 — the NATIVE path (what x86 builds actually execute) ──────────────────────────────
run "native f64_exp/f64_exp2 at +/-inf" 42 <<EOF
${PRE}fn main(): i64 {
    if (f64_exp(INF)   != INF) { return 1; }
    if (f64_exp(NINF)  != 0)   { return 2; }
    if (f64_exp2(INF)  != INF) { return 3; }
    if (f64_exp2(NINF) != 0)   { return 4; }
    return 42;
}
var e = main();
syscall(60, e & 0xFF, 0,0,0,0);
EOF

# ── axis 2 — the POLYFILL path (what aarch64 executes; same defect, same reason) ─────────────
run "polyfill _f64_exp/_f64_exp2 at +/-inf" 42 <<EOF
${PRE}fn main(): i64 {
    if (_f64_exp_polyfill(INF)   != INF) { return 1; }
    if (_f64_exp_polyfill(NINF)  != 0)   { return 2; }
    if (_f64_exp2_polyfill(INF)  != INF) { return 3; }
    if (_f64_exp2_polyfill(NINF) != 0)   { return 4; }
    return 42;
}
var e = main();
syscall(60, e & 0xFF, 0,0,0,0);
EOF

# ── axis 3 — ANTI-VACUOUS: the finite range and the NaN path are unchanged ───────────────────
# exp(1) must still be e, exp2(10) must still be 1024, the overflow/underflow extremes must
# still saturate, and NaN must still propagate (it needs no guard and must not acquire one).
run "finite range, extremes and NaN unchanged" 42 <<EOF
${PRE}var NAN_ = 0x7FF8000000000000;
fn main(): i64 {
    if (f64_exp(F64_ONE) != 0x4005BF0A8B145769) { return 1; }      # e, bit-exact
    if (f64_exp2(f64_from(10)) != 0x4090000000000000) { return 2; } # 1024.0
    if (f64_exp(f64_from(710)) != INF) { return 3; }                # overflows to +inf
    if (f64_exp(f64_from(0 - 800)) != 0) { return 4; }              # underflows to 0
    var n = f64_exp(NAN_);
    if ((n & 0x7FF0000000000000) != 0x7FF0000000000000) { return 5; }
    if ((n & 0x000FFFFFFFFFFFFF) == 0) { return 6; }                # still a NaN, not inf
    if (_f64_exp_polyfill(F64_ONE) == 0) { return 7; }              # polyfill finite path alive
    return 42;
}
var e = main();
syscall(60, e & 0xFF, 0,0,0,0);
EOF

echo 'PASS f64_exp_infinite_argument: exp/exp2 give +inf and +0 at +/-inf on BOTH the native x87 path and the aarch64 polyfill · the finite range, the overflow/underflow extremes and NaN propagation are unchanged'
exit 0
