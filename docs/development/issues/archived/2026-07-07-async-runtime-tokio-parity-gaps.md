# Async runtime — the parity gaps that block porting a tokio-shaped app (stiva)

> **✅ RESOLVED — 5 primitive gaps SHIPPED v6.4.33 → v6.4.41 (9 releases), consolidated
> v6.4.42.** Foundation: F1 reactor (.33) + F2 task substrate / `JoinHandle` (.34). Gaps:
> subprocess via pidfd (.36, gap 1), `interval`/`with_timeout` (.35, gap 2), `task_join`
> (.34, gap 3), net client — `connect` (.38) + `send`/`recv` (.39) + async DNS `resolve`
> (.40) + `join_all`/`select` (.37, gap 4), cooperative `async_rwlock` (.41, gap 5).
> **v6.4.42 consolidation** (adversarial closeout review of the 9 releases) fixed 8 confirmed
> bugs — `async_select` missed-completion + null-guard, `_async_retire` owned-fd leak
> (connect/resolve), `_async_interval_task` null-token deref, `_async_process_task` unchecked
> pidfd deadlock, agnos `async_with_timeout` null-handle parity — AND uncovered+fixed a
> **pre-existing compiler bug: the aarch64 epoll reactor NEVER worked** (`epoll_pwait`=22
> collided with the x86 `pipe`→`pipe2` ESYSXLAT remap → `-EFAULT`; the epoll_event data
> offset was x86-only @4 vs aarch64 @8). Both fixed + verified end-to-end on real pi hardware.
> **Still open (gap 6 + IOCP):** mid-body suspend/resume (streaming socket I/O + blocking
> `async_rwlock` acquire — cross-linked to roadmap-future stackless coroutines) and the
> IOCP-Windows mirror (issue 2026-07-08). Consolidation follow-ons at the bottom of this file.

> **ROADMAPPED 2026-07-07 → arc 5b, scheduled right after SIMD Phase 5.** stiva is a
> real consumer (our Docker project) blocked NOW, so the 5 library primitives (async
> subprocess, `interval`+`timeout`, joinable `JoinHandle`/`task_join`, async TCP client +
> `join_all`/`select`, `async_rwlock`) are a **committed near-term arc** — NOT parked in
> v6.8 (roadmap.md slot 5b). The 6th gap (stackless suspend/resume — execution model) is
> cross-linked to the stackless-coroutines item in roadmap-future.md and is NOT a blocker
> for the 5 primitives. Likely home: extract a `sutra`/`kaal` async-runtime lib, vendor back.

