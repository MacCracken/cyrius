# Windows answers beyond D79 / D94 / D95: a rename of a directory onto an existing file replaces the file (Linux -20, the file kept), a rename of a file onto a directory answers -13 (Linux -21), and `xflock` answers -1 for a closed or negative fd (Linux -9) — OPEN

**Status:** 🟡 **OPEN** — each fix changes what a Windows call computes beyond the decided answers (D79 / D94: a failure
answers the Win32 table's errno; D95: -21 for unlink / truncate / open of a directory); the pw lane stopped on all three.
**Placement:** unplaced — filed at the 6.7.16 close (2026-10-21); the user places it — never 7.x.
**Discovered:** the pw lane — its unit PW1's Blocked item (`xflock`) and its review's file_as_issue (all three; staged as
2026-10-20-pe-rename-of-a-directory-onto-an-existing-file-replaces-the-file.md,
2026-10-20-pe-rename-of-a-file-onto-an-existing-directory-answers-eacces-not-eisdir.md and
2026-10-20-pe-xflock-answers-minus-one-for-a-closed-or-negative-fd.md).
**Severity:** Medium — row 1 loses data: the rename reports success and the file's contents are gone. Rows 2 and 3 are a
different errno (Low). The developer's own program and paths: no boundary is crossed, no ledger id.
**Kind:** decision (one per row).

## Summary

The Windows peers of `sys_rename` / `file_rename` (MoveFileExW) and `xflock` (LockFileEx / UnlockFileEx) answer
differently from Linux in three cells no decision named: `MOVEFILE_REPLACE_EXISTING` lets a DIRECTORY source replace an
existing FILE; MoveFileExW's refusal of a directory TARGET is ERROR_ACCESS_DENIED, -13 through the table; and `xflock`
folds every failure but LOCK_NB contention to -1 (its 6.7.12 contract).

## Reproduction

Measured 2026-10-21 at the 6.7.16 close: the merged x86_64 compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B) on
Linux, and the PE compiler built from that tree (`src/main_win.cyr`) under wine 11.20 in a private WINEPREFIX, each run
in an empty directory. The real-Windows cells are the pw review's measurement on cass (Windows 11, `C:\cyrius-tests`);
they were not re-run at the close. Common head:

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
fn p(v): i64 { fmt_int(v); sys_write(1, " ", 1); return 0; }
```

**1. A directory onto an existing file:**

```cyrius
var fd = sys_open("rn_t", 577, 420);   # O_WRONLY|O_CREAT|O_TRUNC
sys_write(fd, "data", 4);
sys_close(fd);
sys_mkdir("rn_d", 448);
p(sys_rename("rn_d", "rn_t"));
println("");
```

| host | output | afterwards |
|---|---|---|
| x86_64 Linux | `-20` | `rn_t` is still the 4-byte file, `rn_d` the directory |
| wine 11.20 | `0` | `rn_t` is a directory; the file and its 4 bytes are gone |
| cass (the review) | `0` | `Get-ChildItem` lists `rn_t` as `d-----`; the file is gone |

**2. A file onto an existing directory:**

```cyrius
var fd = sys_open("rn_t", 577, 420);
sys_close(fd);
sys_mkdir("rn_d", 448);
p(file_rename("rn_t", "rn_d"));
println("");
sys_unlink("rn_t");
sys_rmdir("rn_d");
```

Linux `-21`; wine `-13`; cass (the review) `-13` (`-1` before 6.7.16's D94).

**3. `xflock` of a closed fd and of a negative fd:**

```cyrius
var fd = file_open("fl_t", O_RDWR | O_CREAT | O_TRUNC, 420);
file_close(fd);
p(xflock(fd, LOCK_EX));
p(xflock(0 - 4, LOCK_EX));
println("");
xunlink("fl_t");
```

Linux `-9 -9`; wine `-1 -1`. (An fd with a low bit set already answers -9 since the pw lane's 141f80a2b; these rows are
multiples of 4.)

## The decision, row by row

| row | change | or keep |
|---|---|---|
| 1 | before MoveFileExW, when the source is a directory and the target an existing non-directory, answer -20 as Linux (the `_win_is_dir` ask lib/syscalls_windows.cyr has, D95's shape) — a check-then-act window, unlike Linux's atomic refusal | Windows' replace (today) |
| 2 | on MoveFileExW's -13, ask whether the target is a directory and answer -21 (as `_win_unlink_eacces` does for D95); anything else keeps -13 | -13 (today) |
| 3 | route `_xflock_win_lock` / `_xflock_win_unlock`'s failures through the Win32 table (ERROR_INVALID_HANDLE -9, …), keeping -11 for LOCK_NB contention | -1 (the 6.7.12 contract) |

## Acceptance

Each repro prints Linux's answer on wine and cass (row 1: `rn_t` keeps its 4 bytes), pinned by a `tests/tcyr/crossos/`
row on every target (native, qemu-aarch64, cxvm, wine and the four hosts; macOS answers its own errnos where they differ —
measure ecb / ach; cx on a Windows host has no flock route, -38).

## The sites

`EMOVEFILEEX_PE` (src/backend/x86/emit.cyr, MoveFileExW, reroute 0xF034 — `sys_rename` in lib/syscalls_windows.cyr,
`file_rename` in lib/io.cyr) passes `MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH`; its FALSE goes through
`_pe_bool_errno` since D94. lib/io.cyr's Windows arm of `xflock` (`_xflock_win`, `_xflock_win_lock` /
`_xflock_win_unlock`) folds every failure but ERROR_LOCK_VIOLATION under LOCK_NB (-11) to -1.
