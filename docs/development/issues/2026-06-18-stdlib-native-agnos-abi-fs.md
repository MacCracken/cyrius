# cyrius-native stdlib agnos ABI gaps (fs.cyr) + a stdlib-wide portable wrapper

> **PARTIALLY RESOLVED (landed, targeting v6.2.23) — fs.cyr done; structural
> asks still OPEN.** The 5 `fs.cyr` sites are fixed: `dir_list`/`is_dir` now have
> a `#ifdef CYRIUS_TARGET_AGNOS` branch using getdents **#29** (3-arg) + the
> sovereign reclen-delimited dirent parse (§4.2: reclen@0/type@2/namelen@3/ino@4/
> name@8, non-NUL-terminated → `str_from_buf`), and the agnos `sys_open`
> `(name, namelen, flags)` ABI. **A v6.2.23 adversarial review caught a P0 in the
> first cut**: the opens used `flags=0`, but the agnos kernel routes a non-`0x800`
> open to `ext2_open()` which rejects directory inodes (`mode != 0x8000` → -1),
> so every dir open died (dir_list empty, is_dir always 0). Fixed to pass
> **`AO_DIRECTORY` (0x800)** so the kernel routes to `ext2_open_dir()`
> (`agnos/kernel/core/syscall.cyr:586`). A new agnos-gate probe (1e) emit-inspects
> getdents #29 + the 0x800 flag to guard against rot. Also during the same slot,
> the **sigil 3.9.0 fold** surfaced a related gap — `luks_write_keyfile` references
> `O_EXCL`, undefined on agnos — fixed by adding `O_EXCL` to io.cyr's neutral
> agnos `O_*` set (`feedback_stdlib_self_sufficient_constants`).
>
> **STILL OPEN (the "stdlib-wide structural fix" section below):** (1) the
> length-carrying portable wrapper set (`xopen`/`xstat`/`xunlink`/`xgetdents`)
> promoted to the base syscalls layer; (2) the cyrlint rule flagging
> unguarded `sys_open(<expr>, <int-literal>, …)` / raw `syscall(SYS_GETDENTS64…)`;
> (3) the other raw-`sys_open(path,<linux-flags>,mode)` sites the audit counted
> (~58 across tls/agnosys/patra **and now sigil's luks_write_keyfile**, which uses
> raw sys_open with Linux args — harmless on agnos in practice since LUKS keyfile
> writing is Linux-disk-only, but it's another instance of this class). These
> remain tracked here; they were NOT in the v6.2.23 scope.

**Filed:** 2026-06-18
**Scope:** cyrius-NATIVE stdlib only — `lib/fs.cyr`. (`lib/tls_native_hs12.cyr` is
covered by `2026-06-18-tls-native-set-ca-system-agnos-sys-open-abi.md`.)
**Not here:** the agnosys + patra hazards from the same audit are filed in THEIR
repos (`agnosys/docs/development/issues/2026-06-18-agnos-cross-target-abi-slant.md`,
`patra/docs/development/issues/2026-06-18-agnos-cross-target-abi.md`) — they vendor
into `lib/` via `cyrius distlib`, so the fixes land upstream and re-vendor.

## fs.cyr — 5 sites (agnos-reachable: `agnoshi` + `owl` dep fs)
`dir_list` (82-129) and `is_dir` (144-160) are guarded `#ifndef CYRIUS_TARGET_WIN`
only — so they run on agnos with Linux assumptions:
- **line 8:** `var SYS_GETDENTS64 = 217;` — agnos has `SYS_GETDENTS`=29 (3-arg, no
  `basep`), not 217 (4-arg).
- **lines 85, 146:** `sys_open(str_data(path), O_RDONLY, 0)` — Linux ABI
  (2nd arg flags); agnos is `(name, namelen, flags)`.
- **lines 96, 155:** `syscall(SYS_GETDENTS64, fd, buf, 4096, basep)` — wrong number
  + arity on agnos.

Fix: add a `#ifdef CYRIUS_TARGET_AGNOS` branch to `dir_list`/`is_dir` using the
agnos getdents (3-arg) + the agnos `sys_open` ABI.

## Stdlib-wide structural fix (the real cure for the whole class)
This audit found 58 such sites across fs + tls + (vendored) agnosys + patra. The
pattern is always the same: a caller hand-rolls `sys_open(path, <linux-flags>, mode)`
which is wrong on agnos because agnos `sys_*` carry an explicit length and reorder
flags. `lib/io.cyr`'s `file_open` already bridges this correctly per-target. Two
asks to stop it recurring:

1. **Promote a length-carrying portable wrapper set** to the base syscalls layer —
   `xopen(path, flags)` / `xstat(path, buf)` / `xunlink(path)` / `xgetdents(fd, buf, n)`
   that do the `#ifdef CYRIUS_TARGET_AGNOS` ABI split once (compute `strlen`, map
   `O_*`→`AO_*`, dispatch the right syscall number). Callers in fs/tls/agnosys/patra
   then use these and never touch the raw ABI.
2. **A cyrlint rule** flagging `sys_open(<expr>, <int-literal>, …)`,
   `sys_stat(<expr>, <expr>)` (2-arg), and raw `syscall(SYS_GETDENTS64|SYS_LSEEK|
   SYS_FDATASYNC, …)` in any file that isn't `#ifdef`-guarded per target — so the
   next agnos-bound caller fails lint, not a QEMU boot.

## Why it matters
The base-OS libs are agnos-destined; Linux is the transitional bootstrap host.
agnos is the destination target, so cross-target ABI safety should be enforced by
the stdlib + lint, not discovered one failed syscall at a time.

## Verify
`agnos/scripts/whirl-smoke.sh` (QEMU + virtio-net + SLIRP) exercises the agnos FS +
TLS paths end-to-end — the harness that surfaced this audit.
