# `if (x)` and `!x` on an f64 compile without a diagnostic and test the bits, so −0.0 is true — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-16. The repro exits 1.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-16, by rasayan's Rust → Cyrius port (M0 step 9, probe 12; `rasayan/docs/development/port-parity.md`
§3). ushma's probe 12 measured the same and recorded it without filing.
**Reporter:** rasayan 2.0.0 port (a coding rule covers it: rasayan's CLAUDE.md, "Never test an f64 for truth").
**Severity:** **Low–Medium.** Nothing warns, and the answer is wrong for exactly one value a numeric library meets
often: −0.0, which every product with a negative zero factor, every `-x` of a zero and every serde `-0.0` produces.
**Affects:** cycc 6.7.18 (every target: the test is on the 64-bit word).

## Summary

The f64 hygiene diagnostics at 6.7.18 catch every mix of an f64 with an integer that rasayan's probe 12 tried
(*integer arithmetic with an f64 right operand*, *an integer stored into an f64/f32 slot keeps its integer bits*,
*comparison mixes f64 and integer operands*). A truth test of an f64 is the one that passes silently: `if (x)` and
`!x` on a typed `f64` test the word for non-zero, so `-0.0` (`0x8000000000000000`) is true and `!(-0.0)` is 0, where
`x != 0.0` and `x == 0.0` say it is zero. A port that transcribes Rust's `if x != 0.0` as `if (x)` gets the wrong
branch on −0.0 and nothing says so.

## Reproduction

[`repros/2026-11-16-f64-truth-test-is-not-diagnosed.sh`](repros/2026-11-16-f64-truth-test-is-not-diagnosed.sh) (filed as
`repros/2026-11-16-f64-truth-test-is-not-diagnosed.sh`), from the repo root:

```sh
bash docs/development/issues/repros/2026-11-16-f64-truth-test-is-not-diagnosed.sh; echo $?
# -0.0 == 0.0: 1, if (-0.0): 1, if (!-0.0): 0
# diagnostics on the truth tests: 0
# repro: DEFECT PRESENT (an f64 truth test compiles silently and tests the bits)
# 1
```

## Proposed fix

Diagnose it like the other f64 traps: *a truth test of an f64 tests its bits (−0.0 is true); compare with 0.0*, for
`if (x)`, `while (x)`, `!x`, `x && …` and `x || …` where `x` is typed `f64` (or `f32`). An IEEE truth test (`x !=
0.0`) would be the other choice, but it changes what existing code computes; the warning does not.

## Consumer-side workaround

rasayan's rule (CLAUDE.md, f64 hygiene): never test an f64 for truth; compare explicitly (`x != 0.0`, `x == 0.0`).
Reviews check it, since the build cannot.
