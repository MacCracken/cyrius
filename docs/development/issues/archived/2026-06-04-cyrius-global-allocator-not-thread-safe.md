# cyrius global allocator is not thread-safe — blocks any multi-threaded accept loop (race audit 2026-06-04)

> **Status**: ✅ RESOLVED in v6.0.64 — recommended fix (b): a process-wide CAS spinlock (`_alloc_lock`)
> serializes `alloc()`/`alloc_reset()` across all four allocator peers + a CAS-publish for the
> `default_alloc()` singleton, closing all three races (bump-pointer, grow, lazy-init). Two latent
> aarch64 bugs surfaced and were fixed in the same release: (1) a missing post-CAS acquire `atomic_fence`
> in `_alloc_lock_acquire` (the CAS is plain `ldxr/stxr` with no ordering on aarch64); (2) the aarch64
> ELF var-area base was only 4-byte aligned, so `atomic_cas` on a *global* SIGBUS'd — fixed by rounding
> the code size to 8 in `src/backend/aarch64/fixup.cyr` (now atomic-on-any-global works, matching x86).
> Verified: new `alloc_thread_safe.tcyr` (fails 5/5 without the lock, passes with) + a 4-thread contended
> run on real aarch64 hardware; self-host byte-identical on x86_64 + aarch64 (pi native+cross) + macho-arm
> (ecb) + Windows (cass); check.sh 85/85. See CHANGELOG [6.0.64].
>
> **Original (race audit 2026-06-04)**: Observed by a
> consumer on cyrius 6.0.57** (a multi-threaded accept loop; race audit 2026-06-04). This is a
> **PRE-EXISTING limitation of the global allocator — NOT introduced by v6.0.61.** Linux threads
> (`clone`/`futex` in `lib/thread.cyr`) have been REAL since long before 6.0.57, so the race has been
> latent on every real-threads target all along; v6.0.61 only *broadened the exposure to Windows* by
> replacing the v6.0.53 serial fallback with real `CreateThread` threads. The threading primitives
> themselves (`thread_create`/`thread_join`, `mutex`, channels) are CORRECT — futex/`CLONE_CHILD_CLEARTID`
> join, `atomic_cas`+futex mutex, Windows `SRWLOCK`. **The bug is allocation-only**: the global bump
> allocator (`lib/alloc.cyr`) has no synchronization, so any `alloc()` inside concurrent threads races.

## Symptom

A consumer's multi-threaded accept loop is **BLOCKED** (their verbatim note, race audit 2026-06-04):

> Multi-threaded accept loop — BLOCKED: the cyrius global allocator is not thread-safe — concurrent
> `alloc` corrupts memory (verified ~5000 corruptions across 4 threads). All stdlib allocation routes
> through the global allocator (the allocator-as-parameter convention in `alloc.cyr` keeps the global
> fns racy for back-compat), so per-thread arenas do not help and a global processing mutex would
> serialize all request handling. Threading primitives themselves (thread_create/join, mutex,
> channels) work. Revisit when cyrius provides thread-safe allocation.

The workers spawn fine and the thread primitives behave, but as soon as worker bodies allocate
(directly or via `vec_push` / `str_cat` / `map_set`), the heap corrupts.

Precise mechanism:
- cyrius threads are REAL preemptive threads sharing ONE process heap via `CLONE_VM` (Linux:
  `lib/thread.cyr:5` "Threads share the process address space (CLONE_VM)", flag at `:202`; Windows:
  v6.0.61 `CreateThread`). All globals — including `_heap_ptr` — are visible and mutable from every
  thread.
- `alloc()` does an unsynchronized load-modify-store on the global bump pointer. Two threads
  interleave: T1 reads `_heap_ptr=X`, computes `X+500` (not yet stored); T2 reads `_heap_ptr=X`,
  computes `X+300`, stores `X+300`; T1 then stores `X+500`. Both believe they own distinct regions,
  but `[X, X+300)` overlaps — subsequent writes clobber each other.
- With 4 threads each issuing ~1000+ allocs the collision space is large; ~5000 surface as detectable
  corruption.

The threading machinery is exonerated: join uses `CLONE_CHILD_CLEARTID` + SHARED `FUTEX_WAIT`
(`lib/thread.cyr:240,247`), mutex uses lock-free `atomic_cas` + `FUTEX_WAIT|FUTEX_PRIVATE_FLAG`
(`:282,287`), channels gate the ring buffer with a mutex (`:311-356`), Windows uses a true `SRWLOCK`
(`lib/thread_win.cyr:62-72`). None of these call `alloc()` in their critical sections.

## Root cause

`lib/alloc.cyr` is a pure bump allocator over a `brk`-managed region, with three unprotected mutable
globals:

```
var _heap_base = 0; var _heap_ptr = 0; var _heap_end = 0;   # alloc.cyr:35-37
```

Two distinct races:

1. **Bump-pointer race** — `lib/alloc.cyr:70-74`: `var ptr = _heap_ptr;` → `var new_ptr = ptr + size;`
   → `_heap_ptr = new_ptr;`. Three separate ops, no lock / CAS / barrier. Concurrent threads
   overlap-allocate (the ~5000-corruption mechanism above).
