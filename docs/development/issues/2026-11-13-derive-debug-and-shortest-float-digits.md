# No `#derive(Debug)`, and no shortest round-trip float printer — open

**Status:** 🟡 **OPEN** (feature request), verified on cyrius 6.7.18 (x86_64), 2026-11-13.
**Discovered:** 2026-11-13, by pravash's Rust → Cyrius port (M8 part d: Rust's derived `Debug` on 36 public types,
`{:?}` and `{:#?}`).
**Reporter:** pravash 2.0.0 port (conversion ledger L16; `pravash/docs/development/pravash-port-plan.md` §8). impetus
solved the printer half locally first (its port plan's S2, `impetus/src/fmtf.cyr`, ADR 0010 there) and didn't file it.
**Severity:** Low. Nothing is wrong; a port carries the derive and the printer by hand meanwhile.

## Summary

Two gaps, met together whenever a Rust type's `Debug` text is ported:

1. **`#derive` has no `Debug`.** The derives are `Serialize`, `Deserialize`, `accessors`, `json` and `cyml` (the
   guide's *Derive* section). pravash writes a `debug(sb, alternate)` by hand for each of 35 types: 949 lines in
   `pravash/src/debug.cyr`, every one of them the same few shapes.
2. **The stdlib can't print a float as Rust, Python, JavaScript or serde_json do.** `fmt_float_buf` prints a fixed
   number of decimals, and bayan's Grisu2 round-trips but isn't always shortest. The shortest digits that read back,
   the closest of them, are what every `{:?}`, `{}` and JSON writer of those languages prints.

## What the derive would generate

Core's builders, as pravash pins them (`pravash/tests/golden/debug.tsv`, 9,602 rows against rustc 1.99.1, all
matching):

| Rust | `{:?}` | `{:#?}` |
|---|---|---|
| a struct | `Name { a: 1.0, b: 2 }` | `Name {\n    a: 1.0,\n    b: 2,\n}` |
| a unit struct | `Name` | `Name` |
| a tuple struct | `DVec3(1.0, 2.0, 3.0)` | `DVec3(\n    1.0,\n    2.0,\n    3.0,\n)` |
| a `Vec` or an array | `[1.0, 2.0]`, `[]` | one element a line, each with `,`; `[]` |
| a unit variant | `Laminar` | `Laminar` |
| a variant with fields | `PowerLaw { consistency: 0.5, power_index: 0.8 }` | as a struct |
| a bool, an integer | `true`, `42` | the same |

In the pretty form a nested value's lines are indented four more spaces (core's `PadAdapter`). A float is Rust's
shortest text (below); an f32 is printed as an f32, with its own digits and thresholds.

## The float printer Rust's `Debug` uses

- the shortest digits that parse back to the same value, the closest to the exact value among them, and on an exact
  tie between two closest candidates the upper one (core's Grisu with a Dragon fallback: 2^-25 is
  `2.9802322387695313e-8`; serde_json's zmij takes the even one, `…5312e-8`);
- positional with at least one fractional digit (`1.0`, `0.0001`, `9999999999999998.0`), except a nonzero value
  below 1e-4 or from 1e16, which is `d.ddde<exp>` with no `+` (`1e16`, `9.999999999999999e-5`, `5e-324`);
- `NaN` (never signed), `inf`, `-inf`, `-0.0`.

## Ask

- **`#derive(Debug)`** on a struct (the field types the JSON derive takes, plus nested derived structs and tuples) and
  on an enum (its variant names), writing Rust's two forms onto a `str_builder` and returning -1 when it can't grow:
  `T_debug(p, sb, alternate)`, say. A data-carrying variant can wait for the tagged shapes of
  `2026-11-11-derive-json-no-vector-array-or-tagged-variant-shapes.md`.
- **A shortest round-trip printer** in the stdlib, f64 and f32: the digits and decimal exponent, with the tie rule a
  parameter (Rust's core rounds up, serde_json's zmij to even), and the forms above. Ryu or Schubfach would be far
  faster than the exact bignum search the ports use (numbers below).

## Notes from the consumer (pravash M8 part d, 2026-11-13)

pravash's stand-ins are `src/fmtf.cyr` (impetus's Burger & Dybvig printer with the f32 case added and every write
returning 0 or -1) and `src/debug.cyr` (the builders and the 35 types), ledger L16. The golden rows are 6,871 f64 and
2,565 f32 printings (the specials, every power of ten and of two with their neighbours, eight steps either side of
both thresholds, and seeded sweeps), 156 values of the 35 types, and 10 states after their own solver steps; pravash's
`validate.py` recomputes every one in Python.

Pinned to one core, two interleaved rounds, against rustc 1.99.1:

| Row | Rust | Cyrius | |
|---|---|---|---|
| `{:?}` of 8 f64s, positional and exponential, one at the subnormal edge | 0.59 µs | 32 µs | 54× |
| `{:?}` of a particle (17 floats, 11 of them 0.0) | 0.92 µs | 5.9 µs | 6.4× |
| `{:#?}` of the same | 2.2 µs | 8.2 µs | 3.8× |
| `{:?}` of an 8 × 8 fluid grid after a step (≈ 650 floats) | 39 µs | 1.25 ms | 32× |

The digit search is the cost: B&D scales the value by 10^k on a 40-limb bignum and divides by repeated subtraction.
A stdlib printer would replace `src/fmtf.cyr`, and the derive the hand-written `debug` methods, with the 9,602 rows
re-run.

## Also needed: pramana (2026-11-15, cyrius 6.7.18)

pramana 1.3.0 derives `Debug` on 38 types, and its port carries it (its decision D12). It needs both float forms the
ask above names:
- serde_json's text for JSON (its D5);
- Rust's `{}` / `{:?}` for `Debug` and `Display`.

Its probe P7 (`pramana/docs/development/port-parity.md` §6.3) checked impetus's `fmtf.cyr` on 280,562 doubles (every
f64 in its base values, the powers of two and ten with their neighbours, the integers to 1,000, 100,000 random bit
patterns, 50,000 short decimals; both signs):
- its serde_json form equals serde_json's text on all of them;
- its Display form equals Rust's `{}` on all of them;
- bayan's Grisu2 differs from serde_json's on 9,714.

pramana vendors one `src/fmtf.cyr` with both forms (impetus's digit core, pravash's Debug form), plus pravash's
`debug(sb, alternate)` builders, as ledger L10. It converts to the stdlib printer and `#derive(Debug)` with its JSON
text rows and `Debug` rows re-run.
