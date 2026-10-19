# A generic whose body writes a field of a `Box<T>` field (`g.v.v = v` with `g: G1<Box<T>>`) is judged a stub: `mkn<i32>(33)` is refused "generic 'mkn' has no i64 (or other scalar) instance: it uses its type parameter as a struct", then "expected ';', got '.'" at `x.v.v` — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 receives lane (unit R4) while probing the zone generic-instance
shapes of issues/2026-10-17-zone-untyped-generic-struct-instance-call-binds-nothing.md; pre-existing (the R3 tip
326c1b56a gives the same), in a fn as at top level. Measured on x86_64; the frontend is shared, so every target.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 receives lane, wave 3; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — valid code refused, two errors (the second a cascade).
**Kind:** bug (generics: the stub scan).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Box<T> { v: T; }
struct G1<T> { v: T; }
fn mkn<T>(v: T): G1<Box<T>> { var g: G1<Box<T>>; g.v.v = v; return g; }
fn f(): i64 { var x = mkn<i32>(33); return x.v.v; }
syscall(60, f());
```

```
error:<source>:5:32: generic 'mkn' has no i64 (or other scalar) instance: it uses its type parameter as a struct (a '.field' on a T-typed value, directly or in a generic it forwards T to) — pass a struct argument, or name a struct type argument
error:<source>:5:47: expected ';', got '.'
```

The same body returning `Box<T>` (`fn mkn<T>(v: T): Box<T> { var g: Box<T>; g.v = v; return g; }`, `return x.v;`)
compiles and exits 33. `g.v` is a `Box<T>` and `.v` of it is a T: no `.field` is taken on a T-typed value.

## Root cause (by reading; to confirm)

The stub scan (`_gen_record` -> `_gs_scan`, src/frontend/parse_fn.cyr) marks a generic whose body takes a `.field` on
a T-typed value; it appears to read `g.v.v` as a field of `g.v`'s declared `T` through the nested instance's list
(`G1<Box<T>>`'s `v: T` read with T unbound), rather than as `Box<T>`'s field. The second error follows from the call
being refused (`x` left untyped).
