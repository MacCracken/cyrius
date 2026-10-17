#!/bin/sh
# zone_pointer_annotation.sh — 6.7.14: a declaration-zone global's pointer annotation is read whole by the
# initialiser replay. EMIT_GVAR_INITS read it with `_gvi_ann`, which stepped ONE `*` and then one token: `var P:
# **i64 = 0;` before the first top-level statement left the cursor on `i64` ("expected '=', got identifier 'i64'",
# rc 1, no binary), `***i64` on the third `*` (+ "undefined variable 'i64'"), `**B<i64>` on `B`, and a refused
# `*( .. )` inside its parentheses (a second error after its refusal). The same declarations after a statement, or
# as a fn local, compiled. `_gvi_ann` now steps every leading `*` (`_gvi_stars`, as pass 1's `_ptr_annot` does)
# and a refused `*( .. )` to its `)` (issues/2026-10-14-declaration-zone-pointer-annotation-replay-reads-one-star.md).
#
#   Z1-Z3  the filed repros verbatim: `**i64` builds and exits 0; `*(i64, i64)` gives exactly its one refusal
#   Z4-Z6  `***i64`, `**(i64, i64)`, `**[i64]` in the zone: built / one refusal each
#   R1-R3  the zone pointers carry their values: `**i64` and `***i64` to a global (7), `**B<i64>` (4), mixed
#          with a following scalar global (10)
#   A1-A3  the same declarations after a top-level statement (the path that always read them whole)
#   W1     `var P: **i64 = 5;` in the zone warns once, as `*i64 = 5` does (6.7.13's D18 (a)); `= 0` is quiet
#
# MUTATION (measured, 6.7.14): `_gvi_stars` reading one `*` (its `while` an `if`) -> Z1, Z4, Z5, Z6, R1-R3 and W1
# RED (the filed "expected '='" text); the `*( .. )` step removed -> Z3 and Z5 RED (the second error).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: zone_pointer_annotation: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: zone_pointer_annotation: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: zone_pointer_annotation: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0; rows=0
bad() { echo "  FAIL: zone_pointer_annotation $1"; fail=$((fail + 1)); }

# build ID WANT_EXIT — the source on stdin compiles with no diagnostic at all and exits WANT_EXIT.
build() {
  rows=$((rows + 1))
  cat > "$D/$1.cyr"
  rc=0; "$CC" < "$D/$1.cyr" > "$D/$1" 2> "$D/$1.err" || rc=$?
  [ "$rc" -eq 0 ] || { bad "$1: compile rc $rc: $(head -1 "$D/$1.err")"; return; }
  [ -s "$D/$1.err" ] && { bad "$1: diagnostics on a clean build: $(head -1 "$D/$1.err")"; return; }
  [ -s "$D/$1" ] || { bad "$1: empty output"; return; }
  chmod +x "$D/$1"
  x=0; "$D/$1" > /dev/null 2>&1 || x=$?
  [ "$x" -eq "$2" ] || bad "$1: exit $x, expected $2"
}
# refuse ID TEXT — exactly one diagnostic line (the refusal TEXT), rc 1.
refuse() {
  rows=$((rows + 1))
  cat > "$D/$1.cyr"
  rc=0; "$CC" < "$D/$1.cyr" > "$D/$1" 2> "$D/$1.err" || rc=$?
  [ "$rc" -ne 0 ] || { bad "$1: rc 0, expected the refusal"; return; }
  n=$(grep -cE '^(error|warning)' "$D/$1.err")
  [ "$n" -eq 1 ] || { bad "$1: $n diagnostics, expected exactly the refusal: $(grep -E '^(error|warning)' "$D/$1.err" | tr '\n' '|')"; return; }
  grep -q "^error.*$2" "$D/$1.err" || bad "$1: the one diagnostic is not \"$2\": $(head -1 "$D/$1.err")"
}

build Z1 0 <<'EOF'
var P: **i64 = 0;
fn main(): i64 { return 0; }
syscall(60, main());
EOF
build Z2 0 <<'EOF'
syscall(1, 1, 0, 0);
var P: **i64 = 0;
syscall(60, 0);
EOF
refuse Z3 'a tuple type cannot be a pointer target' <<'EOF'
var P: *(i64, i64) = 0;
fn main(): i64 { return 0; }
syscall(60, main());
EOF
build Z4 0 <<'EOF'
var P: ***i64 = 0;
fn main(): i64 { return 0; }
syscall(60, main());
EOF
refuse Z5 'a tuple type cannot be a pointer target' <<'EOF'
var P: **(i64, i64) = 0;
syscall(60, 0);
EOF
refuse Z6 'a pointer to a slice is not a type' <<'EOF'
var P: **[i64] = 0;
syscall(60, 0);
EOF
build R1 7 <<'EOF'
var X = 7;
var P: *i64 = &X;
var PP: **i64 = &P;
var PPP: ***i64 = &PP;
syscall(60, load64(load64(load64(PPP))));
EOF
build R2 4 <<'EOF'
struct B<T> { v: T; }
var X: B<i64> = B<i64> { 4 };
var P: *B<i64> = &X;
var PP: **B<i64> = &P;
syscall(60, load64(load64(PP)));
EOF
build R3 10 <<'EOF'
var X = 7;
var P: *i64 = &X;
var PP: **i64 = &P;
var G = 3;
syscall(60, load64(load64(PP)) + G);
EOF
build A1 0 <<'EOF'
syscall(1, 1, 0, 0);
var P: ***i64 = 0;
syscall(60, 0);
EOF
refuse A2 'a tuple type cannot be a pointer target' <<'EOF'
syscall(1, 1, 0, 0);
var P: *(i64, i64) = 0;
syscall(60, 0);
EOF
build A3 7 <<'EOF'
var X = 7;
syscall(1, 1, 0, 0);
var P: *i64 = &X;
var PP: **i64 = &P;
syscall(60, load64(load64(PP)));
EOF
rows=$((rows + 1))
printf 'var P: **i64 = 5;\nvar Q: **i64 = 0;\nsyscall(60, 0);\n' > "$D/W1.cyr"
rc=0; "$CC" < "$D/W1.cyr" > "$D/W1" 2> "$D/W1.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "W1: compile rc $rc: $(head -1 "$D/W1.err")"
else
  n=$(grep -cE '^(error|warning)' "$D/W1.err")
  [ "$n" -eq 1 ] && grep -q '^warning:<source>:1:.*assigning non-pointer to typed pointer' "$D/W1.err" \
    || bad "W1: expected one warning at line 1 (\`= 5\`), got: $(grep -E '^(error|warning)' "$D/W1.err" | tr '\n' '|')"
fi

[ "$rows" -ge 13 ] || bad "only $rows rows ran"
if [ "$fail" -ne 0 ]; then echo "FAIL zone_pointer_annotation: $fail of $rows row(s) red"; exit 1; fi
echo "PASS zone_pointer_annotation: $rows rows — a declaration-zone \`**T\` / \`***T\` global builds and carries its value, a refused \`*( .. )\` / \`**[T]\` gives its one refusal"
exit 0
