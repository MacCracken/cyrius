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
| **Version** | **6.4.40** — **async DNS resolution — the name-based async client is complete.** **`async_resolve(rt, ns_addr, ns_port, host)`** does reactor-integrated DNS A-record resolution: builds a DNS query, UDP-sends it to the nameserver, parks on the reply, parses the first A record (self-contained wire-format with 0xC0 compression-pointer skip, ported from the sandhi resolver) → task handle whose result is the IPv4 as a network-order int (feed straight to `async_connect`), or -1. Closes the loop: **resolve → connect → send → recv**, all reactor-integrated. `async_agnos.cyr` degrades. All lib-only — cycc byte-identical modulo the version string. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,077,592 B (byte-identical to v6.4.39 **modulo the version string** — the .40 work is lib-only, no compiler-logic `src/` change) · seed-derive byte-identical (cycc machine-derivable from the 29 KB seed) · check.sh **140** · self_compile 622 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` round-trip now exercises SIMD** (`f64v_add`+`f64v_sqrt` over local arrays → exit 42 on each host's native cxvm, not a bare write) (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **async runtime arc 5b — F1 (.33) → net client + DNS (.38–.40) SHIPPED (8 releases).** Foundation: F1 reactor (`async_wait_fd`/`async_wait_writable`) + F2 task substrate. Primitives: P1 timers (.35), P2 subprocess via pidfd (.36), P3 combinators `join_all`/`select` (.37), async net client — `async_connect` (.38) + `async_send`/`async_recv` (.39) + `async_resolve` DNS (.40). The name-based async client (resolve→connect→send→recv) is complete. Arc is **FOUNDATION-FIRST**; IOCP-Windows folded in AFTER gap coverage; extraction to a `tantu` repo deferred to a later minor. cx SIMD (.32) + Win64 value-form SIMD (.31) arcs COMPLETE. |
| **Next up** | **async arc 5b — `async_rwlock` (task-yielding shared-state lock, gap 5) → then the IOCP-Windows mirror last** (folds in the epoll-only-blocks-`--win` gap). Then the arc's tail (extraction to `tantu`; the execution-model suspend follow-on). Filed follow-ons: streaming socket I/O with backpressure needs mid-body suspend; pidfd child inherits reactor fds (no CLOEXEC). |
| **Committed after** | **async runtime arc 5b (F1 ✓ .33; F2 ✓ .34; primitives next) → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail.** **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
