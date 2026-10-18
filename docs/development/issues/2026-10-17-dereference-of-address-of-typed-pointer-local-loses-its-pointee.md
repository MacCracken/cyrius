# `*(&p)` of a typed pointer local loses p's pointee: `**(&p)` with `p: *f64v2` is no vector at any vector destination — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (unit V4, while writing the D35 / D36 rows:
`return *p;` and an untyped `var v = *p;` with `p: *V`). Pre-existing: the lane base (c3af6501) gives the same refusals
and the same one-word untyped binding. Frontend: x86_64, x86_64 IR=3, aarch64, cx and PE alike.
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D21 — A: `*(&p)` is p, type kept.
**Severity:** Low — every typed vector destination refuses it by name (no wrong value there); the untyped declaration
binds one word, as it does for any dereference of an untyped word.
**Kind:** language (a typing gap) — `&x` of a pointer local carries no step word (6.7.11's D15: `&x + n` steps bytes), so
`*(&p)` is an untyped word, not the `*f64v2` p is. 6.7.13 typed `*&w` of a VECTOR name (`_amp_vd`); `&p` of a POINTER
name was not in that filing. Whether `*(&p)` should be p (its type kept) is a language question for the user.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn rd(p: *f64v2): i64 { return load64(p) * 10 + load64(p + 8); }
fn dr(p: *f64v2): f64v2 { return **(&p); }
fn run(): i64 {
    var w: f64v2 = mkv(41, 7);
    var p: *f64v2 = &w;
    var a = rd(*(&p));
    var b = lanes(**(&p));
    return a + b;
}
syscall(60, run() % 256);
```

```
x86_64 and PE (cross), identical:
error:<source>:6:34: a vector-returning fn carries its result in a fixed register pair, so `return` takes a local of that vector type or a call to a fn declared to return the same one — got `this expression`
error:<source>:11:19: a value-form vector argument to 'lanes' is a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written `&f`) or a dereference of a pointer to its type (`*p`) - got `*...`
```

The declaration, x86_64 / IR=3 / aarch64 / cx / PE: `var v: f64v2 = **(&p);` is refused ("a value-form vector local is
initialised only from .. - got `*...`"), and the untyped `var v = **(&p); return load64(&v) * 10 + load64(&v + 8);`
compiles to one word (lane 0) and reads the next stack slot as its second lane (x86_64 2 / 130 / 162 on three runs of
one binary, aarch64 26, cx 98, PE 146 — 161 would be the vector). `**p2` of a `p2: **f64v2` is the vector everywhere.

## Root cause

`_dop_vd` / `_pk_word` (src/frontend/parse_expr.cyr) read the dereference operand's step word; `&p` sets none (the
address-of a local is a plain byte pointer by 6.7.11's D15), so the inner `*(&p)` loads p's value with no pointee and
the outer `*` sees no vector. `_amp_vd` covers only `& NAME` where NAME is itself a vector.

## The question

Is `*(&p)` p — its pointee kept (`**(&p)` the vector at every destination, `(*(&ps)).x` a field read) — or an untyped
word as today? If p, `_amp_vd`'s sibling: an inner `*(& NAME)` of a typed pointer NAME takes NAME's step word.
