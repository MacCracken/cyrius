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
| **Version** | **6.4.8** (v6.4.x cycle — **SIMD arc Phase 4 R1: f32v8 (256-bit, 8× f32) on AVX2 — the FIRST VEX/AVX in the toolchain**. First of a planned 2-release Phase-4 split (R1 = VEX substrate + elementwise + CPUID runtime fallback; R2 = fmadd + 8-lane dot + GEMM bench). Before this the compiler emitted ZERO VEX (`decode.cyr`: "no AVX/VEX"); the existing "256-bit" f64v4 is a count-driven 128-bit SSE2 loop, not AVX. **EMIT_F32V8_LOOP** = the f32v4 loop widened to 256-bit VEX — 128-bit SSE bytes + a 2-byte VEX prefix (C5 FC), 8 f32/iter (`rsi += 8`), `vzeroupper` (C5 F8 77) on exit; `f32v8_add`/`_sub`/`_mul` → `vaddps`/`vsubps`/`vmulps ymm` (tokens 147-149). **Every VEX byte llvm-mc-verified** (the `vvvv` field — 1's-complement of src1 — is the invisible wrong-register trap). **f32v8 type** = sentinel −2153 (`_vec_desc` → 4-slot/laneb-4). **256-bit value-return ABI** generalized from exact −21 (f64v4) to `_is_simd256` in the return (parse_fn) + receive (parse_decl) paths → f32v8 shares f64v4's 32-byte/EFLLOAD_F64V4_PAIR ABI, **byte-identical for f64v4** (isolation-differential codegen-diff=0/status-diff=0); construct/return verified on real aarch64 (qemu). **AVX2 RUNTIME FALLBACK** (AVX2 not x86-64 baseline — `vaddps ymm` #UDs pre-AVX2): `simd_has_avx2()` = CPUID leaf 7 EBX bit 5, a byte-for-byte clone of sigil's `_sha_ni_cpuid_probe` (idempotent, no CAS latch); the `f32v8_*_ptr` wrappers branch INSIDE the single call site (AVX2 → `vaddps ymm`; else `f32v_*(…,8)` = 2×SSE) → each path emitted once, zero bloat; both paths value-verified. **cycc has no f32v8 → stays pure SSE2, self-hosts byte-identical everywhere** (fixpoint 1,049,352 B). Lib +14 (`f32v8_make/_splat/_lane0..7_ptr/_add/_sub/_mul_ptr`, pointer-form first). Tests: `simd_f32v8.tcyr` (x86, XFAIL aarch64 — qemu 5 construct-pass/5 arith-fail) + `vr01_f32v8_ctor.tcyr` (x86 6/6 + aarch64 6/6) + **disasm gate** (host-CPU-independent VEX-byte check; check.sh 129→130). **DROPPED from R1:** the planned decode.cyr VEX length-decode — not needed (undecodable VEX → DCE fail-safe-refuses dead f32v8 wrappers) and it broke DCE-mode byte-identity via a PRE-EXISTING `DECODE_LEN` bug (mis-lengths no-ModRM 0F opcodes SYSCALL/CPUID → mis-aligns onto a spurious 0xC5); filed `issues/2026-07-05-decode-len-mislengths-no-modrm-0f-opcodes.md`. **TRACKED (docs only, user premise-check):** the cyrius-x (cx) bytecode backend (born as commit "wasm what") is built/self-hosting/gated but has NO CLI surface (no `--target=cx`, cxvm uninstalled) → `proposals/2026-07-05-cx-bytecode-cli-exposure.md` + roadmap-future + vidya gotcha, post-SIMD. check.sh 130; seed→cybs→cycc byte-id; ecb+cass+pi SELFHOST_OK; self_compile 566 ms; cycc 1,049,352 B. See CHANGELOG [6.4.8].) **Prior:** **6.4.7** = SIMD Phase 3b (value-form typed int ops + iv_dp8 int8 widening dot; integer-SIMD arc closed). **6.4.6** = SIMD Phase 3a (int vector types + packed iv_add/sub/mul). **Earlier releases (6.4.5 back to v5.x): see CHANGELOG.md** — trimmed here (state.md keeps current + ~2 priors). |
