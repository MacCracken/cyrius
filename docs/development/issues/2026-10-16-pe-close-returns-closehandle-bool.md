# PE `sys_close` returns CloseHandle's BOOL (1 = closed, 0 = failed), so a failed close reads as success and every `< 0` test on it is dead — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 platform lane (unit P1) on real cass (Windows 11,
`C:\cyrius-tests`) and under wine 11.19, with the lane's tree (l6714-platform, after the P1 failure-errno fix for the
read / write / open / seek reroutes). Met in passing while fixing EREAD_PE / EWRITE_PE / EOPEN_PE / ELSEEK_PE — the
same class (a kernel32 reroute that does not turn its failure into the POSIX answer), outside their filed surface, so
filed, not fixed.
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — a close on Windows can only fail for a handle that is not open (or a protected one), so no data is
lost by the close itself; but the answer inverts the documented contract: lib/syscalls_windows.cyr `sys_close` says
"Returns 0 on success, -1 on failure", and the reroute answers 1 on success and 0 on failure. Every `sys_close(...) < 0`
/ `file_close(...) < 0` test is dead on Windows (cbt/build.cyr:908, cbt/core.cyr:402, cbt/commands.cyr:6518), and
`file_close_r` answers `Ok(1)` for a good close and `Ok(0)` for a failed one — never `Err`.
**Affects:** `ECLOSE_PE` (src/backend/x86/emit.cyr — `_pe_srw_call_1arg(S, _pe_closeh_get())`, whose own comment says
"Return in rax is the BOOL from CloseHandle (1 = success, 0 = failure)"); `sys_close` / `file_close` / `file_close_r`
on PE.

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("cl_probe.tmp", O_WRONLY | O_CREAT | O_TRUNC, 420);
var ok = sys_close(fd);                      # a real descriptor: 0 on Linux
var bad = sys_close(0 - 999);                # not a descriptor / handle: -9 on Linux
xunlink("cl_probe.tmp");
syscall(SYS_EXIT, 100 + ok * 10 + bad);      # Linux 91; Windows 110 (TRUE 1, FALSE 0)
```

```
x86_64 Linux (cat cl.cyr | build/cycc):                         exit 91
PE (CYRIUS_TARGET_WIN=1 build/cycc), wine 11.19 AND real cass:  exit 110
```

## Root cause

CloseHandle returns a BOOL; ECLOSE_PE hands it back unchanged (since v6.4.44 through the rbx-anchored
`_pe_srw_call_1arg`). The peers that already fold a BOOL (EFLUSHFB_PE: `cmp eax,1; sbb rax,rax`) and, since 6.7.14,
the read / write / open / seek reroutes (the shared GetLastError stub, `_pe_w32_errno_site`) do not have this shape.

## Fix direction (not decided here)

Test the BOOL after the call: TRUE → 0; FALSE → the shared 6.7.14 stub (`_pe_w32_errno_site(S, 0)`, so a bad handle is
-9 as on Linux), or EFLUSHFB_PE's 0 / -1. A src/ change (src/backend/x86/emit.cyr, compiled by cybs): seed-derive and
the cass PE self-host. ⚠ Anything that today reads a Windows close's 1 as success (`!= 0`) flips — audit `sys_close` /
`file_close` callers in lib/ and cbt/ (lib/process_win.cyr, fs_win.cyr, thread_win.cyr, syscalls_windows.cyr and
async_win.cyr neither assign nor test a close's answer — grep of `= sys_close|file_close|syscall(SYS_CLOSE|3,` and
`if (` of the same, 2026-10-16). Row: the repro in
`tests/tcyr/crossos/` (Linux and PE: a good close 0, fd -999 -9), and `file_close_r(-999)` is `Err` on cass.
