# A generic's multi-value return element typed by its type parameter (`fn mm2<V>(x: V): (V, i64)`) binds i64 in a destructure at the f64 instance: `var a, b = mm2<f64>(h);` makes `a` an integer word — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GB-22, `25eeba79a`, and GB-23, `fd0134b10` — no decision needed (the instance returns `(f64, i64)`). `_mret_elem` reads a type-parameter element under the instance's binding, as a single `: T` return is, and the destructure's lookahead resolves an inferred generic method's instance (`_dt_call_fn` → `_mcall_gen`). The filed repro exits 10 with no warning (it exited 7 with "integer arithmetic with an f64 right operand") on x86_64, IR=3, aarch64, cx and PE; the inferred `mm2(h)`, `P_mm<f64>(&p, h)`, `p.mm(h)` and `p.mm<f64>(h)` the same; `var t: (f64, i64) = mm2<f64>(h);` compiles; `(V, i64)` at i32 stays an i64 slot (12), a struct element is the struct. The checks read the instance's values (`var t: (i64, i64) = mm2<f64>(h);` and `mm2<Pt>(p)` into `(i64, i64)` are refused, as for a written `(f64, i64)` / `(Pt, i64)` fn), a generic's tuple local is reported once, and the refusals spell the fn and its values as the source does (GB-23: `mt<f64>`, `Q.pair`, `(Box<Pt>, i64)`). Rows: the new `generic_multi_value_element.sh` V1 (the filed repro verbatim, five legs) – V5f, V5K; `tests/tcyr/crossos/multi_return.tcyr` mv_* (54 → 71 rows); mutations M1 – M6. Filed beside it: the declaration-zone destructure of a written `(f64, i64)` fn leaves its f64 element untyped (issues/archived/2026-10-20-zone-destructure-leaves-f64-element-untyped.md, the user's D98, wave 4). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 generics lane (unit G5) on the lane's tree after the
explicit-method lookahead bite, x86_64, CYRIUS_IR=3, aarch64 (qemu), cx (cxvm), PE (wine): all exit 7; the same on the
slot-open compiler for the free spellings.
**Placement:** 6.7.16 — Break 2, repair 6 (genbind lane, wave 3, unit GB6; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Discovered:** 2026-10-18, 6.7.15 generics G5, checking that the explicit method spelling `var a, b = p.mm<f64>(h);`
(now a destructure, issues/archived/2026-10-16-explicit-method-type-args-in-method-call-lookaheads.md) types its bindings as the
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
