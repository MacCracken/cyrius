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
| **Version** | **6.4.36** — **async runtime P2: subprocess.** The second tokio-parity primitive: spawn a child + await its exit on the reactor without a blocking waitpid, via a `pidfd`. New `SYS_PIDFD_OPEN` (434) + `sys_pidfd_open` (stubbed on macOS-x86 so the shared `linux_common` wrapper keeps the `cbt/cyrius.cyr` Mach-O cross-compile clean). **`async_spawn_process(rt, path, argv, envp)`** forks+execs a child, parks on its pidfd, reaps on wake — result (via `task_join`) is the exit code; the reactor multiplexes multiple children concurrently. **`async_run_process(rt, path, argv, envp, ms)`** spawns + waits with an optional deadline → exit code, or -2 on timeout (child SIGKILLed + reaped + pidfd closed). `async_agnos.cyr` degraded (no clone-fork). All lib-only — cycc byte-identical modulo the version string. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,077,592 B (byte-identical to v6.4.35 **modulo the version string** — the .36 work is lib-only, no compiler-logic `src/` change) · seed-derive byte-identical (cycc machine-derivable from the 29 KB seed) · check.sh **136** · self_compile 630 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` round-trip now exercises SIMD** (`f64v_add`+`f64v_sqrt` over local arrays → exit 42 on each host's native cxvm, not a bare write) (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **async runtime arc 5b — F1 (.33) + F2 (.34) + P1 timers (.35) + P2 subprocess (.36) SHIPPED.** Foundation: F1 epoll reactor + `async_wait_fd`; F2 task substrate (`task_join`/JoinHandle, multi-arg via Futures). Primitives so far: P1 timers (`async_with_timeout` + `async_interval`), P2 subprocess (`async_spawn_process`/`async_run_process` via pidfd). Arc is **FOUNDATION-FIRST** (reactor + substrate before primitives); IOCP-Windows folded in AFTER gap coverage; extraction to a `tantu` repo deferred to a later minor. cx SIMD (.32) + Win64 value-form SIMD (.31) arcs COMPLETE. |
| **Next up** | **async arc 5b — remaining tokio-parity primitives (P1 timers ✓, P2 subprocess ✓):** async net client (async connect/read/write) + `join_all`/`select` + async DNS → `async_rwlock` → then the IOCP-Windows mirror last. Filed follow-on: pidfd child inherits reactor fds (no CLOEXEC yet). |
| **Committed after** | **async runtime arc 5b (F1 ✓ .33; F2 ✓ .34; primitives next) → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail.** **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
