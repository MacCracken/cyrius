# Call-site diagnostics name a method by its mangled fn name (`in a call to 'S_ri'`, `'S_two' expects 2 arguments`) and a generic call by its instance (`'g$i'`) — D27 / A2's vector refusals among them — RESOLVED

> ✅ **RESOLVED in v6.7.14** (FE-23, `cb75b8b7`: one helper, `_fn_src_name(S, fi, noff)`, gives a method `S.ri` / `T.m` from a method record kept where the compiler knows it (GFMETH: pass 1's impl definitions, a call's unknown method, a generic method's instance) and a generic call `g<i32>` / `g2<i32, i64>` / `gx<Box<i64>>` / `g<f64v2>` from its type arguments; the call-site diagnostics use it (6.7.12's D27, 6.7.11's A2, 6.7.13's D31 / D33, the struct type, arity, named arguments, `#pure`, `#deprecated`, `#must_use`, `private`, the destructure, bool / cstring, and "undefined function" on every back end), and a method call's arity counts without `self`; no decision needed. The filed repro is "8:17: … in a call to 'S.ri' - pass &b for its address"; `s.two(1, 2)` is "'S.two' expects 1 argument, got 2"; `s.nope(1)` "undefined function 'S.nope'". Rows: new `frontend/call_site_callee_spelling.sh` N1 (the repro verbatim) – N8 (22 rows, the aarch64 cross too) and the gates moved with the text; mutations RED (19 / 12 of 22). Partly closed: the generics lane's refusals that name a generic METHOD (`generic 'P_pick' has no i64 … instance`, `generic 'P_bm': its type argument does not implement trait 'Show'`) keep the mangled name, because that lane's rows pin the text — filed, 6.7.15 (`2026-10-17-generic-refusals-name-a-generic-method-by-its-mangled-name.md`). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (x86_64; frontend, every target alike). The D27 refusal (6.7.12) and A2's "different vector type" refusal (6.7.11) read `_fnt_names + fi * 8` directly; measured, so do the other call-site diagnostics tried (struct type, arity, named argument, undefined fn) — the review's note that "other diagnostics name the method as written" did not hold for these.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (frontend lane, wave 1, unit F5; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-15, the review of the 6.7.12 fixfirst lane.
**Severity:** Low — a diagnostic names `S_ri` where the source says `s.ri(..)`; the position is right.
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct S { k; }
impl S { fn ri(self, p: *i64): i64 { return *p; } }
fn main(): i64 {
    var s: S; s.k = 1;
    var b: f64v2 = f64v2_make(42, 7);
    return s.ri(b);
}
var rc = main();
syscall(60, rc);
```

```
error:<source>:8:17: cannot pass 'b' to a parameter that is not a pointer to its vector type in a call to 'S_ri' - pass &b for its address
```

The same class, measured on the lane (each with `struct S { k; }` and an `impl S` method):

```
s.rd(f)   (p: *f64v2, f an f32v4)  error:<source>:8:17: cannot pass 'f' to a parameter of a different vector type in a call to 'S_rd'   (6.7.11 the same)
s.ta(b)   (p: *A, b a B)           error:<source>:9:17: cannot pass 'b' to a parameter of a different struct type in a call to 'S_ta'
s.two(1, 2) (fn two(self, a))      error:<source>:6: 'S_two' expects 2 arguments, got 3                                       (6.7.11 the same)
s.ta(a: 1, z: 2)                   error:<source>:6:23: 'S_ta' has no parameter named 'z' - its parameters are: a
s.nope(1)                          warning: undefined function 'S_nope'
g<f64v2>(b) (fn g<T>(p: *T))       ... in a call to 'g$i' - pass &b for its address   (the cascade staged beside this file)
```

## Root cause

The call-site diagnostics print the callee's fn-table name (`_fnt_names + fi * 8`, e.g. `_vec_kind_err` and
`_sarg_vec_ptr` in src/frontend/parse_fn.cyr), which for a method is the mangled `T_m` (`T_Tr_m` for a trait method)
and for a generic call its instance (`g$i`); no shared helper maps a fn index back to its source spelling.

## Proposed fix

One helper (a fn index -> its source spelling: `T_m` -> `T.m` / `s.m`, an instance -> `g<..>`) used by every call-site
diagnostic that names the callee; rows asserting the method spelling in the D27 / A2 / struct-type / arity / named-argument
messages. Changes only diagnostic text; gates that grep `'S_..'` in an expected message move with it.
