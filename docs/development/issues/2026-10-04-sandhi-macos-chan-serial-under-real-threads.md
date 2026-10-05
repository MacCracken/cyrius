# 2026-10-04 — arm64 macOS starts real threads but keeps the serial channel

**Status:** 🟡 **OPEN** — cyrius-side (`lib/thread_macos.cyr`). sandhi works around it (1.10.7).
**Filed in:** `sandhi/docs/development/issues/2026-10-04-cyrius-macos-chan-serial-under-real-threads.md` (copied here 2026-10-04, unedited below this header).
**Placement:** **6.6.16** (user, 2026-10-04). ⚠ Same shape on **Windows**, measured from the source at the 6.6.16 slot: real `CreateThread` threads, a mutex-protected ring whose `chan_recv` never blocks (`lib/thread_win.cyr` ~180), and 6.6.16's N7 makes Windows report `THREADS_CONCURRENT = 1`. The complete fix covers both targets plus the capability.
**Severity:** **P2** — any producer/consumer built on `chan_*` across threads is broken on arm64 macOS, and
on every other target that still uses the serial ring. No error surfaces: the consumer simply sees an
empty channel.
**Reporter:** sandhi, from its first macOS CI run of a pooled-server row (1.10.7, `macos-14`, reproduced on
ecb).
**Toolchain:** cyrius 6.6.15.

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
