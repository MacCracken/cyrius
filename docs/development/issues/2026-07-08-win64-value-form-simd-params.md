# Win64 PE: value-form SIMD params/returns unsupported (`f32v4`/`f64v2`/`f64v4` by value)

**Filed:** 2026-07-08 (surfaced attempting to cross-OS-gate `simd_f32v4` in SIMD Phase 5).
**Severity:** P3 — fails LOUD with a clear message + workaround (pointer-form); no miscompile.
**Component:** `src/backend/x86/emit.cyr` (Win64 vector param/return ABI), the value-form SIMD
wrappers in `lib/simd.cyr`.

## Problem

Passing an `f32v4`/`f64v2`/`f64v4` **by value** as a function parameter (or returning one by
value) hard-errors on the Win64 PE target:

```
error: f64v2/f64v4 value-form params not yet supported on Win64 PE — use pointer-form wrappers from lib/simd.cyr
```

The SysV/AArch64 vector-param ABI (128-bit in a vector register / HVA) is implemented; the Win64
convention (vectors >... passed by hidden pointer, not in XMM) is not. So the value-form half of
the SIMD wrappers (`f32v4_add(a, b)`, `scale(v: f32v4)`, etc.) is x86-SysV + aarch64 only; Win64
consumers must use the pointer-form / flat-array intrinsics (`f32v4_add(&a, &b)`, `f32v_add(&r, a, b, n)`).

This is why `simd_f32v4.tcyr` (value-form-heavy) stays a regular tcyr rather than a full `vr01_`
cross-OS gate — the Win64-safe flat-array subset is gated by `vr01_simd_f32v4_neon.tcyr` instead.

## Fix

Implement the Win64 vector-by-value param/return ABI in the PE path (pass 128-bit vectors by a
hidden pointer per the Win64 convention, matching MSVC/clang `__m128`), then remove the hard-error
and let the value-form wrappers compile on Win64. Verify on cass with a value-form `f32v4` param
round-trip.

## Acceptance

A `--win` program passing/returning an `f32v4` by value compiles and runs correct on cass; the
value-form SIMD wrappers work on Win64; `simd_f32v4.tcyr` can then become a full `vr01_` gate.
