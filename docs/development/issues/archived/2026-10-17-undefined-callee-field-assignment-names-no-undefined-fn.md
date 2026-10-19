# `undefd().n += 1;` (a field of an UNDEFINED fn's result) is "expected ';', got '.'", and as a for step "expected '=', got '('" — neither names the undefined fn — RESOLVED

> ✅ **RESOLVED in v6.7.15** (ST-17, `cb49ae974` — no decision needed: diagnostics only. `_call_field` hands a callee that resolves to no fn, with a `.field` chain, to `_call_undef`, which reports the fn at its name and steps over the call and its chain. The filed statement repro is "3:16: undefined function 'undefd'" alone (it was "3:24: expected ';', got '.'", two warnings and the end-of-compile refusal) and the for step "3:46: undefined function 'undefd'" (was "3:52: expected '=', got '('"), once, on the x86_64, aarch64, cx and PE compilers and the ecb, ach, pi and cass natives; also a value `var x = undefd().n;`, a method or subscript on the result, top level and a closure. It is an error: `--allow-undef` does not build the line. `--syntax-only` stays silent (a sibling module's fn). Rows: `frontend/call_ptr_field_store.sh` U1 / U2 (the repros verbatim, their positions) – U15; mutations RED. Not closed here (filed, 6.7.16): after an earlier plain `undefd();` the field call reads "cannot take a field of the result of 'undefd': it does not return a struct" (`2026-10-18-field-of-call-registered-undefined-fn-says-does-not-return-a-struct.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane (unit S1) while landing
issues/archived/2026-10-15-for-step-call-led-field-assignment-refused-with-false-undefined.md (a for step `gp().n += 1` stores
through a `: *T` result since this unit). Pre-existing: the lane's base compiler (f133fb2f) gives the same lines.
x86_64 measured; the frontend's, every target.
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S6; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
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
