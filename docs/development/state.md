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
| **Version** | **6.4.22** — cx `cycc_cx` **cross-native on macOS + Windows**: the cx bytecode COMPILER faulted at runtime on macOS/PE (its arena used `brk`, which XNU/Win32 lack) — now per-target `#ifdef` (mmap on macho/PE, brk on Linux). Verified on ecb + cass: native `cycc_cx` compiles a `.cyr`→`.cyx` the native `cxvm` runs to exit 42. `cycc_cx` re-added to all 3 tarball builders + a native compile→run round-trip gated in `cross-os-selfhost.sh`. cycc byte-identical (`main_cx.cyr` off the self-host chain). Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,069,552 B (self-host fixpoint; **cycc byte-identical** — LEXID is a runtime-heap relocation, not codegen; differential 340/340) · check.sh **132** · self_compile ~577 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` I/O guard** (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (.17 CLI) + B (.18 f64) + f64-compare (.19) + C (.20 cross-OS `.cyx`) + cycc_cx cross-native (.22) SHIPPED. Arc COMPLETE + cross-native.** cx compiles + runs portable `.cyx` on all 4 hosts, AND the native cx toolchain (cycc_cx + cxvm) works on macOS/Windows/Linux. Full A→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **SIMD Pin 1 aarch64 NEON — Phase 5** → **async runtime (arc 5b, stiva-blocked)**. Near-term correctness repairs (own slots, scope recorded): signed sub-i64 global sign-ext (needs an 8th var-family table, ~LEXID-sized); struct-field-offset collision (P1). cx tail: f32 conversion + transcendentals still fail loud. |
| **Committed after** | **SIMD Phase 5 → async runtime (arc 5b — CONSUMER-BLOCKED by stiva, NOT v6.8-parked)** → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail. **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
