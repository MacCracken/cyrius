#!/bin/sh
# macro_invocation_boundary.sh — v6.6.6 bite 15b.
#
# PP_MACRO_PASS DECIDED "THIS IS A MACRO INVOCATION" FROM THE BYTES ALONE: any
# upper-case byte started a candidate name. Two ways that is wrong, both silent:
#
#   NO LEFT WORD BOUNDARY. With `#define ID(a) (a)`, the name `ID` matched in the
#   MIDDLE of the identifier `myID` — so `fn myID(a)` was rewritten to
#   `fn my((a))` and `myID(5)` to `my((5))`. A program defining BOTH `myID` (9)
#   and `my` (7) therefore CALLED THE WRONG FUNCTION and exited 7, with nothing
#   printed but `duplicate fn 'my'` — naming a function the source never wrote
#   twice. (The RIGHT-hand side was never at risk: PP_HASH_ID hashes up to the
#   `(`, so `IDX(1)` hashes `IDX` and cannot match `ID`.)
#
#   NO LEXICAL STATE. An invocation inside a STRING LITERAL was expanded and the
#   string's bytes rewritten: `"ID(5) literal"` measured 11 bytes instead of 13,
#   and `"line1<LF>ID(5) here"` 14 instead of 16. This is the defect 6.6.6 bite 4
#   fixed in "the four line-oriented passes" — PP_MACRO_PASS is the fifth pass and
#   is BYTE-oriented (it has no `bol`), which is exactly how it was left out of
#   that census.
#
# Fixed by `PP_MACRO_START` (src/frontend/lex_pp.cyr): the byte must start an
# identifier — `PP_IDBYTE` of the previous byte is 0, or it is byte 0 — and
# `PP_LEXST_INSTR` of the shared PP_LEXST state must be 0.
#
# ⭐ EVERY EXPECTED VALUE COMES FROM A TWIN, NOT FROM A NUMBER IN THIS FILE. The
# left-boundary axes compile the same program with the macro RENAMED to one that
# cannot collide (`ZID`), keeping the directive line, its length and the line
# count identical, and require a BYTE-IDENTICAL binary. The string axes measure
# the literal with a `while (load8(...))` loop in the program itself and compare
# against the twin's answer, so the gate never asserts a length it computed.
#
# ⛔ THE FIRST CUT OF THIS FILE SAID, HERE: "comments are deliberately not excluded,
# and there is no axis for them — `#` opens a comment, the lexer drops it, and a
# `#define` body cannot contain a newline, so an expansion inside a comment cannot
# change the emitted binary. An unobservable change is not something a gate can
# hold." THAT WAS FALSE, and saying it is what left the shape untested. The argument
# only covers the bytes an expansion WRITES; PP_EXPAND's argument scan READS to the
# matching `)` with no line bound, so an UNBALANCED `(` in a comment ate the code
# after it:
#
#     #define M(a) 0
#     # TODO: fix M(
#     var r = 42;
#     var t = 1;
#     syscall(60, r + t);          → exit 0, empty stderr. 43 is correct.
#
# Fixed by bounding — not excluding — in `PP_MACRO_CALLABLE` / `PP_ARGS_ON_LINE`: an
# invocation that STARTS in a `#` comment must CLOSE on the same line. Excluding
# comments outright would regress attribute lines, which PP_LEXST also reads as
# comments and whose macros legitimately expand (axis 10).
#
# Axes:
#   1  the filed shape: `myID(5)` calls myID, and the binary is byte-identical to
#      the renamed-macro twin
#   2  the same with a `_` before the name (`my_ID(5)`) — `_` is an identifier
#      byte and was equally unprotected
#   3  a macro invocation inside a single-line string literal keeps its bytes
#   4  the same inside a MULTI-LINE string (a raw LF), which is what makes the
#      shared PP_LEXST state — rather than a per-line flag — load-bearing
#   5  over-correction guard: a REAL invocation still expands (exit 42)
#   6  over-correction guard: an invocation at byte 0 of the file still expands —
#      the `ip == 0` arm of the boundary test, which a naive `ip - 1` read would
#      get wrong
#   7  anti-vacuous: with the macro DEFINED but spelled so it cannot match, every
#      axis-1..4 program compiles to the same bytes as with no macro at all
#   8  an UNBALANCED `(` in a whole-line `#` comment does not delete the code that
#      follows it (exit 43, byte-identical to the renamed-macro twin)
#   9  the same from a TRAILING comment on a real line of code — the shape that
#      needs no contrived file at all
#  10  over-correction guard: a macro on an ATTRIBUTE line still expands. PP_LEXST
#      reads `#inline fn f(): i64 { return N(5); }` as a comment, so a blanket
#      "never expand in a comment" passes axes 8 and 9 and breaks this. Its oracle
#      is a HAND-EXPANDED twin, not a number
#  11  the one accepted behaviour change, pinned so it cannot decay into silence: an
#      invocation whose args WRAP on an attribute line no longer expands, and fails
#      LOUDLY (`undefined function`, compiler exit 1) rather than mis-compiling
#  12  a stray `)` in a LATER comment — legal prose — closed the comment's `(` at
#      depth 0 and the expansion ate two whole statements. The axis that makes the
#      newline stop itself load-bearing: 8 and 9 survive its removal by luck of
#      paren balance, 12 does not
#
# ⚠ NO COMPANION `.tcyr`, AND THE REASON IS ITSELF A DEFECT: a function-like
# `#define` in a file that also `include`s lib/assert.cyr does not compile at all
# — `printf '#define M(a) (a)\ninclude "lib/assert.cyr"\nvar x = 1;\nsyscall(60, x);\n'
# | ./build/cycc` dies with `error:4261:6: expected '}', got end of file`, byte for
# byte the same on b6b3bbd6, i.e. pre-existing and unrelated to this bite. A first
# cut of this coverage WAS a `tests/tcyr/crossos/*.tcyr`; with the includes an
# assert file needs, its binaries came out IDENTICAL from the fixed and the unfixed
# compiler — a test that could not fail. It is filed rather than fixed here (a
# different defect), and the coverage lives in this gate, whose programs have no
# includes at all. ⛔ Do not "restore" the .tcyr without first checking it can go RED.
#
# MUTATION LEDGER (2026-09-19, cycc 1,315,040 B unchanged by this bite, measured). Each mutation is
# applied to a scratch tree (`git archive HEAD src lib bootstrap` + the edited
# file), a compiler built from it with the good cycc, and the gate run against
# that compiler (CYRIUS_CC); the scratch tree is deleted after:
#   N1 the left-boundary arms deleted from PP_MACRO_START (`ip == 0` / PP_IDBYTE)
#      → 2 FAIL / 5 ok: axes 1 and 2. The string axes stay green, which is why
#      the two halves are separate axes.
#   N2 the `PP_LEXST_INSTR(lst) == 1` arm deleted
#      → 2 FAIL / 5 ok: axes 3 and 4.
#   N3 `lst = PP_LEXST(lst, c);` deleted from the copy branch (the state never
#      advances, so nothing is ever "in a string")
#      → 2 FAIL / 5 ok: axes 3 and 4 — the same pair, from the other end.
#   N4 PP_MACRO_START returns 0 always (the over-correction: no macro ever
#      expands) → axes 5, 6, 10, each as a COMPILE failure
#      (`refusing to emit binary with 1 reachable undefined function(s)` — the
#      unexpanded `DBL(...)` is read as a call to a function nobody defined),
#      which is why `compile()` here fails loudly instead of returning quietly.
#   N5 the comment bound REVERTED (PP_MACRO_CALLABLE returns 1 for `lst == 3` too)
#      → axes 8, 9, 11, 12 — the defect itself.
#   N6 the comment bound made a blanket EXCLUSION (`lst == 3` → not an invocation)
#      → axis 10: the attribute line stops expanding. This is why 8/9/12 alone are
#      not enough coverage, and why the fix bounds instead of excluding.
#   N7 only the `c == 10` arm of PP_ARGS_ON_LINE deleted → axes 11, 12. 8 and 9
#      survive it because the code after them is paren-BALANCED, so the runaway
#      scan runs off the end of the file anyway; axis 12 is the one that needs the
#      newline itself.
#   the whole pre-6.6.6 compiler (both defects) → 8 FAIL: axes 1, 2, 3, 4, 8, 9, 11, 12
#   real tree → 12/12 green
#
# Ledger re-run in full at bite 15d (2026-09-19), cycc 1,315,040 B — unchanged again
# by the comment bound; N1–N4 reconfirmed against the 12-axis file.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYRIUS_CC:-"$ROOT/build/cycc"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT

