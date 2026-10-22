# crossos/exec_cmd_forwards_environment.tcyr reports 0 assertions on Windows, so the cass cross-OS leg is red on the merged 6.7.16 tree — RESOLVED

> ✅ **RESOLVED in v6.7.16** (TT-1, `32d34d66a` — no decision needed (a test-shape defect; the 0-assertion rule is unchanged). The PE build of `tests/tcyr/crossos/exec_cmd_forwards_environment.tcyr` now asserts through `cmd.exe`: `_ecf_copy` answers `if "%SMALL%"=="s" (exit 0) else (exit 1)` on PE, and `_ecf_rows` gains W1 (a variable the parent hands `exec_env` reaches `exec_cmd`'s child), W3 (its control: no SMALL → 1) and W4 (`exec_cmd("if defined SystemRoot (exit 0) else (exit 1)")` → 0: the child inherits the parent's own environment); E2's 70,000-byte variable has no Windows twin (a variable is capped at 32,767 characters), and agnos still asserts nothing (no shell; not a lib-test host). The filed repro now prints `3 passed, 0 failed (3 total)` under wine and on real cass, rc 0 (was `0 passed, 0 failed (0 total)`); `CYRIUS_CROSS_OS_FULL=0 sh scripts/cross-os-selfhost.sh cass crossos` gives `SELFHOST_OK` + `ran 357 passed, 0 failed` `LIBTEST_OK` (was 356 / 1, `LIBTEST_FAIL`), ecb, ach and pi 357 / 357; x86_64 Linux E1 – E3 unchanged. Rows: the file's W1 / W3 / W4 (PE) beside E1 – E3. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-20 by the 6.7.16 zone lane (unit Z1, l6716-zone at f8139264f, a tree whose
only changes over the wave-1 integration b73e8d5fe are src/frontend/parse_decl.cyr's declaration-zone initializer
bake, its gates, three other crossos .tcyr files and the guide): `CYRIUS_CROSS_OS_FULL=0 sh
scripts/cross-os-selfhost.sh cass crossos` → `SELFHOST_OK: cass`, then `ran 356 passed, 1 failed on cass`, `failing:
exec_cmd_forwards_environment.tcyr(assert summary reports 0 assertions)`, `LIBTEST_FAIL: 1 test(s) on cass`, rc 1.
ecb, ach and pi: SELFHOST_OK + LIBTEST_OK on the same tree.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; t16 lane, wave 3, unit TT1) — never 7.x.
**Severity:** Medium for the release (release-gate step 4 runs the whole corpus on cass and goes red on this file);
Low as a defect (a test-shape problem, no wrong value).
**Kind:** test / gate (the tools lane's bd794af7a added the file; the lane's commit message says "green on ... cass
(summary only)").
**Discovered:** by unit Z1 while running its crossos rows on the four hosts; not this lane's file or subsystem.

## Reproduction

```sh
cd <the tree>
CYRIUS_TARGET_WIN=1 build/cycc < tests/tcyr/crossos/exec_cmd_forwards_environment.tcyr > /tmp/ecf.exe
wine /tmp/ecf.exe | tail -1      # (a private WINEPREFIX; cass prints the same)
# 0 passed, 0 failed (0 total)
# — the same with b73e8d5fe's build/cycc (the slot-open compiler of this wave): the file's body is
#   `#ifndef CYRIUS_TARGET_WIN`, so a PE build makes no assertion at all.
CYRIUS_CROSS_OS_FULL=0 sh scripts/cross-os-selfhost.sh cass crossos
#   failing: exec_cmd_forwards_environment.tcyr(assert summary reports 0 assertions)
#   LIBTEST_FAIL: 1 test(s) on cass
```

## Root cause

The file's header says Windows "has its own exec_cmd ... there the file reports only its summary", but the cross-OS
lib-test runner (and the check driver's `.tcyr` reader, tests/gates/toolchain/check_driver_requires_summary.sh row
"zero") refuse a summary of 0 assertions — a file that asserts nothing on a target is graded a failure there. So the
row that was "green on cass (summary only)" cannot pass the cass leg as the runner grades it.

## Proposed fix

Give the PE build at least one assertion (e.g. the Windows exec_cmd's own environment forwarding through `cmd.exe`,
or a trivially true row naming why the Unix rows do not apply), or move the file out of the cass leg's selection by
the runner's own skip mechanism if one exists for target-specific files — whichever the tools lane intended; not a
change to the 0-assertion rule (it caught a real class: ci_tcyr_loops_require_summary.sh).
