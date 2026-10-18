# `callptr(&mk4, ..)` / `fncallN(&mk4, ..)` of another vector into a vector local is refused in the generic words, not as a type mismatch — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-8, `42461fe96`: the new `_vrcv_ibad` — the `_vrcv_mbad` twin the filing proposed — refuses a whole `callptr(&f, ..)` / `fncallN(&f, ..)` (inside parentheses too) whose callee returns another vector than the local's. It refuses at the call, before parsing it, in the by-name call's words. The filed repro (`var v: f64v2 = callptr(&mk4, 41);`) printed `4:32: a value-form vector local is initialised only from .. - got `callptr``. It now prints `4:32: vector return type does not match the declared type`; the assignment prints ".. the assigned variable". x86_64, aarch64, cx and PE are alike, and the refusal and its line are unchanged. No decision needed (message text). Rows: `simd_return_shapes.sh` Q5 (the filed repro verbatim) – Q12 (assignment, `fncall1`, wrapped, the same class of another type, 16 into 32 bytes), refused once on host, cx, aarch64 and win64. Mutation M-Q1 RED 32. Staged beside it: the wrapped BY-NAME call and method of another vector keep the generic words (Low). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V4, x86_64). A call through fncallN /
callptr whose callee is written `&f`, `f` declared to return a DIFFERENT vector than the local's, is refused by the
receive's generic refusal ("a value-form vector local is initialised only from a local of its type, a call declared to
return it (by name, a method, or fncallN / callptr with the callee written `&f`) .. - got `callptr`") — whose own list
names the shape the user wrote. The same call by name is refused "vector return type does not match the declared type",
a method as well (D29), and the same call as a value-form argument with A2's "cannot pass 'mk4' to a parameter of a
different vector type".
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-16, implementing issues/archived/2026-10-14-vector-local-refusal-hint-every-source.md (its probe h3).
**Severity:** Low — message text; the refusal and its line are right, no binary is written.
**Affects:** every target (frontend): `_vrcv_src` kind 2 (`_icall_rs_at(S, c) == ty`) falls to the generic refusal.

## Reproduction

```cyrius
include "lib/fnptr.cyr"
fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 { var v: f64v2 = callptr(&mk4, 41); return lanes(v); }
syscall(60, run());
```

```
error:<source>:4:32: a value-form vector local is initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written `&f`) or a dereference of a pointer to its type (`*p`) - got `callptr`
```

The assignment `v = callptr(&mk4, 41);` is the same ("is assigned only from .. - got `callptr`"). By name, `var v: f64v2 =
mk4(41);` gives "vector return type does not match the declared type"; `lanes(callptr(&mk4, 41))` gives "cannot pass
'mk4' to a parameter of a different vector type in a call to 'lanes'".

## Root cause

`_vrcv_src` takes kind 2 only when `_icall_rs_at` equals the local's type; another vector falls to kind 0, and only the
method arm has a mismatch refusal of its own (`_vrcv_mbad`) — there is no kind-2 twin.

## Proposed fix

A `_vrcv_mbad`-like arm for a whole `callptr(&f, ..)` / `fncallN(&f, ..)` whose `_icall_rs_at` is another vector:
"vector return type does not match the declared type" / ".. the assigned variable", in `_vrcv_decl` and `_vrcv_asg`.
Rows beside simd_return_shapes.sh's Q1 / Q2.
