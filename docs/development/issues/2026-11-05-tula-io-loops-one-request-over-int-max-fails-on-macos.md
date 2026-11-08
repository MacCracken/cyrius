# `_io_write_full` and the `file_read_*` loops ask for the whole remainder in one call — over INT_MAX bytes that is EINVAL on macOS

**Status:** 🟡 **OPEN** — filed by tula (2026-11-05); tula works around it in its own loops.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-05, tula 1.6.1's first macOS CI run (`macos-14`, arm64): `make bigfile` failed at
`tula_read_file_into` on a 2.4 GB file.
**Severity:** Medium — a hard failure on macOS with a consumer-side workaround.
**Affects:** cyrius **6.7.18** (stdlib `lib/io.cyr`), macOS targets. Linux is unaffected.

## Summary

Every "read/write it all" loop in `lib/io.cyr` passes the whole remaining length to one `read(2)` / `write(2)`
and loops only on a short count. Linux caps a single request at `MAX_RW_COUNT` (0x7ffff000) and returns short,
so the loop finishes. Darwin refuses a request whose `nbyte` exceeds `INT_MAX` outright: `-EINVAL`, nothing
transferred. So on macOS any buffer over 2 GiB − 1 bytes fails through these helpers, even though the target
can map and allocate it (`ALLOC_MAX` is 0x80000000, so even a single maximal `alloc` is one byte over).

## Reproduction

tula's big-file gate on the macOS runner (tula 1.6.0's loop had the same shape as `_io_write_full`):

```
tula big-file gate (ADR 0006)
  file bytes           : 2415925040
  ...
FAIL: tula_read_file_into
```

The same failure reproduces on Linux by wrapping the `read`/`write` calls so a request over `2147483647` returns
`-22`, as Darwin's do. By the same rule, any of the helpers below with `len`/`maxlen` > 2^31 − 1 should fail on
macOS, e.g. `file_write_all(path, mmap_anon(0x90000000), 0x90000000)` → `-22` (inferred from Darwin's
`read(2)`/`write(2)` contract and the CI failure above; not run directly on macOS).

## Root cause

The unchunked requests, `lib/io.cyr` at 6.7.18:

- `_io_write_full` (:716) — `file_write(fd, buf + off, len - off)` (:719). Behind `file_write_all` (:731),
  `file_write_atomic` (:1067), `file_replace_atomic` (:1094) and `file_write_all_r` (:1611).
- `file_read_all` (:691) — `file_read(fd, buf + total, maxlen - total)` (:696).
- `_io_read_whole` (:825) — `file_read(fd, buf + total, cap - total)` (:861), behind the `file_read_whole*` family.
- `file_read_all_r` (:1587) — `sys_read(fd, buf + total, maxlen - total)` (:1593).
- `_env_load` (:1650, :1734) has the same shape but reads a small environ block; listed for completeness.

## Proposed fix

Cap each request (1 GiB is safe on every target: under Darwin's `INT_MAX`, Linux's `MAX_RW_COUNT` and Windows'
DWORD), keeping the loops' existing short-count handling:

```
var want = len - off;
if (want > 1073741824) { want = 1073741824; }
var w = file_write(fd, buf + off, want);
```

## Consumer-side workaround

tula 1.6.1 caps its own loops (`src/fileio.cyr` `_tula_read_full` / `_tula_write_full`) at 1 GiB per request,
and its `make bigfile` gate now writes and reads a single 2.2 GB tensor. tula's `tula_write_file` and
`tula_write_file_atomic` still go through `file_write_all` / `file_write_atomic`, so on macOS they fail with
`-EINVAL` on a buffer over `INT_MAX` bytes; tula documents that as a known limit.
