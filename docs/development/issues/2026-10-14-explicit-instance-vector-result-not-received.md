# An explicit-instance generic call returning a vector (`mkg<i64>(41, 7)`) is not received by a value-form vector local — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 callargs lane (after its review fixes, x86_64) and the
slot-open compiler (`0f733aea`). With `fn mkg<T>(a: T, b: T): f64v2`, the inferred call `var v: f64v2 = mkg(41, 7);`
gives 161 (right). The explicit instance is not taken by either receive: `var v: f64v2; v = mkg<i64>(41, 7);` is refused
since 6.7.11 ("a value-form vector local is assigned only from .. a call declared to return it .. - got `mkg`"; the
slot-open compiler compiled it with wrong lanes, exit 0 where 161 is right), and `var v: f64v2 = mkg<i64>(41, 7);` is
refused "value-form SIMD arg must be a 16-byte vector" on both compilers — a misleading message for a call declared to
return exactly that vector.
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the review of the 6.7.11 callargs lane (probes review/rev/vr/k1-k3).
**Severity:** Low — a refusal with a working spelling (the inferred call, or a local of the type); the slot-open wrong
value is closed by 6.7.11's refusal.
**Affects:** every release with value-form vectors and explicit generic calls; every target (frontend).

## Reproduction

```cyrius
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 { var v: f64v2; v = mkg<i64>(41, 7); return lanes(v); }
syscall(60, run());
```

```
$ build/cycc < k3.cyr > k3                        # the 6.7.11 lane compiler
error:<source>:3:35: a value-form vector local is assigned only from a local of its type or a call declared to return it (by name, or fncallN / callptr with the callee written `&f`) - got `mkg`; through a fn pointer held in a variable, give the target an out-pointer
# slot-open (0f733aea): compiles, exit 0 (161 is right)
# `var v: f64v2 = mkg<i64>(41, 7);` — both compilers: error:<source>:3:63: value-form SIMD arg must be a 16-byte vector
# `var v: f64v2 = mkg(41, 7);` — both compilers: exit 161
```

## Root cause

The receives recognise a by-name vector call as `IDENT (` only: `_vrcv_byname` / `_vrcv_vcall` (parse_decl.cyr) and the
older declaration / assignment receives test `TOKTYP(c + 1) == 10`, so `mkg<i64>(` (an IDENT followed by `<`) is not a
call to them, and its declared return is not consulted (the explicit instance's GFRS).

## Proposed fix

Read the call head with `_gcall_open` (which steps over `<..>`, as the struct receives do since 6.6.10) and resolve the
callee with `_gen_resolve_call` (the instance, whose GFRS is the vector); rows in simd_return_shapes.sh beside the
inferred `mkg(41, 7)` row, on x86 / aarch64 / cx / PE.
