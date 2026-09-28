# aarch64 `f64_ln` / `f64_log2` return finite values for 0, ±inf, NaN and subnormals, and the ln/exp polyfills miss their stated accuracy by 40–460× — RESOLVED v6.6.8

**Status:** ✅ **RESOLVED v6.6.8** (bite 5) — fdlibm/FreeBSD ports of exp/ln/log2/exp2 with IEEE specials and range guards (≤ 1 ulp, the filed repro exits 0 on qemu-aarch64 and x86_64), PE x87 precision control, ganita 1.2.7 Annex F pow. Filed 2026-09-25 as 🟡 OPEN: reproduced against cyrius HEAD `52fabac5`, whose `lib/math.cyr`
is byte-identical to the 6.6.6 snapshot, with the installed 6.6.6 compiler. The repro exits **15** on
aarch64 (qemu-aarch64 11.1.1) and **0** on x86_64.
**Placement:** **6.6.8 bite 5** — exp/ln family correct on every target: fdlibm ln/log2/exp/exp2 with IEEE specials and range guards; PE x87 precision control; ganita pow Annex F. Pinned 2026-09-27 in [roadmap.md](../../roadmap.md) *The 6.6.7 → 6.6.9 batch* (releases ship strictly in order).
**Discovered:** 2026-09-25 during tyche's 1.0.3 toolchain bump. A golden-stream dump of tyche's
`rng_normal` differed between x86_64 and aarch64 on 220 of 1,952 lines, identically under 6.6.2 and
6.6.6. The divergence traced to `f64_ln`, and a scan of the polyfill turned up the rest.
**Severity:** Medium. On aarch64, a stdlib math builtin silently returns wrong answers: finite values
for inputs whose IEEE-754 / C results are −inf, +inf or NaN, and finite results off by up to 2,313 ulp.
This is the same class and severity as the archived
[`2026-09-08-f64-exp-nan-for-infinite-argument.md`](2026-09-08-f64-exp-nan-for-infinite-argument.md),
which was verified on x86_64 only. x86_64 is not affected.
**Affects:** every aarch64 build that reaches `EF64_LN` / `EF64_LOG2` / `EF64_EXP`. The ln and exp
polyfills date from v5.7.31 and log2 from v5.8.4. Measured on 6.6.6; the special-value half follows
from code that has had no guards since v5.7.31. x86_64 (x87 `fldln2; fxch; fyl2x`) and cx (refuses
floats) are not affected.

## Summary

On aarch64, `f64_ln` lowers to a call to `_f64_ln_polyfill` (`src/backend/aarch64/emit.cyr:1983` →
`lib/math.cyr:138`). `f64_log2` lowers to `_f64_log2_polyfill`, which is `f64_ln(x) * LOG2E`
(`lib/math.cyr:190`), and `f64_exp` lowers to `_f64_exp_polyfill` (`lib/math.cyr:69`). They have
two independent defects:

1. **Special values.** The ln polyfill decomposes its argument as if it were always a positive
   normal double, so:

   | input | aarch64 got | IEEE-754 / C (and x87) |
   |---|---|---|
   | `ln(+0)` | −709.0895657128241 (= −1023·ln 2) | −inf |
   | `ln(-1)`, `ln(-inf)` | −inf | NaN |
   | `ln(+inf)` | 709.782712893384 (= 1024·ln 2) | +inf |
   | `ln(NaN)` | 710.1881780014921 | NaN |
   | `ln(2^-1074)` (min subnormal) | −709.0895657128241 | −744.4400719213812 |
   | `ln(2^-1060)` | −709.0895657128204 | −734.7360113935421 |
   | `log2(+0)` | **−1023.0** exactly | −inf |
   | `log2(+inf)` | **1024.0** exactly | +inf |

   The log2 rows are the most dangerous. They come back as plausible integers, so nothing
   downstream looks wrong. `ln(-0)` does come out −inf, but only by the accident described under
   Root cause.

