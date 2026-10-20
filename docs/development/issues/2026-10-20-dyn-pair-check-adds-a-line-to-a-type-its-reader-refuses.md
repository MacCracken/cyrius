# An impl method's `: Option<..>` / `: Result<..>` return is a parse error, and the impl check adds "'P.sh' returns Option<i64>, trait 'T2' declares i64" beside it (the residual of: forming a dyn adds "does not match its declaration in trait" to a type its own reader refuses) — OPEN

**Status:** 🟡 **OPEN (residual)** — found 2026-10-20 by the 6.7.16 gensig lane (unit GS1). Every repro below in
*Reproduction*, *Also met by unit GS2* and *Also met by unit GS4* is **resolved in the lane** by its review-fix step
(returns: aff3849ff, `_dyn_ret_hand`; parameters: ca1c163da, `_dsq_rf_of`, and 39a237bb0 for a slice or bare `u128`
parameter; D5's over-long list at the impl check and the site: ca1c163da). Each now gives exactly the reader's one
line: dyn_checked.sh F8r1-F8r6 and F8p1-F8p11, traits_checked.sh TRR3 / TRR4. What stays open is the residual in
*Residual* below. It was measured on the lane head 7f3d2260d and is identical on the lane's base b73e8d5fe.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 gensig lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; f16 lane, wave 4, unit FG3) — never 7.x.
**Severity:** Low. Diagnostics only: the compile already fails on the reader's own error.
**Kind:** bug (diagnostics).

## Reproduction

A return that the impl's reader refuses (`: u8` is not a fn return type). The member has no return type:

```cyrius
struct P { a; b; }
trait T2 { fn sh(self); }
fn f(q: *P): i64 { var o: dyn T2 = q; return 0; }
impl T2 for P { fn sh(self): u8 { return 1; } }
fn main(): i64 { return 0; }
```

```
error:<source>:3:36: cannot form dyn T2 from P - its method 'sh' does not match its declaration in trait T2: the return type differs (no return type is i64)
error:<source>:4:30: type 'u8' cannot be a fn return type
```

Without the `fn f` line there is one error: `4:30: type 'u8' cannot be a fn return type` (traits_checked.sh TR8b's
rule, "a side its own reader refuses reports alone").

A member return that the trait's reader refuses (`Nope` names nothing):

```cyrius
struct P { a; b; }
trait T2 { fn sh(self): Nope; }
fn f(q: *P): i64 { var o: dyn T2 = q; return 0; }
impl T2 for P { fn sh(self) { return 1; } }
fn main(): i64 { return 0; }
```

```
error:<source>:2:25: unknown type 'Nope' as a fn return type
error:<source>:3:36: cannot form dyn T2 from P - its method 'sh' does not match its declaration in trait T2: the return type differs (no return type is i64)
```

A parameter type that the impl's reader refuses:

```cyrius
struct P { a; b; }
trait T2 { fn sh(self, n): i64; }
fn f(q: *P): i64 { var o: dyn T2 = q; return 0; }
impl T2 for P { fn sh(self, n: Nope): i64 { return 1; } }
fn main(): i64 { return 0; }
```

```
error:<source>:3:36: cannot form dyn T2 from P - its method 'sh' does not match its declaration in trait T2: parameter 'n' has another type (an untyped parameter is i64)
error:<source>:4:32: unknown type 'Nope' for parameter 'n'
```

## Root cause

`_dyn_pair_chk` (src/frontend/parse_types.cyr) passes code 4 (the return type) to the impl's own check only when
`_tr_ret_differs` (src/frontend/parse_fn.cyr) answers 1. `_tr_ret_differs` answers 0 in two cases: when the returns
agree, and when either side is one its own reader refuses (`_tr_rt_bad`). In the second case the site still reports
its F8 line next to the reader's refusal. Parameters (code 3) have no hand-off at all, so a parameter type that its
reader refuses also "has another type" at the site. 6.7.15's D4 rule, "a side whose return its own reader refuses is
that refusal alone", holds for the impl's check but not for forming a dyn.

## Fix direction

In `_dyn_pair_chk`, add nothing for a code-4 return where a side is `_tr_rt_bad`. Do the same for a code-3 parameter
whose type is refused by its reader: the trait's member reader (`_tr_sig_check`) or PARSE_FN_DEF's parameter reader.
Rows for dyn_checked.sh: the three programs above, each with exactly one error line (the reader's). One question
needs checking first: under `--syntax-only` no type name is resolved, so the reader's refusal does not fire. The site
must then still say something, or nothing, consistently.

## Also met by unit GS2 (2026-10-20): the member returns 6.7.16's D9 refuses join repro 2's class

Since GS2's D9 bite (issues/2026-10-18-trait-member-return-outside-fn-return-set-accepted.md), a member's `: u8`..`: u64`,
`: f32`, enum or `*fn( .. )` return is refused by the trait's reader, so it is `_tr_rt_bad` and `_tr_ret_differs`
answers 0 for it: the impl's "returns .., trait declares .." line is gone (traits_checked.sh TM5), and forming a dyn
adds its F8 line beside the member's refusal, as repro 2 does for `: Nope`:

```cyrius
struct P { a; b; }
trait T2 { fn sh(self): u8; }
fn f(q: *P): i64 { var o: dyn T2 = q; return 0; }
impl T2 for P { fn sh(self) { return 1; } }
fn main(): i64 { return 0; }
```

```
error:<source>:2:25: type 'u8' cannot be a fn return type
error:<source>:3:36: cannot form dyn T2 from P - its method 'sh' does not match its declaration in trait T2: the return type differs (no return type is i64)
```

(GS2's previous compiler, d4a59f3e4, printed one line, the impl's `4:20: 'P.sh' returns i64, trait 'T2' declares u8`.)
The fix direction above covers it unchanged; add this program as a fourth row.

## Also met by unit GS4 (2026-10-20): the member types 6.7.16's D7 refuses join the class

Since GS4's D7 bite (issues/2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md), a trait member's
`Pt<i64>` / `*Pt<i64>` (a non-generic struct, or a scalar, given type arguments) is refused by the trait's reader. The
impl check counts it as a reader-refused return (`_tr_rt_bad` reads `_ngt_tail`), so its "returns .., trait declares .."
line is gone, but forming a dyn adds its F8 line beside the member's refusal, for a return and for a parameter:

```cyrius
struct Pt { x; y; }
struct P { a; b; }
trait T2 { fn sh(self): *Pt<i64>; }
fn f(q: *P): i64 { var o: dyn T2 = q; return 0; }
impl T2 for P { fn sh(self): *Pt { return 0; } }
fn main(): i64 { return 0; }
```

```
error:<source>:3:26: 'Pt' is not a generic struct: it takes no type arguments
error:<source>:4:36: cannot form dyn T2 from P - its method 'sh' does not match its declaration in trait T2: the return type differs
```

```cyrius
struct Pt { x; y; }
struct P { a; b; }
trait T2 { fn sh(self, p: *Pt<i64>): i64; }
fn f(q: *P): i64 { var o: dyn T2 = q; return 0; }
impl T2 for P { fn sh(self, p: *Pt): i64 { return 1; } }
fn main(): i64 { return 0; }
```

```
error:<source>:3:28: 'Pt' is not a generic struct: it takes no type arguments
error:<source>:4:36: cannot form dyn T2 from P - its method 'sh' does not match its declaration in trait T2: parameter 'p' has another type
```

(GS4's previous compiler, b56d6abb7, printed one line each: the impl's `5:30: 'P.sh' returns *Pt, trait 'T2' declares
*Pt<i64>` for the first, the dyn's F8 line alone for the second.) The fix direction above covers both; add them as rows.

## Residual (open) — an impl method's return its reader refuses with a parse error

A fn definition's return reader does not take a `<..>` after `Result` / `Option` / `Tagged`: `fn g(): Option<i64>` is
"expected '{', got '<'" (see staged 2026-10-20-enum-and-handle-type-arguments-unread.md for the class). An impl
method written so is that parse error, and the impl's return check (6.7.15's D4) adds its own line beside it:

```cyrius
struct P { a; b; }
trait T2 { fn sh(self): i64; }
impl T2 for P { fn sh(self): Option<i64> { return 0; } }
fn main(): i64 { return 0; }
```

```
error:<source>:3:30: 'P.sh' returns Option<i64>, trait 'T2' declares i64
error:<source>:3:36: expected '{', got '<'
error:<source>:3:42: undefined variable 'i64'
```

The same happens with `: Result<Pt<i64>>` (`4:30: 'P.sh' returns Result<Pt<i64>>, trait 'T2' declares i64` before
`4:36: expected '{', got '<'`). Forming a dyn adds nothing here, because the impl check owns the difference.
`_tr_rt_bad` does not count the method side's `Name<..>` after a name whose list a fn's return reader cannot read.
The fix is a method-side arm in `_tr_rt_bad` / `_tr_rt_rd`: a head name followed by `<` that is not a generic struct
counts as the reader's refusal on the method side only, because a member's `: Option<i64>` is accepted. The parse
cascade (`undefined variable 'i64'`) is the fn reader's own and belongs with the class issue.
