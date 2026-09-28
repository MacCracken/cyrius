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
# ⛔ 6.6.8 — AND NOTHING THE RUN STARTED OUTLIVES IT, WHICHEVER WAY IT ENDS. This header used
# to say "THE DEADLINE HALF IS ALREADY COVERED" for every child of the run. That was false for
# all 70 gates check.sh ran itself (a foreground `sh "$_g"`: no death signal, no deadline),
# and for the driver's gates it held one level deep only: PR_SET_PDEATHSIG is cleared on
# fork, and the deadline killed the gate's sh alone, so the gate's own children were
# reparented to init. Every kill was SIGKILL, so no gate's `trap 'rm -rf "$T"' EXIT` ran; and
# `kill <check.sh>` waited for the current child to finish (POSIX defers a trap until the
# foreground command returns). Axes 4-10 pin the fix — every gate runs under
# `cyrius_check --run-gate` (programs/checks/run_gate.cyr: a subreaper in the SAME process
# group, PDEATHSIG, TERM -> grace -> KILL of the whole tree) and check.sh runs its children
# as `& wait` and forwards the signal:
#   axis 4   SIGKILL of check.sh while a gate sleeps: none of the gate's processes survive,
#            and its EXIT trap removed its mktemp dir
#   axis 5   the same for a DRIVER-run gate (the real driver's `--gate-row`, i.e. `_gate`)
#   axis 6   a deadline kill takes the grandchildren, says TIMEOUT naming the gate and the
#            setting, exits 124, and the EXIT trap still removes the mktemp dir; 6b the same
#            through check.sh is a `^^ TIMEOUT` line and a counted failure in the summary, and
#            a malformed knob (` 2`) is refused once by check.sh instead of meaning "no deadline"
#   axis 7   SIGTERM of check.sh returns within a few seconds while a gate is sleeping
#   axis 8   `kill -- -PGID` still reaches a grandchild (no setsid anywhere)
#   axis 9   a gate that EXITS leaving a background process behind leaves nothing running
#            (the subreaper is what can still see that orphan)
#   axis 10  ANTI-VACUOUS: the same SIGKILL against a check.sh whose `_chk_gate` is put back
#            to the pre-6.6.8 foreground `sh "$_g"` DOES leak — the harness can see a leak
#   axis 11  a GROUP SIGTERM (`kill -- -PGID`, `timeout`) and a group SIGINT (Ctrl-C) let the
#            gate's EXIT trap run to its LAST command: the supervisor does not answer a
#            signal the gate already has with a second SIGTERM mid-trap
#   axis 12  a gate's own `exit 124` is reported as 1 — never as a TIMEOUT — both with a
#            deadline and under CYRIUS_CHECK_LONG_TIMEOUT=0, directly and through check.sh
# MUTATION PROOF (6.6.8, each edit made and reverted in the lane worktree, one at a time):
#   * `sys_prctl(36, …)` (the subreaper) removed from run_gate.cyr -> axes 4, 5, 6, 7 and 9
#     RED: a supervisor signals each process once, from directly above it, and adopts the
#     orphans as they appear — without the subreaper they go to init, where nothing reaches
#     them (2 survivors on each of 4-7, 1 on 9, and 9's "left 1 process(es)" note is gone).
#   * `_RG_GRACE_MS` set to 0 (TERM then an immediate KILL) -> axes 4, 5, 6 and 7 RED, each on
#     the mktemp dir: the EXIT trap never gets to run.
#   * `_chk_gate` put back to a foreground `sh "$_g"` -> axes 4 and 7 RED (7 measured at 315 s
#     before it was bounded: the SIGTERM waited for the gate's own sleep); axis 10 is that
#     same mutation, run on purpose and required to leak.
#   * `_rg_let_children_end` dropped from the signal path (every signal TERMs the child at
#     once, the first cut) -> axis 11 RED on both TERM and INT: the trap's last command
#     never ran.
#   * `_regression_term_children_once` dropped from `_rg_let_children_end` (adopted orphans
#     spared too) -> axis 11 (INT) RED on the 4 s bound: the gate's `sleep &` ignores SIGINT.
#   * the 124 remap put back behind `deadline_ms > 0` -> axis 12 RED on LONG_TIMEOUT=0,
#     directly and through check.sh.
# ⚠ ONE SIGTERM PER PROCESS. The first cut of the supervisor signalled every descendant at
# once; axis 5 went RED on it — a nested supervisor (driver -> --run-gate) sent the gate's
# shell a SECOND SIGTERM while its EXIT trap ran, and bash dies mid-trap on that.

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
    # 6.6.8: anything an axis left behind carries this run's tag in its argv.
    for _sp in $(ps -eo pid=,args= | awk -v t="$$" '$2 == "sleep" && $3 ~ ("^47[12][.]" t "$") { print $1 }'); do
        kill -9 "$_sp" 2>/dev/null
    done
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

