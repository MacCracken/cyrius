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
| **Version** | **6.4.21** — repair batch: **LEXID identifier-dedup cap 16384 → 65536** (unblocks large multi-bundle consumers like stiva; `lexid_entries` relocated to arena-top `0x7300000`, all 7 forks' arenas extended to `0x7400000`, two-step bootstrap, cycc byte-identical) + **TLS 1.3 server `get_version`** now records the negotiated 0x0304 (`respond_hello`). Signed-global sign-ext was assessed (~LEXID-sized) and DEFERRED to its own slot. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,069,552 B (self-host fixpoint; **cycc byte-identical** — LEXID is a runtime-heap relocation, not codegen; differential 340/340) · check.sh **132** · self_compile ~577 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` I/O guard** (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (v6.4.17 CLI) + B (v6.4.18 f64 arithmetic + global-var fix) + f64-compare follow-up (v6.4.19) + C (v6.4.20 cross-OS `.cyx`) SHIPPED. Arc COMPLETE.** cx now compiles integer/float programs (arithmetic + comparisons + conditionals) and RUNS portable `.cyx` doing I/O on all four hosts via per-target cxvm. Full A→B→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **cx `cycc_cx` cross-native macOS fix** (`issues/2026-07-07-cycc_cx-cross-native-macho-pe.md`) → **SIMD Pin 1 aarch64 NEON — Phase 5** → **async runtime (arc 5b, stiva-blocked)**. Deferred repairs with recorded scope: signed sub-i64 global sign-ext (needs an 8th var-family table, ~LEXID-sized). cx tail: f32 conversion + transcendentals still fail loud. |
| **Committed after** | **SIMD Phase 5 → async runtime (arc 5b — CONSUMER-BLOCKED by stiva, NOT v6.8-parked)** → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail. **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
