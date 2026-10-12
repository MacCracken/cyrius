#!/bin/sh
# tests/gates/toolchain/api_surface_multiline_strings.sh — 6.7.9
#
# `cyrius api-surface` reads a string literal that SPANS LINES as string text, as the compiler
# does: no `{` / `}` on its inner lines moves the brace depth, and no inner line is a
# declaration.
#
# THE DEFECT (docs/development/issues/2026-10-08-api-surface-multiline-string-desync.md).
# programs/cyrius_api_surface.cyr's _scan_file walked a file one LINE at a time and restarted
# every line in code: its brace scan skipped strings, char literals and comments, but each skip
# stopped at the line's end. A multi-line string (legal cyrius) exposed its inner lines as
# code, so
#   * a `{` there raised `depth` for good, and every LATER fn in the file fell outside the
#     `depth == 0` declaration test — dropped from the snapshot;
#   * an inner line starting `fn ghost(x, y)` was listed as public surface `m::ghost/2`;
#   * an inner `#derive(Serialize)` + `struct` pair listed three codec fns no build emits.
# No error was printed, and removed_symbol_census.sh, keyed on the snapshot, read a phantom
# removal or missed a real one. The fix carries ONE lexical state (_asf_lexst_at, the
# preprocessor's PP_LEXST_AT) across the whole file; a line that starts inside a string gets no
# declaration test, and a column-0 `include "..."` line is consumed whole, as the preprocessor
# consumes it (a stray quote after its path opens no string).
#
# ⭐ THE ORACLE IS THE COMPILER. Every shape sits in its own module, compiled into one program
# with CYRIUS_DCE_VERBOSE=1 (nothing is called, so every emitted fn is listed as dead). Then:
#   axis 1  the issue's two filed repros, verbatim — each snapshot is exactly m::after/1 and
#           m::before/1;
#   axis 2  every fixture fn the tool lists is one the compiler emitted, and every one the
#           compiler emitted is listed (no file here is `private`, no name starts `_`);
#   axis 3  the literal table, one module per shape: an inner `{` (top level and in a body), an
#           inner `}` + `fn ... {`, an inner `fn` line, an escaped quote and a line-ending
#           backslash, an inner `#derive` + `struct`, a string reopened on its closing line, an
#           ATTRIBUTE line opening one (code to the lexer); and the guards that open nothing: a
#           quote after a column-0 include's path, in a char literal, in a `#` comment;
#   premises: the fixtures hold 5 lines beginning `fn ms_ghost` (what a per-line scan reads as
#           declarations) and the compiler emitted none of them, nor any `ms_fake` codec.
#
# The tool under test is BUILT HERE from programs/cyrius_api_surface.cyr (API_SRC=<file> builds a
# different source — how the mutants below were run).
#
# MUTATION PROOF (6.7.9, run with API_SRC=<mutant>; checks failed of 21, every one RED):
#   M0  the 6.7.8 tool (each line restarts in code)                          13
#   M1  no line-start guard: the declaration test runs on string lines         8
#   M2  the carried state reset to code at every line start                  13
#   M3  braces counted inside strings too                                      6
#   M4  the column-0 `include` line lexed (its stray quote opens a string)     3
#   M5  a strings-only lexer (no char-literal, no comment state)               4
#   M6  no comment state (a `#` that is not an attribute is code)              3
#   M7  _asf_lexst instead of _asf_lexst_at (an attribute line a comment)      3
#   M8  the comment fast path skips the newline too (state 3 never ends)       3
# ⚠ M6 first read GREEN: the comment fixture said "comment's", and its apostrophe opened a char
# literal that hid the quote. Every guard shape sits in its own module for the same reason —
# in one module M5's two errors cancelled out.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
fails=0
checks=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

if [ ! -x "$ROOT/build/cycc" ]; then echo "FAIL: api-surface-multiline — build/cycc not built"; exit 1; fi
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: api-surface-multiline — mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$ROOT/build/cycc"}
API="$T/api_surface"
if ! "$CC" < "${API_SRC:-$ROOT/programs/cyrius_api_surface.cyr}" > "$API" 2> "$T/build.err"; then
    echo "FAIL: api-surface-multiline — programs/cyrius_api_surface.cyr does not build"; sed -n '1,5p' "$T/build.err"; exit 1
