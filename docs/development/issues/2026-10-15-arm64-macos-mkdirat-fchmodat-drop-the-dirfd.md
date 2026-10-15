# arm64 macOS `sys_mkdirat` / `sys_fchmodat` drop the dirfd: a relative path lands against the cwd — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on ecb (macOS arm64) with a probe cross-built from the 6.7.12
windows lane's tree (ec058d94). Found while fixing the same shape for `openat` (W2,
issues/2026-10-08-embed-open-link-race-pe-macos-arm64.md), which this does not cover.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (windows lane; filed from the 6.7.12 windows lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** Medium — silent wrong-directory side effects: `sys_mkdirat(dirfd, "rel", …)` creates `./rel` in the
CURRENT directory and returns 0; `sys_fchmodat(dirfd, "rel", …)` changes (or fails to find) `./rel`. Any dirfd-relative
walk (the TOCTOU-safe pattern lib/syscalls_linux_common.cyr documents these wrappers for) is wrong on Apple Silicon.
Not a security id: the developer's own program on the developer's own machine.
**Affects:** arm64 macOS (`CYRIUS_MACHO_ARM=1`), every release since the v6.0.34 at-family rows. x86 macOS, Linux
(x86_64, aarch64), Windows (no such wrappers) unaffected.

## Reproduction

```
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/syscalls.cyr"
include "lib/io.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fs.cyr"
alloc_init();
xmkdir("mkat_root", 493);
var dfd = file_open("mkat_root", O_RDONLY | O_DIRECTORY, 0);
var r = sys_mkdirat(dfd, "mkat_sub", 493);
var rc = 0;
if (r == 0) { rc = rc + 1; }
if (is_dir(str_from("mkat_root/mkat_sub")) == 1) { rc = rc + 10; }
if (is_dir(str_from("mkat_sub")) == 1) { rc = rc + 100; }
file_write_all("mkat_root/f.txt", "x", 1);
var c = sys_fchmodat(dfd, "f.txt", 256, 0);
if (c == 0) { rc = rc + 1000; }
syscall(60, rc);
```

- x86_64 Linux: exit 243 (= 1011 & 255: mkdirat 0, `mkat_root/mkat_sub` made, fchmodat 0) — right.
- ecb, `CYRIUS_MACHO_ARM=1 build/cycc_aarch64`: **exit 101** — mkdirat returned 0 and made `./mkat_sub` in the cwd
  (not under `mkat_root`), and fchmodat failed (it looked for `./f.txt`).

## Root cause

src/backend/aarch64/emit.cyr ESYSXLAT, Mach-O branch: `_esx_arm_shift(S, 34, 136, 2)` (mkdirat → BSD mkdir, the dirfd
shifted out) and `_esx_arm_shift(S, 53, 15, 2)` (fchmodat → BSD chmod, dirfd and flags dropped). Darwin has both:
mkdirat 475 and fchmodat 467, with the Linux argument order. The openat row had the same shape until 6.7.12, which added
`_esx_arm_atfd` (a renumber that keeps x0 and turns Linux's AT_FDCWD -100 into Darwin's -2).

## Proposed fix

`_esx_arm_atfd(S, 34, 475)` and `_esx_arm_atfd(S, 53, 467)` — but fchmodat's FLAGS word also needs Darwin's
`AT_SYMLINK_NOFOLLOW` (0x20, Linux 0x100), which lib/syscalls_linux_common.cyr already defines per target for the
stdlib's own callers. A tests/tcyr/crossos/ row: mkdirat / fchmodat relative to a real dirfd (the repro), on every target.
`_esx_arm_shift` then has no rows left and can go.
