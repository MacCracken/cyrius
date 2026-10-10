#!/bin/sh
# Gate: release-gate.sh step 3's VERDICT over a check.sh run (6.6.20).
#
# Step 3 is the one mandated pre-tag run of check.sh. It had two defects, both on the
# reading side, neither visible from a green run:
#
#   * A SKIP passed. check.sh exits 0 over a gate that exited 77 ("GREEN, with N gate(s)
#     SKIPPED"), and step 3 took that 0. So the release gate went green over gates that could
#     not run their check, while CI runs its delegated driver rows under
#     CYRIUS_CHECK_NO_SKIP=1. Now every SKIP must be named on RG_SKIP_ALLOW (two agnos-parity
#     gates whose fallback axis is unreachable on the dev box's mirshi), or the step is RED.
#   * The printed tally was the wrong line. `grep "passed, N failed" | tail -1` took the LAST
#     such line, which in a full run is a shell gate's own count (192 gates run after the
#     driver), though the comment called it the driver's. The verdict now reads the driver's
#     `N passed, M failed, K skipped (T total)` line, the one after its ════ rule, and refuses
#     to guess when there is not exactly one.
#
# Nothing here runs check.sh or the release gate: the verdict is driven through
# `release-gate.sh --check-verdict <file> <rc>` over fixtures that copy check.sh's summary
# format. Axis 9 pins the producers' format strings, so a format change reds this gate
# instead of silently blinding the parser.
#
# Mutation ledger (measured 6.6.20, re-run, don't trust):
#   the verdict back to `grep … | tail -1` + rc only (6.6.19's)  → axes 1-7 red
#   allowlist check deleted (return 0 before it)                → axes 1 2 3 red
#   driver line read with `grep … | tail -1` (no rule, no 1)    → axes 1 2 4 5 6 7 red
#   skipped-count cross-check deleted                           → axis 7 red
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
RG="$ROOT/scripts/release-gate.sh"
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: release_gate_check_verdict: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: release_gate_check_verdict: $1"; exit 1; }
[ -f "$RG" ] || fail "scripts/release-gate.sh missing"
cd "$ROOT"

RULE='════════════════════════'
# A check.sh output: driver block, then a shell gate's own tally (the line `tail -1` took),
# then the summary. $1 = driver tally, $2 = skipped count, $3.. = SKIPPED-list lines.
mk() {
    _f="$WORK/$1"; _d="$2"; _n="$3"; shift 3
    {
        echo "  ok: some driver row"
        echo "$RULE"
        echo "$_d"
        echo "PASS some_shell_gate"
        echo "20 passed, 0 failed"
        echo ""
        echo "── check.sh summary ────────────────────────────────────────────────"
        echo "  shell gates: 192 of 192 produced a result, 0 NOT RUN"
        echo "  failures:    0 (the check binary counts as one row here)"
        echo "  skipped:     $_n (1 shell gate(s) exited 77 + 1 driver row(s) — could not run their check; NOT passes; CYRIUS_CHECK_NO_SKIP=1 makes them failures)"
        if [ "$#" -gt 0 ]; then
            echo "  SKIPPED — these ran but could not check anything, and are NOT passes:"
            for _l in "$@"; do echo "    $_l"; done
        fi
        if [ "$_n" = 0 ]; then echo "  ALL GREEN"
        else echo "  GREEN, with $_n gate(s) SKIPPED — no failure, but not everything was checked"; fi
        echo "────────────────────────────────────────────────────────────────────"
    } > "$_f"
}
A1=tests/gates/platform/agnos_monotonic_clock_rdtsc.sh
A2=tests/gates/platform/agnos_sysinfo_tail_parity.sh
verdict() { # <axis> <fixture> <rc> <want 0|1>
    _rc=0; sh "$RG" --check-verdict "$WORK/$2" "$3" > "$WORK/v$1" 2>&1 || _rc=$?
    [ "$_rc" = "$4" ] || fail "axis $1: --check-verdict exited $_rc, wanted $4: $(cat "$WORK/v$1")"
}

# ── axis 1 (ANTI-VACUOUS): the dev box's real shape is GREEN — the two allowlisted SKIPs,
# one a shell gate, one a driver row. A verdict that refused everything would pass 2-8.
mk g1 "313 passed, 0 failed, 1 skipped (315 total)" 2 "$A1" "(driver row) $A2"
verdict 1 g1 0 0
grep -q 'STEP 3: GREEN' "$WORK/v1" || fail "axis 1: no GREEN line: $(cat "$WORK/v1")"
grep -q 'allowed SKIP: tests/gates/platform/agnos_sysinfo_tail_parity.sh' "$WORK/v1" ||
    fail "axis 1: the driver-row SKIP was not matched against the allowlist by its path"

# ── axis 2: a shell-gate SKIP not on the allowlist is RED, by name ──────────────────────
mk g2 "313 passed, 0 failed, 0 skipped (313 total)" 1 "tests/gates/platform/agnos_abi_doc_parity.sh"
verdict 2 g2 0 1
grep -q 'not on RG_SKIP_ALLOW: tests/gates/platform/agnos_abi_doc_parity.sh' "$WORK/v2" ||
    fail "axis 2: RED but the unlisted SKIP is not named: $(cat "$WORK/v2")"

# ── axis 3: a DRIVER-row SKIP not on the allowlist is RED too ───────────────────────────
mk g3 "312 passed, 0 failed, 1 skipped (313 total)" 2 "$A1" "(driver row) tests/gates/toolchain/some_driver_gate.sh"
verdict 3 g3 0 1
grep -q 'some_driver_gate.sh' "$WORK/v3" || fail "axis 3: RED but the driver-row SKIP is not named"

