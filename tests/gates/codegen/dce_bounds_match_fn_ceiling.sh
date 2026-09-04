#!/bin/sh
# dce_bounds_match_fn_ceiling.sh — v6.5.46
#
# ⛔ DCE WAS UNSOUND ABOVE 32768 FUNCTIONS, ON BOTH BACKENDS, FOR SIX RELEASES.
# v6.5.40 raised the fn-table ceiling 32768 -> 131072 and widened the reachability bitmap
# `live[]` from 4096 to 16384 bytes to match — but neither of the two loops that USE the bitmap
# came along:
#   * the clear loop still stopped at 4096, so three quarters of the bitmap started as whatever
#     the stack frame held;
#   * the address-taken (type-3 fixup) root-seed bound was still `t3idx < 32768`, so a function
#     reachable ONLY through its address was never seeded as a root, DCE concluded it was dead,
#     and NOP-filled it. Nothing can follow a raw pointer back, so that is UNSOUND, not merely
#     conservative.
# MEASURED at v6.5.46 with a 33,001-function program whose target is referenced only by `&fn`:
# pre-fix `CYRIUS_DCE=1` exits **139** (SIGSEGV); post-fix it exits 42. DCE off is correct either
# way, which is why this hid — it only bites the flag.
#
# ⚠ SECOND OCCURRENCE. v6.4.75 fixed exactly this clear loop for the 4096 ceiling; the v6.5.40
# raise reintroduced it. A cap raise has to sweep every consumer of the cap, and this gate is
# what makes the next raise sweep them.
#
# PROPERTY: both bounds, on both backends, are DERIVED from the enforced ceiling — never quoted.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fail() { echo "FAIL dce_bounds_match_fn_ceiling: $1" >&2; exit 1; }

# The enforced ceiling is whatever `_capacity_warnings` refuses at — the same number the user is
# told is hard. Read it there rather than from any comment.
CEIL=$(grep -oE 'GFNC\(S\) \* 100 / [0-9]+ >= 85' "$ROOT/src/common/util.cyr" | grep -oE '[0-9]+' | grep -v '^100$' | grep -v '^85$' | head -1)
[ -n "$CEIL" ] || fail "could not read the enforced fn ceiling from _capacity_warnings — the gate is reading nothing"
[ "$CEIL" -ge 32768 ] || fail "parsed an implausible fn ceiling of $CEIL"
# live[] must hold one bit per fn.
WANT_BYTES=$((CEIL / 8))

for f in src/backend/x86/fixup.cyr src/backend/aarch64/fixup.cyr; do
    DECL=$(grep -oE 'var live\[[0-9]+\];' "$ROOT/$f" | grep -oE '[0-9]+')
    [ -n "$DECL" ] || fail "$f: no 'var live[N];' declaration found"
    [ "$DECL" -ge "$WANT_BYTES" ] \
        || fail "$f: live[] is $DECL bytes but the ceiling is $CEIL fns, needing $WANT_BYTES"

    # ⚠ Anchor on `ci < N` ALONE. Matching the whole statement and then taking every number
    # yields "16384 8 0" — the 8 from `store8` and the 0 from `, 0` — measured on this gate's
    # first run. Same trap as reading 64 out of the type name in `i64[128]`.
    CLR=$(grep -oE 'while \(ci < [0-9]+\) \{ store8' "$ROOT/$f" | grep -oE 'ci < [0-9]+' | grep -oE '[0-9]+')
    [ -n "$CLR" ] || fail "$f: could not find the live[] clear loop"
    [ "$CLR" -eq "$DECL" ] \
        || fail "$f: the clear loop zeroes $CLR of $DECL bytes — $((DECL - CLR)) bytes of the reachability bitmap start as stack garbage (this is the v6.4.75 defect, reintroduced by the v6.5.40 raise)"

    # ⚠ Same anchoring discipline: the IDENTIFIER `t3idx` contains a 3, so taking every number
    # out of the matched statement yields "3 131072". Extract the comparison only.
    ROOTB=$(grep -oE 'if \(t3idx < [0-9]+\) \{' "$ROOT/$f" | grep -oE '< [0-9]+' | grep -oE '[0-9]+')
    [ -n "$ROOTB" ] || fail "$f: could not find the address-taken root-seed bound"
    [ "$ROOTB" -ge "$CEIL" ] \
        || fail "$f: the address-taken root bound is $ROOTB but the ceiling is $CEIL — an address-taken fn above $ROOTB is never seeded as a DCE root, so it is NOP-filled and the program faults"
done

echo "PASS dce_bounds_match_fn_ceiling (ceiling $CEIL fns; live[] clear and address-taken root bound agree with it on both backends)"