2. **Grow race** — `lib/alloc.cyr:75-86`: when `_heap_ptr > _heap_end`, the code computes `new_end`
   and calls `syscall(12, new_end)` (Linux `brk`, at `:79`), then stores `_heap_end = new_end`. `brk`
   is atomic OS-side so one syscall "wins", but BOTH threads then store their own `new_end` — the loser
   stores the FAILED value, corrupting `_heap_end`. The rollback only fires on brk-failure, not on the
   store race.

No `lock` / `atomic` / `mutex` / `cmpxchg` / barrier anywhere in `alloc.cyr` — naked reads/writes
throughout.

**Why per-thread arenas don't fix this today (the global-fn convention):** `lib/alloc.cyr` ships an
allocators-as-parameter vtable (`alloc_via` `:229`, `arena_allocator` `:372`, `bump_allocator`), but
it's optional. The entire stdlib (`vec`/`str`/`hashmap`/`json`/`sigil`/`tls_native`) and cycc itself
call the BARE global `alloc(size)`, which mutates `_heap_ptr` directly. The v5.8.35 `default_alloc()`
singleton (`alloc.cyr:466`, `var _default_allocator` `:478`) routes all back-compat wrappers through
ONE process-wide bump — that singleton IS the shared mutable state arenas are meant to eliminate, and
it's itself lazily initialized without synchronization (a third racy path: two threads both see
`_default_allocator == 0`, both build a vtable, one is lost). Even `arena_new()` bootstraps its
header/backing from the global `alloc()` (`alloc.cyr:136`), so arena CREATION races too. Per-thread
arenas help only code that EXPLICITLY uses `arena_alloc` — the 99% on global `alloc()` still races.

Observed in the wild as the documented-but-load-bearing gap:
- `lib/sigil.cyr` — `sv_batch_verify`'s worker spawn pre-warms crypto module init on the main thread
  so "the lazy `_*_inited` guards don't race across workers, and any init-time `alloc` … happens
  single-threaded (CLAUDE.md quirk #7: alloc/fl_alloc are not thread-safe)" (the quirk-#7 caveat
  appears at `lib/sigil.cyr:1304,1611`). The workers call `sv_verify_artifact_into`, which allocates
  transitively — safe today ONLY because of that hand-rolled single-threaded pre-warm.
- `lib/hashmap.cyr:516-519,537-540` — `map_u64_set` → `map_u64_set_a` → `default_alloc()` /
  `_map_u64_grow_a`, so any concurrent `map_set` in a worker trips the same race.

## Fix options (analysis — slotting is the leader's call)

**Recommended complete fix = (b)** (the only standalone option that closes BOTH races). (d) is the
scalability upgrade for the roadmap; (c) is not viable standalone. Per one-bug-one-complete-fix, the
macho/agnos missing-primitive blocker (below) should be packed into the SAME release as (b).

**(a) Atomic bump pointer** (`lock xadd` / `lock cmpxchg` on `_heap_ptr`)
- How: `atomic_fetch_add(&_heap_ptr, asz)` then bounds-check — expressible NOW; `lib/atomic.cyr`
  already ships `atomic_fetch_add` (`:87`) / `atomic_cas` (`:46`) / `atomic_fence` (`:116`) (arch-gated,
  not target-gated) and `&global` already emits a working address.
- Pros: lowest latency, no syscall on fast path, no lock cell; primitives already proven in the
  `thread.cyr` mutex.
- Cons: **half-fix.** The GROW path is not atomic and is the real bug; `lock xadd` blindly advances
  past `_heap_end`, can't roll back on OOM, and can't atomically move the THREE grow globals together.
  So it STILL needs (b)'s grow-lock → not standalone. macOS contiguity loop + agnos discontiguous
  chunks make a pure atomic-bump worse.

**(b) Single global allocation lock wrapping `alloc()`/`alloc_reset()`** — RECOMMENDED
- How: `var _alloc_lock = 0;` bracketing the whole body (fast + grow). Linux/macho = `thread.cyr`'s
  futex-mutex pattern; Windows = `thread_win.cyr` `SRWLOCK`. Cleanest: a target-dispatched
  `_alloc_lock()`/`_alloc_unlock()` pair beside each per-OS allocator.
- Pros: correct by construction — covers bump AND grow. Reuses proven machinery. One critical section,
  easy to audit. Matches the existing `thread_win.cyr:18` caveat.
