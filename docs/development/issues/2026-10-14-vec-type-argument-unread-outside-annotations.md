# A `Vec<..>` still skips its argument unread as a type argument, a multi-value element, a trait member's parameter, a field's nested `Vec<Vec<..>>`, and in a Vec element's own `<..>` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit G4, the compiler built from
the unit's tree, 2,189,720 B): the repro builds with no diagnostic and exits 3. Unit G4
([`2026-10-09-vec-annotation-type-argument-unchecked.md`](archived/2026-10-09-vec-annotation-type-argument-unchecked.md), the
user's decision (a), 2026-10-13: "a `Vec<T>` var / global / parameter / `*Vec<T>` annotation reads and checks its T
the way a struct field does") made a local, a global (either zone), a parameter, `*Vec<T>` / `**Vec<T>`, a
`*fn(Vec<T>)` parameter and `sizeof(Vec<T>)` read T. The positions below were outside that issue's filed surface and
still skip the `<..>` unread, exactly as every Vec annotation did through 6.7.10.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 genfe lane) — never 7.x. Refusing these changes what compiles
(junk between the brackets stops compiling), so whether the decision's "one rule for every `Vec<T>`" extends to them
is the user's call.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit G4 (probing the positions next to the filed ones).
**Severity:** Low — nothing is miscompiled: a `Vec` is an 8-byte `vec_new()` handle whatever its `<..>` says; the text
is just unchecked, and inconsistently so (`var v: Vec<nosuch>` is refused now, `Box<Vec<nosuch>>` is not).
**Affects:** every release through the 6.7.11 lane tree.

## Reproduction

```cyrius
include "lib/vec.cyr"
struct Box<T> { v: T; }
struct H { items: Vec<Vec<nosuch1>>; more: Vec<Box<(i64, i64)>>; }
trait Sh { fn a(self, v: Vec<nosuch2>): i64; }
fn mv(): (Vec<nosuch3>, i64) { return (0, 1); }
fn idv<T>(x: T): T { return x; }
fn main(): i64 {
    var b: Box<Vec<nosuch4>>;
    var w: Vec<Box<nosuch5>> = 0;
    var a, c = mv();
    return idv<Vec<1 + 2>>(c) + 2;
}
syscall(60, main());
```

```
actual:   builds, no diagnostic ("note: 64 unreachable fns"), exits 3
expected: each of the seven `<..>` refused by name, as `var v: Vec<nosuch1>` is since unit G4
          ("unknown type 'nosuch1' as the Vec element of 'v'", "a tuple type cannot be a Vec element",
          "expected a Vec element type ..., got number 1")
```

The seven positions, one each in the repro:

| Position | Reader that skips it |
|---|---|
| a struct field's NESTED `Vec<Vec<..>>` (`items: Vec<Vec<nosuch1>>`) | `_vec_field_elem` (parse_types.cyr) takes the outer element's name and `_skip_targ_list`s its `<..>` |
| a Vec element's own type arguments, field (`Vec<Box<(i64, i64)>>`) and var (`Vec<Box<nosuch5>>`) | the same skip in `_vec_field_elem`, and `_vec_ann_list`'s non-Vec arm (unit G4 kept "skipped as the field form skips it") |
| a trait member's parameter (`fn a(self, v: Vec<nosuch2>)`) | the trait-signature reader (`_trs_type`) |
| a multi-value return element (`(Vec<nosuch3>, i64)`) | the multi-value element reader |
| a generic struct's type argument (`Box<Vec<nosuch4>>`) and a generic call's (`idv<Vec<1 + 2>>`) | `_parse_one_type_arg` (parse_fn.cyr): a `<` after a name that is not a generic struct is `_skip_targ_list`ed |

## Root cause

Each reader above meets `Vec` as a plain name and skips its `<..>` with `_skip_targ_list` / `SKIP_GENERICS`, which
count `<` / `>` depth and read nothing in between. Unit G4's check (`_vec_ann_chk`, parse_types.cyr, beside
`_vec_field_elem`) is a cursor-neutral reader any of these sites can call with the token of the word `Vec`.

## Proposed fix

If the user extends decision (a) to every `Vec<..>`: call `_vec_ann_chk(S, <the Vec token>, -1)` at each reader above
(the field form through the nested arm of `_vec_field_elem`, or by reading the field's element with `_vec_ann_list`),
and decide whether a non-Vec element's own `<..>` (`Vec<Box<..>>`) is read as that generic's annotation is. Rows: the
repro's seven positions refused once each; `Vec<Box<i64>>`, `Box<Vec<i64>>`, `idv<Vec<i64>>(x)`,
`(Box<Box<i32>>, i64, Vec<Box<i64>>)` (tests/tcyr/frontend/nested_type_args.tcyr) and traits_checked.sh V4 unchanged.