# ── axes 4-10 — the supervisor: nothing a run started outlives it ─────────────────────
# A sleeper gate that records what it started. Every process it leaves carries TAG in its
# argv (`sleep <N>.<TAG>`), so a survivor is found by scanning ps for the tag, never by
# trusting a pid file the process under test wrote.
TAG="$$"
RUN_BIN="$T/drv"
[ -x "$RUN_BIN" ] || { _fail "no driver binary to run gates under (axis 3 failed to build it)"; }
_mk_sleeper() {  # $1 = file, $2 = marker dir, $3 = "exit" to exit leaving a bg process
    {
        echo '#!/bin/sh'
        echo "M=\"$2\""
        echo 'X="$M/scratch.$$"; mkdir "$X" || exit 9'
        if [ "${3:-}" = "trap2" ]; then
            # A trap with WORK after its first command, and a marker only its LAST command
            # writes: a shell killed partway through its EXIT trap leaves no marker.
            echo 'trap '"'"'rm -rf "$X"; sleep 0.2; echo done > "$M/trap.done"'"'"' EXIT'
        else
            echo 'trap '"'"'rm -rf "$X"'"'"' EXIT'
        fi
        echo 'echo "$X" > "$M/scratch.path"'
        echo "sleep 471.$TAG &"
        echo 'echo "$!" > "$M/bg.pid"'
        if [ "${3:-}" = "exit" ]; then echo 'exit 0'; fi
        echo "sleep 472.$TAG"
    } > "$1"
}
_survivors() {  # the processes carrying this run's tag, one pid per line
    ps -eo pid=,args= | awk -v t="$TAG" '$2 == "sleep" && $3 ~ ("^47[12][.]" t "$") { print $1 }'
}
_kill_survivors() { for _sp in $(_survivors); do kill -9 "$_sp" 2>/dev/null; done; }
_wait_file() {  # $1 = file, waits up to ~10 s
    _wi=0
    while [ ! -s "$1" ] && [ "$_wi" -lt 100 ]; do sleep 0.1; _wi=$((_wi + 1)); done
    [ -s "$1" ]
}
_scratch_gone() {  # $1 = marker dir -> "gone" / "left"
    _sx=$(cat "$1/scratch.path" 2>/dev/null || true)
    if [ -n "$_sx" ] && [ -d "$_sx" ]; then echo left; else echo gone; fi
}
# A scratch root that runs the REAL check.sh over a one-gate fake registry, with the tree's
# own driver as the supervisor.
_mk_chkroot() {  # $1 = root, $2 = check.sh to use, $3 = sleeper mode (optional)
    mkdir -p "$1/scripts" "$1/build" "$1/programs/checks" "$1/lib" "$1/tmp" "$1/home" \
             "$1/tests/gates/zzsup" "$1/m"
    cp "$2" "$1/scripts/check.sh"
    cp "$ROOT/VERSION" "$1/"
    : > "$1/programs/checks/main.cyr"
    : > "$1/lib/placeholder.cyr"
    printf '#!/bin/sh\nexit 0\n' > "$1/build/cycc"
    printf '#!/bin/sh\nmkdir -p "$CYRIUS_HOME/bin"\nexit 0\n' > "$1/scripts/install.sh"
    chmod +x "$1/build/cycc" "$1/scripts/install.sh"
    cp "$RUN_BIN" "$1/build/cyrius_check"
    touch -d '2038-01-01' "$1/build/cyrius_check"
    _mk_sleeper "$1/tests/gates/zzsup/zzsleeper.sh" "$1/m" "${3:-}"
    printf '_chk_gate "$ROOT/tests/gates/zzsup/zzsleeper.sh"\n' >> "$1/scripts/check.sh"
}
# Start the scratch check.sh on the sleeper; sets CHK (its pid) once the gate is running.
_start_chk() {  # $1 = root, rest = env assignments
    _r=$1; shift
    rm -f "$_r/m/bg.pid" "$_r/m/scratch.path"
    ( cd "$_r" && exec env -u CYRIUS_HOME HOME="$_r/home" TMPDIR="$_r/tmp" "$@" \
        sh scripts/check.sh zzsleeper ) > "$_r/out" 2>&1 &
    CHK=$!
    _wait_file "$_r/m/bg.pid"
}

