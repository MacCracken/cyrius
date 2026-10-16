# A generic instance's `pp: **T` PARAMETER pins its pointee unbound: `*pp + 1` steps 8 (not sizeof(T)) and `take(**pp)` into `*T`'s struct pushes the first field as the address (139), where the same `**T` as a LOCAL of the instance is right — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V3; the structs lane's D9 (a) — `*pp` of a
`**T` is a `*T` — and the V3 deref-through bite, which types `**pps` of a `**S` as S through the pin, are in). Measured
identically on the V3 base for the step (unchanged by V3).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane; filed from the 6.7.13 vectors lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — the dereference compiles clean and faults on every target; the step is silently wrong.
**Kind:** bug — D9 (a) (the user, 2026-10-15) decides `*pp` of a `**T` is a `*T`; a generic instance's parameter misses
the binding.
**Discovered:** 2026-10-16, the 6.7.13 vectors lane (V3), probing the `**pps` struct typing beyond the filed local
(issues/archived/2026-10-15-vector-deref-through-address-of-or-double-pointer-into-vector-pointer-param.md).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn st<T>(pp: **T): i64 { var a = *pp + 1; var b = *pp; return a - b; }               # a parameter
fn stl<T>(p: *T): i64 { var pp: **T = &p; var a = *pp + 1; var b = *pp; return a - b; }   # a local
fn main(): i64 { var s: P3; var ps: *P3 = &s; var pps: **P3 = &ps; return st(pps) * 100 + stl(ps); }
syscall(60, main() % 256);
```

```
x86_64 56, IR=3 56, aarch64 56, cx 56, PE 56      (st = 8, stl = 24: (8 * 100 + 24) % 256; 120 is right)
```

```cyrius
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn tg<T>(pp: **T): i64 { return take(**pp); }
fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; return tg(pps); }
syscall(60, main());
```

```
x86_64 139, IR=3 139, aarch64 139, cx 252, PE 5      (42 is right; a non-generic `fn tpp(pps: **P3)` gives 42 since V3,
and so does `var pp: **T = &p; take(**pp)` inside the instance)
```

## Root cause

The parameter's step word gets its pin where the parameter list is scanned (`_ek_pin(S, GTI(S) - 1)`,
src/frontend/parse_fn.cyr, the `SSLICE_W` of a `**T` parameter), which for a generic instance is read without the
instance's binding: `_pp_word_at` sizes `*T` by `_ptr_step_peek` with T unbound (8) and `_pp_psid` finds no struct for
T. A local declared in the instance's body is read under the binding (`_tp_c0`), so it is right. Every consumer of the
pin — `*pp` arithmetic, `var q: *T = *pp`, the struct and vector parks — inherits the wrong pointee.

## Fix direction

Pin a generic instance's `**T` parameter under the instance's binding (as its body's locals are), or re-pin the
parameters once the binding is in force. Rows beside tests/tcyr/crossos/double_pointer_deref_step.tcyr.
