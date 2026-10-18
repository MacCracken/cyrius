# A generic's multi-value return element typed by its type parameter (`fn mm2<V>(x: V): (V, i64)`) binds i64 in a destructure at the f64 instance: `var a, b = mm2<f64>(h);` makes `a` an integer word — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 generics lane (unit G5) on the lane's tree after the
explicit-method lookahead bite, x86_64, CYRIUS_IR=3, aarch64 (qemu), cx (cxvm), PE (wine): all exit 7; the same on the
slot-open compiler for the free spellings.
**Placement:** unplaced — filed from the 6.7.15 generics lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Discovered:** 2026-10-18, 6.7.15 generics G5, checking that the explicit method spelling `var a, b = p.mm<f64>(h);`
(now a destructure, issues/2026-10-16-explicit-method-type-args-in-method-call-lookaheads.md) types its bindings as the
free spellings do: none of the generic spellings type a `V` element f64.
**Severity:** Medium — silent: the element holds the double's bits and is used as an integer (a warning, "integer
arithmetic with an f64 right operand", but the wrong value); the non-generic `fn mm3(x: f64): (f64, i64)` binds f64
(control: 10).
**Kind:** codegen / typing defect (what the source says: the instance returns `(f64, i64)`).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn mm2<V>(x: V): (V, i64) { return (x, 7); }
fn main(): i64 {
    var h: f64 = 1.5;
    var a, b = mm2<f64>(h);
    return f64_to(a * 2.0) + b;
}
syscall(60, main());
```

```
actual:   warning:<source>:6:26: integer arithmetic with an f64 right operand
          exit 7 (x86_64, IR=3, aarch64, cx, PE)
expected: exit 10 (a = 1.5 as f64: 3 + 7), as `fn mm3(x: f64): (f64, i64)` gives
```

The same with the inferred `mm2(h)`, `P_mm<f64>(&p, h)`, a method `p.mm(h)` and the explicit `p.mm<f64>(h)`.

## Root cause

Not located. The destructure's callee is the instance (`_dt_call_fn` -> `_gen_resolve_call`), but the bindings' kinds
come from the element kinds recorded for the signature (`_mret_ek`), which for a `V` element are read where V is unbound
(i64) — pass 1's `_mret_elem` record of the template, not the instance's binding.

## Fix direction

Read a type-parameter element's kind under the instance's binding when the destructure's callee is an instance (as a
`: T` return is read, `_ptr_ann_sid_tp`-style), for the free and the method spellings. Rows: the repro 10; `(V, i64)` at
i32 / a struct / f64; the method spellings.