pass=0; fail=0
ulimit -c 0 2>/dev/null || true

# compile $1.cyr -> $1.bin. Fails loudly on a failed compile or an empty binary.
compile() {
    rc=0
    ( "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" ) || rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '  FAIL: %s did not compile: %s\n' "$1" \
            "$(grep -m1 error "$D/$1.err" | cut -c1-90)"
        fail=$((fail+1)); return 0
    fi
    if [ ! -s "$D/$1.bin" ]; then
        printf '  FAIL: %s compiled to an EMPTY binary\n' "$1"; fail=$((fail+1)); return 0
    fi
    chmod +x "$D/$1.bin"
    return 0
}
run_exit() { got=0; ( "$D/$1.bin" ) >/dev/null 2>&1 || got=$?; }

# Each probe is written twice: once with the macro named `ID`, once with it named
# `ZID`. The twin keeps the directive, so the two differ only in whether the name
# can be found in the body — nothing else about the file changes.
twin() { sed 's/#define ID(/#define ZID(/' "$D/$1.cyr" > "$D/$1t.cyr"; }

# ── axis 1 — the filed shape.
cat > "$D/a1.cyr" <<'EOF'
#define ID(a) (a)
fn myID(a): i64 { return 9; }
fn my(a): i64 { return 7; }
var r = myID(5);
syscall(60, r);
EOF
twin a1; compile a1; compile a1t
if [ -s "$D/a1.bin" ] && [ -s "$D/a1t.bin" ]; then
    run_exit a1; got1=$got
    run_exit a1t; gotT=$got
    if [ "$got1" != "$gotT" ]; then
        printf '  FAIL: axis 1 — `myID(5)` exits %s, the renamed-macro twin %s\n' "$got1" "$gotT"
        fail=$((fail+1))
    elif ! cmp -s "$D/a1.bin" "$D/a1t.bin"; then
        printf '  FAIL: axis 1 — same exit (%s) but not the twin bytes\n' "$got1"
        fail=$((fail+1))
    else
        printf '  ok: axis 1 — a macro name inside an identifier is not an invocation (exit %s, twin-identical)\n' "$got1"
        pass=$((pass+1))
    fi
