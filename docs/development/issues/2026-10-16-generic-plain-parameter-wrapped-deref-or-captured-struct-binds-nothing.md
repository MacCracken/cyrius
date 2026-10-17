# Through a generic's plain `x: T` / `p: *T` parameter, a struct argument in parentheses, a whole dereference and a closure-captured struct bind nothing (a struct carrier binds all three since 6.7.11) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 generics lane (unit G5) on the slot-open compiler (2600f67f's
build/cycc) and on the lane's tree after the D8 (a) commit (`4e039c6e`): identical, x86_64.
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16, 6.7.14 generics G5, probing D8 (a)'s spellings
(issues/2026-10-14-generic-pointer-parameter-binds-only-from-pointer-local-decision.md); outside its filed surface.
**Severity:** Low — silent where it compiles (the i64 base runs: `sizeof(T)` 8 for 24); a loud refusal for a captured
struct into `p: *T`. Workaround: spell the type argument (`gs<S>((l))`), or bind to a local first.
**Affects:** every target (frontend); ≤ 6.7.13 and the 6.7.14 lane tree.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct S { v; w; x; }
var GS = S { 5, 8, 3 };
fn gsz<T>(x: *T): i64 { return sizeof(T); }
fn gs<T>(x: T): i64 { return sizeof(T); }
fn m(): i64 { <row> }
alloc_init();
syscall(60, m());
```

```
<row>                                                                  exit (24 = T bound to S)
var l = S { 1, 2, 3 }; return gs(l);                                   24   (the control: a struct local)
var l = S { 1, 2, 3 }; return gs((l));                                 8
var p: *S = &GS; return gs(*p);                                        8
var l = S { 1, 2, 3 }; var f = || gs(l); return fncall0(f);            8
var l = S { 1, 2, 3 }; var f = || gsz(l); return fncall0(f);           rc 1: error:<source>:7:53: cannot pass 'l' to a
                                                                       parameter that is not a pointer to its struct type
                                                                       in a call to 'gsz' - pass &l for its address
var p: *S = &GS; return gsz((p));                                      8    (D8 (a): `gsz(p)` is 24)
return gsz((&GS));                                                     8    (D8 (a): `gsz(&GS)` is 24)
```

Through a struct carrier the same spellings bind (6.7.11, guide § Generic Functions: "Parentheses around the WHOLE
argument and a whole dereference of such a pointer bind `T` as the plain spelling does").

## Root cause

`_infer_conc_at` (src/frontend/parse_fn.cyr) reads a NAME, a call, a float literal and (6.7.14) `&name` at the
argument's first token: a `(` or a `*` there answers i64, and a capture is read only through `p: *T` and only when it
is a `*S` (`_ic_cap`); the carrier reader `_gsc_arg` has `_gsc_wrap` / `_gsc_deref` arms for the first two.
