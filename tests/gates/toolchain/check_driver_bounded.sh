#!/bin/sh
# tests/gates/toolchain/check_driver_bounded.sh — 6.6.6 (bite 8c + its review fixes)
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
# ⚠ AND IN A SECOND MODULE THE FIRST CUT OF THIS GATE COULD NOT SEE. `programs/checks/main.cyr`
# also includes **lib/process.cyr**, whose 10 fork sites had exactly the same shape, and
# three of them are live driver paths (cyrfmt once per fixture, cyrdoc over all of `lib/`,
# a `/bin/sh -c` qemu boot). The first cut of axis 3 hard-coded
# `FILES="lib/regression.cyr programs/checks/*.cyr"`, so it read "0 blocking waits, 31 == 31"
# over a tree where `exec_capture` on a spinner still blocked for ever and still orphaned its
# child — MEASURED, at PPID=1. The census now DERIVES its file list from the driver's own
# transitive `include` closure, so a fork site the driver can reach cannot sit outside it,
# and axis 2c drives the process.cyr path for real. That module keeps its deadline OFF by
# default (it is the general process module — sigil's cryptsetup and deps' git run through
# it), so the driver asks for one in `main()`; axis 3 checks that it still does.
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
#
# MUTATION PROOF, second module (lib/process.cyr), added when the review found axis 3 green
# over a tree where `exec_capture` still hung and still orphaned:
#   * lib/process.cyr reverted to its pre-6.6.6 version -> the gate stops at the harness
#     compile (`undefined function 'proc_set_timeout_ms'`) and says so. Honest, but early,
#     so the three mutants below are the ones that actually exercise axis 2c.
#   * `proc_set_timeout_ms` accepts the value and stores nothing -> axis 2c 4 rows RED, both
#     paths hitting the 60 s backstop (rc 124); every other axis GREEN.
#   * `sys_prctl(1, 9, …)` + the getppid re-check deleted from `_proc_child_guard`, deadline
#     kept -> axis 2c's orphan row RED ALONE (`child NNN STILL ALIVE, reparented to PPID=1`).
#   * the `fork-guard-exempt` marker deleted from `spawn()` -> axis 3 RED (41 vs 40). The
#     exemption is a line someone wrote and justified, not a hole the census ignores.
#   * `proc_set_timeout_ms(...)` deleted from programs/checks/main.cyr -> axis 3's last row
#     RED: the module defaults to NO deadline, so the driver has to ask.
#   * ⭐ THE ONE THAT JUSTIFIES DERIVING THE FILE LIST. The same census, over the same
#     pre-6.6.6 lib/process.cyr, run both ways:
#         hand-written list: 15 files, 31 forks, 31 guards,  0 blocking waits => GREEN
#         derived list:      52 files, 41 forks, 31 guards, 10 blocking waits => RED
#     The first cut of this gate shipped the first number, in the same release that measured
#     the hang. A census is only as honest as the list it reads.
#
# MUTATION PROOF, the PIPE half (axis 2d + the pump row), added when the same review pointed
# out that the deadline sits AFTER an unbounded pump:
#   * lib/regression.cyr + programs/checks/* at the bite's base, 1 MB piped into a child that
#     never reads -> the harness NEVER RETURNS (rc 124 at a 25 s backstop). With the fix ->
#     150 (the module's timeout) in 6 s. The drain fixture returns 7 either way, which is the
#     anti-vacuous half: bounding a pump must not truncate a working pipe.
#   * ⚠ THE FIRST CUT OF `regression_pipe_write_all` POLLED AND THEN WROTE EVERYTHING LEFT,
#     AND AXIS 2D STAYED RED. A blocking write larger than the pipe does not come back short
#     — it waits until every byte is delivered — so a ready POLLOUT is no protection at all
#     past the 64 KB buffer. POLLOUT promises PIPE_BUF (4096) bytes of room and nothing more,
#     so the helper now writes at most that per ready poll. Recorded because "poll, then
#     write" reads correct and is not, and the gate is what said so.
#   * the pump census over the base tree -> 15 hits (3 lib/process.cyr, 1 lib/regression.cyr,
#     2 crosshost, 1 platform_efi, 8 selfhost); over this tree -> 0.
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
# A third fixture, for the PIPE axis: it DRAINS stdin to EOF and then exits 7 — a stack
# buffer and a raw read(2), so it needs no includes. The spinner above never reads, so a
# source larger than the 64 KB pipe buffer blocks the WRITER in sys_write before the wait
# deadline can ever run; this one is the same call that has to keep working.
printf 'fn main(): i64 { var p[65536]; var go = 1; while (go == 1) { var n = syscall(0, 0, &p, 65536); if (n <= 0) { go = 0; } } return 7; }\nvar r = main();\nsyscall(60, r);\n' > "$T/drain.cyr"
for f in spin fine drain; do
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
    # PIPE MODE (HARNESS_PIPE_SRC=<file>): drive regression_pipe_to_bin_capture, the verb
    # that pumps a whole source INTO the child's stdin BEFORE it waits. Selected by env, not
    # by argv, because argv(2) is already axis 1b's second binary.
    var src = getenv("HARNESS_PIPE_SRC");
    if (src != 0) {
        var prc = regression_pipe_to_bin_capture(bin, src, 0, &HARNESS_ENVP);
        if (prc == 0 - 2) { return 150; }
        if (prc == 0 - 1) { return 151; }
        if (prc < 0) { return 152; }
        return prc;
    }
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

