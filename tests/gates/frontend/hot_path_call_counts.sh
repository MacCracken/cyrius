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
#   P  the preprocessor's walks over included text: PP_IFDEF_PASS skips blanks (PP_SKIP_WS) only at a line start,
#      not from every byte, and it and PP_NEUT_FMARK advance the lexical machine (PP_LEXST) only for a byte that can
#      move it (`"` `#` `'` in code, the newline in a comment — directive.cyr above PP_LEXST_INSTR). A self-compile
#      called PP_SKIP_WS 7.6 M and PP_LEXST 13.6 M times for its 7.5 M walked bytes. This row's included file of
#      4,000 lines of code and comments: under 2 PP_SKIP_WS calls per line and under 1 PP_LEXST call per 4 bytes
#      (the parent: one PP_SKIP_WS per byte, two PP_LEXST per byte). src/frontend/lex/pp/pass.cyr, directive.cyr.
#
# MUTATION PROOF (6.7.18, on a scratch copy of src/ with CYCC= its cycc): TOKTYP and PEEKT through L64 / GTI again
# -> RED on A (64 per token); the compiler before the fix (6.7.17's accessors) -> RED on A (141 per token).
# P: the parent of its fix -> RED (180,782 PP_SKIP_WS calls for the 4,000 lines); PP_IFDEF_PASS's `dip` from every
# byte again -> RED (the same count); PP_NEUT_FMARK's skip removed -> RED on the PP_LEXST bound (192,886 calls for
# 180,670 bytes, bound 45,167; the tree reads 4,031 and 20,181).
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

# ── P: the preprocessor's per-byte walks ─────────────────────────────────────────────────────────────────────
mkdir -p "$D/p"
awk 'BEGIN { for (i = 0; i < 2000; i++) { printf "# the note on g%d, a comment the walks pass over\n", i
                                          printf "var g%d = %d;   # and a trailing one\n", i, i } }' > "$D/p/inc.cyr"
printf 'include "inc.cyr"\nsyscall(60, g1999 & 255);\n' > "$D/p/main.cyr"
rm -f "$D/cov.txt"
(cd "$D/p" && "$D/cc_cov" < main.cyr > prog 2> prog.err)
if [ ! -s "$D/cov.txt" ]; then echo "FAIL: $G [P]: no coverage block"; sed -n 1,5p "$D/p/prog.err"; FAIL=1
else
    chmod +x "$D/p/prog"; prc=0; "$D/p/prog" || prc=$?
    B=$(wc -c < "$D/p/inc.cyr" | tr -d ' '); N=$(wc -l < "$D/p/inc.cyr" | tr -d ' ')
    W=$(count PP_SKIP_WS); X=$(count PP_LEXST)
    if [ "$prc" -ne $((1999 & 255)) ]; then echo "FAIL: $G [P]: the program exits $prc, not $((1999 & 255))"; FAIL=1
    elif [ "$W" -ge $((N * 2)) ]; then echo "FAIL: $G [P]: $W PP_SKIP_WS calls for $N included lines ($B bytes; bound $((N * 2)))"; FAIL=1
    elif [ "$X" -ge $((B / 4)) ]; then echo "FAIL: $G [P]: $X PP_LEXST calls for $B included bytes (bound $((B / 4)))"; FAIL=1
    else echo "  ok [P] $W PP_SKIP_WS calls for $N lines, $X PP_LEXST calls for $B bytes"; fi
fi

if [ "$FAIL" -ne 0 ]; then exit 1; fi
echo "PASS: $G"
exit 0
