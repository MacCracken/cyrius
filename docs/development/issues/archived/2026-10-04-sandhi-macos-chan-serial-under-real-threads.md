# 2026-10-04 — arm64 macOS starts real threads but keeps the serial channel — ✅ RESOLVED in 6.6.16

**Status:** ✅ **RESOLVED in 6.6.16** (lane thr, bite thr-1, commits `2439678d` + `5acfa59b` + the two
review-fix commits `a37536ca` (the Windows wait-port pool) and `6d3397ec` (the test's deadline on every
main-thread call)).
- arm64 macOS and Windows have a locked, blocking channel with `lib/thread.cyr`'s contract.
- Every thread peer exports `CHAN_BLOCKING` (1 on Linux, arm64 macOS and Windows; 0 on x86 macOS,
  agnos and cx).
- The Linux channel's own lost wake-ups, found on the way, are fixed too.

See CHANGELOG [6.6.16].

**Filed in:** `sandhi/docs/development/issues/2026-10-04-cyrius-macos-chan-serial-under-real-threads.md` (copied here 2026-10-04, unedited below this header).
**Placement:** **6.6.16** (user, 2026-10-04). ⚠ Same shape on **Windows**, measured from the source at the 6.6.16 slot: real `CreateThread` threads, a mutex-protected ring whose `chan_recv` never blocks (`lib/thread_win.cyr` ~180), and 6.6.16's N7 makes Windows report `THREADS_CONCURRENT = 1`. The complete fix covers both targets plus the capability.
**Severity:** **P2** — any producer/consumer built on `chan_*` across threads is broken on arm64 macOS, and
on every other target that still uses the serial ring. No error surfaces: the consumer simply sees an
empty channel.
**Reporter:** sandhi, from its first macOS CI run of a pooled-server row (1.10.7, `macos-14`, reproduced on
ecb).
**Toolchain:** cyrius 6.6.15.

## Resolution (6.6.16)

**Both of the filing's proposals shipped, not one or the other.** The filing offered either a real
channel on arm64 macOS or a `CHAN_BLOCKING` capability. A capability alone would have left sandhi
serving inline on macOS for ever. A real channel alone would have left every consumer testing target
names to find out whether the channel blocks.

**arm64 macOS** (`lib/thread_macos.cyr`, arm64 arm). The ring is locked with `lib/sync_macos.cyr`'s
`__ulock` lock. Its waiters park on `__ulock_wait` / `__ulock_wake` with an eventcount:
- a waiter registers under the lock, reads its seq word (receivers and senders each have one),
  unlocks, and parks on that value;
- a waker that finds a waiter of the other kind registered advances that seq word under the lock,
  then wakes one (`chan_close` wakes all of them with `ULF_WAKE_ALL`).

The four ways `__ulock` differs from futex, which `sync_macos.cyr` measured, are all respected:
- the argument order is (operation, addr, value, timeout);
- a value mismatch returns 0 at once;
- a wake with nobody parked returns -ENOENT;
- only the low 32 bits are compared, so the seq words wrap at 32 bits.

x86 macOS keeps the serial ring unchanged. Each public `chan_*` is defined once and picks its arm
inside, so the API surface does not move.

**Windows** (`lib/thread_win.cyr`). The issue's placement note said Windows had the same shape: real
`CreateThread` threads over a ring whose `chan_recv` never blocks. The ring keeps its SRWLOCK. A waiter
queues a node, in its own frame, on the channel's receiver or sender FIFO, and blocks in
`GetQueuedCompletionStatus` on an I/O completion port that only it waits on. These are the
0xF01F-0xF021 reroutes `lib/async_win.cyr` already uses, so the bite needed no new reroute and no
`src/` change. A waker unlinks the oldest waiter of the other kind under the lock and posts its port
one token after unlocking; `chan_close` does that for every waiter. Tokens persist, so a token posted
before its waiter blocks is waiting when the waiter gets there, and a waiter leaves its wait only with
its token, so no node outlives its frame in a queue.

The ports come from a process-wide pool, never from the channel. A call takes one the first time it
has to wait and gives it back when it returns, so the handles in existence scale with the threads
waiting at once. The fix's first draft kept two ports per channel for the life of the process, and
review caught what that costs a consumer that makes a reply channel per request (agnosai's inference
queue): measured on cass, 400 such channels took the process from 84 handles to 484, against 85 with
the pool. Up to 64 idle ports are kept, in static storage so `alloc_reset` cannot pull the pool out
from under a waiter. Each port's concurrency value is 0x7FFFFFFF rather than 0, so the port never holds
a token back while released threads are still running.

**Linux: a defect the filing did not name** (`lib/thread.cyr`). The filing took the Linux channel as
the working reference. Under several producers or consumers it was not working:
- Receivers parked on "empty" and senders parked on "full" used ONE futex word, and every operation
  woke ONE thread on it. Four producers and four consumers deadlocked on every run on x86_64. One
  producer feeding three consumers through a cap-1 channel, the shape of sandhi's own pooled server
  when saturated, hung on pi.
