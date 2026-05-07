#!/bin/sh
# Regression: cyrius api-surface tool — snapshot diff correctness.
#
# Pinned to v5.7.33. Pattern adapted from agnosys/scripts/check-api-
# surface.sh; cyrius-native pure-cyrius impl in
# programs/cyrius_api_surface.cyr per sovereign-toolchain stance.
#
# Three test cases:
#   1. snapshot of cyrius repo matches the committed
#      docs/api-surface.snapshot exactly (no drift).
#   2. synthetic snapshot with one extra (removed-from-current)
#      entry → tool reports BREAKING with rc=1.
#   3. synthetic snapshot with one entry deleted (added-in-current)
#      → tool reports non-breaking addition with rc=0.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/build/cyrius_api_surface"
SNAPSHOT="$ROOT/docs/api-surface.snapshot"

if [ ! -x "$TOOL" ]; then
    echo "  skip: $TOOL not built"
    exit 0
fi
if [ ! -f "$SNAPSHOT" ]; then
    echo "  skip: $SNAPSHOT missing — run 'cyrius api-surface --update' first"
    exit 0
fi

TMPDIR="${TMPDIR:-/tmp}"
TEST_SNAP="$TMPDIR/cyrius_api_surface_test_$$.snapshot"
trap 'rm -f "$TEST_SNAP"' EXIT

fail=0
cd "$ROOT"

# Test 1: committed snapshot matches current.
set +e
out=$("$TOOL" --snapshot="$SNAPSHOT" 2>&1)
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    echo "  FAIL: committed snapshot doesn't match current API surface"
    echo "$out" | head -5
    fail=$((fail + 1))
fi

# Test 2: synthetic removal (snapshot has entry not in current).
cp "$SNAPSHOT" "$TEST_SNAP"
echo "_TEST_REMOVED::synthetic_fn/0" >> "$TEST_SNAP"
LC_ALL=C sort -o "$TEST_SNAP" "$TEST_SNAP"
set +e
out=$("$TOOL" --snapshot="$TEST_SNAP" 2>&1)
rc=$?
set -e
if [ "$rc" -ne 1 ]; then
    echo "  FAIL: synthetic removal not flagged (rc=$rc, expected 1)"
    echo "$out" | head -5
    fail=$((fail + 1))
fi
if ! echo "$out" | grep -q "_TEST_REMOVED::synthetic_fn"; then
    echo "  FAIL: synthetic removal not in BREAKING report"
    fail=$((fail + 1))
fi

# Test 3: synthetic addition (snapshot missing one current entry).
cp "$SNAPSHOT" "$TEST_SNAP"
sed -i '1d' "$TEST_SNAP"
set +e
out=$("$TOOL" --snapshot="$TEST_SNAP" 2>&1)
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    echo "  FAIL: synthetic addition incorrectly flagged as breaking (rc=$rc)"
    echo "$out" | head -5
    fail=$((fail + 1))
fi
if ! echo "$out" | grep -q "1 added since snapshot"; then
    echo "  FAIL: addition count not reported as 1"
    echo "$out" | head -5
    fail=$((fail + 1))
fi

if [ "$fail" -eq 0 ]; then
    n=$(wc -l < "$SNAPSHOT")
    echo "  PASS: cyrius api-surface diff (snapshot $n entries; +1 added detected; -1 removed detected) (v5.7.33)"
    exit 0
fi
exit 1
