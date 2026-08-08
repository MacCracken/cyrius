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
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
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

# ── AXIS 4: SUBFOLDERS. A corpus file at any depth must be found, and an explicit
# subfolder argument must be honoured. This is the intended contract and always was;
# `cyrius tests <dir>` has recursed since v6.0.62 and bench/fuzz were simply never
# brought along, so a benchmark under `benches/perf/` silently never ran while the
# command reported success. Top-level-only was a defect, not a design choice — do not
# "fix" this axis back to a flat scan.
echo "axis 4 — a corpus file in a SUBFOLDER is discovered by the bare verb:"
mkdir -p "$P/tests/unit" "$P/benches/perf" "$P/fuzz/deep"
cp "$P/tests/vprobe.tcyr" "$P/tests/unit/nested.tcyr"
cp "$P/tests/vprobe.bcyr" "$P/benches/perf/nested.bcyr"
cp "$P/tests/vprobe.fcyr" "$P/fuzz/deep/nested.fcyr"
rm -f "$P/tests/vprobe.bcyr" "$P/tests/vprobe.fcyr"
out=$(run_verb bench)
check "bench finds benches/perf/nested.bcyr" "1" "$(printf '%s' "$out" | grep -c 'perf/nested.bcyr' || true)"
out=$(run_verb fuzz)
check "fuzz finds fuzz/deep/nested.fcyr" "0" "$(printf '%s' "$out" | grep -ci 'no fuzz harnesses found' || true)"
out=$(run_verb tests)
# Both the scaffolded tests/vprobe.tcyr and the nested tests/unit/nested.tcyr must
# run, i.e. 2 passed. The string appears on more than one line, so test presence
# rather than an exact count.
check "tests finds tests/unit/nested.tcyr" "yes" \
    "$(printf '%s' "$out" | grep -q '2 passed' && echo yes || echo no)"

echo "axis 5 — an explicit SUBFOLDER argument is honoured (the callout form):"
for pair in "bench:benches/perf" "fuzz:fuzz/deep" "tests:tests/unit"; do
    v=${pair%%:*}; d=${pair##*:}
    rc=0; ( cd "$P" && timeout 300 "$CYRIUS" "$v" "$d" >/dev/null 2>&1 ) || rc=$?
    check "cyrius $v $d" 0 "$rc"
done

echo "axis 6 — an unusable argument is REFUSED, not silently ignored:"
for pair in "bench:no-such-dir" "fuzz:no-such.fcyr" "bench:tests"; do
    v=${pair%%:*}; a=${pair##*:}
    rc=0; ( cd "$P" && timeout 300 "$CYRIUS" "$v" "$a" >/dev/null 2>&1 ) || rc=$?
    check "cyrius $v $a exits non-zero" 1 "$rc"
done

# ── AXIS 7: no double-count. The walks are now RECURSIVE, so `tests/bcyr` must NOT
# also be walked explicitly — it lives under `tests/` and would be visited twice.
echo "axis 7 — recursion did not introduce a double-count:"
n_bench=$(grep -cE '_bench_walk_dir\("(benches|tests)"' cbt/commands.cyr)
check "_bench_walk_dir roots (benches + tests, NOT tests/bcyr)" 2 "$n_bench"
n_bcyr=$(grep -c '_bench_walk_dir("tests/bcyr"' cbt/commands.cyr || true)
check "no explicit tests/bcyr walk" 0 "$n_bcyr"
n_repo=$(ls fuzz/*.fcyr 2>/dev/null | wc -l | tr -d ' ')
check "fuzz/*.fcyr on disk" 6 "$n_repo"


# ── v6.5.8: ARGUMENT HYGIENE ACROSS THE VERB SURFACE.
# A sweep of all 17 verbs with a bogus target found FIVE that silently ignored it and
# exited 0: coverage, doc, audit, vet and deny. The worst was `doc`, which printed NOTHING
# and returned success — empty output from a doc generator is indistinguishable from "this
# file has no documentation", so a mistyped path read as a finding about the code rather
# than a user error. Same family as the `bench` fail-open fixed at v6.5.7 and the
# `capacity` green-placebo at v6.4.73: a tool that accepts an argument it does not act on
# is worse than one that rejects it, because the output looks like an answer to the
# question that was asked.
#
# ⚠ Exit codes are captured WITHOUT a pipe. `cmd | tail` yields tail's status, not the
# CLI's — that mistake made an earlier run of this very sweep report rc=0 for all 17 verbs
# and conclude, wrongly, that nothing was broken.
echo "verb argument hygiene — a bogus target is rejected, never absorbed:"
CYB="$ROOT/build/cyrius"
VD=$(mktemp -d)
( cd "$VD" && printf '[package]\nname = "vh"\nversion = "0.1.0"\n' > cyrius.cyml )
for v in doc vet deny audit coverage; do
    ( cd "$VD" && timeout 30 "$CYB" "$v" __no_such_target_xyz__ > vh.out 2>&1 )
    vrc=$?
    check "$v rejects a bogus target" 1 "$([ "$vrc" -ne 0 ] && echo 1 || echo 0)"
    check "$v says error:" 1 "$(grep -c 'error:' "$VD/vh.out" || true)"
done
# The good paths must still work — a rejection that also breaks valid invocations is not a fix.
( cd "$ROOT" && timeout 60 "$CYB" doc lib/fmt.cyr > "$VD/ok.out" 2>&1 )
check "doc on a real file still succeeds" 1 "$([ -s "$VD/ok.out" ] && echo 1 || echo 0)"
rm -rf "$VD"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: scaffold-verb-discovery — test/bench/fuzz each find what cyrius init writes"
    exit 0
fi
echo "FAIL: scaffold-verb-discovery — $fails assertion(s) failed"
exit 1