# ── the SECOND harness — lib/process.cyr ────────────────────────────────────────────
# The driver reaches this module for cyrfmt / cyrdoc / qemu, and it is a DIFFERENT
# implementation of the same shape: its own fork sites, its own wait, and a `sys_read` loop
# on the child's pipe IN FRONT of that wait (which is why bounding the wait alone is not
# enough — a child that holds the pipe and writes nothing never lets the deadline run).
# `argv(2)` is the deadline in ms handed to `proc_set_timeout_ms`; a third argument selects
# `exec_vec` (no pipe, reports the timeout as the module's -2) over `exec_capture` (pipe).
cat > "$T/pharness.cyr" <<'PHARNESS'
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

fn main(): i64 {
    args_init();
    var bin = argv(1);
    if (bin == 0) { return 2; }
    var msarg = argv(2);
    var ms = 0;
    if (msarg != 0) { ms = atoi(msarg); }
    proc_set_timeout_ms(ms);
    var mode = 0;
    if (argc() > 3) { mode = 1; }
    var a = vec_new();
    vec_push(a, bin);
    if (mode == 1) {
        var rc = exec_vec(a);
        if (rc == 0 - 2) { return 150; }
        if (rc < 0) { return 151; }
        return rc;
    }
    var buf = alloc(65536);
    var n = exec_capture(a, buf, 65536);
    if (n < 0) { return 151; }
    return 3;
}
var r = main();
syscall(60, r);
PHARNESS
if ! "$ROOT/build/cycc" < "$T/pharness.cyr" > "$T/pharness" 2> "$T/pharness.err"; then
    echo "FAIL: check_driver_bounded — the process.cyr harness did not compile:"; cat "$T/pharness.err"; exit 1
fi
[ -s "$T/pharness" ] || { echo "FAIL: check_driver_bounded — the process.cyr harness compiled to an EMPTY binary"; exit 1; }
chmod +x "$T/pharness"

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

