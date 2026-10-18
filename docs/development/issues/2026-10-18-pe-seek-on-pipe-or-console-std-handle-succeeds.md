# PE `xlseek` / `sys_lseek` on a PIPE or console handle succeeds on Windows (answers the asked offset, the stream does not move) where Linux and macOS answer -ESPIPE (-29); wine answers -1 — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 platform lane (branch l6715-platform), on the tree that
carries the fix for issues/2026-10-16-pe-lseek-std-fds-pass-raw-handle.md (ELSEEK_PE maps fd 0 / 1 / 2 through
GetStdHandle). PE built with `CYRIUS_TARGET_WIN=1 build/cycc`; run on real cass (Windows 11, `C:\cyrius-tests`) and
under wine 11.19 (a private WINEPREFIX).
**Placement:** unplaced — filed from the 6.7.15 platform lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — no in-tree caller seeks a pipe or a console (lib/, cbt/, programs/, src/ grep for `xlseek` /
`sys_lseek` / `syscall(SYS_LSEEK` / `syscall(8,`). A portable program that detects "stdin is a pipe" by a failed seek
(the POSIX idiom: `lseek(0, 0, SEEK_CUR) < 0` → not seekable, read it to the end) misreads a pipe or console as a
seekable file on Windows. Not a security issue (no boundary: the program's own std handles).
**Needs a decision:** yes — whether a Windows seek on a non-disk handle answers -29 as on Linux / macOS (6.7.14's D51
reason: one program gives one answer on every target), or Windows' own answer is kept and documented.
**Found:** in passing while fixing the std-fd seek (6.7.15 platform lane, unit P2): its brief asked to measure what a
pipe / console std handle answers on cass. Before that fix every std-fd seek failed -9 (the raw handle values), so this
answer could not be seen; the fix made it visible, it did not cause it.

## Reproduction

The std-fd issue's filed repro (`stdseek.cyr`), verbatim:

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

run with stdin from a PIPE (stdout / stderr to files):

```text
x86_64 Linux   printf 'abcdefgh' | ./stdseek > out.txt 2> err.txt                 -29  0  0  1  97
PE, real cass  cmd /c "type in.txt | stdseek.exe > out.txt 2> err.txt"             3  0  0  1  97
PE, wine       printf 'abcdefgh' | wine stdseek.exe > out.txt 2> err.txt          -1  0  0  1  97
```

(97 = 'a': the seek did not move the pipe on any target; only the ANSWER differs.)

A CONSOLE stdin / stdout / stderr on cass (`ssh -tt cass 'C:\...\conseek.exe'`, a ConPTY; the probe seeks fd 0 to 3,
fd 1 and fd 2 SEEK_CUR, and reads GetLastError (`syscall(61515)`) after each): `3 / 0 / 0`, each with GetLastError 0
— SetFilePointerEx succeeds on a console handle too. A pipe STDOUT on cass (`stdseek.exe < in.txt | findstr .`):
SEEK_CUR answers 0. Linux answers -29 for a pipe or a terminal.

## Root cause

ELSEEK_PE (src/backend/x86/emit.cyr) calls SetFilePointerEx on whatever handle it gets and answers the new position
when the BOOL is TRUE. On real Windows SetFilePointerEx on an anonymous pipe or a console handle returns TRUE (the
file object's position is bookkeeping the device ignores); Microsoft documents the call as unsupported on non-seeking
devices, not as failing. wine fails it with ERROR_INVALID_FUNCTION (1), which has no row in the shared GetLastError
table (`_pe_w32_errno_rows_a/_b`), so it answers -1. Linux / macOS lseek(2) answers ESPIPE for a pipe, FIFO or socket
(and Linux for a tty).

## Fix direction (not decided here)

If the answer should be -29 on Windows: before (or instead of) SetFilePointerEx, ask `GetFileType(handle)` and answer
-29 for FILE_TYPE_PIPE (3) and FILE_TYPE_CHAR (2) — one more kernel32 import and a call per seek site (~+20 B a site
plus the call), measured on cass for both shapes; a table row ERROR_INVALID_FUNCTION (1) → -29 would only cover wine.
Row: tests/gates/platform/pe_lseek_std_fds.sh's pipe row (it pins wine's `-1 0 0 1 97` today) moves to
`-29 0 0 1 97`, plus the cass hardware run of both shapes.
