# aarch64 trig polyfill: Payne-Hanek reduction for extreme-|x| accuracy

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
