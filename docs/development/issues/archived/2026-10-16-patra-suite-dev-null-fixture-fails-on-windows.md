# patra's suite opens `/dev/null` for its failed-sync rows: on Windows the open fails and two rows fail — RESOLVED

> ✅ **RESOLVED in v6.7.14** (LIB-10: patra 1.16.4 (`bbded00`, the user's tag), refolded into `lib/patra.cyr` at the integration. No decision was needed; the change is tests only. patra's `tests/tcyr/patra.tcyr` routes its 18 `"/tmp/<name>"` fixtures through `_scr`: the literal on Linux, macOS and agnos, and the relative `<name>` on Windows. `test_failed_sync_reported` opens `NUL` on Windows. The `patra_hdr_write` and `_sync_fail` rows run there; the "nothing to sync is fine" row is replaced by its premise (`xfsync(NUL) < 0`) and a named SKIP. There is no Windows exemption in patra's `src/file.cyr`. On real cass the suite, built against 6.7.14's lib/ (with 6.7.13's xflock re-lock fix and 6.7.14's PE seek fix), reads 1,565 / 1,565, exit 0. 1.16.3's stopped with `0xC0000005` at its first open. Linux x86_64 and aarch64 read 1,645 / 1,645, unchanged. patra's isolated CI: 18 / 18. `lib/patra.cyr` differs from the 1.16.3 fold only in its version line. Filed for 6.7.15, outside this file: patra's other harnesses' `/tmp` paths on Windows, and the macOS `/dev/null` failed-sync row (ecb / ach 1,566 / 1,567, the same with 1.16.3). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — found 2026-10-16 by the 6.7.13 stdlib lane (unit L1) while running patra 1.16.3's suite on real
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
