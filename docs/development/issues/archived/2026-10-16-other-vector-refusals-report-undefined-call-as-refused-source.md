# The vector return, the value-form vector argument and a wrapped vector-local source report a call to a missing fn as a refused source — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-7, `91514482c`: a call naming no fn is left to the undefined-function path at the three filed destinations, inside any parentheses. The wrapped local: `_vrcv_nofnw`, asked by `_vrcv_decl_err` and `_vrcv_other`. The return: `_ret_vec_rule`. The value-form argument: `_sar_none`; Win64's gate leaves it to the value push. Before → after (x86_64, aarch64, cx and PE alike): the wrapped local's `2:32: .. got `(...)`` plus the undefined-function lines → the undefined-function lines and "refusing to emit binary" alone; the return's `1:26: a vector-returning fn .. — got `f64v2_splat`` plus the warning → the warning alone — the verbatim repro, whose fn is never called, now builds (exit 1), as an unwrapped vector local in such a fn does; the argument's `2:30: .. got `f64v2_splat``, with no undefined-function line → "undefined function 'f64v2_splat'", "(reachable call site)", "refusing to emit binary". Under `--allow-undef` the call traps (132). No decision needed (diagnostics). Rows: `simd_return_shapes.sh` H12 – H16 (H12 / H16 the filed local / return verbatim) and `simd_pointer_param.sh` VU1 – VU5 (VU1 the filed argument verbatim) and VUK, on x86_64, aarch64, cx and PE. Mutations M-U1 / M-U2 / M-VU2 RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V4, x86_64; the lane's compiler after the
refusal-hint fix). 6.7.13 (issues/archived/2026-10-14-vector-local-refusal-hint-every-source.md) leaves a call `name(..)` naming
no fn to the undefined-function path when it is the source of a value-form vector LOCAL (`var v: f64v2 =
f64v2_splat(1.0);`, `v = f64v2_splat(1.0);`). Three neighbouring vector destinations still report such a call as a
refused source of their own — ahead of the undefined-function warning, or (the argument) instead of it.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
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
