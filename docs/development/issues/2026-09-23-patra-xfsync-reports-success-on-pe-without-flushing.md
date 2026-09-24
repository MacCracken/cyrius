# `xfsync` on Windows returns 0 without flushing — a durability call that reports success — OPEN

**Status:** 🟡 **OPEN**: read 2026-09-23 in this repo's `lib/io.cyr:383-395` (cyrius 6.6.6). Found by
reading source; **not run on Windows**.
**Placement:** unpinned — `lib/io.cyr`, and a PE reroute if the flush is wired.
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
