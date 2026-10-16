# `ret2(a, b)` in a fn declared to return a vector (`: f64v2` / `f32v4` / `f64v4` / `i32v4`) compiles clean and returns no vector — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.13 multivalue lane (l6713-multivalue, unit M3, the slot-open
compilers of a673123d and the lane tip 68d421a8 alike) on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (multivalue lane; filed from the 6.7.13 multivalue lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — a silent wrong value on code that compiles clean (the caller's vector holds whatever the vector
return registers / the PE result pointer held); `ret2` in a vector fn is rare.
**Discovered:** 2026-10-15, the 6.7.13 multivalue lane (M3), while refusing `ret2(a, b)` in a fn returning a named
struct (issues/2026-10-14-ret2-in-struct-returning-fn-takes-multi-value-path.md, D22 A) — the vector class is outside
that issue's filed surface (named structs).

## Reproduction

```sh
cd <the cyrius tree>
printf 'fn v(): f64v2 { ret2(41, 7); }\nfn main(): i64 { var x: f64v2 = v(); return load64(&x) + load64(&x + 8); }\nvar r = main(); syscall(60, r);\n' > vr.cyr
build/cycc < vr.cyr > vr && chmod +x vr && ./vr; echo $?
# 0     (48 if it were the vector { 41, 7 }; a refusal is what the tuple spelling gets)
```

| fn | x86_64 | aarch64 (qemu) | cx (cxvm) | PE (wine) |
|---|---|---|---|---|
| `fn v(): f64v2 { ret2(41, 7); }` | 0 | 0 | 41 | 0 |
| `fn v(): f64v4 { ret2(41, 7); }` | 0 | 0 | 41 | 0 |
| `fn v(): f32v4 { ret2(41, 7); }` (read with `load32`) | 0 | 0 | 41 | 0 |
| `fn v(): f64v2 { return (41, 7); }` | refused | refused | refused | refused |
| `fn v(): f64v2 { return ret2(41, 7); }` | refused | refused | refused | refused |

The two refused spellings say *a vector-returning fn carries its result in a fixed register pair, so `return` takes a
local of that vector type or a call to a fn declared to return the same one — got `(...)`* / *got `this expression`*
(6.6.6, `_refuse_simd_return` / `_refuse_vector_tuple_return`).

## Root cause

The `ret2` builtin (`src/frontend/parse_expr.cyr`, PARSE_SIMD_EXT's `ptyp == 97` arm) loads rax:rdx and lands through
`_mret_land` (`src/frontend/parse_fn.cyr`). Its context check `_ret2_ctx` refuses it outside a fn (D20), in a 3-value
fn (D21) and, since 6.7.13, in a fn returning a named struct (D22, `_ret2_in_struct`); a fn whose declared return is a
vector (`_cur_fn_returns_vector`, which `_refuse_vector_tuple_return` asks for the tuple literal) is never asked, so
the int-register pair goes back where the caller reads XMM0/XMM1, V0/V1, four cx registers or a PE result pointer.

## For the user

Whether `ret2(a, b)` in a vector-returning fn is refused by the 6.6.6 vector rule's text (as `return (a, b);` there
is) is a language question in the same family as D22; the shape stops compiling if refused. The repair would be one
arm in `_ret2_ctx` beside `_ret2_in_struct` (`_cur_fn_returns_vector(S) == 1` -> the vector refusal at the ret2, once,
in sync) plus rows in tests/gates/codegen/simd_return_shapes.sh (the X10-X12 tuple rows' neighbours).
