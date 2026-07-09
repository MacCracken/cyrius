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
| **Version** | **6.4.33** — **async runtime F1: the epoll reactor (arc 5b opens) + the sandhi 1.7.2 re-vendor + a tls-backend fmt/lint repair.** `async_run` becomes a real epoll reactor: it drives the runtime's shared `epfd` (created since v6.1.22 but never used to multiplex), parks the current task on an fd via the new `async_wait_fd(rt, fd)` (→`TASK_WAITING`, task ptr carried in the epoll `data`, `EPOLL_CTL_DEL` on wake), blocks on the epfd when nothing is runnable, and resumes the task whose fd fired. A task that never parks runs to completion byte-for-byte as before (sandhi/daimon accept loops unaffected). Also: re-folded `lib/sandhi.cyr` → 1.7.2 (native-TLS large-response `step` 4096→16384 + cyrius pin 6.3.5→6.4.32) and cleared the fmt/lint gate violations the concurrent native-TLS `READ_HOLD` hold-buffer fix introduced in `lib/tls_native_ctx.cyr` (formatting only). Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 1,077,592 B (byte-identical to v6.4.32 **modulo the version string** — the .33 work is lib-only, no compiler-logic `src/` change) · seed-derive byte-identical · check.sh **133** · self_compile 620 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` + VR-01 `LIBTEST_OK` + **cx portable-`.cyx` round-trip now exercises SIMD** (`f64v_add`+`f64v_sqrt` over local arrays → exit 42 on each host's native cxvm, not a bare write) (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **async runtime arc 5b — F1 (.33) SHIPPED.** The epoll reactor + `async_wait_fd` park/resume land; the runtime is now an actual event loop, not a serial run-to-completion sweep. Premise-check reframe (2026-07-09, 8-verifier workflow): the engine had no reactor and couldn't yield, so arc 5b is **FOUNDATION-FIRST** — reactor (F1 ✓) + cooperative suspend/resume (F2) before the 5 tokio-parity primitives; IOCP-Windows folded in AFTER gap coverage; extraction to a `tantu` repo deferred to a later minor. cx SIMD (.32) + Win64 value-form SIMD (.31) arcs are COMPLETE (Pin 1 done on all four backends). |
| **Next up** | **async arc 5b F2 (.34): cooperative suspend/resume + the task substrate (result slot + multi-arg) + `JoinHandle`/`task_join`.** Then the primitives — timers → subprocess → net client + `join_all`/`select` + async DNS → `async_rwlock` — then the IOCP-Windows mirror last. Deferred to .34: sandhi 1.7.3 pin→.33 (its native-TLS fix needs .33's `READ_HOLD`; `project_sandhi_173_pin_bump_at_v634`). |
| **Committed after** | **async runtime arc 5b (F1 ✓ .33; F2 next) → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail.** **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
