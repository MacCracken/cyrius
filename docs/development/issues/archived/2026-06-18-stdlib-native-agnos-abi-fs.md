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
> **RESOLVED in v6.2.33 — structural asks closed + the descent-port consumer
> gaps fixed.** (1) The portable wrapper set is now COMPLETE: `xopen`/`xstat`/
> `xunlink`/`xgetdents` (v6.2.26) + **`xlseek`/`xflock` (v6.2.33)** in `lib/io.cyr`
> — `xlseek` is portable as-is (`SYS_LSEEK` is peer-carried on every target),
> `xflock` centralizes the per-target flock number (only the agnos peer carries
> `SYS_FLOCK`), and `programs/agnos_xsys_probe.cyr` exercises both under the
> `_agnos_xsys_gate`. (2) The cyrlint rule flags the genuinely non-portable
> patterns — raw `sys_open(<expr>,<int-literal>,…)` (ABI) + raw
> `syscall(…SYS_GETDENTS…)` (number/arity). **`SYS_LSEEK`/`SYS_FLOCK`/
> `SYS_GETRANDOM` are deliberately NOT flagged**: post-.32 they are peer-carried /
> wrapper-portable, so flagging them would false-positive on the now-correct
> patra code. (3) The descent-MUD-port consumer gaps were fixed at the source:
> **patra 1.12.2** (file.cyr flock/fdatasync agnos `#ifdef`; wal.cyr dropped the
> hardcoded Linux `SYS_GETRANDOM = 318`) and **sakshi 2.4.1** (precedence agnos
> syscall branch — `CYRIUS_ARCH_X86` is predefined even on agnos, so the Linux
> branch silently won; `_sk_open` agnos namelen+AO mapping; BSD socket/sendto
> guarded), both released + re-folded byte-identical. **sigil:** premise-checked
> out of scope (agnos build clean; its only `sys_access` is Linux-disk LUKS).
> The ~58 raw-`sys_open` sites the audit counted were the v6.2.26 premise-check
> finding (mostly vendored / Linux-only / already-fixed) — the substrate + lint
> are the preventative cure, not a migration.

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

## 2026-06-20 update — agnos `lseek`#58/`flock`#59 landed (kernel); descent surfaces the full persistence-chain gap

A second server-stage consumer hit this class hard. The **descent (MUD) port to agnos**
(`agnosticos/docs/development/planning/server-app-ports.md`) re-attempted
`cyrius build --agnos` and the M6 persistence/crypto chain (`libro → sigil → patra →
sakshi`) **fails at compile** with **~10 agnos-undefined syscall symbols** — a larger,
concrete instance of this issue's class (it dies at `lib/patra.cyr:113 undefined variable
'SYS_LSEEK'` before any descent src):

- `patra`  → `SYS_LSEEK`, `SYS_FLOCK`, `SYS_FDATASYNC`, `SYS_FUTEX`
- `sigil`  → `SYS_ACCESS`
- `sakshi` → `SYS_CLOCK_GETTIME`, `SYS_NANOSLEEP`, `SYS_OPENAT`, `SYS_SENDTO`, `SYS_SOCKET`

**Kernel half now DONE — unblocks the seek-based storage on agnos.** agnos gained
**`lseek`#58** + **`flock`#59** (agnos 1.46.x, 2026-06-20 — `kernel/core/syscall.cyr` +
`vfs.cyr`; `lseek(fd,offset,whence)` repositions the `VFS_EXT2_FILE` cursor; `flock(fd,op)`
is BSD advisory whole-file locking, inode-keyed, non-blocking + released on close#6/exit;
`FLOCK_SELFTEST` green). So the **cyrius stdlib half** is now actionable here:

1. **`lib/syscalls_x86_64_agnos.cyr`** — ✅ **DONE (2026-06-20)**: added `SYS_LSEEK = 58` /
   `SYS_FLOCK = 59` to `SysNrAgnos` + `fn sys_lseek(fd, off, whence)` / `fn sys_flock(fd, op)`
   wrappers (mirror the #45-57 band). This resolves patra's *referenced-but-undefined*
   `SYS_LSEEK` (patra dispatches the peer's `SYS_LSEEK` → agnos kernel #58, ABI-correct).
   (patra's *self-defined* `SYS_FLOCK = 73` / `SYS_FDATASYNC = 75` are Linux numbers — those
   are fixed in the **patra repo** below, not here.)
2. **Portable `xlseek`/`xflock`** in the wrapper set (ask #1 above) so patra/sakshi call them
   target-agnostically. The cyrlint rule (ask #2) **already names `SYS_LSEEK`/`SYS_FDATASYNC`**.

**The other 6 symbols** want agnos mappings/stubs in the agnos peer (or the portable
wrappers): `CLOCK_GETTIME`→`uptime_ms`#40/RTC; `NANOSLEEP`→`sleep_ms`#41; `OPENAT`→`open`#7
`(name,namelen,flags)`; `ACCESS`→stat#33 or stub; `SENDTO`/`SOCKET` (sakshi net-logging)→the
agnos `sock_*` band or no-op (network logging is plausibly Linux-only); `FDATASYNC`→`sync`#12
(whole-FS); `FUTEX`→no-op on single-core agnos.

**Consumer-repo fixes** (the per-lib agnos `#ifdef CYRIUS_TARGET_AGNOS` branches): per the
"filed in THEIR repos" note above, **patra** (`patra/docs/development/issues/2026-06-18-agnos-cross-target-abi.md`,
extend it with the lseek#58/flock#59/fdatasync/futex branches now that the kernel provides
them) + **new sigil + sakshi** issues, all of which vendor back via `cyrius distlib`. This
cyrius issue tracks the **stdlib-layer** half (the `syscalls_x86_64_agnos.cyr` constants +
wrappers + the portable set + the lint rule).

## Verify
`agnos/scripts/whirl-smoke.sh` (QEMU + virtio-net + SLIRP) exercises the agnos FS +
TLS paths end-to-end — the harness that surfaced this audit.
