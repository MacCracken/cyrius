# patra's other harnesses still open `/tmp/...` paths: on Windows `patra_uninit.tcyr` fails 3 of 18 and `patra_raw_include.tcyr` 6 of 6 — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on real cass (C:\cyrius-tests), by the 6.7.14 stdlib lane (unit L4), after
patra 1.16.4's suite patch (issues/archived/2026-10-16-patra-suite-dev-null-fixture-fails-on-windows.md) routed every `/tmp/`
path of `tests/tcyr/patra.tcyr` through a per-target helper (`_scr`: relative on Windows) — that suite now reads
1,565 / 1,565 on cass.
**Placement:** 6.7.15 — repair 5 (stdlib lane; filed from the 6.7.14 stdlib lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x. A
fold patch (patra), like 1.16.4.
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
