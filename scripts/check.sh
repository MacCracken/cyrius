#!/bin/sh
# scripts/check.sh — thin shim around programs/checks/main.cyr.
#
# v5.9.1 (2026-05-06) — first slot of the v5.9.x sovereignty pass
# (bash-toolchain → cyrius). The dispatcher logic that used to live
# here (~743 LOC of bash) moved into cyrius. At v6.0.90 the monolithic
# programs/check.cyr (10.2K LoC) was split into programs/checks/
# (slim dispatcher main.cyr + per-suite files). This shim:
#   1. cd's to the repo root so child gates see the expected CWD,
#   2. builds build/cyrius_check on demand (mirrors the v5.8.44
#      auto-build pattern for build/cyrius_api_surface),
#   3. runs the binary and exits with its status — NEVER `exec`, because the
#      EXIT trap that removes the staged CYRIUS_HOME must run. CHANGELOG [6.6.6]
#
# USAGE: `sh scripts/check.sh` is the full run. `sh scripts/check.sh <selector>` runs ONE
# driver suite, one gate bucket or one gate; `--list` prints every selector and an
# unrecognised one exits 2 listing them. Both selector vocabularies are DERIVED from the
# registrations (the driver's own suite table; this file's `_chk_gate` lines plus the
# `_gate(…, "tests/gates/…")` literals in programs/checks/*.cyr), never written down twice.
# CHANGELOG [6.6.6]
#
# The fmt/lint walkers live in lib/audit_walk.cyr only (the driver's fmt + lint suites and
# `cyrius audit` share them). Their bash twin scripts/lib/audit-walk.sh had no caller left
# and was deleted at 6.6.7.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── ⛔ v6.6.6: EVERY GATE RUNS, AND THE VERDICT IS THE SUMMARY AT THE END ─────────────
#
# THE DEFECT. This script is `set -e` and used to invoke the check binary as a bare
# `"$CHECK_BIN"`, then the shell gates below it as bare `sh "$ROOT/tests/gates/…"`. So the
# FIRST red row anywhere aborted the whole script: one failing row in the checks driver —
# a stale doc stamp, say — and NOT ONE of the shell gates after it ever executed, while the
# binary's own "N passed, M failed" line was the last thing printed and read exactly like a
# full run. Measured this release: bite 14's genuinely RED `method_call_runs_every_callee`
# gate was invisible for a whole slot behind a stale doc-stamp row. A suite that stops at
# the first failure reports the first failure, not the state of the tree.
#
# THE RULE, and it is the reason for the manifest below: a gate that did not run is NOT a
# pass and must never be summarised as one. The expected gate list is derived from THIS
# FILE'S OWN SOURCE (`^_chk_gate "$ROOT/…"`), so it cannot drift from the calls; anything on
# that list with no recorded result is printed under NOT RUN. The summary is an EXIT trap,
# so it prints even if something aborts the script anyway — an abort then shows up as a
# long NOT RUN list rather than as silence. CHANGELOG [6.6.6]
_CHK_RESULTS=""       # one "<STATUS> <name>" line per gate that produced a result
_CHK_FAILS=0
_CHK_STAGED_DIR=""    # the throwaway CYRIUS_HOME to remove, when we staged one
_CHK_STARTED=0        # 1 once we are past setup, i.e. once a summary is meaningful
_CHK_DRIVER="programs/checks (the cyrius check binary)"

# The shell gates this script is supposed to run, read back out of its OWN source. One
# reader for the summary and for the selector below, so a targeted run and the NOT RUN
# bookkeeping can never disagree about what the registered set is.
_chk_shell_manifest() {
    grep -oE '^_chk_gate "\$ROOT/[^"]+"' "$ROOT/scripts/check.sh" \
        | sed 's|^_chk_gate "\$ROOT/||; s|"$||'
}
# What THIS run is expected to produce results for. A full run expects all of them; a
# targeted shell-gate run narrows it, so the summary does not report the rest as NOT RUN.
_CHK_MANIFEST=$(_chk_shell_manifest)

# ⛔ 6.6.8 — EVERY CHILD RUNS AS `& wait`, UNDER THE SUPERVISOR, AND A SIGNAL IS FORWARDED.
# A gate used to run as a foreground `sh "$_g"` and the driver as a foreground `"$CHECK_BIN"`.
# Three measured defects came with that:
#   * POSIX runs a trap only after the FOREGROUND command returns, so `kill <this pid>` did
#     nothing until the current gate finished — and when the driver was that command, until
#     the whole ~13-minute driver run finished. `wait` is interruptible; a foreground child
#     is not. So each child runs in the background and is waited for, and the INT/TERM/HUP
#     traps below forward SIGTERM to it (TERM, not the signal received: a `&` job starts with
#     SIGINT ignored, and that ignore is inherited) and wait for it before the summary.
#   * a SIGKILLed check.sh left the gate's sh at PPID=1 with its children alive, and no gate
#     run here had any deadline. Each gate now runs under `cyrius_check --run-gate`
#     (programs/checks/run_gate.cyr): a subreaper in THIS process group (no setsid, so
#     Ctrl-C, `timeout sh check.sh` and `kill -- -PGID` keep reaching everything) with
#     PDEATHSIG, the CYRIUS_CHECK_LONG_TIMEOUT deadline, and TERM -> grace -> KILL of the
#     gate's whole tree so its EXIT trap still removes its mktemp dir.
#   * the driver supervises itself the same way (it re-execs under the supervisor), so a
#     forwarded TERM ends ITS tree in order too. CHANGELOG [6.6.8]
_CHK_CHILD=""
_CHK_RC=0
_chk_run_bg() {
    "$@" &
    _CHK_CHILD=$!
    _CHK_RC=0
    wait "$_CHK_CHILD" || _CHK_RC=$?
    _CHK_CHILD=""
    return 0
}

# Run one shell gate. ALWAYS returns 0 — `set -e` must not turn a red gate into an abort;
# the tally is the verdict.
_chk_gate() {
    _g=$1
    shift
    _gn=${_g#"$ROOT/"}
    if [ ! -f "$_g" ]; then
        echo "  FAIL: $_gn — gate script is MISSING"
        _CHK_RESULTS="$_CHK_RESULTS
MISSING $_gn"
        _CHK_FAILS=$((_CHK_FAILS + 1))
        return 0
    fi
    if [ "$_CHK_PAR" = 1 ]; then _chk_enqueue "$_g"; return 0; fi
    _chk_run_bg "$CHECK_BIN" --run-gate "$_g" "$@"
    _chk_score "$_gn" "$_CHK_RC"
    return 0
}
# The verdict of one gate run: `$1` its name, `$2` the exit status `--run-gate` reported.
_chk_score() {
    _gn=$1
    _grc=$2
    if [ "$_grc" = 0 ]; then
        _CHK_RESULTS="$_CHK_RESULTS
PASS $_gn"
    elif [ "$_grc" = 77 ]; then
        # ⛔ 6.6.11: 77 is the gate saying it could NOT run its check (a missing tool, host or
        # fixture — its own SKIP line above says which). It used to have no way to say so but
        # `exit 0`, and was scored PASS. A SKIP is its own result and its own count, never a
        # pass; under CYRIUS_CHECK_NO_SKIP=1 it is a FAIL — the same rule the driver's rows
        # follow (`_gate_score` in programs/checks/main.cyr). CHANGELOG [6.6.11]
        if [ "$_CHK_NO_SKIP" = 1 ]; then
            echo "  ^^ SKIP REFUSED (CYRIUS_CHECK_NO_SKIP=1 — a gate that could not run is a FAIL): $_gn"
            _CHK_RESULTS="$_CHK_RESULTS
FAIL $_gn"
            _CHK_FAILS=$((_CHK_FAILS + 1))
        else
            echo "  ^^ SKIP (exit 77 — the gate could not run its check; NOT a pass): $_gn"
            _CHK_RESULTS="$_CHK_RESULTS
SKIP $_gn"
            _CHK_SKIPS=$((_CHK_SKIPS + 1))
        fi
    elif [ "$_grc" = 124 ]; then
        # 124 from --run-gate is its deadline and nothing else (a gate's own 124 is reported
        # as 1 — programs/checks/run_gate.cyr). A timeout is a failure, and says it was one.
        # CHANGELOG [6.6.8]
        echo "  ^^ TIMEOUT (killed at the CYRIUS_CHECK_LONG_TIMEOUT deadline): $_gn"
        _CHK_RESULTS="$_CHK_RESULTS
FAIL $_gn"
        _CHK_FAILS=$((_CHK_FAILS + 1))
        _CHK_TIMEOUTS=$((_CHK_TIMEOUTS + 1))
    else
        echo "  ^^ FAILED (exit $_grc): $_gn"
        _CHK_RESULTS="$_CHK_RESULTS
FAIL $_gn"
        _CHK_FAILS=$((_CHK_FAILS + 1))
    fi
    return 0
}

# The driver's verdict (`$1`, its exit status) and its SKIP rows (`--skip-report`) into the tally.
_chk_driver_result() {
    _CHK_DRIVER_RC=$1
    while IFS= read -r _dsk || [ -n "$_dsk" ]; do
        [ -n "$_dsk" ] || continue
        _CHK_RESULTS="$_CHK_RESULTS
DSKIP $_dsk"
        _CHK_DRV_SKIPS=$((_CHK_DRV_SKIPS + 1))
    done < "$_CHK_DRV_SKIPS_F"
    _CHK_SKIPS=$((_CHK_SKIPS + _CHK_DRV_SKIPS))
    if [ "$_CHK_DRIVER_RC" = "0" ]; then
        _CHK_RESULTS="$_CHK_RESULTS
PASS $_CHK_DRIVER"
    else
        _CHK_RESULTS="$_CHK_RESULTS
FAIL $_CHK_DRIVER"
        _CHK_FAILS=$((_CHK_FAILS + 1))
        echo ""
        echo "  ^^ FAILED (exit $_CHK_DRIVER_RC): $_CHK_DRIVER"
        echo "  CONTINUING — the shell gates below still run; the verdict is the summary at the end."
    fi
    return 0
}

# 6.7.0 — the parallel full run (see the driver block below for why). Worker count: CYRIUS_CHECK_JOBS
# (1 = the serial run), default half the online CPUs, capped at 8.
_chk_jobs() {
    _j="${CYRIUS_CHECK_JOBS:-}"
    if [ -z "$_j" ]; then
        _j=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
        case "$_j" in ''|*[!0-9]*) _j=2 ;; esac
        _j=$((_j / 2))
        if [ "$_j" -gt 8 ]; then _j=8; fi
        if [ "$_j" -lt 1 ]; then _j=1; fi
    fi
    case "$_j" in
        ''|*[!0-9]*|0) printf "error: CYRIUS_CHECK_JOBS must be a positive integer (1 = serial); got '%s'\n" "$_j" >&2; exit 2 ;;
    esac
    echo "$_j"
}
# A gate for the pool, or — `# check: serial` in its text — for the quiet run after it.
_chk_enqueue() {
    if grep -q '^# check: serial' "$1" 2>/dev/null; then echo "$1" >> "$_CHK_PDIR/serial"
    else echo "$1" >> "$_CHK_PDIR/queue"; fi
    return 0
}
# Start the driver in the background (its `_gate` rows skipped) and queue its gate scripts.
_chk_par_start() {
    _chk_driver_gate_manifest | while IFS= read -r _m; do [ -n "$_m" ] && _chk_enqueue "$ROOT/$_m"; done
    CYRIUS_CHECK_GATES_ELSEWHERE=1 "$CHECK_BIN" --skip-report "$_CHK_DRV_SKIPS_F" > "$_CHK_PDIR/driver.log" 2>&1 &
    _CHK_DRV_PID=$!
    _CHK_CHILD="$_CHK_DRV_PID"
    echo "check: PARALLEL run — the driver in the background; every gate script queued for a pool of $_CHK_JOBS (CYRIUS_CHECK_JOBS=1 for the serial run)"
    return 0
}
# Run the pool, wait for the driver, run the serial gates, then report everything in order.
_chk_par_drain() {
    [ "$_CHK_PAR" = 1 ] || return 0
    cat > "$_CHK_PDIR/one.sh" <<'ONE'
echo $$ >> "$CHK_PD/pids"
i=${1%% *}
g=${1#* }
"$CHK_BIN" --run-gate "$g" > "$CHK_PD/$i.log" 2>&1
echo $? > "$CHK_PD/$i.rc"
ONE
    awk '{print NR " " $0}' "$_CHK_PDIR/queue" > "$_CHK_PDIR/numbered"
    CHK_PD="$_CHK_PDIR" CHK_BIN="$CHECK_BIN" xargs -P "$_CHK_JOBS" -I{} sh "$_CHK_PDIR/one.sh" {} < "$_CHK_PDIR/numbered" &
    _xp=$!
    _CHK_CHILD="$_CHK_DRV_PID $_xp"
    _CHK_RC=0
    wait "$_xp" || true
    wait "$_CHK_DRV_PID" || _CHK_RC=$?
    _CHK_CHILD=""
    cat "$_CHK_PDIR/driver.log"
    _chk_driver_result "$_CHK_RC"
    while IFS= read -r _ln; do
        _i=${_ln%% *}
        _g=${_ln#* }
        cat "$_CHK_PDIR/$_i.log" 2>/dev/null
        _r=$(cat "$_CHK_PDIR/$_i.rc" 2>/dev/null || echo 1)
        _chk_score "${_g#"$ROOT/"}" "$_r"
    done < "$_CHK_PDIR/numbered"
    if [ -s "$_CHK_PDIR/serial" ]; then
        echo "check: the $(wc -l < "$_CHK_PDIR/serial" | tr -d ' ') \`# check: serial\` gate(s), alone:"
        _CHK_PAR=0
        while IFS= read -r _g; do _chk_gate "$_g"; done < "$_CHK_PDIR/serial"
        _CHK_PAR=1
    fi
    return 0
}

_CHK_DONE=0
_CHK_SIGNAL=""
_CHK_TIMEOUTS=0
_CHK_SKIPS=0
_CHK_DRV_SKIPS=0        # of _CHK_SKIPS, the driver's own SKIP rows (its --skip-report)
_CHK_DRV_SKIPS_F=""
_CHK_DRV_SKIPS_RM=""    # the private dir holding it, when no staged home did
_CHK_PAR=0              # 6.7.0: 1 = this full run is the PARALLEL one (_chk_par_*)
_CHK_PDIR=""            # its private work dir (queue, per-gate logs and exit codes)
_CHK_DRV_PID=
_CHK_NO_SKIP=0
# CYRIUS_CHECK_NO_SKIP: "1" = a gate that exits 77 (could not run) is a FAIL; unset, empty or
# "0" = it is reported and counted as a SKIP. Anything else is REFUSED (exit 2) — `=true` or
# `=yes` silently meaning "off" would make the strict mode a no-op. The SAME contract as the
# driver's `_read_no_skip` (programs/checks/main.cyr), which reads the same variable for its
# own rows; this file used to read it not at all. Called only once a RUN is about to start
# (`--list` / `--resolve` / `--registry` run nothing and ignore it). CHANGELOG [6.6.11]
_chk_read_no_skip() {
    case "${CYRIUS_CHECK_NO_SKIP:-}" in
        ''|0) _CHK_NO_SKIP=0 ;;
        1)    _CHK_NO_SKIP=1 ;;
        *)    printf "error: CYRIUS_CHECK_NO_SKIP must be 1 (a SKIP gate fails) or 0/unset; got '%s'\n" \
                  "$CYRIUS_CHECK_NO_SKIP" >&2
              exit 2 ;;
    esac
}
_chk_finish() {
    _xrc=$?
    # INT/TERM handlers `exit`, which re-enters via the EXIT trap in some shells.
    if [ "$_CHK_DONE" = "1" ]; then exit "$_xrc"; fi
    _CHK_DONE=1
    case "$_CHK_SIGNAL" in
        INT)  _xrc=130 ;;
        TERM) _xrc=143 ;;
        HUP)  _xrc=129 ;;
    esac
    if [ -n "$_CHK_STAGED_DIR" ]; then rm -rf "$_CHK_STAGED_DIR"; fi
    if [ -n "$_CHK_DRV_SKIPS_RM" ]; then rm -rf "$_CHK_DRV_SKIPS_RM"; fi
    if [ -n "$_CHK_PDIR" ]; then rm -rf "$_CHK_PDIR"; fi
    # A run interrupted while building the driver leaves its per-run side files (6.6.20).
    if [ -n "${_CHK_BIN_NEW:-}" ]; then rm -f "$_CHK_BIN_NEW" "$_CHK_BIN_ERR"; fi
    if [ "$_CHK_STARTED" != "1" ]; then exit "$_xrc"; fi

    # Everything THIS run is supposed to have produced a result for (the full registered
    # set, or the subset a targeted run selected — see _CHK_MANIFEST).
    _manifest="$_CHK_MANIFEST"
    _total=$(printf '%s\n' "$_manifest" | grep -c . || true)
    _notrun=""
    _nnot=0
    for _m in $_manifest; do
        if ! printf '%s\n' "$_CHK_RESULTS" | grep -qx "PASS $_m"; then
            if ! printf '%s\n' "$_CHK_RESULTS" | grep -qxE "(FAIL|MISSING|SKIP) $_m"; then
                _notrun="$_notrun $_m"
                _nnot=$((_nnot + 1))
            fi
        fi
    done
    echo ""
    echo "── check.sh summary ────────────────────────────────────────────────"
    # Two INDEPENDENTLY derived numbers that have to add up: results recorded (counted
    # from the tally) and gates with no result (counted from the manifest). If they do not
    # sum to the registered total, this bookkeeping is itself broken — say so rather than
    # printing a self-consistent lie, which is the failure mode this whole block exists for.
    _res_n=$(printf '%s\n' "$_CHK_RESULTS" | grep -cE '^(PASS|FAIL|MISSING|SKIP) (tests/gates|scripts)/' || true)
    printf '  shell gates: %s of %s produced a result, %s NOT RUN\n' "$_res_n" "$_total" "$_nnot"
    printf '  failures:    %s (the check binary counts as one row here)\n' "$_CHK_FAILS"
    printf '  skipped:     %s (%s shell gate(s) exited 77 + %s driver row(s) — could not run their check; NOT passes%s)\n' \
        "$_CHK_SKIPS" "$((_CHK_SKIPS - _CHK_DRV_SKIPS))" "$_CHK_DRV_SKIPS" \
        "$( [ "$_CHK_NO_SKIP" = 1 ] && echo '' || echo '; CYRIUS_CHECK_NO_SKIP=1 makes them failures' )"
    if [ "$_CHK_TIMEOUTS" != "0" ]; then
        printf '  timeouts:    %s of those failures were a gate killed at its deadline (CYRIUS_CHECK_LONG_TIMEOUT) — see the TIMEOUT lines\n' "$_CHK_TIMEOUTS"
    fi
    if [ "$((_res_n + _nnot))" != "$_total" ]; then
        printf '  ⚠ BOOKKEEPING: %s + %s != %s — this summary cannot be trusted\n' \
            "$_res_n" "$_nnot" "$_total"
    fi
    if [ "$_CHK_FAILS" != "0" ]; then
        echo "  FAILED:"
        printf '%s\n' "$_CHK_RESULTS" | grep -E '^(FAIL|MISSING) ' | sed 's/^/    /'
    fi
    if [ "$_CHK_SKIPS" != "0" ]; then
        echo "  SKIPPED — these ran but could not check anything, and are NOT passes:"
        printf '%s\n' "$_CHK_RESULTS" | grep -E '^SKIP ' | sed 's/^SKIP /    /'
        printf '%s\n' "$_CHK_RESULTS" | grep -E '^DSKIP ' | sed 's/^DSKIP /    (driver row) /'
    fi
    if [ "$_nnot" != "0" ]; then
        echo "  NOT RUN — these did NOT execute and are NOT passes:"
        for _m in $_notrun; do echo "    $_m"; done
    fi
    if [ -n "$_CHK_SIGNAL" ]; then
        echo "  INTERRUPTED by SIG$_CHK_SIGNAL — the running child was sent SIGTERM and waited for"
        echo "────────────────────────────────────────────────────────────────────"
        exit "$_xrc"
    fi
    if [ "$_CHK_FAILS" = "0" ] && [ "$_nnot" = "0" ] && [ "$_CHK_SKIPS" != "0" ]; then
        echo "  GREEN, with $_CHK_SKIPS gate(s) SKIPPED — no failure, but not everything was checked"
        echo "────────────────────────────────────────────────────────────────────"
        exit "$_xrc"
    fi
    if [ "$_CHK_FAILS" = "0" ] && [ "$_nnot" = "0" ]; then
        echo "  ALL GREEN"
        echo "────────────────────────────────────────────────────────────────────"
        exit "$_xrc"
    fi
    echo "────────────────────────────────────────────────────────────────────"
    exit 1
}
# INT/TERM as well as EXIT: interrupting a long run is exactly when you most need to be
# told which gates never executed, and dash does not run an EXIT trap on an untrapped INT.
# 6.6.8: the signal is FORWARDED (as SIGTERM) to the child being waited for, and that child
# is waited for, before the summary — see _chk_run_bg.
_chk_on_signal() {
    _CHK_SIGNAL=$1
    if [ -n "$_CHK_CHILD" ]; then
        # shellcheck disable=SC2086 — a list of pids in a parallel run (_chk_par_drain)
        kill -TERM $_CHK_CHILD 2>/dev/null || true
        if [ -n "$_CHK_PDIR" ] && [ -f "$_CHK_PDIR/pids" ]; then kill -TERM $(cat "$_CHK_PDIR/pids") 2>/dev/null || true; fi
        wait $_CHK_CHILD 2>/dev/null || true
    fi
    _chk_finish
}
trap _chk_finish EXIT
trap '_chk_on_signal INT' INT
trap '_chk_on_signal TERM' TERM
trap '_chk_on_signal HUP' HUP

