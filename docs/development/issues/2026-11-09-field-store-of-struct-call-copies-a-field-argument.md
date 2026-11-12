# `s.f = g(t.e)` stores the field argument `t.e`, not `g`'s result, when `g` returns a struct — open

**Status:** 🔴 **OPEN** — verified on 6.7.18 (x86_64), 2026-11-09.
**Placement:** unpinned — 6.x-line backlog (a silent wrong-code bug: suggest the next patch).
**Discovered:** 2026-11-09, by impetus's Rust → Cyrius port (M4, the 3D backend's mass properties).
**Reporter:** impetus 2.0.0 port
**Cyrius version at time of report:** 6.7.18
**Severity:** **High: silent wrong code.** It compiles with no diagnostic and stores a plausible value of the right
type: the argument instead of the result.

## Summary

An assignment whose destination is a struct field and whose right side is a call to a struct-returning fn stores the
wrong value when any argument of that call, at any depth, reads a struct-typed field. The destination receives a copy
of that field argument. The callee runs and returns its result correctly, but the result is discarded.

```cyrius
struct V { x: f64; y: f64; z: f64; }
struct L { v: V; u: V; }
fn V_half(q: V): V { var r: V; r.x = q.x * 0.5; r.y = q.y; r.z = q.z; return r; }

l.v.x = 4.0;
l.u = V_half(l.v);        # l.u.x is 4.0, not 2.0: l.u received l.v
```

Measured on 6.7.18 (the repro prints each case):

| Form | Result |
|---|---|
| `l.u = V_half(l.v)`: 24-byte struct, hidden return pointer | **wrong**: stores `l.v` |
| `l.t = W_half(l.w)`: 16-byte struct, two-register return | **wrong** |
| `l.n = M_half(l.m)`: 72-byte struct | **wrong** |
| `p.u = V_half(p.v)` through a `*L` | **wrong** |
| `l.u = V_half(o.v)`: another struct's field | **wrong** |
| `l.u = V_add(w, l.v)`: the field argument second | **wrong**: stores `l.v` |
| `l.u = V_half(V_half(l.v))`: the field nested one call down | **wrong**: stores `l.v` |
| `var t: V = V_half(l.v); l.u = t;` | correct |
| `x = V_half(l.v)`, `var x: V = V_half(l.v)`: a local destination | correct |
| `l.u = V_half(w)`: a local argument | correct |
| `l.u = V_mk(l.v.x)`: an f64-field argument | correct |
| `l.u = l.v.halved()`: a method on a field | correct |
| `l.u = l.u + V_half(l.v)`: the operator form | correct |

It looks as if the field store copies from the last struct-typed lvalue the right side evaluated, rather than from
the call's result storage.

In impetus, `b.inv_inertia = ImMat3_inverse(b.inertia)` left each body's inverse inertia equal to its inertia, and
`self.linear_velocity = ImVec3_scale(self.linear_velocity, damp)` would have dropped the damping. Golden rows caught
the first: 202 of 234 bodies wrong. Any value-struct math stored into record fields is exposed: vectors,
quaternions, matrices, and AABBs folded in place.

## Reproduction

[`repros/2026-11-09-field-store-of-struct-call-copies-a-field-argument.cyr`](repros/2026-11-09-field-store-of-struct-call-copies-a-field-argument.cyr):

```sh
cyrius build docs/development/issues/repros/2026-11-09-field-store-of-struct-call-copies-a-field-argument.cyr /tmp/fsc
/tmp/fsc; echo "exit=$?"
# -- wrong today: a field destination and a struct-field argument --
# l.u = V_half(l.v)            (24 B): WRONG (got x*1000 = 4000, want 2000)
# ... (7 wrong forms) ...
# -- correct today --
# var t = V_half(l.v); l.u = t: ok
# ... (5 correct forms) ...
# 7 stores wrong
# exit=1
```

## Proposed fix

A field store whose right side is a struct-returning call copies from the call's result storage (the hidden return
slot, or the two return registers), as the local-destination and declaration forms already do. Then add the repro's
seven wrong forms as regression rows.

Until that lands, a diagnostic would help: the compiler can see a struct-returning call with a struct-field argument
on the right of a field store, so it could warn there.

## Consumer-side workaround

Bind the call to a local, then store the local: `var t: ImMat3 = ImMat3_inverse(b.inertia); b.inv_inertia = t;`.
impetus does this at every such site (`src/b3_types.cyr`) and its surface-parity gate scans `src/` and `tests/` for
the pattern, so a new site fails the gate.
