# `file_read_whole*` keeps every buffer it outgrows: a read takes 2–4× the file on the bump heap — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-28 against cyrius 6.7.18 on x86_64 Linux with
[`repros/2026-10-28-file-read-whole-keeps-outgrown-buffers.cyr`](repros/2026-10-28-file-read-whole-keeps-outgrown-buffers.cyr).
`_io_read_whole` (`lib/io.cyr:825`) still grows by `alloc_via` + `memcpy`, and `_bump_realloc` (`lib/alloc.cyr:819`)
still allocates new and keeps the old block. The growth loop is unchanged since 6.6.7 apart from `while (1 == 1)` →
`loop` and `total = total + n` → `total += n` (diffed against `~/.cyrius/versions/6.6.7/lib/io.cyr`).
**Placement:** unpinned — 6.x-line backlog (never 7.x). The user places it.
**Discovered:** 2026-10-28, kii 1.9.1's release measurements. kii reads every input with `file_read_whole_max` under a
256 MiB cap. A 255 MB file cost 517 MB of RSS before kii refused it at the header, and 913 MB when it decoded (kii's
ADR 0002 § v1.9.1 amendment), so the read was more than half of kii's worst case.
**Severity:** Medium — no wrong value, but a silent 2–4× memory cost on every whole-file read, never reclaimed under the
default allocator, with a consumer-side workaround (below).
**Affects:** cyrius 6.6.6 – 6.7.18: every `file_read_whole`, `file_read_whole_max`, `file_read_whole_a` with the bump
or default allocator, and `file_read_whole_into` started at `{ 0, 0 }`. 6.6.6's first cut doubled from 64 KiB; 6.6.7
moved the start to 4 KiB and added the clamp. The shape is the same.

## Summary

`_io_read_whole` starts with a 4 KiB buffer and, each time the buffer fills, allocates one twice the size, copies, and
moves on. The old buffer is not released: under the default allocator `alloc_via` is the global bump `alloc`, which
cannot free, and the loop does not call `free_via` or `realloc_via` anyway. So a read leaves every size it passed
through on the heap: 4 KiB + 8 KiB + … + the final capacity, about **twice the final capacity**. The final capacity is
itself up to twice the file, so a read costs between 2× and 4× the file's size.

**The 4× case has a second cause.** When a read fills the buffer exactly, `total == cap` with `cap < max`, so the loop
doubles **before** it can see EOF. A file whose size is a power of two (4 KiB and up) therefore always pays for one
empty buffer twice its size. A file one byte larger costs the same, because it really needs that buffer.

RSS is lower than the heap figure (an untouched tail is never paged in), but the copies touch every byte of every
intermediate buffer, so RSS still runs 2–3× the file.

## Reproduction

```sh
cd docs/development/issues/repros
# a scratch project: cyrius.cyml with cyrius = "6.7.18" and
#   stdlib = ["string", "fmt", "alloc", "io", "args", "syscalls"]
cyrius build 2026-10-28-file-read-whole-keeps-outgrown-buffers.cyr build/readwhole
head -c 16777216 /dev/zero > /tmp/f && ./build/readwhole /tmp/f
# 16777216 67104880        <- bytes read, heap the read took
```

The repro prints `alloc_used()` after the read minus `alloc_used()` before it, so `args_init`'s 2 MiB is excluded.
Measured on cyrius 6.7.18, x86_64 Linux. Peak RSS is from `getrusage(RUSAGE_CHILDREN)`, with a 13 MB process floor.

| File | Heap the read took | × file | Peak RSS |
|---:|---:|---:|---:|
| 4,096 B | 12,304 B | 3.00 | 13 MB |
| 1,000,000 B | 2,093,128 B | 2.09 | 13 MB |
| 16,777,216 B (2^24) | 67,104,880 B | **4.00** | 50 MB |
| 16,777,217 B | 67,104,880 B | **4.00** | 50 MB |
| 100,000,000 B | 268,431,488 B | 2.68 | 226 MB |
| 134,217,728 B (2^27) | 536,866,952 B | **4.00** | — |
| 200,000,000 B | 536,866,952 B | 2.68 | 450 MB |
| 268,435,456 B (2^28 = `max`) | 536,866,952 B | 2.00 | 516 MB |

At `max` the final buffer is clamped, so it does not double past the file, and the probe byte (`lib/io.cyr:843-848`)
finds EOF without a growth. That is the only power of two that costs 2× rather than 4×.

