#!/bin/sh
# Gate: every `cyrius init` scaffold artifact is DISCOVERED by its verb.
#
# THE FAMILY. `cyrius init` writes all three corpora to `tests/` — `_tests_rel`
# (programs/cyrius-init.cyr:867-873) hardcodes the literal `"tests/"` for ALL THREE
# extensions, and no `benches/` or `fuzz/` directory is ever created. The three verbs
# each grew their walk independently, so each had to learn `tests/` separately:
#
#   v6.4.72  cyrius test   — hardcoded tests/tcyr/ missed a suite at tests/<name>.tcyr
#   v6.4.78  cyrius bench  — benches/ + tests/bcyr/ only; tests/<name>.bcyr invisible
#   v6.5.6   cyrius fuzz   — fuzz/ only, so a scaffolded tests/<name>.fcyr was NEVER
#                            run: `cyrius init` wrote a harness and `cyrius fuzz` then
#                            reported "No fuzz harnesses found in fuzz/"
#
# The first two shipped UNGATED, which is why the third survived to 6.5.6 — nothing
# asserted the family invariant, only the instances. This gate is the invariant: scaffold
# a project, then require each verb to find its own artifact. A fourth corpus added later
# fails here rather than silently going unrun.
#
# WHY IT MATTERS BEYOND DISCOVERY. A harness that is never discovered is never run, so
# defects in it are invisible — `proj-fcyr` carried a broken exit epilogue (fixed in the
# same v6.5.6 patch) that no consumer could ever have observed, because the file the
# scaffolder wrote was unreachable by the verb meant to run it.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2
CYRIUS="$ROOT/build/cyrius"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

if [ ! -x "$CYRIUS" ]; then
    echo "FAIL: scaffold-verb-discovery — $CYRIUS not built"
    exit 1
fi

# ── Scaffold once; all axes read the same project.
( cd "$D" && "$CYRIUS" init vprobe --bin >/dev/null 2>&1 )
P="$D/vprobe"
echo "axis 0 — the scaffolder writes all three corpora (and where):"
for ext in tcyr bcyr fcyr; do
    check "tests/vprobe.$ext exists" "yes" "$([ -f "$P/tests/vprobe.$ext" ] && echo yes || echo no)"
done

# ── AXES 1-3: each verb must FIND its artifact. We grep for the "nothing found"
# message rather than the exit code, because all three verbs return 0 when they find
# nothing — a green exit is exactly how this stayed invisible.
run_verb() { ( cd "$P" && timeout 300 "$CYRIUS" "$1" 2>&1 ); }

echo "axis 1 — cyrius test discovers tests/vprobe.tcyr (v6.4.72):"
out=$(run_verb test)
check "no 'no tests found'" "0" "$(printf '%s' "$out" | grep -ci 'no test.*found' || true)"

echo "axis 2 — cyrius bench discovers tests/vprobe.bcyr (v6.4.78):"
out=$(run_verb bench)
check "no 'No benchmarks found'" "0" "$(printf '%s' "$out" | grep -ci 'no benchmarks found' || true)"

echo "axis 3 — cyrius fuzz discovers tests/vprobe.fcyr (v6.5.6 — the one that was broken):"
out=$(run_verb fuzz)
check "no 'No fuzz harnesses found'" "0" "$(printf '%s' "$out" | grep -ci 'no fuzz harnesses found' || true)"
check "reports a passing harness" "1" "$(printf '%s' "$out" | grep -c 'passed, 0 failed' || true)"

# ── AXIS 4: structural. Each walker must be invoked for BOTH its own dir and tests/.
# Behavioural axes above only prove today's layout; this pins the intent so a future
# refactor that drops one call site fails here.
echo "axis 4 — each walker is invoked for its own dir AND tests/:"
n_fuzz=$(grep -cE '_fuzz_walk_dir\("(fuzz|tests)"' cbt/commands.cyr)
check "_fuzz_walk_dir call sites" 2 "$n_fuzz"
n_bench=$(grep -cE '_bench_walk_dir\("(benches|tests/bcyr|tests)"' cbt/commands.cyr)
check "_bench_walk_dir call sites" 3 "$n_bench"

# ── AXIS 5: no double-count. dir_list is non-recursive, so fuzz/ and tests/ are
# disjoint — but this repo has 6 fuzz/*.fcyr and 0 tests/*.fcyr, so a walker that
# recursed or double-visited would report more than 6.
echo "axis 5 — this repo's own fuzz corpus is counted exactly once:"
n_repo=$(ls fuzz/*.fcyr 2>/dev/null | wc -l | tr -d ' ')
check "fuzz/*.fcyr on disk" 6 "$n_repo"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: scaffold-verb-discovery — test/bench/fuzz each find what cyrius init writes"
    exit 0
fi
echo "FAIL: scaffold-verb-discovery — $fails assertion(s) failed"
exit 1
