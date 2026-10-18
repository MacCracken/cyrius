# PE `sys_close` and `sys_ftruncate` on fd 0 / 1 / 2 pass the raw HANDLE values 0 / 1 / 2 to kernel32 (no GetStdHandle map): close(2) answers -9 and stderr stays open, ftruncate(1) of a redirected stdout fails — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 platform lane (branch l6715-platform), on the tree that
carries the fixes for issues/2026-10-16-pe-close-returns-closehandle-bool.md (a close answers 0 or -errno) and
issues/2026-10-16-pe-lseek-std-fds-pass-raw-handle.md (ELSEEK_PE maps fd 0 / 1 / 2 through GetStdHandle). PE built
with `CYRIUS_TARGET_WIN=1 build/cycc`; run on real cass (Windows 11, `C:\cyrius-tests`) and under wine 11.19.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 platform lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — no in-tree caller closes or truncates fd 0 / 1 / 2 (lib/, cbt/, programs/, src/ grep for
`sys_close` / `file_close` / `sys_ftruncate` / `syscall(3, …)` on 0, 1, 2 or a STD* name: none). A portable program that closes stderr (or stdout) to silence it, or truncates a
redirected stdout, gets a different answer and effect on Windows. Not a security issue (the program's own handles).
**Needs a decision:** yes for the close half — the close-BOOL issue's triage named it ("Whether to map them is the
user's call"): mapping fd 0 / 1 / 2 through GetStdHandle makes close(2) close the process's real stderr handle, as
Linux does. The ftruncate half is the same defect as the lseek one (every other fd-taking file reroute maps them).
**Found:** in passing while fixing the two issues above (6.7.15 platform lane, unit P2).

## Reproduction

Close (`closestd.cyr`):

```cyr
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var c = sys_close(2);         # close stderr
var w = file_write(2, "x", 1); # a write to the closed fd
fmt_int(c); println("");
fmt_int(w); println("");
```

```text
x86_64 Linux                                  0  -9   (stderr closed; the write fails EBADF)
PE, wine and real cass, this lane's tree     -9   1   (CloseHandle(2) fails; stderr still writes)
PE, wine and real cass, 6.7.14 (b2e1f4c48)    0   1   (the BOOL FALSE, read as success)
```

ftruncate (`trstd.cyr`, run with stdout redirected to a file: `./trstd > tr.out`):

```cyr
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
file_write(1, "abcdefgh", 8);
var t = sys_ftruncate(1, 3);  # stdout redirected to a file
syscall(SYS_EXIT, 100 + t);   # Linux 100 (0); a failure 99 (-1)
```

```text
x86_64 Linux     exit 100, tr.out = abc
PE, wine         exit 99,  tr.out = abcdefgh
```

## Root cause

`ECLOSE_PE` (src/backend/x86/emit.cyr, `syscall(3, fd)` → CloseHandle) and `ESETEOF_PE` (0xF03F → SetEndOfFile, which
lib/syscalls_windows.cyr `sys_ftruncate` calls with the caller's fd) put the fd straight into rcx. `EWRITE_PE`,
`EREAD_PE`, `EFLUSHFB_PE` and, since 6.7.15, `ELSEEK_PE` map fd 0 / 1 / 2 through the shared `_pe_fd_to_handle_rcx`
(GetStdHandle(-10 / -11 / -12)) first. sys_ftruncate's two seeks now reach the std handle (6.7.15), its SetEndOfFile
does not, so it answers -1 (before 6.7.15 its first seek failed -9 and it answered -1 too).

## Fix direction (not decided here)

Close: if the user chooses to map, call `_pe_fd_to_handle_rcx` inside ECLOSE_PE's aligned frame (the EFLUSHFB_PE
shape); a later write to that fd then fails as on Linux (GetStdHandle returns the closed value — measure on cass what
WriteFile answers then). ftruncate: the same map in ESETEOF_PE (or a std-fd arm in sys_ftruncate). Rows: the two
repros above in a PE wine gate plus the cass run; a crossos .tcyr cannot redirect its own std streams.
