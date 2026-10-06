#!/bin/sh
# diag_location_eof_and_tail_private.sh — 6.6.17. Two diagnostics that did not name the place
# they describe, unlike every other one (`<file>:line:col`):
#
#   P  the `private` error for a TAIL call. `return pv(x);` on line 3, with `pv` private to an
#      included file, was reported at 4:1 — the `}` below it — because `_vis_check` read the
#      cursor, which a tail call has already moved past `);`. 6.6.16's C9 fixed the same
#      mislocation for `#deprecated`; `private` now takes the same call-site token.
#   E  `expected '}', got end of file`. The EOF token carried the lexer's line at the end of the
#      buffer, one past the last file-map span, so `fn outer() { var x = 1;` (one line) said
#      `error:3:24:` with no `<source>:`, and an unterminated fn in an included file said
#      `error:6:1:` with a `#@file` marker as its excerpt. It now sits just past the last byte
#      of real source (trailing whitespace and `#@` marker lines skipped).
#
# Each row asserts the exact `<file>:line:col` head; row F (anti-vacuous) requires every
# `error:` line any row printed to carry a file name. Run through x86 and the tree's aarch64
# cross compiler (the frontend is shared; this pins that it stays shared).
# RED on the slot-open compiler (4a37046b, x86): P1, P3, E1, E2, E3, E4 and F; P2 is the control.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: diag_location_eof_and_tail_private: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: diag_location_eof_and_tail_private: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: diag_location_eof_and_tail_private: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
"$CC" < src/main_aarch64.cyr > "$D/xa64" 2>/dev/null && chmod +x "$D/xa64" \
  || { echo "FAIL: diag_location_eof_and_tail_private: could not build src/main_aarch64.cyr"; exit 1; }
cd "$D" || exit 1
fail=0; rows=0
bad() { echo "  FAIL: diag_location_eof_and_tail_private $1"; fail=$((fail + 1)); }

printf 'private\nfn pv(x): i64 { return x + 1; }\n' > pv.cyr
# P1 tail + P2 non-tail, callee stamped before the caller
printf 'include "pv.cyr"\nfn f(x): i64 {\n    return pv(x);\n}\nfn g(x): i64 {\n    var r = pv(x);\n    return r;\n}\nvar a = f(1) + g(1);\n' > p1.cyr
# P3 the deferred path: the caller is parsed before the private file is included
printf 'fn f(x): i64 {\n    return pv(x);\n}\ninclude "pv.cyr"\nvar a = f(1);\n' > p3.cyr
printf 'fn outer() { var x = 1;\n' > e1.cyr
printf 'fn outer() { var x = 1;' > e2.cyr
printf 'fn pq(): i64 { return 1; }\nfn outer() { var x = 1;\n' > inc.cyr
printf 'include "inc.cyr"\n' > e3.cyr
printf 'include "inc.cyr"\nvar z = 1;\n' > e4.cyr

# row <label> <compiler> <file> <expected error head, after `error:`> [<excerpt text>]
row() {
  rows=$((rows + 1))
  rc=0; "$2" < "$3" > o 2> e || rc=$?
  cat e >> all.err
  [ "$rc" -ne 0 ] || { bad "$1: rc 0, expected a refusal"; return; }
  grep -qF "error:$4" e || { bad "$1: no 'error:$4' — got: $(grep -m1 '^error' e)"; return; }
  if [ -n "${5:-}" ]; then grep -qF -- "$5" e || bad "$1: the excerpt does not show '$5'"; fi
}
for cc in "$CC" "$D/xa64"; do
  l=$(basename "$cc")
  row "P1 $l" "$cc" p1.cyr "<source>:3:15: 'pv' is private to its file"
  row "P2 $l" "$cc" p1.cyr "<source>:6:16: 'pv' is private to its file"
  row "P3 $l" "$cc" p3.cyr "<source>:2:15: 'pv' is private to its file"
  row "E1 $l" "$cc" e1.cyr "<source>:1:24: expected '}', got end of file" "fn outer() { var x = 1;"
  row "E2 $l" "$cc" e2.cyr "<source>:1:24: expected '}', got end of file" "fn outer() { var x = 1;"
  row "E3 $l" "$cc" e3.cyr "inc.cyr:2:24: expected '}', got end of file" "fn outer() { var x = 1;"
  row "E4 $l" "$cc" e4.cyr "<source>:2:11: expected '}', got end of file" "var z = 1;"
done
# F — anti-vacuous: no error line anywhere above lacks its file
if grep -E '^error:[0-9]' all.err > /dev/null; then bad "F: an error line has no file name: $(grep -m1 -E '^error:[0-9]' all.err)"; fi
grep -q '#@file' all.err && bad "F: a preprocessor marker was shown as a source excerpt"
[ "$rows" -ge 14 ] || bad "only $rows rows ran"

if [ "$fail" -ne 0 ]; then echo "FAIL diag_location_eof_and_tail_private: $fail of $rows row(s) red"; exit 1; fi
echo "PASS diag_location_eof_and_tail_private: $rows rows — a tail call's private error names its own line (stamped and deferred), and end of file is reported at <file>:line:col just past the last source byte (with or without a final newline, inside an include), x86 + aarch64 cross"
exit 0