## Root cause

`lib/io.cyr:842-860`, in `_io_read_whole`:

```cyr
if (total == cap) {
    if (cap == max) { … one-byte probe … }
    var ncap = cap + cap;
    …
    var nb = alloc_via(a, ncap + 1);
    memcpy(nb, buf, total);          # the old `buf` is never freed or reused
    buf = nb;
```

- **Keeping the old buffers.** `alloc_via` + `memcpy` leaves the previous buffer allocated. With the default allocator,
  even `realloc_via` would not help today: `_bump_realloc` (`lib/alloc.cyr:819`) is "alloc new + leak old", by its own
  comment.
- **The early doubling.** Only the `cap == max` branch probes for EOF. Below `max`, a buffer that is exactly full is
  grown before the next `read` can return 0.

The 6.6.7 comment above `file_read_whole` (`lib/io.cyr:756-758`) rejects a stat because Windows has no POSIX stat
here and a stat-then-read races a writer. Both proposals below keep the read to EOF as the only source of truth, so
neither reintroduces that race.

## Proposed fix

Any one of these is an improvement; (1) or (2) brings a read to ~1×, and (3) alone only removes the exact-fill 4×.

1. **Grow in place on the bump heap.** Let `_bump_realloc` extend a block that is the most recent allocation and still
   fits in the current chunk (`old_ptr + align8(old_size) == _heap_ptr`), and have `_io_read_whole` grow through
   `realloc_via` instead of `alloc_via` + `memcpy`. Nothing else allocates during the loop, so the buffer is always
   the top block and each growth is free, no copy. Past the chunk's end it falls back to today's behaviour.
   *Speculation:* I have not checked how `_linux_new_chunk` sizes chunks, so how often a large read crosses a chunk
   boundary is unmeasured. Locking and `CYRIUS_POISON`'s headers need the same care `alloc` takes.
2. **Start from a size hint.** After the open, `sys_fstat(fd)` (or `GetFileSizeEx` on Windows, or nothing where
   neither exists). For a regular file with `0 < st_size <= max`, size the first buffer at `st_size + 1` bytes of
   capacity (one slack byte), so the read that fills it is followed by one that returns 0. A pipe, `/proc`, a
   directory or a file that changed size falls through to the doubling, which still runs to EOF. The hint comes from
   the open fd, so it cannot name a different file, and a writer that grows the file only costs a growth.
3. **Probe before every doubling**, not only at `max`: when `total == cap`, read one byte into a local; at EOF stop,
   otherwise grow and store it. This removes the 4× at power-of-two sizes (one extra 1-byte `read` per growth), and
   nothing else.

Whichever lands, the regression row is the repro's table: heap ≤ ~1.01× the file at 4 KiB, 2^24, 2^24 + 1 and `max`.

## Consumer-side workaround

Pre-size `file_read_whole_into`'s `{ ptr, cap }` from a stat, with one slack byte, which is fix (2) done by the
caller. The repro's `hint` mode does exactly this. x86_64 Linux's `struct stat` has `st_mode` at 24 and `st_size` at
48:

```cyr
var st[144];
var rb[16];
store64(&rb, 0);
store64(&rb + 8, 0);
if (sys_fstatat(0 - 100, path, &st, 0) == 0) {
    var mode = load32(&st + 24);
    var size = load64(&st + 48);
    # A regular file's size is only a starting capacity: the read still runs to EOF.
    if ((mode & 0xF000) == 0x8000 && size > 0 && size <= max) {
        var b0 = alloc(size + 2);
        if (b0 != 0) { store64(&rb, b0); store64(&rb + 8, size + 1); }
    }
}
var n = file_read_whole_into(&rb, path, max);    # data at load64(&rb) when n >= 0
```

Measured with it: 4,104 B for a 4,096-byte file, 16,777,224 B for 2^24 and 2^24 + 1 (RSS 20 MB, was 50), 100,000,008 B
for 100 MB (RSS 98 MB, was 226), and 268,435,464 B at `max` (RSS 260 MB, was 516). A file past `max` is still
`-EFBIG`, a directory still fails the read, and `/dev/stdin` and `/proc/self/status` (no usable size) take the doubling
path as before. The stat is by path, so it can race the open, but it only picks a capacity: a wrong size costs at
most today's growth.

kii has not adopted this yet. It reads with `file_read_whole_max` (`src/image.cyr`, `kii_decode_image`).
