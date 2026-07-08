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
| **Version** | **6.4.30** — **SIMD Phase 5 COMPLETE: integer vectors on aarch64 NEON.** `EMIT_IVEC_BINOP` (width-dispatched add/sub/mul `.16b/.8h/.4s/.2d`; mul i16/i32 only) + `EMIT_IVEC_DP8` (uxtl/sxtl+smlal int8 widening dot) + a fix to the STUR/LDUR Q imm9 large-frame limit that had blocked `simd_ints` from compiling on aarch64. **No SIMD XFAILs remain** (f32v4/.28, f32v8/.29, int/.30). x86 cycc byte-identical; aarch64 self-host byte-identical. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,073,616 B (byte-identical — aarch64 fork only) · aarch64 self-host byte-identical · check.sh **132** · self_compile ~0.6 s |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` I/O guard** (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (.17 CLI) + B (.18 f64) + f64-compare (.19) + C (.20 cross-OS `.cyx`) + cycc_cx cross-native (.22) SHIPPED. Arc COMPLETE + cross-native.** cx compiles + runs portable `.cyx` on all 4 hosts, AND the native cx toolchain (cycc_cx + cxvm) works on macOS/Windows/Linux. Full A→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **Async runtime — arc 5b** (tokio-parity primitives; CONSUMER-BLOCKED by stiva, our Docker project — `issues/2026-07-07-async-runtime-tokio-parity-gaps.md`). **SIMD Pin 1 is now COMPLETE on aarch64** (f32v4 .28 / f32v8 .29 / int .30 — no SIMD XFAILs left). Parked: Win64 value-form SIMD params; cx SIMD. |
| **Committed after** | **SIMD Phase 5 → async runtime (arc 5b — CONSUMER-BLOCKED by stiva, NOT v6.8-parked)** → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail. **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
