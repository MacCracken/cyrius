# `impl X for T`'s check stops at the first method whose return type differs: a second mismatch, or a required method left out, is not reported in that compile — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 generics lane (D4, 6.7.15's: an impl method's
return type is checked against its trait member's, commit 13fd8844d). Measured on the lane tree after the review fix.
**Placement:** unplaced — filed from the 6.7.15 generics review (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
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
