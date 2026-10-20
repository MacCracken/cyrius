# PE `sys_close(-1)` / `sys_close(-2)` answer 0 on Windows — CloseHandle takes the fd as a pseudo-handle (the current process / thread) and succeeds; Linux answers -9 — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 platform lane (branch l6716-platform, unit P1, on the tree
that maps fd 0 / 1 / 2 to the std handles in a close), under wine 11.20 (a private WINEPREFIX) and on real cass
(Windows 11, `C:\cyrius-tests`). The same answer on the slot-open compiler 480de63eb under wine.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 platform lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; p16 lane, wave 3, unit PP1) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D78 — -9, as Linux.
**Severity:** Low — no in-tree caller closes a negative fd on purpose; a portable program whose `sys_close` /
`file_close` / `file_close_r` gets a failed open's `-1` (the common `fd = open(..); ... close(fd)` without a `< 0`
check) reads a success on Windows where Linux reports -EBADF. Not a security issue (the program's own handle table;
closing the current-process pseudo-handle is a no-op).
**Found:** in passing while fixing issues/2026-10-18-pe-close-and-ftruncate-pass-std-fds-raw.md (6.7.16 P1): a
measurement probe showed `CloseHandle(INVALID_HANDLE_VALUE)` answers TRUE on cass and wine, which is why the new
std-close stub answers -9 itself for an INVALID_HANDLE_VALUE std slot. The fd > 2 arm of ECLOSE_PE (any value that is
not 0 / 1 / 2, negative ones included) still hands the fd to CloseHandle as the handle.

## Reproduction

`closeneg.cyr`:

```cyr
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var a = sys_close(0 - 1);     # not a descriptor: Linux -9
var b = sys_close(0 - 2);     # not a descriptor: Linux -9
var c = file_close(0 - 1);    # the same through lib/io.cyr
fmt_int(a); println("");
fmt_int(b); println("");
fmt_int(c); println("");
```

```text
x86_64 Linux (build/cycc)                                   -9 -9 -9
PE under wine 11.20 (CYRIUS_TARGET_WIN=1, this lane's tree)   0  0  0
PE on real cass (same exe)                                    0  0  0
PE under wine, the slot-open compiler 480de63eb               0  0  0
```

(`sys_close(-999)` answers -9 on every target — tests/tcyr/crossos/close_answer.tcyr pins it: -999 is not a
pseudo-handle value, so CloseHandle fails ERROR_INVALID_HANDLE.)

## Root cause

ECLOSE_PE (src/backend/x86/emit.cyr) passes any fd above 2 (unsigned: every negative fd) to `CloseHandle` as the
HANDLE, the `_pe_fd_to_handle_rcx` convention. `-1` is `GetCurrentProcess()`'s pseudo-handle and `-2`
`GetCurrentThread()`'s; `CloseHandle` on a pseudo-handle is documented as harmless and returns TRUE, so the close
answers 0. Measured with a zig-built probe on cass and wine: `CloseHandle(INVALID_HANDLE_VALUE)` = TRUE, while
`WriteFile` / `ReadFile` / `SetFilePointerEx` / `FlushFileBuffers` / `SetEndOfFile` on the same value fail
ERROR_INVALID_HANDLE (-9 through the table) — the close is the one reroute that reads a negative fd as success.

## Fix direction (not decided here)

A negative fd is never a cyrius descriptor on Windows (CreateFileW handles are positive multiples of 4): ECLOSE_PE's
fd > 2 arm can answer -9 for a negative fd without calling CloseHandle (`test rax, rax; js .ebadf`, a few bytes a site,
or one more arm in the shared std-close stub's entry test). This changes what `sys_close(-1)` answers on Windows
(0 → -9, Linux's answer), so whether it ships is the user's call. Rows: closeneg above in
tests/gates/platform/pe_reroute_failure_errno.sh axis 4 (wine) plus the native oracle, and a `sys_close(0 - 1)` row
in tests/tcyr/crossos/close_answer.tcyr (it runs on all four hosts).
