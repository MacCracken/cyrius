# `xfsync` on Windows returns 0 without flushing — a durability call that reports success — RESOLVED v6.6.7

**Status:** ✅ **RESOLVED v6.6.7** (bite 3) — option 1, wired as a route of the LINUX numbers rather
than a new 0xF0xx id. See `CHANGELOG.md` [6.6.7]:

- **The flush.** `syscall(74, fd)` / `syscall(75, fd)` (fsync / fdatasync, argc 2) on PE now call
  `kernel32!FlushFileBuffers` (`EFLUSHFB_PE`, routed from `_PE_ROUTE_FLUSH` in
  `src/frontend/parse_expr.cyr`; literal-only, on the 83 → CreateDirectoryW / 87 → DeleteFileW
  precedent). A nonzero BOOL is 0, a failure -1. Routing the Linux numbers also repairs the
  vendored patra 1.14.3 fold's raw `syscall(SYS_FDATASYNC, fd)`, which was a LOUD -38 on Windows
  (so `wal_log_page` failed every page with `PATRA_ERR_IO`).
- **`xfsync`'s PE arm** is `return syscall(74, fd);`. `xfsync(12345)` is now -1 on PE, as it is
  -EBADF on Linux. One documented divergence: Windows refuses to flush an `O_RDONLY` handle
  (Linux fsyncs it); the only such callers are best-effort directory syncs.
- **The rationale was false too, and that is fixed in the same release.** `EMOVEFILEEX_PE` passed
  `dwFlags = 1` (REPLACE_EXISTING) without `MOVEFILE_WRITE_THROUGH`, so `file_write_atomic` was
  atomic but not durable on Windows. It now passes 9.

Tests: `tests/tcyr/crossos/fsync_flushes.tcyr` (16 rows, every target; runs on real cass in the
release gate's cross-OS leg) and `tests/gates/platform/pe_fsync_flushes.sh` (POSIX oracle, the PE
emitter shape — the only guard on the write-through bit, since nothing can observe durability — and
wine). ⚠ **Ordering for patra:** re-vendoring patra 1.15.0 (which routes Windows fdatasync through
`xfsync`) is safe only WITH or AFTER this fix; before it, the fold's loud -38 would have become a
silent 0. The ORIGINAL status line is kept below for the record.

~~🟡 **OPEN**: read 2026-09-23 in this repo's `lib/io.cyr:383-395` (cyrius 6.6.6). Found by
reading source; **not run on Windows**.~~
**Placement:** **6.6.7 bite 3** — PE fsync/fdatasync really flush: Linux 74/75 route to FlushFileBuffers, and MoveFileExW gains MOVEFILE_WRITE_THROUGH. Pinned 2026-09-27 in [roadmap.md](../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Discovered:** 2026-09-23 during patra's 1.15.0 cut, which routes patra's fdatasync through
`xfsync` on the targets with no `sys_fdatasync` (agnos, Windows).
**Severity:** High for a consumer that syncs for durability on Windows. The call never fails, so the
caller cannot learn that nothing reached disk. None of the consumers named below is known to be
deployed on Windows today.
**Affects:** cyrius 6.6.6 (source checked).

## Summary

`xfsync` documents itself as *"Flush a file descriptor's data + metadata to stable storage … Returns
0 / negative errno."* Its Windows arm is:

```cyrius
    #ifdef CYRIUS_TARGET_WIN
    return 0;                   # MoveFileEx-after-close is durable enough (documented)
    #endif
```

The rationale fits the atomic-rename callers, which rename after closing. It sits in the general
wrapper, though, so every caller that syncs for durability gets a success that flushed nothing.
The PE peer has no `sys_fsync` or `sys_fdatasync`, so `xfsync` is the only portable sync there.

## Who calls it, and whether they read the result

Checked by grep, read-only, 2026-09-23:

| caller | reads the return? |
|---|---|
| `lib/io.cyr:738` `file_write_atomic` | no |
| `cbt/core.cyr:279` `_aw_commit` | no |
| agora `src/arena.cyr:149` | no |
| agnodrm `src/util.cyr:121` | yes (returns it) |
| cyim `src/buffer.cyr:589`, `:611` | **yes** (`< 0` fails the save) |
| hapi `src/audit.cyr:391` | yes |
| thoth `src/toolpin.cyr:719` | **yes** (`< 0` fails the write) |
| patra `src/file.cyr` `_pt_fdatasync` (12 call sites) | one site (`wal_log_page`'s write-ahead check) |

## Options (the maintainer's call)

1. **Wire a real flush**: a kernel32 `FlushFileBuffers(handle)` reroute, like the existing
   `MoveFileExW` (0xF034), `DeleteFileW` (0xF035) and `RemoveDirectoryW` (0xF03B) reroutes, with 0 for a
   nonzero BOOL and -1 otherwise. Success keeps meaning success, now truthfully. None of the callers
   above changes behaviour except by becoming durable.
2. **Return an error until a flush exists.** ⚠ **This would break working code on Windows**: cyim's
   save and thoth's toolpin write treat `xfsync < 0` as failure, and hapi and agnodrm pass the result
   on. The two in-tree callers ignore it, so they would be unaffected. Listed so the cost is visible,
   not as a recommendation.
3. **Keep the no-op, and document at the wrapper that on Windows it is not a durability call.**
   Honest, but it leaves every durability caller exposed.

## What patra does meanwhile

Nothing in code. patra documents that nothing it writes on Windows is flushed (`roadmap.md`
*Platforms*, `SECURITY.md`).
