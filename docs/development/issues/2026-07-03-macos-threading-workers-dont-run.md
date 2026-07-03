# macOS/arm64: `thread_create` does not run the worker (threading broken on ecb)

**Filed:** 2026-07-03 (surfaced by the v6.3.43 VR-01 platform-variant tcyr —
`tests/tcyr/vr01_sync_mutex.tcyr` + `vr01_thread_spawn.tcyr` — running on real ecb
(macOS arm64) hardware). The exact found-by-ports rot VR-01 exists to reveal.
**Severity:** P2 — a whole stdlib subsystem (threads / mutex / channels) is a silent
no-op on macOS. No first-party macOS consumer threads today, so nothing is blocked
*yet*, but any concurrent macOS program would silently mis-run.

## Symptom (real hardware, ecb macOS arm64)

`lib/thread.cyr`'s `thread_create(fp, arg)` returns a non-null handle and
`thread_join` returns 0, but **the worker function never executes**:

- `vr01_sync_mutex`: 8 workers × 1000 locked increments → shared counter is **0**
  (expected 8000). Not lost updates — the workers never ran at all.
- `vr01_thread_spawn`: after `thread_create(&worker,42)` + `thread_join`, the worker's
  side effects (`_vr_done`, `_vr_sum`) are untouched (0). `chan_recv` on an MPSC
  channel also fails (it blocks on the same primitive the workers need).

Both PASS on **Linux** (clone+futex) and **Windows/cass** (CreateThread + a Win32
channel), so this is specifically the macOS thread backend.

## Likely cause

macOS has no `clone(2)`; thread creation must go through `bsdthread_create` (+
`bsdthread_register` / a thread-start trampoline) or libSystem `pthread_create`. If
`thread_create` on macOS falls through to a Linux `clone`-shaped path (or a stub),
`bsdthread_create` is never issued, so no kernel thread is spawned and the worker is
dead code. The futex-based mutex/channel wait (`lib/thread.cyr`) also needs the macOS
`__ulock_wait`/`__ulock_wake` equivalents, not Linux `futex`.

## Fix (its own focused slot — a macOS thread backend)

Mirror the `thread_win.cyr` split: a `lib/thread_macos.cyr` that drives
`bsdthread_create` + `bsdthread_register` (or `pthread_create` via libSystem) for
`thread_create`/`thread_join`, and `__ulock_wait`/`__ulock_wake` for the mutex +
channel wait/wake. Validate on ecb with the VR-01 threading tcyr (restore their
`#ifdef CYRIUS_TARGET_MACOS`-guarded worker/counter assertions to the full checks).

## Coverage today (v6.3.43)

`vr01_sync_mutex` + `vr01_thread_spawn` guard the worker-ran / counter / channel
assertions to `#ifndef CYRIUS_TARGET_MACOS`, and on macOS assert only that the thread
API is **callable without faulting**. So the gap is documented + smoke-covered, not
silently green. When the macOS thread backend lands, un-guard those assertions.
