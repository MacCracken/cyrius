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
| **Version** | **6.4.28** — **SIMD Phase 5: f32v4 packed ops on aarch64 NEON.** Real `EMIT_F32V_LOOP` (`.4s` fadd/fsub/fmul), `EMIT_F32V_FMADD` (fmul+fadd, x86-rounding-matched), `EMIT_F32V_DOT` (fmul+fadd + two faddp reduces) replace the aarch64 stubs; encodings llvm-mc-verified; mirrors the existing `EMIT_F64V_LOOP`. Flips the strict `simd_f32v4` XFAIL → pass on native arm64. x86 cycc + aarch64 self-host both byte-identical. Surfaced (+filed) a Win64 value-form-SIMD-param gap → the cross-OS gate uses the flat-array `vr01_simd_f32v4_neon`. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,073,616 B (byte-identical — aarch64 emit not in the x86 fork) · aarch64 1,010,824 B (fixpoint byte-identical, qemu) · check.sh **132** · self_compile ~0.6 s |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` I/O guard** (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (.17 CLI) + B (.18 f64) + f64-compare (.19) + C (.20 cross-OS `.cyx`) + cycc_cx cross-native (.22) SHIPPED. Arc COMPLETE + cross-native.** cx compiles + runs portable `.cyx` on all 4 hosts, AND the native cx toolchain (cycc_cx + cxvm) works on macOS/Windows/Linux. Full A→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **SIMD Phase 5 remainder** — aarch64 NEON int-vectors (`simd_ints` → `EMIT_IVEC_BINOP`/`EMIT_IVEC_DP8`) then f32v8 2×NEON (`simd_f32v8` → `EMIT_F32V8_*`), both still strict-XFAIL'd. **Then async runtime** (arc 5b, stiva-blocked). (.28 landed f32v4 NEON. .27 folded-stdlib repair done.) Parked follow-ons: Win64 value-form SIMD params; cx SIMD. |
| **Committed after** | **SIMD Phase 5 → async runtime (arc 5b — CONSUMER-BLOCKED by stiva, NOT v6.8-parked)** → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail. **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
