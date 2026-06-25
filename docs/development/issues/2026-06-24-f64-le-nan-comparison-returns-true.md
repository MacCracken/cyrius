# `f64_le(NaN, x)` returns true — float `<=` is wrong on NaN operands (likely `>=` too)

**Filed:** 2026-06-24 (discovered during the prajna 0.6.0 hardening pass; reproduced on cycc 6.2.40).
**Severity:** MEDIUM — silent wrong result in a core numeric comparison. No crash, but it defeats
NaN guards, which is how it slipped through a verification gate in a downstream consumer (below).
**Component:** codegen / stdlib float comparison (`f64_le`, and by inspection probably `f64_ge`).

## Context

prajna (the meta-learning ML reference) finite-difference-gates every hand-derived gradient with
`f64_le(|analytic - fd|, tol)`. A training run diverged and produced a `NaN` gradient — and the
gate **passed it** instead of failing. Root cause: `f64_le(NaN, tol)` evaluates to **1 (true)**.

This is the opposite of IEEE-754: every comparison with a NaN operand is *unordered* and must
return **false** — including `<=`. So `NaN <= x` should be `0`. A NaN silently satisfying a
`<=` bound means any "is this within tolerance / below threshold / finite enough" check can be
fooled by a NaN, which is exactly the failure mode such checks exist to catch.

## Reproduction

```cyrius
fn main(): i64 {
    var nan = f64_div(f64_from(0), f64_from(0));     # NaN
    var inf = f64_div(f64_from(1), f64_from(0));     # +Inf
    fmt_int(f64_le(nan, f64_from(5)));  nl();        # prints 1  — WRONG (IEEE: 0)
    fmt_int(f64_gt(nan, f64_from(5)));  nl();        # prints 0  — correct
    fmt_int(f64_gt(f64_from(5), nan));  nl();        # prints 0  — correct
    fmt_int(f64_le(inf, f64_from(5)));  nl();        # prints 0  — correct (Inf is ordered)
    return 0;
}
```

Verified outputs (cycc 6.2.40): `f64_le(NaN, 5) = 1`, `f64_gt(NaN, 5) = 0`, `f64_gt(5, NaN) = 0`.

## Root cause (hypothesis)

`f64_gt` is correct (returns `0`/false on a NaN operand — IEEE unordered). `f64_le` appears to be
codegen'd as the **boolean negation of `f64_gt`** (`a <= b  ≡  !(a > b)`). That identity holds for
ordered values but **breaks on NaN**: both `NaN > x` and `NaN <= x` should be false, yet `!(false)`
yields true. The x86 idiom that produces this is using `seta`/`setbe` (which read CF/ZF, the
unsigned/unordered flags) for the negated branch instead of an ordered-compare result.

## Scope to confirm

- `f64_le` — **confirmed wrong** on NaN.
- `f64_ge` — **not yet tested**, but if it is generated as `!f64_lt` by the same pattern, it has
  the identical bug. Worth a one-line check.
- `f64_lt` — not yet tested; `f64_gt`/`f64_eq` looked correct in the probe above.

## Impact / current workaround

Any code relying on `<=`/`>=` to reject out-of-range or non-finite values is unsafe. prajna worked
around it in `src/fdgate.cyr` by building a finite-guard out of `f64_gt` only
(`finite(v) = f64_gt(v, -BIG) && f64_gt(BIG, v)`, which correctly rejects NaN/±Inf because `f64_gt`
is IEEE-correct) and routing every gate through it. That is a consumer-side patch for a
language-level correctness bug — the comparison itself should be fixed.

## Suggested fix

`f64_le(a, b)` and `f64_ge(a, b)` must return **false when either operand is NaN** (IEEE unordered).
Generate them from an *ordered* compare (e.g. the result of `ucomisd` read with `setae`/`setbe`
combined with a parity/unordered check that forces false on NaN), rather than as the boolean
negation of `f64_gt`/`f64_lt`. After the fix, the prajna repro above should print `0` for
`f64_le(NaN, 5)` while leaving all ordered comparisons unchanged.