# ── AXIS 2c — ⭐ THE SECOND MODULE. Everything above drives lib/regression.cyr. The driver
# ALSO forks through lib/process.cyr, and that module was still unbounded and unguarded when
# the first cut of this gate went green — so this axis exists because a census scoped by hand
# reported 31 == 31 over a path that hung and orphaned. Three rows, the same three properties:
# it still runs an ordinary child; a hung child is bounded (through the PIPE path, which
# blocks BEFORE the wait, and through the no-pipe path, which reports the module's -2); and
# SIGKILLing the runner does not leave the child behind.
echo "axis 2c — ⭐ the driver's OTHER fork module (lib/process.cyr) is bounded and guarded:"
rc=0
timeout 60 "$T/pharness" "$T/fine" 2000 vec > "$T/p0.out" 2>&1 || rc=$?
check "ANTI-VACUOUS: an ordinary child still returns its own exit code" 7 "$rc"
t0=$(date +%s)
rc=0
timeout 60 "$T/pharness" "$T/spin" 2000 vec > "$T/p1.out" 2>&1 || rc=$?
el=$(( $(date +%s) - t0 ))
check "exec_vec reports the deadline as the module's TIMEOUT (-2)" 150 "$rc"
check "and returned without the 60s backstop" "yes" "$([ "$rc" != 124 ] && echo yes || echo no)"
t0=$(date +%s)
rc=0
timeout 60 "$T/pharness" "$T/spin" 2000 > "$T/p2.out" 2>&1 || rc=$?
el=$(( $(date +%s) - t0 ))
# ⚠ THE PIPE PATH IS THE ONE THAT WAS MEASURED HANGING. exec_capture drains the child's
# stdout BEFORE it waits, so a deadline on the wait alone leaves it blocked in sys_read for
# ever — which is exactly what `CYRIUS_CHECK_TIMEOUT=3 ph ./spin` did (still blocked at 6 s).
check "exec_capture (the PIPE path) returns at all" 3 "$rc"
check "and it was the deadline that ended it, not the backstop" "yes" \
    "$([ "$el" -lt 30 ] && echo yes || echo no)"
"$T/pharness" "$T/spin" 0 > "$T/p3.out" 2>&1 &
prunner=$!
pchild=""
i=0
while [ "$i" -lt 300 ]; do
    pchild=$(ps -eo pid=,ppid= 2>/dev/null | awk -v r="$prunner" '$2==r {print $1}' | head -1)
    [ -n "$pchild" ] && break
    sleep 0.1
    i=$((i + 1))
done
check "premise: it really did spawn a child (deadline 0 = the historical blocking wait)" "yes" \
    "$([ -n "$pchild" ] && echo yes || echo no)"
if [ -n "$pchild" ]; then
    kill -9 "$prunner" 2>/dev/null
    palive=yes
    j=0
    while [ "$j" -lt 100 ]; do
        if ps -p "$pchild" > /dev/null 2>&1; then sleep 0.1; j=$((j + 1)); else palive=no; break; fi
    done
    check "the child dies with the runner (no PPID=1 orphan)" "no" "$palive"
    if [ "$palive" = "yes" ]; then
        echo "        child $pchild STILL ALIVE, reparented to PPID=$(ps -o ppid= -p "$pchild" 2>/dev/null | tr -d ' ')"
        echo "        → PR_SET_PDEATHSIG is missing from _proc_child_guard (lib/process.cyr)."
        kill -9 "$pchild" 2>/dev/null
    fi
else
    kill -9 "$prunner" 2>/dev/null
fi
wait 2>/dev/null || true

# ── AXIS 2d — ⭐ THE PIPE, NOT ONLY THE WAIT. Every verb here reaches its bounded wait only
# AFTER it has finished pumping the child's pipe, and those pumps were unbounded `while`
# loops — so a child that holds its end open and never drains blocks the runner BEFORE the
# deadline can run. Measured on the WRITE side, which is the one the driver actually hits:
# the compiler pipes ~1 MB of src/main.cyr into a child, and 64 KB into a child that never
# reads is enough to block for ever. The anti-vacuous partner is a fixture that DOES drain
# stdin: bounding the pump must not truncate a working pipe.
echo "axis 2d — ⭐ the pipe pump is bounded too, not just the wait:"
# ~1 MB, comfortably past the 64 KB pipe buffer, built here rather than borrowed from the
# tree so the axis does not depend on any particular file's size.
: > "$T/big.src"
i=0
while [ "$i" -lt 64 ]; do
    dd if=/dev/zero bs=16384 count=1 2>/dev/null | tr '\0' 'x' >> "$T/big.src"
    i=$((i + 1))
done
bigsz=$(wc -c < "$T/big.src")
check "premise: the source is bigger than a pipe buffer" "yes" \
    "$([ "$bigsz" -gt 200000 ] && echo yes || echo no)"
rc=0
HARNESS_PIPE_SRC="$T/big.src" CYRIUS_CHECK_TIMEOUT=30 timeout 120 "$T/harness" "$T/drain" \
    > "$T/w0.out" 2>&1 || rc=$?
