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

## Also needed: pramana (2026-11-15, cyrius 6.7.18)

pramana's semantics probe (its M0 step 4, `pramana/docs/development/port-parity.md` §1) checked every f64 operation
pramana 1.3.0 uses against a release-built Rust twin. `f64_min` and `f64_max` differ from Rust on all 69 of its golden
rows with a NaN second operand, as above. pramana calls `min` / `max` at 30 sites and `clamp` at 10, and needs Rust's
saturating `as usize` at 3: `percentile`'s rank, an iteration budget and a histogram bin.

Two more pieces of the surface that are not asked above:
- **A trunc-based fract.** `f64_fract` is x − floor(x), so `f64_fract(−2.75)` is 0.25, where Rust's `fract` (and C's
  `modf`) give −0.75. pramana's golden corpus has 871 `fract` rows. Ask: a trunc-based form, say `f64_fract_trunc`,
  with the current one documented as floor-based.
- **An unsigned u64 → f64.** `f64_from` reads its word as signed: 2⁶³ becomes −9.2e18 and u64::MAX becomes −1, where
  Rust's `n as f64` rounds the unsigned value to nearest. pramana's golden corpus has 536 rows of the conversion
  (Binomial's `n` is a u64). Ask: `f64_from_u64`, rounding to nearest.

[`repros/2026-11-15-f64-fract-floor-and-f64-from-signed.cyr`](repros/2026-11-15-f64-fract-floor-and-f64-from-signed.cyr):

```sh
cyrius build docs/development/issues/repros/2026-11-15-f64-fract-floor-and-f64-from-signed.cyr /tmp/fractu64
/tmp/fractu64; echo "exit=$?"
# f64_fract(-2.75) = 0x3fd0000000000000   WRONG, want 0xbfe8000000000000
# f64_from(2^63 as u64) = 0xc3e0000000000000   WRONG, want 0x43e0000000000000
# f64_from(u64::MAX) = 0xbff0000000000000   WRONG, want 0x43f0000000000000
# exit=1
```

pramana's stand-ins go in its `src/mathx.cyr` (ledger L2), marked `UPSTREAM(L2)`: `_pmn_min` / `_pmn_max` with Rust's
rule, `x − f64_trunc(x)` for `fract`, `_pmn_u64_to_f64` (halve with a sticky bit, convert, double; exact on 2⁶³,
2⁶³ + 2¹¹ + 1 and u64::MAX) and `_pmn_sat_usize`. That is a fifth private copy of this surface.

## Also needed: rasayan (2026-11-16, cyrius 6.7.18)

rasayan's guard layer (Rust 1.2.0's `guard.rs` and the clamps across 18 modules) is built on Rust's NaN rules: a NaN
input to `x.max(0.0)` comes out 0, and `clamp` passes NaN through to the `is_finite` checks after it. Its golden
corpus (`rasayan/docs/development/port-parity.md` §0.1, §2a) has the same asymmetry ushma and pramana measured:
`f64_max` / `f64_min` differ from Rust on 59 of 931 rows each, every one a NaN second operand; `f64_clamp` matches all
845 of its rows; `f64_to` differs from `as u32` on 14 of 99 (negatives, ±∞, 2³² and past).

rasayan 1.2.0's library code (tests excluded) calls:

| Rust | Call sites |
|---|---|
| `f64::min` / `f64::max` / `clamp` | 26 / 22 / 10 |
| `is_finite()` / `is_nan()` | 23 / 3 |
| `as u32` from f64 (the sub-step counts of the metabolic network, calcium and MAPK) | 3 |

Its stand-ins are `_ry_min`, `_ry_max`, `_ry_is_finite`, `_ry_is_nan` and `_ry_powi` in its `src/mathx.cyr` (from
ushma's, kimiya's originally), and `_ry_clamp` and a saturating `_ry_f64_to_u32` (M1): the sixth private copy, after
impetus, kimiya, pravash, ushma and pramana. Item 2's saturating conversions would retire `_ry_f64_to_u32`; its
`f64_is_finite` / `f64_is_nan` the two bit tests.
