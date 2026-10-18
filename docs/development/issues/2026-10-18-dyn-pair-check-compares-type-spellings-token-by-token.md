# Forming a dyn compares a method's types token by token: `Box<i64>` against `Box`, and `Box<Box<i64>>` against `Box<Box<i64> >`, are "the return type differs" / "parameter has another type" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 generics lane (D4, the impl-return check). The
lane's review fix (`_ty_norm_eq`, src/frontend/parse_types.cyr) made the IMPL's return check read both spellings as an
annotation is read; the dyn pair check (`_dyn_sig_eq`) still compares tokens, as it has since 6.7.8. Measured on the
lane tree (l6715-generics after the review fix) and on the slot-open compiler b2e1f4c48: identical output.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 generics review, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — a valid program is refused at compile time (nothing miscompiles): an impl whose method spells a
type differently from its trait member cannot be formed into a dyn, though the impl itself is accepted and its
direct calls run.
**Kind:** bug (the guide's dyn paragraph says the pair check compares "each parameter after `self` and the return by
its resolved type").

## Reproduction

Each program compiles and exits 4 with its `fn f` line removed (the impl is accepted; the method runs). With the
line, forming the dyn is refused:

```cyrius
struct Box<T> { n: i64; v: T; }
struct Pt { x: i64; y: i64; }
trait T { fn c(self): Box<i64>; }
impl T for Pt { fn c(self): Box { var b: Box; b.n = 4; return b; } }
fn f(q: *Pt): i64 { var o: dyn T = q; return 0; }
fn main(): i64 { var p: Pt; var r: Box = p.c(); return r.n; }
```

```
error:<source>:5:36: cannot form dyn T from Pt - its method 'c' does not match its declaration in trait T: the return type differs (no return type is i64)
```

```cyrius
struct Box<T> { n: i64; v: T; }
struct Pt { x: i64; y: i64; }
trait T { fn c(self): Box<Box<i64>>; }
impl T for Pt { fn c(self): Box<Box<i64> > { var b: Box<Box<i64> >; b.n = 4; return b; } }
fn f(q: *Pt): i64 { var o: dyn T = q; return 0; }
fn main(): i64 { var p: Pt; var r: Box<Box<i64> > = p.c(); return r.n; }
```

```
error:<source>:5:36: cannot form dyn T from Pt - its method 'c' does not match its declaration in trait T: the return type differs (no return type is i64)
```

A parameter's type the same way:

```cyrius
struct Box<T> { n: i64; v: T; }
struct Pt { x: i64; y: i64; }
trait T { fn m(self, b: *Box<i64>): i64; }
impl T for Pt { fn m(self, b: *Box): i64 { return b.n; } }
fn f(q: *Pt): i64 { var o: dyn T = q; return 0; }
fn main(): i64 { var p: Pt; var b: Box; b.n = 4; return p.m(&b); }
```

```
error:<source>:5:36: cannot form dyn T from Pt - its method 'm' does not match its declaration in trait T: parameter 'b' has another type (an untyped parameter is i64)
```

Also seen: the parenthesised hint ("(no return type is i64)", "(an untyped parameter is i64)") is printed though
both sides are annotated.

## Root cause

`_dyn_sig_eq` (src/frontend/parse_types.cyr) compares each parameter's and the return's tokens through `_dyn_ty_eq`,
which requires the same token count and kinds: a `>>` (one token, 39) against `> >` (two, 20) differs, and a generic
struct's all-`i64` list (`Box<i64>`, the base `Box` by 6.6.10's annotation rule) against the bare name differs.
`_dyn_pair_chk` hands a return mismatch to the impl's own check (`_tr_ret_differs`) only when that check refuses it;
since the review fix the impl check says "the same type", so the dyn site reports it.

## Fix direction

Compare through `_ty_norm_eq` (the impl check's normalising comparator, beside `_dyn_ty_eq`) in `_dyn_sig_eq`'s
parameter and return comparisons, or make `_dyn_ty_eq` normalise. Rows in dyn_checked.sh: the three programs above
form their dyn and exit 4; `Box<i32>` against `Box<i64>` stays refused. Print the hint only when a side is unannotated.
