# `var x: Foo = b.mk();` — an unknown annotation type cascades into D24's refusal (two errors on one line); D13 carried the free call's cascade to methods and operators — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.13 receives fix step on the lane tree (l6713-receives at
360a6d05) and the lane base (f59668ad's `build/cycc`): identical on x86_64, aarch64 (qemu), cx (cxvm), PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives lane; filed from the 6.7.13 receives review, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Low — a cascade diagnostic beside the right one; the line is refused either way.
**Discovered:** 2026-10-16, the receives lane's review of the D13 bite (6ab2a9c8, issues/
archived/2026-10-14-scalar-annotation-from-struct-method-or-operator-keeps-first-word.md). The free call's cascade predates the
lane (6.7.11's D24); D13 extends it to a method and an operator. A family member of
`2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md` (the cascade class), filed for this site.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 333; q.b = 4; return q; } }
fn main(): i64 {
    var b = Q { 1, 2 };
    var x: Foo = b.mk();
    return 0;
}
syscall(60, main());
```

```
lane:
error:<source>:6:12: unknown type 'Foo' for variable 'x'
  note: a type is i8..i64, u8..u64, u128, f32, f64, bool, cstring, Result, Option, Tagged, Vec, an enum, a vector type, or a struct or union (a fn-local var also takes a slice [T] / slice<T>; missing include?)
error:<source>:6:18: cannot initialise 'x: Foo' from 'Q_mk', which returns the struct 'Q' - declare 'x: Q' or bind a field
base:
error:<source>:6:12: unknown type 'Foo' for variable 'x'
  note: ...
```

The free call `var x: Foo = mkp();` gives the same two errors on the base (6.7.11) and the lane. An operator,
`var x: Str = a + c;` without lib/str.cyr, gives "unknown type 'Str'" and then "cannot initialise 'x: Str' from
'Q_add' ..." (lane). `var x: Foo = 5;` is refused once.

## Root cause

After "unknown type", PARSE_VAR goes on with the annotation's tokens as a non-struct annotation, so D24's scalar
check (`_rcv_scalar_ann` for the free call, `_scv_rec_ann` for a method / operator, src/frontend/parse_decl.cyr) judges
the initialiser against it and refuses it a second time.

## Fix

When the annotation was refused as an unknown type, skip D24's judgement for that declaration (a flag the unknown-type
report sets for the line, as `_scv_err` does for the zone's replay). Rows: free call, method, operator and `&f` callee
under an unknown annotation, each refused once ("unknown type"), on four legs.
