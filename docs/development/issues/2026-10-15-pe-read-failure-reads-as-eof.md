# PE `sys_read` returns ReadFile's byte count even when ReadFile FAILS: a read error reads as 0, end of file — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on real cass (Windows 11) with the 6.7.12 windows lane's tree
(l6712-windows @ 163d1a85); found by the cass full-corpus triage
(issues/archived/2026-10-12-cass-full-corpus-failures-untriaged.md, class (c): a real PE defect). It is the fourth row
`tests/tcyr/stdlib/result_stdlib.tcyr` still fails on cass (the other three: 2026-10-15-pe-open-failure-is-always-minus-one.md).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (windows lane; filed from the 6.7.12 windows lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** Medium — a failed read is indistinguishable from end of file on Windows: a loop that reads to EOF stops
early and reports a short, complete-looking result (the shape fs_win.cyr's FindNextFileW fix closed for listings in
6.6.12), and `file_read_r` answers `Ok(0)` for a handle that is not open.
**Affects:** `EREAD_PE` (src/backend/x86/emit.cyr:1830-1884): after `call [ReadFile]` it returns
`mov eax, [rsp+0x28]` (lpNumberOfBytesRead) without testing the BOOL in eax; every `sys_read` / `file_read` /
`file_read_r` / `file_read_all` on PE.

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var buf[16];
var n = file_read(0 - 999, &buf, 16);        # not a descriptor / handle
syscall(SYS_EXIT, 100 + n);                  # Linux 91 (-EBADF); Windows 100 (0, "EOF")
```

```
x86_64 Linux (build/cycc):                    exit 91
cass (CYRIUS_TARGET_WIN=1 build/cycc, under C:\cyrius-tests):  exit 100
```

and the corpus row on cass: `FAIL: read on bogus fd is Err (got 0, expected 1)`.

## Root cause

ReadFile sets *lpNumberOfBytesRead to 0 "before doing any work or error checking" and returns FALSE on failure; the
emitter discards the BOOL and returns the count, so every failure is a 0-byte read.

## Proposed fix

Test eax after the call: TRUE → the count; FALSE → GetLastError, where ERROR_BROKEN_PIPE (109) and ERROR_HANDLE_EOF
(38) ARE end of file (a pipe whose writer closed — what process_win.cyr's drains and the include reader rely on) and
answer 0, and anything else answers a negative errno (ERROR_INVALID_HANDLE 6 → -EBADF, …). ⚠ The include reader of
cycc.exe itself goes through this emitter, so the change needs the cass self-host and seed-derive; and EWRITE_PE has
the same shape to check. Row: the repro in `tests/tcyr/crossos/` (cass), result_stdlib.tcyr's bogus-fd row green on cass.
