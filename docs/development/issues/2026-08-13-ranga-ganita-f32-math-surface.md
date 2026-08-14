# ganita has no f32 math surface — every f32 consumer widens to f64 and narrows back

**Status:** 🟡 **OPEN** — surfaced while planning the ranga (image processing) Rust→Cyrius port.
**Placement:** unpinned — ganita 1.x backlog. Belongs in **ganita**, not cyrius core.
**Discovered:** 2026-08-13 during the ranga → Cyrius port capability audit
**Severity:** Medium — hard requirement with a known workaround; costs 2 conversions per call in a per-pixel hot path
**Affects:** cycc 6.5.21, ganita 1.0.4 (as folded into `lib/ganita.cyr`)

## Summary

Scalar f32 **arithmetic** is well supported — v6.4.56 gives real `addss`/`subss`/`mulss`/`divss`
plus a NaN-correct `ucomiss` compare ladder across all four backends, and `f32_from`/`f32_to` are
native conversion builtins. But there is **no f32 math library at all**:

```sh
$ grep -c f32 /home/macro/Repos/cyrius/lib/math.cyr /home/macro/Repos/cyrius/lib/ganita.cyr
/home/macro/Repos/cyrius/lib/math.cyr:0
/home/macro/Repos/cyrius/lib/ganita.cyr:0
```

Zero. So any consumer doing f32 math has native `+ - * /` but must round-trip through f64 for
every `sqrt`, `pow`, `cbrt`, `exp`, `ln`, `sin`, `cos`, `atan2`, or `hypot`:

```
# what an f32 consumer writes today for a single powf
var r = f32_from(ganita_f64_pow(f32_to(x), f32_to(e)));
```

Two conversions plus a double-precision transcendental for a value that only ever needed single
precision. In an image-processing inner loop this is per-pixel, per-channel.

The asymmetry is the point: the language treats f32 as a first-class arithmetic type but the math
library only knows f64. A consumer reaching for f32 to halve their working set finds the math
surface pulls them straight back to f64.

## Reproduction

No crash — this is a missing-surface report, not a bug. The observable is the `grep -c` above
returning `0` for both modules while `lib/simd.cyr` exposes a complete `f32v4`/`f32v8` lane surface
and the compiler exposes scalar f32 ops. There is no `f32_sqrt`, `f32_pow`, `f32_min`, `f32_max`,
`f32_clamp`, `f32_lerp`, `f32_floor`, `f32_abs` — nor any `ganita_f32_*`.

Consumer that hit it: **ranga** (image processing — colour spaces, blend modes, filters), whose
Rust implementation is f32 throughout for colour science (Lab, Oklab, XYZ, Delta-E) and carries an
`RgbaF32` pixel format. See `ranga/docs/development/cyrius-port-plan.md` §3 item 1.

## Root cause (if known)

Not a bug — a scope boundary. `lib/math.cyr` (618 lines) and `lib/ganita.cyr` (1401 lines) were both
built for the f64 numeric consumers that came first (hisab, prakash, abaco), none of which needed
single precision. Nothing in the design precludes an f32 tier; it simply was never asked for.

Speculation, flagged as such: a fair amount of it is mechanical. `f32_min`/`f32_max`/`f32_clamp`/
`f32_abs`/`f32_floor`/`f32_sign` can be done on the bit pattern directly without touching f64 at all,
and `f32_sqrt` has a direct `sqrtss` encoding — so the cheap half of the surface needn't be a
widen-narrow wrapper.

## Proposed fix

**Placement: ganita, not cyrius core.** This is advanced-math surface, matching how
`ganita_f64_pow`/`_atan2`/`_asin`/`_hypot` already live there rather than in `lib/math.cyr`.

Suggested tiering, cheapest and highest-value first:

1. **Bit-pattern ops — no f64 round-trip.** `f32_abs`, `f32_neg`, `f32_min`, `f32_max`, `f32_clamp`,
   `f32_sign`, `f32_floor`, `f32_ceil`, `f32_trunc`, `f32_lerp`. For non-negative finite f32 the raw
   32-bit pattern orders identically to an unsigned integer, so min/max/clamp are integer compares.
2. **`f32_sqrt` via `sqrtss`** — direct single-precision encoding, no widening.
3. **Transcendental tier** — `ganita_f32_pow`, `_exp`, `_ln`, `_sin`, `_cos`, `_atan2`, `_hypot`,
   `_cbrt`. Widen-compute-narrow internally is completely acceptable here; the win is that the
   conversions stop being the consumer's problem and the naming stays symmetric with the f64 tier.

If only one thing lands, tier 1 is the one — it is the part that is genuinely wasteful today
(three ops per lane for what should be one integer compare) and it needs no new numerics.

Two smaller adjacent gaps noticed in the same audit, listed for context rather than as asks:
there is no f32 **literal** form (f32 constants are built via `f32_from(f64_from(n))`), and no f32
function **return-type** sentinel — f32 params are typed but returns come back untyped.

## Consumer-side workaround (if any)

ranga is shipping a local `ranga_f32_*` shim (~80 lines) that wraps the widen-narrow pattern once so
call sites stay readable, and using the IEEE-monotonicity integer-compare trick for min/max/clamp on
its normalised `[0,1]` channels. Documented in `ranga/docs/development/cyrius-port-plan.md` §3.

That shim is explicitly a stopgap. If a `ganita_f32_*` tier lands, ranga drops the shim and moves
over — and the other AGNOS graphics consumers (soorat, rasa, tazama, aethersafta) would pick it up
rather than each re-rolling the same eighty lines.
