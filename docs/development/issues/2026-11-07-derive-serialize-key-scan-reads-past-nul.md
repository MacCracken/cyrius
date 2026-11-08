# `#derive(Serialize)`'s `<Name>_from_json_str` reads past the NUL on an unterminated key — OPEN

**Status:** 🔴 **OPEN** — reported by ghurni, which stopped using the derive in 2.7.2.
**Placement:** unpinned — 6.x-line backlog.
**Where the fix lives:** the `_from_json_str` emitter, `src/frontend/lex/pp/serialize.cyr:426`
at 6.7.18 (`src/frontend/lex_pp.cyr` before the split).
**Discovered:** 2026-11-07, during ghurni's 2.7.2 P(-1) security sweep.
**Reporter:** ghurni 2.7.2
**Cyrius version at time of report:** 6.7.18
**Severity:** High. A heap overread on hostile input, the same class as the archived
null-deref issue. It returns data from another allocation as a successful parse, or
faults when the next page is unmapped.
**Affects:** cycc 6.5.36 through 6.7.18. The loop is present in the emitter at 6.5.36,
6.6.3, 6.7.9 and 6.7.18, and the repro fails the same way on 6.6.3 and 6.7.18.

## Summary

The emitted parser reads each key with:

```
_p = _p + 1;
var _ks = _p;
while (load8(json + _p) != 34) { _p = _p + 1; }
```

Nothing stops it at the NUL. Given an unterminated key, it walks off the end of the
string until it meets a `"` somewhere else in memory, then keeps parsing from there.
So `{"k` returns a struct whose fields came from whatever allocation follows, and the
same string against an unmapped page faults.

That is reachable from any caller that parses JSON it did not write: a save file, a
preset, a network message. [`archived/2026-08-31-derive-serialize-from-json-str-null-deref.md`](archived/2026-08-31-derive-serialize-from-json-str-null-deref.md)
closed the null-pointer half of this parser's input handling. This is the
unterminated-input half.

## Reproduction

[`repros/2026-11-07-derive-serialize-key-scan-reads-past-nul.cyr`](repros/2026-11-07-derive-serialize-key-scan-reads-past-nul.cyr)
derives `Serialize` on a two-field struct and runs two cases:

1. `{"k` with its NUL, followed by an allocation holding `":0,"kind":3,"arg0":77}`.
2. The same `{"k` placed so its NUL is the last byte of a mapped page, with the next
   page `mprotect`ed to `PROT_NONE`.

```
cyrius build docs/development/issues/repros/2026-11-07-derive-serialize-key-scan-reads-past-nul.cyr /tmp/derive-nul
/tmp/derive-nul; echo "exit=$?"
```

Actual, on 6.6.3 and 6.7.18 (built from a scratch directory holding that version's
`lib/` snapshot):

```
case 1: parsed kind=3 out of the next allocation (want: 0, a failed parse)
case 2: parsing an unterminated key at a page end (SIGSEGV here = overread)
exit=139
```

Expected: both calls return 0, and the program prints `ok: both refused` and exits 0.

## Root cause

`serialize.cyr:426` emits the key scan above with no `!= 0` term. Every other scan in
the emitted body stops at the NUL, either explicitly (`:417`, `:526`) or because 0 is
not in the set it scans for (the whitespace and colon skip at `:428`, the digit scans
at `:542` and `:563`). The key scan is the only unbounded one found. Nested-object and
`Vec<struct>` value scans were not audited.

## Proposed fix

Stop at the NUL and fail the parse there, with the failure convention the null-deref
fix already uses:

```
while (load8(json + _p) != 34 && load8(json + _p) != 0) { _p = _p + 1; }
if (load8(json + _p) == 0) { return 0; }
```

A regression row should place the input against an unmapped page, as the repro does.
An overread that happens to end in a refusal looks the same as a correct parse, so
only a fault tells them apart.

## Who is exposed

Ten repos under `~/Repos` derive `Serialize` (117 structs). Four call the generated
`_from_json_str` from their own source: garjan (43 call sites), samay (12), prani (8)
and varna (4). The function is public in the other six as well.

## Consumer-side workaround

ghurni 2.7.2 dropped `#derive(Serialize)` from its three structs and hand-wrote
`_to_json`, `_from_json` and `_from_json_str` under the same names, over one strict
reader (`GhJson_read3` in ghurni's `src/error.cyr`). Every read stops at the NUL, each
key must appear exactly once, values must be integers, and nothing may follow the
closing brace. Its `tests/sweep_2_7_2.tcyr` holds every prefix of a valid document
against an unmapped page.
