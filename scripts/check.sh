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
# scripts/lib/audit-walk.sh stays bash for the v5.9.x window — it
# is still consumed by the bash scripts/cyrius dispatcher, queued
# for cyrius conversion at v5.9.5 alongside that dispatcher. The
# fmt/lint walk logic was simultaneously ported into
# lib/audit_walk.cyr (cyrius stdlib module) for the check program's
# use; once scripts/cyrius converts, both audit-walk.sh and this
# bridge can retire together.

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
    _grc=0
    sh "$_g" "$@" || _grc=$?
    if [ "$_grc" = 0 ]; then
        _CHK_RESULTS="$_CHK_RESULTS
PASS $_gn"
    else
        echo "  ^^ FAILED (exit $_grc): $_gn"
        _CHK_RESULTS="$_CHK_RESULTS
FAIL $_gn"
        _CHK_FAILS=$((_CHK_FAILS + 1))
    fi
    return 0
}

_CHK_DONE=0
_chk_finish() {
    _xrc=$?
    # INT/TERM handlers `exit`, which re-enters via the EXIT trap in some shells.
    if [ "$_CHK_DONE" = "1" ]; then exit "$_xrc"; fi
    _CHK_DONE=1
    if [ -n "$_CHK_STAGED_DIR" ]; then rm -rf "$_CHK_STAGED_DIR"; fi
    if [ "$_CHK_STARTED" != "1" ]; then exit "$_xrc"; fi

    # Everything THIS run is supposed to have produced a result for (the full registered
    # set, or the subset a targeted run selected — see _CHK_MANIFEST).
    _manifest="$_CHK_MANIFEST"
    _total=$(printf '%s\n' "$_manifest" | grep -c . || true)
    _notrun=""
    _nnot=0
    for _m in $_manifest; do
        if ! printf '%s\n' "$_CHK_RESULTS" | grep -qx "PASS $_m"; then
            if ! printf '%s\n' "$_CHK_RESULTS" | grep -qxE "(FAIL|MISSING) $_m"; then
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
    _res_n=$(printf '%s\n' "$_CHK_RESULTS" | grep -cE '^(PASS|FAIL|MISSING) (tests/gates|scripts)/' || true)
    printf '  shell gates: %s of %s produced a result, %s NOT RUN\n' "$_res_n" "$_total" "$_nnot"
    printf '  failures:    %s (the check binary counts as one row here)\n' "$_CHK_FAILS"
    if [ "$((_res_n + _nnot))" != "$_total" ]; then
        printf '  ⚠ BOOKKEEPING: %s + %s != %s — this summary cannot be trusted\n' \
            "$_res_n" "$_nnot" "$_total"
    fi
    if [ "$_CHK_FAILS" != "0" ]; then
        echo "  FAILED:"
        printf '%s\n' "$_CHK_RESULTS" | grep -E '^(FAIL|MISSING) ' | sed 's/^/    /'
    fi
    if [ "$_nnot" != "0" ]; then
        echo "  NOT RUN — these did NOT execute and are NOT passes:"
        for _m in $_notrun; do echo "    $_m"; done
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
trap _chk_finish EXIT
trap _chk_finish INT
trap _chk_finish TERM

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
    if ! cat "$CHECK_SRC" | "$CC" > "$CHECK_BIN.new" 2>"$CHECK_BIN.err"; then
        printf "error: the check suite failed to compile:\n" >&2
        cat "$CHECK_BIN.err" >&2
        rm -f "$CHECK_BIN.new" "$CHECK_BIN.err"
        exit 1
    fi
    rm -f "$CHECK_BIN.err"
    chmod +x "$CHECK_BIN.new"
    mv -f "$CHECK_BIN.new" "$CHECK_BIN"
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
# ⚠ A full run drives its shell gates from TWO registries and a selector has to see both,
# or "run that gate" works for 60 of the 192 and reports the other 132 as unknown. The
# other one is `_gate(<name>, "tests/gates/…")` inside programs/checks/*.cyr — 132 rows
# the check binary runs as part of its `regression` phase. Both are read back out of the
# CALLS, so neither can drift from what actually runs. (Cross-checked when this was
# written: the union is exactly the 189 files under tests/gates/ plus the 3 scripts/*.sh
# gates — nothing registered twice, nothing registered and missing, nothing orphaned.
# DERIVE these numbers, never quote this line.)
_chk_driver_gate_manifest() {
    grep -ohE '"tests/gates/[A-Za-z0-9_./-]+\.sh"' "$ROOT"/programs/checks/*.cyr | tr -d '"'
}
_chk_gate_registry() { { _chk_shell_manifest; _chk_driver_gate_manifest; } | sort -u; }
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

    _chk_stage_home
    if [ "$_CHK_KIND" = "suite" ]; then
        _CHK_TARGETED_RC=0
        "$CHECK_BIN" "$_CHK_SEL" || _CHK_TARGETED_RC=$?
        exit "$_CHK_TARGETED_RC"
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

_chk_stage_home

# ⛔ v6.6.6: RECORD the driver's verdict, do NOT abort on it. `"$CHECK_BIN"` used to be a
# bare command under `set -e`, so any red row in it skipped every shell gate below — see the
# header. The shell gates cover things the binary cannot, and a red doc stamp is no reason to
# stop looking at them.
_CHK_STARTED=1
_CHK_DRIVER_RC=0
"$CHECK_BIN" || _CHK_DRIVER_RC=$?
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

# v6.5.56 P0: identifier dedup must be an EXACT compare. It was a PREFIX compare that happened to
# be exact only while `bucket = klen` put one length per chain; v6.5.50's content hash removed
# that invariant without adding the terminator check it had been standing in for, so a shorter
# identifier took a longer one's pool offset and the two became ONE symbol
# (`var ah = 7; var ahxaa = 99;` read `ah` as 99, exit 0). 127 repos carry a colliding pair.
# ⛔ The self-host fixpoint CANNOT see this — cycc's own source has 0 colliding pairs of 54,089,
# and the mutation proof confirms a deliberately-broken compiler still reproduces itself
# byte-identically. This gate pins the PROPERTY on known-colliding pairs instead.
_chk_gate "$ROOT/tests/gates/frontend/lexid_prefix_exact.sh"

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

# 6.6.6: a block-bodied closure in a declaration-zone `var` used to end the program. Pass 1 and
# pass 2 both found the end of the declaration by scanning to the first `;`, and the closure body
# carries one — so both stopped at its `}` and every statement below was dropped, silently. Rows
# are checked against CONTROL programs whose declarations take the (always-correct) PARSE_PROG
# path instead, with cx / aarch64-qemu / PE-wine legs and a static 7-fork parity axis, because
# the pass-2 skip is copied into every `src/main*.cyr`.
sh "$ROOT/tests/gates/frontend/toplevel_decl_block_closure.sh"

# 6.6.6 bite 19a: a `var` declared inside a TOP-LEVEL block is scoped to that block, like one
# in a fn body. It used to register a GLOBAL — and the global var table had no scope mechanism
# at all — so `if (c == 1) { var t = 5; } syscall(60, t);` compiled and exited 5 while the same
# shape inside a fn is `undefined variable 't'`. One spelling, two scoping rules. Rows are
# checked against no-block CONTROL programs; the refusal rows assert the error names the
# variable, the note says where to declare it, and no binary is emitted.
sh "$ROOT/tests/gates/frontend/toplevel_block_var_scope.sh"

# 6.6.6 bite 19f: a function-like `#define` must not change the source every other pass
# produced. PP_IFDEF_PASS does not copy its filtered output back to input_buf, and
# PP_MACRO_PASS reads input_buf and writes preprocess_out — so merely HAVING one function-like
# macro in scope put stripped `#ifdef` arms back into the build (an aarch64 `x0` in an x86
# compile) and truncated the source at the 1 MB helper window. An object-like `#define` never
# ran the pass, which is why it stood. Row C is a byte-for-byte binary differential.
sh "$ROOT/tests/gates/frontend/macro_pass_preserves_ifdef_filtering.sh"

# 6.6.6 bite 19b: a file may DECLARE a global whose name another file has made `private`.
# v6.5.0 put the cross-file check inside FINDVAR so every REFERENCE is covered by one check,
# but PARSE_GVAR_REG's sit_shadow probe and CHKDUPVAL are not references — they ask "does this
# name exist?" while REGISTERING one — and the check turned that answer into an accusation
# against a file's own declaration. The enforcement rows D-G are the point: deleting the check
# would pass every accepting row.
sh "$ROOT/tests/gates/frontend/private_does_not_block_own_declaration.sh"

# 6.6.6 bite 19c: the duplicate-symbol warning went SILENT once a program had registered 1024
# vars — CHKDUPVAL opened with a blanket `pi >= 1024` return, which is the ENUM fold table's
# bound applied to both halves of the probe; gvar_initval is a grown table with no such cap.
# The programs that collide are exactly the large ones. The SYS_* note went with it, so row D
# asserts the note's lines too: a fix that restored only the warning would pass otherwise.
sh "$ROOT/tests/gates/frontend/duplicate_symbol_warning_at_scale.sh"

# 6.6.6 bite 19e: ERR_MSG REPORTS and returns — the three gvar_toks registration sites called
# it at the cap and then stored anyway, writing past the 4096-entry buffer at 0x729000 and
# walking toward TS@0x800000. Same shape as bite 2f. The detector is STATIC (the bytes past the
# buffer are documented free, so a few hundred entries of overflow change nothing observable —
# measured identical at 4200/6000/10000/20000 globals on both compilers); the behavioural axes
# pin the diagnostic, the refusal for all three registration shapes, and the 4096 boundary.
sh "$ROOT/tests/gates/memory/gvar_toks_cap_guards_the_store.sh"

# 6.6.6 bite 19d: a global initializer that READS a constant declared below it got 0 on cx and
# the right value on every other target. cx opts out of the static-init path (its globals live
# in cxvm memory zeroed at startup), which left the deferred replay — in declaration order —
# as the only thing that gives a global its value. Rows are checked against controls declared
# in dependency order AND run on the host, so cx is compared with a second implementation.
sh "$ROOT/tests/gates/codegen/cx_forward_read_constant_global.sh"

# 6.6.6 (review fix to bite 19f's .tcyr): the cross-OS lib-test runner graded tests/tcyr/crossos/
# by EXIT CODE alone, and a process that runs no user code exits 0 — so "the compiler emitted a
# binary that does nothing" and "every assertion passed" were one verdict. Measured on the 6.6.5
# compiler, crossos/macro_expansion_with_include.tcyr compiled to a 43,512-byte binary that
# printed nothing and exited 0: a PASS over the preprocessor defect it is named for. The runner
# now requires the binary's own "N passed" line for any test whose source calls assert_summary.
sh "$ROOT/tests/gates/toolchain/crossos_runner_rejects_a_silent_binary.sh"
# 6.6.6: copying between two DIFFERENT struct (or vector) types is an error, not an 8-byte
# store. Both copy paths answered a type mismatch with `return 0`, which falls through to the
# generic scalar store: `p = q` between a P3 and a Q3 copied ONE word of three and left the
# rest of `p` stale, and `var p: P3 = q;` stored q's ADDRESS into a struct-typed slot (p.x read
# a stack address) — both silent, exit 0. The LITERAL form has been a hard error since 6.6.5.
# Acceptance rows are checked against field-by-field CONTROL programs, and the pointer-bind and
# scalar-source paths are pinned so a future tightening cannot quietly take them out.
sh "$ROOT/tests/gates/frontend/struct_copy_type_checked.sh"

# 6.6.6: a vector-returning fn `return`s only what the vector return ABI can carry. PARSE_RETURN
# handled exactly `return IDENT;` for a local of the matching class and fell through to the
# SCALAR path for everything else, so `fn bad(): f64v2 { return 5; }` compiled clean and handed
# back a half-written register pair — and so did a bare `return;`, `return x + y;` (which
# returned Y UNCHANGED), `return load64(&v);` and a call to a scalar or wrong-width fn. The
# same shape as bite 16c's 9-16 byte struct pair, one type class over. Two sites: the tail-call
# path takes `return f(..);` before the vector branch sees it. Legs: host, cx, qemu-aarch64,
# wine-PE (emulation is NOT hardware — the ecb/ach/cass/pi gate is).
sh "$ROOT/tests/gates/codegen/simd_return_shapes.sh"

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
_chk_gate "$ROOT/tests/gates/frontend/directive_fork_parity.sh"

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


# v6.5.2: every folded stdlib that builds for Linux must also build for agnos.
# `lib/yukti.cyr` shipped SIX agnos ABI errors for months — including `sys_mount` called
# with 5 args against agnos's 0-parameter no-op stub, so yukti returned Ok() for a mount
# that never happened — because NO gate had ever compiled a folded stdlib for a non-Linux
# target. Parity (Linux-OK-but-agnos-broken) rather than "must build", since the distlib
# bundles deliberately do not carry their own stdlib deps. Reports its own coverage: 11/12
# today, niyama skipped and named.
_chk_gate "$ROOT/tests/gates/platform/folds_agnos_parity.sh"

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

# v6.6.4: a RELEASED version's install slot is written from its TAG, never from a drifted
# tree. `install.sh --refresh-only` (and through it `cyrius pulsar`), `cyrius lsp` and the
# retired CLAUDE.md hand-copy recipe all keyed a store write on the working-tree VERSION —
# which between a tag and the next bump still names the released version — so the installed
# "6.6.2" stdlib was 6.6.3's byte for byte and "6.6.3"'s cross-compilers were built two
# commits before the tag. The guard refuses when tag exists ∧ tree drifted ∧ destination
# live; `scripts/verify-store.sh` audits every tagged slot against its tag (+ `--restore`).
# ⚠ Runs entirely in a mktemp mini-repo against a mktemp store — never the live ~/.cyrius.
_chk_gate "$ROOT/tests/gates/toolchain/released_slot_written_from_tag.sh"

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
