# cycc `--agnos` miscompiles compile-time-constant 3-operand chained integer multiplies

**Discovered:** 2026-06-11 during cyrius-doom 0.29.1 (AGNOS port — "game world freezes without input")
**Severity:** Critical (silent wrong codegen → silent data corruption; scoped to the `--agnos` target; mechanical workaround exists)
**Affects:** cycc **6.1.29 and 6.1.35** (both confirmed). `--agnos` target only — the Linux/x86_64 target folds the same expression correctly.
**Reported by:** cyrius-doom (consumer). On cycc 6.1.35; need a release with the `--agnos` const-fold fix to drop the workaround.

> **STATUS: ROOT-CAUSED + FIXED (cyrius-side), pending v6.1.37 cut.**
>
> **Scope correction (premise-checked directly):** the defect is **NOT
> `--agnos`-specific** — it reproduces identically on the **Linux/x86_64** and
> **aarch64** targets too. The fold bug lives in the *shared* frontend
> (`src/frontend/parse_expr.cyr`), which is target-independent; both targets
> emit `mov 320; push; mov 200; pop rcx; imul; shl 2` correctly *after* the fix
> and the wrong `B << 2` before it. The consumer's "Linux is correct (256000)"
> was a misdiagnosis of the minimal **enum** repro (it's wrong on Linux too);
> cyrius-doom's real code likely const-folded `SCREEN_WIDTH * SCREEN_HEIGHT`
> from `#define`/literal sources that *do* fold correctly, while a `var` or enum
> operand triggers the runtime-`imul` path that has the bug.
>
> **Confirmed root cause (not the consumer's speculation):** the bug is the
> **const-fold tracking state (`_cfo`)**, NOT a register-allocation drop. In
> `PARSE_EXPR`'s multiply loop, when the LHS is a tracked constant (`_cfo==1`,
> e.g. `A`) and the RHS is itself a const (enum `B` or a NUM that overflowed the
> small-fold), the branch sets `_cfo = 0` then calls `PARSE_FACTOR(RHS)` — which
> **re-arms** `_cfo`/`_cfp`/`_cfv` on the const RHS. It commits a runtime
> `EIMUL` (A*B=64000) but leaves the stale tracking. The next `* C` then
> const-folds off the stale RHS (`B * C`) and `SCP`-rewinds the code pointer to
> the RHS's `EMOVI`, **discarding the A*B `EIMUL`** → `A * B * C` becomes
> `B * C`. (`(A*B)*4`, `enum*lit*lit`, `var*var*lit` and 2-operand all worked
> because they don't hit this stale-tracking-then-fold sequence.)
>
> **Fix:** clear `_cfo` *after* the runtime `EIMUL` (and on the `_TRY_MUL_BY_POW2`
> success path) in the three `_cfo==1` sub-branches — mirroring the already-correct
> outer-else / div / mod paths. ~6 lines in `src/frontend/parse_expr.cyr`.
>
> **Verified:** repro fixed on x86 + `--agnos` (identical multiply codegen) +
> aarch64 (qemu); cycc self-host **byte-identical fixpoint** (cycc's own source
> has no `enum*enum*C`, so it converged in one step; +112 B); ecb/ach/pi/cass
> `SELFHOST_OK`; check.sh **89/89**; new regression `tests/tcyr/const_chained_multiply_fold.tcyr`
> (8 cases, all targets). The consumer's 0.29.1 workaround can be dropped once
> v6.1.37 ships.

## Summary

A **compile-time-constant 3-operand chained integer multiply** — `A * B * C` where all
three operands are constants that fold at compile time — produces the **wrong value on the
`--agnos` target**. `320 * 200 * 4` folds to **800** instead of 256000. The result equals
`B * C` (`200 * 4 = 800`): the **first operand is effectively dropped** (treated as 1).

This is silent: no compile error, no warning, correct-looking code. It only surfaced because
cyrius-doom used the expression as an `alloc()` size (`alloc(SCREEN_WIDTH * SCREEN_HEIGHT * 4)`),
so an 800-byte buffer was handed a 256000-byte writer → 255 KB heap overflow → corrupted
adjacent allocations → a page fault two frames later. Any `--agnos` program that const-folds a
3-operand multiply (sizes, offsets, table dimensions, scale factors) is exposed to silently
wrong arithmetic.

What is **NOT** affected (verified):
- The **2-operand** fold `320 * 200` = 64000 is **correct** on `--agnos`.
- **Runtime** 3-operand multiplies are **correct** on `--agnos` — e.g. `sy * SCREEN_WIDTH * 4`
  with a variable `sy` produced correct framebuffer offsets (doom rendered correctly frame-to-frame).
- The same constant `A * B * C` on the **Linux** target is **correct** (256000).

So the defect is specific to: **(all-constant operands) × (≥3 chained `*`) × (`--agnos` backend)**.

## Reproduction

Minimal (drop into a `--agnos` smoke and print the two values — e.g. via `sakshi_info`/`fmt_sprintf`):

```cyrius
enum Dim { A = 320; B = 200; }

fn doom_main(): i64 {
    var two_op   = A * B;        # expect 64000  -> got 64000  (OK)
    var three_op = A * B * 4;    # expect 256000 -> got 800     (WRONG on --agnos)
    # print two_op and three_op ...
    return 0;
}
```

- Build `--agnos`, run under QEMU → `three_op = 800`.
- Build for Linux (`cyrius build src/main.cyr ...`), run → `three_op = 256000`.

Observed in cyrius-doom (serial log from `agnos/scripts/doom-smoke.sh`, both 6.1.29 and 6.1.35):

```
MULDBG sw=320 sh=200 sw*sh=64000 sw*sh*4=800
FBALLOC req=800 fb=276888904 | post ptr=276889704   # alloc advanced only 800 bytes
```

Downstream repro harness: `cyrius-doom @ 0.29.1`, `cyrius build --agnos src/main.cyr build/doom_agnos`,
then `agnos/scripts/doom-smoke.sh` (gnoboot + OVMF + NVMe; agnos kernel @ 1.44.22). Pre-fix the
engine froze after one rendered frame; the `ADDR` dump showed `fb_buf` overlapping `colormap`/`flat_cache`.

## Root cause (if known)

**Speculation** (consumer has not read the `--agnos` codegen): the chained `(A * B) * C` lowering
on the `--agnos` backend loses the `A * B` intermediate and multiplies `B * C` instead — i.e. a
register-allocation / constant-fold ordering bug in the 3-operand multiply lowering that only the
`--agnos` target path takes. Evidence for "first operand dropped": result is exactly `B * C` (800 =
200×4), and both the 2-operand fold and the variable-operand runtime multiply are correct, which
points at the *constant-folded 3-operand* lowering specifically, not multiply in general.

## Proposed fix

Fix the `--agnos` constant-fold / lowering of N-operand (N≥3) constant integer multiplies so it
matches the Linux target (and itself for the 2-operand and runtime cases). A regression test of the
shape `assert(320 * 200 * 4 == 256000)` compiled `--agnos` and run under QEMU would lock it; the
all-constant chained-multiply path is the one to cover.

## Consumer-side workaround (shipped in cyrius-doom 0.29.1)

Never write an all-constant 3-operand chained multiply. Either:
- collapse to a 2-operand fold against an existing constant: `SCREEN_SIZE * 4` (where
  `SCREEN_SIZE = 64000`) instead of `SCREEN_WIDTH * SCREEN_HEIGHT * 4`; or
- break the chain with a `var` so the third multiply is `var * const` (a correct runtime multiply):
  `var n = A * B; alloc(n * C);`

Fixed in cyrius-doom `src/framebuf.cyr` (`fb_buf`) and `src/render.cyr`
(`scalelight` / `zlight` in `render_init_light_tables`), CHANGELOG `[0.29.1]`.

**Audit note for other `--agnos` consumers:** grep for all-constant `alloc(X * Y * Z)` and any
const 3-operand multiply used as a size/offset/dimension — they silently compute wrong values on
`--agnos` with no diagnostic. `--ppm`-style single-shot tests will not catch the downstream effect;
exercise the real runtime in QEMU.
