# On macOS `xgetdents(fd, buf, n)` hands Darwin's getdirentries64 the caller's `n` as it is: a buffer no record fits never returns on macOS 13 (the process spins in the kernel, unkillable, and its directory stays locked), and on macOS 27 a buffer the NEXT record does not fit answers 0 — the end of the directory — so the listing silently loses that entry and every one after it — RESOLVED

> ✅ **RESOLVED in v6.7.16** (PP-6, `b748600a3` — 6.7.16's D77, the user, 2026-10-20: "Linux's answer: the records that fit, then -22". `xgetdents` gains a macOS arm, the private `_xgetdents_darwin`: `n >= 1048` passes through, `n < 64` is -22, otherwise it reads a private 1048-byte buffer, hands back every record when all fit, and else puts the directory back (its lseek cookie) and re-reads exactly the fitting records' bytes (at least 64) — -22 when none fit or the re-read returns none; getdirentries64 is never handed a buffer under 1048 bytes. The filed repro verbatim on ecb (macOS 27.0.1) prints `3 records with a 64-byte buffer, last answer -22` / `224 bytes with a 4096-byte buffer` / `-22 for a 24-byte buffer` (was `last answer 0`); x86_64 Linux is unchanged; ecb's /dev (634 entries) lists with no entry repeated at any size and ends -22 early only under 1048 bytes (96 B after 591). ⚠ ach (macOS 13.7.8) was NOT run — neither the repro nor the row: the filing's spinning probe (PID 55644) needs the user's reboot first. The macOS-13 hang is closed by construction only (the kernel is never handed a buffer no record fits); the release gate's ach leg runs the row after the reboot. Rows: the new `tests/tcyr/crossos/xgetdents_small_buffer.tcyr` (a 200-byte listing lists the four entries once and ends 0; a 64-byte loop hands back exactly the entries before the 100-byte name, then -22, and -22 again at it; 24 bytes is -22 on macOS; Windows and agnos SKIP by name) — 17 / 17 natively, qemu-aarch64, the x86_64 cxvm, pi and ecb. Mutation (ecb): the pass-through restored → 2 RED (the loop ends 0). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 on the 6.7.16 platform lane (unit P3), measuring Darwin's
getdirentries64 for cxvm's getdents64 conversion
(issues/archived/2026-10-18-cx-audit-walk-fifo-getdents-mknodat-refused.md). Not fixed there: it changes what a
program computes (a new refusal or a different answer from `xgetdents` on macOS).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 platform lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; p16 lane, wave 3, unit PP2) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D77 — Linux's answer: the records that fit, then -22.
**Severity:** Medium — a stdlib wrapper that, on a supported host, hangs its process unkillably (and
every later access to that directory) or truncates a directory listing with a success-shaped answer.
The developer's own code chooses the buffer; no boundary is crossed (a bug, not a vulnerability).

## Reproduction

`lib/io.cyr`'s `xgetdents` on macOS (both arches) is `syscall(SYS_GETDENTS64, fd, buf, n, &basep)`,
which both Mach-O backends route to Darwin `getdirentries64` (344) with the caller's `n`.

```cyrius
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
alloc_init();
xmkdir("xg_d", 493);
file_write_all("xg_d/a", "x", 1);
file_write_all("xg_d/LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL", "x", 1);
var fd = sys_open("xg_d", O_RDONLY | O_DIRECTORY, 0);
var b[4096];
var r = xgetdents(fd, &b, 64);
var recs = 0;
while (r > 0) {
    var pos = 0;
    while (pos < r) { recs = recs + 1; pos = pos + load16(&b + pos + 16); }
    r = xgetdents(fd, &b, 64);
}
fmt_int(recs); syscall(1, 1, " records with a 64-byte buffer, last answer ", 44); fmt_int(r); syscall(1, 1, "\n", 1);
sys_lseek(fd, 0, 0);
r = xgetdents(fd, &b, 4096);
fmt_int(r); syscall(1, 1, " bytes with a 4096-byte buffer\n", 31);
sys_lseek(fd, 0, 0);
fmt_int(xgetdents(fd, &b, 24)); syscall(1, 1, " for a 24-byte buffer\n", 22);
syscall(60, 0);
```

```text
x86_64 Linux (cycc):
2 records with a 64-byte buffer, last answer -22      <- the 100-byte name does not fit: -EINVAL, said
192 bytes with a 4096-byte buffer
24 for a 24-byte buffer
ecb, macOS 27.0.1 arm64 (CYRIUS_MACHO_ARM=1 cycc_aarch64, ad-hoc signed):
3 records with a 64-byte buffer, last answer 0        <- 4 entries; the long one and all after it lost
224 bytes with a 4096-byte buffer
-22 for a 24-byte buffer
```

On **ach (macOS 13.7.8, x86_64)** the 24-byte call never returns. Measured with an equivalent C probe
(`syscall(SYS_getdirentries64, fd, buf, 24, &basep)`, its first call): the process sat in state `Rs`
using a whole core (11:20 of CPU in 11:21 elapsed), `kill -9` did not end it, and every later
`ls` of its directory blocked in state `U`. It is still there (PID 55644, `~/p6716_P3`) until ach
reboots. The cyrius repro above was NOT run on ach for that reason — its 24-byte line issues the same
call.

## Root cause

`getdirentries64` has no "buffer too small" answer that a caller can rely on across macOS versions:
macOS 27 refuses a buffer under 64 bytes (EINVAL) and, when the NEXT record does not fit, answers 0 —
which reads as the end of the directory — while macOS 13 loops in the kernel when no record fits.
Darwin's records are `align8(25 + namlen)` bytes, at most 1048 (`sizeof(struct direntry)`). `xgetdents`
passes the caller's `n` through; `lib/fs.cyr`'s listers pass 4096 and are unaffected.

## Fix direction

On macOS, never hand `getdirentries64` a buffer under 1048 bytes: refuse a smaller `n` with -EINVAL
before the call (the honest answer: Darwin cannot promise a record fits), or read into a private
1048-byte buffer and copy out what fits, putting the directory back (its lseek cookie) for the rest —
the conversion cxvm's `_cx_darwin_getdents` (programs/cxvm.cyr, 6.7.16) does. ⚠ The platform review found
that put-back's limit (fixed in cxvm by 2b89c707d): on a filesystem without extended readdir (devfs, fdesc) the
re-read converts from old dirents in 3/8 of the buffer and returns fewer records than were converted, or none —
so hand back exactly the records the re-read returned, and -EINVAL when it returns none (ecb's /dev with a 96-byte
buffer then ends after 592 of 635 entries, ach's with 64 bytes after 328 of 334; never a repeat). Which answer `xgetdents`
gives is the user's call. Row: a crossos test of `xgetdents` with a 24- and a 64-byte buffer over a
directory holding a 100-byte name, run on ecb and ach.
