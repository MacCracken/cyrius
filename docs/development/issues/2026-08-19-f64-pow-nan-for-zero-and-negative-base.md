# `f64_pow` returns NaN for a zero or negative base

**Status:** 🟢 **FIXED UPSTREAM, awaiting refold** — landed in ganita **1.1.4** (2026-08-19),
pinned to cyrius 6.5.29. Nothing to change in the compiler or in `lib/` by hand; cyrius clears
this by refolding `dist/ganita.cyr`. Until then `f64_pow` in `lib/ganita.cyr` still returns NaN
for a zero or negative base.
**Placement:** unpinned — 6.5.x backlog. Folded stdlib (`lib/ganita.cyr`), not the compiler.
**Discovered:** 2026-08-19 during ganita 1.1.2's f32-tier test pass, then re-verified against cyrius's own fold
**Severity:** Medium — silently wrong. A public stdlib name returns NaN for inputs with a defined real result, with no diagnostic.
**Affects:** cycc 6.5.28, via the ganita **1.1.1** fold in `lib/ganita.cyr`. Present since the fold carried `ganita_f64_pow`.

## Summary

`f64_pow` is implemented as `exp(y · ln base)`. That identity only holds for `base > 0`,
so every base at or below zero falls out of `ln`'s domain and the NaN propagates out
through `exp`. It is reachable under the plain stdlib-looking name: `lib/ganita.cyr:1538`
aliases `fn f64_pow(base, exp)` onto `ganita_f64_pow`, so a cyrius consumer who never
heard of ganita still hits it.

| call | returns | expected |
|---|---|---|
| `f64_pow(0, 2)` | **NaN** | `0.0` |
| `f64_pow(0, 3)` | **NaN** | `0.0` |
| `f64_pow(-2, 2)` | **NaN** | `4.0` |
| `f64_pow(-2, 3)` | **NaN** | `-8.0` |
| `f64_pow(2, 10)` | `1024.0` ✅ | `1024.0` |
| `f64_pow(9, 0.5)` | `3.0` ✅ | `3.0` |
| `f64_pow(2, 0)` | `1.0` ✅ | `1.0` |

`pow(0, y)` and integral `pow(negative, y)` are ordinary, defined operations — a caller has
no reason to expect either to be a domain error, and nothing warns.

## Reproduction

[`repros/2026-08-19-f64-pow-domain.cyr`](repros/2026-08-19-f64-pow-domain.cyr)

```sh
cyrius build --no-deps docs/development/issues/repros/2026-08-19-f64-pow-domain.cyr /tmp/powdomain
/tmp/powdomain
```

Output as of 6.5.28 — the first four are wrong, the last three are the contrast set:

```
f64_pow(0, 2)    got=NaN  want=0.000000
f64_pow(0, 3)    got=NaN  want=0.000000
f64_pow(-2, 2)   got=NaN  want=4.000000
f64_pow(-2, 3)   got=NaN  want=-8.000000
f64_pow(2, 10)   got=1024.000000  want=1024.000000
f64_pow(9, 0.5)  got=3.000000  want=3.000000
f64_pow(2, 0)    got=1.000000  want=1.000000
```

## Root cause

`lib/ganita.cyr:1203` (folded from ganita `src/math_advanced.cyr:36`):

```cyrius
fn ganita_f64_pow(base, exp): i64 {
    return f64_exp(f64_mul(exp, f64_ln(base)));
}
```

`ln(0)` is `-inf` and `ln(negative)` is NaN. There is no domain handling before the
exp/ln path.

## Blast radius inside the fold

Everything built on `pow` inherits it:

- `ganita_f32_pow` — a thin widen-compute-narrow wrapper, so identical behaviour.
- `ganita_f32_cbrt` — needs `pow` for the magnitude. It already carries a **sign split**
  (`cbrt(x) = -(|x|^(1/3))` for `x < 0`) that exists solely because of this defect;
  removing it turns `cbrt(-8)` into NaN while every positive input still passes.
- `ganita_f32_cbrt(0)` returned NaN for the same reason until ganita 1.1.2 added an
  explicit `±0 -> ±0` guard. **That guard is not in cyrius's fold yet** — see below.

## Fix (landed upstream in ganita 1.1.4)

In `ganita_f64_pow`, ahead of the exp/ln path:

- `exp == 0` → `1.0` (already correct; keep it first, so `pow(0,0) == 1` as in C).
- `base == 0` → `0.0` for `exp > 0`, `+inf` for `exp < 0`.
- `base < 0` with an **integral** `exp` → compute `|base|^exp`, negate when `exp` is odd.
  A non-integral `exp` on a negative base is genuinely undefined in the reals; NaN is
  correct there and should stay.

Shipped exactly that, with one documented departure from C: `pow(-0, odd)` returns `+0`
rather than `-0`, because cyrius's `f64_neg(f64_from(0))` yields `+0` — a negative zero
cannot be produced or asserted against through the f64 helper surface, so the branch would
have been untestable dead code. Zero of either sign returns `+0`.

Sign for a negative base comes from the exponent's parity computed on the magnitude, so
`pow(-x, odd)` is bit-identical to `-pow(x, odd)` — the negative path adds no error. Parity
treats every `|y| >= 2^53` as even, which is exact rather than a shortcut: at that magnitude
consecutive f64 values are 2 apart, so no odd integer is representable.

Mutation-verified upstream: deleting the zero-base branch fails 5 assertions, dropping the
parity sign flip fails 3, and treating every negative-base exponent as integral fails 3 —
the last being the check that a genuinely undefined operation is still reported as NaN.

Cyrius side: nothing to change in the compiler or in `lib/` by hand — the fix arrives by
refolding `dist/ganita.cyr`.

## Fold is stale

`lib/ganita.cyr` is at **1.1.1**; ganita is now at **1.1.4** (pinned to 6.5.29). A refold
picks up, besides this fix:

- **1.1.2** — the `ganita_f32_cbrt(±0)` guard (cbrt of zero currently returns NaN in
  cyrius), plus the first tests the f32 tier has ever had (23/23 functions).
- **1.1.3** — the linalg suite (26/26: LU, Cholesky, QR, SVD, Jacobi eigen, least
  squares, pseudo-inverse), taking ganita's reference coverage to 80%.
- **1.1.4** — this fix, plus its f64/f32 domain tests. 227 assertions total.

## Consumer-side workaround

Guard the base at the call site:

```cyrius
# instead of f64_pow(b, e) where b may be <= 0
if (b == f64_from(0)) { r = f64_from(0); }        # for e > 0
else { r = f64_pow(b, e); }
```

For a negative base with an integral exponent, take `f64_pow(f64_abs(b), e)` and negate
when the exponent is odd — the same shape `ganita_f32_cbrt` already uses internally.

## Test status upstream

ganita's `tests/ganita.tcyr` carries a **self-expiring** group, `f32: known domain gaps`,
asserting the *current* NaN behaviour so the gap stays measured rather than merely known.
Those assertions fail the moment this is fixed, which is the signal to rewrite them to the
correct answers. Consumer-side record:
`ganita/docs/development/issues/2026-08-19-f64-pow-zero-and-negative-base.md`.
