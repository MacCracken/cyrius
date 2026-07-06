# ADR-002: Everything is i64

**Status**: Accepted
**Date**: 2026-03-25
**Context**: Needed a type model for a self-hosting compiler bootstrapped from assembly.

## Decision

All values are 64-bit integers. No separate float, bool, char, or pointer types at the machine level. Type annotations exist for documentation and future checking but do not affect code generation.

## Rationale

- **Simplicity**: One register width, one storage size, one calling convention
- **Bootstrap**: Assembly deals in machine words — mapping 1:1 eliminates abstraction
- **Floats**: Added in v0.9.2 as bit-pattern reinterpretation (SSE2 builtins on i64 values)
- **Pointers**: Just integers — address arithmetic works naturally
- **Structs**: Contiguous i64 fields at fixed offsets

## Consequences

- No type errors at compile time (values are untyped bits)
- Float operations require explicit `f64_from`/`f64_to` — no implicit conversion
- No method dispatch based on type — convention-based naming (`Point_scale`)
- Generics Phase 2 will add compile-time checks without changing codegen

## Status Update (2026-07-06, v6.4.x)

The scalar i64 model still holds — it is the canonical ground-truth type, the "oracle"
every other type reduces back to. But two categories of value are now **typed views
that DO drive codegen**, so the original "type annotations do not affect code
generation" is qualified:

1. **Floats** (since v0.9.2) — `f64`/`f32` reached through the `f64_from`/`f64_to`/
   `f32_from`/`f32_to`/`cvt` conversion hub; scalar float math funnels through `f64`.
2. **SIMD vector types** (the v6.4.x arc) — packed vectors are carried as **negative
   `SLTYPE` sentinels** and live in XMM/YMM registers with distinct per-type emit paths:
   - `f64v2`/`f64v4` (128-bit) keep the legacy `-20`/`-21` sentinels.
   - `f32v4` (128-bit, v6.4.4), integer vectors `i8v16`/`i16v8`/`i32v4`/`i64v2` + unsigned
     (v6.4.6/.7), and `f32v8` (256-bit AVX2/VEX, v6.4.8/.9) use **structured descriptors**
     in the reserved band `<= -2048`, decoded by one `_vec_desc()`.

This is the **"i64 oracle + free type movement"** model: a vector is *N* lanes of an
element type, entered by broadcast/load and **returned to i64 by extract/reduce** —
a first-class view on the type lattice, never a parallel type universe. The pure
"everything is untyped i64 bits" framing is therefore accurate for the scalar core but
no longer literally true across the whole language: floats and SIMD vectors are typed
lanes the backend must know about.

(Related: the generics "Phase 2" note above shipped — `CYRIUS_MONOMORPH` went default-on
at v6.4.0, monomorphizing generic fns without changing the i64 scalar codegen.)
