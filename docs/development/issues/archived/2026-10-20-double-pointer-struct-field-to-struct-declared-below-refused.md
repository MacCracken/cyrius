# A `**B` / `**Box<B>` struct field with B declared below the struct is refused, while the one-star `*B` field compiles — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FB-3, `ffd4b1ab1` — the user's D103 (2026-10-20): accept it, as `*B` — a pointer field to a struct declared below, at any depth. A field of two stars or more whose pointee is a struct or union declared further down, or a generic struct whose arguments do not resolve yet, is consumed with its type arguments checked as the late one-star field's (`_fld_pp_late` / `_pp_late_name`, src/frontend/parse_types.cyr), and its pin at the struct's `}` keeps the pointee late — sized at the dereference, named at the use (`_pp_word_at`, `_pp_inner`, `_pp_sid`). The filed repro exits 3 (it was rc 1, `2:20: type 'B' is declared after its use`), and `p: **Box<B>` 3 (it was `unknown type 'B' as a type argument`); `***B`, a union's field, two structs pointing at each other through `**B` / `**A`, `**Later<Pt>` with both below, a fn above B and a generic struct's `**B` field compile, and reads through them (`*a.p + 1` steps `sizeof(B)`, `var q: *B = *a.p;`, `**a.p` into a `*B` parameter) are right on every target. A by-value `B` field below stays refused; `**B<i64>` (B no generic) gets D7's line. Rows: `generic_struct_field.sh` PL1 (the filed repro verbatim) – PL10 on x86_64 / `CYRIUS_IR=3` / qemu-aarch64 / cxvm / wine, PLK1 – PLK4 (MPL1 – MPL3 measured: the tree before RED 51); `tests/tcyr/crossos/double_pointer_deref_step.tcyr` LB (52 / 52 on four legs). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found by the 6.7.16 wave-3 genbind lane (GB4), 2026-10-20.
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 wave-3 genbind lane (GB4); placed at the wave-3 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; f16 lane, wave 4, unit FG4) — never 7.x.
**Decision (user, 2026-10-20, wave 3's round):** D103 — Accept it, as `*B` (a pointer field to a struct declared below, at any depth).
**Severity:** Low — valid-shaped source refused (rc 1).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct A { k; p: **B; }
struct B { x; }
fn main(): i64 { var a: A; a.k = 3; return a.k; }
syscall(60, main());
```

rc 1, `2:20: type 'B' is declared after its use`; `**Box<B>` gives "unknown type 'B' as a type argument". `p: *B` (and `*Box<B>`) compiles and exits 3 (6.6.17, 6.7.15's D8 (a)).

## Acceptance (D103)

`**B`, `**Box<B>` (and deeper) fields to a struct declared below compile, as the one-star field does; field reads through them are right on every target; a by-value `B` field below stays refused. Rows beside the one-star rows.
