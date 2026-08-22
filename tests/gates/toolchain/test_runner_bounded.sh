#!/bin/sh
# tests/gates/toolchain/test_runner_bounded.sh — v6.5.19
#
# `cyrius test` never hangs on a spinning fixture, and never leaves a child behind
# when the runner dies.
#
# THE INCIDENT THIS EXISTS FOR. `run_binary` (cbt/build.cyr) was fork + execve +
# BLOCKING waitpid, with no deadline and nothing tying the child's lifetime to the
# runner's. So:
#   * a .tcyr that spins hangs the suite forever — the only exit is to kill the
#     runner; and
#   * killing the runner REPARENTS the child to PID 1, where it keeps burning a
#     core indefinitely.
# The v6.5.19 non-regression verifier found 19 such orphans, the oldest at 1h42m,
# together ~13 of 16 cores (load 20.66) — and they flipped the release gate's
# `alloc_via_no_plumbing` 14 ns tripwire RED. TWO separate implementers wrote that
# RED off as "environmental load" without anyone asking what the environment was
# doing. A release gate whose perf tripwires can be flipped red by its own leaked
# children is not a gate, so the runner is now bounded on both axes.
#
# ⭐ AXIS 2 IS THE ONE THAT MATTERS, AND IT IS THE ONE A TIMEOUT ALONE DOES NOT BUY.
# A parent that is SIGKILLed runs no cleanup, ever — so no amount of parent-side
# tidy-up can reach the child. The kernel has to do it: the child sets
# PR_SET_PDEATHSIG(SIGKILL) between fork and execve (Linux). Axis 2 kills the runner
# with SIGKILL specifically, because SIGTERM would let any parent-side handler take
# the credit.
#
# ANTI-VACUOUS: axis 0 proves a NORMAL test still passes and still exits 0 (a runner
# that killed everything would satisfy axes 1 and 2 trivially), and axis 1 checks the
# elapsed time against BOTH a floor and a ceiling — a runner that failed instantly,
# or one that never spawned the child at all, is not "bounded", it is broken.
#
# ⚠ FOUR OF THIS GATE'S OWN ASSERTIONS SHIPPED BROKEN, and the header claimed a
# mutation proof that had never been run against them. Recorded because each is a
# separate reusable trap, and three of the four FAILED OPEN rather than closed:
#   1. The orphan row grepped `ps -eo args=` for a bare `test_bin`, so it counted its
#      OWN grep command line: 1 with nothing running, and the row could never pass.
#      Fixed with the `[t]est_bin` bracket idiom. GREP OVER `ps` ALWAYS SEES ITSELF.
#   2. …and its pattern (`$T/../cyrius-.*test_bin`) could not have matched the real
#      argv (`/tmp/cyrius-<pid>/test_bin`) even so — it was unpassable AND blind.
#   3. The axis-0 "ordinary test still passes" fixture was `fn main() { return 0; }`
#      with NO assertions, so the runner printed no summary at all and the row it
#      anchors could never match. A .tcyr needs real assertions + `assert_summary()`.
#   4. Axis 3 counted `run_binary_timed` MENTIONS inside cmd_test, and the body
#      contains a comment naming it — 2, not 1, RED against correct code. Count call
#      sites (`name(`) with `#` lines stripped.
#   5. The hermetic CYRIUS_HOME had bin/ but no lib/, so axis 4's build died with
#      `cannot find cyrius stdlib` and its real assertion passed VACUOUSLY (no build,
#      no cpp_ file to leak). Only the premise row caught it — which is what premise
#      rows are for.
#
# MUTATION PROOF (all re-run at v6.5.19, RED then GREEN, against these assertions):
#   * `sys_kill(pid, 9)` -> `sys_kill(pid, 0)` + blocking wait -> `WNOHANG` in
#     `run_binary_timed` -> axis 1b RED (max live children 2 vs 1), every other axis
#     GREEN — including the single-file orphan row, which is precisely why axis 1b
#     had to be written against a multi-file suite. See axis 1b's own note.
#   * `run_binary_timed(tmpbin, _run_timeout_ms())` -> `run_binary(tmpbin)` in
#     cmd_test (cbt/commands.cyr) -> axis 1 RED (the runner hangs until the harness
#     `timeout` shoots it; elapsed pins at the ceiling) and axis 3 RED, axis 0 green.
#   * delete `sys_prctl(1, 9, 0, 0, 0)` + the getppid re-check from the child arm of
#     `run_binary_timed` -> axis 2 RED. Measured directly, outside this gate, on the
#     two builds: no-PDEATHSIG left `child 1985510 STILL ALIVE (reparented to
#     PPID=1)`; with PDEATHSIG `child 1985627 died too`.
#   * make `_cbt_env_int` return its default for a well-formed value -> axis 1 RED
#     (the 5 s override stops applying and the elapsed check hits the ceiling).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CY="$ROOT/build/cyrius"
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

