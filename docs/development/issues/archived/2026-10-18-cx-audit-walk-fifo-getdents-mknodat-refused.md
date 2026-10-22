# tests/tcyr/crossos/audit_walk_fifo.tcyr on cx ends `2 passed, 6 failed` on every host: getdents64 (217) and mknodat (259) answer -38 on cxvm (6.7.14's D55 — untranslated pointer calls), so a directory walk sees no entries and the FIFO fixture is never made; no gate runs the file on cx — RESOLVED

> ✅ **RESOLVED in v6.7.16** (PL-7, `26e8eeaff`, and the review fix PL-7r, `2b89c707d` — no decision needed: 6.7.14's D55, one call at a time. cxvm translates and serves getdents64, mknodat and wait4 on every POSIX host (Windows -38, no route) and `poll(NULL, 0, ms)` as a sleep; lib/chrono.cyr's `sleep_ms` gets a cx arm (it was a no-op — the triage's two causes beside the filing's); a Darwin host converts getdirentries64's records to linux_dirent64 (the lseek cookie put back and re-read; PL-7r hands the guest exactly the re-read's records, so a devfs listing with a buffer under 1048 bytes may end early with -EINVAL, never repeats), maps wait4's status word and WCONTINUED, and makes the FIFO through the lib's new macOS `sys_mknodat` arm (Darwin mknod, a Mach-O row 133 → 14 on both backends). `audit_walk_fifo.tcyr` reads `8 passed, 0 failed` on the x86_64, qemu-aarch64, pi, ecb and ach cxvm (it read 2 / 6), and `2 passed, 0 failed` + 6 named not-run rows on cass's cxvm (6.7.16's D28, PL-8). Rows: `cx_crossos_rows_run.sh` R26 (the runner the filing asked for, native and cxvm, floor 8), `cx_host_dispatch.sh` axis 4 and the fixture's rows 15 and 17, `cx_guest_syscall_refusal.sh` R9 / R10, the macOS group of `ns_rootfs_syscalls.tcyr`; mutants in each gate's ledger, MU14 for PL-7r. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 platform lane (branch l6715-platform, unit P4), the file
compiled once with `cycc_cx` and run on cxvm built from the lane's tree on x86_64 Linux, aarch64 (qemu and real pi),
ecb and ach.
**Placement:** 6.7.16 — Break 2, repair 6 (platform lane, wave 1, unit P3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a crossos row that "passes on every target" fails on cx unseen (the same class as
issues/archived/2026-10-16-cx-crossos-mkdir-symlink-rows-fail-and-no-gate-runs-them.md, which covers three other files). cxvm
runs trusted bytecode; no boundary.
**Found:** the P4 unit's brief asks that audit_walk_fifo.tcyr on cx no longer exit mid-file on pi / ecb (the fork
row of issues/archived/2026-10-17-cxvm-forwards-guest-x86-numbers-through-host-renumbering.md). It no longer does: it reaches
its summary on every host. Its remaining failures are the two refused calls below, outside both P4 issues' filed
surface (mkdir / rmdir / unlink / rename / symlink / readlink / stat and the scalar list).

## Reproduction

```sh
cat tests/tcyr/crossos/audit_walk_fifo.tcyr | build/cycc_cx > aw.cyx
mkdir w && cd w && ../build/cxvm < ../aw.cyx; echo "exit=$?"
```

```text
  FAIL: audit_fmt_walk over a directory holding no source file: no error (got 1, expected 0)
  FAIL: fmt and lint walkers over a file: one error each, its note 'error 20' (got -1, expected 0)
  FAIL: premise: a FIFO was made (mknodat on Linux, /usr/bin/mkfifo on macOS) (got -38, expected 0)
  FAIL: the walkers RETURN on a FIFO (with O_RDONLY alone open(2) blocked until the 5 s kill)
  FAIL: fmt and lint walkers over the FIFO: one error each, its note 'error 20' (got -1, expected 0)
  FAIL: the FIFO unlinks (got -2, expected 0)

2 passed, 6 failed (8 total)
exit=6
```

The same on the aarch64 cxvm under qemu and on pi, ecb and ach (on cass `3 passed, 5 failed`). Before the P4 fixes:
`0 passed, 8 failed` on x86_64 Linux (mkdir -38), and on pi / ecb an exit 10 mid-file (fork ran close).

## Root cause

cxvm (programs/cxvm.cyr op 0x70) answers every number it neither translates nor serves -ENOSYS without reaching the
host (6.7.14's D55): getdents64(fd, buf, n) takes a guest buffer, mknodat(dirfd, path, mode, dev) a guest path. So
`xgetdents` reads no entries (the directory walk reports an error) and the FIFO premise fails. D55 says translation is
added one call at a time when a cx program needs it; this crossos file is such a program.

## Fix direction

Translate getdents64's buffer (`_cx_sysbuf(buf, n)`, served through the host's `xgetdents`-equivalent — Darwin's
getdirentries record layout differs from Linux's dirent64, as stat's does) and mknodat's path (the macOS arm of the
test makes its FIFO with /usr/bin/mkfifo, an exec cx does not have). And a runner: add the file to
cx_crossos_rows_run.sh with its cx count.
