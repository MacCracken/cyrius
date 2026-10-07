#!/bin/sh
# Gate: `cyrius audit --internal=platform-check` runs EXACTLY release-gate step 4 on every host
# (6.6.20, CLN-05).
#
# THE DEFECT. scripts/release-gate.sh step 4 runs `cross-os-selfhost.sh "$H" "crossos"` for
# ecb ach cass pi — the self-host AND the platform libtest (tests/tcyr/crossos/ on the native
# compiler). The CLI's cross-OS verb (`_cross_os_selfhost`, cbt/commands.cyr) passed `crossos`
# to ach ONLY: pi and cass ran a bare self-host, and ecb an inline self-host + exit-42 sequence
# with no libtest — while the ach comment said the libtest ran "matching ecb/cass/pi". So the verb
# whose job is the pre-release platform check was weaker than the gate it mirrors, and said
# otherwise.
#
# A DRY RUN, NEVER A HOST. The verb runs in a stand-in root whose scripts/ are recorders
# (check.sh exits 0; cross-os-selfhost.sh, the tarball builders and cass-install-gate.sh log
# their arguments) with `ssh` and `scp` recorders FIRST on PATH and a throwaway HOME (no
# ~/.ssh/config, so a host alias resolves nowhere). The gate refuses to run the verb unless
# `ssh` resolves to its recorder.
#
# AXES
#   0  the expected calls are DERIVED from scripts/release-gate.sh — its `for H in …` host list
#      (floor: 4 hosts) and the selector it passes — never written down here
#   1  the verb hands every one of those hosts to cross-os-selfhost.sh with that selector, once,
#      and makes no other cross-os-selfhost.sh call
#   2  it reports a PASS line per host naming the crossos libtest, and exits 0 over a green run
#   3  ANTI-VACUOUS: the install pillars' ssh/scp really reached the recorders (so the PATH
#      interception that keeps this a dry run is what the verb used)
#
# MUTATION: the 6.6.19 verb (ach alone with `crossos`; pi and cass bare; ecb inline) fails axis 1.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=audit_platform_check_matches_release_gate
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
[ -x "$CC" ] || { echo "FAIL: $NAME — $CC not built"; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $NAME — needs timeout(1)"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

echo "axis 0 — release-gate step 4, derived from scripts/release-gate.sh:"
HOSTS=$(sed -n 's/^for H in \(.*\); do$/\1/p' "$ROOT/scripts/release-gate.sh" | head -1)
SEL=$(sed -n 's/.*cross-os-selfhost\.sh "\$H" "\([^"]*\)".*/\1/p' "$ROOT/scripts/release-gate.sh" | head -1)
nh=$(echo $HOSTS | wc -w | tr -d ' ')
check "the step-4 loop names at least 4 hosts ($HOSTS)" "yes" "$([ "$nh" -ge 4 ] && echo yes || echo no)"
check "it passes a libtest selector ($SEL)" "yes" "$([ -n "$SEL" ] && echo yes || echo no)"
EXPECT=$(for h in $HOSTS; do echo "$h $SEL"; done | sort)

B="$T/bin"; mkdir -p "$B"
( cd "$ROOT" && "$CC" < cbt/cyrius.cyr > "$B/cyrius" 2> "$T/build.err" ) || {
    echo "FAIL: $NAME — could not build cbt/cyrius.cyr"; sed -n '1,5p' "$T/build.err"; exit 1; }
cp "$CC" "$B/cycc"
chmod +x "$B/cyrius" "$B/cycc"

# The stand-in root: `./scripts/cyrius` is what makes the CLI use ./scripts (cbt/core.cyr).
R="$T/root"; mkdir -p "$R/scripts" "$T/hh" "$T/cyhome"
cp "$ROOT/VERSION" "$R/VERSION"
: > "$R/scripts/cyrius"
CO_LOG="$T/co.log"; NET_LOG="$T/net.log"; : > "$CO_LOG"; : > "$NET_LOG"
printf '#!/bin/sh\nexit 0\n' > "$R/scripts/check.sh"
printf '#!/bin/sh\necho "$*" >> "%s"\nexit 0\n' "$CO_LOG" > "$R/scripts/cross-os-selfhost.sh"
for s in build-macos-arm64-tarball.sh build-macos-x86-tarball.sh cass-install-gate.sh; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$s" "$NET_LOG" > "$R/scripts/$s"
done
F="$T/fake"; mkdir -p "$F"
for c in ssh scp; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$c" "$NET_LOG" > "$F/$c"
    chmod +x "$F/$c"
done
chmod +x "$R/scripts/"*.sh
P="$F:$PATH"
for c in ssh scp; do
    got=$(PATH="$P" command -v "$c")
    [ "$got" = "$F/$c" ] || { echo "FAIL: $NAME — '$c' resolves to $got, not the recorder; refusing to run a verb that would reach a real host"; exit 1; }
done

RC=0
( cd "$R" && env PATH="$P" HOME="$T/hh" CYRIUS_HOME="$T/cyhome" SSH_AUTH_SOCK= \
    timeout 300 "$B/cyrius" audit --internal=platform-check ) > "$T/o" 2>&1 || RC=$?

echo "axis 1 — every step-4 host goes to cross-os-selfhost.sh with '$SEL', and nothing else does:"
GOT=$(sort "$CO_LOG")
check "the cross-os-selfhost.sh calls == release-gate step 4" "$(echo $EXPECT)" "$(echo $GOT)"
for h in $HOSTS; do
    check "$h: exactly one '$h $SEL' call" 1 "$(grep -cx "$h $SEL" "$CO_LOG" || true)"
done

echo "axis 2 — the report:"
check "exit 0 over an all-green dry run" 0 "$RC"
check "one PASS line per host naming the crossos libtest" "$nh" "$(grep -c 'PASS: .* cycc self-host byte-identical + crossos libtest' "$T/o" || true)"

echo "axis 3 — anti-vacuous: the dry run's recorders were the ones used:"
check "the install pillars' ssh reached the recorder" "yes" "$(grep -q '^ssh ' "$NET_LOG" && echo yes || echo no)"
check "and their scp" "yes" "$(grep -q '^scp ' "$NET_LOG" && echo yes || echo no)"

if [ "$fails" = "0" ]; then
    echo "PASS: $NAME — audit --internal=platform-check runs release-gate step 4 on $(echo $HOSTS)"
    exit 0
fi
sed -n '1,40p' "$T/o"
echo "FAIL: $NAME — $fails assertion(s) failed"
exit 1
