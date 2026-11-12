# `#derive(Serialize)`: `T_to_json` faults on a `Str` field that is 0, which is what a document missing that field decodes to — open

**Status:** 🔴 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-11. The repro exits 139 (SIGSEGV).
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-11, by ushma's Rust → Cyrius port (M0 probe 11, `ushma/docs/development/port-parity.md` §3),
while re-encoding what `#derive(Serialize)` decoded from serde_json's missing-field documents.
**Reporter:** ushma 2.0.0 port (`ushma/docs/development/ushma-port-plan.md` §8)
**Related:** `2026-11-07-derive-serialize-reader-memsets-a-refused-allocation.md`: its item 2, a refused allocation,
also leaves a `Str` field 0, and this fault then follows on write.
**Severity:** **High.** Decode-then-encode, the commonest use of a derived codec, crashes on a document that merely
omits a string field. The input is untrusted: anyone who can send a document can send one without the field.
**Affects:** cyrius 6.7.18: the derive's writer arm for `Str` (`src/frontend/lex/pp/serialize.cyr:239`) and
`str_builder_add_json_str` (`lib/str.cyr:121`).

## Summary

`T_from_json_str` zeroes the struct first, so a key the document lacks leaves its field 0. For a `Str` field that
means a null `Str`. `T_to_json` writes a `Str` field with `str_builder_add_json_str(sb, load64(ptr + off))`, which
calls `str_data(s)` and `str_len(s)` on it, a load through address 0. A `cstring` field doesn't have the problem:
`str_builder_add_json_cstr` writes `null` for 0.

## Reproduction

`repros/2026-11-11-derive-writer-faults-on-a-zero-str-field.cyr`:

```cyrius
#derive(Serialize)
struct Mat { name: Str; conductivity: f64; }

var m = Mat_from_json_str("{\"conductivity\":401.0}");
Mat_to_json(m, sb);    # SIGSEGV
```

## Root cause

The `Str` arm of the writer assumes a non-null `Str`, and `str_builder_add_json_str` doesn't test for 0.

## Proposed fix

Write `null` for a 0 `Str`, as for a 0 `cstring`. Do it in the emitter's `Str` arm, or in `str_builder_add_json_str`
itself, which then protects hand-written callers too. The decoder should read `null` back as a 0 `Str`, so the two
round-trip.

## Consumer-side workaround

Test every `Str` field for 0 before calling `T_to_json`. ushma doesn't use the derive for serde JSON at all (its ADR
0005); it hand-writes codecs on bayan's tree.
