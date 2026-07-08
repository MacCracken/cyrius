# aarch64 backend: f64 exp2 and atan hard-error (no polyfill)

**Filed:** 2026-07-07 (CHANGELOG-prose deferral sweep — the v6.4.16 trig work named these
"separate unfiled aarch64 gaps").
**Severity:** P3 — fails loud on aarch64; blocks any aarch64 amalgamation using `f64_exp2`/`f64_atan`.
**Component:** `src/backend/aarch64/emit.cyr`, `lib/math.cyr`.

## Problem

`f64_exp2` and `f64_atan` compile on x86 (native x87) but **hard-error on aarch64** —
unlike `f64_sin`/`f64_cos`/`f64_exp`/`f64_ln`, which got polyfills in v6.4.16. CHANGELOG
[6.4.16]: *"exp2 / atan stay hard-errors (separate unfiled aarch64 gaps; tan = sin/cos at
the lib level)."* No backing issue exists (the resolved trig-polyfill issue and the abaco
stdlib-math API issue are about x86 lib-API surface, not the aarch64 backend hard-error).

## Fix

Add `EF64_EXP2` / `EF64_ATAN` aarch64 dispatch + `_f64_exp2_polyfill` / `_f64_atan_polyfill`
in `lib/math.cyr`, mirroring the v6.4.16 sin/cos/exp/ln pattern (tier-1 accuracy,
qemu-verified). `f64_tan` composes from sin/cos at the lib level (no new backend op).

## Acceptance

`f64_exp2`/`f64_atan` compile + run correct on aarch64 (qemu + real ARM), tier-1 accuracy
vs a reference; an aarch64 amalgamation using them builds. Any `src/backend/aarch64` change
re-triggers aarch64 self-host + seed-derive.
