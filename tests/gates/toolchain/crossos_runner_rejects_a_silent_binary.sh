#!/bin/sh
# Gate: the cross-OS lib-test runner must not score a PASS for a binary that ran nothing
# (6.6.6, review fix to bite 19f's .tcyr).
#
# THE DEFECT. scripts/cross-os-libtest-runner.sh is the leg that executes tests/tcyr/crossos/
# on real ecb / ach / cass / pi, and it graded by EXIT CODE alone. A process that executes no
# user code at all exits 0, so "the compiler emitted a binary that does nothing" and "every
# assertion passed" were the same verdict.
#
# That is not hypothetical. MEASURED on the 6.6.5 compiler (a968ed07's build/cycc),
# tests/tcyr/crossos/macro_expansion_with_include.tcyr compiles rc 0 to a 43,512-byte binary
# that prints NOTHING and exits 0 — a PASS scored over the exact preprocessor defect the file
# is named for. The macro pass had replaced the `#ifdef`-filtered source with its own
# unfiltered input and truncated it at the 1 MB helper window, so the whole top-level program
# was gone: assertions, summary line, exit syscall and the file's own `var rc = 92;` seed
# alike. No in-file trick can catch that, because the trick is part of the text that vanished.
# The judgement has to come from outside the binary.
#
# THE CONTRACT NOW ENFORCED. Every .tcyr ends in `assert_summary()`, which prints
# "N passed, M failed (T total)" to stdout. The runner captures stdout and, for a test file
# that calls assert_summary, requires that line with N >= 1. The requirement is DERIVED from
# the test file rather than listed here, so it cannot rot when a test is renamed. Measured
# over the whole corpus at 6.6.6: 332 of 333 .tcyr call assert_summary and all 332 print a
# line with N >= 1; the one that does not (tests/tcyr/frontend/struct_sid_20_21_field.tcyr)
# opts itself out by not calling it, and is not in the crossos set. Row D pins that opt-out.
#
# HOW THE ROWS ARE BUILT, stated plainly because row B is a SIMULATION. The runner's input is
# (test source, binary behaviour). Row B supplies a source whose text contains
# `assert_summary(` and a program that prints nothing and exits 0 — i.e. exactly the pair the
# 6.6.5 compiler produced for macro_expansion_with_include.tcyr, reproduced without needing a
# historical compiler in the gate. It is the runner that is under test here, not the
# preprocessor; the preprocessor's own detector is
# tests/gates/frontend/macro_pass_preserves_ifdef_filtering.sh.
#
# EXPECTED VALUES are computed a DIFFERENT WAY from the actual: each row's expectation is the
# runner's own `__LIBTEST_SUMMARY__ <pass> <fail>` pair, which the runner counts by walking
# the directory, while the gate states the pair from the number of files it planted.
#
# MUTATION LEDGER (6.6.6 — the mutant is a scratch COPY of the runner with the summary check
# deleted, i.e. the shape the runner shipped in before this fix):
#   1. summary check removed  -> row B reports "1 0" (a PASS for the silent binary) -> RED
#   2. real runner            -> GREEN (4 rows)
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
RUNNER="$ROOT/scripts/cross-os-libtest-runner.sh"
[ -x "$CC" ] || { echo "FAIL: crossos_runner_rejects_a_silent_binary: $CC missing"; exit 1; }
[ -f "$RUNNER" ] || { echo "FAIL: crossos_runner_rejects_a_silent_binary: runner missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# A throwaway HOME: the runner cd's to ~/_cyaud, so HOME is what points it at the staged tree.
mkdir -p "$D/_cyaud/lib"
cp "$ROOT"/lib/*.cyr "$D/_cyaud/lib/"
cp "$CC" "$D/_cyaud/cc"

# A file that really asserts and really prints its summary.
REAL='include "lib/assert.cyr"\nvar r1 = assert_eq(2 + 2, 4, "arithmetic");\nvar rc = assert_summary();\nsyscall(60, rc);\n'
# A file whose TEXT calls assert_summary( but whose program prints nothing and exits 0 — the
# 6.6.5 macro-pass outcome, reproduced without a historical compiler.
SILENT='# a dropped program: the text below would have run assert_summary() and exited on it\nsyscall(60, 0);\n'
# A file that asserts, prints its summary, and FAILS — the exit-code leg must still work.
FAILING='include "lib/assert.cyr"\nvar r1 = assert_eq(2 + 2, 5, "deliberately wrong");\nvar rc = assert_summary();\nsyscall(60, rc);\n'
# A file that never mentions assert_summary: silent, exit 0, and legitimately a PASS.
OPTOUT='var q = 0;\nsyscall(60, q);\n'

# _row <id> <dir> <want-pass> <want-fail> <runner> <file-spec>...
# Each file-spec is "name:BODYVAR".
_row() {
    NROWS=$((NROWS + 1))
    _id=$1; _dir=$2; _wp=$3; _wf=$4; _rn=$5
    shift 5
    rm -rf "$D/_cyaud/tests/tcyr/$_dir"
    mkdir -p "$D/_cyaud/tests/tcyr/$_dir"
    for _spec in "$@"; do
        _nm=${_spec%%:*}; _bv=${_spec#*:}
        eval "_body=\$$_bv"
        printf '%b' "$_body" > "$D/_cyaud/tests/tcyr/$_dir/$_nm.tcyr"
    done
    set +e
    _out=$(cd "$D/_cyaud" && HOME="$D" sh "$_rn" './cc' 0 "$_dir" 2>&1)
    set -e
    _sum=$(printf '%s\n' "$_out" | grep '__LIBTEST_SUMMARY__' | tail -1)
    [ -n "$_sum" ] || { bad "row $_id: the runner produced no summary at all"; return 0; }
    _gp=$(printf '%s\n' "$_sum" | awk '{print $2}')
    _gf=$(printf '%s\n' "$_sum" | awk '{print $3}')
    [ "$_gp" = "$_wp" ] || bad "row $_id: $_gp passed, want $_wp"
    [ "$_gf" = "$_wf" ] || bad "row $_id: $_gf failed, want $_wf"
    _ROW_OUT=$_out
}

# A — a genuine test passes, so the check is not a blanket refusal.
_row A ga 1 0 "$RUNNER" "good:REAL"
# B — THE ROW THIS GATE EXISTS FOR: exit 0, no output, and the source says it asserts.
_row B gb 0 1 "$RUNNER" "silent:SILENT"
printf '%s\n' "$_ROW_OUT" | grep -q 'printed NO assert summary' \
    || bad "row B: the failure does not say the binary printed no summary"
# C — the exit-code leg is untouched: a test that runs and FAILS is still a failure.
_row C gc 0 1 "$RUNNER" "failing:FAILING"
# D — a file that never calls assert_summary is not subject to the check (the corpus has one).
_row D gd 1 0 "$RUNNER" "optout:OPTOUT"

# ── mutant: the runner with the summary check deleted. Row B must then read "1 0".
MUT="$D/runner_mut.sh"
awk '
  /^        # ⛔ 6.6.6 — EXIT 0 FROM A BINARY THAT RAN NOTHING IS NOT A PASS\./ { skip = 1 }
  skip && /^        fi$/ { skip = 0; next }
  !skip { print }
' "$RUNNER" > "$MUT"
if grep -q 'printed NO assert summary' "$MUT"; then
    bad "mutant: the summary check was not removed — the ledger below is not proven"
else
    # The mutation proof RUNS on every invocation rather than sitting in a comment: if row M
    # does not report a PASS for the silent binary, the block this gate protects was never
    # load-bearing and the ledger above is a claim, not a measurement.
    _row M gm 1 0 "$MUT" "silent:SILENT"
fi

# Anti-vacuity: the floor is DERIVED from this file's own row calls.
WANT=$(grep -cE '^_row [A-D] ' "$0")
[ "$NROWS" -ge "$WANT" ] || bad "only $NROWS rows ran; this file spells $WANT"

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: crossos_runner_rejects_a_silent_binary: $NFAIL problem(s) over $NROWS rows"
    exit 1
fi
echo "PASS: the cross-OS runner fails a binary that exits 0 without running its assertions ($NROWS rows)"
exit 0
