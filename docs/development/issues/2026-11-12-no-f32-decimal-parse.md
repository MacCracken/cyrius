# No f32 decimal parse: `f32_from(f64_parse_n(..))` rounds twice, and a reader can't get serde's f32 — open

**Status:** 🟡 **OPEN** (feature request), verified on cyrius 6.7.18 (x86_64), 2026-11-12.
**Discovered:** 2026-11-12, by pravash's Rust → Cyrius port (M7 part a: the f32 fields of `SphKernelParams`,
`GridKernelParams` and `ShallowKernelParams`, which pravash's JSON reads as serde_json does).
**Reporter:** pravash 2.0.0 port (conversion ledger L15; `pravash/docs/development/pravash-port-plan.md` §8). The
companion request at bayan: `bayan:docs/development/issues/2026-11-12-json-tree-number-keeps-no-source-text.md`.
**Severity:** Low. Every value that serde_json, C's `strtof` or numpy writes for an f32 reads back right; the
difference is confined to decimals within half an f64 ulp of an f32 midpoint, and to integers past 2^53.

## Summary

The stdlib parses decimals to f64 only (`f64_parse`, `f64_parse_n`, correctly rounded). A reader that wants an f32
takes `f32_from(f64_parse_n(s, n))`, which rounds twice: decimal → f64, then f64 → f32. That equals the f32 nearest
the decimal except when the f64 lands **exactly on an f32 midpoint**. Every midpoint is itself an f64, so it's the only
place the two roundings can disagree, and there the tie goes to even instead of to the decimal's side:

| Input | `f32_from(f64_parse_n)` | f32 nearest the decimal (serde_json `float_roundtrip`, `strtof`) |
|---|---|---|
| `1.0000000596046448` (its f64 is 1 + 2^-24, the midpoint above 1; the decimal lies above it) | `0x3F800000` (1.0) | `0x3F800001` |
| `3.4028235677973366e38` (its f64 is 2^128 − 2^103, the overflow midpoint; the decimal is below) | `0x7F800000` (+∞) | `0x7F7FFFFF` (f32::MAX) |
| `1152921573326323713`, an integer (`f64_from` gives 2^60 + 2^36, a midpoint) | `0x5D800000` | `0x5D800001` |

The first input is the shortest f64 digits of the midpoint, the form an f64 printer writes for it. The second
decides between a value and an overflow: serde_json refuses a decimal that rounds to ±∞ as an f32 (`number out of
range`) and reads this one as f32::MAX.

## Reproduction

[`repros/2026-11-12-no-f32-decimal-parse.cyr`](repros/2026-11-12-no-f32-decimal-parse.cyr), from the repo root:

```sh
cyrius build docs/development/issues/repros/2026-11-12-no-f32-decimal-parse.cyr /tmp/f32p
/tmp/f32p; echo "exit=$?"
# 1.0000000596046448: f32_from(f64_parse) 0x3f800000, nearest f32 0x3f800001
# 3.4028235677973366e38: f32_from(f64_parse) 0x7f800000, nearest f32 0x7f7fffff
# 1152921573326323713 (i64): f32_from(f64_parse) 0x5d800000, nearest f32 0x5d800001
# exit=1
```

## Ask

- **`f32_parse_n(s, n)`**: the f32 nearest the decimal in s[0..n) (ties to even), as its pattern, with
  `f64_parse_n`'s grammar and bounds. The f64 parser's tiers carry over: tier 1's exact fast path with f32's
  10^0 … 10^10, tier 2's window, and tier 3's exact decimal reading off 24 bits instead of 53 (Go's
  `decimal.floatBits(&float32info)`).
- **An exact `i64` → f32**, or a note that `f32_from(f64_from(n))` rounds twice past 2^53 (`cvtsi2ss` does it in one
  instruction on x86_64; `scvtf` on aarch64).

## Notes from the consumer (pravash M7 part a, 2026-11-12)

pravash's stand-in is `_pv_jr_f32` in `src/json.cyr` (ledger L15). It takes RN32 of bayan's correctly rounded f64,
and only when that f64 is an f32 midpoint does it compare the document's decimal with it exactly. That's a 32-bit-limb
bignum over at most 800 kept digits, with a sticky "nonzero digit follows", and it needs the number's text, which
bayan's tree doesn't keep (the companion request). Pinned to one core, a 7-field `SphKernelParams` document reads in
5.9 µs, and 7.4 µs when one field is a midpoint, against serde_json's 231 ns and 261 ns. Integers round exactly from the
i64. The parity rows are 95 serde_json readings in `tests/golden/compute.tsv` (class A): midpoints written exactly,
their shortest f64 digits, the subnormal midpoints 2^-150 and 3·2^-150, the overflow threshold, integers next to a
midpoint, and digit runs past 800. A stdlib `f32_parse_n` over the number's span would replace the midpoint step, with
those rows re-run.