check "ANTI-VACUOUS: a child that DRAINS the pipe still gets it all and returns its code" 7 "$rc"
t0=$(date +%s)
rc=0
HARNESS_PIPE_SRC="$T/big.src" CYRIUS_CHECK_TIMEOUT=3 timeout 60 "$T/harness" "$T/spin" \
    > "$T/w1.out" 2>&1 || rc=$?
el=$(( $(date +%s) - t0 ))
check "a child that never drains the pipe no longer blocks the runner" "yes" \
    "$([ "$rc" != 124 ] && echo yes || echo no)"
check "and it ended within the deadlines, not the 60s backstop" "yes" \
    "$([ "$el" -lt 30 ] && echo yes || echo no)"
if [ "$rc" = 124 ]; then
    echo "        the harness never returned: the write pump in regression_pipe_to_bin_capture"
    echo "        is blocked in sys_write with the pipe full. regression_pipe_write_all's poll"
    echo "        is what bounds it — the wait deadline is never reached from there."
fi

# ── AXIS 3 — THE CENSUS UNDER IT. The behavioural axes above exercise THREE verbs; the
# defect was a HABIT shared by every fork site the driver can reach. So: no blocking
# `sys_waitpid(pid, &x, 0)` may remain outside a `*_wait_deadline` body, and — derived a
# different way — every `sys_fork()` site must be paired with a child-guard call. Two
# independently counted numbers that have to agree.
#
# ⛔ THE FILE LIST IS DERIVED, NOT WRITTEN DOWN. Its first cut was
# `FILES="lib/regression.cyr $(find programs/checks …)"`, which is a list of the files whose
# defect was already known — so lib/process.cyr, which the driver includes and forks through
# on three live paths, sat OUTSIDE the census while the census reported it clean. The list is
# now the driver's own transitive `include` closure (from programs/checks/main.cyr) unioned
# with programs/checks/*.cyr, so a module the driver pulls in is in the census by
# construction. A `#ifdef`-guarded include is followed too: it is compiled on SOME host, and
# an unbounded wait there is the same defect one platform over.
echo "axis 3 — CENSUS: no fork site the driver can reach is unbounded or unguarded:"
_include_closure() {
    _cl_seen=""
    _cl_todo="programs/checks/main.cyr"
    while [ -n "$_cl_todo" ]; do
        _cl_next=""
        for _f in $_cl_todo; do
            case " $_cl_seen " in *" $_f "*) continue ;; esac
            _cl_seen="$_cl_seen $_f"
            [ -f "$_f" ] || continue
            _cl_next="$_cl_next $(sed -n 's/^ *include "\([A-Za-z0-9_/]*\.cyr\)".*/\1/p' "$_f" | tr '\n' ' ')"
        done
        _cl_todo="$_cl_next"
    done
    printf '%s\n' "$_cl_seen"
}
FILES=$( { _include_closure | tr ' ' '\n'; find programs/checks -name '*.cyr'; } \
         | grep -v '^$' | LC_ALL=C sort -u | tr '\n' ' ')
nfiles=$(echo $FILES | wc -w)
check "premise: the census has files to read" "yes" \
    "$([ "$nfiles" -ge 30 ] && echo yes || echo no)"
# Both fork-owning modules must be IN the derived list — a closure walk that silently
# returned nothing would otherwise make every count below trivially agree at 0.
for _m in lib/regression.cyr lib/process.cyr; do
    check "premise: the derivation found $_m" "yes" \
        "$(case " $FILES " in *" $_m "*) echo yes ;; *) echo no ;; esac)"
