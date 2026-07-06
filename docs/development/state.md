# Cyrius — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable);
> this file is **state** (volatile). Bumped via `version-bump.sh` post-hook.
>
> **Consolidated 2026-06-08 (v6.1.4):** the per-patch session-close log
> (104 entries, ~5,600 lines back to v5.x) + the stale v6.0.4-frozen
> structured sections were pruned — that detail is canonical in
> [`CHANGELOG.md`](../../CHANGELOG.md) (per-patch) and
> [`completed-phases.md`](completed-phases.md) (arc retrospective). This file
> now holds only the **active cycle** + current state.

## Current state

> **v6.4.x ACTIVE — the ABI / Language-Features minor** (opened at the v6.3.45 → v6.4.0
> cut, 2026-07-03). v6.3.x (Language Refinements — closures/generics/async/native-float +
> deps-model + bare-metal + perf + cross-OS hardening) **CLOSED at v6.3.45**; its slot table
> is canonical in [CHANGELOG.md](../../CHANGELOG.md).
> **Committed opening sequence** (ORDER fixed 2026-07-03; design chosen at arc-open):
> **integer SIMD (ML/AI) → array-typed struct fields → UEFI Secure Boot signing (gnoboot) →
> function visibility (`pub`/`private`) → Intel-Mac (x86_64 Mach-O) toolchain tail.**
> **Conservatively ~17–26 `.NN` releases for the opening sequence — v6.4.x is a LONG minor**
> (code-grounded scoping 2026-07-04: int-SIMD 5–7, array-fields 3–4, UEFI 3–5, pub/private
> 4–6, Intel-Mac 2–4; **none a release-blocker**). **PINNED immediate: integer SIMD** (pin the
> type-class encoding first — the `-20/-21` pscale sentinel + 2-bit param mask can't hold 8
> int vector types) **+ array-typed struct fields** (pin the `T[N]`-inline-vs-`Vec<T>`-handle
> representation fork). Reactive **agnos + consumer-filed repairs interleave as SEPARATE
> slots** (not counted; 3 already — .0 de-risk / .1 alloc_reset / .2 agnos audio; more agnos
> expected). v7-parked items (LEGAL-01, DWARF, incremental compilation, public release) stay
> in [roadmap-future.md](roadmap-future.md). See [roadmap.md](roadmap.md) for the full pin +
> length map.

| | |
|---|---|
| **Version** | **6.4.9** (v6.4.x cycle — **SIMD arc Phase 4 R2: f32v8 fused multiply-add + 8-lane horizontal dot + f32 GEMM bench — PHASE 4 CLOSES** (f32 SIMD now complete on x86: f32v4 128-bit + f32v8 256-bit, elementwise + FMA + dot). R2 lands the **first 3-byte VEX (C4)** the toolchain emits (R1 was 2-byte C5 only). **`f32v8_fma(dst,a,b,c,n)`** (token 150) → `EMIT_F32V8_FMADD` = **`vfmadd231ps ymm` (C4 E2 7D B8 D1)** — FMA3, 0F38 map, single-rounding fused MAC (matmul inner loop). **`f32v8_dot(a,b,n)`** (token 151) → `EMIT_F32V8_DOT` accumulates `vmulps`/`vaddps ymm`, then the **8-lane reduce the two-haddps f32v4 trick CAN'T do** (haddps never crosses the 128-bit lane split): `vextractf128 xmm1,ymm2,1` (C4 E3 7D 19 D1 01) + `vaddps xmm2,xmm2,xmm1` (**C5 E8 58 D1 — L=0/128-bit** fold) + `vzeroupper` + the proven f32v4 `haddps`×2/`movd eax` tail. **Every VEX byte llvm-mc-verified + disasm-gated.** **`simd_has_fma()`** — vfmadd231ps needs a DIFFERENT CPUID bit than AVX2: **leaf 1 ECX bit 12** (FMA), not leaf 7 EBX bit 5; probe = byte-for-byte clone of sigil's `_aes_ni_cpuid_probe` (leaf 1 ECX), bit 12 not 25. `f32v8_fma_ptr` gates on it (fallback `f32v_fmadd`=mulps+addps, 2 roundings — can differ 1 ULP from fused, so wrappers/tests use exact-product inputs); `f32v8_dot_ptr` gates on `simd_has_avx2()` (fallback `f32v_dot`). api-surface +3. **`bench_f32v8_gemm.bcyr`** 64³ GEMM: 256-bit AVX2 (`f32v8_dot`) vs 128-bit SSE (`f32v_dot`) = **~1.48×** (40.0µs vs 59.0µs; sub-2× — fixed per-cell `vextractf128`+reduce overhead dilutes the 8-vs-4-lane win). `simd_f32v8.tcyr` 10→15 (fma/dot AVX2 + SSE-fallback). cycc has no f32v8 → pure SSE2, self-hosts byte-identical (fixpoint 1,057,544 B); compiler change differential-green (codegen-diff=0 — new emit fires only for tokens 150/151). check.sh 130; seed→cybs→cycc byte-id; ecb+cass+pi SELFHOST_OK; self_compile 563 ms; cycc 1,057,544 B. See CHANGELOG [6.4.9]. **NEXT: Phase 5 — aarch64 NEON (`fmla`/`sdot`) + cx/PE, un-XFAILs simd_f32v4/simd_ints/simd_f32v8.**) **Prior:** **6.4.8** = SIMD Phase 4 R1 (f32v8 256-bit AVX2 elementwise, first VEX/AVX; 256-bit value-return ABI → `_is_simd256`; `simd_has_avx2()` + fallback; decode.cyr VEX dropped). **6.4.7** = SIMD Phase 3b (value-form int ops + iv_dp8; integer-SIMD arc closed). **Earlier releases (6.4.6 back to v5.x): see CHANGELOG.md** — trimmed here (state.md keeps current + ~2 priors). |
