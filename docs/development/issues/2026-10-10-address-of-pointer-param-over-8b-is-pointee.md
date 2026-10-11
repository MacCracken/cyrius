# `&q` of a `q: *P` PARAMETER is the pointee's address when P is a struct over 8 B — every other pointer gives the slot's — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against 6.7.8 @ 484763ed with the tree's `build/cycc`, and with the
tree's cross compilers: the repro exits 3 on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine). Fixing it changes what a
compiling program does, so the direction is the user's call (it was filed, not fixed).
**Placement:** 6.7.10 — Break 2, repair 1, the call-path lane (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-11 — never 7.x. (the fix changes what programs do — the user's call, asked at that open)
**Discovered:** 2026-10-10 while planning the 6.7.8 checked-`dyn` lane (repro `p11.cyr`, the lane's forming-source
audit); filed by the lane's bite D0.
**Severity:** Medium — a silent wrong value: the same spelling `&q` names two different things, with no diagnostic.
**Affects:** cycc 6.6.6 – 6.7.8. Measured with the installed 6.6.5, 6.6.6, 6.6.20, 6.7.0 and 6.7.7 compilers: 6.6.5
gives the slot's address in every case (the repro exits 0); 6.6.6 onward exits 3.

## Summary

`&q` on a parameter declared `q: *P` evaluates to `q` itself — the address of the caller's struct — when `P` is a struct
over 8 bytes. The same `&q` on a `*P` LOCAL, on a `*Q` parameter where `Q` is 8 bytes or less, and on a `*i64`
parameter evaluates to the address of the slot that holds the pointer, which is what `&` means everywhere else.
So `load64(&q)` reads the pointee's first field in one case and the pointer in the others.

## Reproduction

`docs/development/issues/repros/2026-10-10-address-of-pointer-param-over-8b-is-pointee.cyr`:

```cyrius
struct P { x; y; }
fn via_param(q: *P): i64 { var a = &q; return load64(a); }
fn via_local(p0: P): i64 { var q: *P = &p0; var a = &q; return load64(a); }
fn main(): i64 {
    var p = P { 4, 2 };
    var r1 = via_param(&p);
    var r2 = via_local(p);
    if (r1 == 4) { if (r2 != 4) { return 3; } }
    return 0;
}
var rc = main();
syscall(60, rc);
```

```
actual:   exit 3 (r1 = 4: `&q` of the parameter is &p, so load64 reads p.x; r2 = the pointer: `&q` of the local is its slot)
expected: exit 0 (one meaning for `&q`)
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

The size split, measured the same day on the same four targets (each fn returns 1 when `load64(&q)` read the
pointee's first field, 2 when it read the pointer; the program exits `pa*27 + pb*9 + pc*3 + la`):

```cyrius
struct P { x; y; }
struct Q { x; }
fn pa(q: *P): i64 { var a = &q; if (load64(a) == 4) { return 1; } return 2; }
fn pb(q: *Q): i64 { var a = &q; if (load64(a) == 4) { return 1; } return 2; }
fn pc(q: *i64): i64 { var a = &q; if (load64(a) == 4) { return 1; } return 2; }
fn la(p0: P): i64 { var q: *P = &p0; var a = &q; if (load64(a) == 4) { return 1; } return 2; }
fn main(): i64 {
    var p = P { 4, 2 };
    var s = Q { 4 };
    var n = 4;
    return pa(&p) * 27 + pb(&s) * 9 + pc(&n) * 3 + la(p);
}
var rc = main();
syscall(60, rc);
```

```
6.6.6 – 6.7.8: exit 53 (pa = 1, pb = 2, pc = 2, la = 2) — only the `*P` parameter over 8 B is the pointee
6.6.5:         exit 80 (all 2)
```

## Root cause

`src/frontend/parse_expr.cyr:3103`, the `&IDENT` arm of `_PARSE_FACTOR_IMPL`:

```cyrius
if (_local_is_sptr_param(S, ali) == 1) { EFLLOAD(S, ali); SPSC(S, 1); return 0; }
```

This line is 6.6.6's fix for an ADDRESS-PASSED BY-VALUE struct parameter (`fn h(q: P3)`, whose slot then held the
caller's struct address, so `&q` had to be that address). Since 6.6.16 (C7) such a parameter is copied into an inline
local in the prologue (`_sptr_params_localize`), so the arm no longer fires for it outside a `#naked` fn — measured:
through 6.6.15 `store64(&q, 9)` in `fn bv(q: P)` wrote the caller's struct, from 6.6.16 it writes the copy.

`_local_is_sptr_param` (`src/frontend/parse_fn.cyr:1888`) answers 1 for any parameter slot whose type is a plain
struct over 8 B and whose layout is not inline. A `q: *P` parameter is recorded with the same type (`-sid`) and the
same non-inline layout, so it answers 1 too. Nothing in the arm asks `_is_ptr_param` (`parse_fn.cyr:9752`, the
`GLPTRP` mark `_mark_ptr_param` sets), which the other readers of `_local_is_sptr_param` do ask: `_sptr_param_in`
(`parse_fn.cyr:2329`), `_agc_handle_local` (`parse.cyr:2764`) and `_asg_struct_refused` (`parse.cyr:3027`).
`STRUCTSZ <= 8` returns 0 before that, which is why a `*Q` parameter of 8 B or less keeps the slot's address.

## Proposed fix

Either direction changes what a compiling program does, so the user picks:

- **(a)** `&q` of a `*T` parameter is the slot's address, like every other pointer variable and like 6.6.5:
  add `if (_is_ptr_param(S, ali) == 0)` to the arm. Checked in a scratch tree on 2026-10-10 (x86, not committed):
  the repro then exits 0, the size probe 80, and the workaround below is unchanged.
- **(b)** `&q` of a `*T` parameter is refused by name (a `*T` already is the address; `&q` of it is almost always
  a mistake), keeping the slot's address for a `*T` local.

Add gate rows for a `*P` parameter over 8 B, a `*Q` parameter of 8 B or less, a `*i64` parameter, a `*P` local, a
by-value `P` parameter (its own copy since 6.6.16, so `&q` is the copy's address) and a `#naked` fn's by-value `P`
parameter, on the four targets, with an ecosystem-migration line for (a) or (b).

The 6.7.8 checked-`dyn` lane is not affected: it refuses `&q` of a `*T` as a forming source by name (its F3 row) and
forms from `q` itself.

## Consumer-side workaround

Do not take the address of a pointer parameter; copy it into a local first (`var q2: *P = q; var a = &q2;`), which
gives the slot's address on every version.
