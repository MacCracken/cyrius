# `lib/math.cyr`: the exp / exp2 polyfills (aarch64's `f64_exp` / `f64_exp2`) round subnormal results twice, and misround about 10 % of normal results — OPEN

**Status:** 🟡 **OPEN** — filed by kimiya (2026-11-09). Within the documented "finite results within 1 ulp" contract, so
nothing is out of spec. It is an accuracy defect, and it is the reason aarch64's `f64_exp` is not bit-identical to
x86_64's.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-09, during kimiya's M3 kinetics port (`kinetics::arrhenius_rate` and friends against the Rust
oracle, on x86_64 ELF, x86_64 PE and aarch64).
**Severity:** Low. Silent, but amplified: a consumer that multiplies a subnormal `exp` result back into the normal range
turns one subnormal ulp into hundreds or thousands of ulp. kimiya measured up to 39 ulp on aarch64 against the oracle
(`first_order_concentration`), and 0–7 on x86_64.
**Affects:** cyrius 6.7.18. That is the version measured; the code is fdlibm's `e_exp.c` design, so it is likely as old
as the fdlibm ports behind the 6.6.8 contract. `lib/math.cyr` `_f64_exp_kernel` (:92–104) serves `_f64_exp_polyfill`
(:111) and `_f64_exp2_polyfill` (:147). These are the `f64_exp` / `f64_exp2` builtins on aarch64; x86_64 lowers the
builtins to x87.

## Summary

`_f64_exp_kernel` computes y = e^r with fdlibm's rational kernel, **rounds it to 53 bits**, and then for k < −1021 forms
`y·2^(k+1000)` exactly and multiplies by 2⁻¹⁰⁰⁰. That multiply **rounds a second time**, onto the subnormal grid. Rounding
an already-rounded value again is wrong whenever the first rounding lands on, or crosses, a midpoint of the coarser grid.
For results just below DBL_MIN that happens for up to 25 % of inputs, about 0.9 % averaged over the subnormal range.
Even a correctly rounded kernel would keep those errors; only rounding once removes them. glibc does round once (see
Proposed fix), and on the same inputs glibc's exp misrounds none.

Separately, the fdlibm kernel itself is not correctly rounded on about 10 % of normal results. Those errors are within
the documented 1 ulp, and the x87 path misrounds about 5 %. So the two targets disagree on roughly one `exp` call in ten.

## Measurements

Seeded arguments (Python `random.Random(20261109)`). The glibc column is Python 3.14's `math.exp` / `math.exp2`. The
reference is MPFR 4.2.2 at 53 bits with binary64's emin/emax
and `mpfr_subnormalize`, so subnormal results and exact ties round as IEEE round-to-nearest does. The "double rounding"
column counts misses where the polyfill's answer equals the correctly rounded 53-bit value rounded again onto the
subnormal grid: the second rounding alone explains them.

| Function, result range | Arguments | Polyfill misrounded (max) | of which double rounding | x87 builtin misrounded | glibc 2.44 misrounded |
|---|---|---|---|---|---|
| `exp`, subnormal (x in [−745.13, −708.40]) | 20,000 | 187 (1 ulp) | 164 | 27 | 0 |
| `exp`, normal (x in [−708, 709]) | 5,000 | 481 (1 ulp) | — | 263 | 7 |
| `exp2`, subnormal (x in [−1074, −1022]) | 10,000 | 98 (1 ulp) | 91 | 0 | 0 |
| `exp2`, normal (x in [−1021, 1023]) | 3,000 | 313 (1 ulp) | — | 4 | 3 |

- On aarch64 the `f64_exp` / `f64_exp2` builtins returned exactly the polyfill's bits on all 38,000 arguments.
- Even a correctly rounded 53-bit value, rounded again onto the subnormal grid, is wrong on 186 of the 20,000 `exp` and 98
  of the 10,000 `exp2` subnormal results.
- 1 ulp of a subnormal can be a large relative error. `exp(−714.8919412220861)` returns 6801271522920·2⁻¹⁰⁷⁴ instead of
  6801271522921·2⁻¹⁰⁷⁴, a relative error of 1.5·10⁻¹³, which is about 660 ulp once scaled back into the normal range.

## Reproduction

[`repros/2026-11-09-exp-polyfill-double-rounds-subnormal-results.cyr`](repros/2026-11-09-exp-polyfill-double-rounds-subnormal-results.cyr)
is self-proving. It calls the polyfills directly, so it fails the same way on every target. Each line prints got / want /
the target's builtin, and the exit status is the number of wrong lines.

