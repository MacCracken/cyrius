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
| **Version** | **6.4.29** — **SIMD Phase 5: f32v8 on aarch64 works for free (2×NEON fallback).** After .28's f32v4 `EMIT_F32V_LOOP` became real NEON, the aarch64 f32v8 wrappers' 2×128-bit fallback (`f32v_*(n=8)`) works — aarch64 has no 256-bit reg, so 2×NEON IS the correct f32v8. Removed `simd_f32v8` from the strict XFAIL (now passes native arm64, 15/15). Comment-only src edit → cycc byte-identical. `simd_ints` is the last SIMD XFAIL. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,073,616 B (byte-identical — comment-only src edit) · aarch64 1,010,824 B (fixpoint byte-identical) · check.sh **132** · self_compile ~0.6 s |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` I/O guard** (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (.17 CLI) + B (.18 f64) + f64-compare (.19) + C (.20 cross-OS `.cyx`) + cycc_cx cross-native (.22) SHIPPED. Arc COMPLETE + cross-native.** cx compiles + runs portable `.cyx` on all 4 hosts, AND the native cx toolchain (cycc_cx + cxvm) works on macOS/Windows/Linux. Full A→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **SIMD Phase 5 last slot** — aarch64 NEON int-vectors (`simd_ints` → `EMIT_IVEC_BINOP` add/sub/mul .16b/.8h/.4s/.2d + `EMIT_IVEC_DP8` sdot/udot), the last strict-XFAIL. **Then async runtime** (arc 5b, stiva-blocked). (.29 f32v8 free via 2×NEON; .28 f32v4 NEON; .27 folded-stdlib.) Parked: Win64 value-form SIMD params; cx SIMD. |
| **Committed after** | **SIMD Phase 5 → async runtime (arc 5b — CONSUMER-BLOCKED by stiva, NOT v6.8-parked)** → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail. **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
