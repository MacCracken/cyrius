#!/bin/sh
# tests/gates/toolchain/check_driver_bounded.sh — 6.6.6 (bite 8c)
#
# The CHECK DRIVER's children are bounded, and none of them outlives the runner.
#
# THE INCIDENT. `check.sh` runs every .tcyr through the check binary, which reaches
# `_tcyr_compile_and_run` -> `_exec_capture_clean` -> `regression_exec_capture_status`
# (lib/regression.cyr). That was fork + execve + BLOCKING `sys_waitpid(pid, &st, 0)`,
# with no deadline and nothing tying the child's lifetime to the runner's. So a .tcyr
# that spins hung check.sh FOREVER — measured in this release at ~5 minutes before a
# human killed it, with no output and no verdict — and killing the runner REPARENTED the
# test to PID 1, where it kept burning a core. Every other fork site in the driver and in
# lib/regression.cyr had the same shape: 11 in the lib, 19 functions across
# programs/checks/.
#
# ⭐ THIS IS THE SAME DEFECT `tests/gates/toolchain/test_runner_bounded.sh` HAS PINNED FOR
# THE `cyrius test` RUNNER SINCE v6.5.19. That gate's header explains why the second half
# is the one that matters: a SIGKILLed parent runs no cleanup, ever, so no parent-side
# tidy-up can reach the child — the kernel has to do it, via PR_SET_PDEATHSIG(SIGKILL) set
# between fork and execve. The check driver simply never got the same treatment, which is
# why this gate exists rather than an extra axis over there: different runner, different
# code path, and the whole point is that fixing one told us nothing about the other.
#
# ANTI-VACUOUS: axis 0 proves an ORDINARY fixture still runs, still returns its real exit
# code and is NOT reported as a timeout — a wait that killed everything immediately would
# satisfy axes 1 and 2 trivially. Axis 1 checks elapsed time against BOTH a floor and a
# ceiling: a runner that gave up instantly, or one that only stopped because the harness
# `timeout` shot it, is not "bounded", it is broken.
#
# MUTATION PROOF (run at 6.6.6, in a scratch copy of the tree, never in the repo):
#   * lib/regression.cyr reverted to its HEAD~ (blocking-wait) version, everything else
#     current -> axis 1 RED (the harness never returns; the 60 s backstop fires, exit 124
#     instead of 150) and axis 2 RED (`child NNN STILL ALIVE, reparented to PPID=1`).
#     Axis 0 stays GREEN, which is the point of having it.
#   * `sys_prctl(1, 9, 0, 0, 0)` + the getppid re-check deleted from
#     `_regression_child_guard`, deadline kept -> axis 2 RED alone, axes 0/1 GREEN. This
#     is the split the v6.5.19 incident is about: a deadline does not buy the orphan.
#   * the deadline kept but `sys_kill(pid, 9)` in `_regression_wait_deadline` changed to
#     the no-op probe `sys_kill(pid, 0)` with a non-blocking reap -> axis 1b RED, every
#     other axis GREEN. ⚠ MEASURED, and the first cut of this gate had NO axis 1b and went
#     fully green on that mutant: after a single-child run the harness exits immediately
#     and PDEATHSIG reaps the abandoned child for it, so the leak is real and invisible.
#     That is the same vacuity test_runner_bounded.sh records for its own single-file arm,
#     and it is why axis 1b runs TWO children.
#   * axis 3's census with the fix in place -> 0 blocking waits; with lib/regression.cyr
#     reverted -> 11.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

