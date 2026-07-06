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
| **Version** | **6.4.10** (v6.4.x cycle — **frontend-correctness + tooling, the first interim items after the SIMD x86 break point** (aarch64 NEON deferred). TWO bites: **(1) P1 KERNEL-BLOCKER FIX — bare top-level `var X[N]` silently 8× under-sized.** A bare top-level array was N×8 before the first bare top-level statement (pass-1 `PARSE_GVAR_ARR`) but only N bytes after it (pass-2 `PARSE_ARRAY`, fn-local default) → silent 8× under-size → BSS overflow (agnos ring-3 #PF). Fix: `PARSE_ARRAY` (parse_decl.cyr ~61) sizes a bare array N×8 when NOT a fn-local (`GINFN(S) != 1`), matching `PARSE_GVAR_ARR`; fn-locals keep N-byte rounding. **cycc's OWN top-level arrays were affected → TWO-STEP BOOTSTRAP** (cc_fix→cc_fix_b byte-id, fixpoint 1,057,568 B). Differential **codegen-diff=31 / status-diff=0** — 31 programs' top-level arrays correctly GROW to N×8, nothing breaks (safe .bss shift, over-size never under). Regression `toplevel_bare_array_size.tcyr`; closes issues/2026-07-05-toplevel-bare-array-8x-undersize.md. **(2) `cyrius distlib` per-module read cap 256KB → 1MB** — both cbt/commands.cyr sites (flat + --modular) `alloc(262144)`→`alloc(1048576)`, matching cycc's input_buf[1048576]; distlib was rejecting modules cycc compiles fine (shabdakosh 283KB generated CMUdict). cbt-only → cycc unaffected; verified the rebuilt CLI bundles a 405KB module the old rejected; closes the distlib proposal. seed→cybs→cycc byte-id; check.sh 130; ecb+cass+pi SELFHOST_OK; self_compile 556 ms; cycc 1,057,568 B. See CHANGELOG [6.4.10]. **NEXT: more short-term items, then resume Phase 5 aarch64 NEON.**) **Prior:** **6.4.9** = SIMD Phase 4 R2 (f32v8 fma + 8-lane dot + GEMM; first 3-byte VEX; PHASE 4 CLOSED — x86 SIMD complete). **6.4.8** = Phase 4 R1 (f32v8 256-bit AVX2 elementwise, first VEX/AVX). **Earlier releases (6.4.7 back to v5.x): see CHANGELOG.md** — trimmed here (state.md keeps current + ~2 priors). |
