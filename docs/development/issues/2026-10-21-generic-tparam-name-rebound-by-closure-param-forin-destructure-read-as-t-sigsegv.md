# A generic's T-typed parameter name rebound by a closure parameter, a `for x in` variable or a destructure is still read as T: a bounded `x.show()` on it calls the bound's impl on the word (SIGSEGV at T = Pt), and `x.b` makes the generic a stub — OPEN

**Status:** 🟡 **OPEN** — the consistent fix stops two programs that compile today, beyond D102 (the f16b lane's fix step
taught D102's untyped-local readers the same three rebindings, f6792b43a, and stopped here).
**Placement:** unplaced — filed at the 6.7.16 close (2026-10-21); the user places it — never 7.x.
**Discovered:** the f16b lane — its review's file_as_issue (the `x.b` shape), the bounded crash measured by its fix
step; staged as this file. Identical on the lane's base 4ae0873f3 and the lane head 8e6a65fa0 (x86_64): the lane
neither caused nor touched it. Re-measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`;
`build/cycc` 2,822,280 B).
**Severity:** High — silent wrong code: rc 0, no diagnostic, and the binary crashes on every target.
**Kind:** decision — the consistent fix (the name is the rebinding's own, untyped, as a plain fn reads it) also stops two
programs that compile today: `g(7)` below (exit 105) and a never-called generic reading `x.b` on its closure's own `|x|`.

## Summary

Inside `fn g<T: Show>(x: T)`, a closure literal `|x| { .. }`, a `for x in ..` loop and a destructure `var q, x = ..` each
declare a NEW `x`. The generic scans that type T-valued names (`_gsn`) and record bounded call sites (`_bnd_sites`) are
keyed by name with no scope, so `x.show()` / `x.b` on the new `x` is compiled as if it were g's `x: T`: at T = Pt the
bound's `Pt_show` runs with `self` = the closure's 5, and a scalar T makes the generic a stub. A plain fn refuses the same
body.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Pt { x; y; }
trait Show { fn show(self): i64; }
impl Show for Pt { fn show(self): i64 { return self.x * 10 + self.y; } }
impl Show for i64 { fn show(self): i64 { return self + 100; } }
fn g<T: Show>(x: T): i64 { var f = |x| { return x.show(); }; return fncall1(f, 5); }
fn main(): i64 { var p = Pt { 2, 4 }; return g(p); }
syscall(60, main());
```

rc 0, no diagnostic; the binary exits **139** (SIGSEGV) on x86_64, and crashes on every target (measured at the close:
aarch64 SIGSEGV, cx "guest address out of range: 5", PE an access violation, exit 5): inside the closure `x` is the closure's own untyped
parameter (5), but `x.show()` is compiled as the bounded site of g's `x: T`, so at T = Pt it calls `Pt_show` with
`self = 5` and reads fields at address 5.

The same with a `for x in` variable and with a destructure's later name (each rc 0, exit 139 at T = Pt):

```cyrius
fn g<T: Show>(x: T): i64 { var s = 0; for x in 0..2 { s = s + x.show(); } return s; }
fn two(): (i64, i64) { return (1, 2); }
fn g<T: Show>(x: T): i64 { var q, x = two(); return x.show() + q; }
```

The plain-fn analog is refused, as it should be: `fn h(x: Pt): i64 { var f = |x| { return x.show(); }; .. }` and
`fn h(x: Pt): i64 { var s = 0; for x in 0..2 { s = s + x.show(); } return s; }` give `no struct type in scope for 'x';
a method call needs its struct declaration`.

The unbounded shape (the review's item): `struct Q { a; b; }` /
`fn g<T>(x: T): i64 { var f = |x| { return x.b; }; return fncall1(f, 5); }` / `fn main(): i64 { return 0; }` compiles
(rc 0), though `x` is the closure's untyped parameter in every instance; `g(q)` is refused in the instance
(`4:46: no struct type in scope for 'x'`), and `g(5)` gets "generic 'g' has no i64 (or other scalar) instance" with
`note: <source>:4:43: 'g' takes a field of a value typed by its type parameter` — a field of the closure's parameter,
not of a T value. `for x in 0..3 { s = s + x.b; }` in the same generic compiles never called too.

What runs today and would stop: `fn main(): i64 { return g(7); }` with the first `g` exits **105** on all four targets (the closure's 5
through `impl Show for i64`); a consistent fix refuses it at the definition, as `fn h(x: i64)` refuses the same body.

## The decision

- (a) The rebinding's name is its own, untyped, as a plain fn reads it: each repro is refused at the definition ("no
  struct type in scope for 'x'; a method call needs its struct declaration"), as `fn h(x: Pt)` refuses the same body.
  `g(7)` (exit 105 today) and the never-called generic reading `x.b` on `|x|` stop compiling.
- (b) Keep: the rebinding reads as g's `x: T` (the crash at T = Pt stays).

## Root cause

The bounded-site pre-scan (`_bnd_sites` / `_bnr_decl`, src/frontend/parse_fn.cyr) and the stub scan's T-typed names
(`_gsn`, `_gsn_has`; the carriers `_gcr`) are keyed by NAME with no scope, and `_tok_name_decl` (src/frontend/parse.cyr) counts only
`var NAME` and the fn's own parameters as declarations, so a closure literal's parameter, a `for NAME in` variable and a
destructure's later name never shadow g's `x: T` for them. 6.7.16's f16b review fix (f6792b43a, `_gs_rebound`,
parse_fn_def.cyr) taught D102's untyped-local readers these three rebindings (`var y = x;` under `|x|` is untyped
again, the bounded `y.show()` there refused instead of SIGSEGV); the direct `x.show()` / `x.b` reads go through the
name tables, not through those readers.

## Fix direction

Make the bounded-site record and `_gsn` honour the same rebindings `_gs_rebound` reads (a receiver rebound where it
sits is not the bounded parameter's slot / not T-typed), so each shape is refused at the definition as the plain fn
is. That is the decision: the never-called `x.b` generic and `g(7)` stop compiling.