[ -x "$ROOT/build/cycc" ] || { echo "FAIL: check_driver_bounded — build/cycc not built"; exit 1; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: check_driver_bounded: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

# ── fixtures ────────────────────────────────────────────────────────────────────────
# A fixture that never terminates: a live accumulator so nothing can fold it away, and no
# syscall in the loop so it is a genuine spin — the shape that produced the hang.
printf 'fn spin(): i64 { var i = 0; while (1 == 1) { i = i + 1; } return i; }\nfn main(): i64 { return spin(); }\nvar r = main();\nsyscall(60, r);\n' > "$T/spin.cyr"
# And one that finishes immediately with a DISTINCTIVE exit code, for the anti-vacuous row.
printf 'fn main(): i64 { var w = syscall(1, 1, "driver-fixture-ran\\n", 19); return 7; }\nvar r = main();\nsyscall(60, r);\n' > "$T/fine.cyr"
for f in spin fine; do
    if ! "$ROOT/build/cycc" < "$T/$f.cyr" > "$T/$f" 2> "$T/$f.err"; then
        echo "FAIL: check_driver_bounded — the $f fixture did not compile:"; cat "$T/$f.err"; exit 1
    fi
    [ -s "$T/$f" ] || { echo "FAIL: check_driver_bounded — the $f fixture compiled to an EMPTY binary"; exit 1; }
    chmod +x "$T/$f"
done

# ── the harness ─────────────────────────────────────────────────────────────────────
# It drives the EXACT entry point the check driver uses for every .tcyr
# (`regression_exec_capture_status`), and reports the outcome as its own exit code:
#   150 = the module's -2 TIMEOUT code, 151 = -1 (fork/exec failure), otherwise the
#   child's own exit code. Asserting through the real verb is the point — a gate that
#   re-implemented the wait would share nothing with the code it is checking.
cat > "$T/harness.cyr" <<'HARNESS'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/args.cyr"
include "lib/flags.cyr"
include "lib/syscalls.cyr"
include "lib/fs.cyr"
include "lib/process.cyr"
include "lib/net.cyr"
include "lib/regression.cyr"

var HARNESS_ENVP[16];

fn main(): i64 {
    args_init();
    var bin = argv(1);
    if (bin == 0) { return 2; }
    store64(&HARNESS_ENVP, 0);
    var st[16];
    var buf = alloc(65536);
    var n = regression_exec_capture_status(bin, buf, 65536, &HARNESS_ENVP, &st);
    # A SECOND child, run after the first, so the runner is still alive during the
    # second one's deadline — that is the only window in which an ABANDONED first
    # child is observable (axis 1b).
    var bin2 = argv(2);
    if (bin2 != 0) {
        var st2[16];
        var n2 = regression_exec_capture_status(bin2, buf, 65536, &HARNESS_ENVP, &st2);
    }
    var code = load64(&st);
    if (code == 0 - 2) { return 150; }
    if (code == 0 - 1) { return 151; }
    if (code < 0) { return 152; }
    if (code > 127) { return 153; }
    return code;
}
var r = main();
syscall(60, r);
HARNESS
if ! "$ROOT/build/cycc" < "$T/harness.cyr" > "$T/harness" 2> "$T/harness.err"; then
    echo "FAIL: check_driver_bounded — the harness did not compile:"; cat "$T/harness.err"; exit 1
fi
[ -s "$T/harness" ] || { echo "FAIL: check_driver_bounded — the harness compiled to an EMPTY binary"; exit 1; }
chmod +x "$T/harness"

# ── AXIS 0 — ANTI-VACUOUS: an ordinary child still runs and still reports its own code.
echo "axis 0 — ANTI-VACUOUS: a normal fixture runs, returns its real code, is not a timeout:"
t0=$(date +%s)
rc=0
CYRIUS_CHECK_TIMEOUT=30 timeout 120 "$T/harness" "$T/fine" > "$T/f.out" 2>&1 || rc=$?
el=$(( $(date +%s) - t0 ))
check "the fixture's own exit code comes back" 7 "$rc"
check "and it finished promptly (not waited out)" "yes" "$([ "$el" -lt 10 ] && echo yes || echo no)"

# ── AXIS 1 — ⭐ a spinning child is KILLED at the deadline, and reported as a TIMEOUT.
echo "axis 1 — ⭐ a spinning child is killed at the deadline and reported as one:"
t0=$(date +%s)
rc=0
# The `timeout 60` is the BACKSTOP, not the mechanism: if it is what stops the run, the
# exit code is 124 and the elapsed check below fails too.
CYRIUS_CHECK_TIMEOUT=3 timeout 60 "$T/harness" "$T/spin" > "$T/s.out" 2>&1 || rc=$?
el=$(( $(date +%s) - t0 ))
check "reported as the module's TIMEOUT (-2), not as a crash or a plain nonzero" 150 "$rc"
check "the harness returned at all (did not need the 60s backstop)" "yes" \
    "$([ "$rc" != 124 ] && echo yes || echo no)"
check "elapsed >= 3s (the deadline was honoured, not short-circuited)" "yes" \
    "$([ "$el" -ge 3 ] && echo yes || echo no)"
check "elapsed < 30s (killed by the deadline, not by the backstop)" "yes" \
    "$([ "$el" -lt 30 ] && echo yes || echo no)"

# ── AXIS 1b — ⭐ THE ONE AXIS 1 CANNOT SEE: the deadline must KILL the child, not merely
# STOP WAITING for it. MEASURED, not assumed: mutating `sys_kill(pid, 9)` to the no-op
# probe `sys_kill(pid, 0)` plus a non-blocking reap leaves axes 0, 1, 2 and 3 FULLY GREEN,
# because after a single-child run the harness exits immediately and PDEATHSIG reaps the
# abandoned child for it. The leak is real and invisible — the same vacuity
# test_runner_bounded.sh records for its own single-file arm.
#
# It is only observable while the runner is STILL ALIVE, i.e. across a second child — and
# that is also the shape that actually hurts: the check driver runs the whole .tcyr corpus
# in ONE process, so a child abandoned by test 5 burns a core through tests 6..330.
# Correct = never more than the ONE child it is currently running.
#
# SUSTAINED, not a single sample: between `kill(pid, 9)` and the kernel finishing teardown
# the dying child is still in `ps`, measured at well under a second. An ABANDONED child
# stays for the whole of the second deadline — seconds. So the threshold is FOUR
# consecutive samples at 0.25 s (>= 1.0 s of overlap), the same calibration
# test_runner_bounded.sh arrived at after its 2-sample version went red under load.
echo "axis 1b — ⭐ the deadline KILLS the child, it does not merely abandon it:"
# ⚠ THE PID MUST BE THE HARNESS'S, NOT THE JOB'S. Backgrounding `timeout 120 harness …`
# makes `$!` the pid of TIMEOUT; the spinners are then GRANDchildren and a `ppid==$!`
# sampler counts exactly one child (the harness) for ever — green against anything. The
# first cut of this axis did that and passed the abandon mutation it exists to catch. The
# `sh -c 'echo $$; exec "$@"'` idiom hands back the pid the harness actually runs under.
rm -f "$T/b.pid"
( CYRIUS_CHECK_TIMEOUT=4 timeout 120 sh -c 'echo $$ > "$0"; exec "$@"' "$T/b.pid" \
      "$T/harness" "$T/spin" "$T/spin" > "$T/b.out" 2>&1 ) &
job=$!
hpid=""
i=0
while [ "$i" -lt 100 ] && [ -z "$hpid" ]; do
    hpid=$(cat "$T/b.pid" 2>/dev/null || true)
    [ -n "$hpid" ] && break
    sleep 0.1
    i=$((i + 1))
done
check "premise: the harness's own pid was captured (not the timeout wrapper's)" "yes" \
    "$([ -n "$hpid" ] && echo yes || echo no)"
maxlive=0
maxrun=0
run=0
while kill -0 "$job" 2> /dev/null; do
    live=$(ps -eo ppid= 2>/dev/null | awk -v r="$hpid" '$1==r' | grep -c . || true)
    [ "$live" -gt "$maxlive" ] && maxlive=$live
    if [ "$live" -gt 1 ]; then
        run=$((run + 1))
        [ "$run" -gt "$maxrun" ] && maxrun=$run
    else
        run=0
    fi
    sleep 0.25
done
brc=0
wait "$job" 2> /dev/null || brc=$?
check "premise: BOTH children really ran and the run ended in a timeout" 150 "$brc"
if [ "$maxlive" -gt 1 ] && [ "$maxrun" -le 3 ]; then
    echo "        note: saw $maxlive children in a single sample but never four running —"
    echo "        that is the post-SIGKILL teardown window, not an abandoned child."
fi
check "never more than the one child it is currently running (sustained)" 0 \
    "$(if [ "$maxrun" -gt 3 ]; then echo 1; else echo 0; fi)"
if [ "$maxrun" -gt 3 ]; then
    echo "        $maxlive children alive across $maxrun consecutive samples — a timed-out"
    echo "        child kept running while the driver moved on. The deadline is ABANDONING,"
    echo "        not killing: check sys_kill(pid, 9) in _regression_wait_deadline"
    echo "        (lib/regression.cyr). Sustained, so not the post-SIGKILL teardown window."
fi

# ── AXIS 2 — ⭐ THE ORPHAN. SIGKILL the runner while it waits; the child must die with it.
# CYRIUS_CHECK_TIMEOUT=0 disables the deadline on purpose, so what is measured here is
# PR_SET_PDEATHSIG alone. SIGKILL specifically: a SIGTERM could be caught by a
# parent-side handler, and this axis is about what survives when the parent gets no
# chance to do anything at all.
echo "axis 2 — ⭐ SIGKILLing the runner does not leave the child running:"
CYRIUS_CHECK_TIMEOUT=0 "$T/harness" "$T/spin" > "$T/o.out" 2>&1 &
runner=$!
child=""
i=0
while [ "$i" -lt 300 ]; do
    child=$(ps -eo pid=,ppid= 2>/dev/null | awk -v r="$runner" '$2==r {print $1}' | head -1)
    [ -n "$child" ] && break
    sleep 0.1
    i=$((i + 1))
done
check "premise: the runner really did spawn a child" "yes" \
    "$([ -n "$child" ] && echo yes || echo no)"
if [ -n "$child" ]; then
    # AXIS 2b — ANTI-VACUOUS for axis 2: the child must be ALIVE right now, otherwise
    # "it died with the runner" would be true for the wrong reason.
    check "premise: that child is alive before the runner is killed" "yes" \
        "$(ps -p "$child" > /dev/null 2>&1 && echo yes || echo no)"
    kill -9 "$runner" 2>/dev/null
    alive=yes
    j=0
    while [ "$j" -lt 100 ]; do
        if ps -p "$child" > /dev/null 2>&1; then sleep 0.1; j=$((j + 1)); else alive=no; break; fi
    done
    check "the child dies with the runner (no PPID=1 orphan)" "no" "$alive"
    if [ "$alive" = "yes" ]; then
        echo "        child $child STILL ALIVE, reparented to PPID=$(ps -o ppid= -p "$child" 2>/dev/null | tr -d ' ')"
        echo "        → PR_SET_PDEATHSIG is missing from _regression_child_guard"
        echo "          (lib/regression.cyr). A deadline alone cannot fix this: a SIGKILLed"
        echo "          parent runs no cleanup, so the kernel has to do it."
        kill -9 "$child" 2>/dev/null
    fi
else
    kill -9 "$runner" 2>/dev/null
fi
wait 2>/dev/null || true

# ── AXIS 3 — THE CENSUS UNDER IT. The two behavioural axes above exercise ONE verb; the
# defect was a HABIT shared by every fork site in the driver. So: no blocking
# `sys_waitpid(pid, &x, 0)` may remain outside `_regression_wait_deadline`'s own body,
# and — derived a different way — every `sys_fork()` site must be paired with a
# `_regression_child_guard(` call. Two independently counted numbers that have to agree.
echo "axis 3 — CENSUS: no fork site in the driver is unbounded or unguarded:"
FILES="lib/regression.cyr $(find programs/checks -name '*.cyr' | LC_ALL=C sort | tr '\n' ' ')"
nfiles=$(echo $FILES | wc -w)
check "premise: the census has files to read" "yes" \
    "$([ "$nfiles" -ge 10 ] && echo yes || echo no)"
# Two exemptions, both narrow and both load-bearing — an unexempted census is a census
# nobody can make green, and one that exempts by FILE would stop seeing new fork sites:
#   * `_regression_wait_deadline`'s own body: its timeout_ms<=0 opt-out and its post-kill
#     reap are blocking waits BY DESIGN, and they are the implementation of the fix.
#   * a reap on the line after a `sys_kill(...)`: the child is already dead, so the wait
#     cannot block. `regression_run_with_timeout` (which carries its own deadline) ends
#     that way, and so does any future site written the same shape.
# Whole-line `#` comments are stripped first: this file's OWN header quotes the bad shape
# to explain it, and a census that reads prose reports its own documentation.
blocking_lines=$(for f in $FILES; do
        awk -v F="$f" '
            /^fn _regression_wait_deadline\(/,/^}/ { next }
            { line = $0; sub(/^[ \t]*#.*$/, "", line) }
            line ~ /sys_waitpid\([A-Za-z_][A-Za-z0-9_]*, &[A-Za-z_][A-Za-z0-9_]*, 0\)/ {
                if (prev !~ /sys_kill\(/) print F ":" FNR ": " line
            }
            { if (line ~ /[^ \t]/) prev = line }
        ' "$f"
    done)
blocking=$(printf '%s\n' "$blocking_lines" | grep -c . || true)
check "blocking, deadline-free waits left in the driver" 0 "$blocking"
if [ "$blocking" != "0" ]; then printf '%s\n' "$blocking_lines" | sed 's/^/        /'; fi
nfork=$(grep -h 'sys_fork()' $FILES | grep -c 'var ' || true)
nguard=$(grep -h '_regression_child_guard(' $FILES | grep -vc '^fn ' || true)
check "premise: the census actually found fork sites" "yes" \
    "$([ "$nfork" -ge 25 ] && echo yes || echo no)"
check "every fork site arms PR_SET_PDEATHSIG (fork sites == guard calls)" "$nfork" "$nguard"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: check_driver_bounded — a hung test is killed and reported, and no child outlives the check driver"
    exit 0
fi
echo "FAIL: check_driver_bounded — $fails assertion(s) failed"
exit 1
