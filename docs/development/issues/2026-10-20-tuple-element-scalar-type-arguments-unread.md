# A tuple element written with type arguments (`(i64<u8>, i64)`, `(f64<i32>, i64)`, `(bool<u8>, i64)`) compiles with the `<..>` skipped unread, in a local, a global, a parameter and a struct field — OPEN

**Status:** 🟡 **OPEN** — met 2026-10-20 by the 6.7.16 gensig lane (unit GS4) while applying the user's D7 (6.7.16's,
2026-10-19) to issues/2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md. Measured on the lane
head (eafa5a40d) and the lane's base (1e3aad696), x86_64: identical. The tuple element reader is not one of the
positions that filing lists, and refusing the shape changes what compiles, so it is filed, not fixed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 gensig lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16") — never 7.x.
**Severity:** Low — nothing is miscompiled at the written name (the element is the scalar), but the list is never
read, where every other position refuses `i64<u8>` once at the name (6.7.15's D6, 6.7.16's D7).
**Kind:** language (the D6 / D7 rule — "Refuse it once, at the name" — in a reader neither filing listed: the user's
call).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct H { t: (i64<u8>, f64<i32>); k; }
var G: (bool<u8>, i64) = (true, 2);
fn s(u: (i64<u8>, i64)): i64 { var v: (i64<u8>, i64) = (1, 2); return 0; }
fn main(): i64 { var h: H; h.k = 7; return h.k; }
syscall(60, main());
```

```
$ build/cycc < tup.cyr > tup && ./tup; echo $?
7
```

Five tuple elements given type arguments, none reported. (An element that is no tuple type is refused as before:
`(i32<u8>, i64)` is "a tuple element is i64, f64 or bool, not 'i32'", and `(Pt<i64>, i64)` "... not struct 'Pt'".)

Controls on the same compiler, each refused once at the name since 6.7.16's D7: a multi-value return
`fn r(): (i64<u8>, i64)` ("1:10: 'i64' takes no type arguments") and a trait member's tuple parameter
`fn m(self, u: (i64<u8>, i64)): i64;` ("2:27: 'i64' takes no type arguments" — the trait reader reads a tuple's
elements with its one type reader, `_trs_type`). So the same tuple parameter is refused in a trait member and accepted
in a fn.

## Root cause

The tuple element reader (`_tup_elem`, called by `_tup_type`, src/frontend/parse_types.cyr — shared by a local, a
global, a parameter and a field) resolves the element's name (i64 / f64 / bool are kinds 1-3) and then steps the rest
of the element with `_tup_skip_elem`, which counts a `<..>` as depth, so `i64<u8>` is stepped unread; it never asks
`_ngt_refuse`. A trait member's tuple goes through the trait reader instead (`_trs_inner` -> `_trs_type` ->
`_trs_ngt`), which refuses it.

## Fix direction

If the user extends D6 / D7 here: in `_tup_elem`'s name arm, call `_ngt_refuse(S, ti)` for a kind 1-3 element (one
line at the name; `_tup_skip_elem` already steps the list; silent under --syntax-only as D6; mode 0 only, so pass 1's
quiet scan and the replay stay silent). Rows: the program above (five lines, each at its name); a generic
body with two instances once; controls `(i64, f64)`, `(bool, i64)`.