```
cyrius build docs/development/issues/repros/2026-11-09-exp-polyfill-double-rounds-subnormal-results.cyr /tmp/expdr
/tmp/expdr; echo "exit=$?"
exp(-708.625718966676)   subnormal, double rounding: got cb8afe6233a74, want cb8afe6233a75, builtin cb8afe6233a75   <-- WRONG
exp(-714.8919412220861)  subnormal, double rounding: got 62f8b5f8668, want 62f8b5f8669, builtin 62f8b5f8669   <-- WRONG
exp2(-1023.7612887429359) subnormal, double rounding: got 4b841b5dcc4ec, want 4b841b5dcc4eb, builtin 4b841b5dcc4eb   <-- WRONG
exp(-710.7792632481745)  subnormal, kernel: got 17a02a330fa88, want 17a02a330fa89, builtin 17a02a330fa89   <-- WRONG
exp(-335.8298715066705)  normal, kernel: got 21a6a041af09f590, want 21a6a041af09f58f, builtin 21a6a041af09f58f   <-- WRONG
exp2(118.55785380705424) normal, kernel: got 47578da1546ec2be, want 47578da1546ec2bd, builtin 47578da1546ec2bd   <-- WRONG
exit=6
```

On aarch64 (`cyrius build --aarch64 …`, `qemu-aarch64 …`) the lines are the same, but the builtin column equals "got",
so the aarch64 `f64_exp` is the misrounded value. Every "want" is also glibc 2.44's result. Expected once fixed: the first
four lines pass (the subnormal ones). The last two pass only if the kernel is replaced too (fix 2).

## Root cause

`lib/math.cyr` `_f64_exp_kernel`, the line
`return f64_mul(y + ((k + 1000) << 52), _F64_2POW_M1000);` (:103). y is already rounded to 53 bits; the multiply rounds
it again to the subnormal's fewer bits. fdlibm's `e_exp.c` does the same: it adds k + 1000 to y's exponent, then
`return y*twom1000;`. FreeBSD msun's version is `y*twopk*twom1000`. It was written for
a 1-ulp bound, and double rounding stays within 1 ulp, so the contract holds. The normal-result misroundings come from the
kernel's own error, about 0.5 + ε ulp, which fdlibm's Remez rational kernel doesn't bound below 1 ulp.

## Proposed fix

1. **Round subnormal results once** (the four subnormal lines), as glibc does. Its `specialcase`
   (`sysdeps/ieee754/dbl-64/e_exp.c`, from Arm's optimized-routines) works like this: when the result is below DBL_MIN it
   scales y so the result is 2⁻¹⁰²²·y with y < 1, keeps y's rounding error in `lo`, and computes `hi = 1.0 + y;
   lo = 1.0 − hi + y + lo; y = (hi + lo) − 1.0; y = 0x1p-1022 * y`. Adding 1.0 puts hi's ulp at 2⁻⁵², which is 2⁻¹⁰⁷⁴
   after the scale, so `hi + lo` rounds exactly once at the subnormal ulp. The subtraction and the final scale are then
   exact. For fdlibm's kernel, this needs y as an unevaluated sum: keep `hi − (lo − q)` as a pair instead of folding it
   into one double before the scale. That is a few lines, and it touches only the k < −1021 path, so normal results and
   the fast path keep their bits.
2. **Optionally, a better kernel for normal results** (the last two lines): glibc's table-driven exp (2^(j/128) table,
   about 0.51 ulp) misrounds about 0.14 % of the arguments above, against fdlibm's 10 %. A correctly rounded exp, such as
   CORE-MATH's, would make the polyfill target-independent *and* correct. That is a larger change; the polyfills are a
   1-ulp contract today, so this is an ask, not a bug.
3. Either way, the 6.6.8 contract note could say plainly that the x87 builtins and the polyfills are both
   not correctly rounded (x87 misrounds about 5 % of normal `exp` results above).

## Consumer-side workaround

- **kimiya** will not call `f64_exp` for its chemistry. Its next step (kimiya ADR 0006) puts correctly rounded exp /
  expm1 / ln / log10 / pow in its own `src/mathx.cyr`, double-double, + − × ÷ √ only, the same bits on every target, so it
  doesn't wait on this.
- A consumer that only needs the same bits on every target can call `_f64_exp_polyfill` / `_f64_exp2_polyfill` directly,
  as `lib/math.cyr`'s contract note says. It then gets the same misroundings everywhere.
