#!/bin/sh
# tests/gates/toolchain/check_driver_dies_with_check_sh.sh — 6.6.6 (bite 25c)
#
# THE CHECK DRIVER DOES NOT OUTLIVE THE RUN THAT STARTED IT.
#
# THE DEFECT. Bite 8c gave every child the driver forks a PR_SET_PDEATHSIG(SIGKILL) guard
# (`_regression_child_guard`, set between fork and execve) so a killed driver cannot leave
# a test burning a core. Nothing protected the DRIVER ITSELF: `scripts/check.sh` spawns
# `build/cyrius_check`, and a POSIX shell cannot set PR_SET_PDEATHSIG for a child it is
# about to exec. So a SIGKILLed check.sh left the driver running — OBSERVED at PPID=1,
# nine minutes old, still grinding through a suite nobody was watching, holding a core and
# writing into a $TMPDIR whose owner was gone.
#
# ⭐ WHY SELF-ARMING AND NOT A WATCHDOG, since the bite could have gone either way: a
# watchdog is another process and another process can be SIGKILLed too — the same failure
# one level up. The whole reason this defect exists is that a SIGKILLed process runs no
# cleanup, EVER, so nothing in user space can be relied on to outlive it. Arming
# PR_SET_PDEATHSIG for yourself asks the KERNEL to deliver the signal when your parent
# dies, however it dies. That is the only form a SIGKILL cannot defeat.
#
# ⚖️ THE DEADLINE HALF IS ALREADY COVERED, and is deliberately not re-asserted here: bite
# 8c bounded every child of the driver (lib/regression.cyr and lib/process.cyr, censused by
# tests/gates/toolchain/check_driver_bounded.sh axis 3 at 0 blocking waits), and bite 8's
# review bounded the pipe pumps in front of those waits. The driver's own code is loops
# over files; it cannot hang except in a child, and its children are bounded. A
# self-imposed wall-clock deadline on the whole suite would be a number pretending to be a
# bound — on a loaded box the honest value is far above any hang worth catching.
#
# ANTI-VACUOUS: axis 0 runs the SAME spinner with the guard call REMOVED and requires it to
# SURVIVE. Both binaries come out of one generator differing in that single line, so axis 1
# cannot pass because the harness fails to orphan anything, and a kernel or container that
# made PDEATHSIG moot would redden axis 0 rather than silently greening axis 1.
#
# INDEPENDENT DERIVATION: axis 3 does not use the gate's own spinner at all — it compiles
# the REAL `programs/checks/main.cyr` and orphans THAT, so the property is proven on the
# artifact check.sh actually runs, not only on a stand-in that calls the same helper.
#
# MUTATION PROOF (6.6.6, scratch copies — never the repo):
#   * `_regression_die_with_parent()` removed from `main()` -> 3 RED: axis 2 twice (no
#     call in main; "27 statement(s) run in main() before the guard is armed") and axis 3
#     ("the REAL driver SURVIVED the SIGKILLed parent, reparented to PPID=1"). Axes 0/1
#     stay GREEN, because the helper itself is still correct — which is exactly the hole
#     axis 3 exists for: a working primitive nobody calls.
#   * `sys_prctl(1, 9, 0, 0, 0)` deleted from the helper, getppid re-check kept -> 3 RED:
#     axis 1 (armed spinner survived), axis 2's Linux-guard extraction (no prctl to find)
#     and axis 3. Axis 0 GREEN.
#   * the whole helper body replaced with `return 0;` -> the same 3 RED.
#   * the call moved below `alloc_init()` / `_load_environ()` -> axis 2's ordering check
#     RED ALONE ("2 statement(s) run in main() before the guard is armed"). The window
#     this closes is startup; a guard armed after the work has begun is not the fix.
#   * the `#ifdef CYRIUS_TARGET_LINUX` guard removed from the helper -> axis 2 RED alone
#     ("got 'bare'"). An unguarded prctl is a SIGSYS on Darwin and unrouted on PE, and
#     everything still works on Linux, so nothing else can see it.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

