# A vector METHOD result in the destinations D29 did not name: an untyped `var v = s.mv();` binds one word (wrong lanes, silent), `var x: i64 = s.mv()` / `x = s.mv()` store a word, `return s.mv();` from a `: f64v2` fn is refused — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-14, `3478087aa` (the user's decisions D37, D38 and D39, 2026-10-16: A, A, A). (1) `_vrcv_ity` asks `_vmc_whole`, so `var v = s.mv();` is the vector local. Repro 1 read x86_64 / IR=3 / aarch64 1, cx 155, PE 195 and now reads 161 on all five. (2) `_vrcv_mscal` / `_vasg_mscal` refuse a method's vector into a non-vector local. Repro 2 (`var x: i64 = s.mv();`; 0 / 41 / 41) and `x = s.mv();` now print `4:48: vector return type does not match the declared type` / `4:52: .. the assigned variable`, the by-name call's positions, on every leg and host. This reaches a struct, `f64` or pointer destination and a for step too — wider than D38's text, and listed; at `: f64` the by-name `var x: f64 = mkv(..)` still compiles. (3) `_ret_vmc` lets `return s.mv();` through; Win64 goes through a temporary as the method's hidden result pointer (`_ret_vmc_pe`). Repro 3 was refused "got `s`" on every leg and now gives 161; a method of another vector keeps the return rule's refusal. Rows: `simd_return_shapes.sh` M1 / M2 (repros 1 and 3 verbatim) – M5 on five legs, and MK1 (repro 2 verbatim) – MK7 on four; `crossos/simd_indirect_receive.tcyr` M12 – M20 (60 / 60). Mutations M-M1 – M-M5 RED. Staged beside it: wrapped and top-level vector calls into untyped / scalar destinations, a vector call into a scalar global, a chained receiver (each Medium). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V2, after the D29 bite that makes a
method declared `: f64v2` a source the vector local takes: `var v: f64v2 = s.mv();`, `v = s.mv();`).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D37 — A; D38 — A; D39 — A.
**Severity:** Medium — (1) compiles clean and reads wrong lanes on every target, no diagnostic; (2) compiles and
binds lane 0 / a word where the by-name call `var x: i64 = mkv(..)` is refused; (3) is refused loudly.
**Affects:** every target (frontend), every value-form vector type.
**Discovered:** 2026-10-16, the vectors lane (V2), probing the D29 method receive's neighbours. D29 (the user,
2026-10-15) answered "a method declared `: V` … taken as the vector [it is] declared to return" for the RECEIVE (a
vector local's declaration and assignment, the issue's filed repro); these three destinations were not in the filing.

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn run(): i64 { var s: S = S { 1 }; var v = s.mv(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
```
```
x86_64 1, IR=3 1, aarch64 (qemu) 1, cx 155, PE (wine) 195 — 161 is right; no diagnostic.
(`var v = mkv(41, 7);` infers the f64v2 local since v6.5.61; since D29, `var v = callptr(&mkv, 41, 7);` too.)
```

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn run(): i64 { var s: S = S { 1 }; var x: i64 = s.mv(); return x; }
syscall(60, run() % 256);
```
```
x86_64 0, IR=3 0, aarch64 0, cx 41, PE 41 (compiles); `x = s.mv();` into `var x = 0` the same.
The by-name `var x: i64 = mkv(41, 7);` is refused: "vector return type does not match the declared type".
```

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn fwd(s: *S): f64v2 { return s.mv(); }
fn run(): i64 { var s: S = S { 1 }; var v: f64v2 = fwd(&s); return lanes(v); }
syscall(60, run() % 256);
```
```
all five legs: error:<source>:5:31: a vector-returning fn carries its result in a fixed register pair, so `return`
takes a local of that vector type or a call to a fn declared to return the same one — got `s`
```

## Root cause

The untyped declaration infers a vector only from a by-name call (`_vcall_fi` in PARSE_VAR's `vin` block) and, since
D29, a whole `fncallN(&f, ..)` / `callptr(&f, ..)` (`_vrcv_ity`); a method call (`_vmc_fi`, parse_decl.cyr) is not asked,
so the local is one word holding whatever the scalar path stored. The declared-type check in the `vin` block (the
by-name call's "vector return type does not match the declared type" for a scalar annotation) and
`_try_vector_call_assign`'s scalar-destination refusal test `_vcall_fi` only. The vector return rule
(`_simd_ret_call_ok`) accepts a by-name call and (D29) an `&f` indirect call, not a method; PARSE_RETURN's Win64 arm would
need the method arm's hidden-pointer hook (`_sc_vbeg`).

## Proposed fix

A question for the user (what compiles changes): is a method declared `: V` the vector everywhere a by-name call
declared `: V` is — the untyped declaration infers `V`, a scalar destination is refused by name, and `return s.mv();`
from a `: V` fn is accepted (on Win64 through a temporary copied into the result pointer)? Recommended yes: D29's
reasoning ("a method declared `: f64v2` is one [call declared to return it]") reaches these three. Rows beside
simd_return_shapes.sh's C / Q rows on x86_64 / IR=3 / aarch64 / cx / PE, and in
tests/tcyr/crossos/simd_indirect_receive.tcyr.
