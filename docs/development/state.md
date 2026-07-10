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
| **Version** | **6.4.42** — **async arc consolidation + the aarch64 reactor made real.** An adversarial closeout review of the 9 async releases (F1→RwLock) fixed **8 confirmed bugs** (`async_select` missed-completion + null-guard, `_async_retire` owned-fd leak on timed-out connect/resolve, `_async_interval_task` null-token deref, `_async_process_task` unchecked-pidfd deadlock, agnos `async_with_timeout` null-handle parity) + 2 refactors (sleep→`_async_timerfd` dedup, ctx allocs through the rt allocator). Verifying the aarch64 offset fix on **real pi** uncovered + fixed a **pre-existing compiler bug: the aarch64 epoll reactor had NEVER worked** — `epoll_pwait`=22 collided with the x86 `pipe`→`pipe2` ESYSXLAT remap (→ `-EFAULT`), and `epoll_event.data` was x86-only @4 vs aarch64 @8. All 7 async reactor fixtures now pass on pi (first time). Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,077,592 B (**byte-identical to v6.4.41 modulo the version string** — the compiler fix is aarch64-emit-only, not in `main.cyr`'s chain; the lib fixes aren't in the compiler) · seed-derive byte-identical · check.sh **141** · self_compile 623 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` · **the aarch64 async epoll reactor now works end-to-end on real pi** (all 7 reactor fixtures → exit 42 — never exercised before .42; the async gates run only on x86) · cx portable-`.cyx` SIMD round-trip on each host's native cxvm (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **async runtime arc 5b — F1 (.33) → the 5 tokio-parity gaps SHIPPED (9 releases) → consolidation (.42).** Foundation: F1 reactor + F2 task substrate. Gaps: timers (.35), subprocess via pidfd (.36), combinators `join_all`/`select` (.37), net client — connect (.38) + send/recv (.39) + DNS resolve (.40), cooperative RwLock (.41), and the **.42 consolidation** (8 bug fixes + the aarch64-reactor compiler fix, verified on real pi). Arc is **FOUNDATION-FIRST**; IOCP-Windows folded in AFTER gap coverage; extraction to a `tantu` repo deferred to a later minor. cx SIMD (.32) + Win64 value-form SIMD (.31) arcs COMPLETE. |
| **Next up** | **async arc 5b — the two deep remainders: (a) IOCP-Windows mirror** (mirrors the frozen surface, folds in the epoll-only-blocks-`--win` gap; PE-backend work) **and (b) the execution-model mid-body suspend substrate** (unblocks blocking lock-acquire + streaming socket I/O — the roadmap-future stackless-coroutines item). Then the arc tail (extraction to `tantu`). Filed follow-ons (consolidation .42): streaming socket I/O + blocking rwlock acquire (need suspend); pidfd/reactor-fd `O_CLOEXEC`; single-waiter-per-fd multiplex (2nd task on one fd hits `EPOLL_CTL_ADD EEXIST`). |
| **Committed after** | **async runtime arc 5b (F1 ✓ .33; F2 ✓ .34; primitives next) → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail.** **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
