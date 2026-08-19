#!/bin/sh
# v6.5.29 — EVERY `.bcyr` and `.fcyr` in the tree must still COMPILE.
#
# ⛔ WHY. The corpus loop covers `tests/tcyr/**` and nothing else, and the bench step is
# NON-BLOCKING by design — so a bench or fuzz source can stop compiling and no gate says a
# word. That is not hypothetical: the bayan 1.4.2 fold at `.29` broke five `.tcyr` (caught by
# the corpus) AND `benches/bench_mulmod.bcyr` (caught only because a human compiled it by
# hand while chasing the .tcyr failures). Had the five tests not also broken, the bench would
# have shipped broken and silent.
#
# This is the same shape as the v6.5.12 `bench_string` finding — a 56-byte stack overflow
# that SIGSEGV'd from v6.3.15 onward, invisible behind the non-blocking bench step. A source
# that no longer compiles is the cheapest possible version of that bug to catch, and there
# was no gate for it.
#
# ⚠ COMPILE only, deliberately — not run. Benches are long and fuzz harnesses are unbounded;
# running them here would make the gate a timeout waiting to happen. `cyrius bench` /
# `cyrius fuzz` remain the places they execute. Compiling is what catches rot from a stdlib
# fold, a renamed symbol, or a tightened type — which is the failure mode actually observed.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
cd "$ROOT"
O=$(mktemp); E=$(mktemp); trap 'rm -f "$O" "$E"' EXIT

fail=0
n=0
for f in $(find benches fuzz -name '*.bcyr' -o -name '*.fcyr' 2>/dev/null | sort); do
    n=$((n + 1))
    rc=0
    # NEVER merge stderr into the binary stream — that corrupts the output file with
    # diagnostics and produces something that still "runs".
    "$CC" < "$f" > "$O" 2>"$E" || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "  FAIL: $f does not compile (rc=$rc)"
        grep -m2 '^error' "$E" | sed 's/^/      /' || true
        fail=1
    fi
done

# PREMISE ROW — a find that matches nothing would report "0 failures" and read as success.
# An unmatched glob scoring a fake PASS is a documented failure mode in this tree.
if [ "$n" -lt 10 ]; then
    echo "  FAIL premise: only $n bench/fuzz sources found — the search is wrong, not the tree"
    fail=1
else
    echo "  ok premise: $n bench/fuzz sources discovered"
fi

[ "$fail" -eq 0 ] || { echo "FAIL: bench-fuzz-sources-compile"; exit 1; }
echo "PASS: bench-fuzz-sources-compile — all $n .bcyr/.fcyr sources still compile"