if [ -x "$RUN_BIN" ]; then
echo "axis 4: SIGKILL of check.sh leaves nothing of a check.sh-run gate"
R4="$T/r4"; _mk_chkroot "$R4" "$ROOT/scripts/check.sh"
if _start_chk "$R4"; then
    sleep 0.3
    kill -9 "$CHK" 2>/dev/null; wait "$CHK" 2>/dev/null
    sleep 1.5
    NS=$(_survivors | grep -c . || true)
    [ "$NS" = "0" ] || _fail "axis 4: $NS process(es) of the gate survived a SIGKILLed check.sh"
    [ "$(_scratch_gone "$R4/m")" = "gone" ] || _fail "axis 4: the gate's EXIT trap did not run — its mktemp dir is still there"
else
    _fail "axis 4: the sleeper gate never started under check.sh"; sed 's/^/      /' "$R4/out" | tail -5
fi
_kill_survivors

echo "axis 5: SIGKILL of the driver's parent leaves nothing of a DRIVER-run gate"
M5="$T/m5"; mkdir -p "$M5"
_mk_sleeper "$T/g5.sh" "$M5"
( sh -c 'echo $$ > "$0"; "$1" --gate-row "$2" > "$3" 2>&1 & sleep 30' \
      "$T/p5.pid" "$RUN_BIN" "$T/g5.sh" "$T/g5.out" ) > /dev/null 2>&1 &
J5=$!
if _wait_file "$M5/bg.pid" && _wait_file "$T/p5.pid"; then
    sleep 0.3
    kill -9 "$(cat "$T/p5.pid")" 2>/dev/null; wait "$J5" 2>/dev/null
    sleep 1.5
    NS=$(_survivors | grep -c . || true)
    [ "$NS" = "0" ] || _fail "axis 5: $NS process(es) of a driver-run gate survived the driver's SIGKILLed parent"
    [ "$(_scratch_gone "$M5")" = "gone" ] || _fail "axis 5: the driver-run gate's EXIT trap did not run"
else
    _fail "axis 5: the sleeper never started under --gate-row"; sed 's/^/      /' "$T/g5.out" | tail -5
fi
_kill_survivors

echo "axis 6: a deadline kill takes the grandchildren and still runs the EXIT trap"
M6="$T/m6"; mkdir -p "$M6"
_mk_sleeper "$T/g6.sh" "$M6"
RC6=0
CYRIUS_CHECK_LONG_TIMEOUT=2 "$RUN_BIN" --run-gate "$T/g6.sh" > "$T/g6.out" 2>&1 || RC6=$?
[ "$RC6" = "124" ] || _fail "axis 6: a deadline-killed gate exited $RC6, expected 124"
grep -q "TIMEOUT: $T/g6.sh.*CYRIUS_CHECK_LONG_TIMEOUT=2s" "$T/g6.out" || _fail "axis 6: no TIMEOUT line naming the gate and CYRIUS_CHECK_LONG_TIMEOUT=2s"
NS=$(_survivors | grep -c . || true)
[ "$NS" = "0" ] || _fail "axis 6: $NS grandchild(ren) survived the deadline"
[ "$(_scratch_gone "$M6")" = "gone" ] || _fail "axis 6: the EXIT trap did not run on a deadline kill — mktemp dir left"
_kill_survivors

