# `impl X for T`'s check stops at the first method whose return type differs: a second mismatch, or a required method left out, is not reported in that compile — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GS-1, `1d0af4e55` — no decision needed (diagnostics only: the program was already refused). `_tr_check_impl` no longer returns after a return refusal (`_tr_ret_err` consumes nothing and sets no panic latch); the ERR_IDENT arms keep their early return, and one report per method stays. The filed program, verbatim, now reports its three errors in one compile — `3:28: 'P.a' returns i64, trait 'T' declares f64`, `3:58: 'P.b' returns i64, trait 'T' declares f64` (the filing's "3:60" was a column slip) and `3:16: impl is missing method 'c', required by trait 'T'` — on x86_64, aarch64, cx and PE; it printed the first line alone. Rows: `traits_checked.sh` TRC1 (the filed program verbatim: exactly three lines, in order), TRC2 (a parameter-count mismatch after a return refusal: two lines), TRC3 (an undeclared method after a return refusal: two lines); TR1 – TR8b and TRS1 – TRS7 unchanged. Mutant: the lane's base compiler → RED 3 (TRC1 – TRC3). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 generics lane (D4, 6.7.15's: an impl method's
return type is checked against its trait member's, commit 13fd8844d). Measured on the lane tree after the review fix.
**Placement:** 6.7.16 — Break 2, repair 6 (gensig lane, wave 2, unit GS1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — diagnostics only: the compile already fails, and the next compile reports the next problem.
**Kind:** bug (diagnostics).

## Reproduction

```cyrius
struct P { x; }
trait T { fn a(self): f64; fn b(self): f64; fn c(self): i64; }
impl T for P { fn a(self): i64 { return 1; } fn b(self): i64 { return 2; } }
fn main(): i64 { return 0; }
```

```
$ build/cycc < ti.cyr > b; echo $?
error:<source>:3:28: 'P.a' returns i64, trait 'T' declares f64
1
```

`'P.b' returns i64, trait 'T' declares f64` (3:60) and `impl is missing method 'c', required by trait 'T'` are not
reported; each appears alone once the line before it is fixed.

## Root cause

`_tr_check_impl` (src/frontend/parse_fn.cyr) returns as soon as `_tr_ret_chk` refuses a method
(`if (_tr_ret_chk(S, ii, tk, k) == 1) { return 0; }`), as its older arms do after `ERR_IDENT`. Those arms must stop:
`ERR_IDENT` sets the panic latch, which would swallow what follows. `_tr_ret_err` does not set the latch (it consumes
nothing), so the walk could go on to the remaining methods and the missing-method loop.

## Fix direction

In `_tr_check_impl`, let a return refusal continue the method loop and the missing-method loop (still one report per
method); keep the early return on the `ERR_IDENT` arms. A traits_checked.sh row: the program above reports exactly
three lines (`P.a`, `P.b`, the missing `c`).
