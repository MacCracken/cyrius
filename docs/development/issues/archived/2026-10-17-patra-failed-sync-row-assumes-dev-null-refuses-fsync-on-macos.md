# patra's suite on macOS: `patra_hdr_write: a refused sync is an error` fails — macOS syncs `/dev/null` successfully — RESOLVED

> ✅ **RESOLVED in v6.7.15** (PL-15, patra `539d802` (released in patra's `e36f202`; refolded at the integration after the user's 1.16.5 tag) — no decision needed (the fix plan's; tests only). On macOS `test_failed_sync_reported` asserts the premise (`_pt_fdatasync` of `/dev/null` answers 0 — macOS syncs it) and runs the bare `patra_hdr_write` row through the sync seam (`_sync_fail(nul, 0)`, expect `PATRA_ERR_IO`, then `_sync_ok()`); Linux, Windows and agnos keep the bare row. A pipe was not used: its seek fails first, so the row would pass for the wrong reason. The filed repro on ecb (arm64) and ach (x86_64): `1566 passed, 1 failed (1567 total)` → `1568 passed, 0 failed (1568 total)`, exit 0 (+1 the premise row); Linux x86_64 and aarch64 (qemu) 1,645 / 1,645 and cass 1,565 / 1,565 unchanged. Mutation: the 1.16.4 suite on the same hosts → 1 failed. patra's CI isolated (`sibci.sh`): fail=0 at `539d802` and `e36f202`. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on real ecb (macOS arm64) and ach (Intel macOS) by the 6.7.14 stdlib lane
(unit L4), with patra 1.16.3's suite and with the 1.16.4 suite (identical result: the 1.16.4 patch changes nothing on
macOS).
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P6; placed at the 6.7.15 open, 2026-10-18) — never 7.x. A
fold patch, patra 1.16.5 (the user tags it before the refold).
**Severity:** Low — test-fixture portability of a folded stdlib's suite: one row fails on macOS for a premise that is
Linux's, so the macOS run cannot be read green. (patra's roadmap lists macOS as "not run".)

## Reproduction

patra's `tests/tcyr/patra.tcyr` (1.16.3 at b8722b7, and the 1.16.4 commit), built from a scratch copy whose `lib/` is
the cyrius 6.7.14 lane tree's: `CYRIUS_MACHO=1 build/cycc` for ach, `CYRIUS_MACHO_ARM=1 build/cycc_aarch64`
(codesigned ad hoc) for ecb; run in a scratch directory on each host:

```
ach exit=1 1566 passed, 1 failed (1567 total)
  FAIL: patra_hdr_write: a refused sync is an error (got 0, expected 1)
ecb exit=1 1566 passed, 1 failed (1567 total)
  FAIL: patra_hdr_write: a refused sync is an error (got 0, expected 1)
```

(Linux x86_64 1,645 / 1,645; aarch64 under qemu 1,645 / 1,645; Windows on cass 1,565 / 1,565 with 1.16.4.)

## Root cause

`test_failed_sync_reported` (tests/tcyr/patra.tcyr) opens `/dev/null` as "an fd that takes a seek and a write but
refuses fdatasync with EINVAL" — Linux's behaviour. On macOS the sync of `/dev/null` succeeds, so `patra_hdr_write`
returns `PATRA_OK` and the row expecting `PATRA_ERR_IO` fails. The `_sync_fail` seam rows (the failure injected by
patra's test-only fault seam) pass on macOS; only the bare-helper row depends on the device.

## Fix direction

On macOS, assert the premise (`_pt_fdatasync` on `/dev/null` answers 0) and drive the bare `patra_hdr_write` row
through the `_sync_fail` seam instead, or find a macOS fd whose sync is refused (a pipe answers ENOTSUP there, per
src/file.cyr's note) — measure on ecb / ach.