echo "axis 6b: through check.sh, the deadline is a TIMEOUT line and a counted failure"
R6="$T/r6"; _mk_chkroot "$R6" "$ROOT/scripts/check.sh"
RC6B=0
( cd "$R6" && env -u CYRIUS_HOME HOME="$R6/home" TMPDIR="$R6/tmp" CYRIUS_CHECK_LONG_TIMEOUT=2 \
    sh scripts/check.sh zzsleeper ) > "$R6/out" 2>&1 || RC6B=$?
[ "$RC6B" = "1" ] || _fail "axis 6b: a check.sh run whose gate timed out exited $RC6B, expected 1"
grep -q '\^\^ TIMEOUT (killed at the CYRIUS_CHECK_LONG_TIMEOUT deadline): tests/gates/zzsup/zzsleeper.sh' "$R6/out" \
    || _fail "axis 6b: no '^^ TIMEOUT' line naming the gate"
grep -q 'timeouts:    1 of those failures' "$R6/out" || _fail "axis 6b: the summary does not count the timeout"
NS=$(_survivors | grep -c . || true)
[ "$NS" = "0" ] || _fail "axis 6b: $NS process(es) survived the deadline"
_kill_survivors
# A malformed knob is said ONCE, by check.sh, and dropped — never silently a 0 (no deadline).
( cd "$R6" && env -u CYRIUS_HOME HOME="$R6/home" TMPDIR="$R6/tmp" CYRIUS_CHECK_LONG_TIMEOUT=' 2' \
    sh scripts/check.sh --resolve zzsleeper ) > "$R6/knob.out" 2>&1
[ "$(grep -c "CYRIUS_CHECK_LONG_TIMEOUT=' 2' is not a whole number" "$R6/knob.out")" = "1" ] \
    || _fail "axis 6b: check.sh did not refuse CYRIUS_CHECK_LONG_TIMEOUT=' 2' exactly once"

echo "axis 7: SIGTERM of check.sh returns within seconds while a gate sleeps"
R7="$T/r7"; _mk_chkroot "$R7" "$ROOT/scripts/check.sh"
if _start_chk "$R7"; then
    sleep 0.3
    kill -TERM "$CHK" 2>/dev/null
    # Bounded: the defect is that check.sh does NOT return, so waiting on it unguarded would
    # hang this gate for the gate's whole sleep (measured: 315 s against the pre-6.6.8 shape).
    _k=0
    while kill -0 "$CHK" 2>/dev/null && [ "$_k" -lt 100 ]; do sleep 0.1; _k=$((_k + 1)); done
    if kill -0 "$CHK" 2>/dev/null; then
        _fail "axis 7: check.sh was still running 10 s after SIGTERM — the signal waits for the gate"
        kill -9 "$CHK" 2>/dev/null
    fi
    RC7=0; wait "$CHK" 2>/dev/null || RC7=$?
    [ "$_k" -le 40 ] || _fail "axis 7: check.sh took more than 4 s to honour SIGTERM"
    [ "$RC7" = "143" ] || _fail "axis 7: check.sh exited $RC7 on SIGTERM, expected 143"
    grep -q "INTERRUPTED by SIGTERM" "$R7/out" || _fail "axis 7: the summary does not say the run was interrupted"
    sleep 0.3
    NS=$(_survivors | grep -c . || true)
    [ "$NS" = "0" ] || _fail "axis 7: $NS process(es) of the gate survived SIGTERM of check.sh"
    [ "$(_scratch_gone "$R7/m")" = "gone" ] || _fail "axis 7: the gate's EXIT trap did not run on a forwarded SIGTERM"
else
    _fail "axis 7: the sleeper gate never started under check.sh"
fi
_kill_survivors

