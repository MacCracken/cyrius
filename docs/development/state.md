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
| **Version** | **6.4.27** — **P1: agnos `file_open` folded `O_RDWR` → `AO_WRONLY`, so reads on an RDWR fd failed.** `lib/io.cyr:80` now passes the access mode through (`ao = ao \| (flags & 3)`; O_/AO_ are 1:1). Silent miscompile on agnos only (patra "cannot read header" under sit/mirshi); Linux/macOS/Windows untouched. mirshi-verified (fixed→42, buggy→4). Lib-only → cycc byte-identical. The `lib/sakshi.cyr:88` DUPLICATE is a folded fold → fixed in the folded-stdlib repair pass. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,073,616 B (byte-identical — lib-only change, io.cyr not in cycc; all forks unchanged → cross-OS byte-identical-by-construction) · check.sh **132** · self_compile ~0.6 s |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` I/O guard** (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (.17 CLI) + B (.18 f64) + f64-compare (.19) + C (.20 cross-OS `.cyx`) + cycc_cx cross-native (.22) SHIPPED. Arc COMPLETE + cross-native.** cx compiles + runs portable `.cyx` on all 4 hosts, AND the native cx toolchain (cycc_cx + cxvm) works on macOS/Windows/Linux. Full A→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **SIMD Pin 1 aarch64 NEON — Phase 5** → async runtime (arc 5b, stiva-blocked). (Folded-stdlib repair pass DONE in .27: sakshi 2.4.5 / sigil 3.10.1 / ganita 1.0.3 / yukti 2.2.9 fixed-at-source + re-vendored; sandhi premise-disproved. 7 clean: bayan/mabda/niyama/patra/sankoch/vani/yantra.) cx tail: f32 + transcendentals still fail loud. |
| **Committed after** | **SIMD Phase 5 → async runtime (arc 5b — CONSUMER-BLOCKED by stiva, NOT v6.8-parked)** → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail. **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
