# i64v2 value-form packed multiply unimplemented (needs pmuludq sequencing)

**Filed:** 2026-07-07 (CHANGELOG-prose deferral sweep).
**Severity:** P3 — missing SIMD op; the claimed workaround does not actually exist.
**Component:** `src/backend/x86/float.cyr` (`EMIT_IVEC_BINOP`), `lib/simd.cyr`.

## Problem

There is no `i64v2` packed multiply. CHANGELOG [6.4.7]: *"i8 has no packed multiply; i64
packed multiply needs pmuludq sequencing — both left to the pointer-form / flat-array
path."* But the flat-array path does **not** cover i64: `lib/simd.cyr` has
`i64v2_add_ptr`/`sub_ptr` but **no** `i64v2_mul` or `_mul_ptr`, and `iv_mul` is i16/i32
only (v6.4.6). So the capability is genuinely absent, not merely spelled differently.
(i8v16 multiply is a hardware non-feature — SSE has no packed byte multiply — and is
intentionally out of scope.)

## Fix

Implement i64v2 packed multiply via `pmuludq` sequencing (32×32→64 partial products +
shifts/adds for the full 64-bit lane product) in `float.cyr`'s `EMIT_IVEC_BINOP` mul arm
(currently `pmullw`/`pmulld` only), and wire `i64v2_mul` / `i64v2_mul_ptr` in `lib/simd.cyr`.

## Acceptance

`i64v2_mul` produces correct 64-bit lane products (differential vs a scalar reference);
cycc byte-identical; a `.tcyr` regression covers it. Note in `roadmap.md` that the
integer-SIMD arc's "closed here" line left this one op unbuilt.
