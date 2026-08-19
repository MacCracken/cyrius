# `fl_calloc` re-zeroes mmap'd pages one byte at a time — 369x slower than the allocation itself

**Status:** ✅ **RESOLVED** — shipped in **v6.5.28**. See `CHANGELOG.md` [6.5.28].

> ### ✅ FIXED — and the 369x is gone, not merely reduced
>
> `fl_calloc` now skips the zero-fill entirely on the LARGE path (`_fl_class(size) < 0` means
> a fresh `_fl_mmap` mapping, which is kernel-zeroed — verified against fl_alloc's own large
> branch, not assumed), and uses 8-byte stores with a byte tail on the recycled size-class
> path that genuinely still owes the work.
>
> **Measured here: `fl_alloc` 90 us vs `fl_calloc` 80 us for the same 8,294,400-byte buffer —
> statistically identical.** The filing measured 29.633 us vs 10.946 ms on its box; the ratio
> is now ~1.0 instead of 369.
>
> ⚠ **The dangerous half of this fix is the skip.** Skipping BOTH paths would be a silent
> use-of-uninitialised-memory bug that a large-allocation-only test passes happily.
> `tests/tcyr/memory/fl_calloc_zero_paths.tcyr` deliberately dirties a small block with 0xAB,
> frees it, and re-callocs to force the RECYCLED path, plus an odd size to exercise the byte
> tail after the 8-byte loop.
>
> ⚠ **No `memset`.** It lives in `lib/string.cyr`, which freelist does not include — this
> module depends on `mmap` + `atomic` only, and an allocator reaching into the string library
> to zero memory is a dependency edge worth not adding. The 8-byte loop gets the same
> order-of-magnitude win self-contained.
**Placement:** unpinned — 6.5.x backlog. `lib/freelist.cyr`.
**Discovered:** 2026-08-17 benchmarking ranga's image buffers against the frozen Rust baseline
**Severity:** **Medium** — silent >2x perf regression on a very common path; no correctness impact
**Affects:** cycc 6.5.27

## Summary

`fl_calloc(size)` calls `fl_alloc(size)` and then zeroes the result with a
**byte-at-a-time `store8` loop** (`lib/freelist.cyr:325-334`). For any allocation
above the 4 KB size-class threshold, `fl_alloc` takes the large-allocation path
and returns a **fresh `mmap` mapping** (`:266-276`) — which the kernel has
already zero-filled and is contractually required to. The loop is therefore
re-zeroing memory that is provably already zero, one byte at a time.

Measured on 6.5.27, x86_64, for an 8,294,400-byte buffer (one 1080p RGBA8 frame):

```
fl_alloc(8.3MB)  [mmap, kernel-zeroed] :  29.633 us
fl_calloc(8.3MB) [mmap + byte loop]    :  10.946 ms      <-- 369x
```

10.9 ms to hand back a buffer the kernel already prepared in 30 us.

## Reproduction

```
include "lib/alloc.cyr"
include "lib/freelist.cyr"
include "lib/bench.cyr"

fn main(): i64 {
    alloc_init();
    var N = 8294400;
    var b1 = bench_new("fl_alloc");
    bench_batch_start(b1);
    var i = 0;
    while (i < 20) { var p = fl_alloc(N); fl_free(p); i = i + 1; }
    bench_batch_stop(b1, 20);
    bench_report(b1);

    var b2 = bench_new("fl_calloc");
    bench_batch_start(b2);
    i = 0;
    while (i < 20) { var q = fl_calloc(N); fl_free(q); i = i + 1; }
    bench_batch_stop(b2, 20);
    bench_report(b2);
    return 0;
}
var r = main();
sys_exit_group(r);
```

## Root cause

`lib/freelist.cyr:325`:

```
fn fl_calloc(size): i64 {
    var ptr = fl_alloc(size);
    if (ptr == 0) { return 0; }
    var i = 0;
    while (i < size) {
        store8(ptr + i, 0);      # <-- one byte per iteration, 8.3M iterations
        i = i + 1;
    }
    return ptr;
}
```

Two independent problems, and they compound:

1. **The loop is unnecessary on the mmap path.** `_fl_class(size) < 0` means a
   fresh mapping, which is already zero. Only the recycled size-class path can
   hand back dirty memory.
2. **Even where zeroing IS needed, a byte loop is the slowest possible way.**
   `memset` (already in `lib/string.cyr`) would be roughly an order of magnitude
   faster on the small-allocation path.

## Proposed fix

```
fn fl_calloc(size): i64 {
    var cls = _fl_class(size);
    var ptr = fl_alloc(size);
    if (ptr == 0) { return 0; }
    # Large allocations come from a fresh mmap, which the kernel guarantees is
    # zero-filled — re-zeroing is pure waste.
    if (cls < 0) { return ptr; }
    memset(ptr, 0, size);
    return ptr;
}
```

That is the whole change: a size-class test plus swapping the loop for `memset`.
If the mmap-is-zero assumption is considered too implicit to rely on, the
`memset` alone is still a large win and entirely safe.

## Consumer-side workaround

ranga added `bv_uninit` / `pixel_buffer_uninit` — an allocation path that skips
the zero fill for the callers that provably overwrite every byte (crop's row
memcpy, the flips, the format converters). Measured effect:

| | before | after |
|---|---:|---:|
| `crop_1080p_to_720p` | 11.18 ms | 6.53 ms |
| `rgba8_to_argb8_1080p` | 24.46 ms | 14.00 ms |
| `flip_vertical_1080p` | 23.45 ms | 14.10 ms |
| `flip_horizontal_1080p` | 35.18 ms | 26.03 ms |

⚠ That workaround is strictly worse engineering than fixing `fl_calloc`, and I
would drop it if this lands. It trades a guaranteed-zero buffer for an
uninitialised one across a dozen call sites, and the hazard is **not testable**:
because large allocations come from fresh mmap, an incorrect use of the
uninitialised path still reads as zero in every test, and only misbehaves once
the allocator starts recycling. Fixing the source removes the temptation.
