#!/bin/sh
# Gate: two check.sh selectors started in ONE worktree both survive rebuilding the driver (6.6.20).
#
# scripts/check.sh rebuilds build/cyrius_check when any suite or lib source is newer, by compiling
# into a side file and renaming it into place. The side file was ONE fixed name,
# `build/cyrius_check.new`, so two selectors started together in the same tree both compiled into
# it: the second's `>` truncated the first's half-written binary, the first renamed the file away,
# and the second's `chmod +x …new` then failed under `set -e` — a red run caused by the other run,
# not by the tree. Each run now compiles into `…new.<pid>`; the final rename stays shared (it is
# atomic, and both runs build the same sources).
#
# The harness is check_stale_home_reaper.sh's: a scratch root holding the REAL scripts/check.sh,
# a stub scripts/install.sh, and a stub build/cycc that writes the stub driver SLOWLY (2 s between
# its two halves), so run B's compile deterministically overlaps run A's. Axes:
#   1  both runs exit 0;
#   2  the installed driver is the complete one (both halves);
#   3  no per-run side file is left in build/.
# Anti-vacuous: run B's output must show it really started while A was still compiling — the
# stub logs each compile's start and end, and B's start must fall inside A's.
#
# Mutation ledger (measured 6.6.20, 3 of 3 runs): check.sh's 6.6.19 fixed `.new` name → axis 1 red
# twice: run B exits 1 ("chmod: cannot access '…/build/cyrius_check.new'"), and run A exits 2 — it
# resolved its selector against B's half-written driver.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: check_concurrent_selectors_one_tree: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
APID=""
_cleanup() { [ -n "$APID" ] && kill "$APID" 2>/dev/null; rm -rf "$D"; }
trap _cleanup EXIT
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

W="$D/w"
mkdir -p "$W/root/scripts" "$W/root/build" "$W/root/programs/checks" "$W/root/lib" "$W/tmp" "$W/home"
cp "$ROOT/scripts/check.sh" "$W/root/scripts/check.sh"
cp VERSION "$W/root/"
: > "$W/root/lib/placeholder.cyr"
: > "$W/root/programs/checks/main.cyr"
printf '#!/bin/sh\nmkdir -p "$CYRIUS_HOME/bin"\nexit 0\n' > "$W/root/scripts/install.sh"
chmod +x "$W/root/scripts/install.sh"
# The stub compiler: emits a stub driver in two halves, 2 s apart, and logs start/end.
cat > "$W/root/build/cycc" <<STUB
#!/bin/sh
cat > /dev/null
echo "start \$\$ \$(date +%s.%N)" >> "$W/cc.log"
printf '#!/bin/sh\nif [ "\$1" = "--list-suites" ]; then printf "alpha\\\\n"; exit 0; fi\n'
sleep 2
printf '# second-half\nexit 0\n'
echo "end \$\$ \$(date +%s.%N)" >> "$W/cc.log"
STUB
chmod +x "$W/root/build/cycc"
: > "$W/cc.log"

_runsel() { # <out file>
    ( cd "$W/root" && env -u CYRIUS_HOME HOME="$W/home" TMPDIR="$W/tmp" sh scripts/check.sh alpha ) > "$1" 2>&1
}
echo "axis 1-3: two selectors in one tree, both rebuilding the driver"
rm -f "$W/root/build/cyrius_check"
ARC=0; BRC=0
_runsel "$W/a.out" &
APID=$!
sleep 0.4
_runsel "$W/b.out" || BRC=$?
wait "$APID" || ARC=$?
APID=""

# Anti-vacuous: two compiles ran, and B's started before A's ended.
NST=$(grep -c '^start ' "$W/cc.log" || true)
[ "$NST" = 2 ] || _fail "premise: expected both runs to rebuild the driver, the stub compiler ran $NST time(s)"
A_END=$(sed -n 's/^end [0-9]* //p' "$W/cc.log" | head -1)
B_START=$(sed -n 's/^start [0-9]* //p' "$W/cc.log" | sed -n 2p)
if [ -n "$A_END" ] && [ -n "$B_START" ]; then
    awk -v s="$B_START" -v e="$A_END" 'BEGIN { exit !(s < e) }' ||
        _fail "premise: run B's compile started after run A's ended — the two builds did not overlap"
fi
[ "$ARC" = 0 ] || _fail "axis 1: run A exited $ARC: $(tail -3 "$W/a.out")"
[ "$BRC" = 0 ] || _fail "axis 1: run B exited $BRC: $(tail -3 "$W/b.out")"
grep -q '^# second-half$' "$W/root/build/cyrius_check" 2>/dev/null ||
    _fail "axis 2: the installed build/cyrius_check is not the complete driver"
LEFT=$(ls -A "$W/root/build" | grep -E '^cyrius_check\.' || true)
[ -z "$LEFT" ] || _fail "axis 3: side files left in build/: $LEFT"

if [ "$FAILS" = 0 ]; then
    echo "PASS: check_concurrent_selectors_one_tree (two overlapping driver rebuilds in one tree: both runs green, the complete driver installed, no side files left)"
    exit 0
fi
echo "FAIL: check_concurrent_selectors_one_tree — $FAILS assertion(s)"
exit 1
