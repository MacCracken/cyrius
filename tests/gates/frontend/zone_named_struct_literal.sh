#!/bin/sh
# zone_named_struct_literal.sh — 6.7.14: a NAMED-field struct literal initialises a declaration-zone global. The
# zone's replay (EMIT_GVAR_INITS) called the positional walk itself, so `var p = P { a: 1, b: 2 };` before the first
# top-level statement was "undefined variable 'a'" + "unexpected ':'" — in a `kernel;` build too — while the same
# literal in a fn or after a statement compiled; the guide's Structs example failed as written. The replay reads the
# literal through _STRUCT_INIT_BODY (`_gvi_struct_body`), and an all-constant named literal is baked like a
# positional one (`_spc_nfields`), so an x86 kernel build's program sees it
# (issues/2026-10-09-declaration-zone-named-struct-literal-refused.md). The values on every target are
# tests/tcyr/crossos/zone_named_struct_literal.tcyr.
#
#   N1-N3  the filed repros verbatim: n1 exits 2, the annotated form 2, g816 (the guide example) 50
#   K1     the `kernel;` form (ELF64 kernel): builds with NO late-initializer warning and its program reads 2 —
#          the positional form's parity
#   K2     a kernel named literal with a run-time element stays late: named once and read as 0, as the positional
#          literal beside it is
#   E1-E4  a bad named literal in the zone gets the one error the same literal gets after a statement: an unknown
#          field, a missing field, a repeated field, a nested struct field
#
# MUTATION (measured, 6.7.14): the replay's struct arm back on `_emit_struct_positional_init` -> N1-N3, K1, K2 and
# E1-E4 RED (the filed "undefined variable 'a'"); `_spc_walk` without its named arm -> K1 RED (the late warning, 0).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: zone_named_struct_literal: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: zone_named_struct_literal: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: zone_named_struct_literal: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0; rows=0
bad() { echo "  FAIL: zone_named_struct_literal $1"; fail=$((fail + 1)); }
KW='in a kernel build the initializer of'

# build ID WANT_EXIT WANT_WARNINGS [env] — the source on stdin compiles (only WANT_WARNINGS late-initializer
# warnings, no other diagnostic) and exits WANT_EXIT.
build() {
  rows=$((rows + 1))
  cat > "$D/$1.cyr"
  rc=0
  if [ "${4:-}" = kernel ]; then CYRIUS_ELF64_KERNEL=1 "$CC" < "$D/$1.cyr" > "$D/$1" 2> "$D/$1.err" || rc=$?
  else "$CC" < "$D/$1.cyr" > "$D/$1" 2> "$D/$1.err" || rc=$?; fi
  [ "$rc" -eq 0 ] || { bad "$1: compile rc $rc: $(grep -m1 '^error' "$D/$1.err")"; return; }
  nk=$(grep -c "^warning.*$KW" "$D/$1.err")
  na=$(grep -cE '^(error|warning)' "$D/$1.err")
  [ "$nk" -eq "$3" ] && [ "$na" -eq "$3" ] || { bad "$1: $na diagnostic(s) ($nk late-initializer), expected $3: $(grep -E '^(error|warning)' "$D/$1.err" | tr '\n' '|')"; return; }
  [ -s "$D/$1" ] || { bad "$1: empty output"; return; }
  chmod +x "$D/$1"
  x=0; timeout 10 "$D/$1" > /dev/null 2>&1 || x=$?
  [ "$x" -eq "$2" ] || bad "$1: exit $x, expected $2"
}
# same ID — the source on stdin in the zone and after a first statement: the same one error, rc 1 both.
same() {
  rows=$((rows + 1))
  cat > "$D/$1.cyr"
  awk 'BEGIN { d = 0 } /^var/ && d == 0 { print "syscall(1, 1, 0, 0);"; d = 1 } { print }' "$D/$1.cyr" > "$D/$1s.cyr"
  r1=0; "$CC" < "$D/$1.cyr" > "$D/$1" 2> "$D/$1.err" || r1=$?
  r2=0; "$CC" < "$D/$1s.cyr" > "$D/$1s" 2> "$D/$1s.err" || r2=$?
  [ "$r1" -ne 0 ] && [ "$r2" -ne 0 ] || { bad "$1: rc zone $r1 / after a statement $r2, expected both refused"; return; }
  grep -E '^(error|warning)' "$D/$1.err" | sed 's/<source>:[0-9]*:/L:/' > "$D/$1.a"
  grep -E '^(error|warning)' "$D/$1s.err" | sed 's/<source>:[0-9]*:/L:/' > "$D/$1.b"
  n=$(wc -l < "$D/$1.a" | tr -d ' ')
  [ "$n" -eq 1 ] || { bad "$1: $n diagnostics in the zone, expected one: $(tr '\n' '|' < "$D/$1.a")"; return; }
  cmp -s "$D/$1.a" "$D/$1.b" || bad "$1: the zone says $(tr '\n' '|' < "$D/$1.a") — after a statement $(tr '\n' '|' < "$D/$1.b")"
}

build N1 2 0 <<'EOF'
struct P { a; b; }
var p = P { a: 1, b: 2 };
syscall(60, p.b);
EOF
build N2 2 0 <<'EOF'
struct P { a; b; }
var p: P = P { b: 2, a: 1 };
syscall(60, p.b);
EOF
build N3 50 0 <<'EOF'
struct Point { x; y; }
var p = Point { 10, 20 };
var q = Point { x: 10, y: 20 };
var sum = p.x + p.y;
syscall(60, sum + q.y);
EOF
build K1 2 0 kernel <<'EOF'
kernel;
struct P { a; b; }
var p = P { a: 1, b: 2 };
syscall(60, p.b);
EOF
build K2 0 2 kernel <<'EOF'
kernel;
struct P { a; b; }
fn two(): i64 { return 2; }
var p = P { a: 1, b: two() };
var q = P { 1, two() };
syscall(60, p.b + q.b);
EOF
same E1 <<'EOF'
struct P { a; b; }
var p = P { a: 1, z: 2 };
syscall(60, p.b);
EOF
same E2 <<'EOF'
struct P { a; b; }
var p = P { a: 1 };
syscall(60, p.a);
EOF
same E3 <<'EOF'
struct P { a; b; }
var p = P { a: 1, a: 2, b: 3 };
syscall(60, p.a);
EOF
same E4 <<'EOF'
struct Q { x; y; }
struct P { q: Q; b; }
var p = P { b: 1, q: 2 };
syscall(60, p.b);
EOF

[ "$rows" -ge 9 ] || bad "only $rows rows ran"
if [ "$fail" -ne 0 ]; then echo "FAIL zone_named_struct_literal: $fail of $rows row(s) red"; exit 1; fi
echo "PASS zone_named_struct_literal: $rows rows — a named struct literal initialises a declaration-zone global (the filed n1 / annotated / guide example), is baked in a kernel build, and a bad one gets the error it gets after a statement"
exit 0