for b in cyrius cycc; do
    if [ ! -x "$ROOT/build/$b" ]; then
        echo "FAIL: test-runner-bounded — build/$b not built"
        exit 1
    fi
done

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/bin"
cp "$ROOT/build/cycc" "$T/home/bin/cycc"
chmod +x "$T/home/bin/cycc"
# The hermetic home needs a lib/ as well as a bin/: `_auto_deps()` resolves the
# manifest's [deps].stdlib out of CYRIUS_HOME/lib, and a home with only bin/ fails
# the whole build with `cannot find cyrius stdlib`. That is not a neutral omission —
# it silently turned axis 4 into a vacuous pass (no build ⇒ no cpp_ file to leak),
# which is exactly what axis 4's premise row exists to catch. $T/lib is the same
# copy, for the fixtures' own `include "lib/…"` lines (resolved against the entry
# file's directory via the #@incdir marker).
cp -R "$ROOT/lib" "$T/home/lib"
cp -R "$ROOT/lib" "$T/lib"
CYRIUS_HOME="$T/home"
export CYRIUS_HOME

# The set of spinning test children currently on the box, by PID.
#   * `[t]est_bin` — the bracket idiom, and it is LOAD-BEARING: with a plain
#     `test_bin` pattern the `grep` matches its OWN command line in `ps -eo args=`
#     output, so the count is 1 when nothing is running at all and the row can
#     never pass. That is how this check shipped, and it made the assertion both
#     unpassable and incapable of seeing a real orphan.
#   * SETS, not counts: the row below compares before-vs-after, so an unrelated
#     stray from another session cannot flip this gate red on a shared box.
orphan_pids() {
    ps -eo pid=,args= 2>/dev/null | grep '/cyrius-[0-9]*/[t]est_bin' | awk '{print $1}' | sort
}

# A fixture that never terminates. `while (1 == 1)` with a live accumulator so no
# optimiser can fold it away, and no syscall in the loop so it is a genuine spin —
# the exact shape that produced the 1h42m orphans.
printf 'fn spin() { var i = 0; while (1 == 1) { i = i + 1; } return i; }\nfn main() { return spin(); }\nvar r = main();\n' > "$T/hang.tcyr"
# And a fixture that finishes immediately, for the anti-vacuous rows. It has to be a
# REAL .tcyr — assertions plus the closing `assert_summary()`. A bare
# `fn main() { return 0; }` runs and exits 0 but prints no summary at all, so the
# "reported as passed" row below could never match and axis 0 asserted nothing about
# the runner still working.
cat > "$T/fine.tcyr" <<'FINE'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/assert.cyr"

fn main(): i64 {
    var a = assert_eq(2 + 2, 4, "the runner still runs real assertions");
    return 0;
}
var m = main();
var r = assert_summary();
FINE

