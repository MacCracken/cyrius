# aarch64 backend: f64 exp2 and atan hard-error (no polyfill)

> **RESOLVED v6.4.25** (2026-07-08). `EF64_EXP2`/`EF64_ATAN` in
> `src/backend/aarch64/emit.cyr` now polyfill-dispatch to `lib/math.cyr`'s
> `_f64_exp2_polyfill` (`2^x` via 2^n·exp(f·ln2), ~3e-13) / `_f64_atan_polyfill`
> (two-stage reduction + t^21 Taylor, ~1e-14). Verified on real hardware (pi +
> ecb `SELFHOST_OK`, `vr01_exp2_atan_bigtrig.tcyr` 33/33 on x86/qemu/pi/ecb/cass).
> `f64_tan` composes sin/cos at the call site (no backend op). x86 x87 paths
> untouched. Follow-on `2026-07-08-aarch64-ganita-inverse-trig-unguard.md` filed.

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
