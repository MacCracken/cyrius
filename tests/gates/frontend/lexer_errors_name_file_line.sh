#!/bin/sh
# tests/gates/frontend/lexer_errors_name_file_line.sh — 6.6.10
#
# The LEXER refuses every byte that begins no token, and every lexer error names
# `<file>:<line>:<col>` — the same head the parser's diagnostics carry.
#
# AXIS 1 — ⛔ CVE-52. The `@` arm (v5.6.3) skipped any `@` that did not spell `@unsafe`,
# and CVE-31's stray-byte sweep (v6.1.35) never touched it: `return @@@;` compiled and
# returned 0, `5 @- 3` was 2, `@y` was y, `a @* 2` was a*2, and `cyrius lint` passed all
# of it. Every shape below must now exit 1 with `unexpected character (0x40)`.
# AXIS 2 — ANTI-VACUOUS: `@unsafe` is still a block, and still runs.
# AXIS 3 — the location. Lexer errors printed `error:<N>:` with N the raw EXPANDED line
# (marker lines and included bodies counted) and no file and no column: `$` on line 1 of
# a one-line file said `error:2:`. A defect inside an INCLUDED file must name that file.
#
# MUTATION PROOF (6.6.10):
#   * restore `p = p + 1;` in lex.cyr's `@` arm in place of `_lex_stray(S, p, c);`
#     -> axis 1 RED (every `@` shape compiles, rc 0); axes 2-3 green.
#   * make `_lex_err_head` print `PRNUM(GCLINE(S))` instead of FM_LOOKUP + column
#     -> axes 1, 3 and 4 RED on every row.
#   * in lex_pp.cyr PP_DEFINE, pass `ERR_MSG(S, ...)` back instead of `_pp_err_at`
#     -> axis 5 RED (`error:0:1:` is back).
# AXIS 4 — the 16 char/string-literal error sites, each by file:line:col.
# AXIS 5 — the preprocessor's flag-table cap printed `error:0:1:` (ERR_MSG reads the token
# cursor, and no token exists yet); it names the #define's file:line:col now.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: lexer_errors_name_file_line — $CC not built"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: lexer_errors_name_file_line: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
# refused <name> <printf-fmt> <want-rc> <want-stderr-substring>  (compiled from $T, stdin)
refused() {
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    ( cd "$T" && "$CC" < "$T/$1.cyr" > "$T/$1.out" 2> "$T/$1.err" ) || rc=$?
    check "$1: exits 1" 1 "$rc"
    check "$1: names '$3'" yes "$(grep -qF -- "$3" "$T/$1.err" && echo yes || echo no)"
    check "$1: emits no binary" 0 "$(wc -c < "$T/$1.out" | tr -d ' ')"
}

echo "axis 1 — ⛔ CVE-52: a stray '@' is refused, not dropped:"
refused at_triple  'fn f(): i64 { return @@@; }\nvar r = f();\nsyscall(60, r);\n'   'error:<source>:1:22: unexpected character (0x40)'
refused at_single  'fn f(): i64 { return @; }\nvar r = f();\n'                        'error:<source>:1:22: unexpected character (0x40)'
refused at_minus   'var y = 5 @- 3;\nsyscall(60, y);\n'                               'error:<source>:1:11: unexpected character (0x40)'
refused at_prefix  'var y = 7;\nvar z = @y;\nsyscall(60, z);\n'                       'error:<source>:2:9: unexpected character (0x40)'
refused at_times   'var a = 3;\nvar b = a @* 2;\nsyscall(60, b);\n'                   'error:<source>:2:11: unexpected character (0x40)'
refused at_unsafe2 'fn f(): i64 { @@unsafe { return 1; } }\nvar r = f();\n'            'error:<source>:1:15: unexpected character (0x40)'
refused at_eof     'var a = @'                                                        'error:<source>:1:9: unexpected character (0x40)'

echo "axis 2 — ANTI-VACUOUS: @unsafe is still accepted, and runs:"
printf 'fn f(): i64 { @unsafe { return 3; } }\nsyscall(60, f());\n' > "$T/ok.cyr"
rc=0; "$CC" < "$T/ok.cyr" > "$T/ok" 2> "$T/ok.err" || rc=$?
check "@unsafe compiles" 0 "$rc"
chmod +x "$T/ok"
rc=0; "$T/ok" || rc=$?
check "@unsafe block runs (exit 3)" 3 "$rc"

echo "axis 3 — every lexer error names <file>:<line>:<col>:"
refused dollar     'var a = 1;\nvar b = $;\n'                                         'error:<source>:2:9: unexpected character (0x24)'
refused nonascii   'var a = 1;\nvar c = 1 \303\251;\n'                                'error:<source>:2:11: non-ASCII byte (0xc3) -- only ASCII allowed in source (UTF-8 ok in strings)'
mkdir -p "$T/inc"
printf 'fn h(): i64 {\n    return 1 @ 2;\n}\n' > "$T/inc/bad_inc.cyr"
refused in_include 'var a = 1;\ninclude "inc/bad_inc.cyr"\nvar r = h();\n'           'error:inc/bad_inc.cyr:2:14: unexpected character (0x40)'

