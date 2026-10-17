# A non-generic struct or scalar written with type arguments (`Pt<i64>`, `g<Pt<i32>>`, `i64<u8>`) compiles, the arguments ignored — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 generics lane (unit G3), applying D2 (a) to
issues/2026-10-10-unknown-generic-name-accepted-as-type-argument.md. Pre-existing: identical on the slot-open compiler
(2600f67f's build/cycc) and on the lane tree after G3 (fce26f17).
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — nothing is miscompiled at the written name (the struct or scalar is used, the `<..>` is dropped),
but the `<..>` is read by no one: `Box<Pt<nosuch>>` compiles with an unknown name inside it.
**Kind:** language — whether `Name<..>` on a non-generic type is refused (and with what words) is the user's call.
D2 (a) covered `Name<..>` whose Name is NO type and a type parameter given arguments; its question named those
two and said they "run the i64 base", which this shape does not (it runs as `Pt`).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn g<T>(x): i64 { return sizeof(T); }
fn main(): i64 {
    var c: Pt<i64>;
    c.x = 3;
    var b: Box<Pt<nosuch>>;
    b.n = 4;
    return c.x + b.n + g<Pt<i32>>(0) + g<i64<u8>>(0);
}
syscall(60, main());
```

```
$ build/cycc < n1.cyr > n1 && ./n1; echo $?
31
```

3 + 4 + sizeof(Pt) 16 + sizeof(i64) 8: every `<..>` on a non-generic type is skipped unread — a local's annotation
(`var c: Pt<i64>`), a type argument (`Box<Pt<nosuch>>`, `g<Pt<i32>>`), a scalar (`g<i64<u8>>`). The same skip
covers a Vec element's own list when the element is not a generic struct (`Vec<Pt<nosuch>>`, 6.7.14 D5 reads only
a generic element's list).

## Root cause

`_parse_one_type_arg`'s `<` arm (src/frontend/parse_fn.cyr): a name that is not a generic struct but classifies
(`_classify_return_type` != 0: a struct, a scalar) has its list `_skip_targ_list`ed and returns its class; since
6.7.14 only class 0 (no type) is refused (`_targ_bad_gen`). `_gen_ann_sid` (parse_decl.cyr) does `SKIP_GENERICS` for
a non-generic struct (`GSTP == 0`), and the scalar annotation paths skip `<..>` the same way.

## Fix direction

If the user decides `Name<..>` on a non-generic type is refused: one refusal ("'Pt' is not a generic struct: it
takes no type arguments" or the user's words) at the name, once (`_tn_once`), the list skipped — in
`_parse_one_type_arg` (class != 0, `base_sid` non-generic or a scalar) and `_gen_ann_sid`'s non-generic arm. Rows:
the four shapes above, `Vec<Pt<..>>`, controls `Box<Pt>`, `Box<Box<Pt>>`, `Vec<..>`, `Result<..>` (its own refusal).