# ── AXIS 0 — ANTI-VACUOUS. A well-behaved test still passes, exits 0, and is not
# collateral damage of the deadline.
echo "axis 0 — ANTI-VACUOUS: an ordinary test still passes and exits 0:"
rc=0
( cd "$T" && CYRIUS_TEST_TIMEOUT=60 timeout 300 "$CY" test "$T/fine.tcyr" > "$T/f.out" 2> "$T/f.err" ) || rc=$?
check "exit" 0 "$rc"
check "reported as passed" 1 "$(grep -c '1 passed, 0 failed' "$T/f.out" || true)"
check "not reported as a timeout" 0 "$(grep -c 'timed out' "$T/f.err" || true)"

# ── AXIS 1 — ⭐ a hanging test is KILLED, and the suite carries on.
echo "axis 1 — ⭐ a spinning test is killed at the deadline, not waited on forever:"
orph_pre=$(orphan_pids)
t0=$(date +%s)
rc=0
# The harness `timeout 120` is the backstop, NOT the mechanism: if it is what stops
# the run, the elapsed check below fails. CYRIUS_TEST_TIMEOUT=5 is the mechanism.
( cd "$T" && CYRIUS_TEST_TIMEOUT=5 timeout 120 "$CY" test "$T/hang.tcyr" > "$T/h.out" 2> "$T/h.err" ) || rc=$?
t1=$(date +%s)
el=$((t1 - t0))
check "the runner returns at all (did not need the harness backstop)" "yes" \
    "$([ "$rc" != 124 ] && echo yes || echo no)"
check "and it reports a FAILURE, not a pass" "yes" \
    "$([ "$rc" != 0 ] && echo yes || echo no)"
check "names the timeout rather than leaving a bare nonzero code" 1 \
    "$(grep -c 'timed out after 5s' "$T/h.err" || true)"
check "tells the user the override knob" 1 \
    "$(grep -c 'CYRIUS_TEST_TIMEOUT' "$T/h.err" || true)"
# FLOOR and CEILING. The floor rejects a runner that never really ran the child;
# the ceiling rejects one that only stopped because the harness shot it.
check "elapsed >= 5s (the deadline was honoured, not short-circuited)" "yes" \
    "$([ "$el" -ge 5 ] && echo yes || echo no)"
check "elapsed < 60s (killed by the deadline, not by the harness backstop)" "yes" \
    "$([ "$el" -lt 60 ] && echo yes || echo no)"
# Plain files, not process substitution: this script is #!/bin/sh and `<(…)` is a
# bashism that dash does not parse. `comm -13` = "in after, not in before".
sleep 1
printf '%s\n' "$orph_pre"  > "$T/orph.pre"
orphan_pids                > "$T/orph.post"
orph_new=$(comm -13 "$T/orph.pre" "$T/orph.post" | grep -c . || true)
check "nothing survives the single-file run (weak: PDEATHSIG alone would satisfy it)" 0 "$orph_new"

# ── AXIS 1b — ⭐ THE ROW THE WHOLE INCIDENT WAS ABOUT: the deadline must KILL the
# child, not merely STOP WAITING for it.
#
# ⚠ WHY THIS CANNOT BE MEASURED ON A SINGLE-FILE RUN, which is how it was written
# first and why that version was VACUOUS. After a one-file `cyrius test` hits the
# deadline the runner EXITS almost immediately — and the child carries
# PR_SET_PDEATHSIG(SIGKILL), so the kernel reaps it on the parent's exit no matter
# what the deadline did. Measured: with `sys_kill(pid, 9)` mutated to `sys_kill(pid,
# 0)` (a no-op existence probe) plus a non-blocking wait, the single-file axis stayed
# fully GREEN — the leak is real but invisible, because PDEATHSIG covers for it.
#
# The leak is only observable while the runner is STILL ALIVE, i.e. during a
# multi-file suite — which is also the shape that actually burned the box: a child
# abandoned by test 5 keeps a core busy through tests 6..269. So: two spinning
# fixtures, and sample the live child count throughout. Correct runner = never more
# than the ONE it is currently running. Two hanging fixtures rather than a hang plus
# a slow test makes this order-independent — whichever the runner picks first, the
# second one's deadline is the observation window.
# MUTATION-PROVEN at v6.5.19: pristine max = 1, `sys_kill(pid, 9)` -> `sys_kill(pid,
# 0)` + `WNOHANG` gives max = 2.
echo "axis 1b — ⭐ the deadline KILLS the child, it does not merely abandon it:"
mkdir -p "$T/suite"
for n in hang1 hang2; do cp "$T/hang.tcyr" "$T/suite/$n.tcyr"; done
orphan_pids > "$T/suite.pre"
( cd "$T/suite" && CYRIUS_TEST_TIMEOUT=5 timeout 300 "$CY" tests "$T/suite" > "$T/s.out" 2> "$T/s.err" ) &
suite_pid=$!
maxlive=0
while kill -0 "$suite_pid" 2> /dev/null; do
    orphan_pids > "$T/suite.now"
    live=$(comm -13 "$T/suite.pre" "$T/suite.now" | grep -c . || true)
    [ "$live" -gt "$maxlive" ] && maxlive=$live
    sleep 0.5
