# `f64_parse` is not correctly rounded: 1 ulp off on ~23% of short decimals, Inf / 0 at the range ends

**Status:** 🟡 **OPEN** — found by abaco 2.4.9's project audit; not repaired.
**Placement:** **6.6.13**, bite I4 (memory fixes + reported-issue repair, set by the user 2026-10-01) —
see `roadmap.md` § 6.6.13. Default fix: port bayan 1.5.7's parser (`bayan/src/dtoa.cyr`, correctly rounded
for every input) rather than the Clinger + double-double sketch below.
**Discovered:** 2026-09-30, abaco 2.4.9 project audit (finding `ai-nl-parse-f64-inexact`: abaco's
natural-language and currency-rate paths read numbers with `f64_parse`).
**Severity:** Medium — silent wrong values for valid input; consumers can work around it with
their own parser.
**Affects:** cyrius 6.6.12 `lib/math.cyr` (`f64_parse`, line 848; `f64_parse_ok` shares it).

## Summary

`f64_parse` sums the fraction as digit · 0.1^k and applies the exponent by multiplying by 10 one
step at a time. Each step rounds, so the result is not the double nearest the decimal:

- **1 ulp off on 2,271 of the 10,000 literals `0.00` … `99.99`** (22.7%), e.g. `0.3` →
  0.30000000000000004, `0.12` → 0.12000000000000001, `9.95` one ulp high. Every miss is 1 ulp.
- **Overflow to Inf for finite values:** `0.0001e310` → +Inf (1e306 is representable), because
  10^310 is formed before the 0.0001 is applied.
- **Flush to 0 for subnormals:** `123e-310` → 0 (want 1.23e-308), `5e-324` → 0 (want the
  smallest subnormal).
- Near the ends it can be several ulp off: `2.2250738585072014e-308` (DBL_MIN) comes back
  2 ulp high, `8.98846567431158e307` 2 ulp low.

The reference is the correctly rounded double (Python `float()`, i.e. `strtod`).

## Reproduction

`repros/2026-09-30-f64-parse-not-correctly-rounded.cyr`, run from the repo root. It prints each
row's bits; the exit code is the number of wrong rows.

```
cyrius build docs/development/issues/repros/2026-09-30-f64-parse-not-correctly-rounded.cyr /tmp/f64p
/tmp/f64p; echo "exit=$?"      # -> 9 on 6.6.12 (the 3 controls pass)
```

## Root cause

`lib/math.cyr:848` onward: the mantissa and fraction are accumulated in f64 (one rounding per
digit), and the decimal exponent is applied by a loop of `*10` / `/10` (one rounding per step,
and overflow/underflow of the intermediate power of ten before the mantissa is applied).

## Proposed fix

Accumulate up to 19 significant digits exactly in an integer, combine the decimal exponent once,
then scale once: Clinger's fast path (mantissa < 2^53 and |exp| ≤ 22 → one exact multiply or
divide, correctly rounded), otherwise a double-double scale (Dekker two-product) with a single
final rounding. Clamp the combined exponent so long inputs cannot overflow the counter. That is
what abaco's `parse_number` does (`abaco/src/eval.cyr`, cited in `abaco/docs/sources.md`:
Clinger 1990, Dekker 1971): on a 5,000-literal corpus 99.74% bit-exact, worst 1 ulp, and it
handles both range ends. Fully correct rounding needs a bignum or Eisel–Lemire slow path for the
remaining midpoint cases. bayan's archived `2026-09-22-prakash-f64-parse-double-rounding-at-midpoint.md`
covers the same family on bayan's side.

## Consumer-side workaround

abaco 2.4.9 stopped calling `f64_parse`: `_nl_parse_f64` (`abaco/src/ai.cyr`) checks the grammar
itself and takes the value from the evaluator's `parse_number`.
