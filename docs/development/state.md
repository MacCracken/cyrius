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
| **Version** | **6.4.43** — **async arc 5b "W" step R1: the Windows IOCP async CLIENT.** The epoll-only reactor hard-errored ANY `--win` async build (`undefined SYS_EPOLL_CREATE1`), blocking every Windows transport binary (thoth). R1 ships a **real IOCP async client**: `async_resolve` → `async_connect` → `async_send` → `async_recv`, every op overlapped and completing through `GetQueuedCompletionStatus`. New `lib/async_win.cyr` (three-way guard split) + a from-scratch ws2_32 bring-up (13 PE reroutes 0xF01E–0xF02C, each with aarch64+cx stub twins). Root-caused + fixed a **latent codegen bug** the arc exposed: callptr/reroute `>4`-arg marshalling clobbered non-volatile `r12/r14/r15` (ConnectEx 7-arg → `WSAENOTSOCK`; the `>4` path had NEVER been used — max prior 3 args). + `O_CLOEXEC` reactor hygiene. Proven end-to-end on **real cass** across the whole arc. Per-release detail → [CHANGELOG](../../CHANGELOG.md). |
| **cycc** | x86 **1,086,496 B** (+8,904 vs v6.4.42 — the R1 PE reroutes + call helpers + callptr fix grew the emitter; the `>4` callptr path is inert for cycc's own output but the emit code is compiled in) · self-host fixpoint byte-identical · seed-derive byte-identical · check.sh **141** · self_compile 617 ms |
| **Bootstrap / cross-OS** | seed (29 KB asm) → cybs → cycc byte-identical · ecb (macOS/arm64) + cass (Windows/PE) + pi (aarch64) `SELFHOST_OK` · **the Windows IOCP async client runs end-to-end on real cass** (resolve→connect→send→recv → RC 42 against a loopback echo) · the aarch64 epoll reactor works on pi (v6.4.42) · cx portable-`.cyx` SIMD round-trip on each host's native cxvm (release-gate GREEN) |
| **Active minor** | **v6.4.x** — ABI / Language-Features (opened at v6.4.0; v6.3.x closed at v6.3.45) |
| **In-flight arc** | **async arc 5b — the IOCP-Windows "W" step, 3 releases; R1 SHIPPED (.43).** Foundation + the 5 tokio-parity gaps (.33–.41) + consolidation (.42) DONE. **W-step R1 (.43)** = the Windows IOCP async CLIENT: `async_win.cyr` reactor (three-way guard split) + 13 ws2_32/IOCP PE reroutes + overlapped connect/recv/send + DNS (`getaddrinfo`) + the callptr `>4` non-volatile-clobber fix + `O_CLOEXEC` — resolve→connect→send→recv proven on real cass. **R2** = async subprocess (`RegisterWaitForSingleObject`→PQCS) + timers/interval (GQCS deadline + min-heap) + `join_all`/`select` parity. **R3** = overlapped `AcceptEx` server (+`GetAcceptExSockaddrs`). Arc is FOUNDATION-FIRST; cx SIMD (.32) + Win64 value-form SIMD (.31) COMPLETE. |
| **Next up** | **async arc 5b W-step R2** — async subprocess on Windows (`CreateProcessW` exists + `RegisterWaitForSingleObject`→`PostQueuedCompletionStatus`; reap `GetExitCodeProcess`, kill `TerminateProcess`) + timers/interval (`GetQueuedCompletionStatus` `dwMilliseconds` single-deadline + a deadline min-heap) + `async_with_timeout`/`join_all`/`select` Windows parity + full cass/ecb/pi verify. **Then R3** = the overlapped `AcceptEx` server so sandhi/daimon accept on Windows. **Then `tantu` extraction → 6.5.0** (user directive). Filed follow-ons: single-waiter-per-fd multiplex (a real per-fd waiter list, reconsidered as NOT a cheap hygiene bite); mid-body suspend substrate = FUTURE ARC (blocked on the v6.5.x IR re-emit substrate + no live consumer). thoth `--win` end-to-end is a **post-release downstream re-vendor** check (sandhi re-vendors `async` from .43 first). |
| **Committed after** | **async runtime arc 5b (F1 ✓ .33; F2 ✓ .34; primitives next) → UEFI Secure Boot signing → function visibility (`pub`/`private`) → scalar-float completion → diagnostics → Intel-Mac (x86_64 Mach-O) tail.** **v6.5.x = perf-quality** (IR/regalloc substrate + passes; SIMD register-residency pulls into 6.4.x post-NEON) · **v6.6.x = language ergonomics** · **RISC-V → v6.7/v6.8**. Full slot table + async prose in [roadmap.md](roadmap.md). |

> Full arc detail, per-arc length estimates, and the Phase-5 5a/5b plan live in
> [roadmap.md](roadmap.md). Reactive agnos + consumer-filed repairs interleave as
> separate (uncounted) slots.
