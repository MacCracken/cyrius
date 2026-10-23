#!/bin/sh
# tokname_every_emitted_token.sh — 6.7.14: every token number the lexer emits has a NAME, so a
# diagnostic whose cursor sits on it says what it is. TOKNAME (src/common/util.cyr) fell through to
# "unknown" for 24 operator / literal tokens (`<=` `>=` `&` `%` `|` `^` `~` `<<` `>>` `&&` `||`, the
# wrapping / saturating / checked operators, `...`, `?`, `@unsafe` and a float literal):
# `var x <= 1;` said "expected '=', got unknown". TOKNAME_OP names them (a separate fn: cybs's
# per-fn string-literal ceiling; not TOKNAME_BUILTIN, whose table IS the reserved set).
#
#   axis 1  the derivation (issues/archived/2026-10-08-tokname-operator-tokens-unnamed.md): every number in an
#           `ADDTOK(S, N` of src/frontend/{,lex/}*.cyr or a `return N` of LEXKW_EXT, minus 0 (LEXKW_EXT's
#           "not a keyword"), has an arm in TOKNAME, TOKNAME_OP or TOKNAME_BUILTIN. A floor on the
#           emitted set keeps a regex that matches nothing from passing. 6.7.17: and every `return N * 16` of
#           LEXATTRWORD (src/frontend/lex/attr.cyr) — the `#` attributes, emitted as `ADDTOK(S, atk >> 4, 0)`, which
#           the `ADDTOK(S, N` regex never saw — has one in TOKNAME_ATTR (`#deprecated` is 124, `?`'s).
#   axis 2  the filed loop: `var x <OP> 1;` reports "expected '=', got '<OP>'" for each of the 25
#           (`1.5` reads "got float literal"); no row says "got unknown". 6.7.17: the nine attributes the same way
#           (`var x #assert 1;` -> "got #assert"; a zone `var g = 1` before `#assert ..` said "got unknown").
#
# MEASURED (6.7.17): on the parent (no TOKNAME_ATTR) axis 1 is RED naming 107 109 110 122 125 126 127 133
# 163, axis 2 RED on the nine attribute rows.
#
# MUTATION (measured, 6.7.14): TOKNAME_OP removed (the fn and TOKNAME's call) -> axis 1 RED naming
# the 24 numbers, axis 2 RED on 24 of 25 rows (all but `>>>`, named since 6.7.5).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: tokname_every_emitted_token: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: tokname_every_emitted_token: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: tokname_every_emitted_token: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0; rows=0
bad() { echo "  FAIL: tokname_every_emitted_token $1"; fail=$((fail + 1)); }

# axis 1 — the derivation.
{ grep -ohE "ADDTOK\(S, *[0-9]+" src/frontend/*.cyr src/frontend/lex/*.cyr | grep -oE "[0-9]+$"
  awk '/^fn LEXKW_EXT/,/^}/' src/frontend/lex/lex.cyr | grep -oE "return [0-9]+" | grep -oE "[0-9]+"
  awk '/^fn LEXATTRWORD/,/^}/' src/frontend/lex/attr.cyr | grep -oE "return [0-9]+ \* 16" | grep -oE "[0-9]+ " | tr -d ' '; } \
  | grep -vx 0 | sort -u > "$D/em"
awk '/^fn TOKNAME_BUILTIN/,/^}/; /^fn TOKNAME_OP/,/^}/; /^fn TOKNAME_ATTR/,/^}/; /^fn TOKNAME\(/,/^}/' src/common/util.cyr \
  | grep -oE "typ == [0-9]+" | grep -oE "[0-9]+" | sort -u > "$D/nm"
ne=$(wc -l < "$D/em" | tr -d ' ')
rows=$((rows + 1))
[ "$ne" -ge 120 ] || bad "A1: the emitted-token derivation found only $ne numbers (floor 120): the regex no longer matches the lexer"
unnamed=$(comm -23 "$D/em" "$D/nm" | sort -n | tr '\n' ' ')
rows=$((rows + 1))
[ -z "$unnamed" ] || bad "A1: emitted token number(s) with no TOKNAME arm: $unnamed"

# axis 2 — the filed loop, verbatim shapes.
row() {
  rows=$((rows + 1))
  printf 'fn main() {\n    var x %s 1;\n    return 0;\n}\nvar r = main();\n' "$1" > "$D/op.cyr"
  rc=0; "$CC" < "$D/op.cyr" > "$D/o" 2> "$D/e" || rc=$?
  [ "$rc" -ne 0 ] || { bad "A2 '$1': rc 0, expected a refusal"; return; }
  l=$(grep -m1 '^error' "$D/e" || true)
  case "$l" in
    *"expected '=', got $2") ;;
    *) bad "A2 '$1': expected \"got $2\" — got: $l"; return ;;
  esac
  if grep -q "got unknown" "$D/e"; then bad "A2 '$1': still says 'got unknown'"; fi
}
for op in '<=' '>=' '%' '&' '|' '^' '<<' '>>' '&&' '||' '~' '?' '+%' '+|' '+?' '-%' '-|' '-?' \
          '*%' '*|' '*?' '...' '@unsafe' '>>>'; do
  row "$op" "'$op'"
done
row '1.5' 'float literal'
for at in '#assert' '#regalloc' '#pe_import' '#must_use' '#pure' '#io' '#alloc' '#naked' '#inline'; do
  row "$at" "$at"
done
[ "$rows" -ge 36 ] || bad "only $rows rows ran"

if [ "$fail" -ne 0 ]; then echo "FAIL tokname_every_emitted_token: $fail of $rows row(s) red"; exit 1; fi
echo "PASS tokname_every_emitted_token: $rows rows — all $ne token numbers the lexer emits have a name, and the 25 operator / literal rows and the nine attribute rows name their token (never 'got unknown')"
exit 0
