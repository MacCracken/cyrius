# `#derive(Serialize)` in a second `private` file fails to compile: its shared `_cy_json_skipval` is private to the first — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64), 2026-11-12. The repro's build fails.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-12, by bijli's Rust → Cyrius port (M1 part 4, the JSON of its serde types; its port plan D5).
**Reporter:** bijli 2.0.0 port (`bijli/scripts/probes/p16b_derive_private.cyr`, `bijli/docs/development/port-parity.md`
§15)
**Severity:** **Medium.** A library whose public API lives in `private` files (the bundle pattern: each `src/*.cyr`
is `private` and marks its API `public`) can derive JSON for the types of one file only. bijli's `BjComplex` and
`BjFieldVector` are in two such files, so bijli writes its codecs by hand.
**Affects:** cyrius 6.7.18: the derive's one-time helper (`src/frontend/lex/pp/serialize.cyr:93`, guarded by
`_pp_skipval_done` in `derive.cyr:150`).

## Summary

Every derived decoder calls the shared value skipper `_cy_json_skipval`. The derive emits it once, into the file of
the first `#derive(Serialize)` it expands. When that file is `private`, the helper is private to it, and the second
file's decoder is refused:

```
error:scripts/probes/p16b_private_b.cyr:5:47: '_cy_json_skipval' is private to its file
```

## Reproduction

`bijli/scripts/probes/p16b_derive_private.cyr` includes two files, each `private` with one `#derive(Serialize)
public struct`. The build fails as above. With the first file's `private` line removed, it builds and writes
`{"x":1.0,"y":2.0,"z":3.0}`.

## Proposed fix

Emit `_cy_json_skipval` as `public` (it is an internal name already, by its `_cy_` prefix), or emit it outside any
file's `private` scope, at the top of the unit before the first include.

## A related note

In a `private` library file the derive of a `public struct` exports its decoders, `T_from_json_str` and
`T_from_json`, as the library's API. They zero-fill a document's missing or ill-typed fields instead of refusing it,
and allocate on the bump heap per call. A library that wants refusing readers has to name its own differently and
leave those in its API. An attribute to derive the writer alone (`#derive(Serialize, writer)`) would let a library
keep its own readers under the natural names.

## Consumer-side workaround

bijli writes `T_to_json` by hand on `bayan_f64_to_json`, the derive's own printer, so the text is the same.
