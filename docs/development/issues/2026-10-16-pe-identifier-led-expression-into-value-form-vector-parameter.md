# On Windows, an identifier-led expression (`lanes(q + 1)`, `lanes(z * 2)`, `lanes(w + 1)`) passed to a value-form vector parameter compiles and reads garbage — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (after the D30 review fix, `fe1a0447`) and on
the lane base (`f59668ad`, `build/cycc` 2,270,008 B): refused on x86_64 / aarch64 / cx, compiles on PE (both
compilers) and exits 5 under wine. Pre-existing; D30's `_sarg_pe_vword` (which refuses a word there since this
release) never sees this shape.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-16, the 6.7.13 vectors lane's review-fix step (probing the PE one-line fix beside
`lanes(nosuch)`).
**Related:** /home/macro/.cache/c6/6713_staging/vectors/2026-10-16-vector-dereference-into-value-form-parameter-faults-on-pe.md
(`lanes(*pb)` on PE, the same push through `_push_struct_expr_arg` reached from `_sarg_deref`) and
2026-10-16-parenthesised-argument-into-value-form-vector-parameter.md / 2026-10-16-pe-struct-local-into-value-form-vector-
parameter.md (the other PE shapes the address arms take before the parity check). One fix — the parity check before
the address arms for a Win64 value-form vector parameter — may cover all four.
**Severity:** Medium — compiles clean on one target only and computes a wrong value (or faults: a value pushed where the
callee copies 16 bytes through an address — `lanes(5)` faulted the same way on cass before D30); every other target
refuses the same source by name.
**Affects:** PE (Win64) only; every value-form vector parameter.

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(z): i64 {
    var q = 3;
    var w: f64v2 = mkv(4, 2);
    return lanes(q + 1) + lanes(z * 2) + lanes(w + 1);
}
syscall(60, run(3));
```

```
x86_64 / aarch64 / cx (the lane), three lines:
error:<source>:6:18: a value-form vector argument to 'lanes' is a local of its type or a call declared to return it (by name, a method, or fncallN / callptr with the callee written `&f`) - got `q`
error:<source>:6:33: a value-form vector argument to 'lanes' is a local of its type or a call declared to return it (by name, a method, or fncallN / callptr with the callee written `&f`) - got `z`
error:<source>:6:48: a value-form vector argument to 'lanes' is a local of its type or a call declared to return it (by name, a method, or fncallN / callptr with the callee written `&f`) - got `w`
PE (the lane and the base, CYRIUS_TARGET_WIN=1, wine): compiles; exit 5 — and exit 5 for each of `lanes(q + 1)`,
`lanes(z * 2)`, `lanes(w + 1)` alone
```

A literal-led one (`lanes(5 + z)`) is refused on PE (it reaches `_sarg_pe_vword`), as is a whole name (`lanes(q)`).

## Root cause

On Win64 a value-form vector parameter carries the struct-mask bit (address-passed), so `_arg_push_snap` asks
`_try_push_struct_addr_arg` (src/frontend/parse_fn.cyr) first. An argument led by an identifier that is not followed by
`,` / `)` / `(` / `<` reaches its "any other expression" arm — `if (nx != 31) { if (nx != 11) { return
_push_struct_expr_arg(..); } }` — which parses the expression and pushes its VALUE as the parameter's address,
returning 1, so `_sarg_pe_vword` (the D30 parity refusal, called only when every address arm declines) never runs; the
callee copies 16 bytes from address 4 / 6 / ... .

## What a fix needs

On PE, refuse a value-form vector parameter's argument that is not a whole vector local, a vector call, or the `&x`
pointer form (see the `&w` staged file) BEFORE `_try_push_struct_addr_arg`'s expression arm — with `_sar_err`'s words
and the skip the review fix gave `_sarg_pe_vword` (one line) — and rows VZ on PE for `q + 1`, `z * 2`, `w + 1` in
tests/gates/codegen/simd_pointer_param.sh.