echo "axis 8: kill -- -PGID still reaches a grandchild (no setsid)"
if command -v setsid > /dev/null 2>&1; then
    R8="$T/r8"; _mk_chkroot "$R8" "$ROOT/scripts/check.sh"
    rm -f "$R8/m/bg.pid"
    ( cd "$R8" && exec setsid env -u CYRIUS_HOME HOME="$R8/home" TMPDIR="$R8/tmp" \
        sh scripts/check.sh zzsleeper ) > "$R8/out" 2>&1 &
    C8=$!
    if _wait_file "$R8/m/bg.pid"; then
        G8=$(ps -o pgid= -p "$C8" 2>/dev/null | tr -d ' ')
        [ "$G8" = "$C8" ] || _fail "axis 8: setsid did not make check.sh a group leader (pgid '$G8', pid $C8)"
        kill -KILL -- "-$G8" 2>/dev/null
        wait "$C8" 2>/dev/null
        sleep 0.5
        NS=$(_survivors | grep -c . || true)
        [ "$NS" = "0" ] || _fail "axis 8: $NS grandchild(ren) escaped a process-group kill — something left the group"
    else
        _fail "axis 8: the sleeper gate never started"
    fi
    _kill_survivors
else
    echo "  SKIP: no setsid(1) on this host"
fi

echo "axis 9: a gate that exits leaving a background process behind leaves nothing running"
M9="$T/m9"; mkdir -p "$M9"
_mk_sleeper "$T/g9.sh" "$M9" exit
RC9=0
"$RUN_BIN" --run-gate "$T/g9.sh" > "$T/g9.out" 2>&1 || RC9=$?
[ "$RC9" = "0" ] || _fail "axis 9: the gate exited 0 but --run-gate returned $RC9"
NS=$(_survivors | grep -c . || true)
[ "$NS" = "0" ] || _fail "axis 9: $NS process(es) the gate left behind are still running"
grep -q "left 1 process(es) running" "$T/g9.out" || _fail "axis 9: the supervisor did not name what the gate left running"
_kill_survivors

echo "axis 10: anti-vacuous — the pre-6.6.8 foreground \`sh \"\$_g\"\` DOES leak"
# The shipped _chk_gate with only its launcher line put back to the old foreground form.
awk '/_chk_run_bg "\$CHECK_BIN" --run-gate "\$_g" "\$@"/ { print "    _grc=0"; print "    sh \"$_g\" \"$@\" || _grc=$?"; print "    _CHK_RC=$_grc"; next } { print }' \
    "$ROOT/scripts/check.sh" > "$T/check_fg.sh"
grep -q '^    sh "\$_g" "\$@" || _grc=\$?$' "$T/check_fg.sh" || _fail "axis 10: could not build the foreground mutant of check.sh"
R10="$T/r10"; _mk_chkroot "$R10" "$T/check_fg.sh"
if _start_chk "$R10"; then
    sleep 0.3
    kill -9 "$CHK" 2>/dev/null; wait "$CHK" 2>/dev/null
    sleep 1
    NS=$(_survivors | grep -c . || true)
    [ "$NS" -ge 1 ] || _fail "axis 10: the foreground mutant leaked NOTHING — the harness cannot see a leak, so axes 4-9 prove nothing"
else
    _fail "axis 10: the sleeper gate never started under the mutant"
fi
_kill_survivors

