# `fl_alloc` / `fl_free` are not thread-safe, and nothing says so

**Status:** 🔴 OPEN — filed from a consumer (majra), not fixed here.
**Discovered:** 2026-08-10, v6.5.18, chasing an intermittent CI failure in majra's
`test_relay_receive_is_reentrant`.
**Severity:** High — silent memory corruption, and the failure mode looks like a bug in
the consumer's own logic rather than in the allocator.

## The defect

`lib/freelist.cyr` maintains per-size-class free lists in the global `_fl_heads` array
and manipulates them with **plain loads and stores**:

```cyr
var head = load64(&_fl_heads + cls * 8);
if (head != 0) {
    store64(&_fl_heads + cls * 8, load64(head));   // pop
    store64(head, 0);
    return head + 16;
}
```

`grep -c 'mutex_lock\|atomic_cas' lib/freelist.cyr` → **0**, in 6.5.14, 6.5.17 and
6.5.18 alike. This is long-standing, not a regression.

Two threads reaching that pop together both read the same `head` and both return
`head + 16`. **The same block is handed to two callers.**

## Why it is worse than an ordinary data race

The corruption does not present as a crash at the allocation site. It presents as
*wrong data in the consumer's structures*, arbitrarily far away:

majra's relay keeps a per-sender dedup table. Two threads called `relay_receive`
concurrently, each having allocated its message with `fl_alloc(64)`. When both got the
same block, one sender's message arrived carrying the **other sender's sequence number**,
so the relay correctly rejected it as a duplicate. The visible symptom was:

```
FAIL: every strictly-increasing message from sender-a is accepted
FAIL: no message was wrongly dropped as a duplicate
```

which reads exactly like a bug in the dedup logic — a place with a mutex around it that
had recently been audited for reentrancy. It took an A/B under artificial contention to
find that the allocator was the racing party. Under heavier load the same test **faulted**
rather than failing an assertion.

Measured, 40 concurrent instances of the same binary:

| build | failures |
|---|---|
| allocating inside the threads | **4 / 40** (one a core dump) |
| allocations hoisted off the concurrent path | **0 / 40** |

## What the docs say

Nothing. `lib/freelist.cyr`'s header describes the layout and the size classes and does
not mention threads. `fl_alloc`'s own comment does not either. A consumer reading it has
no way to learn the constraint short of reading the body and noticing the absent
synchronisation — and the natural reading of "a free-list allocator" is that it behaves
like the global `alloc`.

**`alloc` does NOT carry the same hazard** — checked, since a consumer that discovers
`fl_alloc` is unsafe reaches for `alloc` next. `lib/alloc.cyr:28` documents "a process-wide
CAS spinlock serializes `alloc()`/`alloc_reset()` across ALL threads" and implements it.
So the two allocators sitting side by side in the same stdlib have **opposite** threading
contracts, and only one of them says so. That asymmetry is most of why this is easy to get
wrong: `fl_alloc` reads as the faster `alloc`, not as a different contract.

## Expected

One of, in preference order:

1. **Make it thread-safe.** A per-class lock, or a CAS loop on the head pointer — the pop
   is a single-word compare-and-swap, which `lib/atomic.cyr` already provides.
2. **Provide a documented safe variant** (`fl_alloc_locked`, or an explicit per-thread
   arena) and say plainly in the header that the bare form is single-threaded.
3. **At minimum, document it.** A one-line "⚠ NOT thread-safe: callers must not use this
   from more than one thread without external synchronisation" in the module header would
   have saved the whole investigation.

Option 3 alone is not really sufficient: the stdlib ships `thread.cyr` next to this, so
the combination is an inviting one, and the failure is silent.

## Consumer-side fix, for reference

majra 2.6.1 does two things, both of which are correct regardless of what happens here:

- `relay_receive_ex` allocated its result struct with `fl_alloc` **after** releasing its
  mutex. Moved inside the critical section — 16 bytes of fixed work in a section that
  already walks the subscriber list.
- The reentrancy test built its messages inside the worker threads, so it was racing the
  allocator rather than the relay. The messages are now built up front, which is what
  makes the test measure the thing it names.

Note the first of those is a *real* consumer bug that this issue's absence of
documentation made easy to write, and that no amount of care in the relay's own locking
would have caught.

## Repro

Any two threads calling `fl_alloc` of the same size class in a loop, then comparing the
returned pointers for uniqueness. majra's
`tests/test_core.tcyr::test_relay_receive_is_reentrant` at 2.6.0 is a ready-made one —
run 40 copies concurrently.
