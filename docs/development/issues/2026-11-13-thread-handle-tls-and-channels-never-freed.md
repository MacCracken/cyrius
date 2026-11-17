# `thread_join` keeps the thread's handle and TLS block, and a channel can't be freed — open

**Status:** 🟡 **OPEN**, verified on cyrius 6.7.18 (x86_64), 2026-11-13.
**Discovered:** 2026-11-13, by pravash 2.0.1's hardening review (its worker pool, `pravash/src/par.cyr`).
**Reporter:** pravash (conversion ledger L17; `pravash/docs/development/pravash-port-plan.md` §8).
**Severity:** Low–medium. Nothing is corrupted. A library that starts and stops threads grows the heap without bound.

## Summary

`thread_create` takes the thread's 24-byte handle (`THREAD_SIZE`) and its 4,096-byte TLS block (`THREAD_TLS_SIZE`)
from `alloc`, the bump heap. `thread_join` unmaps the stack, but it can't return either block, because `alloc` never
frees. `chan_new` takes its 56-byte record (`CHAN_SIZE`), the ring buffer (`cap · 8 + 32`) and a mutex from the same
heap, and there is no `chan_free`.

## pravash's numbers

A solver's pool of T threads is the caller plus T − 1 workers, each on its own job channel, with one answer channel.
Starting and stopping one pool of 4 threads leaves **12,792 bytes** on the bump heap. That is 3 × (4,096 + 24) for
the threads, and the four channels with their rings and mutexes. Measured with `alloc_used()` around
`new → set_threads(4) → step → drop` of a `FluidGrid`.

pravash starts a pool once per thread-count change, never per step, so a step's heap stays flat. A consumer that
makes a threaded solver per effect, or changes its thread count each frame, grows by that much each time. Before
2.0.1, `set_threads` with an unchanged count also restarted the pool: 12.8 KB a frame.

## Asked for

1. **`thread_join` releases the handle and the TLS block.** For example, take both from the freelist (`fl_alloc`), or
   from the stack mapping, which `thread_join` already unmaps.
2. **A `chan_free(ch)`** for a channel no thread is using, which releases the record, the ring and the mutex.

pravash converts its L17 row when both land: the pool frees its channels on stop, and par.cyr's note goes.
