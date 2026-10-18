# `--syntax-only`: `gp().n = 5;` with `gp` in a sibling module is a false "the result is a temporary" (a for step too) — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane (unit S1) while landing
issues/archived/2026-10-15-for-step-call-led-field-assignment-refused-with-false-undefined.md. Pre-existing for the statement
(the lane's base compiler f133fb2f gives the same line); since this unit the for step `gp().n += 1` mirrors the
statement (it was a false "expected '=', got '('" before — false either way). x86_64 measured; the frontend's, every
target.
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S6; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — `--syntax-only` (the LSP / `cyrius check` path) reports an error on valid code whose callee is
declared in another file; a full build of the project compiles it (6.7.13's D8 (a)).
**Kind:** diagnostics (--syntax-only).

## Repro

```cyrius
struct H { n; m; }
fn go(): i64 { gp().n = 5; var i = 0; for (i = 0; i < 3; gp().n += 1) { i = i + 1; } return 0; }
```

`build/cycc --syntax-only < r.cyr` (`gp`, `fn gp(): *H`, lives in a sibling module):

```
error:<source>:2:23: cannot assign to a field of a call result: the result is a temporary
error:<source>:2:65: cannot assign to a field of a call result: the result is a temporary
warning: undefined function 'gp'
```

Want: nothing reported (the callee's return type is unknown in this file, as for every other `--syntax-only` read
of a sibling's call), rc 0 apart from the undefined-function warning.

## Root cause

`_call_field` (src/frontend/parse_expr.cyr), under `--syntax-only` with an unresolvable callee (`fi < 0`), takes the
refusal branch silently ("a return type from a sibling file reads as a scalar") and returns 1 with the cursor on the
`=`; `_stmt_call_field` (and since 6.7.14 the step twin `_step_cf_tail`) then sees an assignment to a call result's
field and reports `_asg_temp_refused`, which is only right when the callee is KNOWN to return a struct by value.

## Proposed fix

Under `--syntax-only`, when the callee did not resolve, parse the assignment's tail silently (`_synonly_fld_tail`, as
PARSE_FIELD_STORE does for an unknown struct) instead of `_asg_temp_refused`, in the statement and the step.
