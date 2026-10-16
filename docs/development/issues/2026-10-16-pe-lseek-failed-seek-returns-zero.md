# Windows `xlseek` / `sys_lseek`: a FAILED seek returns 0 — the PE reroute ignores `SetFilePointerEx`'s BOOL and hands back its pre-zeroed output slot — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.13 stdlib lane (unit L1) while running patra 1.16.3's suite on real
cass for issues/2026-10-15-xflock-windows-relock-drops-the-lock-first.md (built against the lane's tree, l6713-stdlib
from f59668ad): six patra rows fail on Windows only, with the 6.7.12 lib and with the fixed one alike. Measured with the
probe below under wine and on cass (Windows 11, `C:\cyrius-tests`).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane; filed from the 6.7.13 stdlib lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — a seek that FAILED reads as a successful seek to offset 0. Every `xlseek(...) < 0` test on
Windows is dead, and since a failed `SetFilePointerEx` leaves the file pointer where it was, the caller's next
`write` lands at the OLD position: silent misplaced writes. patra's WAL replay of a record naming an unseekable page
"restores" it over whatever the file position was and reports success (on Linux and macOS it refuses and keeps the WAL).
**Affects:** every PE binary since the `syscall(8, …)` → `SetFilePointerEx` reroute (`ELSEEK_PE`,
`src/backend/x86/emit.cyr`); `lib/syscalls_windows.cyr`'s `sys_lseek` doc ("Returns the new offset or -1 on failure")
describes a contract the reroute does not keep.

## Reproduction

```cyr
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("lseek_neg.tmp", O_RDWR | O_CREAT | O_TRUNC, 420);
file_write(fd, "abcdefgh", 8);
var r1 = xlseek(fd, 0 - 1, 0);      # SEEK_SET to -1: must fail
var r2 = xlseek(fd, 4, 0);
var r3 = xlseek(fd, 0 - 100, 1);    # SEEK_CUR to 4 - 100: must fail
var r4 = xlseek(fd, 0, 1);
fmt_int(r1); println("");
fmt_int(r2); println("");
fmt_int(r3); println("");
fmt_int(r4); println("");
file_close(fd);
xunlink("lseek_neg.tmp");
```

```
x86_64 Linux (cat p.cyr | build/cycc):          -22  4  -22  4
PE (CYRIUS_TARGET_WIN), wine AND cass:            0  4    0  4
```

The position after the failed seeks is unchanged (r4 = 4), so the failure is real — only the answer is wrong.

patra 1.16.3's suite on cass (its `/tmp/` paths made relative for Windows; built against the lane's lib), the six rows
this explains, identical with the 6.7.12 and the 6.7.13 lib:

```
FAIL: incomplete: a write over a half-restored file is refused (got 0, expected 1)
FAIL: incomplete: and so is a read (got 13822160, expected 0)
FAIL: incomplete: and a BEGIN (got 0, expected 1)
FAIL: incomplete: and reads (got 3, expected 2)
FAIL: wal_recover reports the restore was incomplete (got 1, expected -1)
FAIL: WAL retained after an incomplete restore (got 0, expected 1)
```

(patra's `page_offset(2^51)` is -1; `wal_recover`'s `_pt_seek(db_fd, -1) < 0` never fires on Windows.)

## Root cause

`ELSEEK_PE` zeroes the `lpNewFilePointer` slot at `[rsp+0x28]`, calls `SetFilePointerEx`, and returns the slot
(`mov rax, [rsp+0x28]`) without looking at the BOOL in `eax`. On failure the API leaves the slot untouched, so the
answer is the pre-zeroed 0. Its own comment ("or -1 packed as 0xFFFFFFFF if the API returned 0") describes code that
is not there.

## Fix

Test `eax` after the call: on FALSE return a negative errno (`-22` for `ERROR_NEGATIVE_SEEK` 131 / an invalid
parameter, as Linux answers a negative resulting offset; `-1` otherwise, or `-9` for an invalid handle), else the slot.
A src/ change: seed-derive and the cass self-host. Rows: the probe above in `tests/tcyr/crossos/` (Linux -22, PE -22,
position unchanged) and patra's six rows on cass.