# Axis 11 — a GROUP signal lets the gate's EXIT trap FINISH. Ctrl-C, `timeout sh check.sh`
# and `kill -- -PGID` reach the gate's shell directly; the supervisor used to answer the
# same signal with its own SIGTERM at once, and bash dies mid-trap on the second one.
echo "axis 11: a group SIGTERM / SIGINT lets the gate's EXIT trap run to its LAST command"
if command -v setsid > /dev/null 2>&1; then
    for _sig in TERM INT; do
        R11="$T/r11$_sig"; _mk_chkroot "$R11" "$ROOT/scripts/check.sh" trap2
        rm -f "$R11/m/bg.pid" "$R11/m/trap.done"
        # INT back to DEFAULT for the run: a `&` job starts with SIGINT ignored, and Ctrl-C
        # at a terminal reaches a foreground run that has it at default.
        _dflt=""
        if [ "$_sig" = INT ]; then
            if env --default-signal=INT true > /dev/null 2>&1; then _dflt="--default-signal=INT"
            else echo "  SKIP (INT half): env(1) has no --default-signal on this host"; continue; fi
        fi
        ( cd "$R11" && exec setsid env $_dflt -u CYRIUS_HOME HOME="$R11/home" TMPDIR="$R11/tmp" \
            sh scripts/check.sh zzsleeper ) > "$R11/out" 2>&1 &
        C11=$!
        if _wait_file "$R11/m/bg.pid"; then
            sleep 0.3
            kill "-$_sig" -- "-$C11" 2>/dev/null
            _k=0
            while kill -0 "$C11" 2>/dev/null && [ "$_k" -lt 150 ]; do sleep 0.1; _k=$((_k + 1)); done
            kill -9 "$C11" 2>/dev/null
            wait "$C11" 2>/dev/null
            sleep 0.5
            [ -s "$R11/m/trap.done" ] || _fail "axis 11 ($_sig): the gate's EXIT trap was cut short — its last command never ran (a second SIGTERM arrived mid-trap)"
            [ "$(_scratch_gone "$R11/m")" = "gone" ] || _fail "axis 11 ($_sig): the gate's mktemp dir was left behind"
            NS=$(_survivors | grep -c . || true)
            [ "$NS" = "0" ] || _fail "axis 11 ($_sig): $NS process(es) survived a group SIG$_sig"
            # Promptly, too: after a Ctrl-C the gate's `sleep &` (a `&` job starts with SIGINT
            # ignored) is adopted still running, and sparing it as well as the gate held the
            # whole grace period (measured: 5 s).
            [ "$_k" -le 40 ] || _fail "axis 11 ($_sig): check.sh took more than 4 s to end on a group SIG$_sig — an adopted orphan waited out the grace period"
        else
            _fail "axis 11 ($_sig): the sleeper gate never started"
        fi
        _kill_survivors
    done
else
    echo "  SKIP: no setsid(1) on this host"
fi

# Axis 12 — 124 is the supervisor's deadline and NOTHING else, with or without a deadline
# set. Under CYRIUS_CHECK_LONG_TIMEOUT=0 a gate's own `exit 124` used to pass straight
# through, and check.sh (and the driver's _gate) reported a deadline that did not exist.
echo "axis 12: a gate's own exit 124 is reported as 1, never as a TIMEOUT — deadline or not"
printf '#!/bin/sh\nexit 124\n' > "$T/g12.sh"
for _lt in 0 30; do
    RC12=0
    CYRIUS_CHECK_LONG_TIMEOUT=$_lt "$RUN_BIN" --run-gate "$T/g12.sh" > "$T/g12.out" 2>&1 || RC12=$?
    [ "$RC12" = "1" ] || _fail "axis 12 (LONG_TIMEOUT=$_lt): a gate's own exit 124 came back as $RC12, expected 1"
    grep -q "exited 124 on its own" "$T/g12.out" || _fail "axis 12 (LONG_TIMEOUT=$_lt): the remap is not said"
done
R12="$T/r12"; _mk_chkroot "$R12" "$ROOT/scripts/check.sh"
printf '#!/bin/sh\nexit 124\n' > "$R12/tests/gates/zzsup/zzsleeper.sh"
( cd "$R12" && env -u CYRIUS_HOME HOME="$R12/home" TMPDIR="$R12/tmp" CYRIUS_CHECK_LONG_TIMEOUT=0 \
    sh scripts/check.sh zzsleeper ) > "$R12/out" 2>&1
grep -q 'TIMEOUT' "$R12/out" && _fail "axis 12: check.sh reported a TIMEOUT under CYRIUS_CHECK_LONG_TIMEOUT=0 (no deadline exists)"
grep -q '\^\^ FAILED (exit 1): tests/gates/zzsup/zzsleeper.sh' "$R12/out" \
    || _fail "axis 12: check.sh did not record the gate as an ordinary failure (exit 1)"
fi

echo ""
if [ "$FAILS" = "0" ]; then
    echo "PASS: the check driver dies with the run that started it"
    exit 0
fi
echo "FAILED: $FAILS assertion(s)"
exit 1
