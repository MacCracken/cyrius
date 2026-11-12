# `lib/syscalls_x86_64_agnos.cyr` has no `fsync`#115 peer, and `sys_open` / `file_open` drop the create mode

**Status:** 🟡 **OPEN** — filed by agnos (2026-11-08). agnos assigned and built `#115` and the `AO_MODE` open flag in its
1.57.18 cut, where they are reviewed and gated. Do not mint them here before agnos's `1.57.18` tag.
**Placement:** `lib/syscalls_x86_64_agnos.cyr` — `SYS_FSYNC = 115` after `SYS_FD_KIND = 111` (:99); `AO_MODE` and
`AO_MODE_SHIFT` beside `AO_EXCL` in the `AgnosOpenFlag` enum (:494); `sys_fsync` / `sys_fdatasync` (:835-837) onto #115;
a mode-carrying `sys_open_mode` beside `sys_open` (:1054). `lib/io.cyr` — `file_open(path, flags, mode)` (:96) passes the
mode on agnos; `xfsync(fd)` (:359) calls `sys_fsync(fd)`.
**Filed:** 2026-11-08, by agnos. agnos minted and built both; cyrius owns the peer.
**Affects:** cyrius **6.7.18**. Both exist from agnos **1.57.18**.
**Severity:** **Low as a defect, blocking for the consumers.** agnos issue `2026-11-06-open-has-no-create-mode` (filed from
thoth 0.55.1): thoth writes its tool pins, session store and session log at 0600 on Linux and macOS, and hoosh and daimon
keep credentials and stores the same way — on agnos all of them land at the kernel's default (0644). Its "Related" half:
`sys_fsync(fd)` here is `sync`#12, the WHOLE system, so every atomic store write (write a temp, fsync, rename) pays for
every other file's pending ZFS writes too.

## The ask

```
# SysNrAgnos
SYS_FSYNC = 115;                 # fsync(fd) → 0 / -1 (agnos 1.57.18): ONE file's data made durable

# AgnosOpenFlag (beside AO_EXCL = 0x2000)
AO_MODE       = 0x4000;          # bits 32..63 of the flags are a CREATE's mode, 0..07777 (agnos 1.57.18)
AO_MODE_SHIFT = 32;

fn sys_fsync(fd): i64 { return syscall(SYS_FSYNC, fd); }
fn sys_fdatasync(fd): i64 { return syscall(SYS_FSYNC, fd); }
# open with a create mode: the kernel stores `mode` (0..07777) as given when the call creates; no umask on agnos
fn sys_open_mode(name, namelen, flags, mode): i64 {
    if (mode < 0 || mode > 0xFFF) { return 0 - 1; }       # the kernel's own answer for a field above 07777
    return syscall(SYS_OPEN, name, namelen, flags | AO_MODE | (mode << AO_MODE_SHIFT));
}
```

and in `lib/io.cyr`:

```
fn file_open(path: cstring, flags, mode): i64 {
    ...                                                   # the existing O_* -> AO_* mapping, unchanged
    if ((flags & 64) != 0) { return sys_open_mode(path, namelen, ao, mode); }   # O_CREAT: the mode reaches the create
    return sys_open(path, namelen, ao);
}
fn xfsync(fd): i64 { return sys_fsync(fd); }             # agnos: per-file since 1.57.18 (was sys_sync, the residual)
```

`file_open`'s callers that pass a mode (`0x1A4` at :732, `_io_tmp_mode` in the atomic write) then get it; one that wants
POSIX's `mode & ~umask` applies its own umask first — **agnos has none**.

## The contract (agnos `docs/development/agnos-userland-abi.md` — § 3.3 `AO_MODE`, the `#115` row, § 3.6 — authoritative)

### `open`#7 — `AO_MODE` (`0x4000`)

- `a3 = flags | AO_MODE | (mode << 32)`, `mode` **0..07777**: owner / group / other rwx plus `S_ISUID` 04000, `S_ISGID`
  02000, `S_ISVTX` 01000, **stored exactly as given** (no umask; every agnos process is uid 0, which Linux and FreeBSD
  let keep `S_ISGID`; `S_ISVTX` on a file is kept, as Linux keeps it).
- **The mode applies only when the call CREATES.** An existing file keeps its mode (POSIX `open`).
- **With `AO_MODE` set, a field above 07777 is -1 and nothing is created** (any of bits 44..63) — openat2's `EINVAL`, not
  `open(2)`'s silent mask. So `sys_open_mode` refuses a bigger value itself rather than masking it into a different mode.
  (`file_open(path, flags, mode)` callers pass POSIX modes, all within 07777.)
