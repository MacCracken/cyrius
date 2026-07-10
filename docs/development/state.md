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
| **Version** | **6.4.34** — **async runtime F2: result-carrying tasks + `task_join` (JoinHandle) + the agnos shm syscall band + the sandhi 1.7.3 pin bump.** `async_run` now captures each task fn's return into a per-task result slot (@40); the F1 reactor loop is extracted into a shared `_async_pump(rt, until)`, and **`task_join(rt, handle)`** drives the loop until a spawned task completes and hands back its result without tearing down the runtime — joining a Future handle yields the async-fn result with multi-arg (via `future_force`), the `tokio::spawn(async{…}).await` shape. Reactive agnos repair: `sys_shm_create`/`_write`/`_read`/`_free` (#71-74) wrap agnos 1.53.9's kernel-owned shared-buffer band. Completed the deferred sandhi **1.7.3** pin bump (`6.4.32→6.4.33`, the version carrying the tls `READ_HOLD` fix 1.7.x depends on). All lib-only — cycc byte-identical modulo the version string. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,077,592 B (byte-identical to v6.4.33 **modulo the version string** — the .34 work is lib-only, no compiler-logic `src/` change) · seed-derive byte-identical (cycc machine-derivable from the 29 KB seed) · check.sh **134** · self_compile 607 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` round-trip now exercises SIMD** (`f64v_add`+`f64v_sqrt` over local arrays → exit 42 on each host's native cxvm, not a bare write) (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **async runtime arc 5b — F1 (.33) + F2 (.34) SHIPPED.** F1 = the epoll reactor + `async_wait_fd` park/resume; F2 = the task substrate (result capture + `task_join`/JoinHandle, multi-arg via Futures). The runtime is now an actual event loop with joinable, result-carrying tasks — the foundation the 5 tokio-parity primitives build on. Arc is **FOUNDATION-FIRST** (reactor + substrate before primitives); IOCP-Windows folded in AFTER gap coverage; extraction to a `tantu` repo deferred to a later minor. cx SIMD (.32) + Win64 value-form SIMD (.31) arcs COMPLETE. |
| **Next up** | **async arc 5b — the tokio-parity primitives on the F1/F2 foundation:** timers (`async_interval` + `timeout(future, dur)`) → async subprocess → async net client + `join_all`/`select` + async DNS → `async_rwlock` → then the IOCP-Windows mirror last. |
| **Committed after** | **async runtime arc 5b (F1 ✓ .33; F2 ✓ .34; primitives next) → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail.** **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
