# The vector return, the value-form vector argument and a wrapped vector-local source report a call to a missing fn as a refused source — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V4, x86_64; the lane's compiler after the
refusal-hint fix). 6.7.13 (issues/2026-10-14-vector-local-refusal-hint-every-source.md) leaves a call `name(..)` naming
no fn to the undefined-function path when it is the source of a value-form vector LOCAL (`var v: f64v2 =
f64v2_splat(1.0);`, `v = f64v2_splat(1.0);`). Three neighbouring vector destinations still report such a call as a
refused source of their own — ahead of the undefined-function warning, or (the argument) instead of it.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane; filed from the 6.7.13 vectors lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-16, implementing the refusal-hint issue (its filed surface is the unwrapped `IDENT (` of the
local's declaration / assignment).
**Severity:** Low — diagnostic text and order only: each shape is refused, no binary is written.
**Affects:** every target (frontend): `_vrcv_decl_err`'s wrapped source (`_vrcv_offender` "(...)"), PARSE_RETURN's vector
refusal (parse_fn.cyr, "a vector-returning fn carries its result .."), the value-form argument's `_sar_err`.

## Reproduction

```cyrius
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 { var v: f64v2 = (f64v2_splat(1.0)); return lanes(v); }
syscall(60, run());
```

```
error:<source>:2:32: a value-form vector local is initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written `&f`) or a dereference of a pointer to its type (`*p`) - got `(...)`
warning: undefined function 'f64v2_splat'
warning: undefined function 'f64v2_splat' (reachable call site)
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
```

```cyrius
fn bad(): f64v2 { return f64v2_splat(1.0); }
syscall(60, 1);
```

```
error:<source>:1:26: a vector-returning fn carries its result in a fixed register pair, so `return` takes a local of that vector type or a call to a fn declared to return the same one — got `f64v2_splat`
warning: undefined function 'f64v2_splat'
```

```cyrius
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 { return lanes(f64v2_splat(1.0)); }
syscall(60, run());
```

```
error:<source>:2:30: a value-form vector argument to 'lanes' is a local of its type or a call declared to return it (by name, a method, or fncallN / callptr with the callee written `&f`) - got `f64v2_splat`
# no undefined-function line at all: the missing include is never named
```

The unwrapped local (`var v: f64v2 = f64v2_splat(1.0);`) gives only the two undefined-function warnings and the
refusing-to-emit line since 6.7.13.

## Root cause

Each destination decides "is this a call declared to return the vector?" (`_vcall_fi` / `_svc_rs`) and refuses every
other source, without asking whether the call's name resolves at all. 6.7.13's `_vrcv_nofn` (parse_decl.cyr: `IDENT (`,
FINDFN none or only the entry an earlier such call registered — `GFDS` 0, no code; not `sizeof` / `mulh64`) answers it
for the vector local's two refusal sites, unwrapped. The wrapped local source (`_ie_unparen` first), PARSE_RETURN's
vector arm and `_sar_src` / `_sar_err` could ask the same question.

## Proposed fix

Ask `_vrcv_nofn` (inside any parentheses) at the three sites and leave such a call to the undefined-function path;
rows in simd_return_shapes.sh (the return, the wrapped local) and simd_pointer_param.sh (the argument) beside H5 / H9.
