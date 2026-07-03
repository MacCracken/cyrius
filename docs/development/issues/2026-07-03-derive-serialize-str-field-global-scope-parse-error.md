# `#derive(Serialize)` struct with a Str field → "unexpected '}'" when used at GLOBAL scope

**Filed:** 2026-07-03 (surfaced building the v6.3.40 f64 fixture; PRE-EXISTING — reproduces
on the pristine v6.3.39 release binary, NOT introduced by the f64 work).
**Severity:** P3 — narrow shape (a `#derive(Serialize)` struct with a `Str` field whose
generated codec fns are invoked from GLOBAL scope). Works fine inside `fn main`, and works
at global scope for i64/f64-only structs. The existing `derive_serialize_roundtrip.tcyr` is
i64-only, which is why it never surfaced.

## Symptom

```
#derive(Serialize)
struct sample { id: i64; label: Str; }
var s = sample { 0, 0 };
...
var s2 = sample_from_json_str(j);   # global scope
# → error:<source>:1: unexpected '}'
```

Same struct + invocation inside `fn main(): i64 { ... }` compiles fine. i64/f64-only structs
at global scope compile fine. So it is specifically a Str field + the emitted codec (likely
`_from_json_str`'s `str_new(json + _vs, ...)` value-read) parsed at global scope.

## Next

Dump the preprocessed output for the Str-at-global case and find the brace/scope imbalance
in the emitted `_from_json_str` (or the interaction with global-scope statement parsing).
Not on the v6.3.40 critical path (f64 landed; the fixture uses i64+f64).
