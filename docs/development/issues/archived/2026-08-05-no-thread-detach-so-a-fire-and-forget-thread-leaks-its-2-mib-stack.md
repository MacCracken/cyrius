# No `thread_detach`, so a fire-and-forget thread permanently leaks its 2 MiB stack and its TLS block — RESOLVED

**Status:** ✅ **SHIPPED — archived 2026-08-07 at v6.5.10.** shipped v6.5.8 as `thread_create_detached` + `thread_is_done`, both live on all three peers. 100 unjoined threads leaked 210,124,800 B of VA; now 0 — the child unmaps its own stack in the trampoline tail and the TLS is carved from that same mapping, so nothing is stranded. ⚠ `thread_is_done` is valid only BEFORE `thread_join`. Gate: tests/tcyr/vr01_thread_detach.tcyr.
**Originally filed as:** (fix shape **2**, `thread_create_detached`, plus the
`thread_is_done` predicate this file asked for under "Worth fixing alongside"). Re-verified live on
cycc **6.5.10**, 2026-08-07: the same `grep -nE '^fn thread_' lib/thread.cyr` that returned two
lines when this was filed now returns **four** —

```
304:fn thread_create(fp, arg): i64 {
389:fn thread_create_detached(fp, arg): i64 {
438:fn thread_is_done(t): i64 {
456:fn thread_join(t): i64 {
```

CHANGELOG [6.5.8] measures the close: 100 unjoined threads leaked **210,124,800 B** of VA
(exactly 100 × 2,101,248) and now leak **0**. **Both** resources named in this file's table are
covered, not just the 2 MiB: the child unmaps its own stack in the trampoline tail (musl's
`__unmapself` shape) and the TLS block is carved from the **top of that same mapping**, so one
`munmap` releases stack and TLS together; and no 24 B handle is allocated at all, because
`CLONE_PARENT_SETTID`/`CLONE_CHILD_CLEARTID` come off for a thread nobody joins
(`lib/thread.cyr:380-422`). The half-fix this file warned against — reclaiming the 2 MiB and
leaving 4 KB behind — was explicitly avoided.
⚠ **`thread_is_done` is valid only BEFORE `thread_join`**: join consumes the handle and on
Windows `CloseHandle()`s it, so a post-join query inspects a closed handle. The intended shape is
the reaper this file described — poll while running, join once it returns 1.

⛔ **ONE sub-note below did NOT ship, and it is not the filed defect.** §Root cause's last
paragraph — *"TLS is leaked on **every** thread including joined ones"* — is **still true at
6.5.10**. The **joined** path is unchanged: `thread_create` still takes its TLS block from the
bump allocator (`lib/thread.cyr:327`, `var tls = alloc(THREAD_TLS_SIZE);`) and `thread_join`'s
tail still calls only `munmap_stack(load64(t + 8), load64(t + 16))` — 4 KiB per joined thread
ever created, never reclaimed. Only the **detached** path carves TLS from the stack mapping. That
is a separate, much smaller item (4 KiB vs 2 MiB, and it needs `thread_create` to change where the
block comes from); it does not keep this file open. Re-file it on its own if a consumer measures it.

**Placement:** closed — ready to archive.
**Discovered:** 2026-08-05, building asynchronous crew submission in agnosai (a worker thread per delegated crew, with no caller to join it).
**Severity:** Medium — a real, unbounded leak in the one thread shape that has no other spelling, with no consumer-side fix available.
**Affects:** cycc 6.5.6 and earlier.

## Summary

`lib/thread.cyr` exposes `thread_create(fp, arg)` and `thread_join(t)` and
nothing else. **Every resource a thread owns is freed by `thread_join` and by
nothing else**, so a thread nobody joins leaks all of it, permanently, for the
life of the process.

Per unjoined thread, measured from the source:

| resource | size | freed by |
|---|---|---|
| stack (`mmap_stack`) | **2 MiB** (`THREAD_STACK_SIZE = 2097152`) | `thread_join` only |
| TLS block | 4 KiB (`THREAD_TLS_SIZE`) | nothing — never freed even on join |
| `Thread` handle | 24 B (`THREAD_SIZE`) | nothing — bump-allocated |

