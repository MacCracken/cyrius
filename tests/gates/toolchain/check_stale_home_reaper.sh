#!/bin/sh
# tests/gates/toolchain/check_stale_home_reaper.sh — 6.6.6 (bite 27b)
#
# A KILLED CHECK RUN'S STAGED CYRIUS_HOME IS RECLAIMED — AND A LIVE RUN'S IS NOT.
#
# THE DEFECT. Since v6.6.4 scripts/check.sh stages a ~19 MB throwaway CYRIUS_HOME under
# $TMPDIR and removes it from its EXIT/INT/TERM trap; bite 25b fixed the one path that
# `exec`ed past that trap. Neither helps against SIGKILL — no trap runs at all — and a
# killed run leaks the whole tree for ever. Five of them (95 MB) were sitting in /tmp when
# this was written, the oldest three hours old, on a box where /tmp is RAM.
#
# ⚠ THE DANGEROUS HALF IS THE REAP, NOT THE LEAK. Several lanes run check.sh on this box at
# once, and a reaper that deletes a LIVE run's home destroys that run — a worse failure than
# the leak it fixes. So the rule is the same one cross-os-selfhost.sh's `_co_reap_stale`
# follows for its `_cyaud_*` dirs: reap by AGE and by OWNERSHIP, never by count. Every home
# carries `.owner` (the creating shell's PID, written as the FIRST thing after mktemp) and
# a home is reclaimed only when it is older than $CYRIUS_CHECK_REAP_MINS minutes AND that
# PID is gone.
#
# AXES
#   1  a stale home whose owner is DEAD is reaped
#   2  a stale home whose owner is ALIVE survives — with the age gate turned OFF, so the
#      ONLY thing keeping it is the ownership check
#   3  a fresh home survives the default threshold (the age gate alone is enough)
#   4  ⭐ a REAL second check.sh run, staging a REAL home, survives a reaper running
#      concurrently with the age gate off — and that same run's home is gone once it
#      finishes, by its own trap. This is the concurrency proof; axis 2 is its unit form.
#   5  anti-vacuous for axis 4: the same old home with `.owner` REMOVED is reaped under the
#      same settings. Without this, axis 4 would also pass if the age gate had quietly
#      stayed on and nothing was ever eligible.
#
# INDEPENDENT DERIVATION: every verdict is `[ -d "$home" ]` on the filesystem afterwards,
# never check.sh's "reaped N" line. The live owner in axis 2 is a process this gate started
# and can see; the live owner in axis 4 is a check.sh this gate started and whose home it
# located by listing $TMPDIR, not by reading check.sh's output.
#
# ⚠ The harness stubs scripts/install.sh (the stager — a real --refresh-only is a full
# toolchain pass and must never be pointed at a live store) and build/cyrius_check (a real
# run is the 13-minute suite). scripts/check.sh itself is the REAL file, copied.
#
# MUTATION PROOF (6.6.6, in a git-archive scratch tree, never the repo):
#   * the `_chk_reap_stale_homes` call removed -> 2 RED: axis 1 (the dead-owner home
#     survives) and axis 5 (so does the unowned one).
#   * the `_chk_home_is_owned` guard removed from the reap loop -> 4 RED across axes 1, 2b
#     and 4: the live unit home AND the live check.sh run's home are both deleted out from
#     under their owners.
#   * the `.owner` stamp removed from the staging path -> 2 RED, both on axis 4 (a real
#     run's home is unowned and is reaped); axes 1, 2b, 3 and 5 stay GREEN, so the stamp
#     and the guard are proven independently.
#   * the age gate disabled (every unowned home eligible) -> 1 RED: axis 3, a home created
#     seconds ago is destroyed.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp -d"; exit 1; }
LIVE_PID=""
_cleanup() {
    [ -n "$LIVE_PID" ] && kill "$LIVE_PID" 2>/dev/null
    rm -rf "$D"
}
trap _cleanup EXIT

FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

W="$D/w"
mkdir -p "$W/root/scripts" "$W/root/build" "$W/root/programs/checks" "$W/root/lib" \
         "$W/tmp" "$W/home"
cp "$ROOT/scripts/check.sh" "$W/root/scripts/check.sh"
cp VERSION "$W/root/"
: > "$W/root/lib/placeholder.cyr"
: > "$W/root/programs/checks/main.cyr"
printf '#!/bin/sh\nexit 0\n' > "$W/root/build/cycc"
chmod +x "$W/root/build/cycc"
printf '#!/bin/sh\nmkdir -p "$CYRIUS_HOME/bin"\nexit 0\n' > "$W/root/scripts/install.sh"
chmod +x "$W/root/scripts/install.sh"
# The stub driver: normally instant, and blocks on a sentinel file when the ENVIRONMENT
# says to, so this gate can hold ONE real check.sh run open at a known point (axis 4) while
# other runs of the same harness still finish instantly. Keying it on the sentinel file
# alone deadlocked: the reaper run that axis 4 fires also runs the driver, and it blocked
# on the same file (measured).
cat > "$W/root/build/cyrius_check" <<STUB
#!/bin/sh
if [ "\$1" = "--list-suites" ]; then printf 'alpha\n'; exit 0; fi
if [ "\${CHK_STUB_BLOCK:-}" = "1" ]; then
    echo "\$CYRIUS_HOME" > "$W/live.home"
    while [ -f "$W/block" ]; do sleep 0.2; done
