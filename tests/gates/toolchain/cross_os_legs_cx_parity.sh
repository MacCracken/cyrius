#!/bin/sh
# Gate: every cross-OS host leg runs the same three cx checks (6.6.20).
#
# scripts/cross-os-selfhost.sh is release-gate step 4 on REAL hardware. Each host leg builds
# a native cxvm and must run:
#   (a) the portable guest-I/O fixture  `_co_cx.cyx`  → exit 42 (the guest's write() went
#       through that host's syscall translation),
#   (b) the cx thread fixture           `_co_cxt.cyx` → exit 255,
#   (c) the native cycc_cx round trip   src/main_cx.cyr → cycc_cx; `_co_cx.cyr` → a .cyx the
#       same cxvm runs to 42.
# Until 6.6.20 the ach (Intel-Mac) leg staged only `_co_cxt.cyx` and ran (b) alone, though the
# x86-macOS tarball ships both cxvm and cycc_cx — so x86-macOS cx guest I/O and its native cx
# compiler were never run on the hardware, while ecb, pi and cass ran all three. That is the
# one-host-missed shape: a check added to some legs and not the others reads green on the
# host that lacks it. This gate reads the script (it runs nothing remote) and refuses a leg
# that drops any of the three, for every host release-gate.sh walks.
#
# Mutation ledger (measured 6.6.20): the 6.6.19 script → axis 2 red on ach (it stages no
# `_co_cx.cyx`); delete the cass `nat.cyx` line → axis 2 red on cass (c); add a fifth host to
# release-gate.sh's loop with no leg here → axis 1 red.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CO=scripts/cross-os-selfhost.sh
RG=scripts/release-gate.sh
fail() { echo "FAIL: cross_os_legs_cx_parity: $1"; exit 1; }
[ -f "$CO" ] || fail "$CO missing"
[ -f "$RG" ] || fail "$RG missing"

# ── axis 1: the host list is release-gate step 4's, and each host has a leg ─────────────
HOSTS=$(sed -n 's/^for H in \([a-z0-9 ]*\); do$/\1/p' "$RG" | head -1)
[ -n "$HOSTS" ] || fail "axis 1: cannot read step 4's host loop from $RG"
_nh=0
for h in $HOSTS; do
    grep -q "^  $h)\$" "$CO" || fail "axis 1: release-gate walks '$h' but $CO has no '  $h)' leg"
    _nh=$((_nh + 1))
done
[ "$_nh" -ge 4 ] || fail "axis 1: only $_nh host(s) read from step 4 ($HOSTS) — expected at least ecb ach cass pi"

# ── axis 2: each leg stages the three fixtures and runs (a), (b) and (c) ────────────────
leg() { awk -v h="  $1)" '$0 == h { on = 1; next } on && /^    ;;$/ { exit } on { print }' "$CO"; }
for h in $HOSTS; do
    L=$(leg "$h")
    [ -n "$L" ] || fail "axis 2: empty leg for $h"
    for f in _co_cx.cyx _co_cx.cyr _co_cxt.cyx; do
        printf '%s\n' "$L" | grep -E '^ *scp ' | grep -qF "$f" || fail "axis 2: the $h leg does not stage $f"
    done
    printf '%s\n' "$L" | grep -E 'cxvm(\.exe)? < _co_cx\.cyx' | grep -q '42' ||
        fail "axis 2: the $h leg does not run the guest-I/O fixture _co_cx.cyx to exit 42 (a)"
    printf '%s\n' "$L" | grep -E 'cxvm(\.exe)? < _co_cxt\.cyx' | grep -q '255' ||
        fail "axis 2: the $h leg does not run the cx thread fixture _co_cxt.cyx to exit 255 (b)"
    printf '%s\n' "$L" | grep -qE 'src[/\\]main_cx\.cyr( \| \./[a-z0-9_]+)? > cycc_cx' ||
        fail "axis 2: the $h leg does not build its native cycc_cx from src/main_cx.cyr (c)"
    printf '%s\n' "$L" | grep -qE 'cycc_cx(\.exe)? < _co_cx\.cyr > _?nat\.cyx|_co_cx\.cyr \| \./cycc_cx > _?nat\.cyx' ||
        fail "axis 2: the $h leg does not compile _co_cx.cyr with its native cycc_cx (c)"
    printf '%s\n' "$L" | grep -E 'cxvm(\.exe)? < _?nat\.cyx' | grep -q '42' ||
        fail "axis 2: the $h leg does not run its cycc_cx output to exit 42 (c)"
done

echo "PASS: cross_os_legs_cx_parity ($_nh legs: $HOSTS — guest I/O, thread fixture, native cycc_cx round trip)"
