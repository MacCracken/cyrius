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
#     -> axis 3 RED on every row.
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

echo ""
if [ "$fails" = 0 ]; then
    echo "PASS: lexer_errors_name_file_line — stray bytes refused (CVE-52), lexer errors name file:line:col"
    exit 0
fi
echo "FAIL: lexer_errors_name_file_line — $fails assertion(s) failed"
exit 1