done
wait "$suite_pid" 2> /dev/null || true
check "premise: BOTH hanging fixtures really ran and hit the deadline" 2 \
    "$(grep -c 'timed out after 5s' "$T/s.err" || true)"
check "never more than the one child it is currently running" 1 "$maxlive"
if [ "$maxlive" -gt 1 ]; then
    echo "        $maxlive test children alive at once — a timed-out child kept running"
    echo "        while the suite moved on. The deadline is abandoning, not killing:"
    echo "        check the sys_kill(pid, 9) in run_binary_timed (cbt/build.cyr)."
fi

# ── AXIS 2 — ⭐ THE ORPHAN. SIGKILL the runner mid-test; the child must die with it.
# SIGKILL deliberately: a SIGTERM could be caught by a parent-side handler, and this
# axis is about what survives when the parent gets no chance to do anything at all.
echo "axis 2 — ⭐ SIGKILLing the runner does not leave the child running:"
CYRIUS_TEST_TIMEOUT=0 "$CY" test "$T/hang.tcyr" > "$T/o.out" 2> "$T/o.err" &
runner=$!
child=""
i=0
while [ "$i" -lt 600 ]; do
    child=$(ps -eo pid=,ppid=,args= 2>/dev/null | awk -v r="$runner" '$2==r && $0 ~ /test_bin/ {print $1}' | head -1)
    [ -n "$child" ] && break
    sleep 0.1
    i=$((i + 1))
done
check "premise: the runner really did spawn a test child" "yes" \
    "$([ -n "$child" ] && echo yes || echo no)"
if [ -n "$child" ]; then
    kill -9 "$runner" 2>/dev/null
    alive=yes
    j=0
    while [ "$j" -lt 100 ]; do
        if ps -p "$child" > /dev/null 2>&1; then sleep 0.1; j=$((j + 1)); else alive=no; break; fi
    done
    check "the child dies with the runner (no PPID=1 orphan)" "no" "$alive"
    if [ "$alive" = "yes" ]; then
        echo "        child $child survived, reparented to PPID=$(ps -o ppid= -p "$child" 2>/dev/null | tr -d ' ')"
        echo "        → PR_SET_PDEATHSIG is missing from run_binary_timed's child arm"
        echo "          (cbt/build.cyr). A timeout alone cannot fix this: a SIGKILLed"
        echo "          parent runs no cleanup, so the kernel has to do it."
        kill -9 "$child" 2>/dev/null
    fi
else
    kill -9 "$runner" 2>/dev/null
fi
wait 2>/dev/null || true

