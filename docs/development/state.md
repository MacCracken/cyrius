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
| **Version** | **6.4.14** — struct-id 20/21 ↔ f64v2/f64v4 SIMD-sentinel collision fix (consumer P1) + cross-OS gate hardening. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | 1,073,544 B (x86_64 self-host fixpoint; codegen-neutral vs .13) · check.sh **130** · self_compile ~570 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **Pin 2 — array-typed struct fields: COMPLETE** (v6.4.11–.13). **struct-sid 20/21 P1: SHIPPED** (v6.4.14 — f64v2/f64v4 folded into the descriptor band, retiring the flat −20/−21). **NEXT: SIMD Pin 1 aarch64 NEON (Phase 5)** — un-pause below. |
| **Next up** | **SIMD Pin 1 aarch64 NEON — Phase 5** (5a f32 NEON → 5b int NEON; un-XFAILs the `simd_*` tcyr on aarch64). x86 SIMD complete (v6.4.4–.9). |
| **Committed after** | UEFI Secure Boot signing → function visibility (`pub`/`private`) → Intel-Mac (x86_64 Mach-O) tail |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
