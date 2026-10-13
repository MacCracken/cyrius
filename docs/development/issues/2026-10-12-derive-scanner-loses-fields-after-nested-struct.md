# The `#derive` scanner `T_from_json_str` skips a nested `#derive`d struct field's object to its first inner `,`: the nested field stays 0, every field after it is lost, and the nested object's own keys land in the outer struct — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the merged 6.7.10 tree (`9c066967`, `build/cycc` 2,106,040 B,
x86_64): for `{"a":1,"inn":{"x":2,"y":3},"b":4}` the scanner `Out_from_json_str` gives a=1, inn.x=0, inn.y=0, b=0,
while the pairs form `Out_from_json(bayan_json_parse(..))` gives 1, 2, 3, 4. The installed 6.7.9 compiler
(`~/.cyrius/versions/6.7.9/bin/cycc`, with its own `lib/`) prints the same rows byte for byte, and 6.6.0's scanner the same
`Out` row (1 0 0 0) — this predates 6.7.10. The guide already names it as a known defect (`docs/guides/cyrius-guide.md:2732`,
6.7.10 B7-5); no issue file carried it.
**Placement:** 6.7.11 — repair 1, the call-arguments / struct operators lanes (roadmap.md § *6.7.11*) — placed
2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, 6.7.10's B7 lane (the derive's narrow / f32 / cstring fields, B7-3 / B7-4): its
`tests/tcyr/derive/derive_serialize_narrow.tcyr` puts the nested struct LAST to keep the fields after it, and the B7-5
guide pass recorded the measured defect.
**Severity:** Medium — silent wrong values from a generated decoder: no diagnostic, the call returns a non-NULL struct,
and a nested object's keys can overwrite the outer struct's fields of the same name. The pairs form is right.
**Affects:** every cycc whose `#derive(Serialize)` emits `T_from_json_str` (measured: 6.6.0, 6.7.9, the 6.7.10 tree),
every target (the codec is generated source).

## Summary

`#derive(Serialize)` emits two decoders: the pairs form `T_from_json(pairs)`, which decodes a nested `#derive`d struct
field through `<Inner>_from_json(bayan_json_parse(v))` and copies it inline, and the single-pass scanner
`T_from_json_str(json)`. The scanner's nested-struct arm does not decode the object at all — it is a value SKIP, and
the skip is depth-blind: it advances to the first `,` or `}` byte. Inside `{"x":2,"y":3}` that is the `,` after
`"x":2`, so the main loop resumes INSIDE the nested object:

1. the nested field is never filled (stays 0);
2. the inner `"y":3` is read as an OUTER key — decoded into the outer struct if it has a field `y`, else skipped as
   unknown — and the inner object's `}` is then taken for the outer object's end: the scan stops, and every field
   after the nested one stays 0;
3. the same depth-blind skip serves an UNKNOWN key (`else { while (..) }`), so an unknown key whose value is an
   object (or a string holding a `,` or `}`) derails the scan the same way: `{"a":1,"extra":{"q":7,"b":9},"b":4}`
   decodes `b` = 9, the inner object's value, not 4.

The Vec<struct> arm of the same scanner (v6.4.13 R3) already decodes each element through `<T>_from_json_str` and
skips with a string- and depth-aware walk; the shared `_cy_json_skipval` helper exists for exactly this (6.4.x R3,
6.7.10 cstring).

## Reproduction