- **Without `AO_MODE` nothing changes:** bits 32..63 are ignored and a create gets the backend's default (ext2 `0644`,
  ZFS `0100644`). No shipped caller changes.
- Backends: ext2 (the inode's mode), ZFS (the SA `MODE` and the trivial NFSv4 ACL derived from it). **FAT / exFAT keep no
  permission bits: the mode is checked, then ignored** (Linux vfat does the same — the mount's `fmask` rules there).
- ⚠ **A pre-1.57.18 kernel ignores the bit AND the field** and creates `0644`. A consumer that must not CLAIM a mode it
  did not get (thoth's rule) probes once: create a scratch file with `sys_open_mode(..., 0600)`, `sys_stat`, compare
  `st_mode & 07777`. A helper here (`agnos_open_mode_ok()`, cached) would save every consumer that probe.

### `fsync`#115

`fsync(fd)` → **0 / -1**. What ONE file holds is made durable, and nothing else (Linux / FreeBSD `fsync(2)`):

- **ext2**: write-through (every `write`#1 is on the device when it returns), so it is the device FLUSH — no sector written.
- **ZFS** (agnos holds at most ONE pending transaction group, of ONE file): an fd of that file **commits** it (durable on
  return); any other ZFS fd **commits nothing** — another file's pending writes stay pending (OpenZFS `zfs_fsync` →
  `zil_commit(zilog, foid)`).
- **FAT / exFAT write-back fd**: its buffered content written now (the fd stays open), then the device flush.
- **A read-only fd syncs its file too** (POSIX; Linux and FreeBSD fsync an `O_RDONLY` fd — on ZFS it commits writes
  another fd of the same file left). **A directory fd** (`AO_DIRECTORY`): 0. **A memory file** (initrd, a FAT read fd,
  `/fonts`): 0.
- **-1** for the console, a pipe, a socket, a channel, a signalfd / epoll / timerfd, a closed fd, `fd < 0` or `>= 32`
  (Linux `EINVAL` / `EBADF`); for a failed flush or commit; for a ZFS fd whose file is gone; once for a ZFS file whose
  pending commit failed earlier (POSIX's deferred `EIO`).
- `sync`#12 is unchanged: the whole-system barrier. It takes no argument, so it could not carry an fd.
- **Probe:** `#115` on an open regular-file fd answers 0 from 1.57.18; an older kernel answers -1 (unknown number). A
  peer that wants to keep working on an old kernel can fall back to `sync`#12 on -1 **for a file fd only** (not for a
  pipe or console, where -1 is the answer).

## Self-proving repro (agnos side, cyrius fake kernel side)

```
var fd = sys_open_mode("/t.txt", 6, 0x2101, 0x180);      # AO_WRONLY|AO_CREAT|AO_EXCL, 0600
var st[6];
sys_stat("/t.txt", 6, &st);
assert((load64(&st) & 0xFFF) == 0x180);                   # 0600 — 0644 (0x1A4) on agnos < 1.57.18 or on today's peer
sys_write(fd, "x", 1);
assert(sys_fsync(fd) == 0);                               # #115 — today's peer issues sync#12 (the whole system)
assert(sys_fsync(1) == 0 - 1);                            # the console: -1 — today's sync#12 answers 0
assert(sys_open_mode("/u.txt", 6, 0x2101, 0x1000) == 0 - 1);   # 010000: refused, and /u.txt not created
assert(sys_stat("/u.txt", 6, &st) == 0 - 1);
```

agnos's own gates: `scripts/smoke/fs-create-mode-smoke.sh` (ring 3 on ext2, debugfs after a crash cut),
`scripts/smoke/fssys-smoke.sh` (in-kernel: one flush, no sector), `scripts/harness/zfs-ring3-test.py` (ZFS: OpenZFS's own
`stat(1)` and `getfacl` of the created files; an fsync'd file kept and a pending one lost across a kill).

## Compatibility

Additive: new constants and one function; `sys_fsync` / `sys_fdatasync` / `xfsync` change from `sync`#12 to `#115` (a
strictly smaller durability scope for the same fd, the POSIX one); `file_open` with `O_CREAT` starts passing the mode the
caller already gives it.

## Related

- agnos `docs/development/agnos-userland-abi.md` § 3.3 (`AO_MODE`), the `#115` row, § 3.6 (ZFS) — the authoritative
  contract.
- agnos issue `docs/development/issues/2026-11-06-open-has-no-create-mode.md` — the consumer's filing.
- `archived/2026-10-13-agnos-sys-fd-kind-111-peer.md` — the previous number agnos added (`#112`–`#114` are other 1.57.18
  tracks' numbers).
