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
#   S  a struct name is looked up through FINDSTRUCT's name index (FNV-1a chains, parse/types/struct.cyr), not
#      compared with every registered struct: N struct declarations and a fn of each (`p: *SK`, `p.a`) cost STREQ
#      calls O(N^2) — the parent: 1,836,928 at 450 structs, 7,319,002 at 900 (3.98x). Bound: 900 structs under
#      3x the STREQ calls of 450 (the tree: 17,753 -> 38,117, 2.14x); the 900-struct program exits 42. A count
#      ratio, not a timing one: under the 1,024-struct cap the quadratic part hides under the linear work in wall
#      time (44 -> 119 ms, 2.7x).
#   L  FINDLOCAL's backward walk over a fn's local slots compares a masked first word, not a STREQ call per slot:
#      a slot holding the offset asked for is the name (identifiers are interned), a differing masked word is not,
#      and a matching one is the name when it is under 8 bytes (its NUL was compared). 2,000 locals in one fn
#      (each `var` asks whether its name is taken): the parent 1,999,011 STREQ calls, the tree 9. Bound: under 10
#      STREQ calls per local. ⚠ The walk itself is still O(locals) per lookup — this row bounds its constant, not
#      its order; an index needs every write of a slot's name (25 sites, two inside `_PARSE_FN_DEF_IMPL`) to go
#      through one setter. src/frontend/parse/fn/table.cyr.
#   G  a closure or generic instance parsed inside a fn snapshots the fn's n local slots (four tables) and puts
#      them back after (`_cl_save_locals` / `_cl_restore_locals`, parse/expr/closure.cyr) with word loops, not an
#      L64 and an S64 call per word: 100 struct instances of `id<T>` in a fn of 1,000 locals made 1,918,276 L64 +
#      S64 calls (the tree 156,376). Bound: under 600,000; the program exits 86.
#   T  a trait impl is found by its type name through an index (FNV-1a chains, parse/fn/traits.cyr), not a walk of
#      every impl: `_tr_providers` (each impl method's prefix) and FINDFN's miss path (`_tr_fb_qual` / `_tr_fb_ambig`,
#      every name that is not a fn) each walked all N impls, testing a prefix (`_tr_pfx`) per impl — the parent:
#      160,800 `_tr_pfx` calls at 200 impls, 641,600 at 400 (3.99x). Bound: 400 impls under 3x the `_tr_pfx` calls
#      of 200 (the tree: 2,000 -> 4,096, 2.05x); the 400-impl program exits 72.
#
# MUTATION PROOF (6.7.18, on a scratch copy of src/ with CYCC= its cycc): TOKTYP and PEEKT through L64 / GTI again
# -> RED on A (64 per token); the compiler before the fix (6.7.17's accessors) -> RED on A (141 per token).
# P: the parent of its fix -> RED (180,782 PP_SKIP_WS calls for the 4,000 lines); PP_IFDEF_PASS's `dip` from every
# byte again -> RED (the same count); PP_NEUT_FMARK's skip removed -> RED on the PP_LEXST bound (192,886 calls for
# 180,670 bytes, bound 45,167; the tree reads 4,031 and 20,181).
# S: the parent of its fix -> RED (398%); FINDSTRUCT scanning the table before its chain (same answer) -> RED (397%).
# L: the parent of its fix -> RED (1,999,011 STREQ calls); FINDLOCAL's word test skipped (every non-identical slot
# to STREQ, same answer) -> RED.
# G: the parent of its fix -> RED (1,918,276 calls); `_cl_wcopy` through L64 / S64 again -> RED.
# T: the parent of its fix -> RED (399%); `_tix_cands` handing back every impl below `_ti_n` (the walk's list, the
# same answers) -> RED.
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
    crc=0; "$D/cc_cov" < "$1" > "$D/prog" 2> "$D/prog.err" || crc=$?
    if [ ! -s "$D/cov.txt" ]; then echo "FAIL: $G: no coverage block for $1"; sed -n 1,5p "$D/prog.err"; FAIL=1; return 1; fi
    if [ "$crc" -ne 0 ]; then echo "FAIL: $G: $1 did not compile (rc $crc)"; sed -n 1,5p "$D/prog.err"; FAIL=1; return 1; fi
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

# ── S: struct names by index ─────────────────────────────────────────────────────────────────────────────────
sgen() {  # sgen n > file: n structs, a fn taking a pointer to each, the last one called
    awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) printf "struct S%d { a: i64; b: i64; }\n", i
                           for (i = 0; i < n; i++) printf "fn f%d(p: *S%d): i64 { return p.a + p.b; }\n", i, i
                           printf "fn main(): i64 { var g: S%d; g.a = 40; g.b = 2; return f%d(&g); }\n", n - 1, n - 1
                           print "syscall(60, main());" }'
}
sgen 450 > "$D/s1.cyr"; sgen 900 > "$D/s2.cyr"
if run "$D/s1.cyr"; then
    S1=$(count STREQ)
    if run "$D/s2.cyr"; then
        S2=$(count STREQ)
        chmod +x "$D/prog"; src=0; "$D/prog" || src=$?
        if [ "$src" -ne 42 ]; then echo "FAIL: $G [S]: the 900-struct program exits $src, not 42"; FAIL=1
        elif [ "$S1" -lt 1 ] || [ "$S2" -ge $((S1 * 3)) ]; then
            echo "FAIL: $G [S]: STREQ calls $S1 (450 structs) -> $S2 (900): $((S2 * 100 / (S1 + 1)))% (bound 300%)"; FAIL=1
        else echo "  ok [S] STREQ calls $S1 (450 structs) -> $S2 (900), $((S2 * 100 / S1))% (bound 300%)"; fi
    fi
