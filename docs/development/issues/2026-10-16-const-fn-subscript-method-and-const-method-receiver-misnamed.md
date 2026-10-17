# A subscript or a method call in a const fn, and a method call on a const, name the wrong refusal (and two report twice) — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 frontend lane (unit F2) beside
issues/2026-10-08-const-field-access-diagnostics-misname-refusal.md, which covers the FIELD forms only (a field store /
read in a const fn, a field store / read on a top-level or local const). Measured on the lane tree at 87ef0dd9 (before
F2) and after F2's const-field bite: the four shapes below are unchanged by it.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — every input is refused; the message names the wrong rule, and two shapes print a second, false error.
**Kind:** diagnostics.

## Repro

```cyrius
# cm1 — a method call on a const fn's local
struct P { x; }
impl P { fn m(self) { return 1; } }
const fn f(n) {
    var a = n;
    return a.m();
}
fn main() { return 0; }
var r = main();
```
```
error:<source>:5:13: expected ';', got '.'
error:<source>:5:15: no struct type in scope for 'a'; a method call needs its struct declaration (missing include?)
```

```cyrius
# cm2 — a subscript of a const fn's local
const fn f(n) {
    var a = n;
    return a[0];
}
fn main() { return 0; }
var r = main();
```
```
error:<source>:3:13: expected ';', got '['
error:<source>:3:13: cannot subscript 'a': it is not a typed array, a *T or a slice local - declare `var a: T[N]` or ...
```

```cyrius
# sc2 — a method call on a top-level const
const NAME = "abc";
fn main() {
    return NAME.m();
}
syscall(60, main());
```
```
error:<source>:3:18: no struct type in scope for 'NAME'; a method call needs its struct declaration (missing include?)
```

```cyrius
# sc3 — a method call on a local const
struct P { x; }
fn main() {
    const L = 5;
    return L.m();
}
syscall(60, main());
```
```
error:<source>:4:15: undefined variable 'L'
error:<source>:4:15: no struct type in scope for 'L'; a method call needs its struct declaration (missing include?)
```

Want: one error each, naming the rule — the const fn's pure subset ("Not: memory (`load64`, arrays, `&x`, fields)",
guide § Constants; a method call is a call of a fn that is not a `const fn`), and "a const has no storage" for a const
receiver, as the field forms say since 6.7.14 ("a field is not in a const fn: ...", "const 'C' has no fields - a const
has no storage").

## Root cause

- cm1 / cm2: the const fn checker's frame-local read (`_ce_name`, src/frontend/parse_fn.cyr) returns the local's value
  and leaves `.m(` / `[` to `_ce_expect(S, 5)` ("expected ';'"); 6.7.14 refuses only `.field` there. The run-time
  compile of the same body (a const fn is also an ordinary fn) then reports its own error: the method arm's `sid == 0`
  report in `_field_load_on` (src/frontend/parse_decl.cyr) and `_sub_refuse` (src/frontend/parse_expr.cyr). 6.7.14's
  stand-down for a refused const fn's body (`_ce_fn_refd`) covers only the field arms' `sid == 0` reports.
- sc2 / sc3: the method arm of `_field_load_on` reports `sid == 0` without asking `_cst_named`; for a local const the
  base's undefined-variable arm in PARSE_FIELD_LOAD reports first (6.7.14 asks `_cst_named` there only for a field,
  not when `(` follows).

## Fix sketch

In `_ce_name`, a frame local followed by `.name(` or `[` refused by name ("a method call is not in a const fn: it calls
only const fns" / "a subscript is not in a const fn: its body takes no memory"), the run-time body's method / subscript
report standing down under the same `_ce_fn_refd`; in PARSE_FIELD_LOAD / `_field_load_on`, a const receiver before the
method arm: "const 'C' has no methods - a const has no storage". Diagnostics only: every input is refused before and
after.
