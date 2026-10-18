# PE `xlseek` / `sys_lseek` on fd 0 / 1 / 2 fails -9: ELSEEK_PE passes the std fds as raw HANDLE values (EWRITE_PE / EREAD_PE / EFLUSHFB_PE map them through GetStdHandle) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 platform lane's tree (l6714-platform, after
636129db0, the failed-seek fix for issues/archived/2026-10-16-pe-lseek-failed-seek-returns-zero.md), PE built with the lane's
`build/cycc_win_cross`, run under wine (a private WINEPREFIX) and on real cass (Windows 11, `C:\cyrius-tests`). Filed
from the platform lane's review: the triage met it in passing, and the lane's handoff named it only in
ecosystem-migration.
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — a seek on a redirected stdin / stdout / stderr, which works on Linux and macOS, fails on Windows
with -EBADF. There is no in-tree caller (lib/, cbt/, programs/, src/ grep). Until 6.7.14 the same seek answered 0 —
the failure was there, invisible (the BOOL was not read); 636129db0 made it visible, it did not cause it.
**Affects:** `src/backend/x86/emit.cyr` `ELSEEK_PE`; `lib/syscalls_windows.cyr` `sys_lseek`, `lib/io.cyr` `xlseek` on
`CYRIUS_TARGET_WIN`.

## Reproduction

```cyr
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var a = xlseek(0, 3, 0);      # stdin redirected from a file: SEEK_SET to 3
var b = xlseek(1, 0, 1);      # stdout redirected to a file: SEEK_CUR
var c = xlseek(2, 0, 2);      # stderr redirected to a file: SEEK_END
var ch[8];
store64(&ch, 0);
var n = file_read(0, &ch, 1); # the byte at stdin's position
fmt_int(a); println("");
fmt_int(b); println("");
fmt_int(c); println("");
fmt_int(n); println("");
fmt_int(load8(&ch)); println("");
```

```sh
printf 'abcdefgh' > in.txt
cat stdseek.cyr | build/cycc > stdseek && ./stdseek < in.txt > out.txt 2> err.txt; cat out.txt
cat stdseek.cyr | build/cycc_win_cross > stdseek.exe          # then, on wine and on cass:
stdseek.exe < in.txt > out.txt 2> err.txt & type out.txt
```

```text
x86_64 Linux:          3   0   0   1  100   (the seek moved stdin to 'd')
PE, wine:             -9  -9  -9   1   97   (every std-fd seek -EBADF; stdin still at 'a')
PE, real cass:        -9  -9  -9   1   97
```

## Root cause

`ELSEEK_PE` pops the fd straight into `rcx` (`mov rcx, rax (hFile)`) and calls `SetFilePointerEx` with it, so fd
0 / 1 / 2 reach kernel32 as the HANDLE values 0, 1, 2 — not handles — and the call fails `ERROR_INVALID_HANDLE`
(-9 through `_pe_w32_errno_site`). Every other fd-taking reroute maps the std fds first through the shared prologue
`_pe_fd_to_handle_rcx` (fd {0,1,2} → `GetStdHandle({-10,-11,-12})`, any other fd used directly, unsigned compare):
`EWRITE_PE`, `EREAD_PE` (v6.4.26) and `EFLUSHFB_PE` (v6.6.7, which calls it from inside an rbx-anchored aligned frame
so the GetStdHandle call gets the same alignment and shadow space). `ELSEEK_PE` still uses its fixed `0x30` frame
(`_pe_fixed_frame`) and never got the mapping.

## Proposed fix

Call `_pe_fd_to_handle_rcx` in `ELSEEK_PE` once the frame is carved (the fd popped into `rax`, `offset` / `whence`
stashed across the GetStdHandle call in the frame, the way EWRITE_PE stashes `buf` / `len` at `[rsp+0x30]` /
`[rsp+0x38]`), so a seek on a redirected std stream reaches the file. What a PIPE or console std handle answers then is
unmeasured (Linux says -29 ESPIPE; Microsoft documents SetFilePointerEx on a pipe as unsupported, not what it
returns) — measure it on cass and pin whatever the shared GetLastError table gives. Row: a `tests/tcyr/crossos/` file that runs with stdin /
stdout redirected from / to files is not something the cross-OS leg sets up, so the row is a PE-run gate (wine) plus
the cass hardware run recorded in the CHANGELOG; the repro above, verbatim, must print `3 0 0 1 100` on PE.