fi

# ── axis 2 — `_` before the name.
cat > "$D/a2.cyr" <<'EOF'
#define ID(a) (a)
fn my_ID(a): i64 { return 11; }
fn my_(a): i64 { return 3; }
var r = my_ID(5);
syscall(60, r);
EOF
twin a2; compile a2; compile a2t
if [ -s "$D/a2.bin" ] && [ -s "$D/a2t.bin" ]; then
    run_exit a2; got2=$got
    run_exit a2t; gotT=$got
    if [ "$got2" = "$gotT" ] && cmp -s "$D/a2.bin" "$D/a2t.bin"; then
        printf '  ok: axis 2 — `_` is an identifier byte too (exit %s, twin-identical)\n' "$got2"
        pass=$((pass+1))
    else
        printf '  FAIL: axis 2 — `my_ID(5)` exits %s, twin %s, bytes %s\n' "$got2" "$gotT" \
            "$(cmp -s "$D/a2.bin" "$D/a2t.bin" && echo same || echo differ)"
        fail=$((fail+1))
    fi
fi

# ── axis 3 — single-line string literal. The program measures its own literal.
cat > "$D/a3.cyr" <<'EOF'
#define ID(a) (a)
var s = "ID(5) literal";
var n = 0;
while (load8(s + n) != 0) { n = n + 1; }
syscall(60, n);
EOF
twin a3; compile a3; compile a3t
if [ -s "$D/a3.bin" ] && [ -s "$D/a3t.bin" ]; then
    run_exit a3; got3=$got
    run_exit a3t; gotT=$got
    if [ "$got3" = "$gotT" ] && cmp -s "$D/a3.bin" "$D/a3t.bin"; then
        printf '  ok: axis 3 — a string literal keeps its bytes (%s, the twin answer)\n' "$got3"
        pass=$((pass+1))
    else
        printf '  FAIL: axis 3 — literal measures %s, the twin %s\n' "$got3" "$gotT"
        fail=$((fail+1))
    fi
