# Cyrius — Current State

> Refreshed every release. This file is **state** (volatile) — a SNAPSHOT of where the
> project is right now, bumped via `version-bump.sh`. It deliberately holds **no
> per-release narrative** (canonical in [`CHANGELOG.md`](../../CHANGELOG.md)) and **no
> backlog** (the full pin sequence + length map is in [`roadmap.md`](roadmap.md); parked /
> v7+ items in [`roadmap-future.md`](roadmap-future.md)). CLAUDE.md holds the durable
> preferences / process / procedures.

## Current state

| | |
|---|---|
| **Version** | **6.4.31** — **Win64 value-form SIMD params & returns (last PE SIMD-ABI gap).** `f32v4`/`f64v2`/`f64v4`/`f32v8` + integer vectors now work as fn params + return values on Win64 PE (MS x64 by-pointer param copy-in `ESTOREPARM_SIMD_WIN64` + retptr return), not just `_ptr` wrappers. `simd_f32v4` 13/13 + `simd_ints` 21/21 on **real cass**. Fixed 2 latent bugs: SIMD-return convention broken on PE since v6.4.6, and a regalloc disp↔index off-by-one on retptr fns (both no-op / byte-identical off-PE). Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,077,592 B (+3,976 for the value-form ABI codegen) · seed-derive byte-identical · check.sh **132** · self_compile ~611 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` I/O guard** (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **Win64 value-form SIMD (.31) — SHIPPED.** `f32v4`/`f64v2`/`f64v4`/`f32v8` + int vectors work as fn params + returns on Win64 PE (by-pointer param + retptr return), verified on real cass (13/13 + 21/21). The prior cx portable-bytecode arc (.17–.22) is COMPLETE. |
| **Next up** | **cx SIMD (.32)** then **async runtime — arc 5b (.33)** (tokio-parity primitives; CONSUMER-BLOCKED by stiva — `issues/2026-07-07-async-runtime-tokio-parity-gaps.md`). **SIMD Pin 1 COMPLETE on aarch64 AND Win64 PE.** Filed follow-up: value-form `f(v,v)` duplicate-arg bug on x86/aarch64 (`issues/2026-07-08-valueform-simd-duplicate-arg-x86.md`, pre-existing). |
| **Committed after** | **SIMD Phase 5 → async runtime (arc 5b — CONSUMER-BLOCKED by stiva, NOT v6.8-parked)** → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail. **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
