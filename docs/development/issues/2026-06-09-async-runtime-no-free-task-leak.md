# `lib/async.cyr` runtime + task structs leak (global bump, no free) — unbounded for a long-running accept loop

- **Filed**: 2026-06-09
- **Reporter**: sandhi (1.4.9 epoll-cooperative server `sandhi_server_run_async`; same shape daimon's `serve_async` already hits)
- **Affects**: `lib/async.cyr` (`async_new` / `async_spawn` / `async_run`) on any long-running batched accept loop.
- **Severity**: Medium — a server built on `async.cyr`'s batched accept model leaks a fixed amount **per connection** (the task struct) and **per batch** (the runtime struct), with no way to reclaim it. Bounded-lifetime / low-traffic consumers are fine; a long-running high-traffic server grows without bound.
- **Status (2026-06-09): OPEN.**

## Problem

The batched-cooperative server pattern (daimon `serve_async`, now sandhi
`sandhi_server_run_async`) is:

```
rt = async_new()
loop:
    accept up to N (non-blocking); for each: async_spawn(rt, handler, arg)
    if batch > 0: async_run(rt); rt = async_new()   # recreate — see below
    else: async_await_readable(sfd)
```

`rt` must be **recreated each batch** because `async_run` closes the runtime's
epoll fd on exit (`syscall(SYS_CLOSE, load64(rt))` at the end of `async_run`),
so the runtime is single-use. But:

- `async_new()` allocates the runtime struct (`RT_SIZE` = 32 B) from the global
  bump allocator (`alloc`).
- `async_spawn()` allocates each task struct (`TASK_SIZE` = 32 B) from the global
  bump.
- The global bump allocator has **no `free`** (`free_via` is a documented no-op),
  and `async.cyr` exposes no runtime/task cleanup.

So every drained batch leaks `32 + (batch × 32)` bytes that can never be
reclaimed — ~**32 B per connection** plus 32 B per batch, for the life of the
process. A server doing millions of requests leaks tens of MB+; it grows without
bound.

sandhi bounds *its own* per-connection allocations (recv buffers + handler arg
structs) with a `max_conns`-sized arena it resets each batch — but it cannot
touch `async.cyr`'s internal `alloc()` calls, so the runtime/task leak remains.

## Proposed fix (either is sufficient; (a) preferred)

**(a) Make the runtime arena-aware.** Add an allocator-taking constructor so the
runtime + its tasks come from a caller-owned arena the caller can `reset_via`
each batch:

```cyr
fn async_new_in(a): i64 { ... allocate rt from `a` ... }   # a = Allocator
# async_spawn already has rt; thread the allocator via rt (store the
# Allocator ptr in a new rt slot) so spawned task structs also come from `a`.
```

Then a server does `arena = arena_allocator(cap); rt = async_new_in(arena); …;
async_run(rt); reset_via(arena);` and nothing leaks. Keep `async_new()` as a
thin wrapper over `async_new_in(bump_allocator())` for back-compat.

**(b) Don't close the epfd in `async_run`; add `async_reset(rt)` / `async_free(rt)`.**
Let `async_run` leave the runtime reusable (move the `SYS_CLOSE` into an explicit
`async_free`), and add `async_reset(rt)` that clears the task list so one runtime
+ one epfd is reused across batches. Task structs would still need an allocator
story for true zero-leak, so (a) is the more complete fix.

## Acceptance

- A batched accept loop (`async_new_in(arena)` + per-batch `reset_via(arena)`)
  serving M connections allocates O(max_conns) memory, not O(M) — RSS flat over a
  sustained request stream.
- `async_new()` / `async_spawn()` / `async_run()` unchanged for existing callers
  (back-compat).

## Related / consumer side

- sandhi `src/server/mod.cyr` `sandhi_server_run_async` (1.4.9) — references this
  issue in its memory note; bounds its own buffers via an arena, awaits this fix
  to eliminate the residual runtime/task leak.
- daimon `serve_async` — same pattern, same leak (recreates `rt` per batch).
- Root cause is the global bump allocator's no-free contract; the arena-aware
  constructor is the idiomatic cyrius answer (mirrors the `_a` / allocator-as-arg
  pattern already used across the stdlib + sandhi).
