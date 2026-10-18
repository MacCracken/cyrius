# A Vec element whose generic struct takes another generic struct's instance (`Vec<Box<Box<R>>>`) is not judged against the outer struct's bound — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 generics lane (unit G3), implementing D10 (a)
(issues/2026-10-16-vec-element-generic-struct-bound-unchecked.md: a Vec element's generic struct is held to its
bounds, nothing minted). The filed surface is `Vec<Box<Pt>>`; this is the one shape the check-only read cannot judge,
so it is filed, not extended.
**Placement:** unplaced — filed from the 6.7.15 generics lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — a Vec is an 8-byte handle; the annotation states a type the program could not declare by value.
**Kind:** language (an outer bound on a nested instance; whether to judge it without minting the inner instance, or
to mint it, is the user's call — D10 (a) says "No new instance is created").

## Reproduction

```cyrius
include "lib/vec.cyr"
trait Show { fn show(self): i64; }
struct R { r; }
struct Box<T: Show> { v: T; n; }
impl Show for R { fn show(self): i64 { return self.r; } }
fn main(): i64 {
    var w: Vec<Box<Box<R>>> = 0;
    return 5;
}
syscall(60, main());
```

```
$ build/cycc < res1.cyr > res1 && ./res1; echo $?
5
```

The same type by value is refused, on the outer bound:

```
error:<source>:7:23: generic 'Box': its type argument does not implement trait 'Show'
        var b: Box<Box<R>>;
                          ^
  note: the bound on type parameter 'T' needs `impl Show for Box$R`, and there is none
```

The inner `Box<R>` IS judged at the element since 6.7.15 (`Vec<Box<Box<Pt>>>` with no `impl Show for Pt` is refused
naming `Pt`); only the outer struct's bound on the inner INSTANCE is not.

## Root cause

A Vec element's list is read by `_targ_chk` (`_ta_chk`: nothing minted, since a struct definition's fields must stay
contiguous in the field pool). A nested `Box<R>` is read as its base sid, so the outer `Box`'s argument is not the
instance `Box$R` that `_instantiate_generic_struct` would judge (`_bnd_impl` compares the impl's type NAME with the
instance's mangled name). 6.7.15's `_tck_nest` marks such a list unjudgeable (`_tck_nj`) rather than judge it against
the base, which `impl Show for Box` would wrongly satisfy.

## Fix direction

Judge the outer slot without the instance's sid: an argument that is a non-base instance can only satisfy a bound if
an impl names that instance, and no source spelling does — so the outer slot fails whenever it is bounded; report it
with the instance's would-be name (`_mint_generic_name`) for the note. Or, if the user prefers, mint the inner
instance where that is safe (a local / a parameter, not a struct field). Rows: the repro refused once naming
`impl Show for Box$R`; `Vec<Box<Box<R>>>` with an unbounded outer struct unchanged; `Vec<Box<Box<i64>>>`'s inner base.
