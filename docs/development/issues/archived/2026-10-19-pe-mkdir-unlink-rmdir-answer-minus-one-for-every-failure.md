# PE `sys_mkdir` / `sys_unlink` / `sys_rmdir` / `sys_ftruncate` / `sys_truncate` answer -1 for every failure — Linux answers -17 / -2 / -39 (EEXIST, ENOENT, ENOTEMPTY), and -22 / -9 / -2 for a truncate of a pipe, a bad or closed fd, a missing path; a cx guest on a Windows host reads the same -1 — RESOLVED

> ✅ **RESOLVED in v6.7.16** (PP-2, `990610948`, with PP-3 `117ae53ab`, PP-4 `f4e6696a0` (finds met fixing it) and the review fixes PP-2r `9ef802604` and PP-2r2 `e24cc3d67` — 6.7.16's D79, the user, 2026-10-20: "Linux's negative errno, through the Windows error table", and D80, 2026-10-20: "-22, as Linux". The new `_pe_bool_errno` sends a kernel32 BOOL's FALSE through the shared GetLastError table stub: `_pe_path_bool1` (CreateDirectoryW / DeleteFileW / RemoveDirectoryW, so `sys_mkdir` / `sys_unlink` / `sys_rmdir` and `xmkdir` / `xunlink` / `xrmdir` through 0xF035 / 0xF03B) drops its `dec; sar`, and ESETEOF_PE (0xF03F) answers 0 / -errno instead of the BOOL, its three lib callers flipped in the same commit. `sys_ftruncate` answers a failed step's errno, with the seek's -29 (a pipe or console), SetEndOfFile's -13 (a read-only or, on Windows only, an O_APPEND descriptor) and — PP-2r — a code the table leaves -1 (the `NUL` device's ERROR_INVALID_FUNCTION) or SetEndOfFile's -9 after both seeks mapped to -22; `sys_truncate` answers its open's errno, and `sys_truncate("NUL", n)` is -22. The filed pathfail prints `0 -17 -39 -2 -2 0 0` under wine and on cass (was `0 -1 -1 -1 -1 0 0`) and the filed ftfail, stdout piped, `-22 -9 -2 -9` (was `-1 -1 -1 -1`), as on Linux; a cx guest's rmdir of a non-empty directory on a Windows host reads -39 (it read -1), and a cx guest's `sys_truncate` now runs on every host (PP-4; it answered -38). ⚠ ftfail's second cell (`sys_ftruncate(99, 3)`, an fd never opened) holds -9 on real Windows only while no live handle sits at 96 — the NT kernel ignores a handle's low two bits, and `ftfail.exe < nul | findstr .` reads -22 there (PP-2r2 moved the guide's row to `sys_ftruncate(-999, n)`); that aliasing is filed separately (`2026-10-20-pe-fd-not-multiple-of-four-aliases-the-handle-below-it.md`, 6.7.16's pw lane). Rows: the new `tests/tcyr/crossos/path_failure_errno.tcyr` (27 rows, Darwin's ENOTEMPTY 66, the null device's ftruncate 0 on macOS) — 27 / 27 natively, qemu-aarch64, the x86_64 cxvm, wine, cass, ecb, ach and pi; `pe_reroute_failure_errno.sh` axes 1 / 4 run pathfail, ftfail and the tcyr (floor 27) and axis 2 requires the table-stub call after every CreateDirectoryW / DeleteFileW / RemoveDirectoryW / SetEndOfFile call; the cx host-dispatch fixture's errno row (Windows rmdir -39) and path row (truncate 7 → 3 bytes); `cli_args_never_dropped.sh`'s wine leg (a missing %TEMP% named with errno 2, PP-3). Mutations each RED: the path `.fail` call NOPped, ESETEOF_PE's map dropped, the lib -22 map dropped, the pre-fix tree (11 RED), the null-device maps (each on its own platform), cxvm's truncate arm (MU15), the CLI carve-out restored (MV). The same class outside D79's five calls (rename / symlink / fsync) and a directory's EACCES are filed separately and placed in 6.7.16 (D94, D95). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 platform lane (branch l6716-platform, unit P2), with
the PE cross compiler built from the lane's tree, under wine 11.20 (a private WINEPREFIX) and on real cass
(Windows 11, `C:\cyrius-tests`). The lane does not change these wrappers; the answer is the slot-open one.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 platform lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; p16 lane, wave 3, unit PP1) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D79 — Linux's negative errno, through the Windows error table.
**Decision (user, 2026-10-20, the found issues' round):** D80 — -22, as Linux.
**Severity:** Low — a portable program that tells "already exists" (`xmkdir` of an existing directory), "absent"
(`xunlink` of a missing file) or "not empty" (`xrmdir`) apart by the errno reads a bare -1 on Windows, where
every other target (and, since 6.7.14, a failed PE open / read / write / seek, and since 6.7.15 a failed close)
answers the negative errno through the `GetLastError` table. No boundary is crossed (no ledger id).
**Widened:** 2026-10-19 by the 6.7.16 platform review (its file_as_issue: "fold it into that issue (dissolve into
the class) rather than file it alone") — `sys_ftruncate` / `sys_truncate` are the same class, measured below.
**Found:** in passing while adding the errno row to tests/fixtures/cx_host_dispatch.cyr for
issues/archived/2026-10-18-cxvm-darwin-errnos-reach-the-guest-unmapped.md (6.7.16 P2): rmdir of a non-empty directory reads
-1 on the PE cxvm (wine and cass), -39 on every POSIX host's cxvm. The fixture pins the -1 as Windows' answer
(its `pe` mask), so a fix here updates that row.

## Reproduction

`pathfail.cyr`, built natively for each target (`cycc` / `cycc_win`), run in an empty directory:

```cyr
include "lib/syscalls.cyr"
include "lib/string.cyr"
var out[256];
var on = 0;
fn pd(v): i64 {
    if (v < 0) { store8(&out + on, 45); on = on + 1; v = 0 - v; }
    var t[24];
    var n = 0;
    if (v == 0) { store8(&t, 48); n = 1; }
    while (v > 0) { store8(&t + n, 48 + v % 10); v = v / 10; n = n + 1; }
    while (n > 0) { n = n - 1; store8(&out + on, load8(&t + n)); on = on + 1; }
    store8(&out + on, 32); on = on + 1;
    return 0;
}
sys_rmdir("pf_d/f");
sys_unlink("pf_d/f");
sys_rmdir("pf_d");
pd(sys_mkdir("pf_d", 448));            # 0
pd(sys_mkdir("pf_d", 448));            # an existing directory: Linux -17
var fd = sys_open("pf_d/f", 577, 420);
sys_close(fd);
pd(sys_rmdir("pf_d"));                 # not empty: Linux -39
pd(sys_unlink("pf_missing"));          # Linux -2
pd(sys_rmdir("pf_missing"));           # Linux -2
pd(sys_unlink("pf_d/f"));              # 0
pd(sys_rmdir("pf_d"));                 # 0
store8(&out + on, 10); on = on + 1;
sys_write(1, &out, on);
sys_exit(0);
```

```text
x86_64 Linux   0 -17 -39 -2 -2 0 0
wine 11.20     0 -1 -1 -1 -1 0 0
cass           0 -1 -1 -1 -1 0 0
```

## Root cause

lib/syscalls_windows.cyr: `sys_mkdir` (syscall 83 → `CreateDirectoryW`), `sys_unlink` (87 → `DeleteFileW`) and
`sys_rmdir` (0xF03B → `RemoveDirectoryW`) document "Returns 0 on success, -1 on failure". All three reroutes go
through src/backend/x86/emit.cyr `_pe_path_bool1` ("One narrow path → one BOOL kernel32 call"), which ends
`dec rax; sar rax, 63` (BOOL → 0 / -1) and never reads `GetLastError` — unlike the open / read / write / seek /
close reroutes, which map it through the shared errno stub since 6.7.14 / 6.7.15. That stub's table already has
the rows these need (`_pe_w32_errno_rows_a` / `_b`: `ERROR_FILE_EXISTS` 80 and `ERROR_ALREADY_EXISTS` 183 → -17,
`ERROR_DIR_NOT_EMPTY` 145 → -39, `ERROR_FILE_NOT_FOUND` / `ERROR_PATH_NOT_FOUND` → -2). Not checked: rename /
symlink failures.

## Fix direction

Send `_pe_path_bool1`'s FALSE arm through the shared errno stub (the -1 for a refused path stays whatever the
reroute's own rule says); update the wrappers' comments, the guide's Windows failure table and the `pe` answer of
tests/fixtures/cx_host_dispatch.cyr's errno row (rmdir -1 → -39). A changed native PE value — the user's call (it
is what 6.7.14 did for open / read / write / seek). A src/ change: seed-derive, a wine gate run and a cass
self-host.

## The same class: `sys_ftruncate` / `sys_truncate` (added by the 6.7.16 platform review)

`ftfail.cyr`, built natively for each target (`cycc` / `cycc_win`, here the lane's `cycc_win_cross`), run in an
empty directory with stdout piped (`./ftfail | cat`; wine `wine ftfail.exe | cat`; cass `ftfail.exe | findstr .`);
the answers go to `ft.out`:

```cyr
include "lib/syscalls.cyr"
include "lib/string.cyr"
var out[256];
var on = 0;
fn pd(v): i64 {
    if (v < 0) { store8(&out + on, 45); on = on + 1; v = 0 - v; }
    var t[24];
    var n = 0;
    if (v == 0) { store8(&t, 48); n = 1; }
    while (v > 0) { store8(&t + n, 48 + v % 10); v = v / 10; n = n + 1; }
    while (n > 0) { n = n - 1; store8(&out + on, load8(&t + n)); on = on + 1; }
    store8(&out + on, 32); on = on + 1;
    return 0;
}
pd(sys_ftruncate(1, 3));              # stdout is a pipe: Linux -22
pd(sys_ftruncate(99, 3));             # an fd never opened: Linux -9
pd(sys_truncate("ft_missing", 3));    # no such file: Linux -2
sys_close(1);
pd(sys_ftruncate(1, 3));              # stdout closed: Linux -9
store8(&out + on, 10); on = on + 1;
var fd = sys_open("ft.out", 577, 420);
sys_write(fd, &out, on);
sys_close(fd);
sys_exit(0);
```

```text
x86_64 Linux   -22 -9 -2 -9
wine 11.20     -1 -1 -1 -1
cass           -1 -1 -1 -1
```

Root cause: lib/syscalls_windows.cyr `sys_ftruncate` returns `0 - 1` whenever its first `SEEK_CUR`, its seek to
`length` or `SetEndOfFile` (reroute 61503) fails, discarding the seek's own errno — -29 on a pipe or console since
6.7.16's D31, -9 for a bad fd, and since 6.7.16's D30 a std fd that was closed answers -9 from the seek too — and
`sys_truncate` returns `0 - 1` when its open fails, discarding the open's -2 / -13. Fix direction: hand back the
failed seek's / open's negative errno and send `SetEndOfFile`'s FALSE through the shared errno stub (as for the
path reroutes above); which answer a pipe gets — Linux's -22 or the seek's -29 — is the user's call, as is the
changed native PE value. The wrappers' comments ("-1 on failure") and the guide's Windows failure table change
with it.