fi
exit 0
STUB
chmod +x "$W/root/build/cyrius_check"
touch -d '2038-01-01' "$W/root/build/cyrius_check"

# Run the real check.sh in the harness. $1 = CYRIUS_CHECK_REAP_MINS, rest = argv.
_run() {
    _rm=$1
    shift
    RC=0
    ( cd "$W/root" && env -u CYRIUS_HOME HOME="$W/home" TMPDIR="$W/tmp" \
        CYRIUS_CHECK_REAP_MINS="$_rm" sh scripts/check.sh "$@" ) > "$W/out" 2>&1 || RC=$?
}

# A PID that is certainly gone: start something and reap it.
sh -c 'exit 0' &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null || true
# A PID that is certainly alive for the length of this gate.
sleep 120 >/dev/null 2>&1 &
LIVE_PID=$!

_mkhome() {  # $1 = suffix, $2 = owner pid (or "" for none), $3 = age in minutes
    _h="$W/tmp/cyrius-check-home.$1"
    mkdir -p "$_h/versions"
    [ -n "$2" ] && printf '%s\n' "$2" > "$_h/.owner"
    if [ "$3" != "0" ]; then
        touch -d "$3 minutes ago" "$_h"
    fi
    echo "$_h"
}

echo "axis 1/2/3: stale+dead is reaped, stale+alive and fresh are not"
H_DEAD=$(_mkhome dead "$DEAD_PID" 300)
H_LIVE=$(_mkhome live "$LIVE_PID" 300)
H_FRESH=$(_mkhome fresh "" 0)
# Default threshold (240 min): the two 300-minute homes are eligible by age, the fresh one
# is not. Ownership then decides between the two eligible ones.
_run 240 alpha
[ -d "$H_DEAD" ]  && _fail "a 5-hour-old home whose owner is dead was NOT reaped"
[ -d "$H_LIVE" ]  || _fail "a home owned by a LIVE process was reaped — a concurrent run would have been destroyed"
[ -d "$H_FRESH" ] || _fail "a home created seconds ago was reaped"

echo "axis 2b: with the age gate OFF, ownership alone still protects the live home"
_run 0 alpha
[ -d "$H_LIVE" ] || _fail "with CYRIUS_CHECK_REAP_MINS=0 the live-owner home was reaped — the ownership check is not what protects it"

echo "axis 5: with the age gate off and no owner, an old home IS reaped"
rm -f "$H_LIVE/.owner"
_run 0 alpha
[ -d "$H_LIVE" ] && _fail "an unowned home survived a reap with the age gate off — axis 2b is vacuous"

echo "axis 4: a REAL concurrent check.sh run's home survives a reaper"
: > "$W/block"
rm -f "$W/live.home"
( cd "$W/root" && env -u CYRIUS_HOME HOME="$W/home" TMPDIR="$W/tmp" \
    CYRIUS_CHECK_REAP_MINS=240 CHK_STUB_BLOCK=1 sh scripts/check.sh alpha ) > "$W/bg.out" 2>&1 </dev/null &
BG=$!
# Wait for that run to have staged and entered the driver.
_i=0
while [ ! -s "$W/live.home" ] && [ "$_i" -lt 100 ]; do
    sleep 0.1
    _i=$((_i + 1))
done
BGHOME=$(cat "$W/live.home" 2>/dev/null || true)
case "$BGHOME" in
    "$W/tmp/cyrius-check-home."*) : ;;
    *) _fail "the concurrent run staged no home under the harness TMPDIR (got '$BGHOME') — axis 4 is vacuous" ;;
esac
[ -d "$BGHOME" ] || _fail "the concurrent run's home does not exist while it is running"
# Age it past any threshold AND run a reaper with the age gate off: the ONLY thing that can
# save it now is its .owner stamp naming a process that is still alive.
if [ -n "$BGHOME" ] && [ -d "$BGHOME" ]; then
    touch -d '300 minutes ago' "$BGHOME"
    _run 0 alpha
    [ -d "$BGHOME" ] || _fail "a reaper deleted a LIVE check.sh run's staged CYRIUS_HOME"
    OWNED=$(cat "$BGHOME/.owner" 2>/dev/null || true)
    case "$OWNED" in
        ''|*[!0-9]*) _fail "the live run's home carries no usable .owner stamp ('$OWNED')" ;;
        *) kill -0 "$OWNED" 2>/dev/null || _fail ".owner=$OWNED is not a live process — the stamp is not the running check.sh" ;;
    esac
fi
# Let it finish; its own trap must take the home with it.
rm -f "$W/block"
wait "$BG" 2>/dev/null || true
[ -n "$BGHOME" ] && [ -d "$BGHOME" ] && _fail "the concurrent run finished and left its staged home behind"

echo ""
if [ "$FAILS" = "0" ]; then
    echo "PASS: stale staged CYRIUS_HOMEs are reaped, live ones are not"
    exit 0
fi
echo "FAILED: $FAILS assertion(s)"
exit 1
