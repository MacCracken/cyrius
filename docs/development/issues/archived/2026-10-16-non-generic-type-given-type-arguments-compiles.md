# A non-generic struct or scalar written with type arguments (`Pt<i64>`, `g<Pt<i32>>`, `i64<u8>`) compiles, the arguments ignored — RESOLVED

> ✅ **RESOLVED in v6.7.15** (GN-3, `b31ed0639` (the user's decision D6 (a), 2026-10-18: refuse it once, at the name): `_ngt_refuse`, called from `_parse_one_type_arg`, `_gen_ann_sid`, the fn definition's parameter and struct-return sites and `_vec_el_args`, refuses a non-generic struct or a scalar followed by `<`. The filed repro, which exited 31, is refused with exactly four lines, each at the name (6:12, 8:16, 10:26, 10:42): "'Pt' is not a generic struct: it takes no type arguments" / "'i64' takes no type arguments"; so are `Vec<Pt<nosuch>>`, `fn f(p: Pt<i64>)`, a `: Pt<i64>` return, a global, a `*Pt<..>` local, `sizeof` and a struct literal head; `Box<Pt>`, `Box<Box<Pt>>`, `Vec<..>` and `Result<..>` are unchanged. ⚠ Partly closed: the filed shapes are refused, but D6's rule does not reach every position yet — a pointer field `p: *Pt<i64>`, a trait member's parameter, a multi-value element `(Pt<i64>, i64)`, a `*fn(Pt<i64>)` / `**Pt<i64>` parameter and a `*i32<u8>` local / global / `: *T` return still compile with the list unread (measured on main, exit 7) — filed: docs/development/issues/2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md (6.7.16). Rows: `generic_type_arg_unknown_refused.sh` NG0 (the filed repro verbatim) - NG8 and a control; `slice_position_refused.sh` K2f; mutations MNG1 - MNG9 each RED. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 generics lane (unit G3), applying D2 (a) to
issues/archived/2026-10-10-unknown-generic-name-accepted-as-type-argument.md. Pre-existing: identical on the slot-open compiler
(2600f67f's build/cycc) and on the lane tree after G3 (fce26f17).
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G1; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D6 — (a) Refuse it once, at the name.
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
