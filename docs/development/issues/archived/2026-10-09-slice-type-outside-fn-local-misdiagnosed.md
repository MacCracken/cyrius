# A slice type outside a fn-local `var` is a mis-diagnosed parse error: declaration-zone globals, parameters, return types, fields — RESOLVED

> ✅ **RESOLVED in v6.7.8** (CHANGELOG [6.7.8]). Every slice position outside a fn-local var is refused by name, once — parameters, returns, fields, zone globals, type arguments (C2-6a) and, at integration, a trait member's signature; a post-statement top-level slice keeps compiling (user, 2026-10-10).

**Status:** ✅ **RESOLVED in v6.7.8** — see the banner above.
**Placement:** 6.7.8 — shipped.
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

## Residual (appended 2026-10-10): a trait member's signature still gives the old parse errors

**Verified** 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f, `cycc_merged` 2,053,536 B), each line a
one-line program compiled from the tree root. The fn-definition positions are refused by name since C2-6a
(`fn f(s: [u8])` "a slice cannot be a parameter (6.7.8: slices are fn-locals) - …", `fn f(): [u8]` "a slice cannot be
a return type …", a field "a slice cannot be a struct or union field …"). A trait member's signature — parsed since
6.7.8's dyn bite D2, so the two lanes' work meets here — still gives the generic errors:

| Shape (merged 6.7.8 tip) | Result |
|---|---|
| `trait T { fn m(self, s: [u8]): i64; }` | `expected identifier, got '['` |
| `trait T { fn m(self, s: slice<u8>): i64; }` | `unknown type 'slice' for parameter 's'`, then the type-list note |
| `trait T { fn m(self): [u8]; }` | `expected identifier, got '['` |
| `trait T { fn m(self): slice<u8>; }` | `unknown type 'slice' as a fn return type` |
| `trait T { fn m(self, s: [u8]): i64 { return 0; } }` (a default body) | `expected identifier, got '['` |

Each is refused (no binary), so nothing compiles that should not; the message is the one this issue replaces. On 6.7.7
all five compiled (the signature was never parsed).

**Discovered:** 2026-10-10 verifying the C2 lane's C2-6a report that a trait's required-method signature checks no
parameter types (`trait T { fn m(self, s: Nonexist): i64; }` compiled, "and so does `s: [u8]` there") — on the merged
tip the unknown name IS refused by name ("unknown type 'Nonexist' for parameter 's'"), and only the slice spellings
are left mis-diagnosed.

**Root cause.** The trait-signature reader `_trs_type` (`src/frontend/parse_fn.cyr:6749`) has no slice arm: a `[` meets
`_trs_err(S, i, 2)` ("expected identifier"), and the word `slice` reaches `_trs_name` as an unknown type.

**Fix.** In `_trs_type`, before the identifier test, refuse `[T]` / `slice<T>` by name with C2-6a's texts
(`_sl_ann_at` / `_sl_param_refuse` for a parameter, `_ret_ann_alt`'s return text for a return), consuming the whole
`[..]` / `slice<..>`. Rows: the five shapes above, each with C2-6a's exact single diagnostic. Placement of this
residual, by the 2026-10-10 filing rule for diagnostics: 6.7.12 — repair 3 (roadmap.md § *The releases after 6.7.7*)
— placed 2026-10-10 — never 7.x, unless the 6.7.8 integration closes it with this issue (it is the same refusal,
reached from one more reader); it changes no program that compiles.
