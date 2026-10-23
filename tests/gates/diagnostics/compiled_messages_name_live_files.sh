#!/bin/sh
# Gate: every compiler source file a compiled message of cycc names exists in the tree (6.7.18).
#
# THE DEFECT. The 6.7.18 frontend moves (src/frontend/lex_pp.cyr -> src/frontend/lex/pp.cyr, and the parse/
# folder) rewrote every path in comments, gates and docs, but one STRING the compiler prints kept the old
# name: the `#derive` field cap's "error: ... (max 256 — raise in lex_pp.cyr / S+0x1FC000 region)", sending a
# reader to a file that no longer exists. A move changes no bytes the compiler emits for a program, so the
# byte-identical proofs could not see it.
#
# ROWS — cycc built from this tree (the gate builds it: build/cycc may lag the sources inside a release):
#   N  every `.cyr` name in the compiler's own strings resolves to a file: a path from the root, from src/ or
#      from src/frontend/ (`lex/pp.cyr`), or a bare basename some file under src/ or lib/ has. `name.cyr` (the
#      include error's placeholder) is the one exception.
#   F  the floor: the scan finds at least 8 names (a broken extraction is not a pass)
#   D  the filed message itself: a 257-field `#derive(accessors)` struct is refused naming lex/pp.cyr
# MEASURED (6.7.18): on the parent (the string unfixed) N is RED naming lex_pp.cyr and D is RED.
#
# Exit 77 (named) when there is no compiler. CHANGELOG [6.7.18]
set -u
NAME=compiled_messages_name_live_files
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: $NAME — cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME — no compiler at $CC"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
bad() { echo "  FAIL: $NAME $1"; fails=$((fails + 1)); }

env -u CYRIUS_BOUNDS -u CYRIUS_COVERAGE -u CYRIUS_POISON "$CC" < src/main.cyr > "$T/cycc" 2> "$T/cycc.err" \
    || { echo "FAIL: $NAME — the tree's compiler does not build"; sed 's/^/    /' "$T/cycc.err" | head -5; exit 1; }
chmod +x "$T/cycc"

# N / F — the names, each a `.cyr` token not followed by a word character (`/.cyrius` is no name).
LC_ALL=C tr -c 'A-Za-z0-9_./\n-' '\n' < "$T/cycc" | grep -E '^[A-Za-z0-9_][A-Za-z0-9_./-]*\.cyr$' | LC_ALL=C sort -u > "$T/names"
n=$(grep -c . "$T/names" || true)
[ "$n" -ge 8 ] || bad "F: only $n .cyr names found in the compiler's strings (floor 8) — the extraction is broken"
find src lib -name '*.cyr' | sed 's|.*/||' | LC_ALL=C sort -u > "$T/bases"
while IFS= read -r p; do
    [ "$p" = "name.cyr" ] && continue
    case "$p" in
      */*) [ -f "$p" ] || [ -f "src/$p" ] || [ -f "src/frontend/$p" ] || bad "N: the compiler names $p, and no such file exists" ;;
      *)   grep -qx "$p" "$T/bases" || bad "N: the compiler names $p, and no file under src/ or lib/ has that name" ;;
    esac
done < "$T/names"
[ "$fails" -eq 0 ] && echo "  ok: N, F — $n .cyr names in the compiler's strings, each a file in the tree"

# D — the filed message, end to end.
{ printf '#derive(accessors)\nstruct Big {\n'
  i=0; while [ "$i" -lt 257 ]; do printf '    f%d;\n' "$i"; i=$((i + 1)); done
  printf '}\nvar r = 0;\n'; } > "$T/big.cyr"
rc=0; "$T/cycc" < "$T/big.cyr" > "$T/big.out" 2> "$T/big.err" || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'struct field cap exceeded (max 256 — raise in lex/pp.cyr / S+0x1FC000 region)' "$T/big.err"; then
    echo "  ok: D — a 257-field #derive struct is refused naming lex/pp.cyr (exit $rc)"
else
    bad "D: a 257-field #derive struct gave exit $rc and: $(head -c 200 "$T/big.err")"
fi

if [ "$fails" -gt 0 ]; then echo "FAIL: $NAME: $fails problem(s)"; exit 1; fi
echo "PASS: $NAME"
exit 0
