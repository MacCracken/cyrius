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
> 4–6, Intel-Mac 2–4; **none a release-blocker**). **The SIMD compute arc (Pin 1) — x86 portion
> is COMPLETE** (6 releases, v6.4.4→v6.4.9: f32v4 128-bit → f32 matmul → integer vectors +
> int8 widening dot → f32v8 256-bit AVX2 elementwise + FMA + dot; first VEX/AVX the toolchain
> ever emitted). **⏸ SIMD BREAK POINT (user 2026-07-05): the x86 SIMD portion is done and the
> arc is intentionally PAUSED. Phase 5 (aarch64 NEON: fmla/sdot + cx/PE) is DEFERRED, to resume
> later in v6.4.x** after interim items — pre-scoped as a mechanical NEON mirror of the existing
> `EMIT_F64V_*` aarch64 code, a planned 2-release split (5a f32 NEON, 5b integer NEON + `iv_dp8`;
> `simd_f32v4`/`simd_ints`/`simd_f32v8` stay XFAIL on ARM until then). **NOW: array-typed struct
> fields (Pin 2) is ACTIVE — R1 shipped v6.4.11** (`Vec<T>` handle fields: parse + metadata +
> access); **R2 = `#derive` Vec<primitive>, R3 = `#derive` Vec<struct> + svara minor patch.**
> (Interim before it: v6.4.10 = bare-top-level-array under-size fix + distlib read-cap bump.)
> **REMAINING committed arcs (order fixed 2026-07-03): UEFI Secure Boot signing → function
> visibility (`pub`/`private`) → Intel-Mac (x86_64 Mach-O) tail.** Reactive **agnos +
> consumer-filed repairs interleave as SEPARATE slots** (not counted; more agnos expected).
> v7-parked items (LEGAL-01, DWARF, incremental compilation, public release) stay in
> [roadmap-future.md](roadmap-future.md). See [roadmap.md](roadmap.md) for the full pin +
> length map.

| | |
|---|---|
| **Version** | **6.4.11** (v6.4.x cycle — **array-typed struct fields R1: `Vec<T>` handle fields.** First release of the Pin 2 arc (3-release `Vec<T>`-handle plan: R1 parse+metadata+access · R2 `#derive` Vec<primitive> · R3 `#derive` Vec<struct> + svara minor patch). Struct/union fields can now be declared `Vec<T>` (e.g. `struct S { xs: Vec<i64>; }`) — previously a hard parse error. A `Vec<T>` field is an **8-byte handle slot** (pointer to the heap Vec), concrete element type T recorded in a **far-negative ftype sentinel** (`MKVEC = (0-0x50000)-elem`, decoded by `IS_VEC_FIELD` (window `(-0x80000,-0x40000]`) / `VEC_ELEM` BEFORE any ft>0/ft<0 path — **OOB-safe by construction** per an adversarial 9-site `GETFTYPE` guard-audit: **0 guards needed**). Field load/store + struct-literal init (local+global) work; because the sentinel is NEGATIVE, struct-init flows through the existing `else`→`FIELDSZ`→8 path with **NO `PARSE_STRUCT_INIT`/`EMIT_GVAR_INITS` edit** (unlike Str, a positive sid that hit the flatten trap). **Fixed** a bare `.field` load truncating the 8-byte handle to 32 bits — the `-width` sign-extend at parse_decl.cyr:404 fired on the negative sentinel → `movsxd`; guarded with `IS_VEC_FIELD`. Found by the audit (the happy-path test used raw `load64(&s+off)`, never `.field`); locked by `vec_struct_field.tcyr` (14 asserts, proven fail-on-bug: pre-fix `.field` load = -354418648 vs full handle → segfault). Syntax `Vec<T>` (not `T[]`) so the type string survives the `#derive` pre-parser for R2/R3; #derive+Vec is R2/R3; Vec fields gated to non-generic structs in R1. cycc byte-id (size unchanged, fixpoint 1,057,568 B); seed→cybs→cycc byte-id; check.sh 130; ecb+cass+pi SELFHOST_OK; self_compile 574 ms. See CHANGELOG [6.4.11]; design `proposals/2026-07-06-array-typed-struct-fields-design.md`. **NEXT: R2 = `#derive` for Vec<primitive>.**) **Prior:** **6.4.10** = frontend-correctness + tooling (P1 bare-top-level-array 8× under-size fix + `distlib` read-cap 256KB→1MB). **6.4.9** = SIMD Phase 4 R2 (f32v8 fma + 8-lane dot; first 3-byte VEX; PHASE 4 CLOSED — x86 SIMD complete). **Earlier releases (6.4.8 back to v5.x): see CHANGELOG.md** — trimmed here (state.md keeps current + ~2 priors). |
