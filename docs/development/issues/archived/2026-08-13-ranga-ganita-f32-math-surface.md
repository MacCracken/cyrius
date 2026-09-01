# ganita has no f32 math surface — every f32 consumer widens to f64 and narrows back

**Status:** ✅ **RESOLVED — ALL THREE TIERS SHIPPED at v6.5.24 (ganita 1.1.0).**

> **✅ ALL THREE TIERS SHIPPED — ganita 1.1.0, folded at cyrius v6.5.24. 23 `ganita_f32_*` fns, api-surface 4843 -> 4866 (+23).** Tier 1: ten helpers
> in the new `src/math_f32.cyr`: `_abs`, `_neg`, `_sign` (pure bit ops), `_min`, `_max`,
> `_clamp` (one signed compare on a monotone key), `_lerp`, `_floor`, `_ceil`, `_trunc`.
> api-surface 4843 -> 4853 (+10, no accidental surface). **MINOR bump, not a patch** — new
> public API. Fixed UPSTREAM first per CLAUDE.md, then re-vendored; the toolchain pin also
> went 6.4.69 -> 6.5.23 (it was 15 patches behind and warning).
>
> ⚠ **THIS FILING'S OWN HINT WAS THE TRAP.** It says "for non-negative finite f32 the raw
> 32-bit pattern orders identically to an unsigned integer, so min/max/clamp are integer
> compares". True — and precisely why a naive implementation is dangerous: IEEE-754 is
> SIGN-MAGNITUDE, so for two NEGATIVES the order REVERSES and any negative compares HIGH
> against every positive. Pixel data is non-negative, so the naive version passes every
> plausible test and breaks the first time a consumer subtracts. Shipped with the standard
> monotone-key transform and verified on the both-negative and mixed-sign cases.
>
> ⚠ **`ganita_f32_lerp` WIDENS, and not by choice:** there is no callable `f32_add` /
> `f32_sub` / `f32_mul`. cyrius dispatches f32 arithmetic through the OPERATORS on an
> `F32_TYID`-typed value (`EMIT_F32_BINOP`), reachable only from a `var x: f32` binding —
> and library params arrive as untyped bit patterns. A first cut called `f32_add(...)` as a
> builtin; `cyrius distlib` caught it as `undefined function`. **That is a real adjacent
> gap: the f32 tier cannot be written in native f32 arithmetic today.**
>
> ⭐ **Its dependency was discharged in the same release.** This tier was GATED on
> `2026-08-13-f64-typed-binding-reassign-warns-as-pointer` — `F32_TYID` (0x40000002) is
> positive, so `lt > 0` at `parse.cyr:1498` counted every f32 local as a typed pointer.
> Shipping f32 helpers first would have made every f32 accumulator in every consumer emit a
> bogus warning. Guard landed at v6.5.24 ahead of this.
>
> **Tier 2** — `ganita_f32_sqrt`. ⚠ The requested `sqrtss` needs a NEW cyrius intrinsic (a
> compiler change, not a library one), so this widens — and it is **correctly rounded, not
> approximate**: f64's 53 mantissa bits exceed 2*24 + 2, so double-then-single rounds to
> exactly the single result. **`sqrtss` intrinsic = cyrius-side follow-up.**
>
> **Tier 3** — `_exp`, `_ln`, `_log2`, `_exp2`, `_sin`, `_cos`, `_atan`, `_round`, `_pow`,
> `_atan2`, `_hypot`, `_cbrt`. Widen-compute-narrow, which this filing explicitly blesses.
> ⚠ `_cbrt` splits on sign because it is built from `pow` (`exp(y*ln x)`) and `ln` of a
> negative is undefined — a bare pow is garbage for negatives while looking fine for the
> positives a naive test uses. Verified -8 -> -2.
>
> ⛔ **PROCESS NOTE, recorded deliberately.** A first cut shipped TIER 1 ONLY and framed
> tiers 2-3 as "interleaved fold-ins". That was a **silent deferral of an enumerated
> consumer surface** — CLAUDE.md: "a consumer filing enumerates the FULL surface they need;
> shipping a subset is a silent deferral." The filing's tiering said *suggested, cheapest
> and highest-value first* — a sequencing hint, NOT permission to ship a third and close
> the slot. The maintainer caught it. All three tiers are in 1.1.0.
>
> **Genuinely remaining, and cyrius-side not ganita-side:** the `sqrtss` intrinsic, and the
> two adjacent gaps this filing noted for context — no f32 **literal** form, and no f32
> function **return-type** sentinel (f32 params type but returns come back untyped). Also
> newly found: **there is no callable `f32_add`/`f32_sub`/`f32_mul`**, so no f32 tier can
> be written in native single-precision arithmetic today. — surfaced while planning the ranga (image processing) Rust→Cyrius port.
**Placement:** **Split — do NOT bounce the whole thing to ganita.** Tier 1 (f32 scalar helpers) rides **v6.5.24 — band C**, in the same bite-cluster as the typed-binding guard it depends on. Tiers 2–3 are interleaved reactive fold-ins.

