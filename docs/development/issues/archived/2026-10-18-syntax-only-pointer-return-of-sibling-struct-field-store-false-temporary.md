# `--syntax-only`: `gp().n = 5;` with `fn gp(): *Foo` defined HERE and `Foo` a sibling module's struct is a false "the result is a temporary" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ST-9, `45135d7db` — no decision needed: a `--syntax-only` false refusal; 6.7.13's D8 (a) makes a `: *T` result's field an lvalue. `_ret_ptr_record` records per fn, under `--syntax-only` only, whether its one-`*` return names a T no type here resolves (`_ret_ptr_unk` → `_fn_rpun`, alloc'd at its first 1, written in pass 1 and pass 2), and `_call_field`'s silent branch arms `_cf_unres` for it (`_cf_unres_fn`). Under `--syntax-only` the filed repro exits rc 0 with no error and no warning (was rc 1, "2:23: cannot assign to a field of a call result: the result is a temporary"), on the x86_64, aarch64, cx and PE compilers. The for step, `+=`, `<<=`, a nested field, a subscript, a callee defined below, `: *Box<i64>`, a generic and top level are accepted too. A `: Foo` result by value, a `: **Foo` and a `: *i64` keep the refusal, and a full compile never allocates the table. Rows: `tests/gates/frontend/call_ptr_field_store.sh` S10 (the filed repro verbatim) – S22; mutations RED 32 / 4 / 4. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S6) beside
issues/archived/2026-10-17-syntax-only-sibling-ptr-call-field-store-false-temporary.md, whose fix covers a callee this file does
not define (a sibling's fn). Here the fn is defined in this file and only its return type's struct is a sibling's.
Pre-existing (the lane head gives the same); x86_64 measured, the frontend's.
**Placement:** 6.7.16 — Break 2, repair 6 (structs lane, wave 1, unit S4; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
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
