# crossos `.tcyr` rows that mkdir or symlink fail on cxvm (`xmkdir` / `xsymlink` reach the host with an untranslated guest path), and no gate runs the crossos corpus on cx — pe_open_failure_errno.tcyr's directory group joins open_flags_per_target / atomic_write_temp_exclusive there — RESOLVED

> ✅ **RESOLVED in v6.7.15** (PL-12, `caa8673d1` + `e7e1c197f` — no decision needed (6.7.14's D55: translation is added one call at a time when a cx program needs it, and `file_write_atomic` is one). cxvm translates the path calls' paths and buffers (-EFAULT without reaching the host when one leaves the guest) and serves mkdir, rmdir, unlink, rename, symlink, readlink and stat through the host's wrappers; a guest `struct stat` is x86_64 Linux's on every host (off x86_64 Linux seven fields are filled from the host's struct, the rest 0); Windows has no readlink / stat route (-38). `sys_unlink`'s 6.7.12 cx arm is removed. The filed repro on the x86_64 cxvm: `pe_open_failure_errno` 8 / 10 → 10 / 10, `open_flags_per_target` 25 / 44 → 44 / 44, `atomic_write_temp_exclusive` 6 / 22 → 22 / 22 (the same on the aarch64 cxvm under qemu and on real pi), and `file_write_atomic("wa_target.txt", "hello", 5)` answers 0 and leaves no `.cyrtmp.` name (it answered -38 and left one). Rows: `cx_crossos_rows_run.sh` R22 – R24 (the three files, native and cxvm each `<N> passed, 0 failed`, N from `n_tgt`, floors 10 / 44 / 22) and R25 (the filed write) — the runner the filing asked for, 66 → 74 rows; `cx_guest_syscall_refusal.sh` R7 / R8 (the calls served at the x86 offsets; a pointer outside the guest -14); the fixture's path row on every host's cxvm. Mutations each RED: the previous cxvm (R22 – R25), the `sys_unlink` cx arm restored (R7), `_cx_host_stat` without its st_mode store. ⚠ On other hosts' cxvm the files still fail rows, each filed (6.7.16): ecb / ach 38 / 44 (Darwin's -62 ELOOP reaches the guest), cass 9 / 10, 6 / 44, 2 / 22 (`/tmp` fixtures, CREATE_NEW-over-a-directory -13); and the runner runs on the x86_64 cxvm only. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 platform lane's tree (l6714-platform): each file compiled
with the lane's `build/cycc_cx` and run through the lane's `build/cxvm` (bytecode on stdin, in a scratch cwd). The two
older files fail the same way at the lane base (2600f67f, its own cycc_cx / cxvm): open_flags_per_target 25 / 44,
atomic_write_temp_exclusive 6 / 18 — the lane adds new failing rows (pe_open_failure_errno's 2; atomic's 4 new rows,
6 / 22), it did not cause the class. Filed from the platform lane's review.
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
⚠ Integration: first confirm whether the stdlib lane's unit L3 (issues/archived/2026-10-15-cx-untranslated-pointer-wrappers-can-reach-cxvm-image.md,
D55 — cxvm answers -38) covers these wrappers; D55 changes the answer from -14 to -38, it does not make the rows pass,
so the rows still need named cx arms (or cxvm translates the path) either way.
**Severity:** Low — no runner reports it: `tcyr_corpus_cross_compiles.sh` only COMPILES the corpus for cx, and
`cx_crossos_rows_run.sh` runs a fixed list of files (none of these three). cxvm runs trusted bytecode (not a sandbox),
so no boundary is crossed; the defect is that a crossos row "passes on every target" while 37 of its assertions fail
on cx, unseen.
**Affects:** tests/tcyr/crossos/pe_open_failure_errno.tcyr, open_flags_per_target.tcyr, atomic_write_temp_exclusive.tcyr
on `CYRIUS_TARGET_CX`; programs/cxvm.cyr op 0x70 (only read / write / open / getrandom / clock_gettime translate a
guest pointer); lib/io.cyr `xmkdir` / `xsymlink` / `file_write_atomic`'s fixture paths.

## Reproduction

```sh
cd <tree>
cat src/main_cx.cyr | build/cycc > build/cycc_cx; cat programs/cxvm.cyr | build/cycc > build/cxvm; chmod +x build/cycc_cx build/cxvm
mkdir -p /scratch/cx
for t in pe_open_failure_errno open_flags_per_target atomic_write_temp_exclusive; do
  cat tests/tcyr/crossos/$t.tcyr | build/cycc_cx > /scratch/cx/$t.cyx
  (cd /scratch/cx && build/cxvm < $t.cyx; echo "exit=$?")
done
```

```text
pe_open_failure_errno        exit=2    8 passed, 2 failed (10 total)
  FAIL: the directory fixture (got -14, expected 0)
  FAIL: file_create_exclusive(dir) is -17 (Windows' CreateFileW says ACCESS_DENIED) (got 3, expected -17)
open_flags_per_target        exit=19   25 passed, 19 failed (44 total)
  FAIL: xsymlink makes the fixture (on Windows: CreateSymbolicLinkW) (got -14, expected 0)
  FAIL: a DANGLING symlink fixture (got -14, expected 0)
  FAIL: make the directory fixture (got -14, expected 0)
  FAIL: a symlink to the directory (got -14, expected 0)
  … and 15 rows that depend on those fixtures (is_symlink, -ELOOP, -EISDIR, -ENOTDIR, O_DIRECTORY opens)
atomic_write_temp_exclusive  exit=16   6 passed, 16 failed (22 total)
  FAIL: symlink fixture at the next temp name (got -14, expected 0)
  FAIL: file_write_atomic still succeeds (the next name is used) (got -14, expected 0)
  FAIL: directory fixture at the next temp name (got -14, expected 0)
  FAIL: 63 taken names in a row: the 64th is used (got -14, expected 0)
  … and the rows that depend on them
```

At the lane base (2600f67f): open_flags_per_target `25 passed, 19 failed (44 total)`, exit 19;
atomic_write_temp_exclusive `6 passed, 12 failed (18 total)`, exit 12.

## Root cause

cxvm's syscall opcode (programs/cxvm.cyr, op 112 / 0x70) translates a guest pointer to a host address only for read,
write, open, getrandom and clock_gettime; mkdir (83), symlink (88) and the others reach the host with the raw guest
offset, which the host kernel answers -EFAULT (-14). So every fixture these files build with `xmkdir` / `xsymlink`
fails on cx, and every row that leans on the fixture fails after it. The same class sits inside the stdlib:
a plain `file_write_atomic("wa_target.txt", "hello", 5)` (no fixture) prints `-14` on cxvm (exit 242) and leaves its
temp file `wa_target.txt.cyrtmp.<pid>.1` behind — its rename (and the cleanup unlink after it) reach the host
untranslated. Nothing reports it: the crossos corpus is run on the
four hardware hosts, and on cx only through cx_crossos_rows_run.sh's fixed list.

## What a fix needs

Either translate the path argument of the path-taking numbers in cxvm (as `_cx_syspath` does for open), or give each of
these files a named `#ifdef CYRIUS_TARGET_CX` arm that still asserts what cx answers (the -38 of D55 once the stdlib
lane lands it) — the pattern the corpus uses for its PE-inapplicable rows. Then a runner: cx_crossos_rows_run.sh gains
the three files (native and cxvm each print `<N> passed, 0 failed`, N derived from the source), or the corpus gets a cx
run with a floor, so the next such row cannot pass "everywhere" unseen.
