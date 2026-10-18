# A struct field `p: *Box<Zork>` is never checked at its declaration — unused it compiles; each use reports the bad type argument again — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 generics lane (unit G2), surveying the positions of
issues/archived/2026-10-14-generic-pointer-to-generic-struct-return-refused.md (`: *Box<Zork>` in a return). Pre-existing:
identical on the slot-open compiler (2600f67f's build/cycc) and on the lane tree (596d1a89).
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D8 — (a) Refuse it at the field, once, used or not.
**Severity:** Low — an unknown or non-name type argument in a pointer field's annotation compiles silently while
the field is unused; a use is refused (once per use, at the declaration's token). The sibling positions refuse it at
the declaration: a by-value field `b: Box<Zork>`, a pointer field `p: *Zork`, a local, a global, a return.
**Kind:** language (every type-argument position checks its names — guide § Generic Functions, v6.6.8; 6.7.14's D6
(a) applies the rule to signatures).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
struct H { p: *Box<Zork>; n; }
fn main(): i64 { var h: H; h.n = 7; return h.n; }
syscall(60, main());
```

```
$ build/cycc < fa.cyr > fa && ./fa; echo $?
7
```

Expected: refused at the field, once — `unknown type 'Zork' as a type argument (...)` at 3:22, as
`struct H { b: Box<Zork>; n; }` (3:23) and `struct H { p: *Zork; n; }` ("unknown type 'Zork' as the target of pointer
'p'", 3:16) are. The same with `p: *Box<1>` (exit 7; a field's `*Box<1 + 2>` used is refused "a type argument is a
type name, got number 1" since 6.7.14).

| shape | got | want |
|---|---|---|
| `p: *Box<Zork>;`, the field unused | exit 7 | refused once, at the field |
| `p: *Box<1>;`, unused | exit 7 | refused once |
| `p: *Box<Zork>;`, then `h.p.n = 7; return h.p.n;` | two identical errors at 4:24 (one per use) | one |
| `b: Box<Zork>;` — control | refused once (3:23) | — |
| `p: *Zork;` — control | refused once (3:16) | — |

## Root cause

`_add_ptr_field` (src/frontend/parse_types.cyr) takes `_fld_ptr_late` first for a pointer to a struct: it records
T's token for late sizing (6.6.17, so two structs can point at each other) and steps the `<..>` with
`SKIP_GENERICS` — the arguments are not read. They are read only when the field is loaded (`_fld_ptr_sid` /
`_fld_ps_get` -> `_ptr_tok_sid` -> `_gen_ann_sid`), once per use, and `_refuse_type_arg_name` (ERR_IDENT) has no
per-token latch.

## Fix direction

Check the late field's type arguments at the declaration without sizing them (as `_targs_resolvable` reads a list:
each name a struct, a scalar, a bound type parameter or a struct declared later, `_declared_later`) and refuse an
unknown one there, once (`_tn_once` on its token), so a use does not report it again. Rows: the table above; two
structs pointing at each other through `*Box<B>` / `*Box<A>` unchanged.
