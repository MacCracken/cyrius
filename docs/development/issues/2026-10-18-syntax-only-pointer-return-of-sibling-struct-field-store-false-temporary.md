# `--syntax-only`: `gp().n = 5;` with `fn gp(): *Foo` defined HERE and `Foo` a sibling module's struct is a false "the result is a temporary" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S6) beside
issues/2026-10-17-syntax-only-sibling-ptr-call-field-store-false-temporary.md, whose fix covers a callee this file does
not define (a sibling's fn). Here the fn is defined in this file and only its return type's struct is a sibling's.
Pre-existing (the lane head gives the same); x86_64 measured, the frontend's.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — `cyrius lint` (`--syntax-only`) reports an error on valid code whose struct is declared in another
file; a full build of the project compiles it (6.7.13's D8 (a): a `: *T` result's field is an lvalue).
**Kind:** diagnostics (--syntax-only).

## Repro

```cyrius
fn gp(): *Foo { return 0; }
fn go(): i64 { gp().n = 5; return 0; }
```

(`struct Foo { n; }` lives in a sibling module.) `cycc --syntax-only < r.cyr`:

```
error:<source>:2:23: cannot assign to a field of a call result: the result is a temporary
```

rc 1. Want: accepted (the store's tail parsed silently), as `var p: *Foo = gp(); p.n = 5;` and the read `gp().n` are.

## Root cause

`_call_field` (src/frontend/parse_expr.cyr): `gp` resolves (fi >= 0) but neither its return struct (`GFRS`) nor its
`*T` pointee (`_fn_rpsid`) is known — `Foo` is not declared here — so `_call_ptr_field` declines and the silent
--syntax-only branch steps over the call; the statement (`_stmt_call_field`) then sees `= 5` and reports
`_asg_temp_refused`. 6.7.15's `_cf_unres` arm covers only a callee with no definition here (`_fn_nodef`).

## Proposed fix

Under --syntax-only, also arm `_cf_unres` when the callee's declared return is a `*T` whose T this file does not
declare, so the statement and the step parse the tail silently; rows beside call_ptr_field_store.sh S1-S9 (`: *Foo`
accepted; `: Foo` by value keeps "the result is a temporary", which is true of it).
