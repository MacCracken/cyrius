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
| **Version** | **6.4.11** — array-typed struct fields R1 (`Vec<T>` handle fields). Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | 1,057,568 B (x86_64 self-host fixpoint) · check.sh **130** · self_compile ~574 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **Pin 2 — array-typed struct fields** (ACTIVE): R1 shipped v6.4.11 → **R2 = `#derive` Vec\<primitive\>** (next) → R3 = `#derive` Vec\<struct\> + svara minor patch |
| **Paused** | SIMD Pin 1 aarch64 NEON (Phase 5) — deferred within v6.4.x (x86 SIMD complete, v6.4.4–.9) |
| **Committed next** | UEFI Secure Boot signing → function visibility (`pub`/`private`) → Intel-Mac (x86_64 Mach-O) tail |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
