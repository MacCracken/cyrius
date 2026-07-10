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
| **Version** | **6.4.35** — **async runtime P1: timers — `async_with_timeout` + `async_interval`.** The first tokio-parity primitive on the F1/F2 foundation. **`async_with_timeout(rt, handle, ms)`** races a spawned task against a deadline timerfd (via a generalized two-handle `_async_pump(rt, until_a, until_b)` + a deadline sentinel task) → 1 if it completes in time (result joinable), 0 if it times out (the pending task is retired). **`async_interval(rt, fp, arg, ms, tok)`** invokes a callback every `ms` until the cancel-token cell `tok` is set. Both on a CLOCK_MONOTONIC timerfd; `async_agnos.cyr` mirrors degraded (no timerfd on the serial client model). All lib-only — cycc byte-identical modulo the version string. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,077,592 B (byte-identical to v6.4.34 **modulo the version string** — the .35 work is lib-only, no compiler-logic `src/` change) · seed-derive byte-identical (cycc machine-derivable from the 29 KB seed) · check.sh **135** · self_compile 611 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` round-trip now exercises SIMD** (`f64v_add`+`f64v_sqrt` over local arrays → exit 42 on each host's native cxvm, not a bare write) (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **async runtime arc 5b — F1 (.33) + F2 (.34) + P1 timers (.35) SHIPPED.** Foundation: F1 epoll reactor + `async_wait_fd`; F2 task substrate (result capture + `task_join`/JoinHandle, multi-arg via Futures). First primitive: P1 timers (`async_with_timeout` combinator + `async_interval`). Arc is **FOUNDATION-FIRST** (reactor + substrate before primitives); IOCP-Windows folded in AFTER gap coverage; extraction to a `tantu` repo deferred to a later minor. cx SIMD (.32) + Win64 value-form SIMD (.31) arcs COMPLETE. |
| **Next up** | **async arc 5b — remaining tokio-parity primitives (P1 timers ✓):** async subprocess (non-blocking spawn + wait-on-loop) → async net client + `join_all`/`select` + async DNS → `async_rwlock` → then the IOCP-Windows mirror last. |
| **Committed after** | **async runtime arc 5b (F1 ✓ .33; F2 ✓ .34; primitives next) → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail.** **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
