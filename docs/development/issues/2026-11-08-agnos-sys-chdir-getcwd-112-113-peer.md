# `lib/syscalls_x86_64_agnos.cyr` has no `chdir`#112 / `getcwd`#113 peer — `sys_chdir` returns -38 — OPEN

**Status:** 🟡 **OPEN** — filed by agnos (2026-11-08). agnos has assigned and built both numbers in its **1.57.18** cut,
where they are reviewed and gated (`scripts/smoke/cwd-smoke.sh`). Do not mint them here before agnos's `1.57.18` tag.
**Placement:** `lib/syscalls_x86_64_agnos.cyr`: `SYS_CHDIR = 112;` and `SYS_GETCWD = 113;` after `SYS_FD_KIND = 111`;
the wrappers replace the explicit `fn sys_chdir(path): i64 { return 0 - 38; }` stub (CHANGELOG [6.5.7]) and sit beside it.
**Filed:** 2026-11-08, by agnos. agnos minted and built the numbers; cyrius owns the peer.
**Affects:** cyrius **6.7.18**. `#112` / `#113` exist from agnos **1.57.18**.
**Severity:** **Low as a defect, the last step of a security fix for the consumers.** agnos 1.57.18 resolves every
relative path from a per-process working directory (agnos issue `2026-11-06-a-relative-path-has-no-working-directory`,
filed from thoth 0.55.1, whose "relative, no `..`" jail read `/etc/secret.txt` for `etc/secret.txt`). A cyrius program
can now rely on that, but cannot `chdir` or ask where it is without a raw `syscall(112/113, …)`: the stdlib's
`sys_chdir` still answers -38 on agnos, and there is no `sys_getcwd` there at all.

## The ask

```
SYS_CHDIR  = 112;   # chdir(path, pathlen) → 0 / -1 (agnos 1.57.18): the caller's working directory
SYS_GETCWD = 113;   # getcwd(buf, cap) → length (NUL not counted) / -1 (agnos 1.57.18)

# Change the working directory. agnos takes (ptr, len), not a C string: pass strlen(path).
fn sys_chdir(path): i64 { return syscall(SYS_CHDIR, path, strlen(path), 0, 0); }
# Write the working directory and a NUL into buf. agnos returns the LENGTH WITHOUT the NUL (Linux's raw syscall counts
# it); cap < length + 1 is -1 with nothing written.
fn sys_getcwd(buf, cap): i64 { return syscall(SYS_GETCWD, buf, cap, 0, 0); }
```

(`strlen` is whatever the peer file already uses for its other C-string wrappers — `sys_open`'s agnos arm does the same
conversion. Pass a3/a4 as explicit zeros: a 3-argument `syscall` leaves a stale r10, the agnos `#100` rule.)

## The contract (agnos `docs/development/agnos-userland-abi.md` § 3.2, rows 112–113 — authoritative)

**`chdir`#112(path, pathlen) → 0 / -1.** The cwd becomes the CLEANED absolute form of `path` (a relative one is joined
to the current cwd first) when that names an existing **directory** — on ext2, ZFS (`/mnt/zfs`), FAT (`/mnt/fat`),
exFAT; a mount root counts. Cleaning is lexical: empty components and `.` vanish, `..` removes the component before
it and never climbs above `/` (`..` from `/mnt/zfs` is `/mnt`), no trailing `/`. A final symlink to a directory is
followed for the check and the LINK's path is kept (a shell's logical `cd`). **-1 with the cwd unchanged:** a bad
range, `pathlen < 1`, a NUL byte in `path`, an input or result over **4095** bytes, a missing path, a non-directory.

**`getcwd`#113(buf, cap) → L / -1.** Copies the cwd and a NUL into `buf`; returns its length L, the NUL **not**
counted. `cap < L + 1` is -1 with **nothing written** (Linux `ERANGE`; never a cut name). A cwd is ≤ 4095 bytes, so
`cap = 4096` always suffices.

**Every process has one:** the first process and kernel threads start at `/`; a child inherits its creator's
(`spawn`#3, `spawn_path`#43, `execwait`#37, `fork`#96); a `#43` / `#37` child is seeded from a valid `PWD=` in the env
it is given (absolute, an existing directory; an invalid one is ignored). **Every relative path any syscall takes
resolves from it**, the program path of `#43` / `#37` included (as `execve` does — no `PATH` search).

**Probe:** `getcwd`#113 with a 4096-byte buffer answers ≥ 1 on agnos ≥ 1.57.18 and -1 (the dispatcher's default)
before — so a portable `sys_getcwd` may answer -38 on -1 if a caller needs to tell "unsupported" apart, and a
consumer that resolves its own paths against `$PWD` (thoth's `fs_path`) can drop that layer when the probe succeeds.

## Self-proving repro (once the peer lands)

```
var b[512];
if (sys_chdir("/etc") != 0) { exit(1); }               # 0 on 1.57.18 (-38 today)
var n = sys_getcwd(&b, 4096);
if (n != 4) { exit(2); }                                # "/etc", NUL at b[4]
if (sys_getcwd(&b, 4) != 0 - 1) { exit(3); }            # cap < L + 1: -1, nothing written
var fd = syscall(7, "hostname", 8, 0, 0);              # open#7, relative: /etc/hostname, not /hostname
if (sys_chdir("/etc/hostname") != 0 - 1) { exit(4); }   # a file: refused, cwd unchanged
exit(0);
```

`agnos_peer_fake_kernel.sh`-style rows: `SYS_CHDIR == 112`, `SYS_GETCWD == 113`, `sys_chdir` passes `strlen(path)` as
a2 and zeros as a3/a4, `sys_getcwd` passes `(buf, cap, 0, 0)`; `agnos_abi_doc_parity` 112 / 113 shared.

## Compatibility

`sys_chdir` changes from an unconditional -38 to the real call: a consumer that treated -38 as "agnos has no cwd" and
fell back to tracking `$PWD` keeps working (the kernel's cwd and a `$PWD` it was seeded from agree); one that now
`chdir`s gets the kernel's resolution for every later relative path. Nothing else changes.

## Related

- agnos `docs/development/agnos-userland-abi.md` § 3.2 rows 112–113 and the paragraph after the table (it reverses the
  "CWD is userland-owned" rule); `docs/architecture/working-directory.md` there for the design.
- `2026-11-03-stdlib-has-no-symlinkat-readlinkat-getcwd-fchmodat2.md` — the Linux-side `getcwd` wrapper gap; the agnos
  `sys_getcwd` here should share its name and argument order.
- The agnos syscall ABI gate (`scripts/check/syscall-abi-check.sh`) is RED BY DESIGN from agnos 1.57.18 — #112 and
  #113 are kernel and ABI-doc numbers with no `SYS_*` here — until this peer lands and agnos re-pins.
