# `*p` of a `*V` at the destinations D34 did not name: `return *p;` from a `: f64v2` fn is refused, and an untyped `var v = *p;` binds one word (lane 0) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V3, after the D34 bite,
issues/archived/2026-10-13-vector-dereference-into-vector-local-decision.md, which made `var v: f64v2 = *p;` / `v = *p;` copy the
vector through the pointer). Both shapes behave as on the lane base (unchanged by D34).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D35 — A; D36 — A.
**Severity:** Low — (1) is a refusal by name (no wrong value); (2) is silent: `v` is one untyped word, so a read of a
second lane through `&v + 8` reads the next stack slot (the user's own out-of-bounds read of a word local), and
`lanes(v)` into a value-form parameter is refused ("must be a 16-byte vector").
**Kind:** language (decision) — D34's question named the annotated declaration and the assignment; its recommendation
("`*pv` one meaning at every destination") reaches these two, which the user did not decide.
**Discovered:** 2026-10-16, the 6.7.13 vectors lane (V3), probing D34's neighbours.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn dr(p: *f64v2): f64v2 { return *p; }
fn run(): i64 { var w: f64v2 = mkv(41, 7); var v: f64v2 = dr(&w); return lanes(v); }
syscall(60, run() % 256);
```

```
every target (x86_64, IR=3, aarch64, cx, PE):
error:<source>:5:34: a vector-returning fn carries its result in a fixed register pair, so `return` takes a local of
that vector type or a call to a fn declared to return the same one — got `this expression`
```

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 { var w: f64v2 = mkv(41, 7); var p: *f64v2 = &w; var v = *p; return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
```

```
x86_64 2, IR=3 226, aarch64 10, cx 98, PE 146      (no diagnostic; 161 would be the copied vector)
the annotated `var v: f64v2 = *p;` (D34): 161 on every target
```

## Root cause

(1) PARSE_RETURN's vector arms (src/frontend/parse_fn.cyr: `_simd_ret_call_ok` and the `return IDENT;` branches) take a
local of the vector type or a call declared to return it; a dereference is neither, so the 6.6.6 return rule refuses
it. (2) An unannotated declaration infers a vector only from a call (`var v = mkv(..)`, 6.7.13 `callptr(&f, ..)`);
`_vrcv_decl` (src/frontend/parse_decl.cyr) asks D34's kind-4 source only under a vector annotation, so `var v = *p;`
takes the scalar path: one word, the value `*p` reads (lane 0).

## The question

(1) `return *p;` from a `: V` fn with `p: *V`: copy the vector through the pointer into the return (as `return q;` of a
local does), or keep refusing it? (2) An untyped `var v = *p;` with `p: *V`: declare a `V` local copied through the
pointer (as `var v = mkv(..)` infers its vector), keep the word, or refuse it by name?
