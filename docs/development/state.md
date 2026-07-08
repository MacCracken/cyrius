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
| **Version** | **6.4.24** — **P1: struct field access silently read a global var when the field name shadowed a top-level var.** The `X.Y` disambiguation loaded global `Y` whenever Y was a global var, ignoring base X → `bc.exit_code` read the global `exit_code` (0) not Container's field @+72. Root cause was NOT the two-struct collision that was filed (nor a buffer overflow) — found via cycc instrumentation in the live stiva unit. Fix: if base X is a known var, `X.Y` is a field access. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,073,648 B (self-host fixpoint; **byte-identical** — cycc has no field-shadows-global pattern; differential codegen-diff=1/status-diff=0 = contained fix) · check.sh **134** · self_compile ~0.6 s |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` I/O guard** (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (.17 CLI) + B (.18 f64) + f64-compare (.19) + C (.20 cross-OS `.cyx`) + cycc_cx cross-native (.22) SHIPPED. Arc COMPLETE + cross-native.** cx compiles + runs portable `.cyx` on all 4 hosts, AND the native cx toolchain (cycc_cx + cxvm) works on macOS/Windows/Linux. Full A→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **.25 = the aarch64 issues** (`f64 exp2/atan` hard-error → add aarch64 polyfills + trig Payne-Hanek extreme-|x|) → then **SIMD Pin 1 aarch64 NEON — Phase 5** → async runtime (arc 5b, stiva-blocked). cx tail: f32 + transcendentals still fail loud. |
| **Committed after** | **SIMD Phase 5 → async runtime (arc 5b — CONSUMER-BLOCKED by stiva, NOT v6.8-parked)** → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail. **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
