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
| **Version** | **6.4.19** — cx f64 comparisons work in conditionals (the Release-B follow-up: root cause was cx's flag-less `EJCC` re-comparing against a stale r1 on the bare-boolean path, NOT the F64 type; fixed cx `ETESTAZ` to set r1=0 + re-wired `EF64_CMP`). Also fixed a latent bare-int-boolean branch bug. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,069,552 B (self-host fixpoint; **cycc byte-identical** — cx work is cx-backend-only; the frontend SESTYPE idea is dead) · check.sh **132** · self_compile ~577 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx portable bytecode target — A (v6.4.17 CLI) + B (v6.4.18 f64 arithmetic + global-var fix) + f64-compare follow-up (v6.4.19) SHIPPED.** cx now compiles + runs real integer/float programs (arithmetic + comparisons + conditionals). **NEXT: Release C — cxvm cross-OS syscall ABI** (guest-syscall ABI cxvm translates per-host so an I/O-doing `.cyx` runs on ecb/cass/pi) + raised 64 KB caps + a `_cx_float_gate`. Full A→B→C in [roadmap.md](roadmap.md) slot 5. |
| **Next up** | **cx Release C — portable cxvm** (guest-syscall ABI per-host + raised code/data caps; makes `.cyx` cross-OS). Remaining cx float tail: f32 conversion + transcendentals (still fail loud). After the cx arc: **SIMD Pin 1 aarch64 NEON — Phase 5**. |
| **Committed after** | UEFI Secure Boot signing → function visibility (`pub`/`private`) → Intel-Mac (x86_64 Mach-O) tail. **2026-07-07 horizon**: + scalar-float completion + diagnostics later in 6.4.x · **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency expected to pull into 6.4.x post-NEON per user follow-up) · **v6.6.x = language ergonomics** (defer, const fn, block scoping, bounds mode, trait-bounds gated) · **RISC-V → v6.7/v6.8** |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
