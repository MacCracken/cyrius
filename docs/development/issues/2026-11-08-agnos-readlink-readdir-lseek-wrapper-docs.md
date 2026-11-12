# `lib/syscalls_x86_64_agnos.cyr`: the `sys_readlink` / `sys_readdir` / `sys_readdir_at` / `sys_lseek` comments describe the pre-1.57.18 agnos ABI

**Status:** 🟡 **OPEN** — filed by agnos (2026-11-08) for its **1.57.18** cut. No new syscall number; no wrapper's
arity changes. Do not edit before agnos's `1.57.18` tag.
**Placement:** `lib/syscalls_x86_64_agnos.cyr` — the comments above `sys_readlink` (:1503-1508), `sys_readdir`
(:1547-1554), `sys_readdir_at` (:1556-1585), `sys_lseek` (:1056-1060); optionally a `RdRec` enum beside `FdKind`
(:194); optionally `lib/fs.cyr` `is_symlink` (:514).
**Filed:** 2026-11-08, by agnos (track T3: issues `2026-11-06-readlink-refuses-a-buffer-shorter-than-the-target`,
filed from thoth 0.55.1, and `2026-11-08-readdir-cuts-a-long-name-and-says-nothing`, filed from crab 0.11.3).
**Affects:** cyrius **6.7.18** (agnos's pin).
**Severity:** **Low as code, medium as documentation**: the `sys_readdir` comment tells a caller "type at +63: 1=dir/0=file",
which written as `== 1` reads a cut DIRECTORY (byte 63 == 3 from 1.57.18) as a file.

## What changed in agnos 1.57.18 (authoritative: agnos `docs/development/agnos-userland-abi.md` rows #29 / #58 / #70 / #81 / #101, § 4.2.1)

- **`readlink#70` copies at most `buflen` bytes and returns the count copied** (Linux / FreeBSD semantics). -1 only
  for: not found, not a symlink, `buflen < 1`, a corrupt link (longer than its format holds), a mount that is neither
  ext2 nor ZFS. Through 1.57.17 a target longer than `buflen` was -1 — so `is_symlink`'s 8-byte probe answered 0 for
  every link with a target over 8 bytes on agnos (thoth 0.55.1 measured a jail following `link-out -> /etc/secret.txt`).
  **With agnos 1.57.18, `is_symlink` is right as written.**
- **`readdir#81` / `readdir_at#101` record byte 63 is FLAGS**: bit 0 `RD_DIR` (1) a directory · bit 1 `RD_CUT` (2) the
  name was longer than 62 bytes and was cut (on a UTF-8 character boundary: 59..62 bytes kept) · bits 2-7 zero.
  Whole names: `getdents#29`.
- **`readdir_at#101`**: `-5` now means only "cursor not 4-byte aligned"; an aligned cursor inside a record is snapped
  to the next record boundary; one at or past the end is exhausted (`0`, cursor `-1`).
- **`lseek#58` accepts an `AO_DIRECTORY` fd** (ext2, ZFS): the position is an opaque cookie — `lseek(fd, 0, SEEK_CUR)`
  is telldir, `lseek(fd, cookie, SEEK_SET)` is seekdir (valid across close / reopen of the same directory);
  `SEEK_END` and a negative result are -1.
- **`getdents#29` with a buffer too small for the next record answers -1** (it answered 0 on ext2).

## The ask

1. Rewrite the four comments to the contract above (the `sys_readlink` one says "-1 on: ... target > buflen"; the
   `sys_lseek` one says "reposition a VFS_EXT2_FILE cursor"; the `sys_readdir_at` one says the cursor must be inside a
   record or -5).
2. Optionally name the flags, so callers mask instead of comparing:
   ```
   enum RdRec { RD_NAME_MAX = 62; RD_DIR = 1; RD_CUT = 2; RD_REC_SZ = 64; }
   ```
3. Optionally make `is_symlink` independent of the kernel version on agnos: `sys_lstat(&cpath, cn, &st) == 0 &&
   (load64(&st) & 0xF000) == 0xA000` (lstat#102, agnos >= 1.56.53) has no buffer to outgrow and is right on 1.57.17
   too — thoth 0.55.1's `fs_is_link` already does exactly this. Keep `sys_readlink` for the Linux/macOS arms.

## Self-proving repro (agnos's gate: `scripts/smoke/fs-listing-smoke.sh`, `tests/readdir/rdlong.cyr`)

```
# /sl -> "/etc" + 88 x "/" + "hostname"   (100 bytes, a slow ext2 symlink)
var b[8];
sys_readlink("/sl", 3, &b, 8)     # agnos 1.57.17: -1 (is_symlink -> 0)   agnos 1.57.18: 8, b = "/etc////"
sys_readlink("/etc/hostname", 13, &b, 8)   # -1 on both (not a link)
# readdir of a dir holding g x 70 (a directory):  byte 63 == 3  ->  `== 1` says "file", `& 1` says "directory"
```
