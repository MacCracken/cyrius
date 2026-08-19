# Decimal float literals past ~9 significant digits parse to a silently wrong value

**Status:** ✅ **RESOLVED** — shipped in **v6.5.28**. See `CHANGELOG.md` [6.5.28].

> ### ✅ FIXED — root cause was TWO overflows in ONE line
>
> The token packed the literal as a 32/32 rational, `(denom << 32) | (numer & 0xFFFFFFFF)`,
> divided at runtime by `EMIT_FLOAT_LIT`. Both halves overflow: the mask TRUNCATES `numer`
> past 2^32, and `denom << 32` overflows the i64 outright once denom exceeds 2^32 — i.e. more
> than 9 fractional digits. That is why the failure is a *different number* rather than a
> rounding error, and why the threshold sits at ~9 significant digits exactly as filed.
>
> Fixed by widening both fields to full i64 via a lazily-allocated side table (`FLIT_ADD`,
> `src/common/util.cyr`) with the token carrying an INDEX. All **three** `EMIT_FLOAT_LIT`
> implementations — x86, aarch64 and cx — each carried their own copy of the defective
> unpack and were re-pointed together. Verified to **16 significant digits**.
>
> ⚠ **The obvious smaller fix would have been wrong.** Capping the fractional digit count
> keeps the rational inside 32 bits, but it discards the remaining digits *silently* — the
> same defect class one notch quieter — and it fails outright for `100.123456789`, where
> `numer = val*denom + frac` overflows 32 bits regardless of how few fractional digits are
> kept. `tests/tcyr/crossos/float_literal_precision.tcyr` asserts that case specifically so
> the shortcut cannot pass, and it lives in `crossos/` because a Linux-only test would have
> proved only one of the three backends.
>
> Fails CLOSED at the table cap: `FLIT_ADD` returns -1 and the lexer hard-errors rather than
> aliasing slot 0 — the v6.4.75 fn_table lesson, where index-N-aliasing-index-0 was itself a
> silent miscompile. — found while porting ranga's Oklab matrices; worked around in consumer code.
**Placement:** unpinned — 6.5.x backlog. Lexer/parser, not stdlib.
**Discovered:** 2026-08-17 during the ranga (image processing) Rust→Cyrius port, M1 colour module
**Severity:** **High** — silent numerical corruption, no diagnostic, and the affected range is exactly where real physical/colour constants live
**Affects:** cycc 6.5.27 (not bisected further back)

## Summary

A decimal float literal with more significant digits than the lexer handles does not error, does not
warn, and does not saturate — it produces a **different, wrong number**, and compilation succeeds.

```
3.14                 -> 3.14              ✅
3.141592             -> 3.141592          ✅
3.14159265           -> 3.14159265        ✅
3.1415926535         -> 0.95822           ❌ wrong
3.141592653589793    -> 0.061575          ❌ wrong
```

The failure is not a rounding error or a truncation — `3.141592653589793` becomes `0.061575`, off by
a factor of 51. Nothing in the toolchain reports it: `cyrius build` succeeds, `cyrius lint` is clean,
and the program runs and produces plausible-looking output.

This is squarely in the range where real constants live. Colour-space matrices, physical constants,
and anything transcribed from a paper routinely carry 10–17 significant digits.

## Reproduction

```
# lit.cyr
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/math.cyr"

fn p(m) { print(m, strlen(m)); }
fn show(l, v) { p(l); p(" = "); var s = str_from_int(f64_to(f64_mul(v, 100000.0))); print(str_data(s), str_len(s)); p("\n"); }

fn main(): i64 {
    alloc_init();
    show("3.14            ", 3.14);
    show("3.141592        ", 3.141592);
    show("3.14159265      ", 3.14159265);
    show("3.1415926535    ", 3.1415926535);
    show("3.14159265358979", 3.141592653589793);
    show("stdlib F64_PI   ", F64_PI);
    return 0;
}
```

```
$ cyrius run lit.cyr
3.14             = 314000
3.141592         = 314159
3.14159265       = 314159
3.1415926535     = 95822        <-- expected 314159
3.14159265358979 = 6157         <-- expected 314159
stdlib F64_PI    = 314159
```

Exit code 0 throughout. Same result whether the literal is a top-level `var` or a function-local.

## Root cause (if known)

Speculation, flagged as such — I did not read the lexer. The pattern looks like the fractional part
being accumulated into a fixed-width integer that overflows: the results are not truncations of the
intended value (which would still be ≈3.14) but unrelated magnitudes, consistent with a mantissa
accumulator wrapping and then being scaled by a digit-count-derived power of ten.

If that is right, the boundary should be around 10^19 for the accumulated digit string, which fits:
`3141592653` (10 digits) still works, `31415926535` (11) does not.

## Proposed fix

Preference order:

1. **Parse correctly** — accumulate into a wider intermediate, or fall back to a
   correctly-rounded decimal→binary conversion for long literals.
2. **Failing that, reject loudly.** A compile error naming the literal and the supported digit count
   would be entirely acceptable and is strictly better than the current behaviour. Consumers can
   then convert to a bit pattern deliberately.

What should *not* happen is the current silent wrong answer. Note the diagnostic bar here is low:
the lexer already knows how many digits it consumed.

## Consumer-side workaround (if any)

Write anything past ~9 significant digits as a hex bit pattern with the decimal in a trailing
comment — which is what the stdlib already does (`F64_PI = 0x4009_21FB_5444_2D18`, `lib/math.cyr:20`).

```
var _OK_M1_00 = 0x3FDA61D629F2E197;   # 0.4122214708
```

Generated with `struct.unpack('<Q', struct.pack('<d', float(v)))[0]`.

**How it surfaced, for calibration on severity.** ranga's Oklab conversion uses Björn Ottosson's
M1/M2 matrices, whose 18 coefficients all carry 10 significant digits (`0.4122214708`,
`1.9779984951`, …). Written as decimals, converting linear white to Oklab returned a lightness of
**6.447** instead of the definitional **1.0**. There was no error and no warning; it was caught only
because the ported test suite asserts the known white-point identity. A port without that assertion
would have shipped a quietly broken colour space.

ranga now uses hex for those matrices and decimals for its 7–8 digit constants (sRGB/P3 matrices,
Lab thresholds), which are exact and much more legible. The mixed rule is documented in
`ranga/src/color.cyr` and `ranga/docs/development/port-mechanics.md`.
