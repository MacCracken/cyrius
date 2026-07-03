> **RESOLVED — Tier A shipped.** Native f64 type + literals (`1.5`) + operators (`+ - * /`,
> comparisons) + NaN on x86 + aarch64 shipped (see CHANGELOG; verified `var x: f64 = 1.5; x + 2.5`).
> Tier B (stdlib intrinsics) was the fallback and is moot. Archived.

# Native float arithmetic (f32/f64 operators or stdlib intrinsics)

**Filed:** 2026-06-16 during mabda 3.2.x (TS.8b — native AMD bilinear/scaled
texture sampling)
**Severity:** Language/stdlib gap — Cyrius has no first-class floating-point
arithmetic. The only float facilities in the ecosystem are mabda's two inline
x86-64 SSE2 *conversion* shims (`f64_to_f32` / `f32_to_f64` in `mabda/src/color.cyr`).
Any actual float MATH (add/sub/mul/div, int→float, comparisons) must be
hand-rolled as inline `asm { ... }` byte blocks, per operation.
**Affects:** every consumer doing real-number math — mabda (GPU: blit scales,
viewport/NDC, color), bijli (EM field simulation), rasa/ranga (image processing),
and any future DSP/physics/geometry code. Also blocks non-x86-64 targets.
**Target slot:** a v6.x language feature (float operators) or a same-arc stdlib
intrinsic set — maintainer direction. No urgency for mabda (the shim below works
on x86-64); this unblocks portable, testable float math ecosystem-wide.

## Trigger

mabda TS.8b adds scaled/bilinear texture sampling on native AMD. The fragment
shader multiplies the fragment position by a per-draw scale = `tex_dim / rt_dim`
(so a W×H texture maps over an arbitrary render target). That scale is an f32 the
CPU must compute from two integers — a single float division. Cyrius can't
express it, so mabda shipped a **shim**, `int_ratio_to_f32(num, den)`
(`mabda/src/color.cyr`), an inline SSE2 block:

```
cvtsi2sd xmm0, num ; cvtsi2sd xmm1, den ; divsd xmm0, xmm1
cvtsd2ss xmm0, xmm0 ; movd eax, xmm0
```

It works (CPU-tested: 1/2→0x3F000000, 2/64→0x3D000000), but it is the third
hand-encoded float asm block in mabda, and the pattern does not scale.

## The problem with the status quo

Hand-rolled inline-asm float ops are:

1. **Fragile.** The byte block hard-codes the stack layout (`[rbp-8]` = first
   arg, `[rbp-16]` = second, `[rbp-24]` = first local). A change to how the
   compiler frames locals/args silently breaks every such helper — caught only by
   a result-comparison test, never by the compiler.
2. **Non-portable.** Every block is x86-64 SSE2. The moment Cyrius targets
   aarch64 (or any other arch), every float helper is dead and must be
   re-encoded in NEON. mabda's `f64_to_f32`, `f32_to_f64`, and now
   `int_ratio_to_f32` are all x86-64-only.
3. **Untestable except by result + uneditable by humans.** A wrong opcode byte is
   invisible in review; there is no mnemonic-level check (unlike GFX9 shader bytes,
   which at least round-trip through `llvm-mc`).
4. **Viral.** Each new float operation (mul, add, sqrt, compare, clamp) is another
   bespoke asm block. Real graphics/sim math needs dozens.

## Proposal

First-class floating point. Two tiers, pick per maintainer appetite:

### Tier A — language float type + operators (preferred)
`f64` (and optionally `f32`) as real types with `+ - * / < > == ...`, the compiler
emitting the target's FP instructions (SSE2 on x86-64, NEON on aarch64). Literals
(`1.5`, `0.03125`). int↔float casts. This is the clean end state; mabda deletes
all three asm shims.

### Tier B — stdlib float intrinsics (minimal unblock)
If full float types are a large lift, a `lib/float.cyr` of compiler-intrinsic
(or one-place-asm) primitives over the existing i64-bit-pattern convention:

| Intrinsic | Meaning |
|---|---|
| `f64_from_i64(n)` | `(double)n` → f64 bit pattern |
| `f64_add/sub/mul/div(a, b)` | f64 arithmetic on bit patterns |
| `f64_lt/le/eq(a, b)` | f64 comparisons → 0/1 |
| `f64_to_f32(x)` / `f32_to_f64(x)` | the existing conversions, promoted to stdlib |

Centralizing the asm in ONE toolchain-owned place (vs. scattered across consumer
repos) already fixes fragility + gives a single porting point for aarch64.

## Why this is more than cosmetic

- **Every AGNOS real-number consumer hits it.** mabda (GPU transforms, blit
  scales, color, NDC), bijli (EM simulation is float-dense), rasa/ranga (image
  filters). Today they either hand-roll asm or contort into fixed-point.
- **Portability is hard-blocked.** AGNOS targeting aarch64 (or anything non-x86)
  cannot run any current float code — it's all SSE2 byte blocks.
- **Correctness/reviewability.** Float ops would be compiler-checked instead of
  hand-encoded; the `[rbp-N]` stack-offset hazard disappears.

## Until then

mabda keeps `int_ratio_to_f32` (+ `f64_to_f32`/`f32_to_f64`) as documented,
CPU-tested x86-64 shims, each cross-referencing this proposal. They are deleted
when Tier A or B lands.