# ── v6.6.6 (bite 27b): REAP THE STAGED HOMES A KILLED RUN LEFT BEHIND ────────────────
#
# THE DEFECT. The EXIT/INT/TERM trap above removes this run's staged CYRIUS_HOME, and bite
# 25b fixed the one path that escaped it. Neither can help with SIGKILL: no trap runs, and
# the ~19 MB tree stays in $TMPDIR for ever. Five of them (95 MB) were sitting in /tmp when
# this was written, the oldest three hours old, on a box where /tmp is RAM.
#
# ⚠ REAPED BY AGE AND BY OWNERSHIP, NEVER BY COUNT — the same rule, and for the same
# reason, as cross-os-selfhost.sh's `_co_reap_stale` for its `_cyaud_*` staging dirs: "keep
# the newest N" deletes a LIVE run's tree the moment two runs overlap, and several lanes run
# check.sh at once on this box. So a home is reclaimed only when BOTH hold:
#   * it has not been touched for $CYRIUS_CHECK_REAP_MINS minutes (default 240 — a full run
#     is ~13 minutes, so four hours is finished by definition), AND
#   * the run that created it is gone. Every home carries `.owner`, written with the
#     creating shell's PID as the FIRST thing after mktemp, so the window in which a live
#     home looks unowned is microseconds; `kill -0` is the liveness oracle, and a PID we
#     cannot signal counts as ALIVE (the safe direction — we decline to delete).
# Best-effort throughout: a reap that fails must never fail the run.
#
# ⛔ VALIDATE THE KNOB BEFORE USING IT — it is the age gate's only input and a bad value
# turns the gate OFF, not up. As first written this was used raw in `[ "$_CHK_REAP_MINS"
# -gt 0 ]`, so `CYRIUS_CHECK_REAP_MINS=4h` made that test ERROR (`[: 4h: integer expected`,
# rc 2 → false), the `-mmin` filter was skipped, and EVERY unowned home became eligible
# whatever its age — measured: a two-minute-old home was reaped. That is live on this box,
# where lanes running a check.sh older than this change stage homes with no `.owner` at
# all: one typo'd env var and a running lane's home is deleted. Same `*[!0-9]*` guard
# `_chk_home_is_owned` already applies to the `.owner` PID, and it is LOUD — a knob that
# silently did not mean what you typed is how this defect got written in the first place.
# CHANGELOG [6.6.6]
_CHK_REAP_MINS="${CYRIUS_CHECK_REAP_MINS:-240}"
case "$_CHK_REAP_MINS" in
    ''|*[!0-9]*)
        printf "check: CYRIUS_CHECK_REAP_MINS='%s' is not a whole number of minutes — using 240\n" \
            "$_CHK_REAP_MINS" >&2
        _CHK_REAP_MINS=240
        ;;
esac
# ⛔ 6.6.8: the two DEADLINE knobs, checked once here the same way. The binary read them with
# atoi, so `2m` meant 2 s and `abc`, '' or ` 120` meant 0 — which DISABLES the deadline. The
# binary now refuses a non-digit value itself (lib/regression.cyr), but every child it spawns
# would say so again; here it is said once and the variable is dropped, so every child uses
# the default. 0 stays valid: it is the documented "no deadline". At most 9 digits, the
# binary's own limit — a longer value passed here and was then refused by every child, once
# each, which is the repetition this block exists to stop. CHANGELOG [6.6.8]
for _kv in CYRIUS_CHECK_TIMEOUT CYRIUS_CHECK_LONG_TIMEOUT; do
    eval "_kval=\${$_kv-__unset__}"
    case "$_kval" in
        __unset__) ;;
        ''|*[!0-9]*|??????????*)
            printf "check: %s='%s' is not a whole number of seconds (digits only, at most 9) — IGNORED, the default deadline stays in force\n" \
                "$_kv" "$_kval" >&2
            unset "$_kv"
            ;;
    esac
done
_chk_home_is_owned() {
    [ -f "$1/.owner" ] || return 1
    _op=$(cat "$1/.owner" 2>/dev/null || true)
    case "$_op" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "$_op" 2>/dev/null
}
_chk_reap_stale_homes() {
    _rtmp="${TMPDIR:-/tmp}"
    [ -d "$_rtmp" ] || return 0
    _reaped=0
    for _h in "$_rtmp"/cyrius-check-home.*; do
        [ -d "$_h" ] || continue
        if [ "$_CHK_REAP_MINS" -gt 0 ]; then
            # find is the age oracle; -mmin/-maxdepth are POSIX and present on BSD find too.
            [ -n "$(find "$_h" -maxdepth 0 -type d -mmin +"$_CHK_REAP_MINS" 2>/dev/null)" ] || continue
        fi
        if _chk_home_is_owned "$_h"; then continue; fi
        rm -rf "$_h" 2>/dev/null || true
        [ -d "$_h" ] || _reaped=$((_reaped + 1))
    done
    if [ "$_reaped" -gt 0 ]; then
        printf "check: reaped %s stale staged CYRIUS_HOME tree(s) in %s (unowned, older than %s min)\n" \
            "$_reaped" "$_rtmp" "$_CHK_REAP_MINS"
    fi
}
_chk_reap_stale_homes

# ── 6.6.20: the CLI's own temp dirs, left by a process that died without cleaning up ──
# `cyrius` makes `$TMPDIR/cyrius-<pid>[-t<nonce>][-<n>]` and removes it on a NORMAL exit only
# (`_cbt_tmpdir_cleanup`, cbt/build.cyr). A signal death skips that — SIGPIPE from
# `cyrius … | head` leaves an EMPTY dir, SIGKILL leaves `test_bin` / `cc_err` — and the
# installed 6.6.0–6.6.5 CLIs never cleaned up at all, so the dirs pile up by the hundred.
# The same rule as the homes above: by AGE ($CYRIUS_CHECK_REAP_MINS) and by OWNERSHIP (the
# pid in the NAME is dead to both `kill -0` and `ps -p` — a pid we cannot signal is not
# dead), never by count; only names of exactly that shape, only dirs this user owns. And
# `rmdir` ONLY: a NON-empty leftover is the CLI's post-mortem contract (a SIGKILLed test's
# binary; the `cyrius lsp` build it tells the user to copy out), so it is never deleted
# here. Best-effort: a reap that fails never fails the run. CHANGELOG [6.6.20]
_chk_pid_alive() {
    kill -0 "$1" 2>/dev/null && return 0
    ps -p "$1" > /dev/null 2>&1
}
_chk_reap_dead_cli_tmpdirs() {
    _rtmp="${TMPDIR:-/tmp}"
    [ -d "$_rtmp" ] || return 0
    _reaped=0
    for _d in "$_rtmp"/cyrius-[0-9]*; do
        [ -d "$_d" ] && [ ! -L "$_d" ] && [ -O "$_d" ] || continue
        _r=${_d##*/}
        _r=${_r#cyrius-}
        case "$_r" in *[!0-9t-]*) continue ;; esac
        _pid=${_r%%-*}
        case "$_pid" in ''|*[!0-9]*) continue ;; esac
        case "${_r#"$_pid"}" in ''|-t[0-9]*|-[0-9]*) ;; *) continue ;; esac
        if [ "$_CHK_REAP_MINS" -gt 0 ]; then
            [ -n "$(find "$_d" -maxdepth 0 -type d -mmin +"$_CHK_REAP_MINS" 2>/dev/null)" ] || continue
        fi
        _chk_pid_alive "$_pid" && continue
        rmdir "$_d" 2>/dev/null && _reaped=$((_reaped + 1))
    done
    if [ "$_reaped" -gt 0 ]; then
        printf "check: reaped %s empty cyrius-<pid> temp dir(s) in %s (their process is gone, older than %s min)\n" \
            "$_reaped" "$_rtmp" "$_CHK_REAP_MINS"
    fi
    return 0
}
_chk_reap_dead_cli_tmpdirs

# ── v6.6.4: the suite runs against a THROWAWAY CYRIUS_HOME staged from the working tree ──
#
# Gates that stage a consumer pinned at `cyrius = "$(cat VERSION)"` resolve their stdlib
# and wrapper from `$CYRIUS_HOME/versions/<VERSION>/`. Between a tag and the next bump
# that slot is the RELEASED snapshot, so a mid-slot lib/ or cbt/ change was invisible to
# them — and the documented workaround (copy lib/ into the released slot, or run the
# same-version `version-bump.sh`) was the exact write that corrupted the installed 6.6.1
# and 6.6.2 stdlibs (issues/archived/2026-09-13-hisab-refresh-only-overwrites-released-snapshot.md).
# install.sh now REFUSES that write. So the suite stages its own home: `versions/<VERSION>`
# is populated from the tree by `install.sh --refresh-only` (a fresh mktemp home never held
# a release, so no override is needed), every OTHER slot of the live store and the dep cache
# are aliased in read-only-by-convention (older pins and sibling checkouts keep resolving),
# and the live store is never written. Set CYRIUS_HOME yourself to bypass the staging.
# ⚠ Side effects of the staging run, inherited from --refresh-only: stale gitignored build/*
# bins are rebuilt from the tree (cycc_win unconditionally) and .git/hooks/pre-commit is
# (re)installed — the same things every version-bump does. PATH is prefixed with the staged
# bin/ so `command -v cyrius` is the TREE-BUILT wrapper: the live one returns early from
# `_try_redirect_to_pinned` when a consumer's pin equals its own version, so a consumer
# pinned at VERSION would otherwise be served by the RELEASED cbt, and a cbt regression in
# the tree would pass twelve wrapper-driven gates (found by the bite-4 review).
# v6.6.6 (bite 27a): a FUNCTION, called after the selector is resolved. `check.sh --list`
# and `check.sh <typo>` used to stage 19 MB and a full toolchain refresh before printing
# their one line of output. Nothing about resolving a selector needs a home.
_chk_stage_home() {
  _CHK_LIVE_HOME="${CYRIUS_HOME:-$HOME/.cyrius}"
  if [ -z "${CYRIUS_HOME:-}" ]; then
    _CHK_HOME=$(mktemp -d "${TMPDIR:-/tmp}/cyrius-check-home.XXXXXX") && [ -d "$_CHK_HOME" ] || { printf "error: mktemp -d failed for the throwaway CYRIUS_HOME (TMPDIR=%s)\n" "${TMPDIR:-/tmp}" >&2; exit 1; }
    # v6.6.6 (bite 27b): stamp the owner FIRST, before anything slow, so a concurrent run's
    # reaper can never mistake this home for abandoned. See _chk_reap_stale_homes above.
    printf '%s\n' "$$" > "$_CHK_HOME/.owner"
    _CHK_VER="$(tr -d '[:space:]' < VERSION)"
    mkdir -p "$_CHK_HOME/versions"
    if [ -d "$_CHK_LIVE_HOME/versions" ]; then
        for _slot in "$_CHK_LIVE_HOME"/versions/*; do
            [ -d "$_slot" ] || continue
            [ "$(basename "$_slot")" = "$_CHK_VER" ] && continue
            ln -s "$_slot" "$_CHK_HOME/versions/$(basename "$_slot")"
        done
    fi
    [ -d "$_CHK_LIVE_HOME/deps" ] && ln -s "$_CHK_LIVE_HOME/deps" "$_CHK_HOME/deps"
    [ -f "$_CHK_LIVE_HOME/signed-since" ] && cp "$_CHK_LIVE_HOME/signed-since" "$_CHK_HOME/signed-since"
    if ! CYRIUS_HOME="$_CHK_HOME" sh "$ROOT/scripts/install.sh" --refresh-only > "$_CHK_HOME/.stage.log" 2>&1; then
        printf "error: could not stage a throwaway CYRIUS_HOME from the tree:\n" >&2
        cat "$_CHK_HOME/.stage.log" >&2
        rm -rf "$_CHK_HOME"
        exit 1
    fi
    export CYRIUS_HOME="$_CHK_HOME"
    export CYRIUS_CHECK_STAGED_HOME=1
    export PATH="$_CHK_HOME/bin:$PATH"
    _CHK_STAGED_DIR="$_CHK_HOME"   # removed by the single _chk_finish EXIT trap
    printf "check: staged CYRIUS_HOME=%s (versions/%s from the tree; other slots + deps aliased from %s; PATH prefixed with its bin/)\n" "$_CHK_HOME" "$_CHK_VER" "$_CHK_LIVE_HOME"
  fi
}

CHECK_BIN="$ROOT/build/cyrius_check"
# v6.0.90: programs/check.cyr split into programs/checks/ (slim dispatcher
# main.cyr + per-suite files). CHECK_SRC is the dispatcher; the rebuild
# trigger watches EVERY suite file (a single-file -nt test would miss a
# stale binary after a suite edit — masking a regression).
CHECK_SRC="$ROOT/programs/checks/main.cyr"
CC="$ROOT/build/cycc"

# ⛔ v6.5.42: watch the INCLUDED lib files too, not just programs/checks/*.cyr. The suite
# includes lib/audit_walk.cyr (and others), so a change there produced NO rebuild and the run
# silently exercised a stale binary — measured: a fix to the audit walkers appeared to have no
# effect at all, and the wrong conclusion was nearly drawn from it. Same failure family as the
# swallowed compile error below: the suite must not be able to run against source it was not
# built from.
# ⛔ v6.6.6: watch ALL of lib/, not a hand-listed subset. The line above named exactly one
# included lib module (audit_walk.cyr) while the suite includes thirteen, so the same
# stale-binary failure the note describes was still live for the other twelve — bite 8c
# made lib/regression.cyr the substrate for every child the driver spawns and a change
# there produced NO rebuild. A hand-maintained list of a derivable set is the shape this
# release keeps finding wrong; `lib/*.cyr` is a superset that costs one extra ~1 s rebuild
# and cannot rot. CHANGELOG [6.6.6]
NEWEST_SRC="$(ls -t "$ROOT"/programs/checks/*.cyr "$ROOT"/lib/*.cyr 2>/dev/null | head -1)"
# Rebuild if: no binary, the glob matched nothing (force a rebuild so the
# build fails loudly rather than running a stale binary), or any suite file
# is newer than the binary.
if [ ! -x "$CHECK_BIN" ] || [ -z "$NEWEST_SRC" ] || [ "$NEWEST_SRC" -nt "$CHECK_BIN" ]; then
    if [ ! -x "$CC" ]; then
        printf "error: build/cycc missing — run 'sh bootstrap/bootstrap.sh' first.\n" >&2
        exit 1
    fi
    # ⛔ v6.5.40: FAIL LOUDLY. This was `> "$CHECK_BIN" 2>/dev/null` with no status check, so a
    # compile error in the suite was invisible AND left a truncated $CHECK_BIN that was then
    # chmod +x'd and run — producing either no output at all or a stale-looking result with no
    # hint that the suite never built. Cost real time during v6.5.40 (an undefined helper in a
    # debug edit produced a completely silent run). The compiler's own diagnostics are the
    # thing you need here, so they are shown.
    # ⛔ v6.6.6: build to a SIDE FILE and rename into place. Writing the redirect straight
    # at $CHECK_BIN fails ETXTBSY whenever a previous run's check binary is still alive —
    # which is exactly what an interrupted or killed run leaves behind, reparented to PID 1
    # — and that aborted the whole suite before a single gate ran, for a reason that has
    # nothing to do with the tree. Measured while writing this bite: one orphaned
    # cyrius_check cost a full 13-minute run. rename(2) over a running binary is fine; the
    # running process keeps its own inode. Same shape as the `cp new && mv -f` recipe
    # CLAUDE.md prescribes for build/cycc. CHANGELOG [6.6.6]
    # ⛔ 6.6.20: the side files are PER RUN (`.new.<pid>`). With one fixed `.new`, two selectors
    # started in ONE worktree both rebuilt into the same file: the second's `>` truncated the
    # first's half-written binary, the first renamed it away, and the second's `chmod` / `mv`
    # then failed under `set -e` — a red run for a reason that is not the tree. The final rename
    # stays shared and atomic: each run installs a complete binary built from the same sources.
    # Gate: tests/gates/toolchain/check_concurrent_selectors_one_tree.sh. CHANGELOG [6.6.20]
    _CHK_BIN_NEW="$CHECK_BIN.new.$$"
    _CHK_BIN_ERR="$CHECK_BIN.err.$$"
    if ! cat "$CHECK_SRC" | "$CC" > "$_CHK_BIN_NEW" 2>"$_CHK_BIN_ERR"; then
        printf "error: the check suite failed to compile:\n" >&2
        cat "$_CHK_BIN_ERR" >&2
        rm -f "$_CHK_BIN_NEW" "$_CHK_BIN_ERR"
        exit 1
    fi
    rm -f "$_CHK_BIN_ERR"
    chmod +x "$_CHK_BIN_NEW"
    mv -f "$_CHK_BIN_NEW" "$CHECK_BIN"
    _CHK_BIN_NEW=""
    _CHK_BIN_ERR=""
fi

# ── ⛔ v6.6.6 (bite 27a): A TARGETED RUN RUNS THAT SUITE — AND A TYPO IS AN ERROR ─────
#
# THE DEFECT. `sh scripts/check.sh <anything>` ran the WHOLE suite. The argument was
# forwarded to the check binary (bite 25b even gated that it was forwarded) and the binary
# threw it away: programs/checks/main.cyr includes lib/args.cyr, never called args_init(),
# and no line of it read argv(n). So `check.sh nosuchsuitename` ran all 130 registered rows
# for thirteen minutes and reported on all of them — an unrecognised name was not an error,
# it was a full run. The comment that stood here ("On a targeted run … run only the
# driver") described the intended behaviour, not the behaviour.
#
# THE TWO HALVES. A run is the cyrius driver AND the shell gates below, so selection has to
# cover both or a "targeted run" silently means "the driver half, all of it". Hence three
# kinds of selector, and EVERY one of them is DERIVED, never listed here:
#   * a driver suite — asked of the binary (`--list-suites`), which answers out of its own
#     suite table, the same table its run loop walks;
#   * a shell-gate BUCKET (`codegen`, `frontend`, …, plus `scripts`) — derived from this
#     file's own `_chk_gate` lines, the same read `_chk_finish` uses for NOT RUN;
#   * a single shell gate, by basename.
# A hand-written list of any of the three is the shape this release keeps finding rotted.
#
# An unknown selector exits 2 and PRINTS the valid ones. Neither it nor `--list` stages a
# CYRIUS_HOME — _chk_stage_home is called only once a selector has resolved.
#
# ⛔ A NAME IN TWO VOCABULARIES RESOLVES; IT IS NOT REFUSED. This block's first cut called
# such a name "ambiguous" and exited 2, and that made `sh scripts/check.sh heapmap`
# — a driver suite `--list` itself advertises, and the one the CHANGELOG bullet quoted a
# timing for — UNREACHABLE, because tests/gates/memory/heapmap.sh has the same basename.
# (The 25 ms that bullet reported WAS the refusal; a real `check.sh heapmap` is ~1.2 s.) Derived over all three vocabularies it was the only collision, so the whole
# "ambiguous" branch existed to reject exactly one advertised selector. A refusal that
# hides a name the tool itself prints is not caution; it is the same shape as the rest of
# this release's finds — the checker disagreeing with the thing it checks. So:
#   * PRECEDENCE, stated once: suite > bucket > gate. An unqualified name always resolves.
#   * QUALIFIED FORMS `suite:x` / `bucket:x` / `gate:x` reach the shadowed one, so nothing
#     registered anywhere is unreachable by any spelling. A qualifier that names nothing in
#     THAT vocabulary is an error — it is an explicit request, not a guess.
#   * A shadowed name says so on stderr when it resolves, and `--list` marks it.
# `check.sh --resolve <sel>…` answers what each selector resolves to and runs NOTHING, which
# is what lets a gate assert that every name `--list` prints resolves. CHANGELOG [6.6.6]
#
# ⛔ The driver-suite path keeps bite 25b's property: the driver's exit status IS the
# verdict and no summary is printed, because the shell-gate manifest is not part of that
# run. It goes through `exit`, never `exec`, so the EXIT trap still removes the staged home
# (that was 25b's bug: `exec` replaces the process and runs no trap).
# CHANGELOG [6.6.6]
# ⚠ A full run drives its shell gates from TWO registries and a selector has to see both.
# The other one is `_gate(<name>, "<path>")` inside programs/checks/*.cyr — the rows the check
# binary runs as part of its `regression` phase. Both are read back out of the CALLS, so
# neither can drift from what actually runs.
# ⛔ 6.6.8: the claim that stood here — "the union is exactly the files under tests/gates/,
# nothing registered twice, nothing orphaned" — was FALSE the day it was next true: ten gates
# added at 6.6.6 were called as bare `sh "$ROOT/…"` lines, which this reader does not see, so
# they aborted the run on failure and no selector could reach them (`check.sh frontend` ran 33
# of the 39 frontend gates and could report ALL GREEN). And the driver reader took only
# `"tests/gates/…"` literals, so the driver's `scripts/differential-smoke.sh` row was
# unreachable too. The union is now a CHECKED property, not a sentence:
# tests/gates/toolchain/check_gate_census.sh reads `--registry` (this reader, duplicates kept)
# and fails on an unregistered gate, a gate registered twice, a registration with no file, a
# driver `_gate(` call whose path is not a literal, and any line here that runs a gate outside
# `_chk_gate`. CHANGELOG [6.6.8]
_chk_driver_gate_manifest() {
    # Only the PATH literal that ends a `_gate(` call — a script named anywhere else in the
    # driver (e.g. `scripts/install.sh`) is not a registration, and neither is a commented-out
    # call.
    grep -hE '(^|[^A-Za-z0-9_])_gate\(' "$ROOT"/programs/checks/*.cyr | grep -vE '^[[:space:]]*#' \
        | grep -oE '"(tests/gates|scripts)/[A-Za-z0-9_./-]+\.sh"\);' | sed 's/");$//; s/^"//'
}
# Every registration, ONE LINE PER CALL — duplicates kept, so a gate registered twice is
# visible (`--registry` prints this; the census gate counts it). Everything else reads the
# de-duplicated set.
_chk_gate_registry_raw() { _chk_shell_manifest; _chk_driver_gate_manifest; }
_chk_gate_registry() { _chk_gate_registry_raw | sort -u; }
_chk_shell_buckets() { _chk_gate_registry | sed 's|/[^/]*$||; s|^tests/gates/||' | sort -u; }
_chk_shell_names()   { _chk_gate_registry | sed 's|.*/||; s|\.sh$||' | sort -u; }
_chk_driver_suites() { "$CHECK_BIN" --list-suites 2>/dev/null; }
# The three vocabularies, read once per process. Cached because the annotated `--list` and
# `--resolve` ask about them a few hundred times and _chk_driver_suites is a process spawn.
_chk_vocab() {
    [ -n "${_CHK_V_READ:-}" ] && return 0
    _CHK_V_SUITE=$(_chk_driver_suites)
    _CHK_V_BUCKET=$(_chk_shell_buckets)
    _CHK_V_GATE=$(_chk_shell_names)
    # A name more than one vocabulary claims. Derived by counting duplicates across all
    # three, so it cannot be a hand-kept list of known collisions (today: `heapmap`).
    _CHK_V_SHADOWED=$(printf '%s\n%s\n%s\n' "$_CHK_V_SUITE" "$_CHK_V_BUCKET" "$_CHK_V_GATE" \
        | grep -v '^$' | sort | uniq -d)
    _CHK_V_READ=1
}
# Every kind a bare name belongs to, in PRECEDENCE order, one per line. The three readers
# above are the only source; this function adds no vocabulary of its own.
_chk_kinds_of() {
    _chk_vocab
    printf '%s\n' "$_CHK_V_SUITE"  | grep -qx -- "$1" && echo suite
    printf '%s\n' "$_CHK_V_BUCKET" | grep -qx -- "$1" && echo bucket
    printf '%s\n' "$_CHK_V_GATE"   | grep -qx -- "$1" && echo gate
    return 0
}
# Mark a name that more than one vocabulary claims, so `--list` never advertises a selector
# without saying which spelling reaches it.
_chk_annotate() {
    _chk_vocab
    while read -r _n; do
        [ -n "$_n" ] || continue
        if printf '%s\n' "$_CHK_V_SHADOWED" | grep -qx -- "$_n"; then
            _ak=$(_chk_kinds_of "$_n" | tr '\n' ' ' | sed 's/ *$//')
            _aw=${_ak%% *}
            printf '  %s   [claimed by %s — bare "%s" runs the %s; qualify (%s) for the rest]\n' \
                "$_n" "$_ak" "$_n" "$_aw" \
                "$(printf '%s\n' "$_ak" | tr ' ' '\n' | grep -v "^$_aw$" | grep -v '^$' | sed "s|\$|:$_n|" | tr '\n' ' ' | sed 's/ *$//')"
        else
            printf '  %s\n' "$_n"
        fi
    done
    return 0
}
_chk_list_selectors() {
    echo "usage: sh scripts/check.sh [<selector>]   (no selector = the full run)"
    echo "       a selector may be qualified: suite:<name>, bucket:<name>, gate:<name>"
    echo "       sh scripts/check.sh --resolve <selector>...   says what each resolves to, runs nothing"
    echo "       sh scripts/check.sh --registry   prints every gate registration (one per call), runs nothing"
    echo ""
    echo "driver suites (programs/checks/main.cyr — runs that phase of the check binary):"
    _chk_driver_suites | _chk_annotate
    echo "gate buckets (runs every registered gate in that bucket, from both registries):"
    _chk_shell_buckets | _chk_annotate
    echo "gates (runs that one gate script):"
    _chk_shell_names | _chk_annotate
}

# Resolve ONE selector. Sets _CHK_KIND (suite|bucket|gate) and _CHK_SEL (the bare name).
# $2 = "quiet" to skip the shadow note (used by --resolve, which prints its own line).
# Returns 2 and explains on stderr when nothing is registered by that name.
_chk_resolve() {
    _r_in=$1
    _r_want=""
    case "$_r_in" in
        suite:*)  _r_want=suite;  _CHK_SEL=${_r_in#suite:}  ;;
        bucket:*) _r_want=bucket; _CHK_SEL=${_r_in#bucket:} ;;
        gate:*)   _r_want=gate;   _CHK_SEL=${_r_in#gate:}   ;;
        *)        _CHK_SEL=$_r_in ;;
    esac
    _r_kinds=$(_chk_kinds_of "$_CHK_SEL")
    if [ -n "$_r_want" ]; then
        if ! printf '%s\n' "$_r_kinds" | grep -qx -- "$_r_want"; then
            printf "error: no %s is registered under the name '%s'\n" "$_r_want" "$_CHK_SEL" >&2
            _chk_list_selectors >&2
            return 2
        fi
        _CHK_KIND=$_r_want
        return 0
    fi
    if [ -z "$_r_kinds" ]; then
        printf "error: unknown check selector '%s' — nothing registered by that name\n" "$_CHK_SEL" >&2
        _chk_list_selectors >&2
        return 2
    fi
    # First line = highest precedence (suite > bucket > gate), as _chk_kinds_of emits them.
    _CHK_KIND=$(printf '%s\n' "$_r_kinds" | head -1)
    _r_rest=$(printf '%s\n' "$_r_kinds" | tail -n +2 | tr '\n' ' ' | sed 's/ *$//')
    if [ -n "$_r_rest" ] && [ "${2:-}" != "quiet" ]; then
        printf "check: '%s' is registered as a %s and as a %s — running the %s; use %s to reach the rest\n" \
            "$_CHK_SEL" "$_CHK_KIND" "$_r_rest" "$_CHK_KIND" \
            "$(printf '%s\n' "$_r_rest" | tr ' ' '\n' | grep -v '^$' | sed "s|\$|:$_CHK_SEL|" | tr '\n' ' ' | sed 's/ *$//')" >&2
    fi
    return 0
}

