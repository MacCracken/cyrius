# An explicit type argument on a METHOD call (`p.id<f64>(h)`) is refused as "unknown field 'id'" and "undefined variable 'f64'" — OPEN

**Status:** 🟡 **OPEN** — reported by the 6.7.9 critical lane's review-fix step as "an explicit generic method call is
still not bound f64". Verified 2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379, 2,057,736 B): the
spelling does not compile at all — `p.id<f64>(h)` and `w.v.id<f64>(h)`, in an expression and as `var a =
p.id<f64>(h);`, are each refused with two errors that name the wrong things; nothing is silently mistyped. The
installed 6.7.0 and 6.7.8 compilers refuse it the same way. The inferred spelling `p.id(h)` is right since 6.7.9 (an
f64 `V` binds, `_mcall_gen`), and no test, gate or guide line uses explicit type arguments on a method.
**Placement:** 6.7.13 — repair 3, the diagnostics lane (roadmap.md § *The releases after 6.7.8*; part 2, the spelling
itself, is the user's call, asked at that release's open) — placed 2026-10-11 — never 7.x.
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