echo "axis 4 — every char/string-literal error (16 sites) names <file>:<line>:<col>:"
# char literals point at the opening quote (col 9), string escapes at their backslash
# (col 10: `var t = "` is 9 bytes). Line 2 of 2 — 6.6.9 said `error:3:` for all of them.
L='var a = 1;\n'
refused ch_unterm     "${L}var c = '"                       "error:<source>:2:9: unterminated char literal"
refused ch_unterm_esc "${L}var c = '\\\\"                   "error:<source>:2:9: unterminated char escape"
refused ch_bad_esc    "${L}var c = '\\\\q';\n"              "error:<source>:2:9: unknown char escape"
refused ch_unterm2    "${L}var c = 'a"                      "error:<source>:2:9: unterminated char literal"
refused ch_multi      "${L}var c = 'ab';\n"                 "error:<source>:2:9: multi-byte char literal not supported"
refused x_short       "${L}var t = \"\\\\x1"                "error:<source>:2:10: \\x escape needs two hex digits"
refused x_bad1        "${L}var t = \"\\\\xZ1\";\n"          "error:<source>:2:10: \\x escape: bad hex digit"
refused x_bad2        "${L}var t = \"\\\\x1Z\";\n"          "error:<source>:2:10: \\x escape: bad hex digit"
refused ub_open       "${L}var t = \"\\\\u{12"              "error:<source>:2:10: \\u{...} escape: missing closing brace"
refused ub_bad        "${L}var t = \"\\\\u{1Z}\";\n"        "error:<source>:2:10: \\u{...} escape: bad hex digit"
refused ub_long       "${L}var t = \"\\\\u{1234567}\";\n"   "error:<source>:2:10: \\u{...} escape: > 6 hex digits"
refused ub_empty      "${L}var t = \"\\\\u{}\";\n"          "error:<source>:2:10: \\u{...} escape: no hex digits"
refused u4_short      "${L}var t = \"\\\\u12"               "error:<source>:2:10: \\u escape needs four hex digits"
refused u4_bad        "${L}var t = \"\\\\u12Z4\";\n"        "error:<source>:2:10: \\u escape: bad hex digit"
refused u_big         "${L}var t = \"\\\\u{110000}\";\n"    "error:<source>:2:10: \\u escape: codepoint > U+10FFFF"
refused u_surr        "${L}var t = \"\\\\uD800\";\n"        "error:<source>:2:10: \\u escape: surrogate codepoint not allowed"

echo "axis 5 — the preprocessor flag-table cap names the #define, not \`error:0:1:\`:"
# 16 slots shared with the builtin predefines, so 20 user #defines overflow on every
# target. The first refused one is whichever lands on slot 16; the row checks the SHAPE
# (a real file and a line inside the defines) and that 0:1 is gone.
: > "$T/ppcap.cyr"
i=0; while [ "$i" -lt 20 ]; do echo "#define PPLOC_D$i" >> "$T/ppcap.cyr"; i=$((i + 1)); done
echo 'var r = 0;' >> "$T/ppcap.cyr"
rc=0; "$CC" < "$T/ppcap.cyr" > /dev/null 2> "$T/ppcap.err" || rc=$?
check "20 #defines: refused" 1 "$rc"
check "no locationless error:0:1:" 0 "$(grep -c '^error:0:1:' "$T/ppcap.err" || true)"
check "names <source>:<line>:9 inside the defines" yes \
    "$(grep -qE '^error:<source>:(1[0-9]|20):9: too many preprocessor #define/flag entries' "$T/ppcap.err" && echo yes || echo no)"
# ERR_MSG also set the panic latch, so the FIRST real parse error after a refused #define
# was swallowed (6.6.9: only the cap errors printed). The pp report leaves the latch alone.
cp "$T/ppcap.cyr" "$T/ppcap2.cyr"
echo 'var x = 2 3;' >> "$T/ppcap2.cyr"
"$CC" < "$T/ppcap2.cyr" > /dev/null 2> "$T/ppcap2.err" || true
check "a parse error after the refused #defines is still reported" 1 \
    "$(grep -c "^error:<source>:22:11: expected ';', got number 3" "$T/ppcap2.err" || true)"
cp "$T/ppcap.cyr" "$T/inc/ppcap_inc.cyr"
printf 'var a = 1;\ninclude "inc/ppcap_inc.cyr"\n' > "$T/ppcap_main.cyr"
rc=0; ( cd "$T" && "$CC" < "$T/ppcap_main.cyr" > /dev/null 2> "$T/ppcap_inc.err" ) || rc=$?
check "20 #defines in an INCLUDED file: refused" 1 "$rc"
check "…named by the included file's own line" yes \
    "$(grep -qE '^error:inc/ppcap_inc.cyr:(1[0-9]|20):9: too many preprocessor' "$T/ppcap_inc.err" && echo yes || echo no)"

echo ""
if [ "$fails" = 0 ]; then
    echo "PASS: lexer_errors_name_file_line — stray bytes refused (CVE-52), lexer errors name file:line:col"
    exit 0
fi
echo "FAIL: lexer_errors_name_file_line — $fails assertion(s) failed"
exit 1