[ -x "$ROOT/build/cycc" ] || { echo "FAIL: build/cycc not built"; exit 1; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: mktemp -d"; exit 1; }
_cleanup() {
    [ -n "${AX_CHILD:-}" ] && kill -9 "$AX_CHILD" 2>/dev/null
    [ -n "${DRV_CHILD:-}" ] && kill -9 "$DRV_CHILD" 2>/dev/null
    rm -rf "$T"
}
trap _cleanup EXIT

FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
ulimit -c 0

# ── the two spinners: identical but for one line ──────────────────────────────────────
_gen_spinner() {
    _out=$1
    _armed=$2
    {
        echo 'include "lib/string.cyr"'
        echo 'include "lib/fmt.cyr"'
        echo 'include "lib/alloc.cyr"'
        echo 'include "lib/io.cyr"'
        echo 'include "lib/vec.cyr"'
        echo 'include "lib/str.cyr"'
        echo 'include "lib/args.cyr"'
        echo 'include "lib/flags.cyr"'
        echo 'include "lib/syscalls.cyr"'
        echo 'include "lib/fs.cyr"'
        echo 'include "lib/process.cyr"'
        echo 'include "lib/net.cyr"'
        echo 'include "lib/regression.cyr"'
        echo 'fn main(): i64 {'
        [ "$_armed" = "armed" ] && echo '    _regression_die_with_parent();'
        echo '    alloc_init();'
        # Bounded backstop: ~20 s of 10 ms poll sleeps, so nothing can run away even if
        # the guard and the gate's own cleanup both fail.
        echo '    var i = 0;'
        echo '    while (i < 2000) { syscall(7, 0, 0, 10); i = i + 1; }'
        echo '    return 0;'
        echo '}'
        echo 'var r = main();'
        echo 'syscall(60, r);'
    } > "$_out.cyr"
    if ! "$ROOT/build/cycc" < "$_out.cyr" > "$_out" 2> "$_out.err"; then
        _fail "the $_armed spinner did not compile:"; sed 's/^/    /' "$_out.err"; return 1
    fi
    [ -s "$_out" ] || { _fail "the $_armed spinner compiled to an EMPTY binary"; return 1; }
    chmod +x "$_out"
    return 0
}

# Runs $1 as a background child of a shell, SIGKILLs the shell, answers "survived"/"died".
# The child's pid is the one the SHELL reports for its own background job — never a
# wrapper's (the trap check_driver_bounded.sh records: backgrounding `timeout prog` makes
# $! the timeout, and the real process a grandchild).
VERDICT=""
ORPHAN_PID=""
ORPHAN_PPID=""
_orphan_test() {
    _bin=$1
    rm -f "$T/p.pid" "$T/c.pid"
    ( sh -c 'echo $$ > "$0"; "$1" > /dev/null 2>&1 & echo $! > "$2"; sleep 25' \
          "$T/p.pid" "$_bin" "$T/c.pid" ) > /dev/null 2>&1 &
    _job=$!
    _i=0
    while [ "$_i" -lt 150 ]; do
        [ -s "$T/c.pid" ] && [ -s "$T/p.pid" ] && break
        sleep 0.1
        _i=$((_i + 1))
    done
    _pp=$(cat "$T/p.pid" 2>/dev/null || true)
    _cp=$(cat "$T/c.pid" 2>/dev/null || true)
    ORPHAN_PID=$_cp
    ORPHAN_PPID=""
    if [ -z "$_pp" ] || [ -z "$_cp" ]; then VERDICT=nostart; return 0; fi
    kill -9 "$_pp" 2>/dev/null
    # Reap the job here, quietly: an interactive-style shell otherwise prints its own
    # "Killed" notification to the gate's stderr when it notices, which reads like a
    # failure in check.sh's output and is not one.
    wait "$_job" 2>/dev/null || true
    sleep 1.5
    if kill -0 "$_cp" 2>/dev/null; then
        ORPHAN_PPID=$(ps -o ppid= -p "$_cp" 2>/dev/null | tr -d ' ')
        kill -9 "$_cp" 2>/dev/null
        VERDICT=survived
    else
        VERDICT=died
    fi
}

# ── axis 0 — the anti-vacuous control: unguarded, it SURVIVES ─────────────────────────
echo "axis 0: an unguarded child of a SIGKILLed shell survives (the defect, reproduced)"
if _gen_spinner "$T/bare" bare; then
    _orphan_test "$T/bare"
    AX_CHILD=${ORPHAN_PID:-}
    case "$VERDICT" in
        survived) echo "  unguarded spinner survived, reparented to PPID=$ORPHAN_PPID" ;;
        nostart)  _fail "the unguarded spinner never started — the harness is broken, so axis 1 would be vacuous" ;;
        *)        _fail "the UNGUARDED spinner died with its parent — something other than the guard is killing children here, so axis 1 proves nothing" ;;
    esac
