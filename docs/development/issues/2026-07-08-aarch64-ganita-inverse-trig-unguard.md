# aarch64: un-guard ganita inverse-trig (asin/acos/atan2) now that f64_atan polyfills

**Filed:** 2026-07-08 (unblocked by v6.4.25's aarch64 `f64_atan` polyfill).
**Severity:** P3 — enhancement; the functions work on x86, just skipped on aarch64.
**Component:** `lib/ganita.cyr` (inverse-trig `#ifdef CYRIUS_ARCH_X86` block, lines ~1197–1252),
`tests/tcyr/math_inverse_trig.tcyr` (mirrors the guard).

## Problem

`ganita_f64_asin` / `ganita_f64_acos` / `ganita_f64_atan2` (and their `f64_asin` /
`f64_acos` / `f64_atan2` wrappers) are wrapped in `#ifdef CYRIUS_ARCH_X86` because
they build on `f64_atan`, which hard-errored on aarch64 pre-v6.4.25. The guard
comment itself calls the aarch64 case "a reserved future stdlib slot if a consumer
surfaces a need." **v6.4.25 added the `_f64_atan_polyfill`, so the blocker is gone**
— their bodies now only need `f64_sqrt` (native aarch64 FSQRT) and `f64_atan`
(polyfilled). `tests/tcyr/math_inverse_trig.tcyr` runs 0/0 on aarch64 today (all
asserts skipped by the same guard); abaco's atan2 quadrant use stays x86-only.

## Fix

Remove the `#ifdef CYRIUS_ARCH_X86` / `#endif` around the ganita inverse-trig block
(and any wrapper-visibility mismatch — the `f64_asin`/`f64_acos`/`f64_atan2` wrappers
at ~1374 sit *outside* the guard while the `ganita_*` bodies sit *inside*, which is a
latent undefined-fn on aarch64 to reconcile). Remove the matching `#ifdef` in
`math_inverse_trig.tcyr` so its 17 asserts run on aarch64 too. This is the
SOURCE-repo (`~/Repos/ganita`) fix, then re-vendor — not a `lib/ganita.cyr`-only fold.

## Acceptance

`math_inverse_trig.tcyr` passes 17/17 on aarch64 (qemu + pi), not 0/0; asin/acos/atan2
match reference to the same tier as x86; x86 unchanged; aarch64 self-host + seed-derive
re-verified. Quadrant correctness (Q1–Q4 + axes) holds on aarch64 exactly as on x86.