2. **Accuracy.** The source comments claim "8 terms gives < 5 ulp" for ln, "~5 ulp at typical
   inputs" for log2, and "~few-ulp relative error" for exp. A 166,000-point scan against a correctly
   rounded reference measured:

   | class | n | x86_64 (x87): CR · max · mean ulp | aarch64 (polyfill): CR · max · mean ulp | bit-identical across targets |
   |---|---:|---|---|---:|
   | ln, uniform (0,1) | 50,000 | 100.0% · 1 · 0.00 | 49.8% · **210** · 7.16 | 49.8% |
   | ln, every binade | 50,000 | 100.0% · 1 · 0.00 | 69.6% · 156 · 0.33 | 69.6% |
   | ln, 1 ± k ulp and 1 ± 2^-j | 1,120 | 99.2% · 1 · 0.01 | 71.8% · 9 · 0.30 | 71.0% |
   | ln, m = √2 reduction edge | 4,800 | 100.0% · 1 · 0.00 | **0.0%** · **213** · 85.44 | 0.0% |
   | log2, every binade | 20,000 | 100.0% · 1 · 0.00 | 56.2% · 92 · 0.49 | 56.2% |
   | exp, [−700, 700] | 20,000 | 94.5% · 1 · 0.06 | 0.6% · **2,313** · 203.63 | 0.6% |
   | exp, [−1, 1] | 20,000 | 100.0% · 1 · 0.00 | 44.6% · **1,899** · 95.91 | 44.6% |

   The worst errors, 213 ulp for ln and 2,313 for exp, are 40× and 460× the comments' claims.
   The file header's looser "~1e-12 relative" target is met (the ln maximum is about 4.7e-14
   relative); the per-function claims are not.

The consequence is that the same program gives different answers on x86_64 and aarch64, since x86 is
effectively correctly rounded. For tyche this broke `rng_normal`'s documented bit-exact cross-platform
determinism: about a third of normal draws differ in their low bits between the two targets.

## Reproduction

[`repros/2026-09-25-aarch64-f64-ln-polyfill-specials-and-accuracy.cyr`](../repros/2026-09-25-aarch64-f64-ln-polyfill-specials-and-accuracy.cyr).
It exits with the number of wrong answers. Special values must match exactly; finite rows must land
within 1 ulp of the correctly rounded value, a bar that both x87 and any fdlibm-grade fix clear.

```sh
cd ~/Repos/cyrius
R=docs/development/issues/repros/2026-09-25-aarch64-f64-ln-polyfill-specials-and-accuracy.cyr
cyrius build --aarch64 $R /tmp/lnpf-a64 && qemu-aarch64 /tmp/lnpf-a64; echo "exit=$?"   # exit=15
cyrius build $R /tmp/lnpf-x86 && /tmp/lnpf-x86; echo "exit=$?"                         # exit=0
```

aarch64 output, abridged:

```
  ln(+0)            got finite 0xc08628b76e3a7b61  want -inf   <-- WRONG
  ln(+inf)          got finite 0x40862e42fefa39ef  want +inf   <-- WRONG
  log2(+inf)        got finite 0x4090000000000000  want +inf   <-- WRONG
  ln(2^-1074)       got 0xc08628b76e3a7b61  cr 0xc0874385446d71c3  310946340992610 ulp   <-- WRONG
  ln(1.41421356..)  got 0x3fd62e42fefa35f3  cr 0x3fd62e42fefa36c8  213 ulp   <-- WRONG
  exp(543.774652.)  got 0x70f6a49cceacf16c  cr 0x70f6a49cceace863  2313 ulp   <-- WRONG
wrong answers: 15
```

**How the table above was produced.** The harness evaluated each builtin on inputs from an integer
xorshift64, which is identical on both targets, plus fixed edge lists, and printed raw bit patterns.
The reference was Python's `decimal` at 50 digits (`Decimal.ln` / `Decimal.exp` are correctly rounded
at the context precision), rounded to double through `fractions.Fraction`; CPython's int/int true
division is correctly rounded. ulp distances are measured on a sign-monotonic integer mapping of
the bit patterns. The x86 host was an AMD Ryzen 7 5800H; the aarch64 binaries ran under
qemu-aarch64 11.1.1. The repro above
carries the load-bearing rows.

## Root cause

1. **No special-value handling in `_f64_ln_polyfill`** (`lib/math.cyr:141-150`). The field split
   assumes a positive normal input:
   - **±0 and subnormals** have `e_raw = 0`, so `e_int = -1023` and `m` gets an implicit leading 1
     that a subnormal does not have. That gives `ln(+0) = -1023·ln 2`, and every subnormal lands
     near −709 regardless of its value.
   - **Negative inputs**: `x & 0x800FFFFFFFFFFFFF` keeps the sign bit, so `m ∈ (-2, -1]`. The
     `m >= 0x3FF6A09E667F3BCD` bit compare is signed and fails, and `u = (m-1)/(m+1) = -2/0 = -inf`,
     so the result is −inf. That is correct for −0 by accident and wrong for every negative number.
   - **±inf and NaN** have `e_raw = 2047`, so `e_int = 1024` and the result is finite.

   `_f64_log2_polyfill` inherits all of this, since it only multiplies by `LOG2E`. `_f64_exp_polyfill`
   got its ±inf guards at 6.6.1; ln never did, because that filing was verified on x86_64, where
   x87 already answers correctly.

