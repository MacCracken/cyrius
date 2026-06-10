# `lib/alloc.cyr` Linux `alloc_init()` is not idempotent — every recall mmaps a fresh 256 MB chunk + resets heap state (regression from the v6.1.19 brk→chunk switch)

> **RESOLVED v6.1.23** — added `if (_heap_base != 0) return <base>` to `alloc_init()`
> in ALL FOUR allocators (`lib/alloc.cyr` Linux, `alloc_macos.cyr`,
> `alloc_agnos.cyr`, `alloc_windows.cyr`); a re-call once the heap is up is a no-op.
> Verified x86_64 + aarch64 (qemu): re-init no longer resets `alloc_used` /
> relocates the bump pointer. Two-step self-host byte-identical (heap change; cycc
> +48 B); cross-OS ecb + cass `SELFHOST_OK`. See CHANGELOG [6.1.23].

- **Filed**: 2026-06-09 (surfaced while fixing the async runtime/task leak, v6.1.22)
- **Affects**: `lib/alloc.cyr` Linux (`CYRIUS_TARGET_LINUX`) `alloc_init()`. Any code that calls `alloc_init()` more than once — notably `lib/thread.cyr` (per-thread init, lines ~167/271/314), `lib/thread_local.cyr` (82/187), `lib/sync_*.cyr`.
- **Severity**: Medium (latent). No data corruption observed (old chunks stay mapped, so previously-handed-out pointers remain valid), but **each recall leaks a fresh 256 MB virtual chunk** (lazy-committed, so RSS cost is only touched pages) and **resets `_heap_used`/`_heap_first_base`** out from under any concurrent user. In a multi-threaded program where each worker thread calls `alloc_init()` on entry, that's one abandoned 256 MB VA reservation per thread + an `alloc_used()` that no longer reflects reality. The recall is also NOT under `_alloc_lock`, so the reset races concurrent `alloc()`.

## Root cause

Pre-v6.1.19 the Linux heap was `brk`-backed; `alloc_init()` re-`brk`'d to the
current break (`_heap_base = brk(0)`), which allocated no new mapping — a recall
was effectively a cheap "continue from current top." v6.1.19 switched the Linux
heap to a chunk-based `mmap` bump allocator (to escape the glibc brk-arena
collision, issue 2026-06-09-brk-bump-heap-vs-fdlopen-libssl-malloc). The new
`alloc_init()` unconditionally `_linux_new_chunk(_LINUX_CHUNK)` — mmaps a fresh
256 MB chunk, repoints `_heap_base/_heap_ptr/_heap_end/_heap_first_*`, and zeroes
`_heap_used`. So a SECOND `alloc_init()` abandons the live chunk.

`async_new()` (lib/async.cyr) hit this directly — it called `alloc_init()` on
every runtime creation → a 256 MB chunk leak per batch in a long-running server.
**v6.1.22 worked around it by dropping the redundant `alloc_init()` from
`async_new()`** (lazy-init covers heap bring-up), but the underlying
`alloc_init()` footgun remains for every other repeated caller.

## Proposed fix

Make Linux `alloc_init()` idempotent — a no-op once the heap is initialized,
matching the lazy-init contract (`if (_heap_base == 0) { alloc_init(); }`):

```cyr
fn alloc_init(): i64 {
    if (_heap_base != 0) { return _heap_first_base; }   # already initialized
    var base = _linux_new_chunk(_LINUX_CHUNK);
    ...
}
```

Callers that genuinely want to free everything already use `alloc_reset()` (which
rewinds to the first chunk without re-mmapping). Verify: cycc calls `alloc_init()`
exactly once at startup → first-call behavior unchanged → self-host byte-identical;
a multi-threaded harness no longer leaks a chunk per thread.

Consider the same idempotency guard for `alloc_macos.cyr` / `alloc_agnos.cyr`
(both mmap-based and re-mmap on recall — pre-existing, not a v6.1.19 regression,
but the same footgun for repeated callers).

## Acceptance

- Repeated `alloc_init()` calls map memory only once; `alloc_used()` stays
  meaningful across calls.
- A thread harness spawning N workers (each calling `alloc_init()`) reserves one
  heap, not N.
- self-host byte-identical (Linux/macOS/Windows cycc unaffected — single
  startup call).
