#!/bin/sh
# call_site_callee_spelling.sh — 6.7.14: a call-site diagnostic names its callee as the source spells it. The fn
# table holds a method as its mangled `T_m` (`T_Tr_m` when two traits give T an `m`) and a generic call as its
# instance `g$i32`, and the call-site messages printed that: "in a call to 'S_ri'" (D27, 6.7.12), "different vector
# type in a call to 'S_rd'" (A2, 6.7.11), the struct-type refusal, "'S_two' expects 2 arguments, got 3", "'S_ta' has
# no parameter named 'z'", "undefined function 'S_nope'", "#pure fn calls #io fn 'A_m'", "'g$i32' is deprecated".
# `_fn_src_name` (parse_fn.cyr) gives every such message `S.ri` / `g<i32>` (a method from its record, GFMETH: pass 1
# records an impl's definitions, the method arm a name a call registered; an instance its base and `<..>` from its
# type arguments, GFIC). A method form's arity message counts the arguments as written, without `self`
# (`_check_arity_p0`). Diagnostics only: no binary changes (issues/archived/2026-10-15-call-diagnostics-name-method-by-mangled-name.md).
#
#   N1   the filed repro verbatim: "... in a call to 'S.ri' - pass &b for its address", once
#   N2   the issue's class, each by a method: A2 `s.rd(f)`, the struct type `s.ta(b)`, `s.two(1, 2)` ("expects 1
#        argument, got 2"), `s.two()` ("got 0"), `s.ta(a: 1, z: 2)`, `s.nope(1)` (both undefined lines)
#   N3   a trait method mangled with its trait (`T_A1_m`) is `T.m`; the free spelling `S_two(&s, 1, 2)` is `S.two`,
#        its count as written ("expects 2 arguments, got 3"); a method declaring no parameter keeps the receiver in
#        its count (`g.zero()`: "expects 0 arguments, got 1")
#   N4   a generic instance: `g<i32>`'s struct-type refusal, arity and named argument; two type arguments
#        `g2<i32, i64>`; a struct instance argument `gx<Box<i64>>`; a generic method `P.id`
#   N5   the other call-site messages: #pure (`A.m`), #deprecated (`S.old`, `g<i32>`), #must_use (`S.mu`), a
#        destructure (`S.one` returns 1 value), a bool parameter (`W.b`, `g<i32>`), a cstring parameter (`W.pr`)
#   N6   `g<f64v2>(b)` (a refused type argument): no line names the minted `g$..`; a call line, if any, `g<f64v2>`
#   N7   controls, unchanged: a plain fn, a free fn named like a method (`S_x`, no impl), a `mod` fn (`mm_f`)
#   N8   the aarch64 cross compiler (built from this tree, when present) names `S.ri` and `S.nope` too
#
# MUTATIONS (measured, 6.7.14, the mutant as CYCC; N8 uses the tree's aarch64 compiler): `_fn_src_name` returning
# `noff` at its top -> 19 rows RED, N1-N6 (the mangled names); `_prescan_meth_note` never called -> 12 RED, N1, N2a-d
# (not `s.nope`), N3, N4d, N5 (the defined methods); `_owncall_args_at` passing 0 for p0 to `_check_arity_p0` -> N2c,
# N4d RED.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: call_site_callee_spelling: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: call_site_callee_spelling: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: call_site_callee_spelling: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fail=0; rows=0
bad() { echo "  FAIL: call_site_callee_spelling $1"; fail=$((fail + 1)); }

# diag ID WANT [CC] — the source on stdin is refused or warned; its diagnostic lines (`error:` / `warning:`, with
# `<source>:` dropped, joined by '|') are exactly WANT.
diag() {
  rows=$((rows + 1))
  _cc=${3:-$CC}
  cat > "$D/$1.cyr"
  "$_cc" < "$D/$1.cyr" > "$D/$1" 2> "$D/$1.err" || true
  got=$(grep -E '^(error|warning)' "$D/$1.err" | sed 's/<source>://' | tr '\n' '|')
  [ "$got" = "$2" ] || bad "$1: got {$got}, want {$2}"
}

