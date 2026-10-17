# `var b: bool = fncall0(&isb);` with `isb(): bool` is refused "not a bool" where `var c: bool = isb();` compiles — a known `&f` callee's `: bool` result is an untyped word — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (unit R3, after the D25 / D26 bite) with
`build/cycc` built from that tree (x86_64); the lane base refuses it the same.
**Placement:** 6.7.15 — repair 5 (receives lane; filed from the 6.7.14 receives lane, placed at the 6.7.14 wave-2 integration, 2026-10-17) — never 7.x.
**Severity:** Low — valid-looking source refused loudly, by name; no wrong value. Workaround: `fncall0(&isb) != 0`.
**Discovered:** 2026-10-17, the receives lane, D25 / D26 (issues/2026-10-16-known-callee-pointer-or-f64-result-
untyped.md): those decisions type a known `&f` callee's `: f64` and `: *T` results as the direct call's (6.7.11's D31
"known half"). The direct call's third mark, a `: bool` fn's result being a boolean value (6.7.3 B2,
`_call_ret_ps`' `_BX_MARK`), is outside their filed surface and was left as found.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
fn isb(): bool { return true; }
fn main(): i64 {
    var b: bool = fncall0(&isb);
    var c: bool = isb();
    if (b) { return 7; }
    return 3;
}
syscall(60, main());
```

```
error:<source>:6:19: cannot initialize bool 'b' with a value that is not a bool
  note: a bool takes true / false, a comparison, !x, && / || or another bool - write `x != 0` for an integer
```

## Root cause

`_icall_scalar` (src/frontend/parse_expr.cyr, 6.7.14) applies the direct call's f64 and `*T` marks to a known callee;
the boolean-value mark (`_bx_fn_is_bool` -> `_BX_MARK`, part of `_call_ret_ps`) is not applied, so the bool check
(`_bx_decl`) sees an untyped word.

## The question (the user's)

Is a known `&f` callee's `: bool` result a boolean value, as `isb()`'s is (the same "as the direct call" reading as
D25 / D26) — `var b: bool = fncall0(&isb);`, `callptr(&isb)` and `b = fncall0(&isb);` compile — or does it stay a
word that a bool refuses (documented)? A callee held in a variable stays a word either way (D31).
