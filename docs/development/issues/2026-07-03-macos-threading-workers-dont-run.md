# macOS/arm64: `thread_create` does not run the worker (threading broken on ecb)

> ## ✅ v6.5.11 — THE FILED SYMPTOM IS FIXED. The worker now runs.
>
> `lib/thread_macos.cyr` now exists: macOS routes to a **serial fallback**, exactly as Windows
> has since v6.0.53 (`thread_win.cyr`) and agnos since v6.2.3 (`thread_agnos.cyr`). The thread
> body runs INLINE, so `thread_create` executes the worker and `thread_join` returns 0.
>
> Measured on **real ach (Intel Mac)**, encoding four separate facts in the exit code —
> handle non-null (+1), join==0 (+2), worker ran exactly once (+4), worker received its arg (+8):
>
> ```
> Linux (real clone threads) : 15
> ach   (serial fallback)    : 15   ← identical
> ```
>
> The three cross-host guards that asserted only a TAUTOLOGY on macOS
> (`assert_eq(rj, rj)`, `assert_eq(_vs_counter, _vs_counter)`, `assert_eq(mrc, mrc)`) have been
> **removed** — `crossos/thread_spawn`, `crossos/sync_mutex` and `crossos/thread_detach` now run
> the SAME assertions on macOS as on every other target, including `_vs_counter == 8000`. All
> three pass on ach. (`thread_detach`'s VA-leak assertion stays Linux-only, correctly: it reads
> `/proc/self/statm` and exercises the Linux asm unmap trampoline.)
>
> ### How it surfaced, because the sequence matters
>
> This was NOT found by looking for it. v6.5.11 fixed `MAP_ANONYMOUS` (Linux `32` was shadowing
> Darwin's `0x1000`), and that fix turned macOS threading from a silent no-op into a **SIGSYS
> crash** — `mmap_stack` had been FAILING on Darwin, so `thread_create` bailed at `sbase < 0`
> and never reached the clone. **A broken constant was acting as the accidental safety net for a
> missing backend.** Bisected on ach with only `lib/mmap.cyr` swapped: pre-fix `exit=0`, post-fix
> `exit=140` (128+12 = SIGSYS).
>
> The first proposed repair was to guard `thread_create` into a polite no-op. The maintainer
> rejected that — correctly: it would have re-created the same silence deliberately, and the
> serial fallback (a twice-proven existing pattern) makes the thing actually work instead.
>
> ### ⚠ WHAT REMAINS OPEN — this issue does NOT close
>
> Threading on macOS is now **correct but UNPARALLELIZED**. Consumers using threads for
> throughput get right answers, serially. A genuinely concurrent Darwin backend
> (`bsdthread_create` / `__ulock_wait`) is still unwritten and remains the **Slot 11** item, as
> does the second gap this file's own body records: `lib/sync_macos.cyr` is a 2-state
> `atomic_cas` spinlock, not a blocking lock.

**Status:** 🟡 **OPEN — narrowed at v6.5.11.** The filed symptom (worker never runs) is FIXED via
the serial fallback; what remains is REAL CONCURRENCY on Darwin, plus the blocking-lock gap.
Original status follows: no macOS thread backend exists. **Re-verified against live code on cycc
6.5.10, 2026-08-07:** `lib/` contains `thread.cyr`, `thread_agnos.cyr`, `thread_local.cyr` and
`thread_win.cyr` — **there is still no `thread_macos.cyr`** — and `grep -rn 'bsdthread_\|__ulock_'
lib/` now returns exactly **one** line, the comment at `lib/alloc.cyr:37` naming the gap. *(This
file previously listed four comment hits — `alloc.cyr`, `sync.cyr`, `sync_macos.cyr`,
`thread_local.cyr`; three of those have since been reworded away. Re-derive the grep, don't trust
the list.)* The VR-01 guards described below are still in place
(`tests/tcyr/vr01_thread_spawn.tcyr:31/:46`, `vr01_sync_mutex.tcyr:41/:44`), so the gap stays
smoke-covered rather than silently green.

⚠ **WIDER THAN THIS FILE STATES, and the 6.5.x concurrency work made the gap BIGGER, not smaller.**
macOS concurrency is **two** gaps and this filing names one. `lib/sync_macos.cyr` is a 2-state
`atomic_cas` **spinlock**, and its own header records that a blocking lock is a separate follow-on.
Neither v6.5.8's `thread_create_detached` work nor v6.5.9's three-state futex mutex touched it —
the v6.5.9 CHANGELOG says outright that "the macOS / Windows / agnos branches are untouched" — so
the Linux↔macOS mutex gap widened from parity to **48 ns futex vs a spinlock**. Both halves must
land together; see the Placement slot.

**Placement:** **v6.5.x Slot 11 (`.39`) — "macOS-arm64 concurrency", last in the minor**
(`roadmap.md` v6.5.x slot table, verified live 2026-08-07). Scoped there as **both** gaps in one
release: `lib/thread_macos.cyr` driving `bsdthread_create` + `bsdthread_register` (mirroring the
`thread_win.cyr` split), **and** `__ulock_wait`/`__ulock_wake` replacing `sync_macos.cyr`'s spinlock
for the mutex + channel wait/wake. Distinct from the Intel-Mac x86 toolchain tail, which closed at
v6.4.59. No consumer is blocked yet, which is why it sits behind the IR-substrate anchor. 6.x line,
never 7.x.
**Downstream:** most of the 23 full-corpus ecb failures in
[`2026-08-05-cross-os-full-corpus-23-failures-on-ecb.md`](2026-08-05-cross-os-full-corpus-23-failures-on-ecb.md)
are downstream of this — that count drops when this slot lands.

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

## Coverage today (unchanged since v6.3.43; re-checked 2026-08-07 on 6.5.10)

`vr01_sync_mutex` + `vr01_thread_spawn` guard the worker-ran / counter / channel
assertions to `#ifndef CYRIUS_TARGET_MACOS`, and on macOS assert only that the thread
API is **callable without faulting**. So the gap is documented + smoke-covered, not
silently green. When the macOS thread backend lands, un-guard those assertions —
`vr01_thread_spawn.tcyr:31`/`:46` and `vr01_sync_mutex.tcyr:41`/`:44`, four guards, which is
the roadmap's stated acceptance for Slot 11 (green on **real ecb**, not a hello-world smoke).