fi
if [ "$(wc -c < "$API")" -lt 20000 ]; then echo "FAIL: api-surface-multiline — built a $(wc -c < "$API")-byte tool"; exit 1; fi
chmod +x "$API"

echo "axis 1 — the filed repros, verbatim"
mkdir -p "$T/p1/src" "$T/p1/docs" "$T/p2/src" "$T/p2/docs"
printf 'fn before(a) { return a; }\nvar BANNER = "usage:\n{ opens nothing, this is string text\nfn ghost(x, y) — also string text\n";\nfn after(b) { return b; }\n' > "$T/p1/src/m.cyr"
printf 'fn before(a) { return a; }\nvar HELP = "usage:\nfn ghost(x, y)\n";\nfn after(b) { return b; }\n' > "$T/p2/src/m.cyr"
for p in p1 p2; do
    rc=0
    ( cd "$T/$p" && timeout 20 "$API" --update --scope project ) > "$T/$p.out" 2>&1 || rc=$?
    check "$p: rc 0, the snapshot is the two real fns" "0|m::after/1 m::before/1" \
      "$rc|$(paste -sd' ' - < "$T/$p/docs/api-surface.snapshot" 2> /dev/null)"
done

P="$T/proj"
mkdir -p "$P/src"
ln -s "$ROOT/lib" "$P/lib"
# 1. a `{` on a string's inner line (the p1 shape)
cat > "$P/src/ms_brace.cyr" <<'EOF'
fn ms_brace_before(a) { return a; }
var MS_BRACE = "usage:
{ opens nothing, this is string text
";
fn ms_brace_after(a) { return a; }
EOF
# 2. an inner line starting `fn name(` (the p2 shape)
cat > "$P/src/ms_fnline.cyr" <<'EOF'
var MS_FN = "usage:
fn ms_ghost_a(x, y)
";
fn ms_fnline_after(a, b) { return a + b; }
EOF
# 3. inside a fn body: an inner `}` and an inner `fn ... {` line
cat > "$P/src/ms_body.cyr" <<'EOF'
fn ms_body(a) {
    var s = "x
}
fn ms_ghost_b(q) {
";
    return a;
}
fn ms_body_after(a) { return a; }
EOF
# 4. inside a fn body: inner `{` lines
cat > "$P/src/ms_bodyopen.cyr" <<'EOF'
fn ms_bodyopen(a) {
    var s = "
{
{
";
    return a;
}
fn ms_bodyopen_after() { return 0; }
EOF
# 5. an escaped quote, and a backslash ending the line, keep the string open
cat > "$P/src/ms_escapes.cyr" <<'EOF'
var MS_ESC = "q\"
fn ms_ghost_c(a)
";
var MS_BSNL = "abc\
fn ms_ghost_d(z)
";
fn ms_escapes_after(a) { return a; }
EOF
# 6. a `#derive` directive on a string's inner line arms nothing
cat > "$P/src/ms_derive.cyr" <<'EOF'
var MS_DERIVE = "
#derive(Serialize)
struct ms_fake { a; }
";
fn ms_derive_after(a) { return a; }
EOF
# 7. a string closed, then another opened on the same line
cat > "$P/src/ms_reopen.cyr" <<'EOF'
var MS_ONE = "one line"; var MS_TWO = "two
fn ms_ghost_e()
lines";
fn ms_reopen_after(a, b, c) { return a; }
EOF
# 8. an ATTRIBUTE line is code (_asf_lexst_at, as the preprocessor's PP_LEXST_AT): a string it
#    opens runs on across lines
cat > "$P/src/ms_attr.cyr" <<'EOF'
#inline fn ms_attr(a) { var s = "
{
"; return a; }
fn ms_attr_after(a) { return a; }
EOF
# 9-11. what does NOT open a string across lines, one module each so no two can cancel out:
#    a quote after a column-0 include's path (the preprocessor consumes the line), a quote in
#    a char literal, a quote in a `#` comment
cat > "$P/src/ms_include.cyr" <<'EOF'
include "lib/syscalls.cyr" trailing "quote
fn ms_after_include(a) { return a; }
EOF
cat > "$P/src/ms_char.cyr" <<'EOF'
var MS_CHAR = '"';
fn ms_after_char(a) { return a; }
EOF
cat > "$P/src/ms_comment.cyr" <<'EOF'
# a comment holding a "quote opens nothing
fn ms_after_comment(a) { return a; }
EOF
{
    for m in ms_brace ms_fnline ms_body ms_bodyopen ms_escapes ms_derive ms_reopen ms_attr \
      ms_include ms_char ms_comment; do
        printf 'include "src/%s.cyr"\n' "$m"
    done
    printf 'fn main(): i64 { return 0; }\nvar r = main();\nsyscall(60, r);\n'
} > "$P/prog.cyr"
check "  (premise: 5 fixture lines begin \`fn ms_ghost\`)" 5 "$(cat "$P"/src/*.cyr | grep -c '^fn ms_ghost')"

echo "the tool"
arc=0
( cd "$P" && timeout 20 "$API" --update --scope=project --snapshot="$T/A.snap" ) > "$T/api.out" 2>&1 || arc=$?
check "api-surface --update runs (rc 0)" 0 "$arc"
sed 's/.*:://; s|/.*||' "$T/A.snap" | sort > "$T/A.txt"

echo "the compiler"
crc=0
( cd "$P" && CYRIUS_DCE_VERBOSE=1 "$CC" < prog.cyr > "$T/prog" 2> "$T/dce.txt" ) || crc=$?
check "the fixture project compiles (rc 0)" 0 "$crc"
sed -n 's/^  dead: \(ms_[A-Za-z0-9_]*\)$/\1/p' "$T/dce.txt" | sort > "$T/E.txt"
check "  (floor: the compiler emitted 15 fixture fns)" 15 "$(wc -l < "$T/E.txt" | tr -d ' ')"
check "  (the compiler emitted no ms_ghost / ms_fake fn)" 0 "$(grep -c 'ghost\|fake' "$T/E.txt")"

echo "axis 2 — the tool lists exactly what the compiler emitted"
check "listed but not emitted" "" "$(comm -23 "$T/A.txt" "$T/E.txt" | paste -sd' ' -)"
check "emitted but not listed" "" "$(comm -13 "$T/A.txt" "$T/E.txt" | paste -sd' ' -)"

echo "axis 3 — the literal table, per shape"
row() {  # $1 = module, $2 = its expected entries (space-separated)
    check "$1" "$2" "$(grep "^$1::" "$T/A.snap" | paste -sd' ' -)"
}
row ms_brace "ms_brace::ms_brace_after/1 ms_brace::ms_brace_before/1"
row ms_fnline "ms_fnline::ms_fnline_after/2"
row ms_body "ms_body::ms_body/1 ms_body::ms_body_after/1"
row ms_bodyopen "ms_bodyopen::ms_bodyopen/1 ms_bodyopen::ms_bodyopen_after/0"
row ms_escapes "ms_escapes::ms_escapes_after/1"
row ms_derive "ms_derive::ms_derive_after/1"
row ms_reopen "ms_reopen::ms_reopen_after/3"
row ms_attr "ms_attr::ms_attr/1 ms_attr::ms_attr_after/1"
row ms_include "ms_include::ms_after_include/1"
row ms_char "ms_char::ms_after_char/1"
row ms_comment "ms_comment::ms_after_comment/1"
check "  (the snapshot holds nothing else)" 15 "$(wc -l < "$T/A.snap" | tr -d ' ')"

if [ "$fails" -ne 0 ]; then
    echo "api_surface_multiline_strings: $fails of $checks check(s) FAILED"
    exit 1
fi
echo "api_surface_multiline_strings: $checks checks — a multi-line string hides no fn and invents none"
exit 0
