#!/bin/sh
# Gate: release-gate.sh step 3's VERDICT over a check.sh run (6.6.20).
#
# Step 3 is the one mandated pre-tag run of check.sh. It had two defects, both on the
# reading side, neither visible from a green run:
#
#   * A SKIP passed. check.sh exits 0 over a gate that exited 77 ("GREEN, with N gate(s)
#     SKIPPED"), and step 3 took that 0. So the release gate went green over gates that could
#     not run their check, while CI runs its delegated driver rows under
#     CYRIUS_CHECK_NO_SKIP=1. Now every SKIP must be named on RG_SKIP_ALLOW, or the step is
#     RED — and since 6.7.16 the list is EMPTY, so every SKIP is RED (its two entries existed
#     only for runtime axes run under another project's built binary, which left the gates).
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
# 6.7.16: with the real list empty, the allowed-SKIP path (axes 1-3, 7) is driven by a FIXTURE
# list — RG_SKIP_ALLOW_FIXTURE, which `--check-verdict` alone reads (axis 10 pins that step 3
# never does) — naming neutral fixture paths, never a real gate. Axis 12 runs the verdict with
# the REAL list: every SKIP, including each former entry, is RED, and a clean run is GREEN.
#
# Mutation ledger (measured 6.6.20, re-run, don't trust):
#   the verdict back to `grep … | tail -1` + rc only (6.6.19's)  → axes 1-7 red
#   allowlist check deleted (return 0 before it)                → axes 1 2 3 red
#   driver line read with `grep … | tail -1` (no rule, no 1)    → axes 1 2 4 5 6 7 red
#   skipped-count cross-check deleted                           → axis 7 red
# (measured 6.7.16; fail-fast, so the FIRST red axis — and the next one with that axis disabled)
#   RG_SKIP_ALLOW back to its two 6.7.15 entries                → axis 10, then axis 12
#   the fixture list read at the top level (either spelling)    → axis 10
#   allowlist check deleted (return 0 before it)                → axis 1, then (1-3 off) axis 12
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
# The FIXTURE allow list (neutral paths; no real gate is allowed to SKIP since 6.7.16).
A1=tests/gates/fixture/allowed_skip_a.sh
A2=tests/gates/fixture/allowed_skip_b.sh
FIXTURE_ALLOW="$A1
$A2"
# verdict with the fixture list; verdict_real with the REAL list (the fixture variable unset).
verdict() { # <axis> <fixture> <rc> <want 0|1>
    _rc=0; RG_SKIP_ALLOW_FIXTURE="$FIXTURE_ALLOW" sh "$RG" --check-verdict "$WORK/$2" "$3" > "$WORK/v$1" 2>&1 || _rc=$?
    [ "$_rc" = "$4" ] || fail "axis $1: --check-verdict exited $_rc, wanted $4: $(cat "$WORK/v$1")"
}
verdict_real() { # <axis> <fixture> <rc> <want 0|1>
    _rc=0; env -u RG_SKIP_ALLOW_FIXTURE sh "$RG" --check-verdict "$WORK/$2" "$3" > "$WORK/v$1" 2>&1 || _rc=$?
    [ "$_rc" = "$4" ] || fail "axis $1: --check-verdict (the real list) exited $_rc, wanted $4: $(cat "$WORK/v$1")"
}

# ── axis 1 (ANTI-VACUOUS): two allowlisted SKIPs are GREEN — one a shell gate, one a driver
# row. A verdict that refused everything would pass 2-8.
mk g1 "313 passed, 0 failed, 1 skipped (315 total)" 2 "$A1" "(driver row) $A2"
verdict 1 g1 0 0
grep -q 'STEP 3: GREEN' "$WORK/v1" || fail "axis 1: no GREEN line: $(cat "$WORK/v1")"
grep -q "allowed SKIP: $A2" "$WORK/v1" ||
    fail "axis 1: the driver-row SKIP was not matched against the allowlist by its path"

# ── axis 2: a shell-gate SKIP not on the allowlist is RED, by name ──────────────────────
mk g2 "313 passed, 0 failed, 0 skipped (313 total)" 1 "tests/gates/fixture/unlisted_skip.sh"
verdict 2 g2 0 1
grep -q 'not on RG_SKIP_ALLOW: tests/gates/fixture/unlisted_skip.sh' "$WORK/v2" ||
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