fi

# ── axis 4 — MULTI-LINE string: the state has to cross the newline.
printf '#define ID(a) (a)\nvar s = "line1\nID(5) here";\nvar n = 0;\nwhile (load8(s + n) != 0) { n = n + 1; }\nsyscall(60, n);\n' > "$D/a4.cyr"
twin a4; compile a4; compile a4t
if [ -s "$D/a4.bin" ] && [ -s "$D/a4t.bin" ]; then
    run_exit a4; got4=$got
    run_exit a4t; gotT=$got
    if [ "$got4" = "$gotT" ] && cmp -s "$D/a4.bin" "$D/a4t.bin"; then
        printf '  ok: axis 4 — a MULTI-LINE string keeps its bytes (%s, the twin answer)\n' "$got4"
        pass=$((pass+1))
    else
        printf '  FAIL: axis 4 — literal measures %s, the twin %s\n' "$got4" "$gotT"
        fail=$((fail+1))
    fi
fi

# ── axis 5 — over-correction guard: a real invocation still expands.
cat > "$D/a5.cyr" <<'EOF'
#define DBL(a) ((a) * 2)
var r = DBL(21);
syscall(60, r);
EOF
compile a5
if [ -s "$D/a5.bin" ]; then
    run_exit a5
    if [ "$got" = "42" ]; then
        printf '  ok: axis 5 — a real invocation still expands (exit 42)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis 5 — `DBL(21)` exits %s, want 42\n' "$got"
        fail=$((fail+1))
    fi
fi

# ── axis 6 — over-correction guard at byte 0 of the FILE. The boundary test reads
#    the byte BEFORE the name, so offset 0 needs its own arm.
printf 'DBL(20);\n#define DBL(a) syscall(60, (a) + 3)\n' > "$D/a6.cyr"
compile a6
if [ -s "$D/a6.bin" ]; then
    run_exit a6
    if [ "$got" = "23" ]; then
        printf '  ok: axis 6 — an invocation at byte 0 still expands (exit 23)\n'
        pass=$((pass+1))
    else
        printf '  FAIL: axis 6 — invocation at byte 0 exits %s, want 23\n' "$got"
        fail=$((fail+1))
    fi
fi

# ── axis 7 — anti-vacuous. The twins carry a macro that is DEFINED but unmatched;
#    prove that is the same thing as having no macro at all, so axes 1-4 are not
#    comparing two equally-broken compiles. Derived a third way: the `#define` line
#    is replaced by a comment of its own, so the file keeps its line count.
nv=0
for probe in a1 a2 a3 a4; do
    sed 's/^#define ID(.*/# no macro at all/' "$D/$probe.cyr" > "$D/${probe}n.cyr"
    compile "${probe}n"
    if [ -s "$D/${probe}n.bin" ] && cmp -s "$D/${probe}t.bin" "$D/${probe}n.bin"; then
        nv=$((nv+1))
    fi