if [ $# -gt 0 ]; then
    case "$1" in
        --list|-l|--list-suites|--help|-h)
            _chk_list_selectors
            exit 0
            ;;
        --registry)
            # Every gate registration, one line per CALL (duplicates kept), from the SAME
            # readers the selectors and NOT RUN use. Runs nothing, stages nothing. The census
            # gate reads this, so it can never check a different set than the one that runs.
            # CHANGELOG [6.6.8]
            _chk_gate_registry_raw
            exit 0
            ;;
        --resolve)
            shift
            [ $# -gt 0 ] || { printf "error: --resolve needs at least one selector\n" >&2; exit 2; }
            # Read the vocabularies HERE: _chk_kinds_of runs inside $( ), which inherits the
            # cache but cannot fill it, so without this every selector re-spawns the driver.
            _chk_vocab
            _CHK_RES_RC=0
            for _s in "$@"; do
                if _chk_resolve "$_s" quiet; then
                    printf '%s %s\n' "$_CHK_KIND" "$_CHK_SEL"
                else
                    printf 'UNRESOLVED %s\n' "$_s"
                    _CHK_RES_RC=2
                fi
            done
            exit "$_CHK_RES_RC"
            ;;
    esac
    if [ $# -gt 1 ]; then
        printf "error: check.sh takes at most ONE selector (got %s: %s)\n" "$#" "$*" >&2
        _chk_list_selectors >&2
        exit 2
    fi
    _chk_resolve "$1" || exit 2
    _chk_read_no_skip

    _chk_stage_home
    if [ "$_CHK_KIND" = "suite" ]; then
        _chk_run_bg "$CHECK_BIN" "$_CHK_SEL"
        exit "$_CHK_RC"
    fi
    # A bucket or a single gate. Narrow the manifest FIRST so the end-of-run summary
    # reports on exactly what was selected instead of calling the other ~128 NOT RUN.
    if [ "$_CHK_KIND" = "bucket" ]; then
        _CHK_MANIFEST=$(_chk_gate_registry | grep -E "^(tests/gates/)?$_CHK_SEL/")
    else
        _CHK_MANIFEST=$(_chk_gate_registry | grep -E "(^|/)$_CHK_SEL\.sh\$")
    fi
    _CHK_SEL_N=$(printf '%s\n' "$_CHK_MANIFEST" | grep -c . || true)
    [ "$_CHK_SEL_N" -gt 0 ] || { printf "error: selector '%s' resolved to 0 gates — the registry reader and the selector disagree\n" "$_CHK_SEL" >&2; exit 2; }
    printf "check: selector '%s' -> %s of %s registered gate(s)\n" \
        "$_CHK_SEL" "$_CHK_SEL_N" "$(_chk_gate_registry | grep -c . || true)"
    _CHK_STARTED=1
    for _m in $_CHK_MANIFEST; do
        _chk_gate "$ROOT/$_m"
    done
    exit 0    # _chk_finish turns the tally into the verdict
fi

_chk_read_no_skip
_chk_stage_home
_CHK_JOBS=$(_chk_jobs) || exit 2
if [ "$_CHK_JOBS" -gt 1 ]; then
    _CHK_PAR=1
    _CHK_PDIR=$(mktemp -d "${TMPDIR:-/tmp}/cyrius-check-par.XXXXXX") && [ -d "$_CHK_PDIR" ] || { printf "error: mktemp -d failed for the parallel run (TMPDIR=%s)\n" "${TMPDIR:-/tmp}" >&2; exit 1; }
    : > "$_CHK_PDIR/queue"
    : > "$_CHK_PDIR/serial"
    : > "$_CHK_PDIR/pids"
    # every registered gate produces a result here — the driver's own included
    _CHK_MANIFEST=$(_chk_gate_registry)
fi

# ⛔ v6.6.6: RECORD the driver's verdict, do NOT abort on it. `"$CHECK_BIN"` used to be a
# bare command under `set -e`, so any red row in it skipped every shell gate below — see the
# header. The shell gates cover things the binary cannot, and a red doc stamp is no reason to
# stop looking at them.
_CHK_STARTED=1
# ⛔ 6.6.11: the driver's own SKIP rows reach THIS verdict. The driver exits 0 over a SKIP (it
# is not a failure), so its rc alone recorded `PASS` for a run in which ~30 driver-registered
# gates could not run, and the summary said ALL GREEN. `--skip-report` has it append each
# SKIP row to a file; every line is a result here and a SKIP in the count. CHANGELOG [6.6.11]
if [ -n "$_CHK_STAGED_DIR" ]; then
    _CHK_DRV_SKIPS_D="$_CHK_STAGED_DIR"
else
    _CHK_DRV_SKIPS_D=$(mktemp -d "${TMPDIR:-/tmp}/cyrius-check-skips.XXXXXX") && [ -d "$_CHK_DRV_SKIPS_D" ] || { printf "error: mktemp -d failed for the driver's skip report (TMPDIR=%s)\n" "${TMPDIR:-/tmp}" >&2; exit 1; }
    _CHK_DRV_SKIPS_RM="$_CHK_DRV_SKIPS_D"
fi
_CHK_DRV_SKIPS_F="$_CHK_DRV_SKIPS_D/.driver-skips"
: > "$_CHK_DRV_SKIPS_F"
# 6.7.0 — THE PARALLEL FULL RUN (the default; CYRIUS_CHECK_JOBS=1 is the serial one). The serial
# run took ~45 minutes on a 16-core box because it ran the driver's phases, then its ~195
# `_gate` rows, then the ~226 shell gates below, ONE AT A TIME — CI looks fast only because it
# splits a subset across ~20 runners. Here the driver starts in the background with
# CYRIUS_CHECK_GATES_ELSEWHERE=1 (it skips its `_gate` rows), every registered gate script — the
# driver's and the shell ones — goes into ONE pool of $_CHK_JOBS `--run-gate` workers (deadline,
# PDEATHSIG and tree-kill unchanged), and a gate marked `# check: serial` (a timing tripwire or a
# scaling ratio, which load would falsify) runs alone after the pool. Logs print in registry
# order and score exactly as the serial run scores them. CHANGELOG [6.7.0]
if [ "$_CHK_PAR" = 1 ]; then
    _chk_par_start
else
_chk_run_bg "$CHECK_BIN" --skip-report "$_CHK_DRV_SKIPS_F"
_chk_driver_result "$_CHK_RC"
fi

# v6.2.28 D7: the bare-metal kernel BOOT gate — a real QEMU execution of the
# kernel built via the formalized triple. This anti-rots the v6.2.27 kernel
# codegen the way the macho port never was (a green checkmark is not
# verification; the kernel actually running IS). Visibly skips when qemu is
# absent rather than masquerading as green.
_chk_gate "$ROOT/scripts/qemu-boot-gate.sh"

# v6.4.47 (arc #3): UEFI Authenticode signing end-to-end gate — `cyrius sign-efi`
# signs a synthetic PE and an independent oracle (openssl + from-scratch PE-hash)
# confirms the signature is one a real UEFI firmware would accept. Skips if openssl
# is absent. The sign path is lib/CLI-only (cycc byte-identical), so this is the
# behavioral gate for the signer.
_chk_gate "$ROOT/scripts/sign-efi-gate.sh"

# v6.4.81: value-form SIMD must exist on every EMIT path, not just the native
# forks. main.cyr's PE/Mach-O CROSS arms were missing CYRIUS_HAS_VAL_SIMD_PARAMS
# since v6.4.31, so the same source built differently depending on WHERE it was
# built. Host-side by necessity: a tcyr runs natively on each host and therefore
# exercises main_win.cyr (always correct), never the cross path.
_chk_gate "$ROOT/tests/gates/platform/valform_simd_crosstarget.sh"

# v6.5.0 Phase 1 (public/private visibility): every fn must be attributed to the
# source file its `fn` keyword is in. Phase 2 turns that partition into a visibility
# boundary, so a wrong stamp means `private` silently mis-scopes. Gated here at
# Phase 1 — while the table is still recorded-not-enforced — so the substrate is
# never write-only and never unverified.
_chk_gate "$ROOT/tests/gates/frontend/fileid_substrate.sh"

# v6.5.0 Phase 2: file-scoped `private` / per-item `public`, WARN mode. Asserts
# per-RESOLUTION-PATH (ordinary / tail / operator), because enforcement that covers
# only the obvious path is the v6.4.81 `_cfo` shape repeating — that class was
# declared fixed three times before the fourth occurrence turned up in a path nobody
# had enumerated.
_chk_gate "$ROOT/tests/gates/frontend/visibility_private.sh"
_chk_gate "$ROOT/tests/gates/frontend/string_token_decoders.sh"
_chk_gate "$ROOT/tests/gates/frontend/public_marker_scoped_to_its_item.sh"
_chk_gate "$ROOT/tests/gates/frontend/derive_with_public.sh"

# v6.5.1: overload-suffix dispatch must be ARITY-AWARE and POSITION-CONSISTENT.
# Asserts across assign / return-tail / nested-arg because the two defects it covers
# were *position-specific* — the redirect ignored the target's arity on the assign and
# nested paths, and PARSE_RETURN's tail path skipped the dispatch entirely, so the same
# call spelled two ways ran two different functions. The 253-file corpus changes 0 bytes
# under the arity fix, i.e. it had ZERO coverage of the shape, which is why this must be
# a gate and not a .tcyr.
_chk_gate "$ROOT/tests/gates/frontend/overload_arity_dispatch.sh"

# v6.5.1: the agnos O_RDWR flag-map gate (v6.4.27) was CI-ONLY — `ci.yml` ran it and
# nothing local did, so `release-gate.sh` could report GREEN while CI went RED. It did
# exactly that this release: the arity escalation above turned the gate's `sys_unlink(path)`
# into a hard error (agnos's wrapper is length-carrying and takes 2 args), and the local
# gate never noticed. A gate CI runs but the release gate does not is the same blind spot
# as grading check.sh by its stdout instead of its exit status — fixed the same way, by
# making the local gate actually run it. `tests/gates/memory/heapmap.sh` is the only other CI-only
# script and it is genuinely redundant: `_heapmap_gate()` in the check binary covers it.
_chk_gate "$ROOT/tests/gates/platform/io_rdwr_agnos.sh"
# v6.5.54: the NOP-harvest compactor must run under IR mode, and the resulting compiler
# must WORK. It was gated off for every IR mode, so CYRIUS_IR=3 shipped 19,067 NOP
# instructions against the default path's 44 (+65,320 B of .text). The gate could not
# simply be lifted: the compactor moves code and the IR records a code position per node,
# so without the stage-3c CP repair the IR-built cycc dies at startup with
# `alloc_init: mmap failed` — mutation-proven, and that reproduction check, not the NOP
# count, is what this gate is really asserting.
_chk_gate "$ROOT/tests/gates/codegen/ir_nop_harvest.sh"

# v6.5.54: ir_build_edges must resolve jump targets within a function. Both BB finders
# scanned the whole program per jump (one of them nesting a node scan inside that), which
# put CYRIUS_IR=3 at 13,967 ms against 672 ms — 21x, and ALL of it here: with FOLD, LASE,
# DCE and DSE all disabled it was still 13,910 ms. Pins the COST, not the mechanism, so any
# sub-quadratic scheme passes.
_chk_gate "$ROOT/tests/gates/codegen/ir_edges_scaling.sh"

# v6.5.55: `enum N: stack` must construct payload variants with NO allocation, the plain boxed
# form must be untouched, and a variant too wide for the (tag, payload) pair must be REJECTED
# rather than silently truncated. Axis 3 is the point: v6.5.15 already tried to stop boxing, by
# relocating the box to a per-call-site global, and shipped a compiler that reported a failed
# file open as SUCCESS in a retaining loop while passing every gate of its day. This gate builds
# N values at ONE call site, keeps them all live, and checks each — and pairs every zero-growth
# assertion with a non-zero control so it cannot go vacuous.
_chk_gate "$ROOT/tests/gates/codegen/stack_enum_no_alloc.sh"

# 6.6.17 — a string only a diagnostic reads (a `#deprecated` / `#assert` message, #derive's
# generated ones too) leaves no bytes in the binary: the lexer moves it to a side table. Binaries
# that differ only in such messages are byte-identical; the messages still print.
_chk_gate "$ROOT/tests/gates/codegen/compile_time_strings_not_emitted.sh"

# v6.5.56 P0: identifier dedup must be an EXACT compare. It was a PREFIX compare that happened to
# be exact only while `bucket = klen` put one length per chain; v6.5.50's content hash removed
# that invariant without adding the terminator check it had been standing in for, so a shorter
# identifier took a longer one's pool offset and the two became ONE symbol
# (`var ah = 7; var ahxaa = 99;` read `ah` as 99, exit 0). 127 repos carry a colliding pair.
# ⛔ The self-host fixpoint CANNOT see this — cycc's own source has 0 colliding pairs of 54,089,
# and the mutation proof confirms a deliberately-broken compiler still reproduces itself
# byte-identically. This gate pins the PROPERTY on known-colliding pairs instead.
_chk_gate "$ROOT/tests/gates/frontend/lexid_prefix_exact.sh"

# 6.6.11 (B05, L8 + the mulh64x premise find): `sizeof(T)` and `mulh64` match WHOLE names.
# Both sizeof sites (expression + #assert) sized a scalar by a byte PREFIX, so sizeof(i16v8)
# was 2, sizeof(i8zz) 1, and `#assert sizeof(i16v8) == 2` passed; PARSE_FACTOR matched
# `mulh64` by a 6-byte prefix, so a user fn `mulh64x(a, b)` compiled as the intrinsic (0 for
# small args). 7 refusal rows, 3 anti-vacuous sizing rows, 3 mulh64x/intrinsic rows.
_chk_gate "$ROOT/tests/gates/frontend/sizeof_whole_name.sh"

# 6.6.20 (BACKLOG-03): the identifier-spelled intrinsics sizeof / mulh64 / fncall0..8 are
# RESERVED as declared names. They sit in neither util.cyr reserved table, so `fn mulh64`
# compiled and every call got the intrinsic, `fn fncall1(a, b)` compiled and its call jumped
# through `a` (SIGSEGV), and `var sizeof` declared with every read a parse error. Every
# declaration form is refused by name; only a file named fnptr.cyr may declare fncall0..8.
_chk_gate "$ROOT/tests/gates/frontend/intrinsic_names_reserved.sh"

# v6.5.56: `private fn h()` must be rejected rather than silently privatising the whole file
# (twelve releases live, no diagnostic). Axes 2-3 keep the fix honest: the own-line and
# `private;` forms are the legitimate spellings and must keep working.
_chk_gate "$ROOT/tests/gates/frontend/private_per_item_rejected.sh"

# 6.6.5: `private` was enforced only against definitions PASS 1 REGISTERED, and pass 1 skipped
# impl bodies, `mod` fns and everything after the first top-level statement — so a call that
# merely came EARLIER in the stream reached a private method from any file. The same root
# produced FALSE refusals (the guide's own two-file example, refused on include order alone),
# false arity errors, and silent SIGSEGVs (a forward call's >8 B struct param took the mask-0
# ABI). Axis 1 is static 7-fork parity — miss one fork and the hole comes back on that target
# only; axis 2 compares the FORWARD refusal set against the BACKWARD one, so the expectation
# is produced by a different compiler path, not a list in the gate.
_chk_gate "$ROOT/tests/gates/frontend/private_forward_reference.sh"

# 6.6.5: `s.m(x)` and `M_m(&s, x)` are one call syntax with TWO marshalling paths, and the
# method one ran NONE of PARSE_FNCALL's callee gates — four silent failures in one argument
# loop (struct-by-value SIGSEGV, an unwrapped `: Str` literal, a vector pushed as an int arg,
# an integer literal into `: cstring`), plus no arity check at all. Every row is a
# DIFFERENTIAL against the identical free fn, so the expected value comes from PARSE_FNCALL
# rather than from a list in the gate: a fifth gate added there and forgotten here fails.
_chk_gate "$ROOT/tests/gates/frontend/method_call_runs_every_callee_gate.sh"

# 6.6.6: a top-level name declared twice is ONE global and the last definition wins. The
# redeclaration used to get a second slot, so `var a = 5; var b = a; var a = 5;` read b as 0
# and the "(last definition wins)" collision warning described a semantics the compiler did not
# implement. Rows are checked against no-redeclaration CONTROL programs, with a cx leg (the one
# target that stores the value rather than baking it) and an aarch64 leg under qemu.
_chk_gate "$ROOT/tests/gates/frontend/global_redeclaration_one_definition.sh"

# 6.6.20 (BACKLOG-01): a redefined FN binds every call to its last definition, as its warning
# says. A call to an already-defined fn baked the entry it saw (ECALLTO), so `var x = g();`
# between two `fn g` bound the FIRST while tail calls and forward calls bound the last (212 for
# the three shapes on x86, aarch64 and cx). The earlier entry now jumps to the winner; #inline
# replay and generic instances read pass 1's redefinition flag; a redefinition CALLED differently
# (return type, parameter masks, variadic) is refused like the 6.5.37 arity mismatch. x86, qemu,
# cxvm and wine, plus a CYRIUS_DCE=1 row where elimination moves the winner under the redirect.
_chk_gate "$ROOT/tests/gates/frontend/fn_redefinition_binds_last.sh"

# 6.6.6: a block-bodied closure in a declaration-zone `var` used to end the program. Pass 1 and
# pass 2 both found the end of the declaration by scanning to the first `;`, and the closure body
# carries one — so both stopped at its `}` and every statement below was dropped, silently. Rows
# are checked against CONTROL programs whose declarations take the (always-correct) PARSE_PROG
# path instead, with cx / aarch64-qemu / PE-wine legs and a static 7-fork parity axis, because
# the pass-2 skip is copied into every `src/main*.cyr`.
_chk_gate "$ROOT/tests/gates/frontend/toplevel_decl_block_closure.sh"

# 6.6.6 bite 19a: a `var` declared inside a TOP-LEVEL block is scoped to that block, like one
# in a fn body. It used to register a GLOBAL — and the global var table had no scope mechanism
# at all — so `if (c == 1) { var t = 5; } syscall(60, t);` compiled and exited 5 while the same
# shape inside a fn is `undefined variable 't'`. One spelling, two scoping rules. Rows are
# checked against no-block CONTROL programs; the refusal rows assert the error names the
# variable, the note says where to declare it, and no binary is emitted.
_chk_gate "$ROOT/tests/gates/frontend/toplevel_block_var_scope.sh"

# 6.6.6 bite 19f: a function-like `#define` must not change the source every other pass
# produced. PP_IFDEF_PASS does not copy its filtered output back to input_buf, and
# PP_MACRO_PASS reads input_buf and writes preprocess_out — so merely HAVING one function-like
# macro in scope put stripped `#ifdef` arms back into the build (an aarch64 `x0` in an x86
# compile) and truncated the source at the 1 MB helper window. An object-like `#define` never
# ran the pass, which is why it stood. Row C is a byte-for-byte binary differential.
_chk_gate "$ROOT/tests/gates/frontend/macro_pass_preserves_ifdef_filtering.sh"

# 6.6.6 bite 19b: a file may DECLARE a global whose name another file has made `private`.
# v6.5.0 put the cross-file check inside FINDVAR so every REFERENCE is covered by one check,
# but PARSE_GVAR_REG's sit_shadow probe and CHKDUPVAL are not references — they ask "does this
# name exist?" while REGISTERING one — and the check turned that answer into an accusation
# against a file's own declaration. The enforcement rows D-G are the point: deleting the check
# would pass every accepting row.
_chk_gate "$ROOT/tests/gates/frontend/private_does_not_block_own_declaration.sh"

# 6.6.6 bite 19c: the duplicate-symbol warning went SILENT once a program had registered 1024
# vars — CHKDUPVAL opened with a blanket `pi >= 1024` return, which is the ENUM fold table's
# bound applied to both halves of the probe; gvar_initval is a grown table with no such cap.
# The programs that collide are exactly the large ones. The SYS_* note went with it, so row D
# asserts the note's lines too: a fix that restored only the warning would pass otherwise.
_chk_gate "$ROOT/tests/gates/frontend/duplicate_symbol_warning_at_scale.sh"

# 6.6.9 bite 1: gvar_toks (the deferred-initializer table) GROWS past its 4096-entry region
# instead of refusing "too many initialized globals" — the 6.6.6 bite-19e cap gate became this
# acceptance gate: every registration shape past 4096 compiles and runs, a constant
# redeclaration past 4096 still supersedes, a kernel replay past 4096 stores into the
# declaration-zone slot, and (statically) every store goes through the one growing path.
_chk_gate "$ROOT/tests/gates/memory/gvar_toks_grows_past_4096.sh"

# 6.6.6 bite 19d: a global initializer that READS a constant declared below it got 0 on cx and
# the right value on every other target. cx opts out of the static-init path (its globals live
# in cxvm memory zeroed at startup), which left the deferred replay — in declaration order —
# as the only thing that gives a global its value. Rows are checked against controls declared
# in dependency order AND run on the host, so cx is compared with a second implementation.
_chk_gate "$ROOT/tests/gates/codegen/cx_forward_read_constant_global.sh"

# 6.6.6 (review fix to bite 19f's .tcyr): the cross-OS lib-test runner graded tests/tcyr/crossos/
# by EXIT CODE alone, and a process that runs no user code exits 0 — so "the compiler emitted a
# binary that does nothing" and "every assertion passed" were one verdict. Measured on the 6.6.5
# compiler, crossos/macro_expansion_with_include.tcyr compiled to a 43,512-byte binary that
# printed nothing and exited 0: a PASS over the preprocessor defect it is named for. The runner
# now requires the binary's own "N passed" line for any test whose source calls assert_summary.
_chk_gate "$ROOT/tests/gates/toolchain/crossos_runner_rejects_a_silent_binary.sh"
# 6.6.11 B01: no .tcyr may end in a shape that exits 0 after an assertion failed. A file that
# defines `fn main` AND calls `main();` at top level without exiting runs the body twice (the
# epilogue auto-calls a defined main) and exits with the second run's `return 0` —
# crossos/derive_accessor_widths.tcyr printed `1 failed` and exited 0 on x86, aarch64 and PE.
# The other shape is `assert_summary();` then a literal `syscall(60, 0)` (platform/pwd_grp).
_chk_gate "$ROOT/tests/gates/toolchain/tcyr_epilogue_shape.sh"
# 6.6.11 B01: the check driver's .tcyr reader requires the assert summary. It scored
# `failed == 0 && ec == 0` off the FIRST " failed" substring of stdout, so a test that died
# before assert_summary (its FAIL rows go to stderr, never captured) and exited 0, or printed
# `0 passed, 0 failed`, read PASS. Now: the LAST `N passed, M failed` line, N >= 1, M == 0, ec 0.
_chk_gate "$ROOT/tests/gates/toolchain/check_driver_requires_summary.sh"
# 6.6.17 (g2): the .tcyr phase hands each test a throwaway HOME holding a copy of the fdlopen
# helper. With no HOME at all the libssl groups of tls_libssl_read_errors / _session_cache /
# _worker_thread SKIPped on every check.sh run; the invoking HOME is still never reached.
_chk_gate "$ROOT/tests/gates/toolchain/check_tcyr_home_has_helper.sh"
# 6.6.17 (g4): the path-A drift row reads each src/frontend/parse_*.cyr WHOLE, sized by fstat,
# through its last fn. It read a fixed 256 KB, and parse_decl / parse_expr / parse_fn had
# outgrown that, so a direct emit in their tails was never scanned.
_chk_gate "$ROOT/tests/gates/toolchain/check_parse_drift_reads_whole.sh"
# 6.6.12 B12 (T4): a .tcyr whose data file is missing fails WITH A COUNT, never a signal.
# text/unicode_normconf.tcyr run outside the repo root printed its FAIL, then stored its
# terminator at corpus + (-ENOENT) — 2 bytes before a fresh mapping — and died of SIGSEGV
# (139), so the tally never printed. The negative length is now clamped: rc 2, `1 passed, 2 failed`.
_chk_gate "$ROOT/tests/gates/toolchain/tcyr_missing_corpus_is_a_count.sh"
# 6.6.11 B01: ci.yml's three full-corpus .tcyr loops (ubuntu, AGNOS container, native arm64)
# grade by the same rule. They passed `ec == 0` plus an optional `N failed` count, so a test
# that died before its summary and exited 0 had no count to read and scored PASS. Each step's
# own `tcyr_verdict` is extracted and run under bash -eo pipefail over 9 cases, plus a mutant.
_chk_gate "$ROOT/tests/gates/toolchain/ci_tcyr_loops_require_summary.sh"
# 6.6.6: copying between two DIFFERENT struct (or vector) types is an error, not an 8-byte
# store. Both copy paths answered a type mismatch with `return 0`, which falls through to the
# generic scalar store: `p = q` between a P3 and a Q3 copied ONE word of three and left the
# rest of `p` stale, and `var p: P3 = q;` stored q's ADDRESS into a struct-typed slot (p.x read
# a stack address) — both silent, exit 0. The LITERAL form has been a hard error since 6.6.5.
# Acceptance rows are checked against field-by-field CONTROL programs, and the pointer-bind and
# scalar-source paths are pinned so a future tightening cannot quietly take them out.
_chk_gate "$ROOT/tests/gates/frontend/struct_copy_type_checked.sh"

# 6.6.11 (B02, L4+L5+L1): a struct RESULT is type-checked against its struct destination. A <= 8 B
# struct result from a method or overloaded operator was never recorded (`_sc_post` returned early
# for class 0), so `h.o = y.same()`, `z = y.same()`, `var z: Odd = y + y` stored an Od2 into an Odd
# silently; `p = mkq()` / `p = mkr()` / `z = mkod2()` / generic `s = mk(r.v)` stored one word of a
# DIFFERENT struct (the sid test sat after `_try_struct_call_assign`'s early exits); an 8 B struct
# FIELD skipped every check; `var p: Pt = h.q` from a field of another type SIGSEGV'd; a top-level /
# leading-block global took a mismatched struct result silently (16 B: SIGSEGV). 30 refusal rows
# (3/8/16/24 B, generic, field/assign/declaration, fn / top level / leading block) checked on the
# MESSAGE, 11 same-type acceptances each checked against a field-by-field control. Mutation-proven
# (ledger in header).
_chk_gate "$ROOT/tests/gates/frontend/struct_result_type_refused.sh"

# 6.6.12 (B02, R1): a struct LITERAL is type-checked at its head and at each nested struct field.
# A generic literal `Box<Pt> { p, 5 }` failed at all three heads (PARSE_VAR, PARSE_GVAR_REG's
# lookahead, the EMIT_GVAR_INITS replay) with "undefined variable 'Box'"; `_lit_head` now resolves
# the instance with the annotation's own resolver, so a mismatched annotation is refused by name —
# in a fn, in the leading declaration block (which never compared a literal with its annotation:
# `var G: Pt = Q { .. }` compiled) and after a statement. A nested struct field now takes a whole
# struct value, and a value of another struct type is refused by name (local, global, field, call,
# method); a struct call with no frame at top level is refused, as the ONLY error. 16 refusal rows on
# the MESSAGE, 4 acceptances each against a field-by-field control. Mutation-proven (ledger in header).
_chk_gate "$ROOT/tests/gates/frontend/struct_literal_type_refused.sh"

# 6.6.12 (B03, V3 + V4): a struct copy whose SOURCE is a field or a global is type-checked. A
# struct-typed field passed as a by-value struct argument (`take(r.v)`) is checked against the
# parameter's struct (recorded per fn, SFPSID — the instance's for a generic) and refused by name
# when it differs: in a fn, a callee defined after the call, top level, a generic instance, a
# method. A top-level copy-init (`var G: Pt = A;` / `= X.f;`) from a source of another struct type
# is refused by name in the leading declaration block and after a statement, at every width, and a
# leading-block source declared BELOW the destination is refused by name (pass 1 cannot see it). 12
# refusal rows on the MESSAGE (each the only error), 2 acceptances against field-by-field controls.
# Mutation-proven (ledger in header). The copy/layout half is struct_field_value_copy.tcyr (crossos).
_chk_gate "$ROOT/tests/gates/frontend/struct_copy_source_type_refused.sh"

# 6.7.3 (repair lane): a struct ARGUMENT is type-checked against its parameter. Only a struct-typed
# field into an address-passed parameter was (6.6.12, above); every other argument was pushed as it
# came and read with the callee's layout (`bq(p)`, a Pt into `b: Q`: 0; `bs(mk1(p))`, a Box<Pt> into
# `b: Box`: 4 where 8 is right; `q + mkp()`: SIGSEGV). Refused by name in the field arm's words:
# locals (inline, pointer-mode, `*T`), globals, captures, free calls, method / operator results,
# fields, the three argument loops, generic instance vs base both ways, a by-value struct of 8 B or
# less and a `Str` handle parameter, an operator's two operands and a method's `self`. `&p`, an
# untyped value and a fn pointer stay accepted. 44 refusal rows on the MESSAGE (each the only
# error), 9 acceptances against field-by-field controls. Mutation-proven (ledger in header). The
# runtime half is tests/tcyr/crossos/struct_arg_type_accepted.tcyr (crossos).
_chk_gate "$ROOT/tests/gates/frontend/struct_arg_type_refused.sh"

# 6.6.12 (B04, R3): a `.field` on a CALL RESULT is refused by name wherever it cannot compile — at
# top level for every return class (no frame to hold the result; each the only error, including
# the leading declaration block and a struct-typed initialiser), on a callee that returns no
# struct, and for a struct-typed field of the result into a destination of a different struct type
# (a `var` and a by-value argument). A `return f(..).x;` from a struct-returning fn gets the struct-
# return diagnostic (without the step-aside the pair form compiled SILENTLY). Under --syntax-only a
# field of an unresolved call is not a syntax error, and the call's arguments are still parsed.
# Mutation ledger in its header. The acceptance rows are the CF group of
# tests/tcyr/crossos/generic_struct_inference.tcyr. (6.6.12 B05, R2) G1-G2: an EXPLICIT generic
# call as a bare top-level statement, struct-returning (`mkg<i32>(1);`, with and without `.a`), is
# refused by name like `mk3(1);` (was `expected '=', got '<'`); G3: `mu<i32>(3);` on a #must_use
# generic warns. 18 rows.
_chk_gate "$ROOT/tests/gates/frontend/call_result_field.sh"

# 6.6.12 (B20, R4): array subscripts `a[i]`, `a[i] = v`, `a[i] OP= v` on `var a: T[N]`. Before
# 6.6.12 the language had no subscript at all (`expected ';', got '['`). Axis 1: fifteen refusals by
# name (four bare `var a[N]` shapes, a scalar, a pointer, a `stack var`, a u128 element, an
# unknown name, six f64/f32/bool/struct element rows naming that shape - B20 review fix). Axis 2: four typed controls run. Axis 3: the crossos runtime file by default
# and under CYRIUS_IR=3. Axis 4: --syntax-only clean. Axis 5: a slice local's bounds-checked s[i]
# untouched. RED on 6.6.11 (22 failures); five mutations in its header, each RED.
_chk_gate "$ROOT/tests/gates/frontend/array_subscript_forms.sh"

# 6.6.6: a vector-returning fn `return`s only what the vector return ABI can carry. PARSE_RETURN
# handled exactly `return IDENT;` for a local of the matching class and fell through to the
# SCALAR path for everything else, so `fn bad(): f64v2 { return 5; }` compiled clean and handed
# back a half-written register pair — and so did a bare `return;`, `return x + y;` (which
# returned Y UNCHANGED), `return load64(&v);` and a call to a scalar or wrong-width fn. The
# same shape as bite 16c's 9-16 byte struct pair, one type class over. Two sites: the tail-call
# path takes `return f(..);` before the vector branch sees it. Legs: host, cx, qemu-aarch64,
# wine-PE (emulation is NOT hardware — the ecb/ach/cass/pi gate is).
_chk_gate "$ROOT/tests/gates/codegen/simd_return_shapes.sh"

# 6.6.5: the `return f(args);` tail path must divert to PARSE_FNCALL for exactly the
# arguments PARSE_FNCALL treats specially — no more. The `: Str` literal divert added here
# was armed by a literal at ANY paren depth, so `return deep(n-1, str_from("x"))` lost its
# TAIL CALL and a correct bounded recursion started SIGSEGVing. Depth 1 is PARSE_FNCALL's
# own criterion. The gate pins its own stack limit so the verdict is not the box's.
_chk_gate "$ROOT/tests/gates/codegen/tail_call_literal_divert_depth.sh"

# v6.5.57: copying an aggregate must copy EVERY word. `dst = src;` used to copy only the first
# 8 bytes for structs AND vectors — reported as a SIMD bug, but a two-field struct truncated
# identically. Axis 7 keeps THREE aggregates live because the fix also had to close a latent
# register-allocator bug: an aggregate's fields are reached as `lea rcx,[rbp+base]`, so only its
# base slot ever appears as an rbp disp and the picker could promote a later word whose real
# writes go through rcx. With only two aggregates the picker never reaches its `count > 1`
# threshold and a build with that exclusion removed still passes.
_chk_gate "$ROOT/tests/gates/codegen/aggregate_copy_all_words.sh"

# v6.5.58: the SIMD-param inline predicate must SEE a wide parameter whatever its width.
# `_fn_has_simd_param` scanned slots [0, pc), but a wide param's SLTYPE lives on its NAMED slot,
# after (slots-1) anonymous fillers — so the window contained it only for TWO 128-bit params.
# Single-128-bit and ALL 256-bit params were invisible and never inlined. Axis 2 is the control:
# an i64-param fn must still be called, because general inlining is default-off for a measured
# reason and this predicate exists to admit the SIMD wrappers WITHOUT switching it on.
_chk_gate "$ROOT/tests/gates/codegen/simd_param_inline_reach.sh"

# v6.5.59: an INLINED 256-bit return must carry all four lanes. The replay re-parses the callee
# inside the CALLER's function context, so `return r;` emitted the caller's return convention —
# which moves ONE XMM. A 256-bit return is a PAIR, so lanes 2-3 were left stale, exit 0, no
# diagnostic. ⭐ Every lane is asserted: a lane-0 check passes while half the vector is wrong,
# which is why no existing SIMD test caught it.
_chk_gate "$ROOT/tests/gates/codegen/inline_simd256_return_lanes.sh"

# v6.5.60, REWRITTEN v6.5.62: the fixed-lane SIMD wrappers must not pay a per-call AVX2 dispatch,
# and the ymm kernel must keep its advantage where that advantage is real. ⛔ This gate's axis 2
# used to REQUIRE the per-call gate by grep, i.e. it asserted the opposite of the truth — it would
# have gone red on the correct change and stayed green through the wrong one, and never had a
# chance at the +59 % that shipped at v6.5.24. Measured one variable at a time: the dispatch CALL
# was the whole cost (~25 %); ymm at a fixed 4 lanes is free. Axes now measure behaviour.
_chk_gate "$ROOT/tests/gates/codegen/simd_valueform_no_avx_transition.sh"

# v6.5.63: `#inline` must actually inline, must WARN when it cannot, and must not change results.
# The directive had NO handler anywhere in src/ until now — it lexed as a comment and did nothing,
# silently, while consumers wrote it (svara has four markers in src/formant.cyr, and its own
# src/lod.cyr records measuring one at "+0.7% -- noise": a measurement of an optimisation that was
# not there). ⭐ The failure mode is a quiet revert to doing nothing, which a results-only test
# cannot see, so axis 1 counts call sites and axis 2 pins the diagnostic. Mutation-proven: arming
# nothing gives "with=100 without=100" and axis 1 fires.
_chk_gate "$ROOT/tests/gates/codegen/inline_directive.sh"
_chk_gate "$ROOT/tests/gates/codegen/dce_data_vaddr_frozen.sh"

# v6.6.3: a directive must reach EVERY per-target fork, and must not be INERT on any of them.
# cyrius has seven forks of the entry point and each carries its OWN copy of the top-level
# directive dispatch, in TWO regions — pass 1 must CONSUME the token, pass 2 must ARM the flag.
# v6.6.3 shipped #inline's consume into all seven and its ARM into one, which turned native
# aarch64 CI red (missing consume at the SECOND region -> the pass-1 scan terminates and every
# later declaration goes unregistered, surfacing as "unexpected struct" on an innocent line) and,
# underneath that, left #inline silently INERT on aarch64, aarch64-macho, x86-macho, PE and cx.
# ⭐ Axis 2 cannot be faked by a grep: it compiles the same fixture twice through each fork's own
# compiler and requires the outputs to DIFFER — byte-identical output IS the proof of inertness,
# and needs no disassembler, so it can never degrade into a skip. Mutation-proven on four
# separate reverts (guard drop, arm drop, flag-consumer break, cx pass-2 revert).
# 6.6.9 (bite 2): it read GREEN while six forks armed none of #must_use/#deprecated/#pure/#io/
# #alloc before the first statement. Now: one dispatcher (_tl_directive) structurally, and the
# four warnings measured in BOTH positions on every runnable fork, plus #assert, bare
# #deprecated and cx #naked rows.
_chk_gate "$ROOT/tests/gates/frontend/directive_fork_parity.sh"

# 6.6.17: the top-level scans (pass 1, pass 2, enum inits) live ONCE in src/frontend/parse_fn.cyr
# and every src/main*.cyr fork calls them; a fork that re-grows its own copy (reads PEEKT, calls
# a scan arm) is refused. Static — the byte-identical proof of the DRY is in CHANGELOG [6.6.17].
_chk_gate "$ROOT/tests/gates/frontend/toplevel_scan_shared.sh"

# v6.5.64: a fixed-lane vector op on three &local operands must emit the DIRECT form (two rbp
# loads, the packed op, one store) with its result reload ELIDED by SLASE — while a real batch
# keeps its pointer+loop kernel and stays correct. ⛔ The instruction saving is NOT the point and
# was measured worth ZERO on its own (a replica removing exactly that scaffolding ran 33.99 ms vs
# 33.96 ms); the win is the removed store-to-load forward, which is why axis 2 asserts the elided
# reload rather than a short instruction stream. Axis 3 is the anti-vacuous control: the fast path
# is chosen by token lookahead, so a loosened precondition would emit a 16-byte op over a real
# batch's extent.
_chk_gate "$ROOT/tests/gates/codegen/simd_direct_form.sh"

# v6.5.67: a `: stack` enum value is TWO registers (rax=tag, rdx=payload). Consuming it where only
# one survives must be a hard ERROR. v6.5.55 shipped the representation with nothing recording
# which calls produce a pair, so the idiomatic forwarding shape silently kept the tag and dropped
# the payload — measured p==9 (a stale rdx) where 3 was correct, exit 0, allocator delta 0, i.e.
# the v6.5.15 "failure reported as success" class on the payload. `?` was worse: rc=0 then SIGSEGV,
# because it dereferences the tag. ⭐ Axis 6 is the anti-vacuous control — a BOXED Result must be
# entirely unaffected, or the check would refuse the documented idiom at ~1,864 ecosystem sites.
_chk_gate "$ROOT/tests/gates/frontend/stack_enum_lossy_context.sh"

# v6.5.68: cycc's x86 LENGTH DECODER must be able to walk every function body cycc emits.
# `DECODE_LEN` feeds `RA_SCAN_LOOPS`, which finds the backward edges that drive v6.5.35's
# loop-aware live-interval extension in the register allocator — on the DEFAULT path — and
# nothing had ever verified it against the bytes cyrius actually emits. Two gaps: `0x99`
# (CQO, emitted before EVERY integer division) had no case, so the picker fell back to
# whole-function intervals in every function using `/` or `%`; and the whole `0F`+imm8-after-
# ModR/M class (`0F BA` BT-group, `0F 70`-`73` shift groups, `0F C2`/`C4`/`C5`/`C6`) returned
# a length ONE BYTE SHORT. ⭐ The second is why this gate walks code instead of checking a
# size: an incomplete decoder returns 0 and callers fall back safely, but a WRONG length
# desynchronises the walk over a real backward edge — and the reverted-fix mutant is byte-for-
# byte the SAME SIZE as the correct compiler, so no size or NOP-count assertion can see it.
_chk_gate "$ROOT/tests/gates/codegen/decode_len_coverage.sh"

# v6.5.68: the NOP runs the IR passes write AFTER every per-function compaction has already
# run are collected by a whole-program pass, and the COMPACTED compiler must be a working one
# that emits exactly the bytes the uncompacted one does. ⭐ The byte count only proves the
# pass ran; axis 2 — compile with the compacted compiler and compare — is the assertion that
# matters, because moving code invalidates every stored code position and ONE unrepaired
# table is a silent miscompile. v6.5.54 demonstrated exactly that by lifting the per-fn pass's
# IR gate without repairing `IR_NODE_CP`, producing a cycc that died with
# `alloc_init: mmap failed`. Seven tables are repaired here, including the entry trampoline's
# hand-emitted disp32, which no emitter registers at all.
_chk_gate "$ROOT/tests/gates/codegen/wholeprogram_nop_compaction.sh"

# v6.5.69: an `async fn` that awaits MID-BODY suspends and resumes where it left off. Before
# this, `await` lowered to a synchronous `future_force` call and a parked task re-entered its
# body FROM THE TOP — so the natural shape compiled clean and did nothing (a TTY relay written
# that way relays ZERO bytes and hangs). ⭐ Axis 1 asserts a side-effect TRACE, not a value:
# the arithmetic still lands on the right number under restart-from-top, so a value assertion
# passes on a compiler with no transform at all. Axis 2/3 are the anti-vacuous pair — an
# `async fn` with no mid-body await must compile to BIT-IDENTICAL bytes, which is why the
# transform is selected by the body rather than by the keyword.
_chk_gate "$ROOT/tests/gates/frontend/coroutine_midbody_suspend.sh"

# v6.5.71: `#derive(accessors)` getters/setters reach the inline-replay path — a measured 3.45x
# on the accessor shape, for generated code nobody hand-tunes. ⛔ Axis 2 is the load-bearing
# anti-regression: the obvious implementation (emit `#inline` into the generated text) CANNOT
# work, because derive bodies are flattened onto ONE LINE for line-number fidelity and `#` opens
# a COMMENT — so the `#` swallows the rest of that line including the NEXT `#derive`. The request
# therefore travels beside the text as a recorded name hash. Axis 1 counts CALLS, not values: an
# inlining change is invisible to a result assertion (mutation-proven — disabling the side
# channel leaves every answer correct and moves callq 3 -> 7).
_chk_gate "$ROOT/tests/gates/frontend/derive_accessors_inlined.sh"

# v6.5.72: `CYRIUS_DCE=1` REMOVES dead code instead of padding it — the flag found unreachable
# functions, overwrote them with 0x90 and reclaimed ZERO bytes while telling users to "set
# CYRIUS_DCE=1 to eliminate". ⭐ Axis 2 is load-bearing: moving code invalidates every stored
# code position, and one unrepaired table is a silent miscompile — this took four attempts and
# six distinct causes, the last being ftype-3 fixups (absolute function addresses behind
# indirect calls), which no body-level check can see because every body still decodes. A byte
# count proves the pass ran; only compiling WITH the result proves it was repaired.
_chk_gate "$ROOT/tests/gates/codegen/dce_eliminates.sh"

# 6.6.20: the compiler's own dead code is a RATCHET. In all 7 forks, every unreachable fn
# defined under src/ is on a recorded floor (tests/fixtures/dead_code_floor.txt); one that
# newly goes dead FAILS by name, and so does a floor entry that is no longer dead (so the floor
# cannot keep an allowance nobody uses). The closeout dead-code pass found the arm64 Mach-O
# writer (15.8 KB) compiled into every x86-family compiler, a superseded TS JSX walker, and
# backend stubs "kept for parse.cyr" that no shared file referenced; a floor recorded only in
# prose had let them sit.
_chk_gate "$ROOT/tests/gates/codegen/dead_code_floor.sh"


# v6.5.2: every folded stdlib that builds for Linux must also build for agnos.
# `lib/yukti.cyr` shipped SIX agnos ABI errors for months — including `sys_mount` called
# with 5 args against agnos's 0-parameter no-op stub, so yukti returned Ok() for a mount
# that never happened — because NO gate had ever compiled a folded stdlib for a non-Linux
# target. Parity (Linux-OK-but-agnos-broken) rather than "must build", since the distlib
# bundles deliberately do not carry their own stdlib deps. Reports its own coverage: 11/12
# today, niyama skipped and named.
_chk_gate "$ROOT/tests/gates/platform/folds_agnos_parity.sh"

# 6.6.12 (B14: SA8, SA9, SB4) — yukti + mabda + vani + sakshi compile together with no
# cross-fold collision. One global namespace and a duplicate only WARNS (last definition wins),
# so mabda's `var PCI_VENDOR_AMD = 0x1002` and yukti's enum `PCI_VENDOR_AMD = 0x1022` re-routed
# each other by include order, and mabda's and vani's `_sk_emit_err` did the same; vani's
# drain/drop/state returned a raw integer beside Err, read as the tag. Both yukti/mabda orders;
# each build also RUNS and must keep both vendor ids. Red on the 6.6.11 folds in both orders.
_chk_gate "$ROOT/tests/gates/toolchain/fold_namespace_collisions.sh"

# v6.5.2: ir_const_fold must not erase a following jump. EJCC/EJMP0 were the only two
# x86 emitters that recorded their IR node AFTER emitting bytes, so the node's CP was the
# END of the jump; const_fold's NOP-fill span (CP(ni+1) - CP(ni_a)) then ran 5-6 bytes long
# and swallowed it, and `return <const>;` fell through. CYRIUS_IR=3-only, so the default
# corpus was 0/253 unaffected and could never have caught it. Capstone assertion is that
# IR=3 self-hosts a byte-identical cycc — the strongest semantics-preserving statement
# available on the largest program in the tree.
_chk_gate "$ROOT/tests/gates/ir-opt/ir3_fold_jump_span.sh"

# v6.5.3: a diagnostic's LINE must survive include expansion. Main-source errors used to
# report `actual - includes_before_it` (line 2 said 1; two includes still said 1). Ten
# shapes, incl. include-once skips and a NESTED include — mutation-proven: 8 of 10 fail on
# the 6.5.2 binary, and the 2 that pass are the regression guards.
_chk_gate "$ROOT/tests/gates/diagnostics/diag_line_after_include.sh"

# v6.5.34: `#@pkgver`'s "is the constant referenced?" scan ran on the ENTRY FILE's raw text,
# before includes expanded — so CYRIUS_PKG_VERSION resolved from the entry file and failed
# from an included one, the reverse of what a byte-0 marker implies. Filed by agnostic. The
# scan moved to the tail of PP_PASS, where the unit is expanded; the declaration is emitted
# optimistically at the top and BLANKED TO SPACES if unused, so the binary of a program that
# never asked for the feature is unchanged (auto_deps_verb_gate axis 5) and no line moves.
_chk_gate "$ROOT/tests/gates/frontend/pkgver_visible_in_includes.sh"

# v6.5.5: an IR_RAW_EMIT marker only shields raw bytes until the NEXT RECORDED node.
# ESWITCH_DISPATCH_PRE recorded one marker at the top, then emitted four recorded nodes
# (EPUSHR/EMOVI/EMOVCA/EPOPR) BEFORE its raw `sub rax, rcx` / `cmp rax, rcx` — so those
# raw bytes had no node and DCE could not see they READ RCX. It eliminated the MOV_CA
# feeding them and the switch dispatched on a stale rcx. Filed against cyrius-doom as a
# LASE bug; it is DCE (CYRIUS_LASE_OFF disables the shared NOP-filler for all three
# passes, which is why the bisection pointed at LASE). CYRIUS_IR=3-only — markers emit no
# bytes, so default codegen is byte-identical and the default corpus could never see it.
_chk_gate "$ROOT/tests/gates/ir-opt/ir3_switch_dce.sh"

# v6.5.34: the three remaining CYRIUS_IR=3 divergences, one per pass — LASE eliminating a
# load whose width conversion IS the semantics, const_fold pairing operands across the NOPs
# it wrote itself, and ESTOC (`mov [rcx], rax`, the struct field store) recording no IR node
# so DCE killed the `mov rcx, rax` addressing it. That last one is the SECOND occurrence of
# the class the ir3_switch_dce gate above documents: bytes emitted with no node are bytes
# liveness cannot see. All three are IR=3-only, so all 282 corpus files passed throughout.
# With this, default-vs-IR=3 is at ZERO divergences across the whole corpus.
_chk_gate "$ROOT/tests/gates/ir-opt/ir3_substrate_correctness.sh"

# v6.5.35: the linear-scan register allocator finally USES the intervals it has computed
# since v5.6.19. Two things blocked it, and the roadmap's "it is one line" framing named only
# the first: every interval's end was force-set to the fn end (a DELIBERATE v5.6.22 guard —
# naive time-sharing miscompiles across a backward edge; measured, it fails 69 of 282), and
# `picked` was a LIFETIME cap of 5 that blocked assignment however many registers expire had
# freed. Loop-aware extension via RA_SCAN_LOOPS replaces the blanket guard; the lifetime cap
# now applies only when the bisection knob asks. -8.5% frame accesses on consumer programs.
_chk_gate "$ROOT/tests/gates/ir-opt/regalloc_cross_bb.sh"

# 6.6.20 — the whole-program compaction registries. WPJS (rel32/disp32 sources) was a fixed
# 49,152 slots that cycc's own build fills to 88 %, and one more declined the whole pass; it now
# spills to alloc'd storage. A registry that does saturate is named on the CYRIUS_IR=3 path too,
# which declined in silence (the CYRIUS_DCE=1 path has named it since 6.6.18).
_chk_gate "$ROOT/tests/gates/ir-opt/wp_compact_registry_caps.sh"

# ⛔ v6.6.1 — `f64_exp`/`f64_exp2` returned NaN for ±inf on BOTH the native x87 path and the
# aarch64 polyfill: the range reduction subtracts a multiple of the argument from itself, so
# ±inf becomes `inf - inf`. Filed from ganita's P(-1) audit, where sinh/cosh(±inf) came back NaN
# and the consumer could not tell whose bug it was.
_chk_gate "$ROOT/tests/gates/codegen/f64_exp_infinite_argument.sh"

# ⛔ v6.6.1 — `clock_now_ns()` on AGNOS read #40 (timer_ticks), which is FROZEN in a foreground
# `run` program (IF cleared, so the 100 Hz ISR never fires). Anything timing itself measured
# exactly zero. #95 (rdtsc) is the only correct monotonic source there — and cyrius already
# documented that, two files away from the code that walked into it.
_chk_gate "$ROOT/tests/gates/platform/agnos_monotonic_clock_rdtsc.sh"

# ⛔ v6.6.1 — `CYRIUS_DCE=1` emitted a PE that faulted 0xC0000005 BEFORE main, and an x86 Mach-O
# that SIGSEGV'd on real Intel-Mac hardware. v6.5.72 made DCE physically remove dead bodies and
# shrink GCP(S), but `_pe_layout(S)` runs at the TOP of FIXUP off the PRE-elimination length, so
# the import payload got written at the post-compaction cursor while the section header still
# named the old offset — the loader mapped the IAT from zero padding. The filing named only
# `--win`; Mach-O shares the path via main_x86_macho.cyr and was ALSO broken, unreported.
_chk_gate "$ROOT/tests/gates/codegen/dce_pe_macho_layout_declines_compaction.sh"

# ⛔ v6.6.1 — `cyrius install`/`cyriusly install` copied binaries IN PLACE, so reinstalling the
# version you are running overwrote the running image and died with ETXTBSY. v6.5.3 fixed exactly
# this in ONE of THREE copy paths; the tarball path (what `cyriusly install` uses) survived and
# was reported from a clean machine. The installer is frozen into each release's immutable tag,
# so a broken one cannot be hot-fixed for an already-published version.
_chk_gate "$ROOT/tests/gates/toolchain/install_atomic_over_running_binary.sh"

# ⛔ v6.6.1 — a silent miscompile that shipped in v6.5.57 and was live for 17 releases.
# `X = Y;` between two locals copied the number of slots the TYPE implies rather than the number
# the VARIABLES occupy, so assigning one struct POINTER to another wrote over neighbouring
# locals. Found only because it corrupted a loop bound in a consumer and the loop then walked
# off its buffer into the process stack.
_chk_gate "$ROOT/tests/gates/codegen/aggregate_copy_assign_slots.sh"

# ⛔ v6.6.2 — THE BOXED TAGGED-UNION PRIMITIVES, AND THE GATE THAT WOULD HAVE CAUGHT v6.6.0.
# `tagged_new` and `payload` were deleted at v6.6.0 as "nothing in the ecosystem called it
# (verified across all 12 sibling stdlibs)". The survey was real and right for those twelve; the
# CLAIM was ecosystem-wide, and the class that used the primitive — DOMAIN libraries — was never
# in scope. agnostik calls `tagged_new` 19 times, agnova 9.
#
# ⭐ THE FULL RELEASE GATE WENT GREEN THROUGH ALL OF IT, and always would: cycc's own source
# includes neither tagged.cyr nor result.cyr, so the self-host fixpoint and seed-derive are
# structurally blind to this module. An ecosystem survey cannot be PROVED from inside this repo,
# but the capability can be pinned — axis 1 reds if any boxed_* function is removed.
# Axis 2 is the subtler half: v6.6.0 also SILENTLY REDEFINED `tag()` and `is_tag()` at unchanged
# arity, so a box read returned the pointer while three documents certified the row "unchanged".
# It asserts every retired spelling produces `undefined function`, never a plausible number.
# ⛔ v6.6.2 — A SIMD INTRINSIC READ ITS DESTINATION POINTER FROM A SLOT NOTHING WROTE.
# Every f64v_*/f32v_*/iv_* handler took `var vbase = GFLC(S);` and did not raise GFLC until after
# all arguments were parsed, so an argument that allocates a frame local — the inline replay, a
# #derive(accessors) getter, a #inline fn, a callptr — bound it to the intrinsic's own destination
# slot. Filed by hisab as a 6.5.71 derive regression; it is neither derive-specific nor a 6.5.71
# regression (reachable via callptr since 6.0.70). Two failure modes: SIGSEGV with the register
# picker on, and a SILENT write into the argument object with it off.
# ⚠ The fixpoint and seed-derive are blind — cycc has zero call sites of these intrinsics.
_chk_gate "$ROOT/tests/gates/codegen/simd_intrinsic_operand_slots.sh"

# ⛔ v6.6.2 — an `object;` build exported libc-reserved names as PREEMPTIBLE globals, so a linked
# C library's own calls bound to cyrius's implementations. `memchr` returns an OFFSET or -1 where
# C returns a POINTER or NULL — inverted in both directions. samvada's process HUNG inside
# sd_bus_call_method; the link succeeded, no duplicate-symbol error, and the failure surfaced in a
# function the cyrius author never called. mabda has hand-carried an `objcopy -L` list for this,
# and that list is wrong in both directions. Now STV_HIDDEN for the 11 derived names.
_chk_gate "$ROOT/tests/gates/codegen/object_hides_libc_names.sh"

_chk_gate "$ROOT/tests/gates/toolchain/boxed_union_primitives.sh"

# ⛔ v6.6.2 — THE PROCESS FIX. A public stdlib symbol cannot disappear without an ecosystem census
# being taken and WRITTEN DOWN. v6.6.0 deleted `tagged_new`/`payload` on a survey of the 12
# fold-table stdlibs, then recorded the result as "nothing in the ecosystem" — and the class that
# used the primitive (DOMAIN libraries) was structurally invisible to that survey.
# This cannot PROVE a survey from inside the repo; it FORCES one. When a name vanishes from
# docs/api-surface.snapshot relative to the last RELEASE TAG, it censuses every sibling checkout
# — first-party AND vendored lib/ + dist/, since 55-68 repos gitignore their stdlib — and reds
# unless docs/retired-symbols.allow accounts for it with a migration reference.
# ⚠ SKIPs loudly when there are no sibling checkouts (CI) rather than passing quietly.
_chk_gate "$ROOT/tests/gates/toolchain/removed_symbol_census.sh"

# ⛔ v6.6.2 — THE GUIDE TAUGHT AN API THE COMPILER NO LONGER HAD. Its Result worked example was
# the PRE-FLIP one — five compile errors, two lines under the table announcing the arity change —
# and a second instance sat in the #derive(Serialize) section. Nothing in the tree could see it.
# ⭐ It also pins the `f32_from` contract, which NO compile can catch: `f32_from` takes an f64 BIT
# PATTERN, so `f32_from(1)` reads integer 1 as f64 bits (a denormal ~5e-324) and narrows to f32
# ZERO. Every SIMD example in the guide did that, and the same mistake had made
# tests/tcyr/simd/simd_f32v8.tcyr VACUOUS — the broken expression on BOTH sides of all 15
# assertions, so they were 0 == 0 and passed whether or not f32v8 SIMD worked.
_chk_gate "$ROOT/tests/gates/toolchain/guide_examples_compile.sh"

# ⛔ v6.6.2 — `cyrius build <foreign-src>` OVERWROTE THE RUNNING COMPILER at the v6.6.0 cut: this
# repo's manifest declares `output = build/cycc`, and the one-argument ladder means "that src +
# the manifest output", so building a TEST wrote an 842 KB binary over the compiler. Recoverable
# only because a stage binary happened to be in /tmp. The roadmap's pinned `.2` occupant.
# ⚠ The gate runs entirely in a temp tree against a COPY — pointed at the real build/cycc, the
# gate would itself be the destructive act.
_chk_gate "$ROOT/tests/gates/toolchain/build_refuses_compiler_overwrite.sh"

# ⛔ v6.6.2 — `funcgate-stage.sh` opened with an unguarded `rm -rf "$H"`, and its whole contract
# is "stage a THROWAWAY CYRIUS_HOME". Pointed at $HOME/.cyrius on 2026-09-07 it destroyed the
# entire installed store; 104 of 126 manifests under ~/Repos then pinned a version with no
# snapshot, and `_try_redirect_to_pinned` fires before dispatch, so those repos could not run ANY
# verb — not even `--version`. The only protection was a sentence in handoff.md, and this tree's
# own history says that file sat stale for thirty-eight releases at a stretch.
# ⚠ This gate does NOT stage into a live home — it drives the refusal paths with temp trees and
# a redirected HOME, so it is safe in check.sh where funcgate-stage.sh itself is not.
_chk_gate "$ROOT/tests/gates/toolchain/funcgate_refuses_live_home.sh"

# 6.6.20 — release-gate.sh step 3's verdict over a check.sh run, driven with fixtures through
# `release-gate.sh --check-verdict` (it runs neither check.sh nor the release gate). Step 3
# took check.sh's exit 0 over SKIPped gates (check.sh exits 0 on "GREEN, with N SKIPPED") and
# printed the last shell gate's tally as the driver's. Every SKIP must now be on RG_SKIP_ALLOW.
_chk_gate "$ROOT/tests/gates/toolchain/release_gate_check_verdict.sh"

# 6.6.20 — every cross-OS leg (release-gate step 4: ecb, ach, cass, pi) runs the same three cx
# checks: the guest-I/O fixture (42), the thread fixture (255) and the native cycc_cx round
# trip. The ach leg ran the thread fixture only. Static: it reads cross-os-selfhost.sh.
_chk_gate "$ROOT/tests/gates/toolchain/cross_os_legs_cx_parity.sh"

# 6.6.20 — every scripts/ file a release-tarball builder names exists. The x86-macOS builder
# `[ -f ]`-guarded a copy of a README that never existed, so it silently shipped none.
_chk_gate "$ROOT/tests/gates/toolchain/tarball_inputs_exist.sh"

# 6.6.20 — two selectors started in ONE worktree both rebuild build/cyrius_check without
# colliding: the driver compiles into a per-run side file (`.new.<pid>`), not one fixed name.
_chk_gate "$ROOT/tests/gates/toolchain/check_concurrent_selectors_one_tree.sh"

# 6.6.20 — the TLS gates' `serve` (tls_first_use_thread_race, tls_libssl_hostname_binding) reads
# a fresh log per attempt. A reused log name let the readiness grep read an EARLIER server's
# ACCEPT before the backgrounded child's truncation — the S0 flake removed as shipped at 6.6.14
# that recurred at 6.6.19. Runs each gate's own serve against a fake openssl; no network.
_chk_gate "$ROOT/tests/gates/concurrency/tls_serve_fresh_log.sh"

# v6.6.4: a RELEASED version's install slot is written from its TAG, never from a drifted
# tree. `install.sh --refresh-only` (and through it `cyrius pulsar`), `cyrius lsp` and the
# retired CLAUDE.md hand-copy recipe all keyed a store write on the working-tree VERSION —
# which between a tag and the next bump still names the released version — so the installed
# "6.6.2" stdlib was 6.6.3's byte for byte and "6.6.3"'s cross-compilers were built two
# commits before the tag. The guard refuses when tag exists ∧ tree drifted ∧ destination
# live; `scripts/verify-store.sh` audits every tagged slot against its tag (+ `--restore`).
# ⚠ Runs entirely in a mktemp mini-repo against a mktemp store — never the live ~/.cyrius.
_chk_gate "$ROOT/tests/gates/toolchain/released_slot_written_from_tag.sh"

# 6.6.20 (RS-02): `--refresh-only` installs no bin it did not rebuild. cybs (no programs/
# source) shipped a June build/cybs into 16 tagged slots, each stamped tree-matches-tag: yes,
# plus the in-flight 6.6.20; a bin or cross-bin whose mapped source is missing, or whose rebuild
# fails, now REFUSES; verify-store re-assembles cybs from the tag and names every bin it could
# not verify. Mini repos + mktemp homes only — never the live ~/.cyrius.
_chk_gate "$ROOT/tests/gates/toolchain/refresh_never_installs_a_stale_bin.sh"

# v6.6.3: every TRACKED path must be checkoutable on Windows/macOS. A file named `c -l)|XX|` —
# debris from a mis-quoted shell redirect — was committed, and the whole five-step release gate
# ran GREEN over it, cross-OS leg included, because that leg SCPs binaries to ecb/ach/cass/pi and
# never checks the repo out on them. The Windows job did, and git aborted before compiling a byte:
# "error: invalid path" / "git.exe failed with exit code 128". ⭐ It reported as "Windows PE32+
# failing" — a platform's entire coverage voided by a FILENAME, invisible to every gate we own
# because they all inspect file CONTENT. Reads the INDEX, not the worktree: the index is what CI
# checks out, so deleting the file locally does not clear this until the deletion is staged.
_chk_gate "$ROOT/tests/gates/toolchain/tracked_paths_portable.sh"

# ⚠ ORDERING (v6.6.2): `scripts/agnos-crossbuild-gate.sh` is LAST on purpose, and that matters.
# check.sh runs under `set -e`, so the first gate to exit non-zero aborts the whole script and
# every gate BELOW it silently never runs. That is exactly what happened when the seven v6.6.2
# gates were first appended after this one: the suite reported "240 passed, 0 failed", the agnos
# gate failed for an ENVIRONMENTAL reason (agnoshi pins 6.5.36, which the 2026-09-07 toolchain
# wipe removed), and not one of the new gates executed — a green summary over unrun gates, which
# is the exact shape of the macOS rot this tree keeps re-learning.
# ⭐ THE RULE: a gate that depends on a SIBLING CHECKOUT or another machine belongs at the END,
# after everything that depends only on this repo. Anything else lets an absent neighbour hide a
# real in-repo regression.

# ⛔ v6.6.0 — THE AGNOS CROSS-BUILD GATE, MOVED FROM CI-ONLY TO HERE, AND THE REASON MATTERS.
# This gate compiles ten CYRIUS_TARGET_AGNOS fixtures (net/entropy/clock/TLS #45-#55, the
# server-socket peer #56/#57, fs dir-listing, sync, io locks, signals, the GPU band, agnoshi).
# It lived ONLY in `.github/workflows/ci.yml`, so `release-gate.sh` — the thing CLAUDE.md calls
# the single consolidated pre-tag check — was structurally blind to it.
#
# ⚠ THAT BLINDNESS SHIPPED A RED CI AT v6.6.0. The Result value-form flip changed the arity of
# every Result, and three of this gate's fixtures are heredoc'd cyrius programs using the old
# boxed idiom (`var sr = tcp_socket(); ... payload(sr)`). The repo-wide migration swept `lib/`,
# `src/`, `tests/`, `programs/`, `benches/` and `cbt/` — every place cyrius CODE lives — and
# missed fixtures embedded in `scripts/`. The full release gate went GREEN (240/240, four hosts)
# and CI still failed, which is the inverse of the macOS-rot lesson and just as bad: there, a CI
# job that never ran the compiler hid a break for nine minors; here, a gate that ran ONLY in CI
# meant the local authority could not see one. A gate the release gate cannot run is not a gate
# the release gate can vouch for.
#
# ⚖️ THE OTHER THREE CI-ONLY SCRIPTS STAY IN CI, and that is a decision, not an oversight.
# `funcgate-stage.sh` / `funcgate-posix.sh` STAGE AN INSTALL into $CYRIUS_HOME and then drive the
# installed CLI end-to-end; running them from check.sh would rewrite the developer's live
# ~/.cyrius in the middle of a check — and this release lost the whole toolchain once already by
# treating that tree as scratch. `build-cycc-verify.sh` is a packaging verifier for the release
# tarball, not a source gate. All three were run by hand at the v6.6.0 cut and pass; the agnos
# gate is the one that both compiles cyrius source AND could regress from a language change,
# which is exactly the class that belongs in the local gate.
_chk_gate "$ROOT/scripts/agnos-crossbuild-gate.sh"

# ⛔ 6.6.5 — rsp was 8 bytes off 16-byte alignment at any call emitted INSIDE an expression.
# cycc's expression codegen is a stack machine (`push rax` per pending value) and nothing
# padded for those pending values at a call; the only alignment invariant was the frame
# rounding, which holds BETWEEN statements. `f(0, c())` entered its callee misaligned and
# `var t = c(); f(0, t);` did not, so a C callee spilling SSE with `movaps` — what gcc emits
# for ordinary code — took a #GP. Filed from mabda 4.1.3 (a SIGSEGV inside NVK's
# create_buffer) and, underneath it, the whole PE base was INVERTED: Windows enters at
# rsp ≡ 8 and cyrius never re-aligned, so on Windows it was the STATEMENT-level calls that
# were misaligned, including cyrius's own CreateFileW reroute.
#
# ⭐ This gate uses a gcc-assembled leaf that measures `(rsp+8) & 15` with the CPU. The fix
# added a compile-time depth counter, and a gate that asked THAT counter would share the
# model it is checking — measured: making ECALLCLEAN skip the emitted `pop rcx` while STILL
# decrementing `_xdepth` produces ZERO compile-time desync reports and 24 misaligned rows
# here. (Deleting the byte AND the decrement is a different mutant and DOES desync, 200
# reports; the gate header carries the full ledger.)
#
# 6.6.5 second cut: it also enforces a ROW FLOOR. The driver keeps a row counter and used
# not to return it, so deleting rows from run() left this gate printing PASS with the same
# message. Two independently derived counts now have to agree with each other and clear 56:
# the probe call sites grepped STATICALLY out of the driver source, and the `ROWS nnn` line
# the driver prints at RUNTIME.
_chk_gate "$ROOT/tests/gates/codegen/call_site_stack_alignment.sh"

# 6.6.6: past the int register ceiling the CALLEE must home each int parameter from its
# int-class ordinal into its own frame slot, counting stack slots from the CALLER's int-class
# total. The old second pass re-derived all three from `pc` (every parameter, any class), so a
# value-form vector next to 6+ ints — or an x86 retptr — bound later ints to the wrong slots,
# silently, on every backend. A generated matrix (vector class x position x 5..9 ints, two
# vectors, struct return) with digit-string expectations, on x86 + aarch64 (qemu) + cx (cxvm)
# + Win64 (wine). Hardware legs: tests/tcyr/crossos/simd_param_int_stack_args.tcyr.
_chk_gate "$ROOT/tests/gates/codegen/stack_param_homing_matrix.sh"

# 6.6.20: an aarch64 call of ANY width takes back exactly the stack it pushed and reads every
# argument, and a local past 64 KiB keeps its value. ECALLCLEAN's `add sp, sp, #imm12` was
# unguarded: from 262 arguments sp was never restored (`#0, lsl #12`), at 263 it moved 64 KiB,
# at 518 an MTE `addg` (SIGILL on pi / Apple Silicon), SIGILL everywhere from 519; the [sp,#imm]
# marshalling past 2048 arguments read slots 32 KiB low (its `str` became an `ldr`), the callee's
# [x29,#imm] past 2053 parameters likewise, and every fp displacement past 64 KiB (param 8192+,
# any local after a 64 KiB buffer) went through a 16-bit-truncated `movz`. cx had the frame-size
# half too: ESUBRSP's lone `movi r252` lowered sp by a 64 KiB+ frame's size mod 64 KiB (now a
# movhi slot). Static words derived in the shell + qemu-aarch64 runs at the measured thresholds
# and a frame probe (exit 77 without qemu) + the host oracle + a cxvm leg (frame probe, the
# twin's cx rows). Hardware: tests/tcyr/crossos/wide_call_stack_unwind.tcyr.
_chk_gate "$ROOT/tests/gates/codegen/wide_call_stack_unwind.sh"

# 6.6.6: the CHECK DRIVER's own children are bounded, and none outlives the runner. Every
# fork site in programs/checks/ and lib/regression.cyr was fork + execve + BLOCKING waitpid
# with no deadline and no death signal, so one spinning .tcyr hung check.sh itself (measured
# ~5 min this release, no output, no verdict) and killing the run reparented the test to PID
# 1 where it kept burning a core — the v6.5.19 `cyrius test` incident, one runner over. Axis
# 1b is the one that matters and the first cut of the gate did NOT have it: with PDEATHSIG in
# place, a deadline that ABANDONS instead of killing passes every single-child axis.
_chk_gate "$ROOT/tests/gates/toolchain/check_driver_bounded.sh"

# ⛔ 6.6.5 — a fn-local STRUCT LITERAL was a GLOBAL slot, and whether an aggregate local was
# inline or a pointer was GUESSED from the neighbouring slot's name. The first made a literal
# shared across recursion, threads and files (a global and a fn-local literal of the same name
# in ONE file returned 2 where 6 is right, silently, with no `private` involved). The second
# was wrong since 5.8.17 for any pointer-mode struct local declared after a closed block or
# after a callptr / bitset / SIMD temporary — SCOPE_POP writes the same -1 marker the guess
# read as "inline" — and it was live in a consumer: stiva's fleet.cyr let a 512 MB node pass a
# 1024 MB memory constraint. The gate below carries the two-file and env-var axes the .tcyr
# corpus cannot express, plus the aarch64/cx emulator legs; the hardware legs are
# tests/tcyr/crossos/aggregate_storage_class.tcyr + hidden_temp_reentrancy.tcyr.
_chk_gate "$ROOT/tests/gates/codegen/fn_local_storage_class.sh"

# 6.6.5 — the CENSUS under it. The hidden-temporary defect was a HABIT, not one lowering: five
# constructs each open-coded the same four lines to get a scratch word and each passed name
# offset 0, which is the program's FIRST LEXED WORD. This pins the SHAPE at the source so the
# sixth cannot slip in, with derived counts and an anti-vacuous floor on every axis.
_chk_gate "$ROOT/tests/gates/codegen/hidden_temp_census.sh"

# 6.6.7 (bite 1): `defer` / `break` / `continue` in a position they cannot honour are refused
# with a named diagnostic and no binary (top-level defer, return/`?`/break/continue out of a
# defer body, break/continue with nothing to leave in the same fn — incl. from a closure), and
# `defer` in a coroutine `async fn` runs exactly once, at completion. Shell gate because the
# refusals are compile-time and CYRIUS_ASYNC cannot be set from a .tcyr. The runtime nested-fn
# rows are tests/tcyr/crossos/defer_every_return_path.tcyr.
_chk_gate "$ROOT/tests/gates/diagnostics/defer_misuse_refused.sh"

# 6.6.7 (bite 2): a defer / secret runs on EVERY return path (tail-shaped `return f(..)` and
# `return Ok(x)` included) with the whole return convention intact, and never rides an inline
# replay. The runtime rows are tests/tcyr/crossos/defer_every_return_path.tcyr; this gate adds
# what a .tcyr cannot reach — async (CYRIUS_ASYNC), the #inline warning, the aarch64 (qemu) /
# PE (wine) legs of that tcyr, and cx rows — every compiler built from source.
_chk_gate "$ROOT/tests/gates/codegen/defer_every_return_path.sh"

# 6.6.7 bite 5 — a `#derive` whose field table disagrees with the parser's struct layout fails
# the build (an `#assert sizeof` inside the first generated fn body — never at top level, where
# it would end the declaration phase and reject every later struct/enum).
_chk_gate "$ROOT/tests/gates/diagnostics/derive_layout_backstop.sh"

# 6.6.7 bite 3 — fsync/fdatasync (74/75) FLUSH on PE (kernel32!FlushFileBuffers) and
# MoveFileExW is write-through. POSIX oracle + emitter shape (the write-through bit's ONLY
# guard — nothing can observe durability) + wine; hardware is the cass leg.
_chk_gate "$ROOT/tests/gates/platform/pe_fsync_flushes.sh"

# 6.6.7 bite 4 — every agnos syscall site hands the kernel a defined a4 (r10): its own 4th arg
# or an explicit zero. agnos read#5/write#1 block only when a4 == 0; an undefined r10 made one
# println block or drop bytes by call history. Disassembly class check + agnos-only proof.
_chk_gate "$ROOT/tests/gates/platform/agnos_syscall_a4_defined.sh"

# 6.6.7 bite 4 — the agnos peer RUN against a scripted fake kernel (PTRACE_SYSEMU,
# tests/fixtures/agnos_sctrace.cyr): the registers each wrapper hands the kernel — a4 defined,
# spawn/redirect/endow argument packing and guards, the wait/kill/peer surface, the loopback
# listen class; 6.6.17: the BSD socket verbs (sys_socket..sys_accept4) on the adapter, their
# arity against the Linux-common wrappers, and the agnos build of the CLI (cbt/cyrius.cyr).
_chk_gate "$ROOT/tests/gates/platform/agnos_peer_fake_kernel.sh"

# 6.6.7 bite 4 — an agnos socket read waits for its deadline on a REAL clock (#95, then the RTC
# armed on its first non-zero read, then — only with no clock — the pause count) and a timeout
# is -11, not EOF; a stalled send is retried. Fake-kernel tiers + a live mirshi TCP exchange.
_chk_gate "$ROOT/tests/gates/platform/agnos_sock_recv_bound.sh"

# 6.6.20 (NET-01) — lib/ws.cyr's ws_close closes its socket through sock_close, never a raw
# syscall(3) (agnos spawn: no FIN, a leaked conn slot, a disarmed endowment; Windows CloseHandle
# on a SOCKET). Fake-kernel axes (#50 not #3, the slot reused, 10 cycles on 8 slots) + a PE
# disassembly of the ws_close body (calls sock_close, never the CloseHandle import).
_chk_gate "$ROOT/tests/gates/platform/ws_close_socket_route.sh"

# 6.6.13 (I8-prim) — _agnos_sock_send_dl(rearm=0) bounds an agnos socket send by the CALLER's
# deadline (the whole transfer, progress or not); rearm=1 — sys_write's route — keeps the 6.6.7
# stall bound. agnos has no poll, so this is native TLS's write deadline there. Fake kernel.
_chk_gate "$ROOT/tests/gates/platform/agnos_sock_send_deadline.sh"

# 6.6.13 (I8, CYRIUS-2026-0017) — native TLS's per-connection deadline on agnos: a record read hands the
# time left to sock_recv's poll, a record write to _agnos_sock_send_dl(rearm=0), so the CALLER's
# deadline (not the socket's 30 s default, not a re-armed stall bound) ends them with
# TLS_ERR_TIMEOUT; no deadline, no change. Fake kernel (agnos has no poll and no SSH host).
_chk_gate "$ROOT/tests/gates/platform/agnos_tls_deadline.sh"

# 6.6.7 — a REFUSED MAPPING is 0 from fl_alloc (never a store through -ENOMEM), and PE
# alloc_init aborts loudly on a refused VirtualAlloc like its Linux/macOS peers. Axis 2 is the
# arena refill under `ulimit -v`, which the crossos .tcyr cannot reach portably.
_chk_gate "$ROOT/tests/gates/memory/alloc_failure_returns_zero.sh"

# 6.6.20 (HEAP-09) — a compiler that cannot map its 246 MiB arena refuses by name instead of
# dying with SIGSEGV 139 and no message: x86, the aarch64 cross, cx and the PE host stage under
# `ulimit -v`, x86 under `ulimit -d`, the native aarch64 fork under qemu across a limit sweep.
_chk_gate "$ROOT/tests/gates/memory/compiler_arena_refused.sh"

# 6.6.7 (bite 9) — the lint and doc walkers FAIL CLOSED. A cyrlint/cyrdoc that crashed, hung,
# refused the file or did not exist scored "0 findings" in `cyrius audit`, the driver's lint
# suite and CI (live in rekha: a 1.65 MB file cyrlint refuses read "ok: lint clean"). Drives
# the walkers against fake and real tools, the driver's lint suite against a fake cyrlint, and
# `cyrius audit` over the rekha shape; each fix is mutation-proven in the gate header.
_chk_gate "$ROOT/tests/gates/toolchain/audit_walk_fails_closed.sh"

# 6.6.10 (bite 15) — every tree walker FAILS, by name, on a directory it cannot list. lib/fs.cyr
# read an unreadable directory as empty and is_dir called it a file, so `chmod 000 tests/bad` made
# `cyrius test` read "1 passed, 0 failed" rc 0 and `cyrius audit` "ok: lint clean". W1-W13: test,
# tests, audit, fuzz, bench, deps --lock/--verify, clean, cyrius_type_audit, cyriusly list, the
# smoke/soak harness ROOT, vidya_load_dir; the chmod rows SKIP by name under root. A1-A4 (every
# uid): an ABSENT directory stays an empty scope, not an error. Proven red on the 6.6.9 tree.
_chk_gate "$ROOT/tests/gates/toolchain/walkers_fail_closed_unreadable_dir.sh"

# 6.6.10 (bite 15) — cyrius-lsp indexes every declaration spelling through cbt/srcscan.cyr's
# `_src_decls` (the reader coverage and distlib use): pub/public, attributes, indentation,
# fn<TAB>, generics, pub/secret var, destructures, enums + members, structs — and nothing in a
# comment, a string or a fn body; files read whole (past 1 MiB). The 6.6.9 LSP fails 15 of 25.
# 6.6.12 (B11, S3), axis 5: the symbol index has no silent cap — the last of 6000 long-named fns
# in one include, a fn in the 300th included file and sigil's last fn all resolve (the 6.6.11
# LSP's fixed row / names / paths / file caps answered null past the cut).
_chk_gate "$ROOT/tests/gates/toolchain/lsp_indexes_every_decl_spelling.sh"

# 6.6.17 — cyrius-lsp reads the open document sized by fstat (it was a fixed 1 MB read, so a
# definition past the cut answered null) and refuses a document over 64 MiB by name.
_chk_gate "$ROOT/tests/gates/toolchain/lsp_reads_whole_document.sh"

# 6.6.7 (bite 10) — the NEXT version-bump can rewrite every document anchor in the live tree.
# Step 5's stamp sed admitted only a date in the parenthetical, so the hand-annotated stamp
# matched nothing and the bump exited 0 (twice: 6.6.7, and — measured — 6.6.8); steps 3/4
# were unverified and the "Updated:" list was unconditional. Runs `version-bump.sh
# --docs-only` over scratch copies of the live docs plus fixtures; mutation-proven in the header.
_chk_gate "$ROOT/tests/gates/toolchain/version_bump_doc_anchors.sh"

# 6.6.8 (bite 1) — a TOP-LEVEL `for x in a..b` / `for x in vec` binds a live global. Its loop
# variable was a fn FRAME slot, and top-level code has no frame: every one segfaulted (x86,
# aarch64), page-faulted under wine, or wrote into dyld's frame on arm64 Mach-O, and every
# read of the name was undefined. Host rows + qemu/wine legs; mutation-proven in the header.
_chk_gate "$ROOT/tests/gates/frontend/toplevel_for_in.sh"

# 6.6.8 (bite 1b) — a `#` directive inside a `#derive`d declaration (or between the `#derive`
# line and it) is refused by name: the derive's walk read it as a comment and counted the fields
# of every branch, while the parser compiled one. Mutation-proven in the header.
_chk_gate "$ROOT/tests/gates/frontend/derive_directive_refused.sh"

# 6.6.8 (bite 1b) — a forwarded type parameter (`inner<T>(p)` in a generic body) resolves to its
# binding; it read as "no type" and silently hit the i64 base (outer<Pt> returned 2, want 16). A
# type-arg naming no type is refused by name. Mutation-proven in the header.
_chk_gate "$ROOT/tests/gates/frontend/generic_type_arg_unknown_refused.sh"

# 6.6.8 (bite 1b) — inside a coroutine `async fn`: fncallN / callptr / a closure call through the
# HEAP-frame slot (ECALLIND called the stack slot: SIGSEGV), and a completed coroutine answers a
# later force with its value instead of resuming its last suspend. Mutation-proven in the header.
# 6.6.12 (B05, T8b): axis M — no dead jmp +0 after a coroutine's resume dispatch.
_chk_gate "$ROOT/tests/gates/frontend/coroutine_fnptr_and_completion.sh"

# 6.6.8 (bite 2) — every syscall a macOS build reaches is ROUTED on both Macs: each literal site
# at its real arity (probed through the Mach-O compilers' own diagnostic, per a Darwin reach
# table), and every shipped program / crossos test compiled for each Mac with zero "not routed"
# warnings. An unrouted arm64-macOS number used to re-run the previous syscall silently; the
# class shipped eight times. Controls + mutation ledger in the header.
_chk_gate "$ROOT/tests/gates/platform/darwin_syscall_literals_routed.sh"

# 6.6.10 (bite 14) — the WHOLE .tcyr corpus compiles for PE, x86 Mach-O, arm64 Mach-O and agnos,
# or the file is on that leg's allowlist, and the allowlists only SHRINK (an allowlisted file that
# compiles is a FAIL too). Nothing cross-built tests/tcyr outside crossos/: 9 PE, 1 Mach-O and 37
# agnos files did not compile. Axis 0 (a never-compiles and an always-compiles fixture per leg) and
# a 350-file floor keep it from reading nothing. Mutation ledger in the header.
_chk_gate "$ROOT/tests/gates/toolchain/tcyr_corpus_cross_compiles.sh"

# 6.6.10 (bite 14) — a refused alloc() in the first-party stdlib returns the fn's sentinel: a lib/
# copy whose alloc refuses exactly the k-th call drives ~45 fns in three probes (67 + 12 lib/ws.cyr +
# 11 lib/ws_server.cyr rows, ~1 s) — each returns its sentinel, REACHES the k-th call, and succeeds
# at count+1. Complements T's static census.
# Mutation ledger in the header.
_chk_gate "$ROOT/tests/gates/memory/stdlib_alloc_refusal_sentinels.sh"

# 6.6.8 (bite 3) — unshare / chroot / pivot_root / capget / capset / process_vm_* / mknodat are
# named in every peer, wrapped on every target, and on ELF-aarch64 the x86 number each peer
# spells reaches the kernel as that call (qemu-aarch64 -strace axis; decoded ESYSXLAT rows
# judged against the committed kernel tables). Mutation ledger in the header.
_chk_gate "$ROOT/tests/gates/platform/ns_caps_family_routed.sh"

# 6.6.8 (bite 3) — fcntl goes through sys_fcntl and O_NONBLOCK through fd_set_nonblocking, whose
# bit is private and per-target (a fold that redefines the public O_NONBLOCK — yukti's EjectConst
# did — cannot change it); no in-tree code hand-rolls either; PE / agnos decline with -38; the
# crossos test runs on the host and under qemu-aarch64. Mutation ledger in the header.
_chk_gate "$ROOT/tests/gates/platform/fcntl_wrapper_only.sh"

# 6.6.8 (bite 4) — an INT-left `+ - * /` with an f64 right operand WARNS (kind 2 of
# _FLT_TYPE_WARN): `0 - 1.5` was integer arithmetic on 1.5's bits (-3.0), silently. WARN only,
# the ADR-002 posture of kind 1; no false positive on unary minus, f64/f64 or int/int.
_chk_gate "$ROOT/tests/gates/diagnostics/f64_int_mix_warn.sh"

# 6.6.8 (bite 6) — the Linux heap comes up on a board smaller than its 256 MB first chunk: the
# grain-sized chunk is MAP_NORESERVE and a refusal falls back to 16 MB chunks (as PID 1 in a
# -m 256M VM it panicked). Row 4, the starved-VM PID-1 boot, is opt-in: CYRIUS_ALLOC_VM=1.
_chk_gate "$ROOT/tests/gates/memory/alloc_first_chunk_small_board.sh"

# 6.6.8 (bite 6) — every allocation check lib/io.cyr gained holds when ITS call alone is
# refused (per-call fault injection): file_write_atomic / file_replace_atomic / getenv.
_chk_gate "$ROOT/tests/gates/memory/io_alloc_refused_per_call.sh"

# 6.6.8 (bite 6) — cx runtime foundations: cxvm's register file holds fp/sp, atomic_cas /
# fetch_add work on cx, the hash seed is published / OS-drawn / varies, clock_gettime is
# translated, and call_site_stack_alignment.tcyr runs on cx.
_chk_gate "$ROOT/tests/gates/toolchain/cx_runtime_foundations.sh"

# 6.6.8 bite 7 — lib/process_agnos.cyr against the fake kernel's proc* modes: spawn_path#43 with
# SPAWN_F_ARGV|CLEANFD and the exact argv blob, WAIT_BLOCK (and its pre-1.57.7 poll fallback), a
# capture that reads to EOF BEFORE it reaps, refusals before any syscall, no spawn#3 / 8 MB alloc.
_chk_gate "$ROOT/tests/gates/platform/agnos_process_spawn.sh"

# 6.6.8 bite 7 — an accepted agnos socket inherits its listener's recv/send timeouts (Linux
# semantics), and an outbound conn that reuses the conn_id does not.
_chk_gate "$ROOT/tests/gates/platform/agnos_accept_timeout_inherit.sh"

# 6.6.8 bite 7 — the agnos peers of process.cyr and regression.cyr define every host verb at the
# same arity (derived from the #ifndef CYRIUS_TARGET_AGNOS regions, not a hand list).
_chk_gate "$ROOT/tests/gates/platform/agnos_process_peer_parity.sh"

# 6.6.10 bite 13 — lib/regression_agnos.cyr's spawn / capture / deadline verbs run real children
# (they were constant stubs): pipes on fds 0/1/2 armed through #62, outputs DRAINED by one
# interleaved non-blocking pump (a write-all-then-read pump deadlocks: mode rgin), the source
# streamed, kill_tree(9) at the deadline, counted in the SHARED regression_deadline_kills;
# terminate_children over proclist#99. Fake kernel, stateful rg* modes; mutation ledger in the header.
_chk_gate "$ROOT/tests/gates/platform/agnos_regression_spawn.sh"

# 6.6.10 bite 13 — lib/async_agnos.cyr: async_timeout forks the body (it ran INLINE and ignored
# `ms`), reads only a whole 8-byte result, and kills the child's tree at the deadline;
# async_run_process spawns from disk under a deadline; async_spawn_process is a serial task. Fake
# kernel as* modes (fork answered as the parent OR the child — one side per trace).
_chk_gate "$ROOT/tests/gates/platform/agnos_async_process.sh"

# 6.6.8 (bite 9) — `cyrius header` had NO gate. It matched only a column-0 `pub fn `, so a bare
# `fn` and `public fn` (the same token) never got a prototype, it ignored the file-scope
# `private` rule, and it read a fixed 64 KiB (every fn past the cut silently dropped, rc=0).
# Spellings, the private rule and a >64 KiB file; mutation-proven in the gate header.
_chk_gate "$ROOT/tests/gates/toolchain/header_spellings_and_size.sh"

# 6.6.8 (bite 10) — `cyrius vet` / `deny` (cyaudit) see exactly the compiler's includes: column 0,
# outside a string, the WHOLE file (a fixed 256 KB read hid a later include from both, rc 0), and
# a path judged by COMPONENT (`lib/../../x` was trusted by vet and passed deny). The compiler is
# the oracle for what an include is; mutation-proven in the header. 6.7.3 axis 7: an ATTRIBUTE
# line is code (PP_LEXST_AT), so its multi-line string no longer hides the next include from
# vet / deny; cyaudit's word list is held to LEXATTRWORD's.
_chk_gate "$ROOT/tests/gates/toolchain/cyaudit_include_directives.sh"

# 6.6.8 (bite 10) — `cyrius api-surface` lists exactly what the COMPILER emits: the `#derive`
# families by name, arity (`_to_json` is `(ptr, sb)`) and visibility (a `private` file), plus
# `pub fn` and wrapped signatures. The oracle is the compiler's own emission, both ways (every
# listed fn is callable at its arity from another file; every omitted one is private).
_chk_gate "$ROOT/tests/gates/toolchain/api_surface_derive_matches_emitter.sh"

# 6.6.8 (bite 8) — every gate under tests/gates/ is registered EXACTLY ONCE and runs through
# `_chk_gate` or the driver; ten 6.6.6 gates were bare `sh` lines no selector could reach.
_chk_gate "$ROOT/tests/gates/toolchain/check_gate_census.sh"

# 6.6.9 (bite 1) — compile time is LINEAR in the global count: constants, enum members,
# deferred initializers and references at 10k vs 20k, as a ratio (limit 3.0x; the 6.6.8
# compiler read ~4x on every row — the var table had no name index, so each registration paid
# two full STREQ walks and every reference a reverse one).
_chk_gate "$ROOT/tests/gates/frontend/globals_scale_linear.sh"

# 6.6.19 (B0b) — string-literal interning is LINEAR in the literal count: LEX scanned the whole
# string pool for every new literal (3k 573 ms, 9k 4,983 ms; a 1.9 MB literal ahead of 3k small
# ones 11.4 s vs 0.92 s after them). Ratio rows (N vs 2N literals < 3.0x; blob before vs after
# < 2.0x) + semantic rows (sharing unchanged, B0a's repro, a #deprecated message wound back).
_chk_gate "$ROOT/tests/gates/frontend/string_intern_scale_linear.sh"

# 6.6.10 (bite 2) — a TOP-LEVEL destructure grows the var table before storing its names:
# gi1+1/gi1+2 were written before SVCNT, past the 8192 band (aliasing var_sizes[0]/var_types[0]:
# a lost name, or g0 silently read 0) and at the grown 16384 cap into the next table. 8 rows,
# both caps.
_chk_gate "$ROOT/tests/gates/frontend/toplevel_destructure_var_cap.sh"

# 6.6.20 (HEAP-02, the use-alias table overflow bug) — the `use mod.fn;` alias table refuses its 65th entry by name before
# any store: use_from / use_to abut, so the 65th alias re-bound alias #1 (a silent wrong call) and
# later ones walked the heap to gvar_cnt (SIGSEGV past ~5062). 5 rows: 64 resolves, 65/200/5100 refused.
_chk_gate "$ROOT/tests/gates/frontend/use_alias_table_cap.sh"

# 6.6.9 (bite 2) — a REACHABLE undefined call is refused on every backend whatever its shape:
# an aarch64 TAIL call (fixup type 4) used to build rc 0 and die SIGILL, and a reference from an
# unreachable fn that came first hid every later live call of the same fn (x86/aarch64/PE). The
# four aarch64/Mach-O forks now print the pre-pass "undefined function" warning like x86.
_chk_gate "$ROOT/tests/gates/diagnostics/undefined_tail_call_refused.sh"

# 6.6.9 (bite 2) — the "large static data" advisory prints on x86/x86-Mach-O/PE/aarch64/
# arm64-Mach-O/cx, not x86 ELF alone; silent for small statics and for cx's own alloc heap.
_chk_gate "$ROOT/tests/gates/diagnostics/large_static_data_every_backend.sh"

# 6.6.9 (bite 3) — a "requires lib/<x>.cyr" / "async is gated" error EXITS 1 on every backend:
# aarch64 (7 f64 polyfills, slice, await, async fn) and cx (slice, await, async fn) used to
# SIGSEGV (rc 139) right after the diagnostic, decoding the -1 fn index as a var fixup.
_chk_gate "$ROOT/tests/gates/diagnostics/missing_helper_error_exits_1.sh"

# 6.6.13 (M2) — `var a: T[N]` is sized by its element (tests/tcyr/crossos/typed_array_elem_size.tcyr
# runs the sizes on every host). This pins the compile-time half: a non-integer element's subscript
# is refused (the decl-zone `i8v16[4]` one compiled), an unknown or later-declared element type is
# refused by name, N * sizeof(T) cannot wrap, and bool / enum / cstring / a generic fn's own T[N]
# (default and CYRIUS_MONOMORPH=0) keep compiling.
_chk_gate "$ROOT/tests/gates/diagnostics/typed_array_elem_refusals.sh"

# 6.6.16 (C8) — one type-name resolver (tests/tcyr/frontend/type_name_resolver.tcyr runs the
# sizes): a name that is no type, or a prefix misspelling (`i8x`), is refused by name at every
# annotation site, sizeof and #assert sizeof — once, no cascade, no binary — and every name of the
# vocabulary still compiles where it is taken (a Str param by name, enums, type parameters).
_chk_gate "$ROOT/tests/gates/diagnostics/type_name_refused.sh"

# 6.6.17 (a5) — `var a, b = f();` where f provably returns ONE value (pass 1 records it, so a
# forward call is judged too) is refused naming f, at fn scope and in both top-level zones; the
# declaration zone gets the whole destructure contract. Pair-carrying callees still destructure.
_chk_gate "$ROOT/tests/gates/diagnostics/destructure_one_value_refused.sh"

# 6.6.16 (C1) — a global array initializer `var X: T[N] = { .. }` is N elements of T, baked into the
# image (tests/tcyr/crossos/global_array_initializer.tcyr runs the values on every host). These pin:
# the shapes it refuses by name (count, range, a non-constant, an element type no list fills, a list
# inside a top-level block); that a `kernel;` build (x86 and EFI) carries the bytes in its image
# with no store behind the program; and that cx bakes the same bytes into the .cyx var data that
# cxvm copies into the guest, and they hash equal to the host image's (and aarch64's under qemu).
_chk_gate "$ROOT/tests/gates/frontend/array_initializer_refusals.sh"
_chk_gate "$ROOT/tests/gates/platform/kmode_array_initializer_baked.sh"
_chk_gate "$ROOT/tests/gates/codegen/cx_array_initializer.sh"

# 6.6.16 (C6) — in an x86 `kernel;` build a global initializer that names an enum holds its value
# from the first instruction: a scalar that folds and an all-constant struct literal are baked into
# the image (run under CYRIUS_ELF64_KERNEL=1, image-scanned for the default kernel build and EFI),
# and what the late replay still runs is named once per declaration — true only there (no warning
# in a host build, an aarch64 kernel build, or an EFI build with efi_main).
_chk_gate "$ROOT/tests/gates/platform/kmode_enum_initializer_baked.sh"

# 6.6.13 (M3) — inside a closure, copying a captured struct copies its bytes
# (tests/tcyr/crossos/closure_capture_struct_copy.tcyr runs the copies on every host). This pins
# the compile-time half: a captured struct or vector of ANOTHER type is refused by name in the field
# store, struct literal, assignment and declaration, as the local form is, and emits no binary.
_chk_gate "$ROOT/tests/gates/diagnostics/closure_capture_struct_copy_mismatch.sh"

# 6.6.9 (bite 3) — `return None();` (any nullary `: stack` variant) beside `return Some(v);` is
# a whole variant, not a dropped tag: no mixed-return warning. The dropped-tag shapes still warn.
_chk_gate "$ROOT/tests/gates/frontend/stack_enum_mixed_return_warning.sh"

# 6.6.16 (H2) — a closure's `return <: stack call>` belongs to the CLOSURE: the pair scans skip a
# closure body, so the enclosing fn is neither refused "bind both" nor warned. The filed hisab
# repro runs verbatim against the tree through a throwaway home; real mixed returns still warn.
_chk_gate "$ROOT/tests/gates/frontend/stack_enum_closure_return_scope.sh"

# 6.6.16 (H1) — fncall0..8 and callptr at TRUE TOP LEVEL dispatch an escaped capturing closure:
# a top-level indirect call opens its own micro-frame (it was never lowered there: SIGSEGV on
# x86/aarch64, 0xC0000005 on PE, 0 for every callee on cx; callptr was refused). The filed hisab
# repro and closure_escape_dispatch.tcyr's top-level section on x86, qemu, wine and cxvm.
_chk_gate "$ROOT/tests/gates/codegen/toplevel_indirect_call.sh"

# 6.6.16 (C5) — a named `fn` / `async fn` inside a fn body, closure, impl method or generic body
# is ONE named error ("fn 'inner' is defined inside fn 'outer'"), its tokens skipped so nothing
# cascades — it used to compile and crash (SIGILL / SIGSEGV). A fn in a top-level block still runs.
_chk_gate "$ROOT/tests/gates/diagnostics/nested_fn_refused.sh"

# 6.6.16 (C9) — `#deprecated("msg")` warns EXACTLY ONCE, on the call's own line, on every path:
# a call before the definition (pass 1 now records it), `&f`, `o.m()`, the struct receives,
# operator dispatch, the PE vector paths, a generic instance, an `#inline` / generic re-parse;
# a tail call is reported at 14:18, not the next token. Binaries identical without the attribute.
_chk_gate "$ROOT/tests/gates/diagnostics/deprecated_every_call_path.sh"

# 6.6.17 — C9's twin for `private`: a tail call's error names its own line, not the `}` after it;
# and `expected '}', got end of file` names <file>:line:col just past the last source byte (it
# had no file and a line past the end, and an included file's EOF showed a `#@file` marker).
_chk_gate "$ROOT/tests/gates/diagnostics/diag_location_eof_and_tail_private.sh"

# 6.6.17 — four false warnings on valid code, each with a row proving the warning still fires on
# a wrong shape: `undefined function` for a fn in a top-level block called earlier, and `assigning
# non-pointer to typed pointer` for a same-typed global, a `: Str` method and a `: Str` field.
_chk_gate "$ROOT/tests/gates/diagnostics/false_warnings_valid_shapes.sh"

# 6.6.17 — a fn attribute lands on the definition it precedes: not on a generic instance a
# top-level statement mints in between, and on an impl method (whose body refused every
# directive); #must_use and #pure's #io / #alloc checks reach the dot call `p.m(..)`.
_chk_gate "$ROOT/tests/gates/diagnostics/attribute_lands_on_its_item.sh"

# 6.6.16 (C10) — cycc's `lib/...` include fallback reads CYRIUS_HOME's store slot, else HOME's,
# from the WHOLE environment: both orders, empty = unset, no fall-through to HOME, past 4 KB / 8 KB
# and across read boundaries, the 1984-B bound never truncated — x86, aarch64, cx, the PE cross and
# the native aarch64 fork under qemu, all built from the tree. The selection is the compile's own
# reachable-undefined refusal, so nothing has to run.
_chk_gate "$ROOT/tests/gates/toolchain/include_fallback_cyrius_home.sh"

# 6.6.17 — the CLI picks its home by cycc's rule (first duplicate wins, empty = unset, the whole
# environment read): `cyrius which` and an include-fallback probe agree on every row; a 600+ B
# CYRIUS_HOME is read by cyrius.exe under wine (SKIP by name without wine).
_chk_gate "$ROOT/tests/gates/toolchain/cli_home_matches_cycc.sh"

# 6.6.9 (bite 3) — a second struct/union with a different layout (the first silently won) and
# an enum constant over a zero/computed global of the same name are warned, not silent.
_chk_gate "$ROOT/tests/gates/frontend/redefinition_layout_and_enum_over_var.sh"

# 6.6.9 (bite 4) — x86 f64_sin / f64_cos (ELF, PE, x86 Mach-O) call lib/math.cyr's fdlibm polyfill,
# not x87 fsin / fcos (66-bit π: sin(π) 1.6e11 ulp off, |x| >= 2^63 returned unchanged).
_chk_gate "$ROOT/tests/gates/codegen/x86_trig_calls_polyfill.sh"

# 6.6.9 (bite 5) — O_NOFOLLOW / O_DIRECTORY / O_CREAT|O_EXCL mean on PE what they mean on Linux
# (CreateFileW resolved a final reparse point for EVERY disposition: O_EXCL over a dangling link
# created its target, O_NOFOLLOW|O_TRUNC truncated a link's target, O_DIRECTORY opened files).
# 6.6.11 (B06, I1+I2) — and a path is used under ITS OWN NAME: the seven narrow-path reroutes
# widened one BYTE per WCHAR and cut at 260 units (a 288-byte O_CREAT open wrote the file at its
# 260-unit prefix; café.txt failed). Axis 2b pins the one shared MultiByteToWideChar(CP_UTF8,
# MB_ERR_INVALID_CHARS) + GetFullPathNameW `\\?\` sequence and its page probe per call site; axis 4
# runs tests/tcyr/crossos/pe_path_utf8_long.tcyr natively (POSIX oracle) and under wine (UTF-8
# locale). Whole-gate SKIP is exit 77. Runtime ~12 s with wine.
_chk_gate "$ROOT/tests/gates/platform/pe_open_posix_semantics.sh"
# 6.6.9 (bite 5) — agnos file_create_exclusive is one atomic AO_EXCL create (was a file_exists
# pre-check + plain create), a refusal classified -EEXIST by lstat#102.
_chk_gate "$ROOT/tests/gates/platform/agnos_create_exclusive_atomic.sh"

# 6.6.9 (bite 8) — the Windows CLI: `_file_size` is open + lseek, not a raw stat (-38 on PE, so
# distlib's verify was inert and `distlib --check` always STALE), and cyrius.exe finds the tools
# in its own bin/ (GetModuleFileNameW, not a '/'-only argv(0) scan). Wine axes SKIP without wine.
_chk_gate "$ROOT/tests/gates/toolchain/cli_pe_file_size_and_sibling_tools.sh"

# 6.6.11 (B09: J4/J6) — a CLI child inherits the WHOLE environment. `load_environ` read
# /proc/self/environ into a fixed 8 KB buffer (every variable past it dropped in every child) and,
# on macOS, left `_envp` EMPTY. Linux/aarch64 axis here; the macOS half is the ecb/ach row in
# cross-os-selfhost.sh. Exit 77 with no /proc/self/environ or no compiler.
_chk_gate "$ROOT/tests/gates/toolchain/cli_child_env_complete.sh"
# 6.6.12 (B10: S-B1) — cbt `_macho_fill_environ` returns <= cap - 1 and keeps only WHOLE entries.
# Its per-entry NUL was stored unconditionally, so a macOS environment larger than the buffer
# returned pos > cap and every caller's `store8(eb + en, 0)` landed past its allocation. The
# macOS-only fn is extracted into an x86 logic probe (40 x 25-byte entries, cap 64, canary);
# the ecb/ach half was verified by hand and is in the CHANGELOG. Exit 77 with no compiler.
_chk_gate "$ROOT/tests/gates/toolchain/macho_fill_environ_bounded.sh"
# 6.6.11 (B09: I3) — cyrius.exe honours CYRIUS_RESOLVED=1 and runs a pinned versions/<pin>/bin/
# cyrius.exe as a child (sys_execve is a -1 stub on PE), propagating its exit code. Wine; 77 without.
_chk_gate "$ROOT/tests/gates/toolchain/cli_pe_pinned_redirect.sh"
# 6.6.20 (the package-pin path bug) — a `[package].cyrius` pin that is not a version's shape (a leading digit, then
# [0-9A-Za-z._-], no `..`) is refused by name at the one reader: a traversal pin made the redirect
# execve a repo-shipped payload/bin/cyrius on every verb, and lib sync / deps / distlib / the lock /
# --version / --print-config used it under CYRIUS_RESOLVED=1. The PE axis runs under wine (named
# SKIP without it; cass runs it on hardware).
_chk_gate "$ROOT/tests/gates/toolchain/manifest_pin_shape_refused.sh"
# 6.6.20 (SEC-04, the file-include manifest read bug) — `[package] version = "${file:PATH}"` is read by the [embed] rules
# (_proj_path_bad + the link-free _proj_read): `../x`, an absolute path, a committed `VERSION ->
# ../x` link, `.git/config`, a hard link, a FIFO (it HUNG the build) and a file past 511 bytes are
# refused by name, and a value holding a control byte (a two-line file, a literal `\n`) is refused
# — it is written after `#@pkgver`, where a line break started a new SOURCE line. The ./VERSION
# fallback (`_project_version`: distlib's stamp, `cyrius package`) reads through the same checks.
_chk_gate "$ROOT/tests/gates/toolchain/pkgver_file_interp_confined.sh"
# 6.6.20 (SEC-02, the build-output quoting bug) — a manifest [build] output is confined to the project (it reached
# /bin/sh unquoted on macOS and was cmd.exe's redirect target on Windows); codesign runs by argv.
_chk_gate "$ROOT/tests/gates/toolchain/build_output_confined.sh"
# 6.6.20 (RS-04) — cyriusly's version operand is a version (a leading digit, [0-9A-Za-z.-], no
# `..`) in BOTH peers (programs/cyriusly.cyr and scripts/cyriusly): `uninstall ../versions`
# deleted the whole store, the active version included, and `install` spliced the operand into a
# /bin/sh -c line. A fake curl on PATH; nothing reaches the network.
# 6.7.3 (the cyriusly cmdtools CWD-script bug) — the compiled `cyriusly cmdtools` ran the CURRENT directory's scripts/cyriusly
# (any checkout's script, with the user's privileges); it runs <home>/versions/<current>/scripts/
# cyriusly only, refusing by name otherwise, and every store writer ships that twin (axes 7, 9:
# install.sh's tarball and refresh-only paths run hermetically, in throwaway homes).
_chk_gate "$ROOT/tests/gates/toolchain/cyriusly_version_operand_refused.sh"
# 6.6.20 (SEC-07, CYRIUS-2026-0035) — with a trusted verifier present, a release at or above the first
# signed release (6.2.31) whose SHA256SUMS / .sig cannot be fetched is REFUSED by name in
# install.sh, ci.sh and install.ps1: the TOFU signed-since floor only guarded versions at/above the
# highest one verified locally, so a tampered 6.6.15 (or anything, with no floor file, or an
# attacker-chosen pre-signing "latest") installed and went active; `cyriusly install <v>` ran <v>'s
# own pre-SEC-07 installer, so it still did. A stub curl and verifier; no network. install.ps1's
# functional half runs on cass; here it is static.
_chk_gate "$ROOT/tests/gates/toolchain/install_signature_required.sh"
# 6.6.20 (CLN-13) — no stdlib include of cbt/cyrius.cyr brings in only dead code (lib/tagged.cyr
# did: 18 dead fns on every target). Static census over the include closure, self-tested.
_chk_gate "$ROOT/tests/gates/toolchain/cli_includes_all_used.sh"
# 6.6.11 (B10: K7) — `cyrius soak` says what a failed self-host step DID (signal, empty output,
# a real status) through `_raw_fail_describe`, never the raw `_self_host_step` return as an
# "exit". Exit 77 with no compiler or CLI.
_chk_gate "$ROOT/tests/gates/toolchain/cyrius_soak_describes_failures.sh"
# 6.6.11 (B10: S2) — a named dep's THIN PROFILE of a package the consumer declares as a stdlib
# leaf (bote → libro → sigil-mldsa) is neither vendored nor auto-included; the fold is the
# package and the build succeeds on it alone. Exit 77 with no compiler, CLI or lib/sigil.cyr.
_chk_gate "$ROOT/tests/gates/toolchain/deps_stdlib_profile_not_vendored.sh"
# 6.6.11 (B10: K5/K8) — a distlib `.deps` sidecar is the UNION over every target, identical
# whichever host / target env runs it, with a named owner rule for target-partial symbols.
# Exit 77 with no compiler or CLI, or when cycc_aarch64 does not build from src/.
_chk_gate "$ROOT/tests/gates/toolchain/distlib_sidecar_host_independent.sh"

# 6.6.9 (bite 9) — a temp dir the CLI cannot write is named as that: the dep-cache check says
# "could NOT be verified" (reason 10) instead of calling a healthy cache tampered, the hasher
# names its capture, lint's pre-pass refuses instead of passing an unparsable file; an absolute
# $TMPDIR is the temp base. Namespace axes SKIP without unprivileged userns.
_chk_gate "$ROOT/tests/gates/toolchain/deps_cache_capture_failure_named.sh"

# 6.6.9 (bite 9) — cyrius.lock covers every .cyr `cyrius deps` leaves in lib/: a newly declared
# stdlib leaf is locked, a stdlib-only project gets its first lock (deps AND build), an empty
# lock is present-but-empty, and `deps --verify` fails a file with no lock line, by name.
_chk_gate "$ROOT/tests/gates/toolchain/deps_lock_new_leaf_locked.sh"

# 6.6.17 — `cyrius lib sync` is held to the 6.6.4 stdlib-leaf guard (a snapshot moved under an
# unchanged pin is refused by name, nothing written; `--relock` accepts) and re-locks only the
# rows it wrote: removed files' rows dropped, every other row kept, commit pins kept.
_chk_gate "$ROOT/tests/gates/toolchain/lib_sync_relocks.sh"

# 6.6.9 (bite 10, CYRIUS-2026-0009) — no cbt string literal names a shared /tmp/ path, and `cyrius self`
# stages both compilers in the private 0700 temp dir (the /bin/sh script at /tmp/cyr_*_$$ is
# gone), names a failed step, refuses a 0-byte compiler (the script scored it PASS), and leaves
# nothing behind; `_copy_binary` leaves no dst when it fails (the macOS stage leak).
_chk_gate "$ROOT/tests/gates/toolchain/cbt_no_shared_tmp_paths.sh"
# 6.6.20 (SEC-05, CYRIUS-2026-0034) — a crash-safe replace's sibling temp ("<path>.cyrtmp.<pid>.<ctr>",
# predictable) is created O_EXCL|O_NOFOLLOW: a link planted there redirected file_write_atomic /
# _aw_open's write into the file it named and was renamed over the path. cyrfmt --write and
# deps --lock skip planted names, refuse by name when 64 are taken; only _io_tmp_open builds it.
_chk_gate "$ROOT/tests/gates/toolchain/atomic_temp_exclusive.sh"

# 6.6.9 (bite 11) — a check-driver row that did not run its check (missing tool, host or
# fixture) prints SKIP and is tallied as a SKIP, never as a PASS; CYRIUS_CHECK_NO_SKIP=1 (what
# CI's delegated steps run under) makes every SKIP a FAIL. 86 rows used to score it as a pass.
_chk_gate "$ROOT/tests/gates/toolchain/check_driver_skip_is_not_pass.sh"

# 6.6.9 (bite 11) — CI runs the check driver's rows (fmt, lint, object-init, linker,
# shared-dlopen, capacity) under CYRIUS_CHECK_NO_SKIP=1 instead of carrying hand-copied shell
# twins of them; no workflow run: line references tests/fixtures/; the .tcyr floor is written
# once (tests/tcyr/CORPUS_FLOOR); every CI self-host step uses cross-os-selfhost.sh's fork.
_chk_gate "$ROOT/tests/gates/toolchain/ci_steps_delegate_to_driver.sh"

# 6.6.17 (P1) — every cyrius.cyml key the ecosystem, the init templates and package-format.md
# use is declared in `cyrius help manifest` (read / held / dropped / info), and the guide's table
# says the same. The expected keys come from what consumers write, not from the vocabulary.
_chk_gate "$ROOT/tests/gates/toolchain/manifest_key_inventory.sh"

# 6.6.17 (P1) — every [build] / [package] / [sections] read goes through ONE reader that reads the
# WHOLE manifest (refused by name past 16 MiB) and parses values as TOML: a [build] past 64 KiB, a
# key after a multi-line array, literal / escaped strings, the CYML body, `cyrius package`.
_chk_gate "$ROOT/tests/gates/toolchain/manifest_one_reader.sh"

# 6.6.17 (P1) — `cyrius build --print-config` prints every value with its origin (argument >
# environment > manifest > default) and builds / resolves nothing; checked against verbatim
# consumer manifests, with the expected values parsed from the fixtures by awk.
_chk_gate "$ROOT/tests/gates/toolchain/build_print_config.sh"

# 6.6.17 (P1) — [build] dce / strict / defines resolve argument > environment > manifest > default
# at every rung, observed where they land (a stub cycc's argv + CYRIUS_DCE, the program's exit
# code); mistyped values refused; held target / dropped features / unknown keys warned by name.
_chk_gate "$ROOT/tests/gates/toolchain/build_config_precedence.sh"

# 6.6.17 (P1) — on Windows the resolved dce / strict reach cycc.exe (CYRIUS_DCE in its
# environment, --strict on its command line): a PE stub compiler under a private wine prefix.
# SKIP by name without wine.
_chk_gate "$ROOT/tests/gates/toolchain/build_config_windows_arm.sh"

# 6.6.20 (REFACTOR-10 / CBTB-10) — compile() hands the compiler its flags from ONE list
# (`_cc_flags`): the POSIX argv is built and sized from it, the PE command line joins it. The real
# helpers run for all 8 flag combinations (the old fixed argv[32] held 4 slots for 5 writers).
_chk_gate "$ROOT/tests/gates/toolchain/compile_flag_list.sh"

# 6.6.20 (CBTB-03) — a failed fork is a NAMED failure in every forking verb and in the LSP: under
# `ulimit -u 1` build keeps the old binary and leaves no temp (it used to print `OK (0 bytes)`, exit
# 0 and rename its empty write-probe over the binary), and `hooks install` no longer reports a hook
# it never installed. Derived half: every sys_fork in cbt/ + cyrius-lsp is checked and no
# sys_waitpid result is discarded. SKIP by name where the limit is not enforced (root).
_chk_gate "$ROOT/tests/gates/toolchain/cli_fork_failure_named.sh"

# 6.7.0 — `cyrius --help` lists every verb main() dispatches exactly once (sub-forms as their own
# lines), lists nothing main() does not dispatch, names the --version / --help / -h aliases, and
# puts every description on one column. The verb set is derived from main()'s streq(cmd, …) sites;
# a runtime probe of the built CLI is the second oracle. Six verbs had no line through 6.6.20.
_chk_gate "$ROOT/tests/gates/toolchain/help_lists_every_verb.sh"

# 6.6.17 (P1) — bare `cyrius test` runs [build] test (file / dir / list) first, then tests/, each
# file once; a missing target is a named failure; absent key = unchanged; an argument wins.
_chk_gate "$ROOT/tests/gates/toolchain/test_runs_build_test.sh"

# 6.6.17 (P1 m6) — manifest keys compare whole (`dev-stdlib` is not `stdlib`, `test-only` is not
# `test`) and [deps.NAME] path / git / tag / target are TOML strings: `'…'` reads, a bare value is
# refused by name, a quoted word in a comment inside an array is not an element.
_chk_gate "$ROOT/tests/gates/toolchain/toml_key_boundary_and_values.sh"

# 6.6.17 (P5-A) — `cyrius coverage` takes RUN programs as a TEXT corpus ([coverage] programs, or
# --programs which wins), `*` within one path segment, empty globs named, corpus programs not
# measured, and --per-entry names which entry references which fn. Execution coverage is v6.7.x.
_chk_gate "$ROOT/tests/gates/toolchain/coverage_run_programs.sh"

# 6.6.10 (bite 12) — the check driver runs only tools it BUILT from this tree in this run:
# all nine executables it runs come from its private run dir, planted build/ stubs and a
# ~/.cyrius/bin copy are ignored, and a tool that does not compile is a FAIL naming it.
_chk_gate "$ROOT/tests/gates/toolchain/check_driver_builds_its_tools.sh"

# 6.6.16 (G1) — every gate runs from `/`: the --run-gate supervisor chdirs there before it
# starts a gate and refuses a relative script path, so a gate that does not cd to the root it
# derives from $0 is red on every run instead of green because check.sh ran from the root.
_chk_gate "$ROOT/tests/gates/toolchain/gates_run_from_foreign_cwd.sh"

# 6.6.16 (G5) — the check driver finds sit from a git worktree: $SIT_DIR, <root>/../sit, then
# the worktree's gitdir/commondir route to the main checkout's sibling sit, then
# $HOME/Repos/sit; a miss names every path tried. Every release lane's sit-fsck row SKIPped.
_chk_gate "$ROOT/tests/gates/toolchain/check_sit_lookup_worktree.sh"

# 6.6.20 (RLM-01) — every `_regression_wait_deadline` in lib/regression.cyr and the check driver
# consumes its result before the status buffer is decoded: a deadline (0) or an unobserved child
# (-1, waitpid never wrote it) is never read as an exit code. Static, with a clean-fixture + per-rule
# mutant self-test; the runtime rows are tests/tcyr/platform/regression_wait_unobserved.tcyr.
_chk_gate "$ROOT/tests/gates/toolchain/regression_wait_status_checked.sh"

# 6.6.10 (bite 12) — the harness never stores through a refused allocation: test_scratch
# panics by name on x86, qemu-aarch64, wine and cxvm; bench_new returns 0; the regression verbs
# return -1 before any fork. Mutation ledger in the header.
_chk_gate "$ROOT/tests/gates/memory/harness_alloc_refused.sh"

# 6.6.10 (bite 12) — every first-party `alloc(` result is zero-checked before its first use:
# a census against a SHRINK-ONLY allowlist (a new unchecked site fails, a fixed site fails
# until its allowlist line is deleted), with a self-tested detector and a mutation row.
_chk_gate "$ROOT/tests/gates/memory/stdlib_alloc_checked_census.sh"

# 6.6.20 (RLM-05) — every `&local` buffer handed to fmt_hex_buf / fmt_int_buf holds the
# callee's worst case (17 / 21 bytes): fmt_sprintf's %x scratch was [16] and its NUL landed
# on the neighbouring slot. A census (latent: no run-time probe sees it), with a self-tested
# detector, a floor and a mutation row.
_chk_gate "$ROOT/tests/gates/memory/fmt_buf_callers_sized.sh"

# 6.6.10 — gates added by bites that finished after lane T's registration pass, registered at
# integration (check_gate_census axis 1 found them unregistered on the merged tree):
# cx float unary ops run (bite 10); the dead-static hint on every backend (bite 10); integer
# literals >= 2^64 refused (bite 8); unknown/forward struct field types refused (bite 5); agnos
# proc_kill_tree refused by name (bite 11); cycc_cx reads its environment (bite 10); object mode
# refused where no emitter exists (bite 10); a PE-hosted ELF object (bite 10); the Job-object PE
# reroutes routed (bite 17); process errno constants on every target (bite 11).
_chk_gate "$ROOT/tests/gates/codegen/cx_float_unary_ops_run.sh"
_chk_gate "$ROOT/tests/gates/diagnostics/dead_static_hint_every_backend.sh"
_chk_gate "$ROOT/tests/gates/frontend/integer_literal_overflow_refused.sh"
_chk_gate "$ROOT/tests/gates/frontend/struct_field_type_unknown_refused.sh"
_chk_gate "$ROOT/tests/gates/frontend/impl_self_typed.sh"
_chk_gate "$ROOT/tests/gates/frontend/traits_checked.sh"
_chk_gate "$ROOT/tests/gates/frontend/generic_struct_field.sh"   # 6.7.1 (C3)
_chk_gate "$ROOT/tests/gates/frontend/trait_bounds_checked.sh"   # 6.7.1 (C3)
_chk_gate "$ROOT/tests/gates/frontend/const_checked.sh"   # 6.7.2 (B1, C1)
_chk_gate "$ROOT/tests/gates/frontend/bool_checked.sh"    # 6.7.3 (B2)
_chk_gate "$ROOT/tests/gates/frontend/enum_const_not_lvalue.sh"   # 6.7.3 (repair lane)
_chk_gate "$ROOT/tests/gates/frontend/if_expr_checked.sh"   # 6.7.4 (B3)
_chk_gate "$ROOT/tests/gates/frontend/loop_do_checked.sh"   # 6.7.5 (B5)
_chk_gate "$ROOT/tests/gates/frontend/field_compound_checked.sh"   # 6.7.5 (B8)
_chk_gate "$ROOT/tests/gates/toolchain/test_absorbs_tests.sh"   # 6.7.6 (Break 1 lane G)
_chk_gate "$ROOT/tests/gates/toolchain/cybs_call_arity_named.sh"
_chk_gate "$ROOT/tests/gates/platform/agnos_proc_kill_tree_refused.sh"
_chk_gate "$ROOT/tests/gates/platform/cx_compiler_reads_env.sh"

# 6.6.20 (REVBE-03 + REFACTOR-04) — the compiler reads its WHOLE environment: `_read_env` made one
# 8191-byte read, so a selector the CLI appends behind a large inherited environment was lost
# (`cyrius build --win` -> ELF, rc 0) and a value straddling the cut was read short; a value over
# 255 B is refused by name on every target instead of cut.
_chk_gate "$ROOT/tests/gates/platform/compiler_reads_whole_environment.sh"
_chk_gate "$ROOT/tests/gates/platform/object_mode_non_elf_refused.sh"

# 6.6.17 — the Windows fork honours `--syntax-only` (cbt passes it to cycc.exe for `cyrius lint`);
# x86, the PE cross and cycc.exe under wine, each with an anti-vacuous no-flag row.
_chk_gate "$ROOT/tests/gates/platform/syntax_only_flag_pe.sh"
_chk_gate "$ROOT/tests/gates/platform/pe_hosted_elf_object.sh"
_chk_gate "$ROOT/tests/gates/platform/pe_job_reroutes_routed.sh"

# 6.6.11 (B07, I4) — lib/net.cyr's socket verbs reach ws2_32 on PE. Every verb issued the Linux
# socket numbers, none routed on CYRIUS_TARGET_WIN, so each returned -38 and http_* could not work
# on Windows. Axes: 0xF045-0xF04A (accept/shutdown/send/recv/ioctlsocket/WSAPoll) routed at their
# arity and warned one short, named in the routed-number note, imported; and a PE build of every
# net.cyr/http.cyr verb leaves no unrouted literal syscall attributed to either file. Compile-only
# (~2 s); behaviour is tests/tcyr/crossos/net_loopback_tcp.tcyr + net_resolve_pe.tcyr on cass.
# Whole-gate SKIP is exit 77.
_chk_gate "$ROOT/tests/gates/platform/pe_socket_reroutes_routed.sh"

# 6.6.12 (B08, Q5 + S-B3) — kernel32!GetLastError is routed on PE (0xF04B) and lib/fs_win.cyr
# reads it after FindNextFileW returns 0: that 0 is both the end and a failure part-way, and with
# no reroute every 0 was the end, so a listing that failed half-way came back as a complete,
# shorter directory. Axes: 0xF04B routed at argc 1 and warned at argc 2, named in the
# routed-number note (printed whole — its byte count was hand-kept), imported; every FindNextFileW
# loop reads GetLastError, then FindClose, then tests 18; no lib/ module hands 0xF016/0xF019 a
# stdlib-widened buffer (narrow UTF-8 since 6.6.12, for the long-path fix); fs_dirlist.tcyr under
# wine. Hardware: the same .tcyr + pe_path_utf8_long.tcyr on cass. Whole-gate SKIP is exit 77.
_chk_gate "$ROOT/tests/gates/platform/pe_last_error_reroute.sh"

# 6.6.16 (net-3, N5) — every WSAGetLastError (0xF024) and every int-returning ws2_32 result in
# lib/ is read masked to 32 bits: their PE emitters define only eax. Static (no compiler, no wine;
# the defect is ABI-latent — cass zero-extends today), with a built-in clean-fixture + per-rule
# mutant self-test. The values are pinned on cass by tests/tcyr/crossos/fd_wait_ready.tcyr.
_chk_gate "$ROOT/tests/gates/platform/pe_wsa_lasterr_masked.sh"

# 6.6.20 (sec-pe SEC-08, the Windows bare-name process-start bug) — on Windows a System32 program is started by its absolute
# GetSystemDirectoryW path, never by a bare name: CreateProcessW searches the PARENT'S CURRENT
# DIRECTORY before System32, so a cmd.exe committed to a checkout ran on every `cyrius build` and a
# committed certutil.exe forged `deps --lock`'s hashes (measured on cass). Axis 0 (static): no
# lib/ or cbt/ literal starts a command line with a bare System32 name. Axes 1-4 (wine; plant
# beside the caller — wine does not search the cwd): build, test, capacity, deps --lock and the
# stdlib's exec_cmd / _win_compile_spawn never run the plant. The cwd vector itself is graded on
# real Windows by tests/tcyr/crossos/system_programs_not_from_cwd.tcyr. Whole-gate SKIP is exit 77.
_chk_gate "$ROOT/tests/gates/platform/pe_system_programs_absolute.sh"

_chk_gate "$ROOT/tests/gates/platform/process_errno_constants_every_target.sh"

# 6.6.18 (XLAT-1) — aarch64 folds a literal syscall number's ESYSXLAT chain at compile time (no
# `cmp x8` word left on ELF or arm64 Mach-O; qemu -strace twins against the runtime chain, named
# SKIP without qemu-aarch64). Cross-builds cycc_aarch64 from src with $CYCC.
_chk_gate "$ROOT/tests/gates/platform/esysxlat_fold.sh"

# 6.6.18 (XLAT-4) — the pre-commit hook's build/cycc-native-aarch64 band is 700K–2M: a COPY of
# scripts/hooks/pre-commit in a throwaway `git init` refuses an un-folded 2,042,184 B build.
_chk_gate "$ROOT/tests/gates/toolchain/precommit_arm_size_band.sh"

# 6.7.0: a parallel run executes everything queued above, then reports (_chk_par_drain).
_chk_par_drain
