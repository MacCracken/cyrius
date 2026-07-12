# i64v2 value-form packed multiply unimplemented (needs pmuludq sequencing)

**Status (2026-07-11): RESOLVED in cyrius 6.4.53** — added `i64v2_mul` / `i64v2_mul_ptr`
(value + pointer form, `lib/simd.cyr`), low 64 bits per lane (signed==unsigned in two's
complement). Per-backend: **x86/PE/Intel-Mac** (shared SSE emitter) synthesize via **pmuludq
sequencing** `a·b = a_lo·b_lo + (a_lo·b_hi + a_hi·b_lo)<<32` (the `a_hi·b_hi·2^64` term wraps
out mod 2^64); **aarch64 NEON** extracts the 2 lanes to GPRs + scalar `mul` + reinserts (no
`.2d` integer multiply exists); **cx** does a native 64-bit lane `mul` (`load64`/opcode-18/
`store64`) — only the `w==8` hard-error was dropped. i8 (`w==1`) still errors on the packed
backends (no 8-bit vector multiply in SSE/NEON — a hardware non-feature). All 10 x86 + 8
aarch64 encodings llvm-mc-verified; cycc self-hosts byte-identical (it uses no SIMD).
Regression: `simd_ints.tcyr` cross-term `(2^32+1)·3` + wraparound `2^32·2^32≡0`, and an i64
`iv_mul` case in `vr01_simd_cx.tcyr` gated cross-OS on **pi + ecb + cass**.

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
