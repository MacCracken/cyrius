# PE `sys_unlink` / `xunlink`, `sys_truncate` and `file_open(dir, O_WRONLY)` of a DIRECTORY answer -13 (ERROR_ACCESS_DENIED through the Win32 table) — Linux answers -21 (EISDIR) — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.16 p16 review (its file_as_issue; the p16 handoff had listed it as the
user's call without a file), measured again 2026-10-20 on the p16 lane (l6716-p16 at e24cc3d67) with the PE
compiler built from the lane's tree (`CYRIUS_TARGET_WIN=1 ./build/cycc`), under wine 11.20 (a private WINEPREFIX)
and on real cass (Windows 11, `C:\cyrius-tests`).
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 p16 review; placed at the p16 / t16 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; pw lane, wave 4, unit PW1) — never 7.x.
**Decision (user, 2026-10-20, asked at the p16 / t16 integration):** D95 — Yes, -21 as Linux (a directory answers EISDIR; a real permission failure stays -13).
**Severity:** Low — a silent wrong value: a program that tells "that is a directory" (-21) from "permission denied"
(-13) by the errno reads -13 on Windows for both. No boundary is crossed (no ledger id). (`sys_rmdir` of a FILE
already matches Linux: -20 on both, ERROR_DIRECTORY.)
**Why it is not fixed in the lane:** 6.7.16's D79 decided "Linux's negative errno, through the Windows error
table", and the table answers -13 for ERROR_ACCESS_DENIED, so the two halves of the decision disagree for this
shape. Answering -21 means classifying an ERROR_ACCESS_DENIED by asking the name (GetFileAttributesW, 6.7.14's
`file_create_exclusive` shape) in DeleteFileW's and CreateFileW's failure paths — a change to what open / unlink /
truncate answer beyond the decided ones: the user's call.

## Reproduction

`dirfail.cyr`, built for each target from the repo root (`./build/cycc` / `CYRIUS_TARGET_WIN=1 ./build/cycc`),
run in an empty directory:

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
fn p(v): i64 { fmt_int(v); sys_write(1, " ", 1); return 0; }
sys_rmdir("df_d");
sys_mkdir("df_d", 448);
p(sys_unlink("df_d"));                  # unlink of a directory: Linux -21
p(xunlink("df_d"));                     # the same through xunlink: Linux -21
p(sys_truncate("df_d", 1));             # truncate of a directory: Linux -21
p(file_open("df_d", O_WRONLY, 0));      # open of a directory for writing: Linux -21
println("");
sys_rmdir("df_d");
```

| host | output |
|---|---|
| x86_64 Linux | `-21 -21 -21 -21` |
| wine 11.20 | `-13 -13 -13 -13` |
| cass (real Windows 11) | `-13 -13 -13 -13` |

## The sites

- `_pe_path_bool1` (src/backend/x86/emit.cyr ~3818) for DeleteFileW (87 / 0xF035): a FALSE BOOL goes through the
  shared table (`_pe_bool_errno`), where ERROR_ACCESS_DENIED (5) is -13.
- `EOPEN_PE` (~4282, CreateFileW): its failure goes through the same table; `sys_truncate` (lib/syscalls_windows.cyr)
  answers its open's errno.

A fix keeps the table as it is (-13 is right for a real permission refusal) and, where -13 comes back, asks the
name's attributes: a directory answers -21 (`file_create_exclusive` and `_io_tmp_taken` in lib/io.cyr already
classify CREATE_NEW's -13 over a directory as -17 this way). Rows: a `crossos/` tcyr pinning the four cells -21
on every target, and pe_reroute_failure_errno.sh's axis 4 running it under wine.
