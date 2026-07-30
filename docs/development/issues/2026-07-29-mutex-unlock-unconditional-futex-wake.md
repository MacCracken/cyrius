# `mutex_unlock` issues a FUTEX_WAKE syscall on every release — 394ns for an uncontended lock

**Status:** 🟡 **OPEN** — filed 2026-07-29. Verified against live code: `lib/sync.cyr:72-78` calls
`syscall(SYS_FUTEX, m, FUTEX_WAKE | FUTEX_PRIVATE_FLAG, 1, 0, 0, 0)` unconditionally, with no
waiter-present check and no third mutex state to base one on. First measured on cycc 6.5.0;
**re-verified on cycc 6.5.2 (2026-07-29, after the bayan/sandhi release): `mutex_lock_unlock` is
392ns, unchanged, and `lib/sync.cyr:72-78` still issues the unconditional wake.**
**Placement:** unpinned — 6.x-line backlog. Self-contained fix inside `lib/sync.cyr`; no ABI or
surface change (`MUTEX_SIZE` stays 8, `mutex_new`/`_lock`/`_unlock` signatures stay).
**Discovered:** 2026-07-29 while benchmarking agnosai's M5 orchestration layer.
**Severity:** Medium — silent perf gap, measured 8.6× on the primitive and it compounds. No consumer-side
workaround exists short of not using the stdlib mutex.
**Affects:** cycc 6.5.2 and every earlier version carrying `lib/sync.cyr`'s two-state futex mutex
(Linux backend only — the Windows SRWLOCK and macOS spinlock backends are not affected).

## Summary

`lib/sync.cyr`'s Linux mutex is a **two-state** futex lock: the cell is 0 (free) or 1 (held).
`mutex_lock` has a correct CAS fast path and never enters the kernel when the lock is free.
`mutex_unlock` has no fast path — it clears the cell and then calls `FUTEX_WAKE` **every time**,
whether or not any thread is parked.

Two states are not enough to know. With only 0 and 1, the releasing thread cannot distinguish
"nobody ever contended" from "somebody is asleep on this", so it must assume the latter and pay a
syscall. The comment at `lib/sync.cyr:74` says *"wakes one waiter (kernel no-ops the wake when none
are parked)"* — which is true of the wake and beside the point: the **syscall itself** is the cost,
and on a mitigated x86_64 kernel that is ~400ns of pure overhead on an operation whose fast path is
a 6ns CAS.

The result is that every lock-guarded stdlib structure is syscall-bound rather than atomic-bound.
Measured on the repro machine (x86_64, Linux 7.1.5, spectre mitigations on):

| op | time | note |
|---|---|---|
| `nop_loop` | 0ns | loop overhead |
| `alloc_16` | 9ns | a real memory op, for scale |
| `atomic_cas_hit` + `atomic_store` | 6ns | the lock's own fast path |
| **`mutex_lock` + `mutex_unlock`** | **394ns** | **~65× the CAS pair it is built on** |
| `mutex_lock` + `mutex_unlock`, wake line deleted | **46ns** | **8.6× — the syscall is the cost** |
| `chan_try_send` + `chan_try_recv` | 1.590µs | ~4 mutex pairs' worth |

The channel row is where it stops being academic. `chan_try_send`/`chan_try_recv` each take the
channel's mutex, so a single-producer/single-consumer round trip on a ring that is never full and
never empty — no slow path taken anywhere — costs **1.59µs**. In agnosai that sets the floor for the
whole event layer: an SSE fan-out to 64 subscribers measures 101µs, of which ~99% is futex syscalls
for wakes nobody is waiting for.

## Reproduction

`docs/development/issues/repros/2026-07-29-mutex-unlock-unconditional-futex-wake.bcyr`

```sh
cyrius bench docs/development/issues/repros/2026-07-29-mutex-unlock-unconditional-futex-wake.bcyr
```

Single-threaded, so no waiter is ever parked and **every** `FUTEX_WAKE` in the run is wasted.
`atomic_cas_hit` is in the repro deliberately: it measures the exact primitive `mutex_lock`'s fast
path is built from, so the gap between 6ns and 394ns cannot be blamed on loop or bench overhead.

Expected: `mutex_lock_unlock` within a small multiple of `atomic_cas_hit` — single-digit to low
double-digit ns. Actual: 394ns, i.e. a syscall.

### The syscall is the whole cost — measured, not inferred

Rather than argue it from the timer, delete the one line. Copy `lib/sync.cyr` aside, drop
`mutex_unlock`'s `syscall(SYS_FUTEX, ...)`, change nothing else, and re-run the same loop:

| `mutex_lock` + `mutex_unlock` | time |
|---|---|
| as shipped | **394ns** |
| with the `FUTEX_WAKE` line removed | **46ns** |

**8.6×**, and it accounts for 348 of the 394ns. The remaining 46ns is the two `atomic_fence` calls
plus the CAS, which is where an uncontended lock should be.

The patched build is only valid single-threaded — with the wake gone outright a real waiter would
never be woken — so this measures the size of the prize, not a candidate fix. The candidate fix is
below, and it reaches the same fast path while keeping the wake for the case that needs it.