fi

# ── L: FINDLOCAL's walk ──────────────────────────────────────────────────────────────────────────────────────
awk 'BEGIN { print "fn main(): i64 {"; for (i = 0; i < 2000; i++) printf "    var v%d = %d;\n", i, i
             print "    return v1999 & 255;"; print "}"; print "syscall(60, main());" }' > "$D/l.cyr"
if run "$D/l.cyr"; then
    chmod +x "$D/prog"; lrc=0; "$D/prog" || lrc=$?
    Q=$(count STREQ); F=$(count FINDLOCAL)
    if [ "$lrc" -ne $((1999 & 255)) ]; then echo "FAIL: $G [L]: the 2,000-local program exits $lrc, not $((1999 & 255))"; FAIL=1
    elif [ "$F" -lt 2000 ]; then echo "FAIL: $G [L]: only $F FINDLOCAL calls — the fixture no longer exercises the walk"; FAIL=1
    elif [ "$Q" -ge 20000 ]; then echo "FAIL: $G [L]: $Q STREQ calls for 2,000 locals (bound 20,000; 6.7.17 read 1,999,011)"; FAIL=1
    else echo "  ok [L] $Q STREQ calls for 2,000 locals ($F FINDLOCAL calls; bound 20,000)"; fi
fi

# ── G: the local-slot snapshot around an instance ────────────────────────────────────────────────────────────
awk 'BEGIN { print "fn id<T>(x: T): T { return x; }"; for (k = 0; k < 100; k++) printf "struct T%d { a: i64; }\n", k
             print "fn main(): i64 {"; for (i = 0; i < 1000; i++) printf "    var v%d = %d;\n", i, i
             print "    var s = 0;"
             for (k = 0; k < 100; k++) printf "    var p%d: T%d; p%d.a = %d; var q%d = id<T%d>(p%d); s = s + q%d.a;\n", k, k, k, k, k, k, k, k
             print "    return s & 255;"; print "}"; print "syscall(60, main());" }' > "$D/g.cyr"
if run "$D/g.cyr"; then
    chmod +x "$D/prog"; grc=0; "$D/prog" || grc=$?
    GL=$(count L64); GS=$(count S64); GN=$(count _cl_save_locals)
    if [ "$grc" -ne 86 ]; then echo "FAIL: $G [G]: the instance program exits $grc, not 86"; FAIL=1
    elif [ "$GN" -lt 100 ]; then echo "FAIL: $G [G]: only $GN snapshots (_cl_save_locals) — the fixture no longer takes the path"; FAIL=1
    elif [ $((GL + GS)) -ge 600000 ]; then echo "FAIL: $G [G]: $((GL + GS)) L64 + S64 calls for $GN snapshots of 1,000+ slots (bound 600,000)"; FAIL=1
    else echo "  ok [G] $((GL + GS)) L64 + S64 calls for $GN snapshots of 1,000+ slots (bound 600,000)"; fi
fi

# ── T: trait impls by type name ──────────────────────────────────────────────────────────────────────────────
tgen() {  # tgen n > file: one trait, n structs each with its impl, a fn calling every method
    awk -v n="$1" 'BEGIN { print "trait Sh { fn area(self): i64; }"
                           for (i = 0; i < n; i++) { printf "struct Q%d { a: i64; }\n", i
                                                     printf "impl Sh for Q%d { fn area(self): i64 { return self.a + %d; } }\n", i, i }
                           print "fn main(): i64 { var s = 0;"
                           for (i = 0; i < n; i++) printf "    var q%d: Q%d; q%d.a = 1; s = s + q%d.area();\n", i, i, i, i
                           print "    return s & 255; }"; print "syscall(60, main());" }'
}
tgen 200 > "$D/t1.cyr"; tgen 400 > "$D/t2.cyr"
if run "$D/t1.cyr"; then
    P1=$(count _tr_pfx)
    if run "$D/t2.cyr"; then
        P2=$(count _tr_pfx)
        chmod +x "$D/prog"; trc=0; "$D/prog" || trc=$?
        if [ "$trc" -ne 72 ]; then echo "FAIL: $G [T]: the 400-impl program exits $trc, not 72"; FAIL=1
        elif [ "$P1" -lt 1 ] || [ "$P2" -ge $((P1 * 3)) ]; then
            echo "FAIL: $G [T]: _tr_pfx calls $P1 (200 impls) -> $P2 (400): $((P2 * 100 / (P1 + 1)))% (bound 300%)"; FAIL=1
        else echo "  ok [T] _tr_pfx calls $P1 (200 impls) -> $P2 (400), $((P2 * 100 / P1))% (bound 300%)"; fi
    fi
fi

if [ "$FAIL" -ne 0 ]; then exit 1; fi
echo "PASS: $G"
exit 0
