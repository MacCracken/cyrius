# `sys_fork` from a threaded process can hand the child an allocator lock nobody will release — open

**Status:** 🟡 **OPEN** — verified against `lib/alloc.cyr` (`_alloc_lock`) and `lib/freelist.cyr` (`_fl_lock`) on the 6.7.18 snapshot, 2026-11-02. bote 3.7.0 takes both locks itself around its fork; nothing in the stdlib does.
**Placement:** unpinned — 6.x-line backlog, never 7.x.
**Discovered:** 2026-11-02 during bote 3.7.0, moving an outbound fetch (forked into a child) onto worker threads
**Reporter:** bote v3.7.0 (MCP core service)
**Cyrius version at time of report:** 6.7.18
**Affected stdlib:** `lib/alloc.cyr` (`_alloc_lock_acquire` / `_alloc_lock_release`), `lib/freelist.cyr` (`_fl_lock_acquire` / `_fl_lock_release`), `lib/syscalls_*_linux.cyr` (`sys_fork`)
**Severity:** **Medium** — a hang, not corruption, in the child of a multi-threaded process that forks and then allocates. A parent that waits with a deadline, as bote does, loses the child's work; one that waits for ever hangs.

## Summary

`fork` copies only the calling thread. Once `_threads_active` is set, `alloc` and `fl_alloc` take spinlocks, and a lock another thread
held at the moment of the fork stays held in the child, where no thread will ever release it: the child's first allocation spins for good.
POSIX's answer is `pthread_atfork` (take the locks before the fork, release them on both sides after). Cyrius has no such hook, so the
only way to fork safely from a threaded program is to call the allocators' underscore-prefixed lock functions directly.

## Reproduction

bote's `tests/bote_threads.tcyr`, "a fork while another thread holds an allocator's lock": one thread holds `_alloc_lock` half the time
(acquire, spin 300, release, spin 300) while the main thread forks 24 children that each `alloc(64)` and answer over a pipe with a 3 s
deadline. With a plain `sys_fork`, children hang and the deadline ends them; with the locks held across the fork, 24 of 24 answer. The
same with `_fl_lock` and `fl_alloc`.

## Root cause

An absence: nothing between `sys_fork` and the allocators knows a fork is happening.

## Proposed fix

A public pair the allocators own, for example `alloc_fork_prepare()` / `alloc_fork_parent()` / `alloc_fork_child()`, or one wrapper
`fork_safe()` that takes `_fl_lock` then `_alloc_lock` (the order neither allocator nests them in), forks, and releases both on each
side. Any further stdlib lock a child is likely to need (the thread-local registry on aarch64 macOS, `chan` locks) belongs in the same
hook.

## Consumer-side workaround

bote 3.7.0's `_bf_fork` (`src/fetch.cyr`) does exactly that with the underscore functions when `_threads_active` is set, and plain
`sys_fork` otherwise. It is coupled to two stdlib internals by name, which is why this is filed.

## Severity rationale

Medium: needs a threaded program that forks and allocates in the child before exec, which is how a consumer isolates work the stdlib
would otherwise leak (bote's outbound HTTP, because of sandhi's TLS heap) — so the consumers most careful about memory are the ones it bites.

## Related

- sandhi `docs/development/issues/2026-11-02-bote-tls-connect-keeps-each-connection-on-the-heap.md` — why bote forks for a fetch at all.

## Pointers

- bote: `src/fetch.cyr` (`_bf_fork`); `tests/bote_threads.tcyr` ("fork: ...").