fi

# ── axis 1 — the guard: armed, it DIES ────────────────────────────────────────────────
echo "axis 1: _regression_die_with_parent() makes the child die with a SIGKILLed parent"
if _gen_spinner "$T/armed" armed; then
    _orphan_test "$T/armed"
    AX_CHILD=${ORPHAN_PID:-}
    case "$VERDICT" in
        died)     echo "  armed spinner died with its parent" ;;
        nostart)  _fail "the armed spinner never started" ;;
        *)        _fail "the ARMED spinner SURVIVED the SIGKILLed parent, reparented to PPID=$ORPHAN_PPID" ;;
    esac
fi

# ── axis 2 — the source census: the driver arms it, FIRST, and Linux-guarded ──────────
echo "axis 2: the driver arms the guard as its first statement, under a Linux guard"
NCALL=$(grep -c '^ *_regression_die_with_parent();' programs/checks/main.cyr || true)
[ "$NCALL" -ge 1 ] || _fail "programs/checks/main.cyr never calls _regression_die_with_parent()"
# Nothing may execute before it: the body of main() up to the call must be empty once
# comments and blank lines are removed.
PRE=$(awk '/^fn main\(\): i64 \{/ { inm = 1; next }
           inm && /_regression_die_with_parent\(\);/ { exit }
           inm { print }' programs/checks/main.cyr \
      | sed -e 's/^[ \t]*//' -e '/^#/d' -e '/^$/d' | grep -c . || true)
[ "$PRE" = "0" ] || _fail "$PRE statement(s) run in main() before the guard is armed — the startup window is the whole point"
# The helper is Linux-only: an unguarded prctl is a SIGSYS on Darwin and unrouted on PE.
GUARDED=$(awk '/^fn _regression_die_with_parent\(\): i64 \{/ { inf = 1 }
               inf && /#ifdef CYRIUS_TARGET_LINUX/ { g = 1 }
               inf && /sys_prctl\(/ { print (g ? "guarded" : "bare"); exit }' lib/regression.cyr)
[ "$GUARDED" = "guarded" ] || _fail "_regression_die_with_parent's sys_prctl is not inside a CYRIUS_TARGET_LINUX guard (got '$GUARDED')"

# ── axis 3 — the REAL driver, not a stand-in ──────────────────────────────────────────
echo "axis 3: the REAL build of programs/checks/main.cyr dies with a SIGKILLed parent"
if ! "$ROOT/build/cycc" < programs/checks/main.cyr > "$T/drv" 2> "$T/drv.err"; then
    _fail "the real check driver did not compile:"; sed 's/^/    /' "$T/drv.err"
else
    [ -s "$T/drv" ] || _fail "the real check driver compiled to an EMPTY binary"
    chmod +x "$T/drv"
    # Its own TMPDIR, so the suite work it starts and never finishes is swept with $T.
    TMPDIR="$T" _orphan_test "$T/drv"
    DRV_CHILD=${ORPHAN_PID:-}
    case "$VERDICT" in
        died)    echo "  the real driver died with its parent" ;;
        nostart) _fail "the real driver never started" ;;
        *)       _fail "the REAL driver SURVIVED the SIGKILLed parent, reparented to PPID=$ORPHAN_PPID — this is the observed defect" ;;
    esac
fi

echo ""
if [ "$FAILS" = "0" ]; then
    echo "PASS: the check driver dies with the run that started it"
    exit 0
fi
echo "FAILED: $FAILS assertion(s)"
exit 1
