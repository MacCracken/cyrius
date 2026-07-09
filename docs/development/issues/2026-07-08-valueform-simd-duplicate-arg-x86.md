# Value-form SIMD: duplicate arg `f(v, v)` returns `v` not the op — x86 + aarch64

**Filed:** v6.4.31 (found while extending the cross-OS SIMD gate)
**Severity:** P2 (correctness, narrow trigger)
**Targets:** x86-Linux (SSE) + aarch64 (NEON). **Win64 PE is CORRECT** (v6.4.31's
by-pointer param path passes `&v` twice and reads distinct memory).

## Repro

```cyr
fn scale2(v: f32v4): f32v4 { return f32v4_add(v, v); }   # v + v = 2v
...
var va: f32v4 = f32v4_make(0x40000000, 0x40000000, 0x40000000, 0x40000000);  # 2.0f
var vd: f32v4 = scale2(va);
assert_eq(f32v4_lane0(vd), 0x40800000, "= 4.0f");   # FAILS on x86/aarch64: got 2.0f
```

`scale2(va)` returns `va` (2.0f), not `2·va` (4.0f) — the value-form call
`f32v4_add(v, v)` with the **same value-form local passed twice** collapses to a
single operand. Confirmed on the prior release (v6.4.29) → **pre-existing, not a
.31 regression** (v6.4.31's x86/aarch64 SIMD-return codegen is byte-identical).

## Not-triggered-by

- Distinct args: `f32v4_add(a, b)` is fine (the shipped `simd_f32v4.tcyr` uses
  `scale2(b)` on a splat'd `b` and passes 13/13 — so the trigger is narrow, tied to
  the specific arg local / duplication and did not surface in the corpus).
- Win64 PE: correct (by-pointer ABI).

## Likely cause

The SysV/NEON value-form caller (`PARSE_FNCALL` XMM-routing, parse_fn.cyr ~1202-1250)
records each value-form arg's source local into a scratch table and emits the XMM/V
loads in a second pass. A duplicated source local likely collides in that table /
second-pass ordering so the second operand reads the wrong slot (or the same XMM is
reloaded). Needs a look at the `_fc_simd_table` second-pass emit vs. `_fc_simd_pc_caller`.

## Fix slot

Untriaged — value-form-on-x86 shipped v6.4.4/.28; this is a latent edge. Fold into a
value-form-correctness pass (not the Win64 .31 arc). The cross-OS gate
(`vr01_simd_f32v4_neon.tcyr`) deliberately uses distinct-arg patterns until fixed.