- `closed` was not part of the futex word, so a receiver could sleep through `chan_close`.

Linux now runs the same eventcount as arm64 macOS, over futex. With nobody waiting it makes no syscall;
before, every send and every receive made a `FUTEX_WAKE`. cx keeps its single-thread spin and issues no
futex.

**The capability.** `CHAN_BLOCKING` sits beside `THREADS_CONCURRENT` in every peer, and is documented in
`lib/thread.cyr`'s header:
- 1 means `chan_recv` / `chan_send` block, and any number of producer and consumer threads may share
  the ring;
- 0 means no second thread exists to end a wait: x86 macOS and agnos answer at once, and cx spins as
  it always has.

**Verification.** `tests/tcyr/crossos/chan_blocking_threads.tcyr` has 49 rows, and 11 on a serial peer.
Every wait in it has a deadline, so a regression fails instead of hanging: on a blocking peer the main
thread makes no channel call itself and joins only threads it has seen finish. A `chan_recv` mutated
to answer 0 after any wake, and a `chan_send` mutated to drop its value after waiting, each fail in
30 s with a named row (the review draft of the test hung on both).
- 10/10 runs on x86, qemu-aarch64, pi, ecb and cass.
- The serial arm 10/10 on ach.
- Green under wine and cxvm.
- RED on the old code: 13 of 49 rows failed on ecb and on cass, without hanging, and the old Linux
  channel deadlocked row D on x86 (5/5) and pi (3/3).
- Four workers blocked in `chan_recv` for 3 s used 0.00 s of CPU on ecb, 0.001 s on x86 and 0.016 s
  on cass.
- A channel stress probe (close landing mid-cycle, senders blocked at close, 8x8 on cap 1, try_ verbs
  mixed with blocking peers) ran 23/23 on ecb, 10/10 on pi, 5/5 on cass and 3/3 on x86. It hangs the
  old Linux code on pi and x86.
- The 19 thread-including crossos tests pass on ecb, pi, ach and cass (cass re-run with the final
  Windows channel).
- A Windows mutant whose `GetQueuedCompletionStatus` fails one call in three (the error path: unlink
  if unclaimed, never close a port a token may still reach) keeps all 49 rows and the stress probe
  green on cass and under wine.

**sandhi.** `_sandhi_server_pool_inline` can key on `CHAN_BLOCKING == 1` instead of
`CYRIUS_TARGET_LINUX` once sandhi pins cyrius ≥ 6.6.16. That is sandhi's change to make, upstream. The
note is in the integration filings.

## What happens

`lib/thread_macos.cyr` (6.6.15):

- **`thread_create` starts real threads on arm64 macOS.** `THREADS_CONCURRENT = 1` (v6.5.44, via
  `pthread_create` through `__got[5]`); x86 macOS stays serial (`THREADS_CONCURRENT = 0`).
- **The channel below it is the serial ring on both archs:**
  - no lock;
  - `chan_recv` is `chan_try_recv`, which returns **0 when empty** instead of blocking;
  - `chan_send` returns **-1 when full** instead of waiting.

On arm64 that ring is now shared by real threads. A consumer that does `while (1) { v = chan_recv(ch); if (v == 0) break; ... }`,
the standard worker shape and the one `lib/thread.cyr`'s Linux channel supports, sees 0 at once and
exits. A producer's `chan_send` into a channel with no live consumer fails silently once full, and the
ring's head/tail/count are updated without a lock by several threads.

## Consequence in sandhi

`sandhi_server_run_pooled` and `sandhi_server_run_pooled_tls` spawn `max_conns` workers that each loop on
`chan_recv` and treat 0 as "channel closed". On macOS every worker exited immediately, so the servers
bound, listened and accepted but **never served a request**:
- a complete `GET` to a pooled server on ecb went unanswered until the client's 3 s timeout;
- the same happened with the server in a thread, in a forked child, and with or without a stop flag.

The 1.10.7 macOS CI run caught it through `test_server_request_budget_answers_408`, the first macOS test
that needs a pooled server to answer.

## sandhi's workaround (1.10.7)

`_sandhi_server_pool_inline()` answers 1 on every target but Linux with `THREADS_CONCURRENT == 1`. There
the pooled entry points serve each accepted connection on the accept thread, with the same per-request
contract (budget, refusals, arenas). That is correct but unparallelised, the same stance the stdlib's
serial thread backends take. A target test is used because the stdlib exposes no channel capability.

## Proposed fix (cyrius-side)

Either:

- give arm64 macOS a real channel: a mutex + condition variable (or `__ulock_wait` / `__ulock_wake`)
  around the ring, with `chan_recv` blocking until a value arrives or the channel closes, matching
  `lib/thread.cyr`; or
- export a capability (e.g. `CHAN_BLOCKING`) next to `THREADS_CONCURRENT`, so consumers can choose a
  strategy without testing target names (the v6.5.36 / v6.5.44 rule the stdlib already states for
  threads).

Once a real channel lands, sandhi can key `_sandhi_server_pool_inline` on that capability instead of
`CYRIUS_TARGET_LINUX`, and macOS gets a parallel pool.
