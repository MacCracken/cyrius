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
| **Version** | **6.4.39** — **async socket send/recv + the agnos block-device syscall band.** The async net client gains single-shot reactor **`async_send`/`async_recv`** (park on the socket's write/read readiness, then one write/read; result = byte count) — completing the connect → send → recv async client. And the agnos **`sys_blk_*`** (#75-80) raw block-device wrappers land (the .34 shm band's sibling — the native-install primitive: a sovereign installer/mkfs partitions + formats a disk with no Linux parted/mkfs). Both agnos-guarded / async-lib-only → cycc byte-identical modulo the version string. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,077,592 B (byte-identical to v6.4.38 **modulo the version string** — the .39 work is lib-only, no compiler-logic `src/` change) · seed-derive byte-identical (cycc machine-derivable from the 29 KB seed) · check.sh **139** · self_compile 611 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` round-trip now exercises SIMD** (`f64v_add`+`f64v_sqrt` over local arrays → exit 42 on each host's native cxvm, not a bare write) (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **async runtime arc 5b — F1 (.33) + F2 (.34) + P1 timers (.35) + P2 subprocess (.36) + P3 combinators (.37) + net connect (.38) + net send/recv (.39) SHIPPED.** Foundation: F1 reactor (`async_wait_fd`/`async_wait_writable`) + F2 task substrate. Primitives: P1 timers, P2 subprocess (pidfd), P3 combinators, async net client (`async_connect`/`async_send`/`async_recv` — connect + single-shot socket I/O). Arc is **FOUNDATION-FIRST**; IOCP-Windows folded in AFTER gap coverage; extraction to a `tantu` repo deferred to a later minor. cx SIMD (.32) + Win64 value-form SIMD (.31) arcs COMPLETE. |
| **Next up** | **async arc 5b — async DNS (name resolution, so the client is name-based end-to-end) → `async_rwlock` → then the IOCP-Windows mirror last.** Filed follow-ons: streaming socket I/O with backpressure needs mid-body suspend; pidfd child inherits reactor fds (no CLOEXEC). |
| **Committed after** | **async runtime arc 5b (F1 ✓ .33; F2 ✓ .34; primitives next) → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail.** **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
