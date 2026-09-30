#!/bin/sh
# Gate: every full-corpus .tcyr loop in .github/workflows/ci.yml grades by the ONE tcyr rule
# (6.6.11 B01, O3).
#
# THE DEFECT. The three loops (ubuntu `test`, `test-agnos` in the agnosticos container, and
# `aarch64-native`) graded `ec != 0 || N failed > 0`, reading N from the first-or-last
# `[0-9]* failed` anywhere in the merged output. A test that died before assert_summary() and
# exited 0 has no count to read, so it scored PASS — MEASURED at 6.6.11 by running the 6.6.10
# ubuntu step body under `bash -eo pipefail` on a staged die-early fixture (and a `0 passed,
# 0 failed` one): both PASS.
#
# THE RULE (the check driver's `_tcyr_grade`, the cross-OS runner, its cass leg, `cyrius
# test`): when the SOURCE calls assert_summary(, the LAST `N passed, M failed` line must exist
# with N >= 1 and M == 0, and the exit code must be 0. Each loop defines `tcyr_verdict` and
# fails a test on any non-empty verdict.
#
# AXES
#   1  each of the >= 3 steps that walk `find tests/tcyr` defines `tcyr_verdict` and uses it
#      (`why=$(tcyr_verdict ...)`), and no longer carries the old `[0-9]* failed` grep.
#   2  BEHAVIOUR: each step's own `tcyr_verdict` body is extracted from ci.yml and run under
#      `bash -eo pipefail` (the GHA shell) against fixture (source, exit, output) triples —
#      so a step whose copy drifts is caught, not just a step missing the name.
#   3  MUTATION (every run): a copy of the extracted function with the summary requirement
#      deleted must pass the die-early triple.
#
# Exit 77 when it could not run (no bash). CHANGELOG [6.6.11]
set -u

