# `f64_sin` / `f64_cos` have no aarch64 polyfill — any trig-consuming code is x86-only

> **RESOLVED — v6.4.16.** `_f64_sin_polyfill` / `_f64_cos_polyfill` added to core-cyrius
> `lib/math.cyr` (range-reduce to [−π/4, π/4] + Horner Taylor through 1/15!/1/14!, shared
> `_core` helpers) + `EF64_SIN`/`EF64_COS` dispatch in `src/backend/aarch64/emit.cyr`
> (mirrors the v5.7.31 exp/ln pattern the ask specified). Accuracy tier-1 (worst < 1e-14 vs
> x87, all quadrants); aarch64 end-to-end verified under qemu (compiles + `sin²+cos²=1` +
> anchors) and self-hosts byte-identical. `exp2`/`atan` remain x86-only (separate unfiled
> gaps; `tan` = sin/cos at the lib level). Test `tests/tcyr/vr01_trig_polyfill.tcyr`.
> **Consumer unblock:** attn11 can drop `[deps.hisab] target = "x86_64"` + the three
> `#ifndef CYRIUS_ARCH_AARCH64` gates once it re-vendors math.cyr. See CHANGELOG [6.4.16].

- **Filed**: 2026-07-07 (by an attn11 consumer — the 1.14.0 hearing lane broke the
  aarch64 CI leg; repro on cc 6.4.14, also reproduces at the 6.2.29 attn11 CI pin)
- **Severity**: P2 (Medium) — arch parity gap, fail-loud (a hard compile error, no
  wrong results). Blocks entire consumer *features* on aarch64 rather than
  degrading them.
- **Scope**: the aarch64 backend + stdlib `math.cyr`. `f64_exp` / `f64_ln` /
  `f64_log2` got aarch64 polyfills at **v5.7.31** (`_f64_ln_polyfill` etc., with
  the `parse_expr` auto-dispatch); **sin/cos never did** — the compiler
  hard-rejects them on aarch64.

## Symptom

Any aarch64 build whose amalgamation contains a `f64_sin` / `f64_cos` call fails:

```
error: f64_sin is x86-only for v5.6.0; aarch64 has no native trig — needs polyfi
compile tests/attn11.tcyr -> build/test_a64 [aarch64] FAIL
```

## Trigger (the consumer case)

attn11 1.14.0's **hearing lane** (the modality-axis hearing proof): the Hann
window (`f64_cos`) and the synthetic-audio synth (`f64_sin`), plus **hisab's
`num_fft`** (its twiddle factors call both, unguarded in `dist/hisab.cyr`),
pulled in as `[deps.hisab]`. Dep modules auto-prepend into every matching
target's amalgamation, so hisab's mere presence broke the aarch64 build even
with the consumer's own calls `#ifndef`-gated.

## Consumer-side workaround (shipped in attn11 1.14.0)

`[deps.hisab] target = "x86_64"` (the v6.3.1 dep target key — which forced the
attn11 pin 6.2.29 → 6.4.14, since CI installs the pin and older cbt ignores the
key) + `#ifndef CYRIUS_ARCH_AARCH64` around the manual includes / CLI flags /
suite registrations. The hearing lane is **x86-only** until this closes.

## Affects (beyond attn11)

**hisab itself** (its dist cannot compile aarch64 at all — `num_tan`, `num_fft`,
polar/complex helpers), the shravan/naad-class DSP surface, and any future
audio/graphics consumer on the Pi-ARM line (seema fleet, the 1.6x aarch64 kernel
line). The hearing-on-a-Pi tok/s story is exactly the sovereignty flex the
ecosystem wants eventually, and it is gated here.

## Ask

The v5.7.31 pattern, applied to trig: stdlib `_f64_sin_polyfill` /
`_f64_cos_polyfill` (range-reduce to [−π/4, π/4] + polynomial — the
`_f64_ln_polyfill` precision bar, ~1e-15) + `parse_expr` auto-dispatch on
aarch64. NEON-native trig instructions are **not** the ask (there are none
anyway — even hardware sin/cos on aarch64 is a library affair); the polyfill
alone unblocks. Phase-5 SIMD trig, if ever, is a separate optimization.

## Unblock signal (consumer side)

When the polyfill lands: attn11 drops `target = "x86_64"` from `[deps.hisab]`
and removes its three `#ifndef CYRIUS_ARCH_AARCH64` gates; the hearing suite
group then runs under qemu-aarch64 like the rest (expected suite 1066 with the
hearing group live on both arches).

---
*Mirrored consumer-side at
`attn11/docs/development/issues/2026-07-07-cyrius-aarch64-trig-polyfill.md`.*