# ── AXIS 3 — `cyrius run` is NOT deadlined. A user running a server through the CLI
# must not be shot at 5 minutes; only the batch verbs carry a deadline. Asserted on
# the source, since waiting out a 300 s default to prove a negative is not a test.
echo "axis 3 — the deadline is applied to the batch verbs and NOT to 'cyrius run':"
# ⚠ COUNT CALL SITES, NOT MENTIONS. These rows grep a function body for a name, and
# a body contains PROSE as well as code: cmd_test carries a comment reading "See
# `run_binary_timed` in cbt/build.cyr for both halves", which made the count 2 and the
# row RED against a perfectly correct cmd_test. Strip whole-line `#` comments first,
# and require the open paren so only a real call counts.
calls_in() {   # $1 = fn name, $2 = symbol to count
    awk -v f="^fn $1\\\\(" '$0 ~ f,/^}/' "$ROOT/cbt/commands.cyr" \
        | sed 's/^[[:space:]]*#.*$//' | grep -c "$2(" || true
}
check "cmd_run does not deadline its child" 0 "$(calls_in cmd_run run_binary_timed)"
check "cmd_run does still run one" 1 "$(calls_in cmd_run run_binary)"
for f in cmd_test _fuzz_run_one _bench_run_one; do
    check "$f deadlines its child" 1 "$(calls_in "$f" run_binary_timed)"
done

# ── AXIS 4 — the preprocessed source is not left on disk. Found while fixing the
# above: `_materialize_source` writes <tmpdir>/cpp_<pid> and NOTHING ever removed it,
# one per compiling CLI invocation, forever. Measured on the maintainer's box before
# the fix: 21,289 leftover /tmp/cyrius-* directories holding 2.8 GB.
echo "axis 4 — a compiling run does not leave its preprocessed source behind:"
mkdir -p "$T/pj/src"
printf '[package]\nname = "pj"\nversion = "0.1.0"\n\n[deps]\nstdlib = ["syscalls","alloc","string","io"]\n' > "$T/pj/cyrius.cyml"
printf 'fn main() { return 0; }\nvar r = main();\n' > "$T/pj/src/main.cyr"
# ⚠ v6.5.34 — SCOPE THIS TO THE DIRECTORY THIS BUILD CREATES. The original scanned the
# three globally-newest /tmp/cyrius-* dirs, which made the axis **flaky by construction and
# self-inflicted**: AXIS 1 ABOVE DELIBERATELY SIGKILLS A RUNNER, and — as this gate's own
# header explains — a SIGKILLed parent runs no cleanup, ever, so it leaves exactly a
# `cpp_<pid>` + `test_bin.tmp.<pid>` pair behind. Whether that debris was still inside the
# global top-3 when axis 4 ran depended on how many unrelated cyrius processes had started
# in between, so the gate failed inside a full `check.sh` run and PASSED when run on its own.
# Observed at v6.5.34: `check.sh` red on `/tmp/cyrius-828621`, the same gate green standalone
# minutes later, with no code difference. Diff the directory listing across the build instead.
ls -d /tmp/cyrius-* 2>/dev/null | sort > "$T/dirs_before"
( cd "$T/pj" && timeout 300 "$CY" build src/main.cyr "$T/pj/out" > "$T/pj.out" 2> "$T/pj.err" ) || true
check "premise: the build really did use the manifest prepend" 1 \
    "$([ -f "$T/pj/out" ] && echo 1 || echo 0)"
ls -d /tmp/cyrius-* 2>/dev/null | sort > "$T/dirs_after"
leftover=0
newdirs=$(comm -13 "$T/dirs_before" "$T/dirs_after")
for d in $newdirs; do
    n=$(ls -A "$d" 2>/dev/null | grep -c '^cpp_' || true)
    leftover=$((leftover + n))
done
# ANTI-VACUOUS: if the build created no temp dir at all there is nothing to leak and the
# check would pass for the wrong reason — the exact failure mode the header records for the
# hermetic-CYRIUS_HOME bug that made an earlier axis vacuous.
check "premise: the build created a temp dir to inspect" 1 \
    "$([ -n "$newdirs" ] && echo 1 || echo 0)"
check "no cpp_* preprocessed source left by THIS build" 0 "$leftover"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: test-runner-bounded — hanging tests are killed, and no child outlives the runner"
    exit 0
fi
echo "FAIL: test-runner-bounded — $fails assertion(s) failed"
exit 1
