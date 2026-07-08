# Async runtime — the parity gaps that block porting a tokio-shaped app (stiva)

> **ROADMAPPED 2026-07-07 → arc 5b, scheduled right after SIMD Phase 5.** stiva is a
> real consumer (our Docker project) blocked NOW, so the 5 library primitives (async
> subprocess, `interval`+`timeout`, joinable `JoinHandle`/`task_join`, async TCP client +
> `join_all`/`select`, `async_rwlock`) are a **committed near-term arc** — NOT parked in
> v6.8 (roadmap.md slot 5b). The 6th gap (stackless suspend/resume — execution model) is
> cross-linked to the stackless-coroutines item in roadmap-future.md and is NOT a blocker
> for the 5 primitives. Likely home: extract a `sutra`/`kaal` async-runtime lib, vendor back.


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
