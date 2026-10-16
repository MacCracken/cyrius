# The `#derive` scanner `T_from_json_str` does not walk a SCALAR field's object or array value: its inner keys are read as the outer struct's — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 struct lane (`l6711-struct` @ 6cc59858, x86_64; the
scanner is generated cyrius, so every target), with the compiler before and after that commit alike: for `P { a: i64;
b: i64; }` the scanner decodes `{"a":{"q":7,"b":9},"b":4}` with b = 9; the pairs form `P_from_json(bayan_json_parse(..))`
gives b = 4.
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 struct lane (S7), fixing issues/2026-10-12-derive-scanner-loses-fields-after-
nested-struct.md — which made the scanner's NESTED-STRUCT arm and its UNKNOWN-KEY arm walk a value whole
(`_cy_json_skipval`). The scalar arms were outside that issue's filed surface and keep the old behaviour.
**Severity:** Medium — silent wrong values from a generated decoder on a document whose shape does not match the
struct (no diagnostic; the call returns non-NULL). A key placed INSIDE a scalar field's object value lands in the
outer struct, so the scanner and any real JSON parser (bayan's pairs form included) read the same document
differently — a parser differential a validator in front of the decoder would not see. Not a security id: the
document's author can set `b` directly.
**Affects:** every cycc whose `#derive(Serialize)` emits `T_from_json_str` (measured: the 6.7.11 lane, before and after
S7), every target.

## Reproduction

```cyrius
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
struct P { a: i64; b: i64; }
#derive(Serialize)
struct U { a; b; }
#derive(Serialize)
struct F { a: f64; b: i64; }
#derive(Serialize)
struct B { a: bool; b: i64; }
#derive(Serialize)
struct T { a: Str; b: i64; }

fn pv(p: *P): i64 { return p.b; }
fn uv(p: *U): i64 { return p.b; }
fn fv(p: *F): i64 { return p.b; }
fn bv(p: *B): i64 { return p.b; }
fn tv(p: *T): i64 { return p.b; }

alloc_init();
println_int(pv(P_from_json_str("{\"a\":{\"q\":7,\"b\":9},\"b\":4}")));   # i64 field holding an object
println_int(uv(U_from_json_str("{\"a\":{\"q\":7,\"b\":9},\"b\":4}")));   # untyped field
println_int(fv(F_from_json_str("{\"a\":{\"q\":7,\"b\":9},\"b\":4}")));   # f64 field
println_int(bv(B_from_json_str("{\"a\":{\"q\":7,\"b\":9},\"b\":4}")));   # bool field
println_int(tv(T_from_json_str("{\"a\":{\"q\":7,\"b\":9},\"b\":4}")));   # Str field
println_int(pv(P_from_json_str("{\"a\":[1,{\"b\":9}],\"b\":4}")));      # an array holding an object
println_int(pv(P_from_json_str("{\"a\":\"x,\\\"b\\\":9\",\"b\":4}")));   # a string (right)
println_int(pv(P_from_json(bayan_json_parse(str_from("{\"a\":{\"q\":7,\"b\":9},\"b\":4}")))));  # the pairs form
syscall(SYS_EXIT, 0);
```

```
actual:   9 9 9 9 9 9 4 4
expected: 4 4 4 4 4 4 4 4   (the field `a` left 0, as for any value its type cannot take)
```

## Root cause

`src/frontend/lex_pp.cyr`, `PP_DERIVE_SERIALIZE_BODY`'s `_from_json_str` emitter: the integer arms (typed and
untyped) parse a decimal and stop at the first non-digit; the f64 / f32 arm (`PP_DFLT_SCAN`), the bool arm
(`PP_DBOOL_SCAN`) and the Str arm (`PP_DQSTR_SCAN`) take their own token. None walks a value of another JSON
shape: on an object or array the cursor stays at its `{` / `[`, and the main loop then steps into it byte by
byte (`else { _p = _p + 1; }`) and reads its keys as the outer object's — the same derailment the nested-struct
and unknown-key arms had until 6.7.11 (`_cy_json_skipval` there now).

## Proposed fix

After each scalar arm's own parse, walk the rest of the value with `_cy_json_skipval(json, _p)` (it stops at the
value's depth-0 terminator, so after a well-formed scalar it moves nothing; on an object, array or a string where
a number was expected it skips the whole value and leaves the field as that arm leaves it). Rows: every scalar
kind holding an object, an array of objects and a string; well-formed documents byte-for-byte unchanged in value;
the scanner agreeing with the pairs form.
