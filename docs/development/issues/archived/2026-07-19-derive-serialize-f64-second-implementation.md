# `#derive(Serialize)` carries a second, divergent f64 codec — fixing the libraries cannot reach it — FIXED (6.4.69)

**Fixed 2026-07-20 (cycc 6.4.69).** The derive (`src/frontend/lex_pp.cyr`) no longer
inlines `fmt_float_buf(…, 6)` / `f64_parse` into generated `*_to_json` / `*_from_json`:
it now emits calls to the **named stdlib codec** `bayan_f64_to_json` /
`bayan_f64_from_json` (bayan 1.2.1 — the Grisu2 round-trip-correct formatter + the
correctly-rounded parser). So (a) the two float codecs in the tree are now ONE — the
derive and bayan agree bit-for-bit, killing the 1-ULP divergence; (b) the next fix is a
bayan release, not a recompile-the-world; (c) the compiler change and the bayan change
shipped in the **same release**, so no two-format window. **Consumers must rebuild**
(the emitted call text changed — relink is not enough) and have `lib/bayan.cyr` in
scope for an f64-deriving struct. Verified: the filed repro's finite values now
round-trip bit-exact and the two paths AGREE (was "PATHS DISAGREE"); `Inf`/`NaN` emit
valid `null`. Self-host fixpoint byte-identical, seed-derive green, cross-OS ecb+cass
green. Gates: `tests/tcyr/derive_serialize_f64.tcyr` + `derive_vec_primitive.tcyr`
(updated to the Grisu2 shortest output) + `vr01_f64_json_roundtrip.tcyr`.

---

**Discovered:** 2026-07-19 while implementing **samay** M4 (JSON `Serialize`/`Deserialize`
for every public type) against cycc 6.4.67.
**Severity:** **High** — the two float codecs in the tree already disagree by 1 ULP on
byte-identical text, and the derive's half is **compiled into consumer binaries**, so no
library release can fix it. Fixing bayan alone splits the ecosystem's float format in two.
**Affects:** cycc **6.4.67** (code paths date to v6.3.40). `src/frontend/lex_pp.cyr`.
**Related:** [`2026-07-19-f64-json-roundtrip-6-decimal-cap.md`](./2026-07-19-f64-json-roundtrip-6-decimal-cap.md)
— same underlying formatter defect, different blast radius. Read that one first; this
issue is specifically about *why it needs a compiler change too*.

## Summary

There are **two independent f64 JSON implementations** in the tree:

| | emit | parse |
|---|---|---|
| **bayan** value tree | `_jb_walk` → `fmt_float_buf(v, buf, 6)` | `_jp_atof` |
| **`#derive(Serialize)`** | `lex_pp.cyr:900-903` and `:882`, inlining `fmt_float_buf(..., &_dfb, 6)` **into generated code** | `lex_pp.cyr:1042` → `f64_parse` (`lib/math.cyr:514`) |

They share the formatter's 6-decimal cap but use **different parsers**, and those parsers
are not equivalent. Measured on byte-identical input `{"x":0.333333}`:

```
bayan  _jp_atof  -> 0x3fd55553ef6b5d46
derive f64_parse -> 0x3fd55553ef6b5d47
```

So a document written by one and read by the other changes value. This is a live bug
today, independent of any future fix.

The structural problem is that the derive's emit is **not a library call that a release
can swap out** — `lex_pp.cyr` pastes `fmt_float_buf(..., 6)` inline into every generated
`*_to_json`. Every consumer that ever ran `#derive(Serialize)` has a private copy of the
6-decimal formatter baked into its binary and its `dist/*.cyr` bundle.

**Consequence for sequencing:** if the bayan/stdlib fix ships without a matching compiler
change, JSON produced in the same process will carry **two different float formats**
depending on which code built it — `{"x":0.3333333333333333}` from a bayan-built tree,
`{"x":0.333333}` from a `#derive`-built struct. That is strictly worse than the current
uniformly-wrong state, because it is no longer obvious which values are trustworthy.

## Reproduction

`docs/development/issues/repros/2026-07-19-derive-serialize-f64-second-implementation.cyr`

