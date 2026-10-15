# A bounded method call on a struct carrier's `T` field (`b.v.show()`, `b: Box<T>`, `T: Show`) is a struct use: `gs(bi)` with `bi: Box<i64>` is refused although `impl Show for i64` exists — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 by the 6.7.11 genfe lane (unit G2) on its tree, after the
carrier-field fix ([2026-10-10-generic-base-reads-carrier-field-as-struct.md](2026-10-10-generic-base-reads-carrier-field-as-struct.md)).
Before that fix the definition did not compile at all ("expected ';', got '.'").
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 genfe lane) — never 7.x.
**Discovered:** 2026-10-14, 6.7.11 genfe G2, probing the carrier-field rule's edges.
**Severity:** Low — a loud refusal of valid source (no miscompile), with a one-line workaround: bind the field to a
`T`-typed local first (`var t: T = b.v; return t.show();` compiles and exits 65 on the repro).
**Affects:** every cycc with generic struct carriers (6.7.8+); every target (the check is frontend).

## Summary

A bounded type parameter's method call on a `T`-typed NAME (`t.show()` with `t: T`, `T: Show`) is a TRAIT use: the
stub scan does not count it a struct use (`_bs_find`, a pass-1 bounded site), and an i64 call reaches the bound's
`impl Show for i64` through the bounded-scalar receiver path. The same call on a struct carrier's `T` field —
`b.v.show()` with `b: Box<T>` — is no bounded site (`_bnr_decl` records names declared `T`, never a carrier's field),
so 6.7.11's carrier rule (`_gs_cfield`) counts it a struct use: the base is the stub, the struct call `gs(b)` is
right, and the scalar call `gs(bi)` is refused naming `gs` — while the same body through a `T`-typed local works for
both.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for i64 { fn show(self): i64 { return self + 1; } }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
struct Box<T> { v: T; n; }
fn gs<T: Show>(b: Box<T>): i64 { return b.v.show(); }
fn go(): i64 {
    var b: Box<Pt>; b.v.x = 1; b.v.y = 6; b.n = 2;
    var bi: Box<i64>; bi.v = 4; bi.n = 1;
    return gs(b) * 10 + gs(bi);
}
syscall(60, go());
```

```
actual (6.7.11 genfe tree):
error:<source>:11:28: generic 'gs' has no i64 (or other scalar) instance: it uses its type parameter as a struct (a '.field' on a T-typed value, directly or in a generic it forwards T to) — pass a struct argument, or name a struct type argument
before 6.7.11: error:<source>:7:44: expected ';', got '.'   (the definition itself)
expected: compiles, exit 65 (gs$Pt reads Pt's show = 6; gs(bi) reaches `impl Show for i64` = 5)
workaround: `fn gs<T: Show>(b: Box<T>): i64 { var t: T = b.v; return t.show(); }` — exit 65
```

## Root cause

Two halves, both lexical/pass-1: the bounded-site table (`_bnr_decl` / `_bs_add`, src/frontend/parse_fn.cyr) records a
method call only on a name declared `T` / `*T`, so `b.v.show()` is not a bounded site; and `_gs_cfield` (6.7.11)
then counts `b.v.<anything>` a struct use. The method arm (`_field_load_on`) has no path for a bounded call whose
receiver is a carrier FIELD at a scalar `T` (the bounded-scalar `self` push, `_bs_scalar_self`, takes a name).
A fix records `x.f.m(` as a bounded site when `x` is a carrier whose `f` is `T` (the carrier table `_gcr` already
names them), keeps it a trait use in `_gs_cfield`, and gives the method arm the field value as the scalar `self`.
Rows: the repro (65) on every fork; `gs(b)` alone; a carrier whose `T` has no i64 impl refused naming i64.
