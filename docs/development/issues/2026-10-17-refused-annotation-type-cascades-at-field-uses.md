# A variable whose annotation type was refused ("unknown type 'Foo'") cascades "no struct type in scope" at each `.field` use — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (l6714-receives at 4e8d8384, x86_64; the
shared frontend, so every target). Identical on the lane base (f133fb2f's `build/cycc`). Met by unit R1 while fixing
issues/archived/2026-10-16-unknown-annotation-type-cascades-into-d24-refusal.md (the D24 cascade on the declaration's OWN line,
fixed there); a later USE of the variable was not part of that filing.
**Placement:** 6.7.15 — repair 5 (receives lane; filed from the 6.7.14 receives lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Low — every shape is refused; the first error is the right one. One invented error follows per use.
**Kind:** bug (diagnostic cascade).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 333; q.b = 4; return q; } }
fn mkq(): Q { var q: Q; q.a = 333; q.b = 4; return q; }
fn main(): i64 {
    var x: Foo = 5;
    return x.a;
}
syscall(60, main());
```

```
error:<source>:6:12: unknown type 'Foo' for variable 'x'
  note: a type is i8..i64, ... (missing include?)
error:<source>:7:15: no struct type in scope for 'x'; a '.field' access needs its struct declaration (missing include?)
```

The same second error for a field STORE after a method initialiser (`var x: Foo = b.mk(); x.a = 1;` ->
`error:<source>:9:9: no struct type in scope for 'x'; a '.field' assignment needs its struct declaration`) and for a
parameter (`fn f(q: *Foo): i64 { return q.a; }` -> "unknown type 'Foo' for parameter 'q'" then
"no struct type in scope for 'q'"). Oddly a free-call initialiser does not cascade (`var x: Foo = mkq(); return x.a;`
gives the one error), so the declaration's initialiser decides whether the use cascades.

Expected: one error, the unknown type; a use of a variable whose annotation was refused says nothing more (the refused
annotation is the cause, and "missing include?" is already the note on it).

## Root cause (not bisected)

`_tn_refuse` (src/frontend/parse_types.cyr) lets the declaration parse on as a plain i64 "so each bad name is reported
once, with no cascade" — but the `.field` arms (`_field_load_on` / PARSE_FIELD_STORE's "no struct type in scope" report)
do not know the variable's type was refused, and report the i64 base. A per-slot "annotation refused" mark (set where
`_tn_ann` / the parameter's annotation refuses, read by the "no struct type in scope" reporters) would end it. The
staged frontend issue 2026-10-17-late-declaration-refusal-cascades-at-its-uses.md is the same class for a struct
refused as a late declaration (its 4th repro is this shape through a refused `struct Q`).
