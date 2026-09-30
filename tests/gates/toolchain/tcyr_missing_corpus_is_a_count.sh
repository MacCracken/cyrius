#!/bin/sh
# tests/gates/toolchain/tcyr_missing_corpus_is_a_count.sh — 6.6.12 (B12, T4)
#
# A .tcyr whose data file is missing FAILS WITH A COUNT, never with a signal.
#
# THE DEFECT. tests/tcyr/text/unicode_normconf.tcyr reads its corpus at the CWD-relative path
# tests/data/NormalizationTest.txt. Run from anywhere else, `file_read_all` returns -ENOENT
# (-2), the corpus assertion printed its FAIL line, and then the unconditional terminator
# `store8(corpus + corpus_len, 0)` wrote 2 bytes BEFORE the 4 MB buffer — a fresh mapping — and
# the test died of SIGSEGV (exit 139). The tally the assert framework exists to print never
# appeared, and a signal reads as "the test crashed", not "the corpus is missing".
# The fix clamps a negative length to 0 before the store, so the row loop sees an empty corpus
# and `assert_summary` reports the failures.
#
# AXES (the test built from the tree, run from an EMPTY scratch dir):
#   1  it exits non-zero, and NOT by a signal (rc < 128)
#   2  it prints exactly one `N passed, M failed` summary with M >= 1
#   3  it names the missing corpus in a FAIL line
#
# MUTATION (6.6.12): the `if (corpus_len < 0) { corpus_len = 0; }` guard deleted -> axes 1 and 2
# RED (rc 139, no summary line). Exit 77 when it could not run (no compiler).
set -u
NAME=tcyr_missing_corpus_is_a_count
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME — no compiler at $CC"; exit 77; }
TC="$ROOT/tests/tcyr/text/unicode_normconf.tcyr"
[ -f "$TC" ] || { echo "FAIL: $NAME — $TC is missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $NAME — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null || true
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

( cd "$ROOT" && "$CC" < "$TC" > "$D/t" 2> "$D/t.err" ) \
    || { sed 's/^/    /' "$D/t.err" | tail -5; echo "FAIL: $NAME — unicode_normconf.tcyr does not compile"; exit 1; }
chmod +x "$D/t"
mkdir -p "$D/empty"
RC=0
( cd "$D/empty" && timeout 60 "$D/t" ) > "$D/out" 2>&1 || RC=$?

echo "axis 1: a missing corpus exits non-zero, not by a signal"
[ "$RC" != 0 ] || _fail "axis 1: exited 0 with no corpus"
[ "$RC" -lt 128 ] || _fail "axis 1: exited $RC — a signal (or the timeout), not a failure count"
echo "axis 2: exactly one 'N passed, M failed' summary, M >= 1"
NS=$(grep -cE '^[0-9]+ passed, [0-9]+ failed' "$D/out" || true)
[ "$NS" = 1 ] || _fail "axis 2: $NS summary lines (expected 1)"
grep -qE '^[0-9]+ passed, [1-9][0-9]* failed' "$D/out" || _fail "axis 2: the summary does not count a failure"
echo "axis 3: the FAIL line names the corpus"
grep -q 'tests/data/NormalizationTest.txt' "$D/out" || _fail "axis 3: nothing names tests/data/NormalizationTest.txt"
[ "$FAILS" = 0 ] || sed 's/^/    | /' "$D/out" | tail -6

echo ""
if [ "$FAILS" -gt 0 ]; then
    echo "FAIL: $NAME — $FAILS check(s) failed (rc $RC)"
    exit 1
fi
echo "PASS: $NAME (rc $RC, $(grep -E '^[0-9]+ passed' "$D/out"))"
