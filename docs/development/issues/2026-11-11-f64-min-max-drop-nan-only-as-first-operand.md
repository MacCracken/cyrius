# `f64_min` / `f64_max` ignore a NaN only as the first operand, and the stdlib lacks the rest of the Rust f64 surface — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-11.
**Discovered:** 2026-11-11, by pravash's Rust → Cyrius port (M0 step 4, `pravash/docs/development/port-parity.md` §1).
impetus found the same at its M0 (its port plan §8, "Stdlib math", not filed).
**Reporter:** pravash 2.0.0 port (conversion ledger L2; `pravash/docs/development/pravash-port-plan.md` §8).
**Severity:** **Medium.** Every Rust port needs its own helpers today, and code that takes `f64_min` / `f64_max` for
`fmin` / `fmax` gets NaN wherever a NaN is the second operand.

## Summary

`f64_min(NaN, 1.0)` is 1.0, but `f64_min(1.0, NaN)` is NaN; `f64_max` the same. IEEE 754-2008 minNum / maxNum, C's
`fmin` / `fmax` and Rust's `f64::min` / `f64::max` all return the number whichever operand is the NaN. The asymmetry
looks like the `minsd` / `maxsd` instruction's own rule (it returns the second operand when either is NaN) leaking
through. pravash's Rust oracle calls `min` / `max` at 165 sites and `clamp` at 22. Over its 760-row golden sweep,
`f64_min` and `f64_max` each differ on exactly the 69 rows with a NaN second operand.

## Reproduction

[`repros/2026-11-11-f64-min-max-drop-nan-only-as-first-operand.cyr`](repros/2026-11-11-f64-min-max-drop-nan-only-as-first-operand.cyr),
from the repo root:

```sh
cyrius build docs/development/issues/repros/2026-11-11-f64-min-max-drop-nan-only-as-first-operand.cyr /tmp/minnan
/tmp/minnan; echo "exit=$?"
# f64_min(1.0, NaN) = 0x7ff8000000000000   WRONG, want 0x3ff0000000000000   (and f64_max likewise)
# exit=1
```

## Ask

1. **Make `f64_min` / `f64_max` minNum / maxNum** (return the other operand when exactly one is NaN), or add
   `f64_min_num` / `f64_max_num` with that rule if existing behaviour must stay. For equal operands, including
   +0 and −0, pravash's oracle (rustc 1.99.1 on x86_64) returns the second operand for both min and max, and the
   current functions already agree there.
2. **The rest of the f64 surface a Rust port needs**, each a one-liner today in every port (impetus's `mathx.cyr`,
   kimiya's, pravash's):
   - public `f64_is_nan`, `f64_is_finite`, `f64_copysign`, and `f64_sin_cos` (the pair);
   - typed constants `F64_MAX`, `F64_INFINITY`, `F64_NEG_INFINITY`, `F64_NAN`, `F64_EPSILON`, `F32_EPSILON`. The
     `F64_*` names today are untyped `var`s holding bits, so `F64_PI * x` is integer arithmetic unless the caller
     re-types them;
   - **saturating float → integer conversions** with Rust's `as` rules: NaN → 0, out of range → the type's
     bound, and negatives → 0 for an unsigned target. For example `f64_to_i32_sat`, `f64_to_u32_sat` and
     `f64_to_u64_sat`. `f64_to` is the i64 conversion: `f64_to(-3.7)` is −3, where `as usize` gives 0, and
     `f64_to(1e10)` is 10,000,000,000, where `as i32` gives `i32::MAX`. pravash has 24 such cast sites (grid
     indices, the SPH cell key, the Morton code).

## Also needed: ushma (2026-11-11, cyrius 6.7.18)

ushma's port measured the same asymmetry on its golden corpus. `f64_max` and `f64_min` differ from Rust on 59 of 600
rows each, and every one has a NaN second operand (`ushma/docs/development/port-parity.md` §2a). `f64_clamp` matches
Rust on all 617 of its rows with valid bounds.

ushma 1.4.0's library code (tests excluded) calls this surface at:

| Rust | Call sites |
|---|---|
| `f64::max` / `f64::min` | 11 / 6 |
| `is_finite()` / `is_nan()` | 21 / 5 |
| `f64::NAN` / `f64::INFINITY` / `f64::NEG_INFINITY` / `f64::EPSILON` | 11 / 1 / 1 / 1 |
| `clamp` | 9 (`f64_clamp` is fine) |

Its stand-in is kimiya's `_km_min`, `_km_max`, `_km_is_finite`, `_km_is_nan` and `_km_powi`, vendored into ushma's
`src/mathx.cyr` as `_us_*`. That is a fourth private copy, after impetus's, kimiya's and pravash's.
