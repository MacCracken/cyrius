# patra's other harnesses still open `/tmp/...` paths: on Windows `patra_uninit.tcyr` fails 3 of 18 and `patra_raw_include.tcyr` 6 of 6 — RESOLVED

> ✅ **RESOLVED in v6.7.15** (PL-16, patra `1a22ddf` + `e36f202` (refolded at the integration after the user's 1.16.5 tag) — no decision needed (the fix plan's; tests only). `_scr` moves into the test-only include `tests/scratch_path.cyr` (the literal off Windows, the relative name on Windows, no allocation), and every other `"/tmp/<name>"` literal goes through it: `patra_uninit`, `patra_raw_include`, six fuzz harnesses (13), the benchmark (2), `test_libro` (2), `test_vidya` (1) — 20 beside the suite's 18. patra's CI gains a step that refuses a bare `/tmp` literal (and an empty scan). The filed repro on real cass: `patra_uninit` 15 / 18 → 18 / 18 and `patra_raw_include` 0 / 6 → 6 / 6, exit 0; `test_libro` and `test_vidya` 0xC0000005 → 15 and 19 passed; `fuzz_btree`, `fuzz_file`, `fuzz_jsonl`, `fuzz_sql` and `fuzz_wal` → 0; the benchmark exits 0. Rows: the CI step (38 literals, all through `_scr`); mutations each FAIL under `bash -e` and `bash -eo pipefail`: one literal unwrapped, an empty directory, 1.16.4's tree (20 literals). patra's CI isolated: ok=19, fail=0. ⚠ Seven of the eight fuzz harnesses pass on cass: `fuzz_bytes`, which now opens its file there, exposed its own defect (its mutations land at a heap address used as a page number — a ~17-minute write and a 50 GB file on cass) — its own issue, placed in 6.7.15's libfix lane and fixed in the same untagged patra 1.16.5. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on real cass (C:\cyrius-tests), by the 6.7.14 stdlib lane (unit L4), after
patra 1.16.4's suite patch (issues/archived/2026-10-16-patra-suite-dev-null-fixture-fails-on-windows.md) routed every `/tmp/`
path of `tests/tcyr/patra.tcyr` through a per-target helper (`_scr`: relative on Windows) — that suite now reads
1,565 / 1,565 on cass.
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P6; placed at the 6.7.15 open, 2026-10-18) — never 7.x. A
fold patch, patra 1.16.5 (the user tags it before the refold), like 1.16.4.
**Severity:** Low — test-fixture portability of a folded stdlib's harnesses: no shipped code is wrong, but these
harnesses cannot be read green on Windows.

## Reproduction

patra at its 1.16.4 commit (`tests/tcyr/patra_uninit.tcyr`, `tests/tcyr/patra_raw_include.tcyr` with `dist/`), each
built from a scratch copy whose `lib/` is the cyrius 6.7.14 lane tree's, with that tree's `build/cycc_win_cross`
(`cat tests/tcyr/<t>.tcyr | CYRIUS_TARGET_WIN=1 cycc_win_cross > <t>.exe`), run under C:\cyrius-tests on cass:

```
patra_uninit exit=3
=== after patra_init ===
[302478583003043] [ERROR] patra: cannot open or create file
  FAIL: patra_open succeeds
  FAIL: create (got 1, expected 0)
  FAIL: insert (got 1, expected 0)
15 passed, 3 failed (18 total)
patra_raw_include exit=6
=== dist/patra.cyr included alone ===
[302480655248892] [ERROR] patra: cannot open or create file
  FAIL: open db through the bundle
  FAIL: create (got 1, expected 0)
  FAIL: insert (got 1, expected 0)
  FAIL: query
  FAIL: one row (got 0, expected 1)
  FAIL: id round-trips (got 0, expected 7)
0 passed, 6 failed (6 total)
```

## Root cause

The same fixture shape 1.16.4 fixed in `tests/tcyr/patra.tcyr`, in the files outside that filing: `/tmp/<name>` is the
drive-rooted `\tmp\<name>` on Windows, which does not exist on cass. Literals:
`tests/tcyr/patra_uninit.tcyr:20` (`_upath`), `tests/tcyr/patra_raw_include.tcyr:18` (`_rpath`),
`fuzz/fuzz_wal.fcyr:13-14`, `fuzz/fuzz_file.fcyr:11` and `:101`, `fuzz/fuzz_bytes.fcyr:14`,
`tests/bcyr/patra.bcyr:9` and `:208`, `programs/test_libro.cyr:9` and `:105`, `programs/test_vidya.cyr:14`.

## Fix direction

The 1.16.4 helper (`_scr("/tmp/<name>")`: the literal on Linux, macOS and agnos, `p + 5` on Windows — no allocation,
so a top-level path variable can use it before `alloc_init`) in each file, or one shared include for the harnesses.
