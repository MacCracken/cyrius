# aarch64 trig polyfill: Payne-Hanek reduction for extreme-|x| accuracy

> **RESOLVED v6.4.25** (2026-07-08). Added a Payne-Hanek-lite double-double
> (Dekker TwoProduct, no FMA) range reduction to `_f64_sin_polyfill` /
> `_f64_cos_polyfill`, gated at |x| ≥ 8192. Below the gate the single-constant
> small-angle path is **byte-identical** (unchanged); above it the dd path is
> exact to ~1e-16 through |x| ≈ 1e15 (was ~5e-2 at 1e15). Verified via
> `vr01_exp2_atan_bigtrig.tcyr` (sin/cos(1e4,1e6) refs + sin²+cos²=1 to |x|≈1e6)
> on x86/qemu/pi/ecb/cass; vr01_trig_polyfill small-angle suite unchanged 31/31.

**Filed:** 2026-07-07 (CHANGELOG-prose deferral sweep).
**Severity:** P3 — accuracy polish; the polyfill is correct for typical angles.
**Component:** `lib/math.cyr` (`_f64_sin_polyfill` / `_f64_cos_polyfill`).

## Problem

The v6.4.16 aarch64 trig polyfills use a **single-constant range reduction** (like
`_f64_exp`'s single `ln2`). CHANGELOG [6.4.16]: *"extreme-|x| Payne-Hanek is a future
polish slot."* For large `|x|` the single-constant reduction loses precision. Never filed —
the resolved trig-polyfill issue does not mention Payne-Hanek.

## Fix

Add large-argument **Payne-Hanek** range reduction to `_f64_sin_polyfill` /
`_f64_cos_polyfill` (multi-word `2/π` product for the high-magnitude path), gated so the
common small-|x| path stays cheap.

## Acceptance

`sin`/`cos` of large angles (e.g. `1e15`) match a reference to tier-1 accuracy on aarch64;
small-angle path unchanged; qemu + real-ARM verified.