`chan_try_send` + `chan_try_recv` at 1.590µs is roughly four mutex pairs, so the same order of
improvement should follow there. That one is an inference from the ratio, not a measurement.

## Root cause

`lib/sync.cyr:72-78`:

```cyrius
fn mutex_unlock(m): i64 {
    atomic_fence();   # release barrier
    atomic_store(m, 0);
    syscall(SYS_FUTEX, m, FUTEX_WAKE | FUTEX_PRIVATE_FLAG, 1, 0, 0, 0);
    return 0;
}
```

The syscall is unconditional. The two-state design at `lib/sync.cyr:59-69` is what forces it: after
`atomic_store(m, 0)` the old value is already gone, and even before the store, `1` carries no
information about whether a waiter exists.

Note this is a *design* gap rather than an oversight — the module's header is explicit that it
mirrors `lib/thread.cyr`'s "proven mutex", and it inherited the two-state shape along with the
correctness. The lock is correct. It is only slow.

## Proposed fix

The standard three-state futex mutex (Drepper, *Futexes Are Tricky*, §6 "Mutex, Take 3"). Cell
values become 0 = free, 1 = held with no waiters, 2 = held with at least one waiter. Unlock then
calls `FUTEX_WAKE` only when it observes 2, which is exactly the case where a waiter exists:

```cyrius
# Blocking acquire. 0 = free, 1 = held, 2 = held with waiters.
fn mutex_lock(m): i64 {
    var c = atomic_cas_val(m, 0, 1);          # see note below
    if (c != 0) {
        # Announce a waiter before parking, and keep the cell at 2 for as long
        # as one exists — a lock re-acquired as 1 would lose the wake.
        while (c != 0) {
            if (c == 2 || atomic_cas_val(m, 1, 2) != 0) {
                syscall(SYS_FUTEX, m, FUTEX_WAIT | FUTEX_PRIVATE_FLAG, 2, 0, 0, 0);
            }
            c = atomic_cas_val(m, 0, 2);      # re-acquire AS 2, not 1
        }
    }
    atomic_fence();
    return 0;
}

# Release. Only enters the kernel when a waiter announced itself.
fn mutex_unlock(m): i64 {
    atomic_fence();
    if (atomic_swap(m, 0) == 2) {
        syscall(SYS_FUTEX, m, FUTEX_WAKE | FUTEX_PRIVATE_FLAG, 1, 0, 0, 0);
    }
    return 0;
}
```

Two subtleties that make or break it, flagged because both are easy to drop:

1. **The re-acquire in the wait loop must store 2, not 1.** A thread that wakes, wins the lock, and
   sets the cell to 1 has erased the fact that *other* threads are still parked; the next unlock
   sees 1, skips the wake, and those threads never run. Storing 2 is conservatively correct — it
   costs a spurious wake after the last waiter leaves, never a lost one.
2. **`mutex_unlock` needs the pre-store value**, so plain `atomic_store` will not do. The sketch
   above uses `atomic_swap`, and the fast path in `mutex_lock` uses a CAS that *returns the observed
   value* rather than a 0/1 success flag.

That second point is a real blocker for a consumer-side fix and may be one for the stdlib too:
**`lib/atomic.cyr` currently exposes neither.** `atomic_cas(ptr, expected, new)` returns success as
0/1 and discards the observed value, and there is no `atomic_swap` / `atomic_exchange` at all. Both
are single instructions on both supported arches (`lock cmpxchg` already computes the old value into
`rax` and it is simply not returned; `xchg` for the swap; `casal`/`swpal` on aarch64), so this is a
plumbing gap rather than a design question. A three-state mutex needs them, and so does any
consumer wanting to hand-roll one — which is why there is no workaround to document below.

If adding to `lib/atomic.cyr` is out of scope for the release that takes this, a narrower fix gets
most of the win: keep two states, but have `mutex_unlock` skip the wake when it can prove no waiter
exists. That proof needs a separate waiter counter incremented before `FUTEX_WAIT` and decremented
after, which costs another 8 bytes (breaking `MUTEX_SIZE = 8`) and two more atomics — strictly worse
than three states. Recommend doing it properly.

## Consumer-side workaround

None available. `atomic_cas`'s 0/1 return and the absence of `atomic_swap` mean a consumer cannot
build a three-state mutex out of what `lib/atomic.cyr` exposes, so there is nothing to vendor.

agnosai has **not** worked around this. Its orchestration layer takes one mutex per bus/hub
operation and its benchmarks record the current numbers as the Cyrius baseline; a fix here will show
up as a straight improvement in `bench-history.csv` (`event_round_trip_1_sub`,
`event_fanout_64_subs`, `pubsub_publish_4_patterns`) rather than requiring any change on the
consumer side.

## Related

- `2026-07-28-sock-send-result-allocates-per-call.md` — also a per-operation cost in a hot stdlib
  path, also invisible until benchmarked. Same shape of finding, unrelated mechanism.
