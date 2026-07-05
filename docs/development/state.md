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
| **Version** | **6.4.7** (v6.4.x cycle — **SIMD arc Phase 3b: value-form typed integer ops + int8 widening dot (b1.58 GEMM inner loop)** — the SECOND of the planned 3a/3b split; the integer-SIMD arc CLOSES here. **PARAM-MASK REDESIGN (the byte-identity-sensitive half — differential 0/331):** `_classify_param_type`/`_classify_return_type` gained integer arms (structured-descriptor sentinels), the def-fold/prescan set the 2-bit `_fnt_simdmask` **class 1 for ANY `≤ −2048` vector param** (not just f64v2), and the caller class-1 arg type-check relaxed from the exact f64v2 sentinel (`−20`) to `_is_simd128(S,arg)` — any 16-byte vector — while **f32v4 (mask code 3) stays STRICT** so `simd_vec_reject` still rejects a mismatched SIMD arg. Byte-identical because the only pre-existing class-1 params were f64v2-called-with-f64v2-args, so widening the accepted set changes no live codegen. **VALUE-FORM OPS (lib/simd.cyr, +14 fns):** `i32v4_add`/`_sub`/`_mul(a,b)` + `i32v4_lane{0..3}(v)`, `i16v8`/`i8v16`/`i64v2` add/sub(/mul) — VALUE params route through XMM as a full 16 bytes (lane 3 survives); value-form SIMD args must be **bare local IDENTs** (not call temps, same as f32v4). **WIDENING MAC = `iv_dp8(a,b,n)`** (token 146): u8·i8→i32 dot, `EMIT_IVEC_DP8` = `pxor` accum + `pcmpeqw`/`psrlw` ones + 16-lane `movups`/`pmaddubsw`/`pmaddwd`/`paddd` loop + `phaddd`×2 + `movd eax` + **`movsxd rax,eax` (sign-extend — FOUND-BY-TESTING: a −1 int8 weight came back `0xFFFFFF88`=−136 zero-ext)**. The b1.58 GEMM inner loop; `bench_i8_gemm.bcyr` 64³ **~30×** (28.7µs SIMD vs 879.5µs scalar). `simd_ints.tcyr` 11→21 asserts (value-form + signed iv_dp8). aarch64/cx stub → x86-only phase (`simd_ints` stays XFAIL). check.sh 129; self-host fixpoint + seed→cybs→cycc byte-identical; ecb+cass+pi SELFHOST_OK; self_compile 561 ms; cycc 1,049,352 B. See CHANGELOG [6.4.7].) **Prior:** **6.4.6** = SIMD Phase 3a (int vector types i8v16/i16v8/i32v4/i64v2+u* + packed iv_add/sub/mul; descriptor-driven ABI generalization, differential 0/328; fixed a rough-scan retptr SIGSEGV descriptor-driven). **6.4.5** = SIMD Phase 2 (f32v_fmadd + f32v_dot; bench_f32_gemm ~27×). **Earlier releases (6.4.4 back to v5.x): see CHANGELOG.md** — trimmed here (state.md keeps current + ~2 priors; the rest is canonical in CHANGELOG). |
