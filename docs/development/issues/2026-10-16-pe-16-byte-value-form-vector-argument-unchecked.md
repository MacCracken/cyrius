# On PE, a value-form 16-byte vector parameter (`v: f64v2` / `v: f32v4` / an integer vector) takes a vector local of any type with no check — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V1, after the value-form f32v8 bite) and
on the lane's base compiler (`f59668ad`, `build/cycc` 2,270,008 B): the three probes below are refused on x86_64,
x86_64 `CYRIUS_IR=1` / `CYRIUS_IR=3` / `CYRIUS_DCE=1`, aarch64 (qemu) and cx (cxvm) and compile on PE (wine), where the
callee reads whatever bytes sit at the argument's address.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane; filed from the 6.7.13 vectors lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-16, the 6.7.13 vectors lane, the value-form f32v8 parameter bite
(`archived/2026-10-15-value-form-f32v8-parameter-receives-one-word.md`), whose filed rows required the 32-byte half of this
check on PE (an f64v4 local into `v: f32v8` and the reverse) — that half landed with it (`_sarg_pe_v32`); the 16-byte
parameters are beyond that issue's filed surface.
**Severity:** Medium — compiles clean on one target only and computes a wrong value (or reads past a 16-byte local into
a 32-byte one's neighbour); every other target refuses the same source by name.
**Affects:** PE (Win64) only; every value-form 16-byte vector parameter (f64v2, f32v4, i8v16 … u64v2).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn g(v: f64v2): i64 { if (load64(&v) == 9) { return 0; } return load64(&v + 8); }
fn main(): i64 { var e: f64v4 = f64v4_make(1, 2, 3, 4); return g(e); }
syscall(60, main());
```

```
x86_64 / IR=1 / IR=3 / DCE / aarch64 / cx: error:<source>:4:67: value-form SIMD arg must be a 16-byte vector
PE (wine): compiles, exit 2 (the f64v4's lane 1)
```

`fn g(v: f32v4)` given an f64v2 local (`f64v2_make(5, 7)`, `return load32(&v + 4)`): elsewhere `value-form SIMD arg type
mismatch (callee expects f32v4)`; PE compiles, exit 0. `fn g(v: f64v2)` given an f32v8 local: elsewhere `.. must be a
16-byte vector`; PE compiles, exit 3.

## Root cause

Win64 passes a value-form vector parameter by address: the prescan sets the parameter's struct-mask bit, not its SIMD
mask code, so `_call_arg_one`'s `_pm_simd` arm (`_simd_arg_record` → `_simd_arg_typecheck`) never runs there. The
argument reaches `_try_push_struct_addr_arg` → `_sarg_vec_ptr` (src/frontend/parse_fn.cyr), whose not-a-`*V` branch
returns `_TARGET_PE` (push the address) with no type check; 6.7.13 added `_sarg_pe_v32` there for the 32-byte
parameters only.

## Fix direction

In `_sarg_vec_ptr`'s PE branch, check a 16-byte value-form parameter by the rule `_simd_arg_typecheck` applies
elsewhere (class 1: any 16-byte vector by size; f32v4 exactly), the parameter's class read from the definition's tokens
as `_pv32_param` reads the 32-byte one. A source that compiles on PE today stops compiling there (it computes garbage);
rows on PE (wine) and cass.
