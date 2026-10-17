# patra's suite opens `/dev/null` for its failed-sync rows: on Windows the open fails and two rows fail — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.13 stdlib lane (unit L1) while running patra 1.16.3's suite on real
cass for issues/archived/2026-10-15-xflock-windows-relock-drops-the-lock-first.md (suite built by the lane's tree,
l6713-stdlib from f59668ad, against the vendored `lib/patra.cyr` = patra's `dist/patra.cyr` at 1.16.3). The same two
rows fail with the 6.7.12 lib and with the 6.7.13 one; Linux passes them.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane, wave 2, unit L4; placed at the 6.7.14 open, 2026-10-16; a fold patch: patra 1.16.4, its own `tests/tcyr/patra.tcyr` — ⛔ the user tags it before the refold) — never 7.x.
**Severity:** Low — a test-fixture portability defect of a folded stdlib's suite: no shipped code is wrong, but the
suite cannot be read green on Windows, so a real Windows regression in the same run is easier to miss.

## Reproduction

patra 1.16.3's `tests/tcyr/patra.tcyr` (its `"/tmp/` paths made relative, since cass has no `C:\tmp`), compiled with
`CYRIUS_TARGET_WIN` against the lane's `lib/`, run under `C:\cyrius-tests` on cass:

```
=== a failed fdatasync is reported, not taken for durability (1.16.2) ===
  FAIL: open /dev/null
  FAIL: jsonl_append: an fd with nothing to sync is fine (got 1, expected 0)
```

## Root cause

`test_failed_sync_reported` opens `"/dev/null"` for "an fd that takes a seek and a write but refuses fdatasync with
EINVAL". On Windows that is the drive-rooted path `\dev\null`, which does not exist, so `file_open` fails and the rows
that use the fd fail (the others pass by accident on a negative fd). The suite's other `"/tmp/..."` paths have the
same Linux-only shape (every database the suite opens fails on cass unless `C:\tmp` exists).

## Fix

In patra's suite: a `CYRIUS_TARGET_WIN` arm for the nothing-to-sync fd (the `NUL` device, if `xfsync` on it answers
the "nothing to sync" error the row means — measure on cass — or the row skipped on Windows with its premise
asserted), and the `/tmp/` fixture paths through a per-target scratch helper. Then the suite on cass reads
0 failed apart from filed defects.
