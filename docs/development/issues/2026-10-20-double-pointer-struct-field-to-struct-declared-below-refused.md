# A `**B` / `**Box<B>` struct field with B declared below the struct is refused, while the one-star `*B` field compiles — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.16 wave-3 genbind lane (GB4), 2026-10-20.
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
