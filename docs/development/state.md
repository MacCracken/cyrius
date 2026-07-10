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
| **Version** | **6.4.38** — **async runtime: net client (connect).** The reactor gains write-readiness parking (`async_wait_writable`, the EPOLLOUT complement of F1's `async_wait_fd`; both now share `_async_wait_events`) and **`async_connect(rt, addr, port)`** — a non-blocking TCP connect that parks on the socket's write-readiness during the handshake, reads back SO_ERROR, and returns a task handle whose result (via `task_join`) is the connected fd (or -1). Raw Linux socket syscalls keep async.cyr net.cyr-free; `async_agnos.cyr` degrades. First piece of the async net client — verified end-to-end against a localhost listener (connect → accept → send/recv). All lib-only — cycc byte-identical modulo the version string. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,077,592 B (byte-identical to v6.4.37 **modulo the version string** — the .38 work is lib-only, no compiler-logic `src/` change) · seed-derive byte-identical (cycc machine-derivable from the 29 KB seed) · check.sh **138** · self_compile 606 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` round-trip now exercises SIMD** (`f64v_add`+`f64v_sqrt` over local arrays → exit 42 on each host's native cxvm, not a bare write) (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **async runtime arc 5b — F1 (.33) + F2 (.34) + P1 timers (.35) + P2 subprocess (.36) + P3 combinators (.37) + net connect (.38) SHIPPED.** Foundation: F1 reactor (`async_wait_fd`/`async_wait_writable`) + F2 task substrate. Primitives: P1 timers, P2 subprocess (pidfd), P3 combinators (`async_join_all`/`async_select`), async net **connect** (`async_connect`). Arc is **FOUNDATION-FIRST**; IOCP-Windows folded in AFTER gap coverage; extraction to a `tantu` repo deferred to a later minor. cx SIMD (.32) + Win64 value-form SIMD (.31) arcs COMPLETE. |
| **Next up** | **async arc 5b — finish the net client + remaining primitives:** async socket read/write (bounded by the no-suspend model — poll-task or an execution-model follow-on) + async DNS → `async_rwlock` → then the IOCP-Windows mirror last. Filed follow-ons: pidfd child inherits reactor fds (no CLOEXEC); streaming read/write needs mid-body suspend. |
| **Committed after** | **async runtime arc 5b (F1 ✓ .33; F2 ✓ .34; primitives next) → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail.** **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
