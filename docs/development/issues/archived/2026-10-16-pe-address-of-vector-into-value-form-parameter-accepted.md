# On Windows, `&w` passed to a value-form vector parameter compiles and runs, where x86_64 / aarch64 / cx refuse it — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-6, `4468074a1` (comments in `2ba36a97c`) (the user's decision D33, 2026-10-16: A — refuse on Windows too). `_sarg_pe_vform` takes `&x` no more. The filed repro (`lanes(&w)`) exited 42 on PE; it now prints x86_64's one line (`5:18: .. got `&w``), and so does `lanes((&w))`. The fix the filing named for the receives was taken: Win64's own-call vector receives — `_try_vector_call_assign`, PARSE_VAR's `_f2c` / `_f4c`, `_vrcv_pe_call` and PARSE_RETURN's PE arm — route `name(&x, ..)` to `name_ptr` (`_pe_venter` / `_pe_vroute`), as PARSE_FNCALL's `_fnc_route` does. So `f64v2_add(&a, &b)` goes to `f64v2_add_ptr` on every target, and the six corpus files that broke at 6.7.13's D30 bite run green on PE. A receive of a value-form fn with no `_ptr` sibling (`vadd(&a, &b)`) is refused on PE with x86_64's two lines. cass's native `cycc.exe` refuses the repro with x86_64's line. Rows: `simd_pointer_param.sh` VZa1 (the filed repro verbatim) and VZa2, refused once on x86_64, aarch64, cx and PE; VZa3 (the receives, f64v2 / f64v4, exit 7 on five legs); VZa4; VZa5 (the six files under wine). Mutations M-VZa1 / M-VZa2 RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (after the D30 bite and its review fix,
`0fbeb6de`) and on the lane base (`f59668ad`, `build/cycc` 2,270,008 B). Pre-existing: the base PE compiler accepts it
too; D30's `_sarg_pe_vword` keeps the exemption on purpose.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D33 — A.
**Discovered:** 2026-10-16, the review of the 6.7.13 vectors lane (the D30 bite).
**Severity:** Low — the program computes the right value on Windows (the by-address ABI copies the vector `&w`
points at); the defect is a target divergence: the same source compiles on one target and is refused on the other three.
**Affects:** PE (Win64) only; every value-form vector parameter (`x: f64v2`, `v: f32v4`, `v: f64v4`, `v: f32v8`, the
integer vectors).

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 {
    var w: f64v2 = mkv(4, 2);
    return lanes(&w);
}
syscall(60, run());
```

```
x86_64 / aarch64 / cx (the lane):
error:<source>:5:18: a value-form vector argument to 'lanes' is a local of its type or a call declared to return it (by name, a method, or fncallN / callptr with the callee written `&f`) - got `&w`
PE (the lane and the base, CYRIUS_TARGET_WIN=1, wine): compiles, exit 42
x86_64 (the base): error:<source>:5:18: value-form SIMD arg must be a local IDENT (inline-replay path)
                   error:<source>:5:19: expected ';', got identifier 'w'
```

## Root cause

On Win64 a value-form vector parameter is address-passed (its struct-mask bit), so `&w` reaches `_arg_push_snap`'s
value push, which pushes the address — exactly what the callee's copy-in wants. `_sarg_pe_vword`
(src/frontend/parse_fn.cyr), which refuses every other word there since D30, exempts a leading `&` (TOKTYP 27) on
purpose: Win64's own-call vector receives (`_f2c` / `_f4c`, `_try_vector_call_assign`, `_vrcv_pe_call`, PARSE_RETURN's
PE arm) emit `f64v2_add(&a, &b)` against the VALUE form, without PARSE_FNCALL's `_ptr` overload routing, and refusing
`&x` broke 6 corpus files on PE (measured at the D30 bite).

## What a fix needs

The user's call first: is `&w` into a value-form vector parameter valid cyrius (then x86_64 / aarch64 / cx should take
it, loading the vector through the address), or refused on Windows too (then the PE receive paths must route their
`f64v2_add(&a, &b)` through the `_ptr` form, or mark their own calls so `_sarg_pe_vword` can tell them from source)?
Either way: a row on x86_64 / aarch64 / cx / PE in tests/gates/codegen/simd_pointer_param.sh (VZ), and the guide's D30
paragraph.
