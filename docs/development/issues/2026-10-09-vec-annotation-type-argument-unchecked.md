# A `Vec<T>` var or parameter annotation never reads its `<T>`, so `Vec<(i64, i64)>` compiles where every other type argument refuses a tuple — OPEN

**Status:** 🟡 **OPEN** — decision only. Verified 2026-10-09 against the merged 6.7.7 tip (`cycc_merged`, 1,916,288 B;
tree @ 06bd8981) and against 6.7.6's `build/cycc`, using
[`repros/2026-10-09-vec-annotation-type-argument-unchecked.cyr`](repros/2026-10-09-vec-annotation-type-argument-unchecked.cyr).
Both compile it with no diagnostic and it exits 1. Under the merged tip, `Box<(i64, i64)>`, `id<(i64, i64)>(..)` and a
struct field `items: Vec<(i64, i64)>` are each refused by name.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
It is a question for 6.7.10's open, which decides the other B4 (tuple) follow-ons.
**Discovered:** the 6.7.7 B4 (tuples) lane, bite T2. Its hand-off records "`var v: Vec<(i64, i64)> = ...` is NOT
refused (it compiled before 6.7.7; the plan's R3 listed it)". Reported out of scope and filed 2026-10-09.
**Severity:** Low. Nothing is miscompiled: a `Vec` is an 8-byte `vec_new()` handle whatever its `<T>` says. The type
argument is just unchecked text.
**Affects:** verified on cycc 6.7.6 and the merged 6.7.7 tip. Older releases were not bisected; the skip predates
both. `(i64, i64)` names a type only from 6.7.7, but 6.7.6 skips it all the same.

## Summary

A `Vec<...>` annotation on a **local, a global (either zone) or a parameter** skips its `<...>` without reading it.
Anything between the brackets compiles: a tuple, an unknown name, or something that is not a type at all
(`Vec<1 + 2>`). Other places check the same text:

| Where | `<(i64, i64)>` | `<nosuchtype>` |
|---|---|---|
| `var v: Vec<..>` (local, global), `fn f(v: Vec<..>)`, `*Vec<..>`, `Vec<Vec<..>>` | compiles | compiles |
| struct field `items: Vec<..>` | "a tuple type cannot be a Vec element" | "unknown type 'nosuchtype' for struct field 'items'" |
| `Box<..>` (a generic struct), `id<..>(..)` (a generic fn) | "a tuple type cannot be a type argument" | refused by name |
| `fn f(): Vec<..>` | "type 'Vec' cannot be a fn return type" (Vec itself refused) | same |

6.7.7 (B4) refuses a tuple as a type argument everywhere it reads one. It deliberately kept the var / parameter form
compiling, because it compiled before 6.7.7 and nothing that compiles may stop compiling without the user's
decision. Refusing it now would be that kind of change, so it waits on the user.

## Reproduction

[`repros/2026-10-09-vec-annotation-type-argument-unchecked.cyr`](repros/2026-10-09-vec-annotation-type-argument-unchecked.cyr):

```sh
build/cycc < docs/development/issues/repros/2026-10-09-vec-annotation-type-argument-unchecked.cyr > /tmp/vecann
chmod +x /tmp/vecann && /tmp/vecann; echo $?      # compiles silently; exits 1
```

## Root cause

`_gen_ann_sid` (`src/frontend/parse_decl.cyr:4366`) handles the token after an annotation's name. When the name is
not a generic struct (`sid <= 0`), and `Vec` never is (`_tn_code(4, 8)`, `parse_types.cyr:100`, "the field
vocabulary's handle"), it calls `SKIP_GENERICS` (`parse_fn.cyr:9472`). That calls `_skip_targ_list`, which only
counts `<` / `>` / `>>` / `>>>` depth and reads nothing in between. The parameter type paths (pass 2 after `_tn_param_check`,
`parse_fn.cyr:13979` ff.; pass 1's prescan, `:11572`) and `_ptr_annot`'s `*T` arm (`parse_types.cyr:753`) skip it
the same way. The field form reads its element through `_vec_field_elem`
(`parse_types.cyr:1850`): a tuple goes to `_tup_pos_refuse(S, "a Vec element")` at `:1852`, a name to
`_vec_elem_code` (`:1832`). That is why only fields refuse.

## Proposed fix

The decision, asked in one line at 6.7.10's open:

- **(a) Read `Vec<T>`'s argument the way the field form does** (`_vec_field_elem`) at the var / parameter / `*Vec<T>`
  sites. A tuple is then refused by name ("a tuple type cannot be a Vec element"), and so is an unknown name. Programs
  that compile today with a non-type in the brackets stop compiling, which needs a CHANGELOG +
  ecosystem-migration.md line.
- **(b) Refuse only a tuple** (`_tup_pos_refuse(S, "a Vec element")` when the `<` is followed by `(`). Smaller, but
  `Vec<nosuchtype>` still compiles.
- **(c) Keep it unchecked and document** in the guide that a `Vec` var's `<T>` is a comment.

(a) is the one that makes every `Vec<T>` read its `T`. It is a language change either way, so it is the user's call.
