#!/bin/sh
# hot_path_call_counts.sh — 6.7.18 (the optimization review). The compiler's hottest paths make the calls they
# should, COUNTED rather than timed: the tree's compiler is built in the execution-coverage mode (CYRIUS_COVERAGE=1,
# every fn body counts its entries) and run on fixed generated programs, and each row bounds one count against the
# size of its input. A count is deterministic — no box load, no best-of-N — so a row reads the same on every run.
#
# HOW THE ROWS WERE FOUND (the field note `a_per_name_check_must_ask_its_cheap_question_first_v6717`): a sampling
# profile of a self-compile (gdb, the frame chain at every 2 ms, mapped through CYRIUS_SYMS) and the coverage counts
# of the same compile at two input sizes. 6.7.17's self-compile spent a quarter of its samples inside one-line
# accessors.
#
# ROWS
#   A  the token-stream and state accessors read their cells directly (load64 / store64), not through L64 / S64:
#      PEEKT made eight calls (GTI twice, GTCNT, TOKTYP, and an L64 under each) and each L64 frame saves five
#      registers. A self-compile made 108 M L64 calls (25 M after); this row's 3,000-statement fn, 141 per lexed
#      token (10.8 after). Bound: under 24 L64 calls per token (ADDTOK). src/common/util.cyr, backend/common/tokens.cyr.
#
# MUTATION PROOF (6.7.18, on a scratch copy of src/ with CYCC= its cycc): TOKTYP and PEEKT through L64 / GTI again
# -> RED on A (64 per token); the compiler before the fix (6.7.17's accessors) -> RED on A (141 per token).
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=hot_path_call_counts
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
unset CYRIUS_BOUNDS CYRIUS_POISON CYRIUS_DCE
FAIL=0

# The instrumented compiler appends one block per run to the file named when IT was compiled.
(cd "$ROOT" && CYRIUS_COVERAGE=1 CYRIUS_COVERAGE_FILE="$D/cov.txt" "$CC" < src/main.cyr > "$D/cc_cov" 2> "$D/cc_cov.err")
if [ ! -s "$D/cc_cov" ]; then
    echo "FAIL: $G: the coverage-mode build of src/main.cyr produced nothing"; sed -n 1,5p "$D/cc_cov.err"; exit 1
fi
chmod +x "$D/cc_cov"

# run <program>: compile it with the instrumented compiler; the counts land in $D/cov.txt (one run's block only).
run() {
    rm -f "$D/cov.txt"
    "$D/cc_cov" < "$1" > "$D/prog" 2> "$D/prog.err"
    if [ ! -s "$D/cov.txt" ]; then echo "FAIL: $G: no coverage block for $1"; sed -n 1,5p "$D/prog.err"; FAIL=1; return 1; fi
    return 0
}
# count <fn name>: its entries in the last run.
count() { awk -v n="$1" '$3 == n { s += $1 } END { print s + 0 }' "$D/cov.txt"; }

# ── A: the accessors make no calls ───────────────────────────────────────────────────────────────────────────
awk 'BEGIN { print "fn main(): i64 {"; print "    var s = 0;"
             for (i = 0; i < 3000; i++) printf "    s = s + %d;\n", i
             print "    return s & 255;"; print "}"; print "syscall(60, main());" }' > "$D/a.cyr"
if run "$D/a.cyr"; then
    L=$(count L64); T=$(count ADDTOK)
    if [ "$T" -lt 15000 ]; then echo "FAIL: $G [A]: only $T tokens counted (ADDTOK) — the fixture or the count broke"; FAIL=1
    elif [ "$L" -ge $((T * 24)) ]; then echo "FAIL: $G [A]: $L L64 calls for $T tokens ($((L / T)) per token; bound 24, 6.7.17 read 141)"; FAIL=1
    else echo "  ok [A] $L L64 calls for $T tokens ($((L / T)) per token, bound 24)"; fi
fi

if [ "$FAIL" -ne 0 ]; then exit 1; fi
echo "PASS: $G"
exit 0
