#!/bin/sh
# cybs_leading_underscore.sh — 6.6.17. cybs (the bootstrap compiler the 29 KB seed assembles)
# must lex a LEADING underscore as part of the identifier.
#
# THE DEFECT. cybs's lexer dispatch (bootstrap/cybs.cyr) sent a-z / A-Z to `lexer_ident` and
# everything else it did not know to `lexer_skip`, which DROPPED the byte. `_` had no arm, so
# `_fi` lexed as `fi`: a local `fi` and a local `_fi` shared one slot, `fn _aq` and `fn aq` were
# one fn, and a local `_x` captured every read of a global `x`. build/cycc lexes correctly, so
# only gen1 (cybs's compile of src/main.cyr) was wrong, and three places in src/ hit it:
#   _PARSE_FN_DEF_IMPL  `fi` / `_fi` — the fixup-shift loop clobbered the fn index, so the
#                       code-end table was written at a garbage index after every compacted fn
#   READFILE            `_allow_parent` / `allow_parent`, `_allow_abs` / `allow_abs` — gen1
#                       ignored CYRIUS_ALLOW_PARENT_INCLUDES=1 and CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1
# The first was harmless only while the fn tables sat in their fixed 8192-slot regions. Once
# the compiler passed 2048 fns (6.6.17's shared top-level scans did it) the tables grew to
# packed alloc'd buffers, the stray write landed in the struct-mask table, a tail call lost its
# TCO, and seed-derive went RED: gen2 != build/cycc. gen1 also differed from build/cycc on 41
# of the 453 tcyr (every program past 2048 fns); after the fix it matches on all 453.
#
# Rows: closure (the seed still assembles cybs, cybs still reproduces the seed); L/F/G — local,
# fn and global-vs-local pairs stay distinct under cybs; I — the real consequence: gen1 compiles
# a >2048-fn program byte-identically to build/cycc, and honours CYRIUS_ALLOW_PARENT_INCLUDES.
# MUTATION (6.6.17): the slot-open bootstrap/cybs.cyr (no `_` arm) -> RED on L, F, G and I.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: cybs_leading_underscore: cannot cd to $ROOT"; exit 1; }
[ -x bootstrap/asm ] || { echo "SKIP: cybs_leading_underscore: bootstrap/asm missing"; exit 77; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: cybs_leading_underscore: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cybs_leading_underscore: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0
bad() { echo "  FAIL: cybs_leading_underscore $1"; fail=$((fail + 1)); }

cat bootstrap/cybs.cyr | bootstrap/asm > "$D/cybs" 2>/dev/null || true
chmod +x "$D/cybs" 2>/dev/null || true
[ -s "$D/cybs" ] || { echo "FAIL: cybs_leading_underscore: the seed could not assemble bootstrap/cybs.cyr"; exit 1; }
cat bootstrap/asm.cyr | "$D/cybs" > "$D/asm2" 2>/dev/null || true
cmp -s "$D/asm2" bootstrap/asm || bad "closure: cybs no longer reproduces the seed"

# run <name> <want-rc>: compile $D/<name>.cyr with cybs, run it, compare the exit code
run() {
  "$D/cybs" < "$D/$1.cyr" > "$D/$1" 2>/dev/null || true
  chmod +x "$D/$1" 2>/dev/null || true
  rc=0; "$D/$1" || rc=$?
  [ "$rc" = "$2" ] || bad "row $1: exited $rc, want $2 — cybs merged an identifier with its leading-underscore twin"
}
printf 'fn t(): i64 {\n    var fi = 5;\n    var _fi = 9;\n    _fi = _fi + 1;\n    return fi;\n}\nsyscall(60, t());\n' > "$D/L.cyr"
printf 'fn _aq(): i64 { return 1; }\nfn aq(): i64 { return 2; }\nsyscall(60, aq() * 10 + _aq());\n' > "$D/F.cyr"
printf 'var gx = 5;\nfn t(): i64 {\n    var _gx = 9;\n    return gx + _gx * 0;\n}\nsyscall(60, t());\n' > "$D/G.cyr"
run L 5; run F 21; run G 5

# I — gen1 must compile like build/cycc. Both inputs pull in ~6100 fns, past the 2048-fn grow.
"$D/cybs" < src/main.cyr > "$D/gen1" 2>/dev/null || true
chmod +x "$D/gen1" 2>/dev/null || true
if [ ! -s "$D/gen1" ]; then
  bad "row I: cybs produced no gen1 from src/main.cyr"
else
  for f in tests/tcyr/compiler/large_input.tcyr tests/tcyr/compiler/large_source.tcyr; do
    "$D/gen1" < "$f" > "$D/o1" 2>/dev/null || true
    "$CC" < "$f" > "$D/o2" 2>/dev/null || true
    [ -s "$D/o2" ] && cmp -s "$D/o1" "$D/o2" || bad "row I: gen1 and $(basename "$CC") emit different bytes for $f"
  done
  mkdir -p "$D/p/sub"
  printf 'fn pq(): i64 { return 42; }\n' > "$D/p/pq.cyr"
  printf 'include "../pq.cyr"\nsyscall(60, pq());\n' > "$D/p/sub/m.cyr"
  ( cd "$D/p/sub" && CYRIUS_ALLOW_PARENT_INCLUDES=1 "$D/gen1" < m.cyr > "$D/pm" 2>/dev/null ) || true
  chmod +x "$D/pm" 2>/dev/null || true
  rc=0; [ -s "$D/pm" ] && { "$D/pm" || rc=$?; }
  [ "$rc" = 42 ] || bad "row I: gen1 ignored CYRIUS_ALLOW_PARENT_INCLUDES=1 (READFILE's _allow_parent / allow_parent pair)"
fi

if [ "$fail" -ne 0 ]; then echo "FAIL cybs_leading_underscore: $fail row(s) red"; exit 1; fi
echo "PASS cybs_leading_underscore: cybs keeps a leading underscore (local, fn and global pairs distinct; seed closure holds); gen1 compiles past the 2048-fn grow like build/cycc and honours CYRIUS_ALLOW_PARENT_INCLUDES"
exit 0
