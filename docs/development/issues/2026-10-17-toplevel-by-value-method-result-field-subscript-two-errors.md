# A top-level `o.mk().p[0] = 5;` (a method returning a struct by value) is reported twice, the second a false "cannot subscript field 'p': it is not a *T field" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-17 by the 6.7.14 structs lane (unit S1) beside
issues/archived/2026-10-15-toplevel-by-value-call-field-store-two-errors.md, whose fix (`_tsc_n`: the statement forms step over
the rest once the call refused itself) covers `mk().n = 5;`, `mk().n += 1;`, `mkp().p[0] = 5;` and the method's
`o.mk().n = 5;` / `+= 1` at top level (call_ptr_field_store.sh T0-T5). The method form with a subscript of the result's
`*T` field is not covered: its second error is written inside PARSE_FIELD_LOAD's chain, before `_stmt_method_call`
regains control. Measured on the lane tree after 54da13808 (x86_64; the frontend's, every target).
**Placement:** 6.7.15 — repair 5 (structs lane, wave 2, unit S6; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — refused code, one statement reported twice, the second error false (`p` IS a `*i64` field).
**Kind:** diagnostics.

## Repro

```cyrius
include "lib/syscalls.cyr"
struct H { n; p: *i64; }
struct O { a; }
var buf[16];
impl O { fn mk(self: *O): H { var h: H; h.n = 1; h.p = &buf; return h; } }
var o: O = O { 0 };
o.mk().p[0] = 5;
syscall(60, 0);
```

`build/cycc`:

```
error:<source>:7:7: 'O_mk' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn
error:<source>:7:9: cannot subscript field 'p': it is not a *T field
```

Want one error, the first. In a fn the same statement stores through the field (`fn go(): i64 { var o: O = O { 0 };
o.mk().p[0] = 5; return load64(&buf); }` exits 5), and the free call's twin at top level (`mkp().p[0] = 5;`) is one
error since 81d561fe8.

## Root cause

The method chain refuses the by-value call at top level (`_refuse_toplevel_struct_call`, no panic latch, `_tsc_n`
counts it) and then keeps walking the chain: the `.p[0]` subscript is resolved against a result that was never typed,
so `_psub_ed` (src/frontend/parse_expr.cyr) reports the field as no `*T` field. The skip `_stmt_method_call` now does
on `_tsc_n` runs only after PARSE_FIELD_LOAD returns.

## Proposed fix

Stop the method chain's walk at the refusal (or have `_psub_ed` stay silent when `_tsc_n` moved during the statement),
so the refusal is the statement's one error; a row beside call_ptr_field_store.sh T3-T5.
