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
| **Version** | **6.4.32** — **cx SIMD codegen: packed-verb emitters + the frame-addressing fixes they needed.** The cx bytecode backend gained real per-lane emitters for every flat-array SIMD verb (`f64v_*`/`f32v_*`/`iv_*`: add/sub/mul/div, dot, fmadd, scale, axpy, sqrt, int8 dp8) — portable `.cyx` is now a byte-exact SIMD oracle matching x86 SSE / aarch64 NEON. New cxvm opcodes `f32widen`/`f32narrow`/`fsqrt` (0x66–0x68). Fixed 2 pre-SIMD cx bugs: `ELOAD_LOCAL_ADDR` was a `return 0` stub (`&local` aliased to addr 0), and the scalar load/store disp path omitted the regalloc/ret_stash reservation `EFLADDR` already had (SIMD stash collided with array storage) — unified via `_cx_ldisp`. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,077,592 B (**byte-identical to v6.4.31** — cx-backend-only change) · seed-derive byte-identical · check.sh **132** · self_compile ~616 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` round-trip now exercises SIMD** (`f64v_add`+`f64v_sqrt` over local arrays → exit 42 on each host's native cxvm, not a bare write) (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **cx SIMD (.32) — SHIPPED.** Every flat-array packed verb now emits on the cx bytecode backend (13 stubs → real per-lane loops); portable `.cyx` is a byte-exact SIMD correctness oracle. Fixed 2 latent cx local-addressing bugs it exposed. The prior Win64 value-form SIMD (.31) + cx portable-bytecode (.17–.22) arcs are COMPLETE. |
| **Next up** | **async runtime — arc 5b (.33)** (tokio-parity primitives; CONSUMER-BLOCKED by stiva — `issues/2026-07-07-async-runtime-tokio-parity-gaps.md`). **SIMD Pin 1 COMPLETE on x86 + aarch64 + Win64 PE + cx.** Filed pre-existing follow-ups: value-form `f(v,v)` dup-arg bug (`issues/2026-07-08-valueform-simd-duplicate-arg-x86.md`); cx value-form SIMD params/returns (`issues/2026-07-09-cx-valueform-simd-params-returns.md`); cx `var x = assert_summary()` mis-capture (`issues/2026-07-09-cx-var-capture-after-global-mutation.md`). |
| **Committed after** | **SIMD Phase 5 → async runtime (arc 5b — CONSUMER-BLOCKED by stiva, NOT v6.8-parked)** → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail. **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