`thread_join` (`lib/thread.cyr:284-298`) futex-waits on the `CLONE_CHILD_CLEARTID`
slot and then calls `munmap_stack(load64(t + 8), load64(t + 16))`. That
`munmap_stack` is the **only** call site that reclaims a thread stack.

## Why a consumer cannot work around it

The obvious workarounds are all unavailable, which is what makes this worth
filing rather than absorbing:

1. **The thread cannot free its own stack.** It is *running on* that stack when
   its body returns, and the trampoline's next instruction after `call rax` is
   `SYS_EXIT` (`_thread_spawn`, `lib/thread.cyr:133-160`). There is no epilogue
   the thread could hook to `munmap` itself, and unmapping the stack you are
   standing on is not something a consumer can arrange from Cyrius anyway.
2. **`thread_join` is the wrong shape for fire-and-forget.** Joining is exactly
   what the caller is trying not to do — the whole point of the pattern is that
   the submitting thread returns immediately.
3. **A reaper works but is not free, and is not always possible.** A consumer
   can retain every handle and join those whose work has visibly finished. That
   is bookkeeping every consumer with this pattern must now re-invent, it needs
   an out-of-band "is it done?" signal (the handle itself has no non-blocking
   status predicate — `thread_join` blocks unconditionally), and it still holds
   2 MiB per in-flight thread with no way to bound how long that lasts.

## Reproduction

Any fire-and-forget thread. The leak is visible as RSS/VSZ growth with no
corresponding live data:

```cyr
fn worker(arg): i64 { return 0; }

fn main(): i64 {
    alloc_init();
    var i = 0;
    while (i < 1000) {
        thread_create(&worker, 0);   # never joined
        sleep_ms(1);
        i = i + 1;
    }
    # ~2 GiB of stacks mapped, all of it dead: every worker returned long ago.
    sleep_ms(60000);                 # inspect /proc/self/status VmSize here
    return 0;
}
```

Each iteration maps 2 MiB that is never unmapped, so the process reaches ~2 GiB
of virtual mappings for 1000 threads that have all exited.

## Root cause

Not speculation — it is a missing API rather than a bug in the existing one.
`thread_create` allocates the stack and TLS; `thread_join` frees the stack. No
third path exists, and the clone in `_thread_spawn` passes no flag that would
make the kernel reclaim a userspace mapping (it could not — the mapping is the
consumer's, not the kernel's).

Note also that TLS is leaked on **every** thread including joined ones:
`thread_create` allocates `THREAD_TLS_SIZE` and `thread_join` frees only the
stack. 4 KiB per thread ever created is small, but it is unbounded in a
long-running server and is arguably a separate one-line fix.

## Proposed fix

> **Shape 2 is what shipped**, with exactly the `SYS_MUNMAP`-then-`SYS_EXIT` trampoline tail
> described below. Shape 1 (a reaper / free-list) was not needed. `thread_is_done` shipped too.

Two shapes, either of which closes it. The second is the smaller change.

**1. `thread_detach(t)`** — mark the handle so its resources are reclaimed when
the thread exits rather than when someone joins. This needs a reclaim path that
does not run on the dying stack: the usual answer is a small reaper the runtime
owns, or having the exiting thread hand its stack to a free-list that the next
`thread_create` unmaps.

**2. `thread_create_detached(fp, arg)`** — a create variant that allocates the
stack such that the thread can release it at exit. The standard trick is to
`munmap` from the trampoline *after* switching off the stack, immediately before
`SYS_EXIT`; since `_thread_spawn` already hand-writes that trampoline, the two
extra instructions have a natural home. `SYS_MUNMAP` followed directly by
`SYS_EXIT` never touches the stack in between.

Worth fixing alongside: free the TLS block in `thread_join`, and consider a
non-blocking `thread_is_done(t)` predicate — the `CLONE_CHILD_CLEARTID` slot the
join loop already reads (`load64(t) != 0`) is exactly that test, it is simply
not exposed, and without it a consumer-side reaper cannot tell which handles are
safe to join without blocking.

## Consumer-side workaround

**None shipped, because none is satisfactory.** agnosai's
`agnosai_orchestrator_submit_crew` (`src/orchestrator/orchestrator.cyr`) spawns
one thread per delegated crew and does not join it; the leak is documented in
place and accepted for now, with a reaper deferred. The comment there points at
this filing. A reaper would bound it but not close it, for the reasons above.