diag N1 "error:8:17: cannot pass 'b' to a parameter that is not a pointer to its vector type in a call to 'S.ri' - pass &b for its address|" <<'EOF'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct S { k; }
impl S { fn ri(self, p: *i64): i64 { return *p; } }
fn main(): i64 {
    var s: S; s.k = 1;
    var b: f64v2 = f64v2_make(42, 7);
    return s.ri(b);
}
var rc = main();
syscall(60, rc);
EOF
diag N2a "error:8:17: cannot pass 'f' to a parameter of a different vector type in a call to 'S.rd'|" <<'EOF'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct S { k; }
impl S { fn rd(self, p: *f64v2): i64 { return 0; } }
fn main(): i64 {
    var s: S; s.k = 1;
    var f: f32v4;
    return s.rd(f);
}
syscall(60, main());
EOF
diag N2b "error:9:17: cannot pass 'b' to a parameter of a different struct type in a call to 'S.ta'|" <<'EOF'
struct A { x; }
struct B { y; }
struct S { k; }
impl S { fn ta(self, p: *A): i64 { return 0; } }
fn main(): i64 {
    var s: S; s.k = 1;
    var a: A; a.x = 1;
    var b: B; b.y = 2;
    return s.ta(b);
}
syscall(60, main());
EOF
diag N2c "error:3: 'S.two' expects 1 argument, got 2|error:4: 'S.two' expects 1 argument, got 0|" <<'EOF'
struct S { k; }
impl S { fn two(self, a): i64 { return a; } }
fn main(): i64 { var s: S; s.k = 1; return s.two(1, 2)
    + s.two(); }
syscall(60, main());
EOF
diag N2d "error:3:55: 'S.ta' has no parameter named 'z' - its parameters are: a|" <<'EOF'
struct S { k; }
impl S { fn ta(self, a): i64 { return a; } }
fn main(): i64 { var s: S; s.k = 1; return s.ta(a: 1, z: 2); }
syscall(60, main());
EOF
diag N2e "warning: undefined function 'S.nope'|warning: undefined function 'S.nope' (reachable call site)|error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)|" <<'EOF'
struct S { k; }
impl S { fn ta(self, a): i64 { return a; } }
fn main(): i64 { var s: S; s.k = 1; return s.nope(1); }
syscall(60, main());
EOF
diag N3a "error:6: 'T.m' expects 2 arguments, got 3|" <<'EOF'
trait A1 { fn m(self, x): i64; }
trait B1 { fn m(self, x): i64; }
struct T { v; }
impl A1 for T { fn m(self, x): i64 { return 1; } }
impl B1 for T { fn m(self, x): i64 { return 2; } }
fn main(): i64 { var t: T; t.v = 1; return T_A1_m(&t, 1, 2); }
syscall(60, main());
EOF
diag N3b "error:3: 'S.two' expects 2 arguments, got 3|error:4: 'MG.zero' expects 0 arguments, got 1|" <<'EOF'
struct S { k; }
impl S { fn two(self, a): i64 { return a; } } struct MG { a; } impl MG { fn zero(): i64 { return 7; } }
fn main(): i64 { var s: S; s.k = 1; var g: MG; g.a = 0; return S_two(&s, 1, 2)
    + g.zero(); }
syscall(60, main());
EOF
diag N4a "error:4:55: cannot pass 'b' to a parameter of a different struct type in a call to 'g<i32>'|" <<'EOF'
struct A { x; }
struct B { y; }
fn g<T>(x: T, p: *A): i64 { return 0; }
fn main(): i64 { var b: B; b.y = 1; var r = g<i32>(1, b); return r; }
syscall(60, main());
EOF
diag N4a2 "error:4: 'g<i32>' expects 2 arguments, got 3|" <<'EOF'
struct A { x; }
fn g<T>(x: T, p: *A): i64 { return 0; }
fn main(): i64 {
    return g<i32>(1, 2, 3); }
syscall(60, main());
EOF
diag N4a3 "error:4:22: 'g<i32>' has no parameter named 'z' - its parameters are: x, p|" <<'EOF'
struct A { x; }
fn g<T>(x: T, p: *A): i64 { return 0; }
fn main(): i64 {
    return g<i32>(1, z: 2); }
