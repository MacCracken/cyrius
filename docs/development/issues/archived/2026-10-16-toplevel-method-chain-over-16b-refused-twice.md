# A top-level `.field` / `.m()` on a method result over 16 B is refused twice — RESOLVED

> ✅ **RESOLVED in v6.7.14** (RC-3, `80dae593` — no decision needed; diagnostics only: the filed repro gives exactly one error per line (6:14 'B_mk', 7:12 'mk3'), where line 6 was reported at 6:14 and 6:16; a top-level dyn method chain over 16 B, `b0.mk().tot()` and the statement `b0.mk().b;` are one error each. `_method_chain`'s top-level arm no longer repeats the refusal `_sc_pre` made for a result over 16 B (the `&f` callee's own skip folded in). With the structs lane's top-level field-store fix beside it, `b0.mk().b = 5;` at top level is one error too (three before). Rows: `frontend/call_result_field.sh` C4 (the repro verbatim) – C10 (floor 28); mutation RED C4 C5 C7 – C10. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — found 2026-10-16 by the 6.7.13 receives lane (unit R3) while fixing
issues/archived/2026-10-13-field-of-indirect-call-struct-result.md (D16 (a)), whose known-callee chain had the same shape and
is refused once (its `_icall_chain` skips the second report). The method arm is unchanged by that fix. x86_64, the
lane tree (`build/cycc` 2,278,280 B); the frontend's, so every target.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — refused code, one expression reported twice.
**Kind:** diagnostics.

## Repro

```cyrius
struct P3 { a; b; c; }
struct B { k; }
impl B { fn mk(self): P3 { var r: P3 = P3 { 1, 2, 3 }; return r; } }
fn mk3(a): P3 { var r: P3 = P3 { a, a + 1, a + 2 }; return r; }
var b0: B = B { 1 };
var g = b0.mk().b;
var h = mk3(5).b;
syscall(60, g + h);
```

`cat repro.cyr | build/cycc`:

```
error:<source>:6:14: 'B_mk' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn
error:<source>:6:16: 'B_mk' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn
error:<source>:7:12: 'mk3' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn
```

Want one error for line 6, as the free call on line 7 gets. A 9-16 B method result (`P2`) is refused once.

## Root cause

The method arm (src/frontend/parse_decl.cyr, `_field_load_on`) asks for the result's temp through `_sc_pre_m` →
`_sc_pre`, which at top level refuses a retptr-class (> 16 B) result with `_refuse_toplevel_struct_call` and returns
-1; `_method_chain` then reaches its own `GINFN(S) != 1` arm and reports `_refuse_toplevel_struct_call` again.
Neither latches `_panic`.

## Proposed fix

In `_method_chain`'s top-level arm, skip the report when `_ret_agg_class(S, fi) == 2` (`_sc_pre` already made it),
as the known-callee chain (`_icall_chain`, parse_expr.cyr) does. Check the dyn arm (`_dyn_call` → `_dyn_call_top`),
which also reaches `_method_chain`, before moving the test into `_method_chain` itself. Row: the repro, one error
per line.
