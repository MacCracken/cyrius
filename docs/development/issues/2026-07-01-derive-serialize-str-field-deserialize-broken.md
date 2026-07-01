# `#derive(Serialize)` `_from_json` cannot deserialize `Str` fields — garbage on roundtrip

**Discovered:** 2026-07-01 during shravan 2.4.1 (restoring the full serde surface — JSON metadata serialization)
**Severity:** Medium (silent wrong-data on deserialize; workaround: hand-write `_from_json`)
**Affects:** cycc with `Str`-field `#derive(Serialize)` — serialize support landed ~v5.10.x; deserialize never implemented. Verified broken on the **6.3.19** pin and the **6.3.22** wrapper.

## Summary

`#derive(Serialize)` on a struct with `Str`-typed fields generates a working
`<Struct>_to_json` — it correctly emits the string *content* (`"Song"`, not the
pointer, per the v5.10.x Str-field fix). But the matching generated
`<Struct>_from_json` does **not** reconstruct `Str` fields: after `from_json` the
fields hold raw/uninitialised pointer bytes, so a serialize → parse →
deserialize → re-serialize roundtrip produces garbage. Int/primitive fields
roundtrip correctly (verified in the same shravan suite); only `Str`
**deserialize** is unimplemented. The working serialize half silently masks it —
the corruption only shows when you read the deserialized struct back.

## Reproduction

Self-contained: [`repros/derive-serialize-str-roundtrip.cyr`](./repros/derive-serialize-str-roundtrip.cyr)

```cyr
#derive(Serialize)
struct Meta { title: Str; artist: Str; }

fn main() {
    alloc_init();
    var m = Meta { str_new("Song", 4), str_new("Band", 4) };
    var sb = str_builder_new();
    Meta_to_json(&m, sb);
    var js = str_builder_build(sb);          # {"title":"Song","artist":"Band"}  — OK

    var rec = Meta_from_json(bayan_json_parse(js));
    var sb2 = str_builder_new();
    Meta_to_json(rec, sb2);                  # re-serialize the deserialized struct
    var js2 = str_builder_build(sb2);
    if (str_eq(js, js2) == 1) { return 0; }
    return 1;
}
```

```
$ cyrius build docs/development/issues/repros/derive-serialize-str-roundtrip.cyr /tmp/str_rt
$ /tmp/str_rt
to_json:   {"title":"Song","artist":"Band"}
roundtrip: {"title":"�","artist":"�"}     # expected {"title":"Song","artist":"Band"}
$ echo $?
1
```
(cycc 6.3.22)

Expected: `roundtrip` == `to_json`. Actual: `Meta_from_json` leaves the `Str`
fields as garbage pointers.

## Root cause (speculation — verify against the derive codegen)

The `_from_json` derive codegen appears to have a primitive/i64 path only
(bayan `..._get_int`) and no `Str` branch — for a `Str` field it treats the
parsed value like an int (reads/stores a pointer) instead of extracting the
JSON string. The serialize path received the v5.10.x `Str` handling; the
deserialize path never got the symmetric change.

## Proposed fix

In the `_from_json` derive codegen, emit a string-extraction branch for
`Str`-typed fields, mirroring the serialize side:
`bayan_json_get(pairs, "<field>")` → guard `bayan_json_v_is_str(v)` →
`bayan_json_v_str(v)` (returns the `Str` ptr) → copy it into the field so it
outlives the parse arena.

## Consumer-side workaround (shravan)

shravan 2.4.1 ships `ShrAudioMetadata` (7 tag fields, `Option<String>` → `Str`)
**serialize-only** — `ShrAudioMetadata_to_json` (the derive, tested) is correct;
the roundtrip test asserts `to_json` only. When a full roundtrip is needed the
deserializer is hand-written against bayan:

```cyr
fn _meta_get_str(dst, pairs, key) {
    var v = bayan_json_get(pairs, str_new(key, strlen(key)));
    if (bayan_json_v_is_str(v) == 1) {
        var s = bayan_json_v_str(v);            # Str ptr
        store64(dst, load64(s)); store64(dst + 8, load64(s + 8));
    }
    return 0;
}
# ShrAudioMetadata_from_json: alloc(7*16), _meta_get_str per field, return ptr.
```

## Recommended security floor

shravan is on the v5.0.0+ floor (cyrius.cyml manifest). This is a
codegen-completeness bug with no security impact; the fix can land in any 6.3.x
point release.