# ── axis 4: the tally is the DRIVER's line, not the last "passed, N failed" ─────────────
# A driver failure with the last shell gate printing "20 passed, 0 failed": the old read
# printed the shell gate's line and called it green.
mk g4 "312 passed, 1 failed, 0 skipped (313 total)" 0
verdict 4 g4 0 1
grep -q '^  driver: 312 passed, 1 failed, 0 skipped (313 total)$' "$WORK/v4" ||
    fail "axis 4: the printed tally is not the driver's: $(grep driver: "$WORK/v4" || true)"

# ── axis 5: no driver tally at all (the driver died before its summary) is RED ──────────
mk g5 "" 0
verdict 5 g5 0 1
grep -q "cannot identify the check driver's tally line (found 0" "$WORK/v5" ||
    fail "axis 5: wrong reason: $(cat "$WORK/v5")"

# ── axis 6: two driver-shaped tallies after a rule is ambiguous — RED, not a guess ──────
mk g6 "313 passed, 0 failed, 0 skipped (313 total)" 0
{ echo "$RULE"; echo "9 passed, 0 failed, 0 skipped (9 total)"; cat "$WORK/g6"; } > "$WORK/g6b"
verdict 6 g6b 0 1
grep -q "found 2 lines" "$WORK/v6" || fail "axis 6: wrong reason: $(cat "$WORK/v6")"

# ── axis 7: a summary whose SKIP list disagrees with its own count is RED ───────────────
mk g7 "313 passed, 0 failed, 1 skipped (315 total)" 3 "$A1" "(driver row) $A2"
verdict 7 g7 0 1
grep -q 'says 3 skipped but lists 2' "$WORK/v7" || fail "axis 7: wrong reason: $(cat "$WORK/v7")"

# ── axis 8: check.sh's own non-zero exit is RED whatever the lines say ──────────────────
mk g8 "313 passed, 0 failed, 0 skipped (313 total)" 0
verdict 8 g8 1 1
grep -q 'check.sh exited 1' "$WORK/v8" || fail "axis 8: wrong reason: $(cat "$WORK/v8")"

# ── axis 9: the producers still print the shapes the parser reads ───────────────────────
grep -q "println(\"$RULE\");" "$ROOT/programs/checks/main.cyr" || fail "axis 9: the driver's rule line changed"
grep -q '_p(" skipped (");' "$ROOT/programs/checks/main.cyr" || fail "axis 9: the driver's tally shape changed"
grep -qF "printf '  skipped:     %s (" "$ROOT/scripts/check.sh" || fail "axis 9: check.sh's 'skipped:' line changed"
grep -qF 'echo "  SKIPPED — these ran' "$ROOT/scripts/check.sh" || fail "axis 9: check.sh's SKIPPED header changed"
grep -qF "sed 's/^DSKIP /    (driver row) /'" "$ROOT/scripts/check.sh" || fail "axis 9: check.sh's driver-row SKIP line changed"
grep -qF "sed 's/^SKIP /    /'" "$ROOT/scripts/check.sh" || fail "axis 9: check.sh's shell-gate SKIP line changed"

# ── axis 10: step 3 itself goes through the verdict, every allowlist entry is a real gate,
# and the header names all four cross-OS hosts ──────────────────────────────────────────
grep -q '^_rg_check_verdict "\$T/check.out" "\$rc" || fail' "$RG" || fail "axis 10: step 3 does not use _rg_check_verdict"
_allow=$(sed -n '/^RG_SKIP_ALLOW="/,/"$/p' "$RG" | tr -d '"' | sed 's/^RG_SKIP_ALLOW=//')
_an=0
for _a in $_allow; do
    [ -f "$ROOT/$_a" ] || fail "axis 10: RG_SKIP_ALLOW names $_a, which does not exist"
    _an=$((_an + 1))
done
[ "$_an" = 2 ] || fail "axis 10: RG_SKIP_ALLOW holds $_an entries, expected the 2 agnos-parity gates"
grep -q '^#   4\. cross-OS self-host .*ach' "$RG" || fail "axis 10: the header's step 4 does not name ach"

# ── axis 11 (6.7.7): a RED run names the driver's failing rows, and fail() keeps check.sh's
# output — the first 6.7.7 gate run was RED on "the cyrius check binary" with no file named and
# the output deleted with the temp dir ─────────────────────────────────────────────────────
mk g11 "541 passed, 2 failed, 0 skipped (543 total)" 0
{ echo "  codegen/some_test                 PASS"; echo "  crossos/flaky_timing_row          FAIL (exit 1)";
  echo "  platform/slow_child               TIMEOUT (run) — killed at the deadline"; cat "$WORK/g11"; } > "$WORK/g11b"
verdict 11 g11b 1 1
grep -q 'driver rows that failed:' "$WORK/v11" || fail "axis 11: the RED verdict lists no failing driver rows: $(cat "$WORK/v11")"
grep -q 'crossos/flaky_timing_row' "$WORK/v11" || fail "axis 11: a FAIL row is not named"
grep -q 'platform/slow_child' "$WORK/v11" || fail "axis 11: a TIMEOUT row is not named"
grep -q 'codegen/some_test' "$WORK/v11" && fail "axis 11: a PASS row is listed as failed"
grep -q '_rg_kd/check.out' "$RG" || fail "axis 11: fail() no longer keeps check.sh's output in a checked mktemp dir"

echo "PASS: release_gate_check_verdict (11 axes)"