2. **ln truncation** (`lib/math.cyr:156-176`). The atanh series stops after `u^14/15`. At the
   reduction boundary m = √2, `|u| = 3 − 2√2 = 0.171573`, and the first omitted term relative to the
   sum is `u^16/17 = 3.3e-14`, about **207 ulp** of ln(√2). The measured maximum is 213. The comment's
   "`u^17/17 ≈ 4e-16` absolute" is an arithmetic slip: `0.171573^17 / 17 = 5.7e-15`, or `1.1e-14`
   after the `2u` factor. Minor contributors: `m + 1` rounds, dropping m's last bit for m ∈ [1, √2),
   and `e_int * F64_LN2` uses a one-word ln 2, which is off by `e_int × 2.3e-17`.

3. **exp truncation and reduction** (`lib/math.cyr:88-128`). An 11-term Taylor series on
   `|r| ≤ ln2/2` leaves a first omitted term of `r^11/11! = 2.2e-13` absolute, about **2,765 ulp**
   relative at `exp(−ln2/2)`. The comment quotes 1.4e-13 and then concludes "few-ulp", which does not
   follow. The reduction also uses a one-word `LN2`, so `r` carries an error that grows with `|n|`
   (up to ~1,010 at |x| = 700).

4. **The gate cannot see either defect.** `_aarch64_f64_polyfill_gate`
   (`programs/checks/platform_aarch64.cyr:574`) is labelled *"polyfills bit-accurate on Pi"*. It
   runs `tests/fixtures/aarch64_f64/polyfill_ops.cyr`, which has 10 finite rows with tolerances of
   1,024–8,192 ulp and no special-value rows, and it skips entirely when the Pi is unreachable over
   SSH.

## Proposed fix

1. **Guard special values at the top of `_f64_ln_polyfill`**, before the field split, in the same
   shape as the 6.6.1 exp guards: NaN → return `x`; negative non-zero (sign bit set) → NaN; ±0 → −inf;
   +inf → +inf. For **subnormals**, scale by 2^54 (`f64_mul(x, 0x4350000000000000)`) and subtract 54
   from `e_int`. log2 then inherits the fixes through its `f64_ln` call.
2. **ln accuracy.** Either extend the series through `u^28/29` (seven more Horner steps, truncation
   ≈ 2^-60 relative) or port a minimax log (fdlibm `e_log.c`, < 1 ulp) with a two-word ln 2, where
   `ln2_hi` has enough trailing zero bits that `e_int·ln2_hi` is exact. Correct the comments.
3. **exp accuracy.** Use a Cody–Waite two-word `LN2` reduction and a longer or minimax polynomial
   (fdlibm `e_exp.c`, < 1 ulp). Correct the comment.
4. **Gate.** Move the repro's rows into `polyfill_ops.cyr`: exact special-value classes and ≤ 1 ulp
   finite rows. Or add them as a `tests/tcyr/crossos/` case so they run on real ecb and pi, not only
   when the Pi answers SSH. Drop "bit-accurate" from the label unless it becomes true.
5. **Cross-target bit identity is a design decision (the maintainer's call).** Items 1–4 make
   aarch64 *correct*; they do not make it *identical* to x86_64. A < 1 ulp polyfill still disagrees
   with x87 wherever either one is not correctly rounded, and x87 exp was correctly rounded on only
   94.5% of [−700, 700] here. Only a correctly rounded implementation on both targets, or one software
   implementation used on both, would make these builtins bit-identical across targets. If that is
   not a language promise, say so in the guide, because consumers are currently inferring it.

## Consumer-side workaround

- **tyche 1.1.0** (the reporter) took `f64_ln` out of `rng_normal`. It uses its own logarithm,
  `_rng_ln` in `src/rng.cyr`: a table-free double-double evaluation built only from `f64_add` /
  `f64_sub` / `f64_mul` / `f64_div` (Dekker products, no FMA), about 220 operations. It gave the
  correctly rounded result on all 1,294,808 test inputs and on 9,999,999 of the 10,000,000 values
  behind a 10M-draw run; the miss is a hard case 2^-74 from a rounding midpoint. It is
  bit-identical on x86_64 and aarch64: 256,002 inputs and 10,000,000 consecutive `rng_normal` draws
  were compared, and tyche's CI now runs its exact-bit vectors under qemu-aarch64. The price is
  speed: `_rng_ln` measures 283 ns, and `rng_normal` went from 92 ns (x87 `f64_ln`) to 347 ns on an
  x86_64 host. Any consumer that needs a cross-target `ln` can copy it; both projects are
  GPL-3.0-only.
- **Everyone else**: on aarch64, guard 0, negative, non-finite and subnormal inputs before calling
  `f64_ln` or `f64_log2`, and do not rely on ln/log2/exp results agreeing bit-for-bit across targets.
