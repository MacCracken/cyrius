# A user struct named like a float vector type (`struct f32v4 { .. }`) is a struct as a local and a vector as a parameter type — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V1) and its base compiler (`f59668ad`):
`var s: f32v4; s.a = 5;` declares the user's struct, while `fn g(v: f32v4)` makes `v` the SIMD vector, so `v.a` is
refused "SIMD vector has no named fields". The same for `f64v2` / `f64v4`, and since 6.7.13 for `f32v8` (the value-form
f32v8 bite gave `f32v8` its parameter class, `_classify_param_type` 10, which reads the name before any struct lookup,
as the other three do).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane; filed from the 6.7.13 vectors lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-16, the 6.7.13 vectors lane, checking what the f32v8 parameter class changes
(`archived/2026-10-15-value-form-f32v8-parameter-receives-one-word.md`).
**Severity:** Low — a name collision with the stdlib's own vector types, refused by a (misleading) message, never a wrong
value. ⚠ Behaviour change in 6.7.13: a `struct f32v8` used as a VALUE parameter type compiled through 6.7.12 (it was
the struct) and is now refused like `struct f32v4`'s; as a `*f32v8` parameter it is still the struct's pointer.
**Affects:** every target; the four float vector names (`f32v4`, `f32v8`, `f64v2`, `f64v4`) as a user struct's name.
The integer vector names are classified the same way (the negative descriptors).

## Reproduction

```cyrius
struct f32v4 { a; b; c; }
fn g(v: f32v4): i64 { return v.a; }
fn main(): i64 { var s: f32v4; s.a = 5; return g(s); }
syscall(60, main());
```

```
$ build/cycc < r.cyr > r        # every target, the 6.7.13 base and the lane
error:<source>:2:33: SIMD vector has no named fields
# `struct f32v8` in the same shape: through 6.7.12 compiled, exit 5; 6.7.13: the same refusal
```

## Root cause

`_classify_param_type` (src/frontend/parse_fn.cyr) is pure byte-compares over the name, by design (the two parameter
scans must agree, and it carries no lookup), so a vector name wins in a parameter; the declaration path and
`_classify_return_type` look the struct up first (FINDSTRUCT), so the struct wins there. Nothing refuses the struct's
declaration.

## Fix direction

The user's call (what the name means): either refuse `struct <vector name>` at its declaration by name (the vector
types are the language's), or have every reader prefer the declared struct (both parameter scans would need the struct
table, in the same order, so they still agree). Rows on x86_64 / aarch64 / cx / PE.
