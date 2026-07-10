# async runtime is epoll-only — no IOCP path blocks every `--win` build that pulls `async`

> **✅ CLIENT RESOLVED — v6.4.43 (W-step R1).** `--win` async builds now LINK + RUN: a real
> IOCP client (`lib/async_win.cyr`) — `async_resolve`→`async_connect`→`async_send`→`async_recv`,
> every op overlapped and completing through `GetQueuedCompletionStatus`, proven end-to-end on
> real cass (RC 42 vs a loopback echo). From-scratch ws2_32 bring-up: 13 PE reroutes (0xF01E–
> 0xF02C) + a callptr `>4`-arg codegen fix the arc exposed. The undefined-`SYS_EPOLL_CREATE1`
> hard-error that blocked EVERY `--win` async binary is gone. **Still open:** R2 = async
> subprocess + timers + combinator parity on Windows; R3 = the overlapped `AcceptEx` SERVER so
> sandhi/daimon can *accept* on Windows (the server half of Acceptance below). thoth's `--win`
> end-to-end is a downstream check after sandhi re-vendors `async` from .43. See CHANGELOG [6.4.43].

> **ARC-OPEN DECISION (2026-07-09): folded into async arc 5b, sequenced AFTER gap coverage.**
> Premise-check verdict `FOUNDATIONAL_DEPENDENT_MUST_WAIT`: epoll is not behind a poller seam
> (inline across 4 fns — `async_new_in`/`async_await_readable`/`async_timeout`/`async_read`), and
> each of the 5 tokio-parity primitives adds new inline poll/wait sites, so an IOCP backend must
> MIRROR the frozen surface, not precede it. Land the reactor + suspend/resume foundation and the
> 5 primitives first; then `async_win.cyr` mirrors that surface in one shot (3+ kernel32 reroutes:
> `CreateIoCompletionPort` / `GetQueuedCompletionStatus` / `PostQueuedCompletionStatus` + WSA
> overlapped I/O, each a v6.4.26-style PE-reroute bite with mandatory aarch64+cx return-0 stub
> twins). Optional-early: the 3 core kernel32 emitters *could* be pre-registered like
> `TerminateProcess`, but they're inert without the lib backend. See roadmap.md slot 5b.

**Filed:** 2026-07-08 (thoth 0.20.4 — the Windows shell substrate landed + verified on `cass`, but the full
thoth `--win` binary still cannot link).
**Severity:** P2 — blocks shipping ANY Windows binary that uses the async transport (the sandhi/daimon/bote
server + client shapes), including thoth (which consumes sandhi → `async` for its hoosh HTTP transport).
No workaround: the symbol is referenced unconditionally, so even a program that never enters the async loop
fails to cross-compile.
**Component:** `lib/async.cyr` (epoll-only) + the Windows PE backend. Sibling to the existing
`lib/async_agnos.cyr` per-target split.

## Problem

`lib/async.cyr:58` references `SYS_EPOLL_CREATE1` (and the epoll fd/ctl/wait syscalls) with no
`#ifdef CYRIUS_TARGET_WIN` guard and no Windows path. Cross-compiling any program that pulls the `async`
stdlib dep with `--win` hard-errors:

```
error: lib/async.cyr:58: undefined variable 'SYS_EPOLL_CREATE1' (missing include or enum?)
```

epoll is Linux-only; Windows needs an **IOCP** (I/O Completion Port) backend — `CreateIoCompletionPort` /
`GetQueuedCompletionStatus` / `PostQueuedCompletionStatus`, all kernel32, so the PE reroute surface can add
them the same way 6.4.26 added `TerminateProcess` (`0xF01D`). Consequence: **no program using the async
transport can be built for Windows.** thoth pulls `async` transitively via sandhi (its LLM/HTTP transport),
so `cyrius build src/main.cyr thoth.exe --win` fails at `async.cyr` — thoth ships no Windows binary despite
its OS-agnostic front-end design, even though its Windows substrate (a capturing, timed `shell` tool built
on the 6.4.26 `TerminateProcess`/`_win_wait_timeout` primitives) is already implemented and verified
end-to-end on a real Windows 11 x86_64 host.

## Fix (IOCP backend, mirroring the agnos split)

Add a Windows async backend gated by `#ifdef CYRIUS_TARGET_WIN` (parallel to `lib/async_agnos.cyr`): an IOCP
event loop (`CreateIoCompletionPort` + `GetQueuedCompletionStatus`) behind the same `async_*` surface the
epoll loop exposes, with the kernel32 calls added as PE reroutes. At minimum, the epoll symbols must be
`#ifndef CYRIUS_TARGET_WIN`-guarded so a Windows build links — but thoth genuinely RUNS the transport on
Windows (hoosh HTTP), so a link-only stub would fake capability; a real IOCP loop is the correct fix.

## Acceptance

A program pulling `async` cross-builds `--win`; the sandhi server/client transport runs on Windows via IOCP;
`cyrius build src/main.cyr thoth.exe --win` links, and the resulting `thoth.exe` runs on `cass` (Windows 11
x86_64) and reaches a live hoosh gateway. (thoth's Windows shell substrate is already proven; this transport
gate is the last blocker for a shipping Windows thoth binary.)
