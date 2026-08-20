# `#derive(Serialize)` / `#derive(Deserialize)` on an enum — generate the codec

**Status:** ✅ **RESOLVED** — shipped in **v6.5.31**. See `CHANGELOG.md` [6.5.31].

> ⚖️ **Decisions taken by the maintainer 2026-08-19**, which is what unblocked this:
> **name string** for the wire shape (`"Multiply"`) and **`Result`** for the parse side. The
> number form was rejected as ambiguous — a JSON consumer cannot tell it from any other
> integer field. Tagged objects were rejected because a struct's field key already names the
> type, so the tag only restates it: `{"fmt":"RGBA8"}` rather than
> `{"fmt":{"PixelFormat":"RGBA8"}}`.
>
> Both directions shipped, which is what ranga needed — the parse side is the half it could
> not emulate. `E_to_json(v, sb)` writes the quoted name (`null` for an unrecognised value, so
> the surrounding document stays valid JSON); `E_from_json_str(json)` returns `Ok(value)` /
> `Err(-1)` and accepts either a quoted JSON value or a bare name.
>
> ⭐ **Smaller than the sketch predicted.** The member-name collection needed NO enum-specific
> code: an enum body walks the same copy loop as a struct, so `A` and `B` land in the
> field-name table exactly as struct fields do. The only parser differences were the keyword
> width (5 vs 7) and a flag selecting the codec shape. The generated code compares against the
> enum CONSTANTS rather than baked-in numbers, so renumbering cannot desynchronise it.
>
> ⛔ **One pre-existing defect surfaced while wiring this and is fixed here too:** a bare
> `#derive(Deserialize)` emitted NOTHING — on **structs** as well as enums — because the codec
> body was only reached when `Serialize` happened to be stacked with it. Same silent-no-op
> family, one directive away, and fixing it only for enums would have left the struct half
> still silent.
The silent-no-op half was closed at v6.5.30: a derive on a non-struct is now rejected with a
diagnostic naming the enum. What remains is generating the codec.
**Placement:** unpinned — 6.5.x backlog. Derive expansion (`src/frontend/lex_pp.cyr`).
**Severity:** Feature. No silent failure remains; consumers get a clear error and a workaround.
**Requested by:** ranga (M7 parity audit, 2026-08-19) — hand-writes four enum codecs today
(`PixelFormat`, `BlendMode`, `ColorSpace`, one payload enum).

## What the consumer needs

Both directions. The Display side is the smaller half and ranga already emulates it
(`pixel_format_name` / `blend_mode_name`); the **parse** side is absent entirely and is
recorded in ranga's audit as a real gap against the Rust line — Rust's `FromStr` turns
`"Multiply"` back into a `BlendMode`, and the port cannot.

- `E_to_json(v, sb)` — the 2-arg composable form the struct codecs already use.
- `E_from_json_str(s)` — value from name, with a defined failure result.

## ⚖️ The decision owed — the JSON wire shape

A C-like enum is an integer with names, so a codec can legitimately emit any of:

1. **Name string** — `"Multiply"`. Human-readable, matches Rust's `Serialize` default for
   unit variants, and is what makes `FromStr` round-trip meaningful. Costs bytes and breaks
   if a variant is renamed.
2. **Number** — `3`. Compact and matches the underlying representation, but a JSON consumer
   cannot tell it from any other integer field, and renumbering silently changes the wire
   format.
3. **Tagged object** — `{"BlendMode":"Multiply"}`. Self-describing, verbose, and inconsistent
   with how the struct codecs emit their fields today.

**This is not a detail that can be picked and changed later**: the format is the wire contract
the moment a consumer ships anything persisted or transmitted. Getting it wrong is worse than
not having the feature, which is why the loud rejection shipped first and this did not.

Recommendation if no preference: **option 1 (name string)**, because it is the only one where
`E_from_json_str` is meaningful without a separate schema, and it matches the Rust behaviour
the port is being measured against.

## Implementation sketch (once the shape is chosen)

The machinery is closer than it looks. `PP_PARSE_STRUCT_DEF` already collects declared member
names into the derive tables; an enum body (`NAME = value;`) parses on the same shape as a
struct field with a default. What is missing is:

1. An enum arm in the parse step (the `is_struct` check added at v6.5.30 is where it branches).
2. A name<->value emitter — a switch in each direction, which is the table the compiler
   already holds.
3. `_to_json` / `_from_json_str` bodies following the existing struct emitters.

## Acceptance

- `#derive(Serialize)` on an enum generates a callable `E_to_json(v, sb)`.
- `#derive(Deserialize)` generates `E_from_json_str(s)` with a defined not-found result.
- A `.tcyr` round-trips every variant of a 3+ variant enum, including the not-found path.
- The v6.5.30 rejection still fires for any OTHER non-struct declaration — the gate
  `tests/gates/diagnostics/derive_non_struct_rejected.sh` keeps its axes, with the enum rows
  inverted from "rejected" to "works".