- Cons: serializes all allocations (contention for an alloc-heavy accept loop); adds an
  `atomic_cas`+fence to every alloc even single-threaded (cycc's own hot path — perf-tax watch);
  `thread.cyr`'s mutex does an unconditional `FUTEX_WAKE` per unlock → needs a leaner internal lock to
  avoid a syscall-per-alloc. Pulling `thread.cyr` into `alloc.cyr` risks an include cycle
  (`thread.cyr` includes `alloc.cyr`) → factor the lock into `atomic.cyr` or a standalone helper.
- Effort: ~2-3 days. Linux+Windows near-free; the real work is the leaner lock + macho/agnos policy +
  4-target byte-identical self-host (Closeout 3b: ecb + cass).

**(c) Per-thread arenas + stdlib takes an `Allocator` handle**
- Pros: best scalability, zero contention, the vtable already ships (v5.8.33 arc).
- Cons: **defeated by the global-fn convention today** — every allocating signature would need an
  `Allocator` param (major-version blast radius across `vec`/`str`/`hashmap`/`json`/`http`/`sigil`/
  `tls_native` + every consumer + cycc internals), OR global `alloc()` resolves its arena from TLS =
  that's option (d). `arena_new` itself races on bootstrap. Standalone it does NOT fix the global-alloc
  race an accept loop hits. Effort: very high.

**(d) Thread-local bump arenas + shared slow-path for growth** — roadmap scalability upgrade
- How: keep the global `alloc()` entry (no signature churn), resolve a per-thread chunk from TLS
  (`lib/thread_local.cyr`), bump lock-free within it, take a SHARED lock only to `mmap`/`brk` a fresh
  chunk on exhaustion.
- Pros: lock-free common case + back-compat global `alloc()` (fixes (c)'s killer flaw) + lock only on
  rare grow. `thread_local.cyr` works on all 4 targets; workers auto-get a TLS block via `CLONE_SETTLS`.
- Cons: most moving parts; `alloc_reset()`/`alloc_used()` semantics murky across per-thread chunks;
  main thread must `thread_local_init()` before workers; TLS slot budget is only 16; grow-lock inherits
  the macho/agnos blocker; adds a TLS-read to cycc's single-threaded hot path (zero benefit there).
  agnos has no `clone`/`CLONE_SETTLS` → degrades to (b). Effort: small arc (2-4 slots).

### Missing primitives cyrius needs first (the honest pack-in)
- **macho blocking lock — NONE.** `lib/syscalls_macos.cyr:86` defines `SYS_FUTEX=202` (+ FUTEX_WAIT/
  WAKE/PRIVATE_FLAG `:142-144`), but **202 is the LINUX number — Darwin has no futex.** A blocking
  mutex on macho needs `__ulock_wait`/`__ulock_wake` (BSD ulock) or `pthread_mutex` via libSystem,
  neither exposed. Today only a CAS spinlock works on macho. (This bogus copied-number is itself worth
  fixing/removing so it can't be mistaken for a working primitive.)
- **agnos atomic-wait/futex — NONE** in the surveyed ABI (`lib/syscalls_x86_64_agnos.cyr`). Blocking
  lock impossible; only a CAS spinlock. An agnos-userland-ABI futex/park primitive must be proposed +
  frozen.
- **Multi-word atomic for grow — NONE.** No CAS across `_heap_base`/`_heap_ptr`/`_heap_end` together;
  any multi-word update needs a lock, not a single CAS.
- **Leaner internal lock — NONE.** No try-lock / wake-only-if-waiters variant; the existing
  `thread.cyr` mutex's unconditional `FUTEX_WAKE`-per-unlock would add a syscall per alloc even
  uncontended.
- **Fast-path atomics — present (no gap).** `atomic_fetch_add`/`atomic_cas`/`atomic_fence` ship in
  `lib/atomic.cyr`. Option (a)'s blocker is purely the grow path + Windows/macho/agnos blocking, not
  the atomics.

Net: macho's `SYS_FUTEX=202` is bogus and agnos has no futex at all, so on BOTH the (b) lock degrades
to a CAS spinlock (correct, burns CPU under contention). Ship the spinlock fallback + file the macho
`__ulock_wait`/`__ulock_wake` exposure and an agnos-userland-ABI futex proposal as separately-scoped
follow-ons.

## Scope / impact

**Blocked:** any consumer running concurrent threads that allocate — multi-threaded accept loops,
parallel batch verify (`sigil.sv_batch_verify` is safe only because it hand-rolls the single-threaded
pre-warm workaround), any worker that touches `vec`/`str`/`hashmap`/`json` after spawn.

**Still works:** all single-threaded code (cycc self-host is single-threaded — unaffected); the
threading primitives (`thread_create`/`join`, `mutex`, channels) themselves; concurrent code that
pre-allocates on the main thread and passes pre-built buffers via the arg pointer (the documented
workaround); explicit per-thread `arena_alloc` IF the arena is created on the main thread before spawn.

This is the exact cross-OS class of change that rotted silently before — verify byte-identical
self-host on ecb (macOS) + cass (Windows) per Closeout 3b before close.

## Notes

The gap is already half-documented in-tree: `lib/thread_win.cyr:18-20` carries "the bump allocator
(alloc.cyr) is not itself thread-safe, so thread bodies should avoid concurrent alloc() … pass
pre-allocated buffers via the arg pointer." The SAME constraint applies on Linux/macho/agnos but is
only noted in the Windows variant's header; sigil references it as "CLAUDE.md quirk #7". This issue
promotes that scattered caveat to a tracked, slot-able fix.