> **⟳ Re-stamped 2026-08-14 at v6.5.21 (backlog re-triage).** Gap verified UPSTREAM as well as in the fold, per the fix-the-source-repo rule. ⚠ GATED ON `2026-08-13-f64-typed-binding-reassign-warns-as-pointer`.
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

---

## ⟳ AMENDED 2026-09-01 — the "no native f32 tier is possible" residual was WRONG

This filing closed with:

> **Genuinely remaining, and cyrius-side not ganita-side:** ... Also newly found:
> **there is no callable `f32_add`/`f32_sub`/`f32_mul`**, so no f32 tier can be written
> in native single-precision arithmetic today.

The first clause is true. **The conclusion drawn from it is not, and it cost ganita a
release.** `ganita_f32_lerp` shipped widen-compute-narrow for three releases on the
strength of that sentence, and the module header repeated it as settled fact.

The reasoning was: f32 arithmetic is reachable only from a `var x: f32` binding, "and
these params arrive as untyped i64 bit patterns". A parameter can simply **be typed**:

```
fn ganita_f32_mul(a: f32, b: f32): i64 {
    var s: f32 = a * b;
    return s;
}
```

Typed params put the incoming pattern in an xmm lane as a single, `var s: f32` emits the
single-precision op, and returning `s` as `i64` hands the bit pattern back unchanged.
Verified on cycc 6.5.36: `ganita_f32_add(2^24, 1.0)` returns `0x4B800000` (2^24, ties-to-
even) where an f64 accumulator gives 2^24+1 — native, not widened. `cyrius distlib`
accepts the typed params in a bundle. **Shipped as ganita 1.2.0** (`_add` / `_sub` /
`_mul` / `_div`, and `_lerp` rebuilt on them).

### What is actually still missing, cyrius-side

1. **No f32 function RETURN type.** `fn f(): f32` is rejected —
   *"fn return type must be struct or i8/i16/i32/i64/Result/Option/Tagged/cstring/f64/f64v2/f64v4"*.
   Params type; returns do not. Harmless for a bit-pattern library API (the pattern is the
   interchange form anyway), but it makes the asymmetry a trap: an author who tries the
   obvious `fn f(a: f32, b: f32): f32` hits an error whose message does not hint that
   dropping the return type to `i64` works. **This is very likely what produced the wrong
   conclusion above** — the first attempt fails, and it reads as "f32 is not usable here".
2. **No `sqrtss` intrinsic** — `ganita_f32_sqrt` still widens. Correctly rounded (53 > 2·24+2),
   so this is a cost item, not an accuracy one.
3. **No f32 literal form** — f32 constants must be built via `f32_from(f64_from(n))`.

Item 1 is the one worth fixing: the error message should name `i64` as the way to return an
f32 pattern, or `f32` should be accepted as a return type. Either would have prevented this.
