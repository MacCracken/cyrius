# A Vec element's generic struct is not checked against its bounds: `Vec<Box<Pt>>` with `struct Box<T: Show>` and no `impl Show for Pt` compiles — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 generics lane (unit G3), implementing D5 (a) of
issues/2026-10-14-vec-type-argument-unread-outside-annotations.md (a generic Vec element's own `<..>` is read, by
name, minting nothing). Pre-existing: identical on the slot-open compiler (2600f67f's build/cycc) and on the lane
tree after G3 (fce26f17).
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — a Vec is an 8-byte handle whatever its element is; the annotation states a type the program
could not declare (`var b: Box<Pt>` is refused).
**Kind:** language — D5 (a) decided the element's list is refused BY NAME (unknown names, tuples, non-names); a
bound is a further check (an instance's), which the read deliberately does not mint.

## Reproduction

```cyrius
include "lib/vec.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
struct Box<T: Show> { v: T; n; }
fn main(): i64 {
    var w: Vec<Box<Pt>> = 0;
    return 5;
}
syscall(60, main());
```

```
$ build/cycc < n4.cyr > n4 && ./n4; echo $?
5
```

With `var w: Box<Pt>;` in its place:

```
error:<source>:6:19: generic 'Box': its type argument does not implement trait 'Show'
  note: the bound on type parameter 'T' needs `impl Show for Pt`, and there is none
```

## Root cause

`_vec_el_args` -> `_targ_chk` (6.7.14) reads the element's list with `_ta_chk` set, so `_parse_one_type_arg`
returns the base sid instead of `_instantiate_generic_struct`, whose `_bnd_check_struct` is where a bound is judged
(a struct definition's fields must stay contiguous, so nothing is minted inside one). Before 6.7.14 the list was
not read at all.

## Fix direction

If the user wants the bound checked there: under `_ta_chk`, call the bound check alone (`GSBND` /
`_bnd_check_struct` for the base and the read arguments) without minting the instance, reporting once at the
element. Rows: the repro refused once; `impl Show for Pt` present compiles; a field `Vec<Box<Pt>>` the same.
