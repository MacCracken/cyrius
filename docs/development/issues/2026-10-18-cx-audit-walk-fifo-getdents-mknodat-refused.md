# tests/tcyr/crossos/audit_walk_fifo.tcyr on cx ends `2 passed, 6 failed` on every host: getdents64 (217) and mknodat (259) answer -38 on cxvm (6.7.14's D55 — untranslated pointer calls), so a directory walk sees no entries and the FIFO fixture is never made; no gate runs the file on cx — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 platform lane (branch l6715-platform, unit P4), the file
compiled once with `cycc_cx` and run on cxvm built from the lane's tree on x86_64 Linux, aarch64 (qemu and real pi),
ecb and ach.
**Placement:** unplaced — filed from the 6.7.15 platform lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — a crossos row that "passes on every target" fails on cx unseen (the same class as
issues/2026-10-16-cx-crossos-mkdir-symlink-rows-fail-and-no-gate-runs-them.md, which covers three other files). cxvm
runs trusted bytecode; no boundary.
**Found:** the P4 unit's brief asks that audit_walk_fifo.tcyr on cx no longer exit mid-file on pi / ecb (the fork
row of issues/2026-10-17-cxvm-forwards-guest-x86-numbers-through-host-renumbering.md). It no longer does: it reaches
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
