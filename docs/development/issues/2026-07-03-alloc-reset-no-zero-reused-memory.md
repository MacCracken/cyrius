# `alloc_reset()` rewinds the bump pointer without zeroing; reused first-chunk memory leaks the prior occupant's bytes

> **OPEN** — filed 2026-07-03 by **daimon** (consumer), against cyrius 6.3.43.
> `lib/alloc.cyr` `alloc_reset()` (lines 228–236). A **memory-reuse information-leak** in the bump allocator: the only point the allocator hands the same address to a different owner is `alloc_reset()`, and it does not zero the reclaimed span. Same bug class as **CVE-2026-34988** (Wasmtime) / **CVE-2022-39393**. Consumers cannot fix it (the stdlib owns both the allocator and — via sandhi — the reset call site), so it must be fixed here.

**Severity:** Low → High. Low for a single-trust-domain consumer; High the moment a consumer hands one allocator to two logical owners across a reset (multi-tenant hosting, sandboxing, untrusted federation, external tool-callback response data sharing the heap).

## Summary

The bump allocator is forward-only and chunk-based: 256 MB anonymous `mmap` chunks (`MAP_ANONYMOUS | MAP_PRIVATE`), a pointer bump per allocation, a fresh chunk `mmap`'d on overflow. **New chunks are safe** — Linux zero-fills anonymous pages on first touch, so forward allocation onto never-touched space reads as zero.

The gap is `alloc_reset()`: it rewinds `_heap_base` / `_heap_ptr` / `_heap_end` to the first chunk and sets `_heap_used = 0`, **but does not zero the reclaimed span**. Subsequent allocations reuse those first-chunk addresses while the previous occupant's bytes are still resident, leaking the first owner's data into the second.

`alloc_reset()` is the **only** point the allocator ever hands the same address to a different owner — everywhere else it moves forward onto kernel-zeroed pages. So this one function is the entire reuse channel.

## Root cause (`lib/alloc.cyr:228`)

```cyrius
fn alloc_reset(): i64 {
    _alloc_lock_acquire();
    _heap_base = _heap_first_base;
    _heap_ptr  = _heap_first_base;
    _heap_end  = _heap_first_end;
    _heap_used = 0;                 // rewind — but [_heap_first_base, old _heap_ptr) is NOT zeroed
    _alloc_lock_release();
    return 0;
}
```

## Reproduction (conceptual)

```cyrius
var a = alloc(64);
memset(a, 0xAA, 64);      // "sensitive" bytes
alloc_reset();
var b = alloc(64);        // same address as a
// b reads 0xAA… (stale), not 0x00
```

Without the reset, `b` is a fresh forward address on a kernel-zeroed page and reads clean — the leak is specific to reset-then-reallocate.

## Why this must be fixed in cyrius (not the consumer)

- `lib/alloc.cyr` is stdlib — a consumer that vendors it (gitignored, resync'd) cannot persist an edit.
- The reset is not even driven by the top-level consumer: **sandhi** calls `alloc_reset()` between request batches (per-batch request-arena reset between epoll drains). Both the allocator and the reset call site are inside the stdlib; the consumer has no seam to interpose on.

## Proposed fix

Zero-on-reset is the industry-matched baseline for a bump/arena allocator (Wasmtime resets reused slots to a known-zero state; Android init-on-free; glibc `MALLOC_PERTURB_`). A bump allocator has no per-object free, so the reset boundary is the natural and *cheap* place to carry the guarantee — one bulk operation per reset, not per allocation, leaving the two-instruction allocation hot path untouched.

1. **Zero the used span in `alloc_reset()` before rewinding** — `memset(_heap_first_base, 0, _heap_used)`. Smallest change; transparent to every consumer; O(used) per reset (µs-scale for MiB spans), negligible against the batch I/O a reset brackets.
2. **Or, for large page-aligned chunks**, `madvise(_heap_first_base, span, MADV_DONTNEED)` — drop the physical pages so the next fault re-serves fresh kernel-zeroed pages (one syscall; Wasmtime's default per-slot reset).
3. If a transparent cost is unacceptable, expose an opt-in `alloc_reset_zeroed()` and have sandhi call it on the request-arena reset. Transparent (1/2) is preferred — no consumer should have to know the reset was unsafe.

Fixing it here closes the reuse channel for **all** downstream consumers at once.

## References

- **CVE-2026-34988** (GHSA-6wgr-89rj-399p) — Wasmtime pooling-allocator cross-guest linear-memory leak; fixed by resetting a reused slot to a known-zero/guarded state before reuse.
- **CVE-2022-39393** (GHSA-wh6w-3828-g9qf) — related Wasmtime CoW-image-on-slot-reuse leak.
- Consumer report / gate: daimon VULN-007 (`daimon/docs/audit/2026-04-13-security-audit.md`); daimon 1.3.2 ships a partial consumer-side mitigation (scrubbing its own sensitive buffers before the reset window) that cannot cover this stdlib reset boundary.
