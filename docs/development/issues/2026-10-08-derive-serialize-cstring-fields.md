# `#derive(Serialize)` does not support a `: cstring` field — it is taken for a nested struct (asked by sigil) — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: `#derive(Serialize) struct Cert { name:
cstring; bits: i64; }` with a `Cert_to_json` call is refused (`undefined function 'cstring_to_json'` — reachable —
and `'cstring_from_json'`); the same struct with `name: Str` builds and prints `{"name":"example.org","bits":256}`.
sigil still hand-rolls the codec for exactly this reason (`lib/sigil.cyr:1248-1271`).
**Placement:** unpinned — 6.x-line backlog (asked by the sigil fold) — never 7.x.
**Discovered:** sigil's hand-rolled `certpin_info_to_json` ("cyrius #derive(Serialize) does not yet support
cstring-pointer fields … Drop this and re-#derive the type when the toolchain gains it"); filed 2026-10-08 from
roadmap.md.
**Severity:** Low — a codegen-feature gap with a shipped stopgap (hand-written codecs).
**Affects:** cycc ≤ 6.7.6.

## Summary

The derive codec's field dispatch (`src/frontend/lex_pp.cyr`, `PP_DERIVE_SERIALIZE_BODY` and its field loop
~2586-2745) recognises `Str`, `f64`, `i8`/`i16`/`i32`/`i64`, `bool`, `Vec<…>` and an untyped slot; any other type
name falls to the nested-struct arm and emits `<type>_to_json(…)` / `<type>_from_json(…)`. `cstring` — the
language's own NUL-terminated pointer type, which `: cstring` parameters already check — lands there, so a struct
holding C strings cannot be derived at all. sigil (cert metadata: subject / issuer / serial / fingerprints) keeps
`#derive(accessors)` with UNTYPED fields and a hand-written `certpin_info_to_json` that emits each C string escaped
or `null` (`agnosys_json_emit_cstr_or_null`); `dmverity_status_to_json` (`lib/sigil.cyr:3536`) is the same shape.

## Reproduction

```cyr
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/hashmap.cyr"
include "lib/bayan.cyr"

#derive(Serialize)
struct Cert { name: cstring; bits: i64; }

alloc_init();
var c = alloc(16);
store64(c, "example.org");
store64(c + 8, 256);
var sb = str_builder_new();
Cert_to_json(c, sb);
var s = str_builder_build(sb);
syscall(SYS_WRITE, 1, str_data(s), str_len(s));
syscall(SYS_EXIT, 0);
```

```sh
cat cert.cyr | /home/macro/Repos/cyrius/build/cycc > /tmp/cert
# rc 1: warning: undefined function 'cstring_to_json' / 'cstring_from_json'
#       error: refusing to emit binary with 1 reachable undefined function(s)
# with `name: Str` (and store64(c, str_from("example.org"))): rc 0, prints {"name":"example.org","bits":256}
```

## Root cause

No `cstring` arm in the derive field dispatch (encode beside the `is_str` arm, `src/frontend/lex_pp.cyr:2710-2722`;
decode likewise in the `_from_json` emitter), so the name is treated as a derived struct type.

## Proposed fix

A `cstring` arm in both codecs: encode the NUL-terminated bytes with the same RFC 8259 escaping `Str` uses (a
`str_builder_add_json_cstr`-style helper beside `str_builder_add_json_str` in `lib/str.cyr`), and a null pointer as
`null`; decode a JSON string to a fresh NUL-terminated `alloc` copy (unescaped) and `null` to 0. Because such a
struct does not compile today, no working program changes; the NULL ↔ `null` wire shape is the one sigil already
ships (the user may pick otherwise). Guide + vidya entries for the new field type (CLAUDE.md: no language feature
without vidya). Gates: a round-trip `.tcyr` (escapes, embedded `"` / `\` / control bytes, NULL), and sigil
re-derives `certpin_info` in its own release, byte-comparing its JSON against the hand-rolled output.
