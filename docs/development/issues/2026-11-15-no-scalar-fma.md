# No scalar fused multiply-add: correctly rounded code that relies on fma must emulate it, at 6.5–20× the cost — open

**Status:** 🟡 **OPEN** (feature request) — verified on cyrius 6.7.18 (x86_64), 2026-11-15: no scalar fma in the stdlib
or in ganita.
**Discovered:** 2026-11-15, by pramana's Rust → Cyrius port (M0 step 9e, the FMA-free port of CORE-MATH's erf and erfc;
`pramana/docs/development/port-parity.md` §6.7).
**Reporter:** pramana 2.0.0 port (conversion ledger L12; `pramana/docs/development/pramana-port-plan.md` §10).
**Severity:** **Medium.** Nothing computes wrong: an exact emulation exists. But it costs most of the time of every
correctly rounded function written for an fma, and the subnormal case needs special handling.

## Summary

The correctly rounded libraries the AGNOS ports draw on (CORE-MATH; the double-double kernels kimiya and pramana use)
are written for `fma(a, b, c)`: a·b + c with one rounding. It serves two ways:
- **the exact error of a product:** `lo = fma(a, b, −a·b)`;
- **a single rounding** in Horner steps, double-double products and exp reductions, which the published error bounds
  assume.

Cyrius has neither a scalar builtin nor a stdlib function for it. The nearest, `f64v_fmadd` (`lib/simd.cyr`), is not
one:
- on x86_64 it is `mulpd` + `addpd`, two roundings, deliberately, since FMA3 is a separate CPUID bit
  (`src/backend/x86/float.cyr:837`);
- on aarch64 it is `fmla`, one rounding.

So it gives different bits on the two targets for the same inputs.

pramana ported CORE-MATH's binary64 erf and erfc with an exact emulation:
- the product is computed exactly by Dekker's algorithm with Veltkamp's split (about 17 flops);
- RN(p + e + c) is then computed exactly by Boldo and Melquiond's round-to-odd sum (kimiya's `_km_rn3`).

It is exact whenever the product's error is representable. The one exception in those two files, erf's tiny path
`fma(l, 0x1p-106, y)`, whose product can fall below the subnormal grid, needed its own exact rounding.

The emulation is correct: the port gives CORE-MATH's own bits on all of its worst cases and 2.77 million more
arguments, the same on x86_64, PE and aarch64. It is also most of the cost. Measured in C on the same source, and
the Cyrius port beside it, pinned (ns per call):

| Region | CORE-MATH, hardware FMA | the same, fma emulated | glibc | the Cyrius port |
|---|---|---|---|---|
| erf, x ∈ [1e-4, 1/16) | 5.7–6.1 | 114.6–116.0 | 21.6–22.6 | 555–560 |
| erf, x ∈ [1/16, 5.9) | 10.5–10.9 | 91.9–94.3 | 29.1–30.2 | 604–610 |
| erfc, x ∈ (−5.8, 0) | 12.4–12.6 | 82.0–84.2 | 27.3–28.0 | 508–511 |
| erfc, x ∈ [0, 2.88] | 15.8–16.3 | 108.0–110.1 | 34.4–37.4 | 667–675 |
| erfc, x ∈ [2.9, 25.8] | 37.3–37.6 | 413.9–425.8 | 72.8–75.6 | 2,259–2,279 |

So the emulation alone makes CORE-MATH 6.5–20× slower.

## Reproduction

[`repros/2026-11-15-no-scalar-fma.cyr`](repros/2026-11-15-no-scalar-fma.cyr), from the repo root:

```sh
cyrius build docs/development/issues/repros/2026-11-15-no-scalar-fma.cyr /tmp/fma
# warning: undefined function 'f64_fma' (reachable call site)
# error: refusing to emit binary with 1 reachable undefined function(s)
```

With a = 1 + 2⁻³⁰, b = 1 − 2⁻³⁰ and c = −1, `a * b + c` gives 0, where one rounding gives −2⁻⁶⁰. Once `f64_fma`
exists, the repro builds and exits 0 when it returns −2⁻⁶⁰.

## Ask

**`f64_fma(a, b, c)`**: RN(a·b + c) with one rounding, for every input, subnormal products included.
- Emit the hardware instruction where the target has it (x86_64 FMA3 `vfmadd231sd`, aarch64 `fmadd`).
- Fall back to an exact software fma elsewhere: musl's integer `fma.c`, or the Dekker plus round-to-odd form above
  with the subnormal case handled.

Both give the same bits, since an fma is correctly rounded, so every target stays deterministic.

## Meanwhile

pramana's stand-in is the exact emulation in its `src/crmath.cyr` (from M2): `_km_two_prod` and `_km_rn3`, and the
tiny-path rounding, marked `UPSTREAM(L12)`. It converts to `f64_fma` with its erf, erfc and `normal_cdf` rows re-run;
the bits must not change.
