# PE `file_rename` / `sys_rename`, `xsymlink` / `sys_symlink` and `xfsync` / `sys_fsync` answer -1 for every failure — Linux answers the errno (-2 for a missing path or parent, -9 for a non-descriptor); the same class as 6.7.16's D79, outside its five calls — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.16 p16 review (its file_as_issue), measured again 2026-10-20 on the p16
lane (l6716-p16 at e24cc3d67) with the PE compiler built from the lane's tree (`CYRIUS_TARGET_WIN=1 ./build/cycc`),
under wine 11.20 (a private WINEPREFIX) and on real cass (Windows 11, `C:\cyrius-tests`).
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 p16 review; placed at the p16 / t16 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; pw lane, wave 4, unit PW1) — never 7.x.
**Decision (user, 2026-10-20, asked at the p16 / t16 integration):** D94 — Yes, extend D79 (rename / symlink / fsync answer Linux's errnos through the Windows error table).
**Severity:** Low — a silent wrong value: a portable program that tells "absent" from another failure by the errno
reads a bare -1 on Windows for these three calls, where every other target, and since 6.7.16 a Windows mkdir /
unlink / rmdir / ftruncate / truncate (D79 / D80), answers the negative errno. No boundary is crossed (no ledger id).
**Why it is not fixed in the lane:** routing these three through `_pe_bool_errno` changes what a Windows program
reads from calls beyond the five D79 decided (mkdir / unlink / rmdir / ftruncate / truncate) — the user's call. It
is a `src/` change (seed-derive, the cass self-host).

## Reproduction

`rsfail.cyr`, built for each target from the repo root (`./build/cycc` / `CYRIUS_TARGET_WIN=1 ./build/cycc`), run
in an empty directory:

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/fs.cyr"
alloc_init();
fn p(v): i64 { fmt_int(v); sys_write(1, " ", 1); return 0; }
var fd = sys_open("rs_t", 577, 420);
sys_close(fd);
p(file_rename("rs_missing", "rs_x"));          # rename of a missing path: Linux -2
p(xsymlink("rs_t", "rs_missing_dir/l"));       # link under a missing directory: Linux -2
p(xfsync(0 - 999));                            # fsync of a non-descriptor: Linux -9
println("");
sys_unlink("rs_t");
```

| host | output |
|---|---|
| x86_64 Linux | `-2 -2 -9` |
| wine 11.20 | `-1 -1 -1` |
| cass (real Windows 11) | `-1 -1 -1` |

(The symlink cell on cass is -1 for any failure, including the policy refusal a non-elevated process without
Developer Mode gets; the missing parent is what the row names.)

## The sites (src/backend/x86/emit.cyr at e24cc3d67)

- `EMOVEFILEEX_PE` (~3919, MoveFileExW, 0xF034 — `sys_rename` / `file_rename`): `dec rax; sar rax, 63` (BOOL → 0 / -1).
- `ESYMLINKW_PE` (~4056, CreateSymbolicLinkW, 0xF03E): `movzx eax, al` (the BOOLEAN), which `sys_symlink` in
  lib/syscalls_windows.cyr folds to 0 / -1.
- `EFLUSHFB_PE` (~3107, FlushFileBuffers, 74 / 75 — `sys_fsync` / `sys_fdatasync` / `xfsync`): `cmp eax, 1;
  sbb rax, rax`.

None reads GetLastError. The fix is D79's shape: each FALSE goes through the shared table stub (`_pe_bool_errno`,
rsp as for the call), so a missing path is -2, a bad handle -9, a refused link -1 only where the table has no row;
`sys_symlink`'s fold then answers the errno instead of -1 (it calls CreateSymbolicLinkW with the unprivileged
flag, then again without it after any failure, and returns -1 when both fail — it would answer the second call's
errno; its `!= 0` success tests flip to `== 0`, as the 0xF03F callers did in 990610948). Rows: a `crossos/` tcyr
pinning `file_rename` of a missing path -2, `xsymlink` under a missing directory -2 (where links can be made), and
`xfsync(-999)` -9 on every target; pe_reroute_failure_errno.sh's axis 2 adds the three calls to its
table-stub-after-every-BOOL check.
