> **RESOLVED v6.3.40 (f64) + filed to v6.4.x (arrays).** Premise-check found a codec derive
> ALREADY exists — `#derive(Serialize)` emits `Type_to_json`/`Type_from_json`/`_from_json_str`
> covering i8/i16/i32/i64/Str/nested, and the typed `json_v_*` DOM (Tier B) already exists in
> bayan. The real gap was **f64** (emitted undefined `f64_to_json` → hard error) — FIXED in
> v6.3.40 (f64 across all three codec fns; fractional round-trip verified). **Arrays** turned out
> to need a LANGUAGE feature that doesn't exist (`struct { x: T[]; }` doesn't parse — array-typed
> struct fields), so it's filed to **v6.4.x** (roadmap_6.md). The proposal's `#derive(json)`
> typed-DOM variant was deemed unnecessary (would duplicate the existing codec). See CHANGELOG [6.3.40].

# Compile-time struct↔data-format codecs (`#derive(json)` / annotation-driven)

**Filed:** 2026-07-03 during the svara Rust→Cyrius port (L3 — the 101-phoneme
data-table layer + the crate's serde surface).
**Severity:** Language/stdlib gap — Cyrius has no compile-time struct ↔
data-format codec. Every serde-shaped (de)serialization must be hand-written
per field, per type: `Type_set_x(s, json_v_float(json_v_obj_get(o, "x")))` …
repeated for every field of every serializable struct, plus a hand-written
round-trip test.
**Affects:** every ported crate with a serde surface. The migration inventory
flags **90+ repos using serde**. Concretely today: svara (~40 public types that
were `Serialize + Deserialize` in Rust, plus a 101-phoneme × formant/bandwidth/
amplitude/duration/tilt/VOT data table), naad and vidya (both **dropped** their
serde round-trip tests on port because there is no codec).
**Target slot:** a v6.x language feature (extend `#derive`) and/or a `bayan`
stdlib helper set — maintainer direction. Not urgent (the hand-written path
works); this removes a large, mechanical, error-prone tax from every port.

## Trigger

svara's phoneme layer is a 101-entry table — each phoneme maps to F1–F5
frequencies + bandwidths + amplitudes, a default duration, spectral tilt, VOT
timing, and a class tag. In Rust this is a `match` over a `#[derive(Serialize,
Deserialize)]` enum plus struct tables; the crate invariant is *"every public
type is `Serialize + Deserialize` with a round-trip test"* (~40 types).

Cyrius has no serde and no codec derive, so the port must either (a) hand-write
`Type_from_json` / `Type_to_json` for each of the ~40 types, or (b) hand-walk a
parsed data file field-by-field into fixed-layout structs. Either way the
round-trip **tests** vanish — exactly what happened in naad and vidya.

## The problem with the status quo

Data-format support is actually decent at the *parse* layer:

- **JSON** has a typed DOM: `json_v_parse(src)` → tree, then
  `json_v_obj_get(o, key)`, `json_v_arr_get/len`, and typed leaves
  `json_v_int` / `json_v_float` / `json_v_str`. Ergonomic for reading.
- **TOML** is stringly-typed: `toml_parse` → sections + pairs, but `toml_get`
  returns a value you hand-convert (`f64_parse` per numeric field). There is
  **no `toml_v_*` typed DOM** to mirror the JSON one.

But mapping parsed data *into a struct* (and back) is entirely manual:

1. **Per-field boilerplate, per type.** Every field is a hand-written
   `Type_set_field(s, json_v_float(json_v_obj_get(o, "field")))`. A 12-field
   struct is 12 lines in each direction; svara's ~40 types are hundreds of
   lines of purely mechanical code.
2. **Round-trip parity silently lost.** The Rust "every type round-trips + is
   tested" invariant has no cheap equivalent, so ports drop it (naad, vidya).
   That's a correctness regression that no gate catches.
3. **JSON/TOML asymmetry.** Numeric tables in TOML need manual string→f64 per
   field because there's no `toml_v_float`; the same table in JSON is typed.
4. **The machinery already exists — for the wrong output.** `#derive(accessors)`
   *already* walks a struct's field layout at compile time and emits
   `Type_field` / `Type_set_field`. A codec is the same compile-time codegen,
   just emitting parse/build calls instead of load/store.

Note what is **NOT** being asked for: runtime, reflection-based serialization.
That is genuinely impossible under the everything-is-`i64`, no-RTTI design and
should stay out of scope. This proposal is *compile-time* only.

## Proposal

### Tier A — `#derive(json)` reading field type annotations (preferred)

Cyrius already accepts field type annotations (`struct P { f1: f64; name: str;
class: i64; }`) but treats them as documentation. Make them **load-bearing for
codec derive**: `#derive(json)` reads each field's declared type at compile time
(exactly as `#derive(accessors)` reads the layout) and emits

- `P_from_json(objval) -> P*` — `json_v_obj_get` + the type-appropriate leaf
  getter (`json_v_float` for `f64`, `json_v_int` for `i64`, `json_v_str` for
  `str`), and
- `P_to_json(p) -> jsonvalue` — `json_v_obj_new` + `json_v_*_new` per field.

Rules that fall straight out of the existing model:

- A field annotated with a **struct type** recurses (`Q_from_json` / `Q_to_json`).
- An **array** field (`f64[]`, `P[]`) maps to `json_v_arr_*`.
- Field name → JSON key (with an optional `#json_key("…")` override later).
- Composes with `#derive(accessors)` on the same struct.

This is the minimal, elegant hook: it turns the currently-decorative annotations
into something real, needs no RTTI, and reuses the derive infrastructure.
`#derive(cyml)` is the same idea over the CYML/TOML shape (pairs with typed
coercion), pending Tier B.

### Tier B — typed TOML DOM (`toml_v_*`) in `bayan`

A `bayan` stdlib addition mirroring `json_v_*`: `toml_v_parse` → tree, with
`toml_v_float` / `toml_v_int` / `toml_v_str` / `toml_v_arr_*` / `toml_v_table_get`.
Stdlib-only (no language change); closes the JSON/TOML asymmetry so numeric
tables in TOML/CYML extract typed. Tier A's `#derive(cyml)` would target this
DOM.

### Independent bug (file regardless)

`toml_parse_file`'s `Str` results alias a static buffer across calls, forcing a
heap-copy per access. That's a correctness footgun independent of the above.

## Why this is more than cosmetic

- **Systematic across the migration.** 90+ serde-using repos each pay this tax
  and each quietly drops round-trip test coverage. One derive restores the
  invariant everywhere.
- **svara alone:** ~40 hand-written codecs + a 101-row table loader collapse to
  one attribute per type.
- **No new concepts.** It's `#derive(accessors)` aimed at a data format — same
  compile-time path, same flat-layout model.

## Until then

svara ships its numeric data tables as **JSON**, read via the typed `json_v_*`
DOM (typed extraction, no string-parsing), and hand-writes the ~40 type codecs +
round-trip tests, each cross-referencing this proposal. They collapse to
`#derive(json)` when Tier A lands.
