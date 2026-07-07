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
| **Version** | **6.4.13** — array-typed struct fields R3 (`#derive` for `Vec<#derive-struct>`); the array-typed arc **CLOSES**. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | 1,073,544 B (x86_64 self-host fixpoint; R1→R3 codec generator) · check.sh **130** · self_compile ~577 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **Pin 2 — array-typed struct fields: COMPLETE** (R1 `Vec<T>` fields v6.4.11 · R2 `#derive` Vec\<primitive\> v6.4.12 · R3 `#derive` Vec\<struct\> v6.4.13). **NEXT: review new issues/proposals** (incl. the struct-id 20/21 ↔ `-20/-21` SIMD-sentinel collision), then the committed arcs below. |
| **Paused** | SIMD Pin 1 aarch64 NEON (Phase 5) — deferred within v6.4.x (x86 SIMD complete, v6.4.4–.9) |
| **Committed next** | UEFI Secure Boot signing → function visibility (`pub`/`private`) → Intel-Mac (x86_64 Mach-O) tail |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
