# An explicit type argument on a METHOD call (`p.id<f64>(h)`) is refused as "unknown field 'id'" and "undefined variable 'f64'" — RESOLVED

> ✅ **RESOLVED in v6.7.14** (GN-16 (`2e26e069`; the user's decision D7 (a), 2026-10-16: accept it, binding as the free spelling does; a field of the same name still wins): `.m<..>(`, where m is a generic method and no field of the receiver's struct, reads its list as `_explicit_generic_call` does and enters the method arm on that instance (`_meth_targs` / `_meth_xinst`). The filed repro exits 0 (it was refused "unknown field 'id'" + "undefined variable 'f64'") on x86_64, IR=3, aarch64, cx and PE: `var a = p.id<f64>(h);` is an f64; the chained `w.v.id<f64>(h)`, a `*P` receiver, a statement, `p.id<Pt>(q)` in a receive and a 16 / 24 B return, and a bounded `p.bm<f64>(h)` work too; `p.n < k` and `q.id < k` on a field are unchanged. Rows: `frontend/generic_method_infer.sh` E0 (the repro verbatim) – E7; `crossos/generic_method_struct_arg.tcyr` X1 – X14 on seven legs; mutations ME1 and ME3 – ME7 RED (ME2 unproven). Not closed here (filed, 6.7.15): the lookaheads keyed on `x.m(` do not see `x.m<..>(` — `var a, b = p.mm<i64>(3);` is refused "multi-value destructure needs a call on the right-hand side". CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — reported by the 6.7.9 critical lane's review-fix step as "an explicit generic method call is
still not bound f64". Verified 2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379, 2,057,736 B): the
spelling does not compile at all — `p.id<f64>(h)` and `w.v.id<f64>(h)`, in an expression and as `var a =
p.id<f64>(h);`, are each refused with two errors that name the wrong things; nothing is silently mistyped. The
installed 6.7.0 and 6.7.8 compilers refuse it the same way. The inferred spelling `p.id(h)` is right since 6.7.9 (an
f64 `V` binds, `_mcall_gen`), and no test, gate or guide line uses explicit type arguments on a method.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane, wave 1, unit G4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D7 — (a).
**Discovered:** 2026-10-11 during 6.7.9's review of the generic f64 result fix.
**Severity:** Low — a loud refusal; the messages call a method an unknown field and a type an undefined variable.
**Affects:** cycc 6.7.0 – 6.7.9 (measured), every target (frontend).

## Summary

A free generic call takes explicit type arguments (`gid<f64>(h)`, `g<Pt>(p)`); a method call does not. `p.id<f64>(h)`
is read as the field `id` (unknown on `P`) compared with `f64` (an undefined variable) — the `<` taken as less-than.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P { a; }
impl P {
    fn id<V>(self, x: V): V { return x; }
}
fn main(): i64 {
    var p: P = P { 1 };
    var h: f64 = 1.5;
    var a = p.id<f64>(h);
    if (a * 2.0 != 3.0) { return 1; }
    return 0;
}
syscall(60, main());
```

```
error:<source>:9:17: unknown field 'id' on struct 'P'
error:<source>:9:21: undefined variable 'f64' (missing include or enum?)
```

## Proposed fix

1. **The diagnostic (this lane, no decision):** in the method arm, `IDENT <` after `.` where `IDENT` names a GENERIC
   method of the receiver's type is refused once, by name — "explicit type arguments are not taken on a method call:
   write `p.id(h)` (inferred) or the fn form `P_id<f64>(&p, h)`" (the fn form compiles and is right today: the repro
   rewritten that way exits 0) — with the `<..>(..)` consumed.
2. **The decision (the user's, at the open):** whether a method call takes explicit type arguments as a free call
   does. A "yes" routes `p.m<T..>(..)` through `_explicit_generic_call` with the receiver as parameter 0, typed by
   `_call_ret_marks` (so `var a = p.id<f64>(h);` is an f64 binding), with rows on x86_64 / aarch64 / cx / PE.

Rows for part 1: the repro, the chained `w.v.id<f64>(h)`, and a non-generic method followed by a real `<` comparison
(`p.n < k`) unchanged.

## Consumer-side workaround

`p.id(h)` (the argument binds `V`), or the fn form `P_id<f64>(&p, h)`.
