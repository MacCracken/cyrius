# `#derive(Serialize)` can't write serde's array form for a vector struct or its tagged form for a data-carrying variant — open

**Status:** 🟡 **OPEN** (feature request) — checked against cyrius 6.7.18's guide ("Derive Serialize on a struct / an
enum"), 2026-11-11.
**Discovered:** 2026-11-11, by pravash's Rust → Cyrius port (the language review, its port plan §1.1). impetus needed
the same shapes and hand-wrote its codecs (its ADR 0010; its port plan §8, "Derive features for serde-shaped JSON",
not filed).
**Reporter:** pravash 2.0.0 port (conversion ledger L10; `pravash/docs/development/pravash-port-plan.md` §8).
**Severity:** **Low–medium.** Ports read and write the JSON Rust programs already produce, so each hand-writes the
codecs for these two shapes.

## Summary

pravash carries serde on 22 types (its decision D4), so its Cyrius library must decode, bit for bit, the documents
serde_json writes from them. `#derive(Serialize)` / `#derive(Deserialize)` covers most of them. Two shapes it can't
express:

1. **A vector struct as a JSON array.** glam's `DVec3` serializes as `[x, y, z]`. A Cyrius struct `PvV3 { x: f64;
   y: f64; z: f64; }` derives as `{"x":…,"y":…,"z":…}`, so every particle, body and config with a vector field
   (`FluidParticle.position`, `.velocity`, `.acceleration`; `RigidBody`; `FluidConfig.gravity`, `.bounds_*`) needs a
   hand codec.
2. **A data-carrying enum variant, externally tagged.** serde writes `ConstitutiveModel::NeoHookean { youngs_modulus,
   poisson_ratio }` as `{"NeoHookean":{"youngs_modulus":…,"poisson_ratio":…}}` and a unit variant as `"Fluid"`. The
   derive does the unit variant (a name string), but a variant with fields can't be derived (and a `: stack` enum
   carries one field at most). pravash's cases are `ConstitutiveModel`, `BodyShape` and `BoundaryCondition`.

## Ask

1. **An attribute that serializes a struct as an array of its fields in order**, e.g.
   `#derive(Serialize, array)` (serde's tuple-struct form), with the matching decoder.
2. **Externally tagged variants**: for an enum declared as a kind plus a payload struct (the shape ports use, since
   boxed variants allocate), a way to derive `{"<Variant>": <payload object>}`. That could be an attribute naming the
   payload struct per variant, or derive support for a tagged union.

Until then pravash hand-writes these codecs in `src/json.cyr` as marked stand-ins, and converts when the derive covers
them. Its JSON rows (decode the oracle's documents to the same bits, then round-trip) must come out unchanged.

## Also measured: ushma (2026-11-11, cyrius 6.7.18)

ushma's port ran `#derive(Serialize)` on three of its 28 serde types (StatePoint, ThermalMaterial, Phase) against
serde_json 1.0.154's own documents (`ushma/docs/development/port-parity.md` §3, probe 11). It found two more shapes
a port needs, besides the vector-array and tagged-variant ones above.

- **Variant names differ from the constants.** Enum members are global, so a library prefixes them
  (`US_PHASE_SOLID`), and the derived codec writes and reads that name: `"US_PHASE_SOLID"`. serde writes `"Solid"`,
  and the derived reader can't read it. A per-variant rename, or a prefix to strip (`#derive(Serialize,
  strip_prefix = "US_PHASE_")`), would cover every prefixed library.
- **The sequence form.** serde accepts a struct written as an array, its fields by position
  (`[300.0,101325.0,…]`); the derived reader returns 0.
- **Smaller:**
  - a variant name over 31 bytes is a compile error (`#derive field name too long (max 31 bytes)`);
  - the f64 text is bayan's printer, not serde's (`9223372036854776000.0` against `9.223372036854776e+18`);
  - the decoders accept documents serde refuses: truncated, trailing data, a BOM, trailing commas, duplicate and
    missing fields, `null`, NaN and Infinity, `1e400`, leading zeros, `+1.5`, `.5`, `1.`, and a string or bool for an
    f64. That is 49 of 51 disagreements; `2026-11-11-derive-writer-faults-on-a-zero-str-field.md` files the one
    that faults.

ushma hand-writes its codecs on bayan's tree for now (its ADR 0005), as impetus and pravash do.

## Also needed: pramana (2026-11-15, cyrius 6.7.18)

pramana serializes 38 types (its decision D5) and validates 20 on deserialize, through serde's `try_from`, which runs
the type's validating constructor: a `Normal` with σ ≤ 0 is refused, not built. Its probe P7 decoded 1,495 documents
serde_json 1.0.154 wrote (`pramana/docs/development/port-parity.md` §6.3). Beyond the shapes above, the derive would
need three things before pramana could use it:
1. **A validation hook:** the decoder hands the decoded fields to a named constructor and returns its refusal code,
   e.g. `#derive(Deserialize, validate = PmnNormal_new)`. Without it, every validated type needs a hand codec
   anyway.
2. **Matrices:** 15 `Vec<Vec<f64>>` fields (covariance, transition and emission matrices), which serde writes as
   `[[…],[…]]` and pramana stores flat, row-major, with their dimensions. A matrix form over `(ptr, rows, cols)`
   would cover them.
3. **u64 fields:** the RNG's state, Binomial's `n` and the histogram's counts. 13 of P7's 35 saved RNG states are above
   2⁶³, which bayan's tree refuses today (`bayan:docs/development/issues/2026-11-09-json-integer-above-i64-max-refuses-the-document.md`).

pramana writes serde_json's float text byte for byte, through impetus's `fmtf.cyr` (its D5 as amended), not bayan's
Grisu2, which differs on 9,714 of 280,562 doubles. Until the derive covers these, pramana hand-writes its 38 codecs
over bayan's tree in `src/json.cyr` (ledger L7, `UPSTREAM(L7)`), as impetus, pravash and ushma do.
