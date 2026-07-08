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
| **Version** | **6.4.25** — **aarch64 transcendental gaps closed: `f64_exp2` / `f64_atan` polyfills + Payne-Hanek-lite double-double trig range reduction.** `EF64_EXP2`/`EF64_ATAN` route to new `_f64_exp2_polyfill` (~3e-13) / `_f64_atan_polyfill` (~1e-14); `_f64_sin/cos_polyfill` get a dd reduction for \|x\| ≥ 8192 (exact to ~1e-16 through 1e15, small-angle path byte-identical). aarch64-only compiler change → x86 `cycc` byte-identical. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,073,648 B (self-host fixpoint; **byte-identical to 6.4.24** — x86 fork unaffected; differential codegen-diff=0/343) · aarch64 1,010,896 B (fixpoint byte-identical, qemu) · check.sh **132** · self_compile ~0.6 s |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` I/O guard** (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (.17 CLI) + B (.18 f64) + f64-compare (.19) + C (.20 cross-OS `.cyx`) + cycc_cx cross-native (.22) SHIPPED. Arc COMPLETE + cross-native.** cx compiles + runs portable `.cyx` on all 4 hosts, AND the native cx toolchain (cycc_cx + cxvm) works on macOS/Windows/Linux. Full A→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **SIMD Pin 1 aarch64 NEON — Phase 5** → async runtime (arc 5b, stiva-blocked). (.25 shipped the aarch64 `f64 exp2/atan` + trig Payne-Hanek; opened `aarch64-ganita-inverse-trig-unguard` follow-on — asin/acos/atan2 now unblocked on aarch64.) cx tail: f32 + transcendentals still fail loud. |
| **Committed after** | **SIMD Phase 5 → async runtime (arc 5b — CONSUMER-BLOCKED by stiva, NOT v6.8-parked)** → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail. **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
