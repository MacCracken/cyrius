# A GENERIC operator fn is dispatched at its i64 base: `b + p` with `fn P1_add<T>(l: P1, r: T): G1<T>` runs T = i64 (the result holds p's address), where the free spelling `P1_add(b, p)` calls `P1_add$Pt` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone, unit Z2, x86_64; the operator dispatch
is the shared frontend), and identical on the lane base (f8139264f's compiler).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16") — never 7.x.
**Severity:** Medium — a silent wrong value (no diagnostic): the operator spelling and the free spelling of the same
call compute different things.
**Kind:** bug — or, if a generic operator fn is not meant to be accepted, a missing refusal; which one is the user's
call (the guide does not say whether an operator fn may be generic).
**Discovered:** by unit Z2 while landing issues/2026-10-18-zone-untyped-generic-method-generic-struct-result-binds-nothing.md
("a generic OPERATOR fn takes the same route"): the zone's reader was made to agree with the dispatch, which calls the
base, so a zone `var y = b + 3;` is the base `G1` as after the first statement. If the dispatch is changed to infer,
the zone's `_gu_minst` operator arm (`_gz_mti < 0`: the base) must change with it.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
struct P1 { a; }
struct Pt { a; }
fn P1_add<T>(l: P1, r: T): G1<T> { var g: G1<T>; g.v = r; return g; }
fn f(): i64 {
    var b = P1 { 30 };
    var p = Pt { 33 };
    var y = b + p;
    var z = P1_add(b, p);
    return y.v * 1000 + z.v.a;
}
syscall(60, f() % 256);
```

```
(rc 0) exit 9
```

`z.v.a` is 33 (`P1_add$Pt`), `y.v` is p's address (the i64 base took the by-value struct's pointer as T); `y.v.a` is
refused "expected ';', got '.'" (y is the base `G1`, v an i64). With `var p = 3;` both agree.

## Root cause

EMIT_OP_DISPATCH / `_EMIT_OP_DISPATCH_AGG` (src/frontend/parse_expr.cyr) look the operator fn up by name
(`BUILD_OP_NAME` -> FINDFN) and call that entry: a generic operator fn's base, with no `_gen_call_head` inference over
the two operands, so a struct operand never instantiates `P1_add$Pt`.
