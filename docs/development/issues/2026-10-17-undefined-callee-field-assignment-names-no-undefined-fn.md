# `undefd().n += 1;` (a field of an UNDEFINED fn's result) is "expected ';', got '.'", and as a for step "expected '=', got '('" — neither names the undefined fn — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane (unit S1) while landing
issues/archived/2026-10-15-for-step-call-led-field-assignment-refused-with-false-undefined.md (a for step `gp().n += 1` stores
through a `: *T` result since this unit). Pre-existing: the lane's base compiler (f133fb2f) gives the same lines.
x86_64 measured; the frontend's, every target.
**Placement:** 6.7.15 — repair 5 (structs lane; filed from the 6.7.14 structs lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Low — refused code (nothing compiles wrong), but the first error points at the field tail, not at the
undefined name.
**Kind:** diagnostics.

## Repro

```cyrius
include "lib/syscalls.cyr"
struct H { n; m; }
fn go(): i64 { undefd().n += 1; return 0; }
syscall(60, go());
```

```
error:<source>:3:24: expected ';', got '.'
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
```

As a for step:

```cyrius
include "lib/syscalls.cyr"
struct H { n; m; }
fn go(): i64 { var i = 0; for (i = 0; i < 3; undefd().n += 1) { i = i + 1; } return i; }
syscall(60, go());
```

```
error:<source>:3:52: expected '=', got '('
```

Want: the undefined fn named first (`undefined function 'undefd'`, as a bare `undefd();` reports it), once.

## Root cause

`_call_field` (src/frontend/parse_expr.cyr) returns 0 for an unresolvable callee ("an undefined callee reports
itself"): the statement then parses the call with PARSE_FNCALL and stops at the `.` (`expected ';'`), the undefined
fn surfacing only in the end-of-compile refusal; the for step's `_step_call_field` returns 0 too, and the step falls to
`_for_step_assign`, which expects `=` after the name.

## Proposed fix

When the callee is unresolvable and a `.field` chain follows, report `undefined function '<name>'` at the name and step
over the statement (or the step); --syntax-only stays silent (a sibling module's fn).
