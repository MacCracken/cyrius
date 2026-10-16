# A struct passed to a `*V` parameter (`rd(s)` with `p: *f64v2`, `s: Pt`) is accepted silently: its address is read as the vector — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (unit X1) and on the slot-open compiler
(`7f57e532`): the repro compiles with no diagnostic and exits 42 on x86_64, x86_64 `CYRIUS_IR=3`, aarch64, cx and PE —
`rd` reads the struct's bytes as an `f64v2`.
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D33 — A.
**Discovered:** 2026-10-15, the fixfirst lane, probing D27's mirror image (D27 refuses a vector into a pointer of
another kind; a struct into a pointer to a vector is the other direction).
**Severity:** Low — no fault (the address is a real object's); a type mismatch the compiler does not name, where a
struct of another type into `*S` (6.7.3) and a vector of another type into `*V` (6.7.11) are refused by name.
**Affects:** every target; a struct local, a struct call result or `*ps` (a `*S`) into any `*V` parameter.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct Pt { x; y; }
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 { var s: Pt; s.x = 42; s.y = 7; return rd(s); }
var rc = main();
syscall(60, rc);
```

```
x86_64 42, IR=3 42, aarch64 42, cx 42, PE 42      (no diagnostic)
```

## Root cause

`src/frontend/parse_fn.cyr` `_try_push_struct_addr_arg`'s struct-local arm checks the argument against the parameter's
recorded struct (`_sarg_type_err`, GFPSID), and a `*V` parameter records none (its class is 9, no struct), so nothing
compares — the local's address is pushed as for a `*S` of the same struct. `_sarg_vec_ptr` (6.7.11, the vector-type
check) runs only for a vector local.

## The question

Refuse by name ("cannot pass 's' to a parameter that is a pointer to a vector type"), as the other direction is refused
since 6.7.12 (D27), or keep accepting it (a struct's bytes viewed as a vector, as `&s` would be)? `&s` itself is a
plain pointer and converts freely either way.
