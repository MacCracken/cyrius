# `alloc_reset()` scrubs and rewinds over the memoized default `Allocator`, so the next `vec_new()` calls through a zeroed vtable

**Status:** 🔴 **OPEN** — filed 2026-08-05, worked around consumer-side with a one-line store.
**Placement:** unpinned, but this is a hard crash in two stdlib calls used exactly as documented —
it wants a patch release, not the 6.x backlog. One store fixes it (see below).
**Discovered:** 2026-08-05 building a hisab 2.9.0 differential harness that had to reset the arena
between cases, because the geometry entry points under test never free.
**Severity:** High — SIGSEGV, jump to address 0, from `alloc_reset()` + `vec_new()`. No unsafe
construct, no FFI, no manual `store64` on the consumer side. Silent until it faults.
**Affects:** cycc 6.5.6 (verified). The shape is present in `lib/alloc.cyr` as written, so every
release carrying the memoized `default_alloc()` is a candidate.

## Summary

`default_alloc()` builds the process-wide default `Allocator` **inside the global bump arena** and
memoizes its address. `alloc_reset()` zeroes that region and rewinds the bump pointer back over it.
The memo is never cleared, so it survives as a pointer into scrubbed, re-issuable arena space.

The next allocation through the default allocator therefore loads a function pointer of `0` out of
the wiped vtable and calls it.

```
alloc_init();
vec_new();        # <- Allocator struct built at arena offset N, address memoized
alloc_reset();    # <- offset N zeroed, bump pointer rewound past it
vec_new();        # <- SIGSEGV
```

Both functions are being used for exactly what they document. `alloc_reset()` is the supported way
to reuse the arena; `vec_new()` is the ordinary vec constructor.

## Reproduction

[`repros/2026-08-05-alloc-reset-default-allocator-segv.cyr`](./repros/2026-08-05-alloc-reset-default-allocator-segv.cyr) —
12 lines, stdlib only, no project deps:

```
$ cyrius build 2026-08-05-alloc-reset-default-allocator-segv.cyr build/repro
OK
$ ./build/repro; echo "exit=$?"
first vec ok
reset ok
exit=139            # SIGSEGV
```

Adding `_default_allocator = 0;` on the line after `alloc_reset()` — and changing nothing else —
prints `second vec ok` and exits `0`. That one store is the entire difference.

Nothing about `vec` is special here; it is just the shortest path to `default_alloc()`. Any
`*_a`-family call that defaults its allocator reaches the same dead vtable. A routine using only
raw `alloc()` and `store64` survives the same sequence, which is what localises this to the memo
rather than to the arena rewind in general.

## Root cause

Three pieces, all in `lib/alloc.cyr`:

1. **`allocator_new` (:422–431)** puts the `Allocator` in arena memory:

   ```
   fn allocator_new(alloc_fn, realloc_fn, free_fn, reset_fn, state): i64 {
       var a = alloc(40);
       ...
   ```

2. **`default_alloc` (:653–681)** calls `bump_allocator()` → `allocator_new(...)` once, then
   CAS-publishes the result into the global `_default_allocator` (:647) and returns the memo
   forever after.

3. **`alloc_reset` (:243–262)** scrubs the reused span of the first chunk and rewinds:

   ```
   var span = _heap_ptr - _heap_first_base;
   if (_heap_base != _heap_first_base) { span = _heap_first_end - _heap_first_base; }
   if (span > 0) { _alloc_zero(_heap_first_base, span); }
   _heap_base = _heap_first_base;
   _heap_ptr  = _heap_first_base;
   ```

The struct is allocated after `alloc_init()`, so it always lies within
`[_heap_first_base, _heap_ptr)` — inside `span`, unconditionally. `alloc_reset` clears
`_heap_base`/`_heap_ptr`/`_heap_end`/`_heap_used` but not `_default_allocator`, which is the only
global in the file holding an address *into* the arena rather than a bound *of* it.

Worth separating: **the scrub is not the bug.** Without it the rewind still re-issues those 40
bytes to the next caller, so the vtable gets overwritten by unrelated data and the same call goes
somewhere arbitrary. The CVE-2026-34988-class zeroing only converts a nondeterministic
use-after-reset into a deterministic null jump — which is the better failure, and is how this got
found at all.

The register state at the fault follows from the path rather than from a debugger session: the
faulting call is the vtable's slot-0 `alloc` dispatch, made while allocating the 24-byte header
inside `vec_new_a`.

## Proposed fix

Preferred — **take the default `Allocator` out of the arena.** Back it with a file-scope buffer so
no arena operation can reach it:

```
var _default_allocator_storage[40];
```

`default_alloc()` then fills that buffer in place instead of calling `allocator_new`, and
`_default_allocator` becomes a constant address. Resets stop being able to invalidate it, the
lazy-init CAS dance goes away with them, and a program that resets in a loop stops re-allocating
40 bytes per reset.

Minimal — **clear the memo in `alloc_reset()`**, one store, under the lock it already holds:

```
_heap_used = 0;
_default_allocator = 0;     # memo pointed into the span just scrubbed
_alloc_lock_release();
```

This is correct single-threaded and is what the consumer-side workaround does. It is weaker under
threads: a peer that already read `default_alloc()` into a local still holds the dangling pointer.
Calling `alloc_reset()` while other threads allocate is unsound regardless, but the static-storage
form degrades better there — the vtable stays valid even when the rewind is racy.

Either way, `alloc_reset`'s doc comment should say that it invalidates every pointer previously
handed out, including ones the stdlib itself is holding. The comment currently reasons carefully
about the info-leak channel and says nothing about live references into the span.

## Consumer-side workaround

Cyrius has one flat global namespace, so a consumer can reach the memo directly:

```
alloc_reset();
_default_allocator = 0;    # force default_alloc() to rebuild in the fresh arena
```

hisab's 2.9.0 EPA differential harness carries exactly this. It is a stopgap and should be deleted
when the fix lands — a consumer poking a private stdlib global is precisely the shape that breaks
on a stdlib refactor.

## Consumer impact

No hisab release is affected: no hisab source, test, bench or fuzz harness calls `alloc_reset()`,
which is why 1818 assertions across four suites never surfaced it.

It is a live hazard for anything that resets a per-frame arena between library calls — the
downstream physics/engine/simulation consumers do exactly that. The first vec-backed entry point
after the reset faults, and it will read as a crash in the callee (`gjk_epa_3d`, `bvh_build`,
`delaunay_2d`, `convex_hull_2d`, `kdtree_build`, the quadtree/octree stores) rather than as an
allocator problem, since the stale memo carries no evidence of where it came from.
