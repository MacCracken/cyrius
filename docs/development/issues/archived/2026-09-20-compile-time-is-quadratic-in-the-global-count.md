# Compile time is QUADRATIC in the number of globals — 70,000 exceeds two minutes — RESOLVED v6.6.9

**Status:** ✅ **RESOLVED v6.6.9** (bite 1) — the global var table has an FNV name index, gvar_toks grows past 4096 and the supersede scan reads a per-name list: 20,000 globals compile in ~0.1 s (gate `globals_scale_linear.sh`, bench rows `compiler/scale_20k_*` in `scripts/bench-history.sh`; the two quadratic walks, `_findvar_core` and `_gv_prior`, are named in CHANGELOG [6.6.9]). ⚠ The table below timed FAILING compiles: `var gN = f(N);` was refused past 4096 until this fix.
**Placement:** **6.6.9 bite 1** — The global var table scales linearly: FNV name index, full-byte lexer hash, gvar_toks 4096 cap lifted. Pinned 2026-09-27 in [roadmap.md](../../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Discovered:** 2026-09-20

## Measured

Generated programs of N deferred globals (`var gN = f(N);`), same box, same compiler:

| globals | wall |
|---|---|
| 6,000 | ~0.9 s |
| 10,000 | ~2.6 s |
| 20,000 | ~11.3 s |
| 70,000 | > 120 s (timeout) |

Four-fold time for a doubling is the signature of a linear scan per registration.

## Why it matters

Generated code is the case: a table-driven consumer that emits one global per row hits this
long before it hits any documented cap (`gvar_toks` is 4,096 entries, and the var table is
1,048,576). The compiler does not say it is slow, it just takes minutes.

## Acceptance criteria

- The 20,000-global program compiles in time proportional to N, not N².
- A bench row (`benches/`) that records the shape, so the next regression is visible.
- Name the scan that was quadratic in the CHANGELOG — the fix is only trustworthy if the
  mechanism is stated.