> **ARC-OPEN DECISIONS (2026-07-09, after a code-grounded 8-verifier premise-check).** Arc 5b
> opens at **v6.4.33**. All 6 gaps CONFIRMED still-missing against v6.4.32 source (none stale).
> **Reframe:** the runtime is **not actually an event loop** — the rt epoll fd is created+closed
> but never used to multiplex (`async_run` is a serial linked-list sweep), `TASK_WAITING` is a
> dead state, nothing yields mid-body, `async_sleep_ms` blocks the whole loop, the runtime is
> single-use, and tasks are single-arg with no result slot. So gaps 1/2/4/5 cannot be honestly
> non-blocking without a **reactor + cooperative suspend/resume** substrate first (only gap 3
> JoinHandle is deliverable in today's run-to-completion model). Two uncovered categories the
> 5-item list omits: **async file I/O** and **async DNS** (a name-based async client still blocks
> on `getaddrinfo`). **User calls (2026-07-09): (1) FOUNDATION-FIRST** — build the reactor +
> suspend/resume + JoinHandle substrate before the primitives; **(2) IOCP-Windows folded into this
> arc, AFTER gap coverage** (issue 2026-07-08); **(3) extraction to its own repo DEFERRED to a
> later minor** — build in-place in `lib/async.cyr` for now; **when extracted+refolded the repo
> name will be `tantu`** (thread/fiber, NOT `sutra`/`kaal` — the earlier suggestion is superseded).
> Honest arc length grew from ~3–5 to **~6–8 releases**. Sugar (`async`/`await`) stays
> compiler-resident (lex tokens 134/135, `_ASYNC_OK` gate) — only the 13-fn runtime library is
> ever extractable. Dependency-ordered shape + rationale in roadmap.md slot 5b.


- **Filed**: 2026-07-07 (found porting stiva Rust→Cyrius; the whole async
  container-orchestration surface deferred to "v3.1" bounced off these gaps).
- **Severity**: P2 (feature-completeness). `lib/async.cyr` exists and works for
  the *server accept-loop* shape it was built for (sandhi/daimon/bote), but a
  consumer whose Rust is written against **tokio's task/timer/process/net/lock**
  surface can't port its async layer 1:1 — it has to be rebuilt, not translated.
- **Scope**: `lib/async.cyr` (+ the `async fn`/`await` sugar). Not a bug — an API-
  surface + execution-model gap. Affects any tokio-based consumer, not just stiva.
- **User direction (2026-07-07)**: async may warrant **its own repo** (like sigil/
  sandhi/sankoch), matured there, then **folded back into the stdlib** — same
  productize-then-vendor path `flags`→`cmdit` and the crypto libs took.

## What exists today (`lib/async.cyr`, verified)

Cooperative epoll runtime, single-threaded, run-to-completion:
- `async_new()` / `async_new_in(a)` (arena-owned), `async_spawn(rt, fp, arg)`,
  `async_run(rt)` (blocks until all tasks done; **single-use** — closes epfd).
- `async_sleep_ms(ms)`, `async_timeout(fp, arg, ms)` (one-shot), `async_read(fd,…)`,
  `async_await_readable(fd)`.
- `future_force(fut)`, `async_spawn_future(rt, fut)`; `async fn`/`await` sugar
  (opt-in `CYRIUS_ASYNC=1`).
- Cancellation tokens (`cancel_token_check`/`signal`, atomic-backed) — good.

Documented limits (guide v6.3.11 + header): the model is **deferred-then-forced,
run-to-completion** — NOT stackless coroutines. `await` **re-runs the body** each
time (no force-once memoization). No true **mid-body suspend/resume** across an
`await` (a Future bundles the whole call). `async` **generic** fns and
**struct-returning** `async fn`s unsupported. Capturing closures unsupported on PE.

## The gaps that actually blocked the stiva port

Each maps to a tokio primitive the Rust used pervasively:

1. **Async subprocess** (`tokio::process::Command`) — kavach sandbox exec, the
   nsenter exec path, CRIU dump/restore, slirp4netns/pasta spawn, and every
   `ip`/`nft` shell-out. `lib/process.cyr` is **blocking** (`run`/`spawn`/`wait`);
   there is no "spawn a child + await its exit on the loop + timeout" primitive.
   This alone deferred most of `runtime.cyr` / `container.cyr`.
2. **Timers as intervals + timeout-around-a-future** (`tokio::time::interval` /
   `timeout`). `async_timeout` is a one-shot task-after-delay; there is no
   `interval` (health probe loops) and no `timeout(future, dur)` combinator
   (probe/exec deadlines). `health.cyr`'s `start_probe_loop`/`run_probe` deferred
   here.
3. **Spawn with a joinable result** (`tokio::spawn` → `JoinHandle<T>`).
   `async_spawn` schedules but there's no ergonomic "await this task's return
   value" / structured `JoinHandle`. Background daemon tasks + `wait()` need it.
4. **Async net client + concurrent awaits** (`tokio::net` / `reqwest` +
   `join!`/`select!`). The registry pull/push client wants async connect/read/
   write and **concurrent layer downloads**; `sandhi`/`http` cover the server +
   blocking-client shapes, but there's no async HTTP client + no `join_all`/
   `select` combinator to fan out N downloads.
5. **Async-aware shared state** (`Arc<RwLock<HashMap>>`). `lib/thread.cyr` has a
   preemptive mutex; there is no async RwLock / task-yielding lock for the token
   cache + container-manager state a single-threaded loop shares across awaits.
6. **Force-once memoization + true suspend** (already on the roadmap) — without
   memoization, `await x` twice runs the body twice (surprising + wrong for
   side-effecting futures); without mid-body suspend you can't write a natural
   `loop { select! { … } }` server/agent.

## Suggested direction

- **Extract to a repo** (`sutra`? `kaal`? — an async/runtime name), where the
  execution model can grow without a compiler release, then vendor the frozen
  API back into `lib/async.cyr` (the cmdit/sankoch path).
- **API surface to add** (independently useful, mostly library-level over the
  existing epoll loop): `async_process_spawn`/`_wait`/`_output` (non-blocking
  child + exit on the loop), `async_interval` + `async_with_timeout(future, ms)`,
  a joinable `async_task`/`task_join`, an async TCP client
  (`async_connect`/`_write`) + `join_all`/`select`, and an `async_rwlock`.
- **Execution model** (needs runtime work): force-once memoization, then
  poll-based stackless suspend/resume across `await` (the guide's planned
  follow-on) — this is what unlocks natural `loop { … await … }` agents.

Filed from the stiva port; the language was not modified. Companion: the stiva
v3.1 roadmap item "map the tokio-shaped async onto `lib/async.cyr`" is gated on
this.

## Consolidation follow-ons (discovered in the v6.4.42 adversarial review — still open)

These survived the consolidation's confirmed-bug fix pass as genuine-but-deferred
work (the review REFUTED nothing here; they are execution-model / hardening items,
not the 8 shipped fixes):

1. **Mid-body suspend/resume** (gap 6 above) — poll-tasks re-run from the TOP on each
   wake (no saved continuation), so **streaming socket I/O with backpressure** and a
   **blocking `async_rwlock` acquire** (only the TRY-family exists) are not expressible.
   This is the execution-model wall; cross-linked to **roadmap-future.md → Stackless
   coroutines**. Everything below is bounded and independent of it.
2. **pidfd / reactor-fd `O_CLOEXEC`** — `async_new_in` opens the epfd with
   `EPOLL_CREATE1, 0` (not `EPOLL_CLOEXEC`); reactor timerfds use `TIMERFD_CREATE, 0`;
   connect sockets set `O_NONBLOCK` but not `O_CLOEXEC`. `_async_process_task` fork+exec
   therefore leaks the whole reactor fd table into the child. Fix: add CLOEXEC at each
   creation site (`async_new_in`, `_async_timerfd`, the socket-open paths). One-liner each.
3. **Single-waiter per fd** — `_async_wait_events` uses the epoll `data` slot AS the
   waiter identity, so two tasks parking the same fd hit `EPOLL_CTL_ADD` `EEXIST`
   (return unchecked) and the second is silently starved. A broadcast / multi-consumer
   pattern needs an explicit per-fd waiter list. No consumer needs it yet; file-and-park.

## IOCP-Windows mirror (the other remaining arc item)

Tracked separately in **issues/2026-07-08-async-epoll-only-blocks-win-transport.md** —
the reactor is epoll-only, so `--win` async blocks. Folds in AFTER gap coverage per the
arc-open decision. Not started.
