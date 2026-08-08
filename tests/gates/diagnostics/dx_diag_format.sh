#!/bin/sh
# v6.4.60 (DX diagnostics): assert cycc's error output carries a COLUMN and a
# SOURCE-EXCERPT with a caret — the format is
#     error:<source>:LINE:COL: <message>
#         <offending source line>
#             ^
# Regression guard for the packed-tok_lines offset (lex.cyr ADDTOK / util.cyr
# GTLINE mask + GTOFF) and the _err_head / _err_col / _err_excerpt emitter path.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
T=$(mktemp); E=$(mktemp)
trap 'rm -f "$T" "$E"' EXIT

# A missing-semicolon error → "expected ';', got return"; the offending token is
# `return` at column 5 of line 3.
printf 'fn main(): i64 {\n    var x = 42\n    return x;\n}\n' > "$T"
if "$CC" < "$T" > /dev/null 2>"$E"; then
    echo "FAIL: the broken program compiled clean — expected a parse error"; exit 1
fi

# 1) COLUMN: error:<file>:LINE:COL:  (two numeric fields after the filename)
grep -Eq '^error:[^:]*:[0-9]+:[0-9]+: ' "$E" || { echo "FAIL: no :LINE:COL: column in the diagnostic:"; cat "$E"; exit 1; }
# 2) exact location — `return` starts at column 5 of line 3
grep -q ':3:5: ' "$E" || { echo "FAIL: wrong line:column (want :3:5:):"; cat "$E"; exit 1; }
# 3) the CARET line — leading spaces then a single ^
grep -Eq '^ +\^$' "$E" || { echo "FAIL: no caret excerpt line:"; cat "$E"; exit 1; }
# 4) the offending SOURCE line appears in the excerpt
grep -q 'return x;' "$E" || { echo "FAIL: source excerpt missing the offending line:"; cat "$E"; exit 1; }
# 5) the retired internal `at fail:` table dump must NOT reappear
grep -q 'at fail:' "$E" && { echo "FAIL: the retired 'at fail:' capacity dump is back:"; cat "$E"; exit 1; }

echo "PASS: dx diagnostics — column (:L:C:) + source excerpt + caret; no at-fail noise"
exit 0
