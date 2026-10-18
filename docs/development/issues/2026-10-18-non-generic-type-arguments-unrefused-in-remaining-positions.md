# `Name<..>` on a non-generic struct or a scalar is still unread (or refused with other words) in the positions 6.7.15's D6 readers do not reach — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 generics lane (unit G1), applying 6.7.15's D6 (a) to
issues/2026-10-16-non-generic-type-given-type-arguments-compiles.md. Measured on the lane tree after that bite (the
D6 refusal is in `_parse_one_type_arg`, `_gen_ann_sid`, the fn definition's parameter and struct-return sites and
`_vec_el_args`).
**Placement:** unplaced — filed from the 6.7.15 generics lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — nothing is miscompiled at the written name (the struct or scalar is used, the `<..>` dropped),
but a name inside the list is never checked, and four positions refuse the shape with a parse error instead of D6's
words (one of them with a cascade).
**Kind:** language (the positions are the user's D6 rule — "Refuse it once, at the name" — in readers its filing did
not list: whether D6 extends to them is the integration's / the user's placement).

## Reproduction

Compiles (rc 0) — the five positions that skip a non-generic `<..>` unread:

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct H { p: *Pt<i64>; k; }
trait Sh { fn m(self, p: Pt<i64>): i64; }
fn mv(): (Pt<i64>, i64) { var p: Pt; return (p, 3); }
fn ap(cb: *fn(Pt<i64>): i64): i64 { return 0; }
fn dp(p: **Pt<i64>): i64 { return 0; }
fn main(): i64 { var h: H; h.k = 7; return h.k + ap(0) + dp(0); }
syscall(60, main());
```

```
$ build/cycc < stage1.cyr > s1 && ./s1; echo $?
7
```

Refused, but by a parse error rather than D6's words (a scalar return also cascades):

```cyrius
struct Pt { x; y; }
fn f(): i64<u8> { return 3; }
syscall(60, f());
```

```
error:<source>:2:12: expected '{', got '<'
error:<source>:2:17: undefined variable 'u8'
```

```cyrius
struct Pt { x; y; }
struct H { f: Pt<i64>; g: i64<u8>; k; }
fn s(): i64 { var a: [Pt<i64>] = 0; return 0; }
syscall(60, 7);
```

```
error:<source>:2:17: expected identifier, got '<'
error:<source>:3:25: expected ']', got '<'
```

A pointer to a SCALAR written with type arguments also compiles unread in a local, a global and a `: *T` return
(added by the lane's review, 2026-10-18; the same programs exit 7 on the slot-open compiler b2e1f4c48), where the
`p: *i32<u8>` parameter and a `*Pt<i64>` local, parameter or return are refused by D6:

```cyrius
fn f(): i64 { var d: *i32<u8> = 0; return 0; }
fn main(): i64 { return f() + 7; }
```

```cyrius
var gd: *i32<u8> = 0;
fn main(): i64 { return 7; }
```

```cyrius
fn f(): *i32<u8> { return 0; }
fn main(): i64 { var p = f(); return 7; }
```

```
$ build/cycc < each.cyr > b && ./b; echo $?
7
```

Controls on the same compiler: `fn f(p: *i32<u8>): i64` is "1:10: 'i32' takes no type arguments" and
`var p: *Pt<i64> = 0;` is "2:26: 'Pt' is not a generic struct: it takes no type arguments", each once.

With D6 applied everywhere each would be one line at the name: "'Pt' is not a generic struct: it takes no type
arguments" / "'i64' takes no type arguments".

## Root cause

The readers of these positions skip a `<..>` after a non-generic name (`SKIP_GENERICS`) or never expect one:

- a pointer field `p: *Pt<..>`: `_fld_ptr_late` / the quiet `_ptr_step_peek` (pass 1) and `_ptr_tok_sid` at a use (the
  D6 bite keeps `_ptr_tok_sid` silent, so a use never reports out of source order); the generic analogue is
  issues/2026-10-16-pointer-field-generic-type-args-read-only-at-use.md (6.7.15's D8, unit G2);
- a trait member's parameter `_trs_type`, a multi-value element `_mret_elem`, a `*fn(..)` parameter `_pty_name` /
  `_pty_end`: the generic analogue is issues/2026-10-16-generic-type-args-unread-in-mret-trait-and-fn-pointer-signatures.md
  (6.7.15's D7, unit G2) — the same three readers;
- a `**Pt<..>` parameter: `_pty_end` (the reader behind two stars);
- a scalar return `: i64<u8>`: `_PARSE_FN_DEF_IMPL`'s scalar-return arm consumes the name and leaves the `<` to the
  body's `{` check;
- a `*i32<..>` local, global or return: `_ptr_annot` (src/frontend/parse_types.cyr, the reader of those three `*T`
  annotations) skips the pointee's `<..>` with `SKIP_GENERICS`; a struct pointee is refused on its way through the
  struct path, a scalar one is not (the parameter reader in `_PARSE_FN_DEF_IMPL` calls `_ngt_refuse` for both);
- a by-value field `f: Pt<..>` / `g: i64<..>` (`PARSE_STRUCT_DEF`'s field reader) and a slice element `[Pt<..>]`
  (`_tn_slice_w`) do not expect a `<` after a non-generic name.

## Fix direction

Call the D6 helper (`_ngt_refuse(S, name_ti)`, src/frontend/parse_types.cyr) at each reader before it skips the list —
alongside G2's D7 / D8 reads of the same positions, which read a generic struct's list there — and skip the list in the
three readers that do not (scalar return, by-value field, slice element), so each is one line at the name.