done
# Two exemptions, both narrow and both load-bearing — an unexempted census is a census
# nobody can make green, and one that exempts by FILE would stop seeing new fork sites:
#   * a `*_wait_deadline` body (`_regression_wait_deadline`, `_proc_wait_deadline`): the
#     timeout_ms<=0 opt-out and the post-kill reap are blocking waits BY DESIGN, and they
#     are the implementation of the fix. Matched by SHAPE, not by name, so the module that
#     gets this treatment next is covered without editing the gate.
#   * a reap on the line after a `sys_kill(...)`: the child is already dead, so the wait
#     cannot block. `regression_run_with_timeout` (which carries its own deadline) ends
#     that way, and so does any future site written the same shape.
# Whole-line `#` comments are stripped first: this file's OWN header quotes the bad shape
# to explain it, and a census that reads prose reports its own documentation.
blocking_lines=$(for f in $FILES; do
        awk -v F="$f" '
            /^fn _[a-z_]*_wait_deadline\(/,/^}/ { next }
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
# The PIPE half of the same habit (axis 2d's defect): a `sys_read`/`sys_write` on the line
# directly under a `while (`, INSIDE A FUNCTION THAT FORKS. That scoping is the whole
# definition — a pump on a child's pipe is the one that can block for ever, while the same
# idiom over a regular file (lib/io.cyr's `file_read_all`, process_agnos.cyr's ELF slurp)
# cannot and is not a finding. Deriving it from "the enclosing fn calls sys_fork()" also
# means the helpers are exempt without naming them: their bodies are the loop, and they do
# not fork.
# ⚠ SCOPE, stated so nobody reads this row as wider than it is: it is the POSIX
# fork+pipe idiom. lib/process_win.cyr's `run_capture` has the same unbounded drain over a
# Windows HANDLE with no fork in sight, and needs a PE mechanism (there is no poll(2)
# there) — this row does not see it and does not claim to.
pump_lines=$(for f in $FILES; do
        awk -v F="$f" '
            /^fn / { infn = 1; forked = 0; np = 0 }
            { line = $0; sub(/^[ \t]*#.*$/, "", line) }
            line ~ /sys_fork\(\)/ { forked = 1 }
            line ~ /sys_(read|write)\(/ {
                if (prev ~ /while \(/) { pend[np] = F ":" FNR ": " line; np = np + 1 }
            }
            { if (line ~ /[^ \t]/) prev = line }
            /^}/ {
                if (infn == 1 && forked == 1) { for (i = 0; i < np; i++) print pend[i] }
                infn = 0; forked = 0; np = 0
            }
        ' "$f"
    done)
pumps=$(printf '%s\n' "$pump_lines" | grep -c . || true)
check "unbounded pipe pumps left in the driver (loops inside forking fns)" 0 "$pumps"
if [ "$pumps" != "0" ]; then printf '%s\n' "$pump_lines" | sed 's/^/        /'; fi
nfork=$(grep -h 'sys_fork()' $FILES | grep -c 'var ' || true)
nguard=$(grep -hE '_(regression|proc)_child_guard\(' $FILES | grep -vc '^fn ' || true)
# ONE exemption, by MARKER rather than by file, so it is a line someone has to write and
# justify: `spawn()` in lib/process.cyr, whose entire contract is that the child OUTLIVES the
# call (PDEATHSIG there would kill a consumer's daemon the moment the launcher exits). The
# markers are printed, so adding one is visible in the gate output rather than in a diff.
nexempt=$(grep -h 'fork-guard-exempt' $FILES | grep -c . || true)
check "premise: the census actually found fork sites" "yes" \
    "$([ "$nfork" -ge 35 ] && echo yes || echo no)"
check "every fork site arms PR_SET_PDEATHSIG (fork sites - exemptions == guard calls)" \
    "$nfork" "$((nguard + nexempt))"
if [ "$nexempt" != "0" ]; then
    echo "        $nexempt exemption(s), each with its reason in the source:"
    grep -n 'fork-guard-exempt' $FILES | sed 's/^/          /'
fi
# And the driver has to ASK for the bound: lib/process.cyr defaults to no deadline (it is the
# general process module), so without this call its children are unbounded however well the
# module is written. Derived from the driver source, not from the module.
nset=$(grep -c 'proc_set_timeout_ms(' programs/checks/main.cyr || true)
check "the check driver sets lib/process.cyr's deadline (proc_set_timeout_ms in main.cyr)" \
    "yes" "$([ "$nset" -ge 1 ] && echo yes || echo no)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: check_driver_bounded — a hung test is killed and reported, and no child outlives the check driver"
    exit 0
fi
echo "FAIL: check_driver_bounded — $fails assertion(s) failed"
exit 1
