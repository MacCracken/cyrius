# A for step `gp().n += 1` (a field of a call's result) is refused "expected '=', got '('" plus a false "undefined variable 'gp'" — the statement form stores through a `: *T` result since 6.7.13 (D8 (a)) — RESOLVED

> ✅ **RESOLVED in v6.7.14** (ST-4, `ede6b7e18`: a classic-`for` step that assigns a field of a call's result is the statement's assignment. No new decision: 6.7.13's D8 (a) makes the field an lvalue, and 6.7.5's rule makes every assignment a statement takes a step. The filed repro exits 3 on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine). Through 6.7.13 it was "expected '=', got '('" plus the false "undefined variable 'gp'"; wave 1's frontend lane had already removed the second. Also stored: `o.gp().n = v`, `gpg<H>().n += 1`, a chain, `gq().q[1] += 2`, `fncall0(&gp).n += 1` and a whole struct-typed field. A by-value `mk().n += 1` step is refused once, "the result is a temporary" (at top level the no-frame refusal alone), and a step with no `=` keeps "expected '='". Rows: `call_ptr_field_store.sh` F0 (the filed repro verbatim) - F6 on the four compilers; `crossos/call_ptr_field_store.tcyr` gains 16 `st_` rows and a top-level step (17 -> 34) on x86_64 / IR=1 / IR=3 / DCE / aarch64 / cx / PE and on ecb, ach, cass and pi. Mutations RED 27 / 11 / 7. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — found 2026-10-15 by the 6.7.13 structs lane (unit S4) while landing D8 (a) (a field of a `: *T`
call's result is an lvalue, issues/archived/2026-10-08-field-store-through-pointer-returning-call-refused.md). Measured on the
lane tree after that bite, x86_64 / aarch64 / cx / PE (the frontend's, all four equal).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane, wave 2, unit S1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — refused code, but with a false second error ("undefined variable 'gp'" for a fn that is defined),
and 6.7.5's rule is that every assignment a statement takes is a for step.
**Kind:** language (a position D8 (a) did not name) + diagnostics.

## Repro

```cyrius
include "lib/syscalls.cyr"
struct H { n; m; }
var buf[16];
fn gp(): *H { return &buf; }
fn mk(): H { var h: H; h.n = 1; return h; }
fn go(): i64 { var i = 0; for (i = 0; i < 3; gp().n += 1) { i = i + 1; } return load64(&buf); }
syscall(60, go());
```

`build/cycc` (the lane tree after D8 (a)), all four targets:

```
error:<source>:6:48: expected '=', got '('
error:<source>:6:49: undefined variable 'gp'
```

As a statement, `gp().n += 1;` stores through the pointer (D8 (a)); as a for step it is refused, twice, the second error
naming a defined fn. `mk().n += 1` as a step gives the same two errors (as a statement: "cannot assign to a field of a
call result: the result is a temporary"). The method form `o.gp().n += 1` as a step: one error, "expected '=', got '.'".
Want: the step stores 3 (exit 3), as `var p: *H = gp(); for (..; ..; p.n += 1)` does; a by-value result refused as the
statement refuses it.

## Root cause

`_for_step_replay` (src/frontend/parse_ctrl.cyr) takes `*p`, `name.f` (PARSE_FIELD_STORE, term `)`), `a[i]`, `f()[i]`
and plain names; a step that opens with a call (`IDENT (` / `IDENT <`) falls to `_for_step_assign`, which expects `=`
after the name and then parses `(` as a fresh expression. D8 (a)'s store (`_cpf_try`, armed by the statement forms
`_stmt_call_field` / `_stmt_method_call` with terminator `;`) is never armed for a step, whose terminator is `)`.

## Proposed fix

Arm `_cpf_try` from `_for_step_replay` for a call-led step with terminator `)` (it ends the step at `)` through
`_fst_on`'s `term`), and give a by-value call's field the statement's "the result is a temporary" refusal, once.
