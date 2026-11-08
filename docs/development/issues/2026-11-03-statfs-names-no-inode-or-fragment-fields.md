# `Statfs` names no inode or fragment field, so `df -i` hardcodes offsets — OPEN

**Status:** 🟡 **OPEN** — verified 2026-11-03 against cyrius 6.7.18.
**Placement:** unpinned — 6.x-line backlog. Three enum members, per OS.
**Discovered:** 2026-11-03 by kriya (coreutils-equivalent), moving `df` off its private statfs offset table
onto the stdlib's `Statfs` layout for 1.8.4.
**Severity:** Low. The Linux offsets are right on x86_64 and aarch64 alike. The cost is that a consumer that
needs these fields has to hardcode them, which is what the `Statfs` comment in
`lib/syscalls_linux_common.cyr` tells it never to do.
**Affects:** cyrius 6.7.18; `enum Statfs` in `lib/syscalls_linux_common.cyr` (both arms) and
`lib/syscalls_x86_64_agnos.cyr`.

## Summary

`enum Statfs` names `STATFS_BSIZE`, `STATFS_BLOCKS`, `STATFS_BFREE`, `STATFS_BAVAIL` and the one-buffer contract
`STATFS_BUFSZ`, with `statfs_bsize()` for the width trap on Darwin. That is enough for a capacity figure
(yukti's `filesystem_usage`), but not for `df`. It also needs:

| Field | Used for | Linux `struct statfs` offset (x86_64 = aarch64) |
|---|---|---|
| `f_files` | `df -i` total inodes | 40 |
| `f_ffree` | `df -i` free inodes | 48 |
| `f_frsize` | the block size `df` counts in (POSIX `f_frsize`; `f_bsize` is the fallback when it is 0) | 72 |

Linux's 120-byte layout is the same on both arches. kriya's `df` reads these at the offsets above, and its
output on x86_64 and on aarch64 under qemu matches GNU df's figures (`smoke-df.sh`, 48 cases on each).

## Proposed fix

- `STATFS_FILES = 40`, `STATFS_FFREE = 48`, `STATFS_FRSIZE = 72` in the Linux arm.
- In the macOS arm, Darwin's `struct statfs64` offsets for `f_files` / `f_ffree`, read off real hardware
  as the existing four were. Darwin has no `f_frsize`; `STATFS_FRSIZE` could equal `STATFS_BSIZE` there,
  or be absent, with the choice documented.
- The agnos arm: whatever its frozen 32-byte record carries, or absent.

## Consumer-side workaround

kriya 1.8.4 (`src/cmd/df.cyr`, `enum DfStatfs`) names the three itself, at the Linux offsets, beside the
stdlib's four. It drops them when the stdlib names them.