```sh
cd /home/macro/Repos/cyrius
cat > /tmp/nest.cyr <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/alloc.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/hashmap.cyr"
include "lib/result.cyr"
include "lib/fnptr.cyr"
include "lib/io.cyr"
include "lib/bayan.cyr"

#derive(Serialize)
struct In { x: i32; y: i64; }

#derive(Serialize)
struct Out { a: i64; inn: In; b: i64; }

#derive(Serialize)
struct Out2 { a: i64; inn: In; y: i64; }

#derive(Serialize)
struct P { a: i64; b: i64; }

fn row(tag: cstring, a, b, c, d): i64 {
    println(tag);
    println_int(a); println_int(b); println_int(c); println_int(d);
    return 0;
}
fn out(tag: cstring, o: *Out): i64 { return row(tag, o.a, o.inn.x, o.inn.y, o.b); }
fn out2(tag: cstring, o: *Out2): i64 { return row(tag, o.a, o.inn.x, o.inn.y, o.y); }
fn pp(tag: cstring, p: *P): i64 { return row(tag, p.a, p.b, 0, 0); }

alloc_init();
var js = "{\"a\":1,\"inn\":{\"x\":2,\"y\":3},\"b\":4}";
out("1. scanner Out:", Out_from_json_str(js));
out("1. pairs   Out:", Out_from_json(bayan_json_parse(str_from(js))));
out2("2. scanner Out2:", Out2_from_json_str("{\"a\":1,\"inn\":{\"x\":2,\"y\":3},\"y\":4}"));
pp("3. scanner P:", P_from_json_str("{\"a\":1,\"extra\":{\"q\":7,\"b\":9},\"b\":4}"));
syscall(SYS_EXIT, 0);
EOF
cat /tmp/nest.cyr | build/cycc > /tmp/nest && chmod +x /tmp/nest && /tmp/nest | paste -sd' '
# 1. scanner Out: 1 0 0 0 1. pairs   Out: 1 2 3 4 2. scanner Out2: 1 0 0 3 3. scanner P: 1 9 0 0
```

Expected: `1. scanner Out: 1 2 3 4` (as the pairs form), `2. scanner Out2: 1 2 3 4` (the outer `y` is 4, the inner
3 stays in `inn.y`), `3. scanner P: 1 4 0 0` (an unknown key's object value is skipped whole). The pairs form gives
`1 2 3 4` for Out2 and `1 4` for P on the same inputs.

## Root cause

`src/frontend/lex_pp.cyr`, `PP_DERIVE_SERIALIZE_BODY` (`:2477`), the `_from_json_str` emitter:

- `:3034-3041` — the nested-struct arm ("Nested struct: skip value (fall through to json_get path)") emits
  `while (load8(json + _p) != 44 && load8(json + _p) != 125 && load8(json + _p) != 0) { _p = _p + 1; }`: no decode,
  and a skip that stops at the first `,` / `}` at ANY depth, inside strings included.
- `:3055-3056` — the unknown-key arm emits the same depth-blind skip.
- `:2507-2513` — `_needsk` (emit `_cy_json_skipval` once) is set only for a Vec<struct> or a cstring field, so the
  nested arm could not call the depth-aware helper today without that gate learning the nested case.

The pairs form's nested arm (`:2833-2855`) is the model: `<Inner>_from_json(..)`, then `memcpy(ptr + off, np, tsz)`
with `tsz` from `_pp_derive_sizes`.

## Proposed fix

In the scanner's nested-struct arm, decode and skip as the Vec<struct> arm does: emit
`if (load8(json + _p) == 123) { var _nq<fi> = <Inner>_from_json_str(json + _p); if (_nq<fi> != 0) {
memcpy(ptr + <off>, _nq<fi>, <tsz>); } } _p = _cy_json_skipval(json, _p);` (`tsz` looked up from `_pp_derive_sizes`
exactly as `:2836-2852` does — one shared helper for both arms), and set `_needsk` for any field that falls to the
nested arm. The `{` guard matters: `<Inner>_from_json_str` scans forward to the FIRST `{` it finds, so called on a
`null` (or any non-object) value it would decode the next object later in the document; with the guard such a value
leaves the field 0. Replace the unknown-key arm's skip with `_p = _cy_json_skipval(json, _p);` too, so
`_cy_json_skipval` is emitted for every derived struct (the bytes of every derive-using program change; well-formed
documents with no nested or unknown object values decode as before).
Rows: the three above in a derive `.tcyr` (scanner and pairs agree, field order before / middle / last, a string
value holding `,` and `}` inside the nested object, an unknown key holding an object, array and comma-bearing string);
`tests/tcyr/derive/derive_serialize_narrow.tcyr`'s `check_out(.., nested = 0, ..)` for the scanner becomes 1; the
guide's known-defect note (`cyrius-guide.md:2732`) goes.

## Consumer-side workaround

Decode a struct that nests a `#derive`d struct (or may meet unknown keys holding objects) with the pairs form,
`T_from_json(bayan_json_parse(str))`, which gives every field on these inputs. Or declare the nested field LAST and
accept it decoding to 0 through the scanner.
