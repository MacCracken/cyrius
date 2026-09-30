#!/bin/sh
# redefinition_layout_and_enum_over_var.sh — 6.6.9 bite 3. Two silent redefinitions are
# reported.
#
# (1) A second `struct X` / `union X` with a DIFFERENT layout. REGSTRUCT appended and FINDSTRUCT
#     returned the first match, so the second definition was registered and never read: sizeof
#     and every field offset came from the first, with no diagnostic. Two `#derive(accessors)`
#     structs `SP` of 5 and 3 fields built rc 0 with sizeof(SP) = 40. (6.6.11: a derived
#     redefinition with other field names, order or size is now a build error — the derive
#     layout backstop, tests/gates/diagnostics/derive_layout_backstop.sh F — so `sp_derive`
#     redefines SP with the same names at the same offsets and another field TYPE — the garjan +
#     prani DcBlocker shape; an 8-byte struct type, because f64 / i64 / untyped do not differ to
#     the parser — which still builds and warns, now at line 5.)
# (2) An ENUM constant declared after a global of the same name whose value is ZERO or COMPUTED
#     (`var A = 0;`, `var A = f();`, `var A = "s";`). CHK_ENUM_SHADOW refuses the opposite
#     order and CHKDUPVAL compares two literals, but this pairing was silent. Every later use
#     folded to the constant, including in the variable's own module.
#
# Both are WARNINGS: the builds that carry them today keep compiling.
#
# Anti-vacuous rows: an IDENTICAL redefinition stays silent; distinct names stay silent; a zero
# constant over a zero var is not reported; the literal-vs-enum conflict keeps its existing
# CHKDUPVAL wording. The compilers are built FROM SOURCE, so reverting either fix turns this RED.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: redefinition_layout_and_enum_over_var: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL redefinition_layout_and_enum_over_var: no compiler at $CC"; exit 1; }
cd "$R" || exit 1
"$CC" < src/main.cyr > "$T/x86" 2>"$T/eb" || { echo "FAIL redefinition_layout_and_enum_over_var: stage1 build failed"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/x86"
"$T/x86" < src/main_aarch64.cyr > "$T/aarch64" 2>"$T/eb" || { echo "FAIL redefinition_layout_and_enum_over_var: could not build src/main_aarch64.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/aarch64"
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

fx() { printf '%s\n' "$2" > "$T/$1.cyr"; }
# (1) struct / union redefinition
fx sp_derive 'struct W { v; }
#derive(accessors)
struct SP { a; b; c; d; e; }
#derive(accessors)
struct SP { a: W; b; c; d; e; }
syscall(60, sizeof(SP));'
fx sp_width 'struct SP { a; b: i32; }
struct SP { a; b; }
syscall(60, sizeof(SP));'
fx sp_kind 'struct SP { a; b; }
union SP { a; b; }
syscall(60, sizeof(SP));'
fx un_field 'union U { a; b; }
union U { a; c; }
syscall(60, sizeof(U));'
fx sp_same 'struct SP { a; b: i32; }
struct SP { a; b: i32; }
syscall(60, sizeof(SP));'
fx sp_distinct 'struct SP { a; b; }
struct SQ { a; }
syscall(60, sizeof(SP));'
# (2) enum constant over a zero / computed global
fx ev_call 'fn g() { return 9; }
var A = g();
enum Pv { A = 4130; }
syscall(60, A & 255);'
fx ev_str 'var A = "x";
enum Pv { A = 4130; }
syscall(60, A & 255);'
fx ev_zero 'var A = 0;
enum Pv { A = 4130; }
syscall(60, A & 255);'
fx ev_zero_zero 'var A = 0;
enum Pv { A = 0; }
syscall(60, A & 255);'
fx ev_enum_enum 'enum Pv { A = 3; }
enum Qv { A = 3; }
syscall(60, A & 255);'
fx ev_literal 'var A = 4098;
enum Pv { A = 4130; }
syscall(60, A & 255);'

# expect <compiler> <fixture> <needle or -> <count>
expect() {
  "$T/$1" < "$T/$2.cyr" > "$T/o" 2>"$T/e"; rc=$?
  if [ "$rc" -ne 0 ]; then _bad "$1 $2: rc $rc (a warning must not fail the build)"; grep '^error' "$T/e" | head -2; return; fi
  n=$(grep -c "$3" "$T/e")
  if [ "$n" -ne "$4" ]; then _bad "$1 $2: $n line(s) matching '$3', expected $4"; grep -v '^note' "$T/e" | head -3 | cut -c1-160 | sed 's/^/      /'; return; fi
  pass=$((pass + 1))
}
LAY='redefined with a different layout'
EOV='is an enum constant here and a global variable before it'
for c in x86 aarch64; do
  expect "$c" sp_derive   "struct 'SP' $LAY" 1
  expect "$c" sp_width    "struct 'SP' $LAY" 1
  expect "$c" sp_kind     "union 'SP' $LAY" 1
  expect "$c" un_field    "union 'U' $LAY" 1
  expect "$c" sp_same     "$LAY" 0
  expect "$c" sp_distinct "$LAY" 0
  expect "$c" ev_call      "duplicate symbol 'A' $EOV" 1
  expect "$c" ev_str       "duplicate symbol 'A' $EOV" 1
  expect "$c" ev_zero      "duplicate symbol 'A' $EOV" 1
  expect "$c" ev_zero_zero "duplicate symbol" 0
  expect "$c" ev_enum_enum "duplicate symbol" 0
  expect "$c" ev_literal   "redefined with conflicting value" 1
  expect "$c" ev_literal   "$EOV" 0
done
# the warning names the redefinition's line (line 5, the second `struct SP`)
"$T/x86" < "$T/sp_derive.cyr" > "$T/o" 2>"$T/e"
if grep -q "^warning:<source>:5:.*struct 'SP' $LAY" "$T/e"; then pass=$((pass + 1)); else _bad "sp_derive: the warning does not point at the second definition"; grep "$LAY" "$T/e" | head -1; fi

if [ "$fail" -ne 0 ]; then echo "FAIL redefinition_layout_and_enum_over_var: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS redefinition_layout_and_enum_over_var: $pass rows — a re-laid-out struct/union and an enum over a zero/computed global are reported on x86 and aarch64, the benign shapes stay silent"
exit 0
