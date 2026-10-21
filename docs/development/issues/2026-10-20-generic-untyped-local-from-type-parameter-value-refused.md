# An untyped local initialised from a T-typed value in a generic (`var y = x; return y.b;`) is refused at the definition, though valid at T = Q — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.16 wave-3 genbind lane (GB5), 2026-10-20.
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 wave-3 genbind lane (GB5); placed at the wave-3 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; f16 lane, wave 4, unit FG4) — never 7.x.
**Decision (user, 2026-10-20, wave 3's round):** D102 — y takes T's type in each instance (at a scalar T, `y.b` is refused as `x.b` is: the generic has no scalar instance).
**Severity:** Low — valid cyrius refused (rc 1, no binary).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn g<T>(x: T): i64 { var y = x; return y.b; }
fn main(): i64 { var q = Q { 3, 4 }; return g(q); }
syscall(60, main());
```

rc 1, `3:43: no struct type in scope for 'y'`. `{ var y = x; y = mkp(); return y.b - 400; }` is refused with 6.7.15's D33 words ("cannot assign 'y' from 'mkp'"). Both are valid at T = Q; `var y: T = x;` compiles.

## Root cause

An untyped local's type is read from its initializer at the generic's definition, where `x` has no struct; the instance never re-reads it. 6.7.16's D1 `return &n;` rule already treats `var n = x;` as typed by T.

## Acceptance (D102)

The repro returns 4; at a scalar T (`g(5)`) the generic is refused as a stub (no scalar instance), as `x.b` is. Rows in the generic stub gates on x86_64 / aarch64 / cx / PE.
