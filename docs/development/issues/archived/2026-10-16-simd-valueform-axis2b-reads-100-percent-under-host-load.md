# simd_valueform_no_avx_transition.sh axis 2b reads 9 ms / 9 ms (100 %) under host load and fails a check.sh run — RESOLVED

> ✅ **RESOLVED in v6.7.14** (IN-17, `073e9bc95` (no decision needed: a gate): axis 2b's fixtures run 150,000 passes (were 20,000), ~47 ms / ~25 ms on a quiet box, timed in microseconds (best of 5) — both halves of the fix direction; each fixture is checked to compute its last lane before it is timed (a broken fixture is a loud FAIL), and a 128-bit run under 20 ms is reported `too-fast` by name. The bound is 90 %, not the old strict 100 %: routing `f64v256_add` through the 128-bit kernel makes the two fixtures the same code, which read 98 – 103 %, so a `< 100 %` bound caught that mutation 4 runs in 8; 90 % catches it 8 in 8, and the real win reads 52 – 55 % (53 % under the lane gate's load). Row: `simd_valueform_no_avx_transition.sh` axis 2b; mutations RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: open — seen once in the 6.7.13 stdlib lane's lane gate (the first of two full check.sh runs on the same tree).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (infra lane, wave 1, unit I5; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low (a gate flake: a full suite went red with no code change behind it; nothing a user meets).

## Repro

The lane tree at `c99ea1e3` (branch `l6713-stdlib`; the lane touches only `lib/io.cyr`'s `#ifdef CYRIUS_TARGET_WIN`
arm, a crossos `.tcyr`, a platform gate and docs: nothing this gate compiles — it includes only `lib/simd.cyr` and
`lib/syscalls.cyr`), on x86_64 Linux with other sessions sharing the box (`uptime` read after the run: 15-minute
load average 8.2):

```
cd <worktree> && TMPDIR=<scratch> CYRIUS_CHECK_JOBS=4 sh scripts/check.sh
```

Run 1:

```
FAIL simd_valueform_no_avx_transition axis2b: the ymm kernel no longer wins at batch n
  f64v256_add 9ms vs f64v_add 9ms over n=1024 (100%, must be < 100%).
  If ymm stopped paying even in a batch loop, the wrappers' dispatch removal needs re-deciding.
  ^^ FAILED (exit 1): tests/gates/codegen/simd_valueform_no_avx_transition.sh
```

The same tree, the gate alone, minutes later:

```
PASS simd_valueform_no_avx_transition: value 9ms/9ms (100%) · _ptr 15ms/15ms (100%) · ymm batch win 70% · no per-call dispatch · 4 lanes correct
```

Run 2 of the full suite on the same tree: green.

## Root cause

Axis 2b compares two best-of-5 wall-clock timings measured in whole milliseconds, each about 9-13 ms, against a strict
`< 100 %` bound (`KR=$(( K2 * 100 / K1 ))`, fail at `KR >= 100`). The gate is `# check: serial`, so check.sh runs it
alone after the pool, but "alone" only covers this check.sh: other sessions on the same host still load the CPU, and
at ~9 ms a 1 ms rounding step is 11 %. One noisy sample set is enough to read the 256-bit kernel equal to the 128-bit
one. The fixture runs too briefly (20,000 iterations of n = 1024) for millisecond resolution to carry a strict bound.

## Fix direction (for whoever takes it)

Lengthen the axis-2b fixtures so each run is well above the millisecond floor (as axis 1 / 2a's "too fast to
compare" floors already guard), or measure in finer units, so the ratio's resolution is a few percent, not 11 %.