NAME=ci_tcyr_loops_require_summary
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CIY="$ROOT/.github/workflows/ci.yml"
command -v bash >/dev/null 2>&1 || { echo "SKIP: $NAME — no bash (the GHA step shell) to run the extracted grader"; exit 77; }
[ -f "$CIY" ] || { echo "FAIL: $NAME — $CIY missing"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME — mktemp"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
_fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# Split ci.yml into one file per `run: |` block that walks the corpus. A block starts at a
# `run: |` line and ends at the first line indented no deeper than the `run:` key.
awk -v out="$T/step" '
    function close_blk() { if (inrun) { close(fn); if (!walks) system("rm -f \"" fn "\""); } inrun = 0 }
    {
        if (inrun) {
            match($0, /^ */)
            if ($0 !~ /^[ \t]*$/ && RLENGTH <= ind) { close_blk() }
            else { print > fn; if ($0 ~ /find tests\/tcyr -name/ && $0 ~ /for t in/) walks = 1; next }
        }
        if ($0 ~ /^ +(- )?run: \|/) {
            match($0, /^ */); ind = RLENGTH; if ($0 ~ /^ +- run:/) ind = ind + 2
            n++; fn = out "." n; inrun = 1; walks = 0
        }
    }
    END { close_blk() }
' "$CIY"
NSTEP=$(ls "$T" | grep -c '^step\.' || true)

echo "axis 1: every corpus loop uses tcyr_verdict"
[ "$NSTEP" -ge 3 ] || _fail "axis 1: found $NSTEP step(s) walking tests/tcyr (floor 3: ubuntu, AGNOS, native arm64) — the reader is blind"
for s in "$T"/step.*; do
    [ -f "$s" ] || continue
    grep -q '^ *tcyr_verdict() {' "$s" || _fail "axis 1: $(basename "$s") does not define tcyr_verdict"
    grep -q 'why=\$(tcyr_verdict ' "$s" || _fail "axis 1: $(basename "$s") does not grade with tcyr_verdict"
    grep -q "grep -o.* failed' *|" "$s" && _fail "axis 1: $(basename "$s") still greps a bare '[0-9]* failed' count"
done

echo "axis 2: each step's own grader, under bash -eo pipefail"
printf 'include "lib/assert.cyr"\nvar r = assert_summary();\n' > "$T/src_summ.tcyr"
printf 'var q = 0;\nsyscall(60, q);\n' > "$T/src_plain.tcyr"
NL='
'
# id | source | ec | output | want ("" = pass, else a substring of the verdict)
run_case() {   # $1 = grader file
    _g=$1
    _c() {
        _got=$(bash -eo pipefail -c ". \"$_g\"; tcyr_verdict \"\$1\" \"\$2\" \"\$3\"" _ "$2" "$3" "$4" 2>&1) || _got="GRADER-ERROR: $_got"
        if [ -z "$5" ]; then
            [ -z "$_got" ] || _fail "axis 2: $(basename "$_g") case $1 — want PASS, got '$_got'"
        else
            case "$_got" in *"$5"*) ;; *) _fail "axis 2: $(basename "$_g") case $1 — want '$5', got '${_got:-PASS}'" ;; esac
        fi
    }
    _c good       "$T/src_summ.tcyr"  0 "x${NL}3 passed, 0 failed (3 total)" ""
    _c die_early  "$T/src_summ.tcyr"  0 "  FAIL: dies early" "no assert summary"
    _c zero       "$T/src_summ.tcyr"  0 "${NL}0 passed, 0 failed (0 total)" "0 assertions"
    _c failed_ec0 "$T/src_summ.tcyr"  0 "${NL}23 passed, 1 failed (24 total)" "1 failed"
    _c last_wins  "$T/src_summ.tcyr"  0 "${NL}1 passed, 0 failed (1 total)${NL}1 passed, 1 failed (2 total)" "1 failed"
    _c msg_noise  "$T/src_summ.tcyr"  0 "the open failed as expected${NL}2 passed, 0 failed (2 total)" ""
    _c exit3      "$T/src_summ.tcyr"  3 "${NL}1 passed, 0 failed (1 total)" "exit 3"
    _c optout     "$T/src_plain.tcyr" 0 "" ""
    _c optout_ec  "$T/src_plain.tcyr" 1 "" "exit 1"
}
for s in "$T"/step.*; do
    [ -f "$s" ] || continue
    # The function, from its `tcyr_verdict() {` line to the `}` at the same indentation.
    awk '
        /^ *tcyr_verdict\(\) \{/ { match($0, /^ */); ind = RLENGTH; on = 1 }
        on { print; match($0, /^ */); if ($0 ~ /^ *}$/ && RLENGTH == ind) on = 0 }
    ' "$s" > "$s.fn"
    [ -s "$s.fn" ] || { _fail "axis 2: could not extract tcyr_verdict from $(basename "$s")"; continue; }
    run_case "$s.fn"
done

echo "axis 3: mutation — the summary requirement deleted"
F1=$(ls "$T"/step.*.fn 2>/dev/null | head -1)
if [ -n "$F1" ]; then
    # Delete the whole `if grep -q 'assert_summary(' ...; then ... fi` block (the rule's
    # summary half): an empty `then` would be a bash syntax error, not a mutant.
    awk '/^ *if grep -q .assert_summary\(. / { skip = 1; next } skip && /^ *fi$/ { skip = 0; next } !skip { print }' "$F1" > "$T/mut.fn"
    grep -q 'no assert summary' "$T/mut.fn" && _fail "axis 3: the mutant still carries the summary branch"
    _m=$(bash -eo pipefail -c ". \"$T/mut.fn\"; tcyr_verdict \"\$1\" 0 \"  FAIL: dies early\"" _ "$T/src_summ.tcyr" 2>&1) || _m="GRADER-ERROR"
    [ -z "$_m" ] || _fail "axis 3: the mutant still refused die_early ('$_m') — axis 2's die_early row proves nothing"
else
    _fail "axis 3: no extracted grader to mutate"
fi

if [ "$fails" -gt 0 ]; then
    echo "FAIL: $NAME: $fails problem(s)"
    exit 1
fi
echo "PASS: $NAME ($NSTEP corpus loops, each grader run over 9 cases under bash -eo pipefail; mutant proven)"
exit 0
