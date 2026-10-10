# A slice type outside a fn-local `var` is a mis-diagnosed parse error: declaration-zone globals, parameters, return types, fields — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`cycc_merged`, 1,916,288 B; tree @
06bd8981) and 6.7.6's `build/cycc`, with
[`repros/2026-10-09-slice-type-outside-fn-local-misdiagnosed.cyr`](repros/2026-10-09-slice-type-outside-fn-local-misdiagnosed.cyr).
Both compilers report the two errors it quotes. With its two `var` lines moved after the first statement, the same
file compiles and exits 0 on both. Each shape in the table below was compiled with the merged tip.
**Placement:** 6.7.8 — checked `dyn` + C2 (roadmap.md § *6.7.8*: "File at the open: slice parameters and top-level
slices are mis-diagnosed parse errors") — placed 2026-10-09 — never 7.x. C2's open decides slice scope, and the fix
follows that answer.
**Discovered:** first noted, unfiled, by the 6.7.8 – 6.7.12 release plan (2026-10-09). Met again out of scope by a
6.7.7 lane (the declaration-zone global) and filed 2026-10-09.
**Severity:** Medium for the declaration-zone global: the guide's own `var s: [u8] = 0;` fails as a leading global,
and the workaround is to declare it after the first statement. Low for the rest, which are diagnostics, since
whether a slice may be a parameter, return or field is the scope question C2 answers.
**Affects:** cycc 6.7.6 and the merged 6.7.7 tip (older releases not bisected).

## Summary

`[T]` and `slice<T>` (the guide's "Slices": "Two equivalent type forms") are read only by **PARSE_VAR**: a fn-local
`var`, and a top-level `var` after the first statement that is not a declaration. Every other place that takes a
type annotation either has no arm for them, so the `[` or the `slice` name falls through to a generic parse error,
or names `slice` an "unknown type". The same declaration also flips between refused and accepted depending on
whether a bare statement came before it.

| Shape (merged 6.7.7 tip) | Result |
|---|---|
| fn-local `var s: [u8] = 0;` / `var t: slice<i64> = 0;` | compiles |
| top-level `var GS: [u8] = 0;` after a bare statement (`main();`) | compiles (and `slice<u8>` too) |
| top-level `var GS: [u8] = 0;` in the declaration zone (before any bare statement; `var r = main();` is still in the zone) | `expected '=', got identifier 'u8'` |
| top-level `var GT: slice<u8> = 0;` in the declaration zone | `unknown type 'slice' for variable 'GT'`, then a note listing the types, which omits slices |
| `fn f(s: [u8])` | `expected ')', got identifier 'u8'`, and `s.len` in the body cascades `no struct type in scope for 's'` |
| `fn f(s: slice<u8>)` | `unknown type 'slice' for parameter 's'` |
| `fn f(): [u8]` | `expected identifier, got '['` |
| `fn f(): slice<u8>` | `unknown type 'slice' as a fn return type` |
| struct field `s: [u8];` | `expected identifier, got '['` |
| struct field `s: slice<u8>;` | `unknown type 'slice' for struct field 's'`, then `expected identifier, got '<'` |
| top-level slice (after a statement), then `GS.len` | `no struct type in scope for 'GS'` (the guide: dot syntax is fn-local only, so the rule is documented but the message misleads) |

## Reproduction

```sh
build/cycc < docs/development/issues/repros/2026-10-09-slice-type-outside-fn-local-misdiagnosed.cyr > /tmp/slicez
# error:<source>:12:9: unknown type 'slice' for variable 'GT'
# error:<source>:11:10: expected '=', got identifier 'u8'
```

Move the two `var` lines below `noop();` (the first statement) and it compiles and exits 0. The parameter shape:

```cyr
include "lib/slice.cyr"
fn f(s: [u8]): i64 { return s.len; }
fn main(): i64 { return 0; }
syscall(60, main());
```
```
error:<source>:2:10: expected ')', got identifier 'u8'
error:<source>:2:34: no struct type in scope for 's'; a '.field' access needs its struct declaration (missing include?)
```

## Root cause

- **PARSE_VAR** has the two arms: `[T]` at `src/frontend/parse_decl.cyr:5989`–`6008`, with element width from
  `_tn_slice_head` / `_tn_slice_w`, and `slice<T>` at `:6013`–`6033`, which matches the word `slice` by its bytes
  (`0x006563696C73`).
- **PARSE_GVAR_REG**'s annotation ladder (`parse_decl.cyr:4526`–`4550`, the declaration zone) has arms for `*T`,
  `u128` and a `_tn_head` name only. A `[` falls into the else arm, which steps one token (`STI(S, GTI(S) + 1)`), so
  `u8` is met where `=` is expected. `slice` goes to `_tn_ann`, which does not know it.
- **Parameters:** `_tn_param_check` (`parse_types.cyr:982`) refuses `slice` by name. A `[` is not a type head there,
  so the parameter list's own `expect ')'` fires. Pass 1's `_prescan_params` steps the same tokens.
- **Return types and fields:** `_classify_return_type` / `_tn_ret_refuse` and the struct-field type path take a name
  or `*T`, so `[` is "expected identifier".

## Proposed fix

C2's slice-scope decision (6.7.8's open) picks which of these positions a slice may take.

1. **Whatever the answer, the declaration-zone global must agree with PARSE_VAR's top-level arm.** Give
   PARSE_GVAR_REG the same `[T]` / `slice<T>` arms (16-byte `{ptr, len}` slot, element width recorded), so a leading
   `var GS: [u8] = 0;` declares what it declares after a statement. This is the guide's own line. The
   EMIT_GVAR_INITS replay must step the same tokens.
2. **Positions C2 leaves out are refused by name** ("a slice cannot be a parameter type yet — pass `&s` as a `*`
   …", or as C2 words it) at the `[` / `slice`, consuming the whole `[..]` / `slice<..>` so nothing cascades. That
   replaces `expected ')'`, `expected identifier`, `unknown type 'slice'` and the `s.len` cascade.
3. Positions C2 admits (a parameter as a 16-byte by-value pair, a return, a field) are built in C2's slice bites
   instead.
4. The type-list notes ("a type is …", "a field type is …") name `[T]` / `slice<T>` where they are accepted.
5. Optionally, have a top-level slice's `GS.len` say "slice dot syntax is fn-local only (use `slice_len(&GS)`)"
   instead of "no struct type in scope".

Gate rows: each shape in the table above, in both zones, with the exact single diagnostic or an exit-0 run.