# ── axis 10: step 3 itself goes through the verdict, the real allowlist is EMPTY (6.7.16),
# the fixture list is read by --check-verdict alone, and the header names all four cross-OS
# hosts ─────────────────────────────────────────────────────────────────────────────────
grep -q '^_rg_check_verdict "\$T/check.out" "\$rc" || fail' "$RG" || fail "axis 10: step 3 does not use _rg_check_verdict"
_top=$(grep -c '^RG_SKIP_ALLOW=' "$RG" || true)
_emp=$(grep -c '^RG_SKIP_ALLOW=""$' "$RG" || true)
[ "$_top" = 1 ] && [ "$_emp" = 1 ] ||
    fail "axis 10: release-gate.sh's top-level RG_SKIP_ALLOW is not the one line RG_SKIP_ALLOW=\"\" ($_top top-level assignment(s), $_emp empty) — the release gate allows no SKIP since 6.7.16"
# Outside comments, the only other line that sets RG_SKIP_ALLOW, and every line that names
# RG_SKIP_ALLOW_FIXTURE, sit inside the `if [ "${1:-}" = "--check-verdict" ]` block — so step 3
# can never take the fixture list.
_fx=$(awk '
    /^if \[ "\$\{1:-\}" = "--check-verdict" \]; then$/ { inb = 1; next }
    inb && /^fi$/ { inb = 0; next }
    /^[[:space:]]*#/ { next }
    /RG_SKIP_ALLOW_FIXTURE/ { n++ }
    !inb && /^RG_SKIP_ALLOW=""$/ { next }
    !inb && (/RG_SKIP_ALLOW_FIXTURE/ || /(^|[^A-Za-z0-9_])RG_SKIP_ALLOW=/) { print "    line " NR ": " $0 }
    END { if (n == 0) print "    (no line reads RG_SKIP_ALLOW_FIXTURE — axes 1-3 and 7 drive nothing)" }' "$RG")
[ -z "$_fx" ] || fail "axis 10: RG_SKIP_ALLOW is set, or RG_SKIP_ALLOW_FIXTURE read, outside --check-verdict:
$_fx"
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

# ── axis 12 (6.7.16): the REAL list refuses every SKIP — each former entry by path, a
# driver row, a blank SKIPPED line — and a run with no SKIP is GREEN (ANTI-VACUOUS: an empty
# list that refused everything would pass the RED rows alone) ───────────────────────────
mk g12a "313 passed, 0 failed, 0 skipped (313 total)" 1 "tests/gates/platform/agnos_monotonic_clock_rdtsc.sh"
verdict_real 12a g12a 0 1
grep -q 'not on RG_SKIP_ALLOW: tests/gates/platform/agnos_monotonic_clock_rdtsc.sh' "$WORK/v12a" ||
    fail "axis 12: a former entry's SKIP is not refused by name: $(cat "$WORK/v12a")"
mk g12b "312 passed, 0 failed, 1 skipped (313 total)" 1 "(driver row) tests/gates/platform/agnos_sysinfo_tail_parity.sh"
verdict_real 12b g12b 0 1
grep -q 'not on RG_SKIP_ALLOW: tests/gates/platform/agnos_sysinfo_tail_parity.sh' "$WORK/v12b" ||
    fail "axis 12: a former entry's driver-row SKIP is not refused by name: $(cat "$WORK/v12b")"
mk g12c "313 passed, 0 failed, 0 skipped (313 total)" 1 ""
verdict_real 12c g12c 0 1
mk g12d "313 passed, 0 failed, 0 skipped (313 total)" 0
verdict_real 12d g12d 0 0
grep -q 'STEP 3: GREEN' "$WORK/v12d" || fail "axis 12: a run with no SKIP is not GREEN under the real list: $(cat "$WORK/v12d")"
grep -q 'allowed SKIP' "$WORK/v12a" "$WORK/v12b" "$WORK/v12c" && fail "axis 12: the real list allowed a SKIP"

echo "PASS: release_gate_check_verdict (12 axes; the real RG_SKIP_ALLOW is empty and refuses every SKIP)"
