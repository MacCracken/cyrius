# A generic instance's `pp: **T` PARAMETER pins its pointee unbound: `*pp + 1` steps 8 (not sizeof(T)) and `take(**pp)` into `*T`'s struct pushes the first field as the address (139), where the same `**T` as a LOCAL of the instance is right — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-15, `3a122cb2b` (the user's decision D40, 2026-10-16: A — T = P3, as `st<P3>(pps)`). This file's root cause is WRONG, as the triage said: an instance's `pp: **T` parameter pins correctly (`st<P3>(pps)` 120, `tg<P3>(pps)` 42 on the base). The implicit call never instantiated, because `_gs_param` reads one `*`, so `pp: **T` carried nothing and T was inferred i64. The fix is in inference. A T that no `x: T` / `p: *T` parameter and no generic struct carries is now carried by the first parameter declared exactly `**T` (`_gen_infer_ind`, `_pp_tparam`). It binds the struct the whole argument's pin names: a `**S` local, parameter, capture or global, a field chain, a `: **S` call, or `&p` / `&G` of a `*S`; free calls and generic methods alike. Repro 1 read 56 on x86_64, IR=3, aarch64, cx and PE and now reads 120. Repro 2 read 139 / 139 / 139, cx 254, PE 5 and now reads 42. The four hosts give 120 / 42 natively. A direct or struct carrier still wins. A `*S`, `**i32`, `***S`, `(pps)` and `pps + 0` bind nothing; `tg((pps))` still faults. Rows: the new `frontend/generic_double_pointer_infer.sh` (R1 / R2 the filed repros verbatim, P, M, E on five legs) and `crossos/double_pointer_deref_step.tcyr` GI / GK (14 rows). Mutations MD1 – MD6 RED. Staged beside it: a `***T` parameter carries nothing (Low, a decision). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V3; the structs lane's D9 (a) — `*pp` of a
`**T` is a `*T` — and the V3 deref-through bite, which types `**pps` of a `**S` as S through the pin, are in). Measured
identically on the V3 base for the step (unchanged by V3).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V5; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D40 — A.
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