```
$ cyrius build docs/development/issues/repros/2026-07-19-derive-serialize-f64-second-implementation.cyr /tmp/derivef64
$ /tmp/derivef64
-- exact for both paths --
0.5   derive emits {"x":0.500000}
      orig  =0x3fe0000000000000
      bayan =0x3fe0000000000000
      derive=0x3fe0000000000000
      ok

-- the two float parsers diverge by 1 ULP --
1/3   derive emits {"x":0.333333}
      orig  =0x3fd5555555555555
      bayan =0x3fd55553ef6b5d46
      derive=0x3fd55553ef6b5d47
      *** PATHS DISAGREE on identical text ***
2/3   derive emits {"x":0.666667}
      orig  =0x3fe5555555555555
      bayan =0x3fe55556084a515d
      derive=0x3fe55556084a515e
      *** PATHS DISAGREE on identical text ***

-- derive inherits the same annihilation + invalid-JSON emit --
1e-9  derive emits {"x":0.000000}      -> both read back 0x0
+Inf  derive emits {"x":-.00000-}      -> invalid JSON
NaN   derive emits {"x":-.00000-}      -> invalid JSON

failure count: 5
$ echo $?
1
```

Deterministic. Exit 0 would mean the paths agree *and* round trip.

## Root cause (verified)

**Emit — two inline sites**, both hardcoding `6`, writing into the shared `var _dfb[80]`
scratch declared at `src/frontend/lex_pp.cyr:763`:

```
:900-903   per-field f64 branch
           "store8(&_dfb + fmt_float_buf(load64(ptr + <off>), &_dfb, 6), 0);"
           "str_builder_add_cstr(sb, &_dfb);"

:882       vec-of-f64 branch
           "store8(&_dfb + fmt_float_buf(vec_get(_vh…"
```

Surrounding commentary at `:747`, `:801`, `:852`. Because these are `PP_EMIT_STR` calls,
the text lands in the *consumer's* generated source — the defect is copied, not linked.

**Parse — `src/frontend/lex_pp.cyr:1042`**: `", f64_parse(str_data(v))); }\n"`, i.e.
`lib/math.cyr:514`. bayan's `_jp_atof` is a separate implementation with separate rounding
behavior. Neither is correctly rounded; they happen to land on adjacent ULPs.

## Proposed fix

1. **One implementation, not three.** Land a single correctly-rounded pair (format +
   parse) in the stdlib, and have *all* of `lex_pp.cyr`'s emitted code, `lib/math.cyr`'s
   `f64_parse`, and bayan's `_jb_walk`/`_jp_atof` route through it. The derive should emit
   a **call** to a named stdlib function rather than inlining a formatter, so the next fix
   is a library release instead of a recompile-the-world.

2. **Ship the compiler change and the library change in the same release.** Sequencing
   them apart is what creates the two-format window described above. If they must be
   split, land the *derive* side first — a derive-built document is the one most consumers
   actually produce.

3. **Consumers must rebuild, not relink.** Whatever release carries this needs a
   CHANGELOG note saying so explicitly, and every first-party project with a committed
   `dist/*.cyr` containing generated `*_to_json` needs that bundle regenerated. A
   `grep -l "fmt_float_buf" */dist/*.cyr` sweep across `~/Repos` would size this.

4. **Regression test.** There is currently no test anywhere covering derive f64 round trip.
   The repro above is a ready-made matrix; the cross-path agreement assertion
   (`bayan_parse(text) == derive_parse(text)`) is the one that would have caught this.

## Consumer-side workaround

None for the emit side — you cannot intercept what the derive inlines. A consumer needing
exact f64 today must avoid `#derive(Serialize)` on f64 fields entirely and hand-write those
fields against the bayan DOM, which is precisely the hand-written codec burden the derive
exists to remove.

samay's M4 is blocked on this rather than worked around; see
`samay/docs/development/issues/2026-07-19-cyrius-f64-json-roundtrip.md`.

## Notes for whoever picks this up

Two traps cost me real time; both are in the repro's comments:

- **Escaped quotes in a `.cyr` source literal** (`"{\"x\":1e10}"`) do not reach the parser
  as intended — the probe silently becomes a parse error that *looks* like a fast, healthy
  result. Build test documents with `str_builder` and check the parser's return value for
  `0`; never infer from timing alone.
- **`var r: S = S_from_json(...)` then `r.x`** does not read the field back correctly (it
  yielded a pointer value). `load64(rec)` does. Unclear whether that is a derive bug, a
  typed-local bug, or my misuse — **not investigated**, and deliberately not asserted as a
  defect here. Worth a look if someone is already in this code.

Verified non-issues, so nobody re-chases them: neither `bayan_json_parse` nor
`json_v_parse` mutates its input buffer (checked byte-by-byte before and after).

**Reporting on:** cycc 6.4.67, bayan 1.2.0.
