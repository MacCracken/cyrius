# A Vec element whose generic struct takes another generic struct's instance (`Vec<Box<Box<R>>>`) is not judged against the outer struct's bound — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GS-9, `1e3aad696` — the user's decision D10, 2026-10-19 at the 6.7.16 open: refuse it at the element, once, nothing created. A Vec element's nested non-base instance stands in its enclosing list's slot as a pending instance (an interned sentinel no impl names, `_pn_of`), judged with the by-value line and printed as the mangler would spell it; nothing is minted. The filed res1.cyr, verbatim, is refused once at 7:16, `generic 'Box': its type argument does not implement trait 'Show'`, the note naming `impl Show for Box$R` (it exited 5) — on x86_64, aarch64, cx and PE. `Vec<SB<UB<R>>>`, a field, a parameter, a global and a generic's `Vec<Box<Box<T>>>` (per instance) alike; an unbounded outer over an instance (exit 5) and `Vec<Box<Box<i64>>>` unchanged; the by-value and the Vec form of one instance report once. Rows: `trait_bounds_checked.sh` VN0 (the filed program verbatim) – VN8. Mutants: the lane's previous compiler → RED 15; MVN1 and MVN2 → RED 1 each. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 generics lane (unit G3), implementing D10 (a)
(issues/archived/2026-10-16-vec-element-generic-struct-bound-unchecked.md: a Vec element's generic struct is held to its
bounds, nothing minted). The filed surface is `Vec<Box<Pt>>`; this is the one shape the check-only read cannot judge,
so it is filed, not extended.
**Placement:** 6.7.16 — Break 2, repair 6 (gensig lane, wave 2, unit GS3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D10 — Refuse it at the element, once, nothing created.
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
