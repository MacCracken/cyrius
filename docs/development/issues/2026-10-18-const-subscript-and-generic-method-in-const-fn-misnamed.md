# A subscript of a const, and an explicit generic method call `a.m<T>(..)` in a const fn, name the wrong rule (one with a false "undefined variable") — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 frontend lane (unit F3) beside
issues/2026-10-16-const-fn-subscript-method-and-const-method-receiver-misnamed.md, whose filed surface is a method call
`.m(` and a subscript on a const fn's LOCAL, and a method call on a const. F3 refuses those by name (a subscript on any
const fn frame entry — local, parameter or body const — is "a subscript is not in a const fn"). The shapes below are
outside that surface and unchanged by it. Measured on the lane tree after F3's first two commits (b02930ac0 + the
latch fix); the same refusals print on the lane's compiler before F3 (e5a003c6f), q3's and r3's false errors
included. (A const fn's own body const subscripted, `const k = 3; return k[0];`, printed "expected ';', got '['" and
a false "undefined variable 'k'" there; F3 refuses it once, as a subscript in a const fn.)
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 frontend lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — every input is refused; the message names the wrong rule, and two shapes print a FALSE error.
**Kind:** diagnostics.

## Repro

```cyrius
# q1 — a top-level const subscripted in a const fn
const C = 5;
const fn f(n) {
    return C[0];
}
fn main() { return 0; }
var r = main();
```
```
error:<source>:3:13: expected ';', got '['
```

```cyrius
# q2 — a top-level const subscripted in an ordinary fn
const C = 5;
fn main(): i64 { return C[0]; }
syscall(60, main());
```
```
error:<source>:2:26: cannot subscript 'C': it is not a typed array, a *T or a slice local - declare `var a: T[N]` or `p: *T` (T an integer, f64, f32 or bool), or load / store at an explicit byte offset
```

```cyrius
# q3 — a local const subscripted
fn main(): i64 { const L = 5; return L[0]; }
syscall(60, main());
```
```
error:<source>:1:39: undefined variable 'L' (missing include or enum?)      <- false: L is declared
```

```cyrius
# q4 — a const subscripted in a const context
const C = 5;
const K = C[0];
syscall(60, K);
```
```
error:<source>:2:12: expected ';' after a const's value
```

```cyrius
# r3 — an explicit generic method call on a const fn's local
const fn f(n) {
    var a = n;
    return a.m<i64>(1);
}
fn main() { return 0; }
var r = main();
```
```
error:<source>:3:13: a field is not in a const fn: its body takes no memory (fields, arrays, load64, &x)
error:<source>:3:19: undefined variable 'i64' (missing include or enum?)      <- false
```

Want: one error each, naming the rule — "a const has no storage" for a const subscripted (as 6.7.14's "const 'C' has
no fields - a const has no storage" and 6.7.15's "const 'C' has no methods"; the wording of a subscript form is to be
chosen), "a method call is not in a const fn" for r3, and no false "undefined variable".

## Root cause

- q1 / q4: the evaluator's top-level-const read (`_ce_name`'s `_cst_find` arm, src/frontend/parse_fn.cyr) asks
  `_ce_fld_refused` for `.field` / `.m(` only; a `[` is left to `_ce_expect` ("expected ';'" / the const's end rule).
  F3's `_ce_sub_refused` is asked in the frame arm only (a const fn's own locals and body consts).
- q2 / q3: the run-time subscript (`_arr_sub_addr`, src/frontend/parse_expr.cyr) resolves a top-level const to its
  size-0 slot (k 3, no element: `_sub_refuse`'s generic text) and does not see a local const at all (no slot: the
  k == 0 "undefined variable" arm). Neither asks `_cst_named`.
- r3: `_ce_fld_refused` keys a method call on `(` right after the name (`TOKTYP(_ce_ti + 2) == 10`); the explicit
  `<..>` form is read as a field, and the run-time compile of the body then reads `<i64>` as a comparison
  (`a.m < i64 > (1)`), whose `i64` is an undefined variable.

## Fix sketch

A `[` after a const in `_ce_name` (the `_lc_find` and `_cst_find` arms) and in `_arr_sub_addr` before its k 0 / k 3
refusals, refused by name as the field / method forms are (`_cst_fld_at`-style, in sync where the brackets can be
stepped); `_ce_fld_refused` taking `.m<..>(` as a method call (the `_mx_take` / `<..>` skip the method arm uses).
Diagnostics only: every input is refused before and after.
