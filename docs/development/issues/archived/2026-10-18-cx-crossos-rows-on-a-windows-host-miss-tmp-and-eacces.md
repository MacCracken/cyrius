# On a Windows host's cxvm the crossos file-fixture rows fail: open_flags_per_target / atomic_write_temp_exclusive put their fixtures under `/tmp/` (cx is not `CYRIUS_TARGET_WIN`, and `C:\tmp` does not exist), and file_create_exclusive over a directory answers Windows' -13 to a guest whose lib only classifies it under `CYRIUS_TARGET_WIN` — RESOLVED

> ✅ **RESOLVED in v6.7.16** (PL-8, `9f31529e1` — the user's D28, 2026-10-19: "Named not-run on -38". The two files' `_scratch` is cwd-relative under `CYRIUS_TARGET_CX`, as on PE; a Windows host's cxvm answers an `O_CREAT | O_EXCL` open refused -13 over a name that exists -17 (no decision needed: Linux's answer, and `lib/io.cyr`'s native Windows rule); and a row whose call has no Windows route (readlink for `is_symlink` — the triage's third cause; getdents64, fork, wait4, mknodat for `audit_walk_fifo`) prints `not run: this host has no <call> route`. On real cass's cxvm: `pe_open_failure_errno` 10 passed, `open_flags_per_target` 41 + 3 not run, `atomic_write_temp_exclusive` 21 + 1 not run, `audit_walk_fifo` 2 + 6 not run, 0 failed (they read 9 / 1, 6 / 38, 2 / 20, 3 / 5); every other host's cxvm unchanged at 10 / 44 / 22 / 8. Rows: the new cx crossos leg in `scripts/cross-os-selfhost.sh` (all four hosts; the expected not-run count pinned per host), `cross_os_legs_cx_parity.sh` axis 3, the fixture's row 16 (-17 on every host). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on real cass (Windows 11, `C:\cyrius-tests`) with a PE cxvm built from
the 6.7.15 platform lane's tree (unit P4: the host dispatch and the path calls) by `build/cycc_win_cross`, each file
compiled once with `cycc_cx` and run from an empty directory under `C:\cyrius-tests`.
**Placement:** 6.7.16 — Break 2, repair 6 (platform lane, wave 1, unit P3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D28 — Named not-run on -38.
**Severity:** Low — no runner runs the crossos corpus on a Windows host's cxvm (the cross-OS legs run it natively;
tests/gates/codegen/cx_crossos_rows_run.sh runs these files on the x86_64 Linux cxvm, where all three pass). A cx
program with the same shapes fails the same way on Windows. No boundary is crossed.
**Found:** in passing, running the three crossos files the path-call fix makes pass on cx
(issues/archived/2026-10-16-cx-crossos-mkdir-symlink-rows-fail-and-no-gate-runs-them.md) on every host's cxvm: x86_64 Linux and
pi pass all three in full; ecb / ach fail only the -ELOOP rows (filed:
2026-10-18-cxvm-darwin-errnos-reach-the-guest-unmapped.md); cass fails as below.

## Reproduction

```sh
cat tests/tcyr/crossos/<file>.tcyr | build/cycc_cx > <file>.cyx      # Linux, once
# cass, from an empty dir under C:\cyrius-tests:   cxvm.exe < <file>.cyx
```

```text
pe_open_failure_errno        exit=1   9 passed, 1 failed (10 total)
  FAIL: file_create_exclusive(dir) is -17 (Windows' CreateFileW says ACCESS_DENIED) (got -13, expected -17)
open_flags_per_target        exit=38  6 passed, 38 failed (44 total)
  FAIL: create the target (got 0, expected 1)
  FAIL: xsymlink makes the fixture (on Windows: CreateSymbolicLinkW) (got -1, expected 0)
  … every fixture row -2 / -1 after it
atomic_write_temp_exclusive  exit=20  2 passed, 20 failed (22 total)
  FAIL: symlink fixture at the next temp name (got -1, expected 0)
  FAIL: file_write_atomic still succeeds (the next name is used) (got -2, expected 0)
  …
```

`if exist C:\tmp` on cass: no.

## Root cause

Two things a cx guest on a Windows host meets that its x86_64-Linux stdlib does not expect:
1. The two files' `_scratch()` chooses `"/tmp/<name>.<pid>"` under `#ifndef CYRIUS_TARGET_WIN` — a cx build is
   `CYRIUS_TARGET_CX`, so it takes the `/tmp/` arm, which Windows resolves on the current drive (`C:\tmp\…`), absent:
   every create answers -2 and every fixture row after it fails.
2. CREATE_NEW over an existing DIRECTORY fails ERROR_ACCESS_DENIED on Windows 11 (-13 through the PE errno table);
   lib/io.cyr's `file_create_exclusive` / `_io_tmp_taken` classify that -13 as -17 only under `CYRIUS_TARGET_WIN`
   (6.7.14), and a cx guest compiles the x86_64-Linux arm, so the -13 reaches the caller.

## Fix direction

(1) is the test files' (a scratch arm for cx that does not assume `/tmp`, e.g. the cwd-relative name the PE arm uses,
or `test_scratch`); (2) is cxvm's or the stdlib's call: classify a Windows host's -13 from an O_CREAT|O_EXCL open in
cxvm's open arm (the stdlib's own rule, applied where the host is known), or give lib/io.cyr a cx arm that asks the name
as the Windows arm does. Row: the three files on cass's cxvm `<N> passed, 0 failed` (a cx leg in
scripts/cross-os-selfhost.sh's cass job).
