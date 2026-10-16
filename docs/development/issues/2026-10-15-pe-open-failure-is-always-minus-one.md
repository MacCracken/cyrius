# PE `sys_open` answers -1 for every Win32 failure, so `file_open_r` / `file_read_all_r` can never say `IoNotFound` on Windows — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on real cass (Windows 11) with the 6.7.12 windows lane's tree
(l6712-windows @ 163d1a85); found by the cass full-corpus triage
(issues/archived/2026-10-12-cass-full-corpus-failures-untriaged.md, class (c): a real PE defect). Three of the four rows
`tests/tcyr/stdlib/result_stdlib.tcyr` still fails on cass after the lane's fixture fixes are this one (the fourth
is 2026-10-15-pe-read-failure-reads-as-eof.md).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (windows lane; filed from the 6.7.12 windows lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** Low — no wrong data, but a portable caller cannot tell "the file is not there" from "access denied" or
any other failure on Windows: every Result-returning open answers `IoOther`, and errno-keyed code takes its generic
branch.
**Affects:** `EOPEN_PE` (src/backend/x86/emit.cyr:3507 — `mov rax, -1` / CreateFileW's INVALID_HANDLE_VALUE) and its
documented contract in lib/syscalls_windows.cyr `sys_open` ("-1 for a Win32 failure"); through it `file_open`,
`file_open_r`, `file_read_all_r`, `file_write_all_r` and every other `_io_errno_to_iorr` caller (lib/io.cyr:1367).

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("no_such_file_w1.txt", O_RDONLY, 0);
syscall(SYS_EXIT, 0 - fd);                   # Linux 2 (-ENOENT); Windows 1 (-1)
```

```
x86_64 Linux (build/cycc):                    exit 2
cass (CYRIUS_TARGET_WIN=1 build/cycc, under C:\cyrius-tests):  exit 1
```

and the corpus rows on cass:

```
  FAIL: Err payload = IoNotFound (got 4, expected 0)      # file_open_r("/no/such/file/anywhere")
  FAIL: payload = IoNotFound (got 4, expected 0)          # file_read_all_r("/no/such/file/again")
  FAIL: Err payload = IoNotFound (got 4, expected 0)      # the `?` chain through file_open_r
```

## Root cause

CreateFileW reports why it failed through GetLastError (ERROR_FILE_NOT_FOUND 2, ERROR_PATH_NOT_FOUND 3,
ERROR_ACCESS_DENIED 5, ERROR_SHARING_VIOLATION 32, ERROR_FILE_EXISTS 80, …); the reroute returns INVALID_HANDLE_VALUE
(-1) and nothing reads it, so `_io_errno_to_iorr(1)` maps the 1 to `IoOther`. GetLastError has been routed since
6.6.12 (0xF04B).

## Proposed fix

Translate the Win32 error to the negative POSIX errno the other targets return (2/3 → -ENOENT, 5 → -EACCES, 80 →
-EEXIST, …), either in `EOPEN_PE` after the call or in lib/syscalls_windows.cyr's `sys_open` (`h < 0` → read 0xF04B).
⚠ The contract change touches every PE caller that compares an open result with -1 exactly (`_win_open_checked` /
`_win_nofollow_refusal` pass the raw value through as `err`; audit `== 0 - 1` sites on PE paths first). Row: the repro
in `tests/tcyr/crossos/` (cass), and result_stdlib.tcyr's three IoNotFound rows green on cass.
