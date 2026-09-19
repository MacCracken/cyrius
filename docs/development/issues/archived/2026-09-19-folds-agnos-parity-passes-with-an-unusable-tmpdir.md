# `folds_agnos_parity.sh` PASSES "0/12 … (12 skipped)" when its temp dir cannot be created — FIXED

**Status:** ✅ FIXED in 6.6.6 (bite 13) — found during 6.6.6 bite 12 (gate-wide audit under a
missing `TMPDIR`); reproduced verbatim at HEAD before the fix.
**Placement:** unpinned — 6.x-line backlog (the next repair batch).
**Discovered:** 2026-09-19
**Severity:** Medium — a gate reads GREEN having checked nothing. It does not write the tree
(its writes go to `/…` and fail), so it is not bite 12's defect; it is the vacuous-pass half of the
same unchecked-`mktemp` shape bite 12 fixed in `lexid_buckets_by_content.sh`.
**Affects:** `tests/gates/platform/folds_agnos_parity.sh` at 6.6.5 / 6.6.6-dev.

## Reproduction

```sh
TMPDIR=/nonexistent sh tests/gates/platform/folds_agnos_parity.sh; echo rc=$?
```

Actual (tail):

```
    SKIP: yukti — not buildable in this harness on Linux either (see stderr); extend PREAMBLE to cover it
PASS: folds-agnos-parity — 0/12 folded stdlibs build for BOTH Linux and agnos (12 skipped)
rc=0
```

Expected: `FAIL: … mktemp -d failed (TMPDIR=/nonexistent)` and a non-zero exit — and, independently,
a run in which ZERO folds were checked must never be a PASS.

## Root cause

Line 28: `D=$(mktemp -d)` is unchecked, so `$D` is empty and every probe path becomes `/lin.cyr`,
`/ag.err`, …; each build then "fails on Linux" and is classified SKIP. Lines 107–113 print the SKIP
count honestly but still `exit 0` when `checked == 0`.

## Proposed fix

`D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: …"; exit 1; }` (the bite-12 idiom), and a floor on
`checked` — a normal run today checks 11 of 12 (`niyama` is skipped: `undefined variable 'NFD'`), so a
run that checks none must not be a PASS.

## Acceptance criteria

- `TMPDIR=/nonexistent` and a chmod-555 `TMPDIR` both FAIL with a message naming the temp dir.
- A run where every fold is skipped FAILs.
- Triage the rest of the family in the same change: bite 12's audit found 32 gates that exit 0 with
  a missing `TMPDIR`. Most are static source scans that legitimately need no temp dir; re-derive the
  list (`TMPDIR=/nonexistent sh <gate>` for each, keep the rc=0 ones) and check each for a vacuous pass.

## Resolution (6.6.6, bite 13c)

`D=$(mktemp -d) && [ -d "$D" ] || { echo FAIL…; exit 1; }`, and a floor of 10 on `checked` (a normal
run checks 11 of 12). `TMPDIR=/nonexistent` and a chmod-555 `TMPDIR` now FAIL naming the temp dir; a
scratch copy whose `build/cycc` always fails (every fold SKIPped) FAILs "only 0/12 folds were checked"
where the 6.6.5 gate PASSed. The acceptance item "triage the rest of the family" landed in bite 13f —
every gate's `mktemp` is now checked and `gates_never_write_tree.sh` forbids the unchecked shape; the
gates that still exit 0 under a missing `TMPDIR` were re-derived there (see the CHANGELOG).
