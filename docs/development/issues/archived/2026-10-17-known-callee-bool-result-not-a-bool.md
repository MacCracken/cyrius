# `var b: bool = fncall0(&isb);` with `isb(): bool` is refused "not a bool" where `var c: bool = isb();` compiles — a known `&f` callee's `: bool` result is an untyped word — RESOLVED

> ✅ **RESOLVED in v6.7.15** (RC-9, `b8f51c75a` — the user's decision D30 (a), 2026-10-18: as the direct call. `_icall_scalar` (src/frontend/parse_expr.cyr) gives a `: bool` known callee the direct call's boolean stamp (`_BX_MARK`). The filed repro, refused "cannot initialize bool 'b' with a value that is not a bool" (6:19), exits 7 on x86_64, aarch64 (qemu), cx and PE (wine); `callptr(&isb)`, `b = fncall0(&isb);`, a wrap, `fncall1(&isb1, 3)`, `return fncall0(&isb);` from a bool fn and a bool parameter compile too. A callee held in a variable (6.7.11's D31), an `: i64` callee and `fncall0(&isb) + 0` are still refused. Nothing that compiled changes. Rows: `frontend/bool_checked.sh` K1 (the repro verbatim) – K10; `crossos/fncall_scalar_result.tcyr` group B (23 / 23 on four legs and on pi, ecb, ach, cass); mutation RED K1 – K7. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (unit R3, after the D25 / D26 bite) with
`build/cycc` built from that tree (x86_64); the lane base refuses it the same.
**Placement:** 6.7.15 — repair 5 (receives lane, wave 3, unit R3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D30 — (a) yes, as the direct call.
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
