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
| **Version** | **6.4.16** — aarch64 `f64_sin`/`f64_cos` polyfill (attn11 consumer P2 arch-parity), **cut together with v6.4.15 absorber-band** (.15 not separately pushed — both changesets ship in the .16 tag). Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,069,552 B (self-host fixpoint; trig lives in the aarch64 backend + `lib/math.cyr`, neither in the x86 compiler — x86 byte-identical vs .15) · check.sh **131** · self_compile ~577 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` (incl. `vr01_trig_polyfill`; release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **v6.4.15 absorber-band + v6.4.16 aarch64 trig polyfill: SHIPPED.** Trig was a reactive consumer repair (interleaves, uncounted). **NEXT: cx bytecode backend CLI exposure** (user-set order 2026-07-07: absorber → cx CLI → Phase 5 NEON; the trig repair rode ahead per bottom-to-top / consumer-blocking priority). |
| **Next up** | **cx bytecode backend CLI exposure** (interim DX — `cyrius build --target=cx` mirroring `--target=js`, install `cxvm` + a `.cyx` run path, finish cx float ops, decide SIMD-on-cx; a consumer hit the wasm-shaped wall). **Then SIMD Pin 1 aarch64 NEON — Phase 5** (5a f32 → 5b int NEON; un-XFAILs the `simd_*` tcyr on aarch64; x86 SIMD complete v6.4.4–.9). |
| **Committed after** | UEFI Secure Boot signing → function visibility (`pub`/`private`) → Intel-Mac (x86_64 Mach-O) tail. **2026-07-07 horizon**: + scalar-float completion + diagnostics later in 6.4.x · **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency expected to pull into 6.4.x post-NEON per user follow-up) · **v6.6.x = language ergonomics** (defer, const fn, block scoping, bounds mode, trait-bounds gated) · **RISC-V → v6.7/v6.8** |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
