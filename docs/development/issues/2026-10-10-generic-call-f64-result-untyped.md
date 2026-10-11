# A generic call's `T = f64` result is an untyped word when T is inferred or only the return type — `gid(h) * 2.0` multiplies bits — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f, `cycc_merged`
2,053,536 B) with the tree's compiler and the cross compilers built from it: the repro exits 7 on x86_64, aarch64
(qemu), cx (cxvm) and PE (wine), where 0 is right, and each failing row warns "integer arithmetic with an f64 right
operand". The installed 6.6.20, 6.7.4 and 6.7.7 compilers also exit 7. The C2 lane reported the explicit, return-only
shape; verifying it found that EVERY inferred call is affected too (`gid(h) * 2.0`).
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-4a (reported only, `~/.cache/c6/c2/changelog_handoff.md` §
*C2-4a — out of scope*: `gg<f64>(&B, 2) * 2.0`); the inferred shapes were found verifying it for this filing.
**Severity:** Medium — a wrong value on source that compiles, with a spurious warning as the only sign (the method
issue's grading); every generic returning `T` at `T = f64` meets it unless the result is bound to an `f64` first.
**Affects:** cycc 6.6.20 – 6.7.8 measured (6.6.20, 6.7.4, 6.7.7, the merged 6.7.8 tip); not bisected further.

## Summary

A call's f64 result must be typed f64 (`SESTYPE(F64_TYID)`) so the next operator takes the float arm. For a generic fn
returning `T`, that happens only on the explicit spelling with a `T`-typed parameter (`gid<f64>(h)`,
`gid2<f64>(h, 1)`). Two shapes leave the result an untyped word holding the double's bits:

1. **Any INFERRED call** — `gid(h) * 2.0` with `fn gid<T>(x: T): T` and `h: f64`; `gid2(h, 1) * 2.0`.
2. **An explicit call whose `T` is only the return type** — `gg<f64>(&h) * 2.0` with `fn gg<T>(q): T`.

The outer `* 2.0` then multiplies the bit pattern as an integer. `var v: f64 = gid(h);` followed by `v * 2.0` is right
(the annotation types the variable); `var v = gid(h);` is an untyped word.

## Reproduction

`docs/development/issues/repros/2026-10-10-generic-call-f64-result-untyped.cyr`:

```cyrius
include "lib/syscalls.cyr"
fn gg<T>(q): T { return load64(q); }
fn gid<T>(x: T): T { return x; }
fn gid2<T>(x: T, k): T { return x; }
fn main(): i64 {
    var h: f64 = 1.5;
    var bad = 0;
    if (gg<f64>(&h) * 2.0 != 3.0) { bad = bad | 1; }      # explicit, T only in the return
    if (gid(h) * 2.0 != 3.0) { bad = bad | 2; }           # inferred
    if (gid2(h, 1) * 2.0 != 3.0) { bad = bad | 4; }       # inferred, an integer last argument
    if (gid<f64>(h) * 2.0 != 3.0) { bad = bad | 8; }      # control
    if (gid2<f64>(h, 1) * 2.0 != 3.0) { bad = bad | 16; } # control
    return bad;
}
var rc = main();
syscall(60, rc);
```

```
expected: exit 0
actual:   exit 7 (rows 1, 2, 4; three "integer arithmetic with an f64 right operand" warnings) on all four targets
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

`src/frontend/parse_expr.cyr`:

- **Inferred (shape 1):** PARSE_FACTOR's call arm runs `PARSE_FNCALL(S, noff)` (which resolves the generic to its
  instance) and then `_call_ret_marks(S, FINDFN(S, noff))` (`:3849`). `FINDFN(noff)` is the generic BASE, whose return
  `T` is recorded as the i64 base's, not `-9`, so `_call_ret_marks` (`:2634`, `GFRS == 0 - 9`) never types the result.
- **Explicit (shape 2):** `_explicit_generic_call` (`:2560`) calls the instance and then only `_call_ret_ps(S, _spec)`
  (`:2597`) — no `_call_ret_marks` on the instance. Why the explicit spelling WITH a `T` parameter is typed right
  (the controls) is not traced; speculation: something in the instance call path types it from the parameter, which a
  return-only `T` does not have.

## Proposed fix

Type a call's result from the fn the call REACHES: have PARSE_FNCALL (or `_gen_resolve_call`) leave the resolved
instance's fi where the factor reads it, and call `_call_ret_marks` on that fi in both the inferred arm (`:3849`) and
`_explicit_generic_call` (`:2597`), making sure the instance's return sid is `-9` at `T = f64` (an f32 `T` checked the
same way: `gid(f) * 2.0` with `f: f32` warns the same "integer arithmetic" today). Rows: the repro's five rows plus `T = f32`, a `*T` return, a generic method
(`p.m(h)`, after [the method issue](2026-10-09-method-call-result-keeps-last-arg-f64-type.md)), a forward call to an
instance, at the four targets; the `var v = gid(h);` binding typed f64.
