# `var n: i64 = fncall1(&mk3, 5);` (a struct over 8 B through a known fn pointer into a scalar annotation) compiles and reads the first field, where `var n: i64 = mk3(5);` is refused (D24) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 tree (main 0601aff4, `build/cycc` 2,223,320 B, x86_64).
Found by the 6.7.11 release-docs pass: two lanes' rules meeting on the merged tree (the user, 2026-10-14: "file and fix
them in 6.7.12").
**Placement:** 6.7.12 — repair 2: the platform release (fixfirst lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D28 — refused as D24 refuses mk3(5).
it extends decision D24 (user, 2026-10-13) to a shape D24's text does not name; confirm, or keep the first-field read and
document it.
**Severity:** Low — silent first-field read; the direct call is refused by name.
**Affects:** cycc 6.7.11 — ARG-1 (8359e5a4) made `fncallN(&f, ..)` / `callptr(&f, ..)` of a known struct-returning
callee "a struct value, as `f(..)` is"; RET-8 (92b690cb) refuses a struct over 8 B into a scalar annotation for a direct
or generic call only.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct P3 { a; b; c; }
fn mk3(x): P3 { var r = P3 { x, x + 1, x + 2 }; return r; }
fn main(): i64 { var n: i64 = fncall1(&mk3, 5); var m: i64 = callptr(&mk3, 5); return n * 10 + m; }
syscall(60, main());
```

```
compiles, no diagnostic; exits 55 (n = 5, m = 5: each reads P3.a)
```

The direct call, for comparison:

```cyrius
fn main(): i64 { var n: i64 = mk3(5); return n; }
```

```
error:<source>:4:31: cannot initialise 'n: i64' from 'mk3', which returns the struct 'P3' - declare 'n: P3' or bind a field
```

## Fix

`_rcv_scalar_ann` (src/frontend/parse_decl.cyr) judges the initialiser's callee through `_rcv_iscall`; teach it the
known-callee `fncallN(&f, ..)` / `callptr(&f, ..)` spellings ARG-1 resolves (`_icall_sret`'s callee), so the same
refusal names `mk3`. Rows beside `struct_receive_inference_checked.sh` and `struct_value_codegen.sh` FP*.
