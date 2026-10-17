# A top-level `mk().n = 5;` (a struct returned by value) is reported twice: the no-frame refusal and "the result is a temporary" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-15 by the 6.7.13 structs lane (unit S4) while writing D8 (a)'s refusal rows
(issues/archived/2026-10-08-field-store-through-pointer-returning-call-refused.md; the by-value result keeps its refusal). The
same before and after that bite (x86_64; the frontend's, every target).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — refused code, one statement reported twice.
**Kind:** diagnostics.

## Repro

```cyrius
include "lib/syscalls.cyr"
struct H { n; m; }
fn mk(): H { var h: H; h.n = 1; return h; }
mk().n = 5;
syscall(60, 0);
```

`build/cycc`:

```
error:<source>:4:3: 'mk' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn
error:<source>:4:8: cannot assign to a field of a call result: the result is a temporary
```

Want one error (either names the statement's real problem). In a fn the same statement gives only the second.

## Root cause

`_stmt_call_field` (src/frontend/parse_expr.cyr) runs `_call_field`, whose top-level arm reports
`_refuse_toplevel_struct_call` without latching `_panic` and returns 1 with the cursor on `=`; the statement form then
sees the assignment and reports `_asg_temp_refused` as well.

## Proposed fix

In `_stmt_call_field`, skip `_asg_temp_refused` when `_call_field` refused the call itself (at top level, a by-value
result) — the statement is stepped over to its `;` either way.