done
if [ "$nv" -eq 4 ]; then
    printf '  ok: axis 7 — an unmatched macro compiles like no macro at all (4/4 probes)\n'
    pass=$((pass+1))
else
    printf '  FAIL: axis 7 — only %s of 4 twins match the no-macro build\n' "$nv"
    fail=$((fail+1))
fi

# ── axis 8 — an unbalanced `(` in a whole-line comment must not eat the code below.
#    The twin renames the MACRO and leaves the comment exactly as written, so the two
#    files differ only in whether that `M(` can be found — nothing else moves.
cat > "$D/a8.cyr" <<'EOF'
#define M(a) 0
# TODO: fix M(
var r = 42;
var t = 1;
syscall(60, r + t);
EOF
sed 's/^#define M(/#define ZM(/' "$D/a8.cyr" > "$D/a8t.cyr"
compile a8; compile a8t
if [ -s "$D/a8.bin" ] && [ -s "$D/a8t.bin" ]; then
    run_exit a8; got8=$got
    run_exit a8t; gotT=$got
    if [ "$got8" = "$gotT" ] && cmp -s "$D/a8.bin" "$D/a8t.bin"; then
        printf '  ok: axis 8 — an unbalanced `(` in a comment keeps the code below it (exit %s, the twin answer)\n' "$got8"
        pass=$((pass+1))
    else
        printf '  FAIL: axis 8 — comment-opened expansion: exit %s, twin %s, bytes %s\n' "$got8" "$gotT" \
            "$(cmp -s "$D/a8.bin" "$D/a8t.bin" && echo same || echo differ)"
        fail=$((fail+1))
    fi
fi

# ── axis 9 — the same shape from a TRAILING comment on a line of real code.
cat > "$D/a9.cyr" <<'EOF'
#define M(a) 0
var r = 42;  # see M(
var t = 1;
syscall(60, r + t);
EOF
sed 's/^#define M(/#define ZM(/' "$D/a9.cyr" > "$D/a9t.cyr"
compile a9; compile a9t
if [ -s "$D/a9.bin" ] && [ -s "$D/a9t.bin" ]; then
    run_exit a9; got9=$got
    run_exit a9t; gotT=$got
    if [ "$got9" = "$gotT" ] && cmp -s "$D/a9.bin" "$D/a9t.bin"; then
        printf '  ok: axis 9 — a TRAILING comment does not eat the next line (exit %s, the twin answer)\n' "$got9"
        pass=$((pass+1))
    else
        printf '  FAIL: axis 9 — trailing-comment expansion: exit %s, twin %s, bytes %s\n' "$got9" "$gotT" \
            "$(cmp -s "$D/a9.bin" "$D/a9t.bin" && echo same || echo differ)"
        fail=$((fail+1))
    fi
fi

# ── axis 10 — over-correction guard. `#inline` is an ATTRIBUTE, but PP_LEXST reads
#    the `#` as a comment opener, so a blanket "never expand in a comment" would pass
#    axes 8 and 9 and silently stop expanding here. Oracle: the same file with the
#    macro HAND-EXPANDED — a different derivation from any number in this gate.
cat > "$D/a10.cyr" <<'EOF'
#define N(a) (a + 1)
#inline fn f(): i64 { return N(5); }
var r = f();
syscall(60, r);
EOF
sed 's/return N(5);/return (5 + 1);/' "$D/a10.cyr" > "$D/a10t.cyr"
compile a10; compile a10t
if [ -s "$D/a10.bin" ] && [ -s "$D/a10t.bin" ]; then
    run_exit a10; gotA=$got
    run_exit a10t; gotT=$got
    if [ "$gotA" = "$gotT" ] && cmp -s "$D/a10.bin" "$D/a10t.bin"; then
        printf '  ok: axis 10 — a macro on an ATTRIBUTE line still expands (exit %s, the hand-expanded answer)\n' "$gotA"
        pass=$((pass+1))
    else
        printf '  FAIL: axis 10 — attribute-line expansion: exit %s, hand-expanded %s, bytes %s\n' "$gotA" "$gotT" \
            "$(cmp -s "$D/a10.bin" "$D/a10t.bin" && echo same || echo differ)"
        fail=$((fail+1))
    fi