syscall(60, main());
EOF
diag N4b "error:6:99: cannot pass 'q' to a parameter of a different struct type in a call to 'g2<i32, i64>'|" <<'EOF'
struct Pt { x; }
struct Q { y; }
struct Box<T> { v: T; }
fn g2<A, B>(a: A, b: B, p: *Pt): i64 { return 0; }
fn gx<T>(b: *T, p: *Pt): i64 { return 0; }
fn main(): i64 { var q: Q; q.y = 1; var bx: Box<i64> = Box<i64> { 1 }; var r = g2<i32, i64>(1, 2, q); return r; }
syscall(60, main());
EOF
diag N4c "error:5:97: cannot pass 'q' to a parameter of a different struct type in a call to 'gx<Box<i64>>'|" <<'EOF'
struct Pt { x; }
struct Q { y; }
struct Box<T> { v: T; }
fn gx<T>(b: *T, p: *Pt): i64 { return 0; }
fn main(): i64 { var q: Q; q.y = 1; var bx: Box<i64> = Box<i64> { 1 }; return gx<Box<i64>>(&bx, q); }
syscall(60, main());
EOF
diag N4d "error:3: 'P.id' expects 1 argument, got 2|" <<'EOF'
struct P { k; }
impl P { fn id<T>(self, x: T): T { return x; } }
fn main(): i64 { var p: P; p.k = 1; return p.id(1, 2); }
syscall(60, main());
EOF
diag N5a "warning:3:33: #pure fn calls #io fn 'A.m'|" <<'EOF'
struct A { v; }
#pure
fn h(p: *A): i64 { return p.m() + 0; }
impl A {
    #io
    fn m(self): i64 { return 1; }
}
fn main(): i64 { var a: A; a.v = 0; return h(&a); }
syscall(60, main());
EOF
diag N5b "warning:10:43: #must_use result of 'S.mu' is discarded|warning:10:54: 'S.old' is deprecated: use other|warning:10:69: 'g<i32>' is deprecated: use g2|" <<'EOF'
struct S { k; }
impl S {
    #deprecated("use other")
    fn old(self): i64 { return 1; }
    #must_use
    fn mu(self): i64 { return 2; }
}
#deprecated("use g2")
fn g<T>(x: T): i64 { return 1; }
fn main(): i64 { var s: S; s.k = 1; s.mu(); return s.old() + g<i32>(1); }
syscall(60, main());
EOF
diag N5c "error:4:81: multi-value destructure binds 3 names, but 'W.one' returns 1 value - bind it to one name: \`var x = f(..);\`|" <<'EOF'
struct W { k; }
impl W { fn one(self): i64 { return 1; } }
fn g<T>(x: T): T { return x; }
fn main(): i64 { var w: W; w.k = 1; var a = 1; var d = g<i32>(1); var p, q, r = w.one(); return a + d; }
syscall(60, main());
EOF
diag N5d "error:4:41: cannot pass a value that is not a bool to bool parameter 'x' of 'W.b'|error:4:55: cannot pass a value that is not a bool to bool parameter 'y' of 'g<i32>'|error:4:64: passing integer literal 42 to 'W.pr' which expects a cstring (a POINTER, not a number)|" <<'EOF'
struct W { k; }
impl W { fn b(self, x: bool): i64 { return 0; } fn pr(self, p: cstring): i64 { return 0; } }
fn g<T>(x: T, y: bool): i64 { return 0; }
fn main(): i64 { var w: W; w.k = 1; w.b(5); g<i32>(1, 5); w.pr(42); return 0; }
syscall(60, main());
EOF
rows=$((rows + 1))
cat > "$D/N6.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn g<T>(p: *T): i64 { return 0; }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    return g<f64v2>(b);
}
syscall(60, main());
EOF
"$CC" < "$D/N6.cyr" > "$D/N6" 2> "$D/N6.err" || true
grep -q '^error.*generic type-args must be a scalar' "$D/N6.err" || bad "N6: the type argument's own refusal is missing: $(head -1 "$D/N6.err")"
grep -q "'g\\$" "$D/N6.err" && bad "N6: a line names the minted instance: $(grep "'g\\$" "$D/N6.err" | head -1)"
if grep -q 'in a call to' "$D/N6.err"; then grep -q "in a call to 'g<f64v2>'" "$D/N6.err" || bad "N6: the call line does not name g<f64v2>: $(grep 'in a call to' "$D/N6.err" | head -1)"; fi
diag N7 "error:5: 'S_x' expects 1 argument, got 2|error:5: 'mm_f' expects 1 argument, got 2|error:5: 'pl' expects 1 argument, got 2|" <<'EOF'
struct S { k; }
fn S_x(a): i64 { return a; }
fn pl(a): i64 { return a; }
mod mm; fn f(a): i64 { return a; }
var r = S_x(1, 2) + mm_f(1, 2) + pl(1, 2);
syscall(60, r);
EOF
A64="$ROOT/build/cycc_aarch64"
if [ -x "$A64" ]; then
  diag N8a "error:8:17: cannot pass 'b' to a parameter that is not a pointer to its vector type in a call to 'S.ri' - pass &b for its address|" "$A64" < "$D/N1.cyr"
  diag N8b "warning: undefined function 'S.nope'|warning: undefined function 'S.nope' (reachable call site)|error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)|" "$A64" < "$D/N2e.cyr"
else
  echo "  NOTE: call_site_callee_spelling N8 not run — no build/cycc_aarch64 (build it from src/main_aarch64.cyr)"
fi

[ "$rows" -ge 22 ] || bad "only $rows rows ran"
if [ "$fail" -ne 0 ]; then echo "FAIL call_site_callee_spelling: $fail of $rows row(s) red"; exit 1; fi
echo "PASS call_site_callee_spelling: $rows rows — call-site diagnostics name a method \`S.ri\` and a generic call \`g<i32>\`; a method form's arity counts as written"
exit 0
