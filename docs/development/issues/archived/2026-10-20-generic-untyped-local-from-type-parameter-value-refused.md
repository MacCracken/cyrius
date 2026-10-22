# An untyped local initialised from a T-typed value in a generic (`var y = x; return y.b;`) is refused at the definition, though valid at T = Q — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FB-2, `2f8900ebe`, and the review fixes FB-2r `d458f47dc` and FB-2r2 `f6792b43a` — the user's D102 (2026-10-20): y takes T's type in each instance. The stub scan reads an untyped `var y = E;` whose whole initializer is a value of a type parameter — `x`, wrapped, another such local through a chain of any length, a generic call whose `: U` / `: G<..U..>` return binds U to one (nested to any depth), or a carrier `b: Box<T>` by value — as typed by T (`_gs_uvar` / `_gs_vkind`, src/frontend/parse_fn_def.cyr), and the bounded-site scan records it as a receiver (`_bnr_uvar`). The filed repro returns 4 (it was rc 1, `3:43: no struct type in scope for 'y'`); `g(5)` is refused at the call as a stub, "generic 'g' has no i64 (or other scalar) instance ...", with `note: ... 'g' takes a field of a value typed by its type parameter`; never called, it compiles. The second filed shape, `var y = x; y = mkp(); return y.b - 400;`, returns 44 at T = Q (it drew 6.7.15's D33 words) and is D1's stub at 5. A bounded `y.show()` calls the bound's impl at every T. A `*T` value, `*p`, `x.f`, `x + 1` and a name rebound by a closure's `|x|`, a `for x in` or a destructure's later name stay untyped, as the instance types them (FB-2r2). Rows: `struct_result_type_refused.sh` TV0 (the filed repro verbatim) – TV9n, TV10 – TV10s, TV11 – TV11l, TVX on aarch64 / cx / PE (floor 367; MTV1 – MTV9 measured); `tests/tcyr/crossos/generic_struct_only_lines.tcyr` V1 – V21 (33 / 33 on x86_64, qemu-aarch64, cxvm, wine). Not this file's shape, staged by the lane for the user's decision: a generic's T-typed parameter itself rebound by `|x|` / `for x in` / a destructure is still read as T by `x.show()` / `x.b` (SIGSEGV at T = Pt; the same on the lane's base). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found by the 6.7.16 wave-3 genbind lane (GB5), 2026-10-20.
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