fi

# ── axis 11 — the accepted loss, pinned. A WRAPPED invocation on an attribute line is
#    indistinguishable from the axis-8 shape without a list of attribute names to keep
#    in sync (the drift CLAUDE.md warns about), so it is no longer expanded. It must
#    fail LOUDLY. If this ever starts passing quietly, the bound was widened wrongly.
printf '#define ADD(a,b) (a + b)\n#inline fn f(): i64 { return ADD(1,\n2); }\nvar r = f();\nsyscall(60, r);\n' > "$D/a11.cyr"
rc11=0
( "$CC" < "$D/a11.cyr" > "$D/a11.bin" 2> "$D/a11.err" ) || rc11=$?
if [ "$rc11" -ne 0 ] && grep -q "undefined function 'ADD'" "$D/a11.err"; then
    printf '  ok: axis 11 — a WRAPPED invocation on an attribute line fails loudly (exit %s, names ADD)\n' "$rc11"
    pass=$((pass+1))
else
    printf '  FAIL: axis 11 — wrapped attribute-line invocation: compiler exit %s, stderr %s\n' "$rc11" \
        "$(head -c 90 "$D/a11.err")"
    fail=$((fail+1))
fi

# ── axis 12 — the axis that makes the NEWLINE STOP load-bearing rather than a
#    belt-and-braces. In axes 8 and 9 the code that follows is paren-BALANCED, so the
#    runaway scan happens to run off the end of the file and stops there anyway; drop
#    the newline test alone and they still pass. Here a LATER COMMENT contains a
#    stray `)` — perfectly legal prose — and it closes the comment's `(` at depth 0,
#    so the expansion eats `var r` and `var t` and the program exits 0. This is the
#    shape that fails on every mutation of the bound, including dropping just the
#    `c == 10` arm of PP_ARGS_ON_LINE.
cat > "$D/a12.cyr" <<'EOF'
#define M(a) 0
# TODO: fix M(
var r = 42;
var t = 1;
# and then ) done
syscall(60, r + t);
EOF
sed 's/^#define M(/#define ZM(/' "$D/a12.cyr" > "$D/a12t.cyr"
compile a12; compile a12t
if [ -s "$D/a12.bin" ] && [ -s "$D/a12t.bin" ]; then
    run_exit a12; gotC=$got
    run_exit a12t; gotT=$got
    if [ "$gotC" = "$gotT" ] && cmp -s "$D/a12.bin" "$D/a12t.bin"; then
        printf '  ok: axis 12 — a stray `)` in a LATER comment cannot close an earlier one (exit %s, the twin answer)\n' "$gotC"
        pass=$((pass+1))
    else
        printf '  FAIL: axis 12 — stray `)` closed the comment paren: exit %s, twin %s, bytes %s\n' "$gotC" "$gotT" \
            "$(cmp -s "$D/a12.bin" "$D/a12t.bin" && echo same || echo differ)"
        fail=$((fail+1))
    fi
fi

if [ "$fail" -gt 0 ]; then
    printf 'FAIL: macro-invocation-boundary — %s of %s axes failed\n' "$fail" "$((pass+fail))"
    exit 1
fi
printf 'PASS: macro-invocation-boundary — %s/%s axes green\n' "$pass" "$pass"
