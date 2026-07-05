# aarch64-native tcyr XFAIL: `simd_f32v4` — f32v4 packed ops are x86-only until SIMD Phase 5

- **Filed**: 2026-07-05 (v6.4.4, after CI caught it on real ARM)
- **Kind**: **phase-gated feature gap, NOT a bug** — expected-to-fail *for now*
- **CI**: `.github/workflows/ci.yml` → job `aarch64-native` → step "Test suite
  (.tcyr) — full corpus on NATIVE arm64" → `XFAIL="simd_f32v4"`

## What

`tests/tcyr/simd_f32v4.tcyr` exercises f32v4 packed arithmetic (`addps`/`subps`/
`mulps` via `f32v_add`/`_sub`/`_mul`). SIMD Phase 1 (v6.4.4) implemented these on
**x86 only**; the aarch64 (and cx) `EMIT_F32V_LOOP` is a **stub** that emits
nothing, so on ARM the arithmetic no-ops and 5 of the 8 asserts fail (exit 5).
Construct/extract (`f32v4_make`/`_splat`/`_lane`) work on all targets — only the
packed ops are gated.

## Why XFAIL, not SKIP

SKIP never runs the test on ARM → the workaround would sit there silently even
after aarch64 gains f32v4 support, masking a real regression (the "green
checkmark that doesn't test what it claims" failure mode). **XFAIL still runs it
on real ARM**, expecting failure now. When Phase 5 lands NEON f32v4, the test
**passes** → the loop records an **XPASS**.

**The XFAIL is STRICT (`xfail_strict`): an XPASS is a HARD CI failure, not a soft
log line.** The corpus gate is `test $fail -eq 0 && test $xpass -eq 0`, so the
moment `simd_f32v4` passes on ARM the aarch64-native job goes **RED** with:

```
XPASS: simd_f32v4 — now PASSES on ARM; REMOVE it from XFAIL (see docs/development/issues/)
```

This is the whole point: a green check + a buried "XPASS" reminder is the silent
placebo we refuse to ship — you would only discover it two minors later. A RED
job forces the removal at exactly the right time. During Phases 2–4 (before NEON)
the test legitimately fails on ARM and is xfail'd → the job stays green; it cannot
persist past the point it should pass.

## set -e gotcha (v6.4.5 — the XFAIL loop must be set-e-safe)

The GHA shell is `bash -eo pipefail`. The corpus loop originally captured a
test's exit code with `out=$("$bin" 2>&1); ec=$?`. When an XFAIL test
*legitimately fails* (e.g. `simd_f32v4` no-ops the f32 arithmetic on the ARM
stubs → 10 failed asserts → `exit 10`), the command-substitution failure trips
`set -e` and **aborts the whole step with the test's exit code — before the xfail
bookkeeping ever runs**. So the v6.4.4 SKIP→XFAIL flip *silently turned the
aarch64 job red* (SKIP never ran the test; XFAIL runs it and the failure aborted
the step). Fixed to `ec=0; out=$("$bin" 2>&1) || ec=$?` (and `... || f=""` on the
grep, for tests that crash with no "N failed" line). **Rule: any change to the
SKIP/XFAIL loop logic MUST be tested under `bash -eo pipefail` with a mock
failing test — not just the case-match.** And note the local-gate gap: the
release gate's cross-OS step runs only the `vr01_` LIBTEST glob on real ARM, so a
full-corpus aarch64 loop bug slips past it; reproduce with `qemu-aarch64` (compile
a tcyr with `build/cycc_aarch64`, run under qemu — exit codes match CI).

## Why the underlying op is a silent stub (not a hard error)

A hard error at `EMIT_F32V_LOOP` on aarch64/cx would break **every** aarch64
build that `include "lib/simd.cyr"` — the f32v4 arithmetic wrapper bodies are
emitted before DCE (DCE is opt-in), so the error would fire on the *definition*,
not just on use. Clean `#ifdef` gating of the wrappers isn't possible either: the
value-form wrappers need both `CYRIUS_ARCH_X86` **and**
`CYRIUS_HAS_VAL_SIMD_PARAMS`, but the preprocessor is single-level only (nested
`#ifdef` and `#if defined(A) && defined(B)` both fail to exclude — verified
empirically). So the stub stays, and the test is XFAIL'd.

## Removal (SIMD Phase 5 — aarch64 NEON)

When Phase 5 implements `EMIT_F32V_LOOP` on aarch64 (NEON `fmla`/packed-single)
— and cx, if its SIMD pipeline lands — do ALL of:

1. Remove `simd_f32v4` from `XFAIL` in `ci.yml` — the aarch64-native job will be
   **RED** (strict XPASS) until you do; that red is the forcing cue, not optional.
2. Confirm `simd_f32v4.tcyr` passes 8/8 on real ecb/pi (add it to the `vr01_`
   cross-OS LIBTEST glob or rename it, so the release gate — not only CI —
   covers it going forward).
3. Update the `lib/simd.cyr` / `backend/aarch64/emit.cyr` / `backend/cx/emit.cyr`
   comments that say "x86-only this phase".
4. Delete/close this file.
