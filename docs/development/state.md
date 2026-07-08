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
| **Version** | **6.4.20** — cx arc C: a portable `.cyx` doing real I/O runs on ALL FOUR hosts (x86-Linux, aarch64/pi, macOS/ecb, Windows/cass), verified on real hardware. Two cxvm bugs fixed: the `open` pointer-slot (fixed s3=flags instead of s2=path — EFAULT on all hosts) + Windows arity-bucket miss (fixed argc-6 shape hit no PE route → -ENOSYS; now arity-correct dispatch). Caps 64 KB → 1 MB + overflow probe. cxvm ships in macOS/Windows tarballs. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,069,552 B (self-host fixpoint; **cycc byte-identical** — cx work is cx/cxvm-only, off the self-host chain) · check.sh **132** · self_compile ~577 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` I/O guard** (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (v6.4.17 CLI) + B (v6.4.18 f64 arithmetic + global-var fix) + f64-compare follow-up (v6.4.19) + C (v6.4.20 cross-OS `.cyx`) SHIPPED. Arc COMPLETE.** cx now compiles integer/float programs (arithmetic + comparisons + conditionals) and RUNS portable `.cyx` doing I/O on all four hosts via per-target cxvm. Full A→B→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **SIMD Pin 1 aarch64 NEON — Phase 5.** cx tail (all deferred + filed, not blocking): the cx **compiler** `cycc_cx` cross-native on macOS/Windows (`issues/2026-07-07-cycc_cx-cross-native-macho-pe.md`); f32 conversion + transcendentals (still fail loud). |
| **Committed after** | UEFI Secure Boot signing → function visibility (`pub`/`private`) → Intel-Mac (x86_64 Mach-O) tail. **2026-07-07 horizon**: + scalar-float completion + diagnostics later in 6.4.x · **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency expected to pull into 6.4.x post-NEON per user follow-up) · **v6.6.x = language ergonomics** (defer, const fn, block scoping, bounds mode, trait-bounds gated) · **RISC-V → v6.7/v6.8** |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
