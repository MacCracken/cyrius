# A method no bound declares, called on a struct carrier's `T` field (`b.v.other()`, `b: Box<T>`, `T: Show`), is not checked against the bound — RESOLVED

> ✅ **RESOLVED in v6.7.15** (GN-18, `da30dffed` (the user's decision D5 (a), 2026-10-18: refuse it at the definition), and GN-19, `b71f8853a` (met in passing): `_bnd_fsite` refuses, through `_bnd_site`'s two refusals (`_bnd_site_refuse`), a method no trait of the bound declares — or two declare — called on a carrier's bounded `T` field. The filed repro, which exited 77, is refused once at 7:45, "method 'other' is not in the bound on type parameter 'T'", its note naming `'b.v'`, called or not (the definition alone exited 3); the ambiguous method is refused once at the definition; `b.v.show()`, an unbounded `Box<T>`, a field whose type parameter has no bound and a `p: *T` field are unchanged. GN-19: a later contract refusal the panic latch swallows prints no orphan note. Rows: `trait_bounds_checked.sh` BD0 (the filed repro verbatim) - BD7, BDK, BC7 (now the refusal) and N2; mutations MBD1 - MBD3 each RED. Filed beside it (6.7.16): later contract refusals swallowed in pass 1, and `v.other<i64>(1)` escaping the contract. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 generics lane (unit G4), on the slot-open compiler and after the
bounded-carrier-field bite (issues/archived/2026-10-14-bounded-method-call-on-carrier-field-is-a-struct-use.md): identical.
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D5 — (a) Refuse it at the definition.
**Discovered:** 2026-10-16, 6.7.14 generics G4. That bite records `x.f.m(` on a carrier's T field as a bounded site
only when `m` is a method of exactly one trait of the bound (a trait use; a scalar T takes the field's value). It
records NOTHING otherwise, so a method the bound does not declare keeps its 6.7.11 reading — whether the contract
should refuse it, as it refuses the same call on a `T`-typed name, changes what compiles: a question for the user.
**Severity:** Low — the bound's contract (6.7.1: "on a bounded T, `v.m()` must be a method of a bound's trait,
checked at the generic's definition") has a hole; nothing is miscompiled (the call resolves per instance, as on an
unbounded T, and a scalar T's base is the stub).
**Affects:** 6.7.11 (carrier fields read as a struct) through the 6.7.14 lane tree; every target (frontend).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
impl Pt { fn other(self): i64 { return 77; } }
struct Box<T> { v: T; n; }
fn gs<T: Show>(b: Box<T>): i64 { return b.v.other(); }
fn go(): i64 { var b: Box<Pt>; b.v.x = 1; b.v.y = 6; b.n = 2; return gs(b); }
syscall(60, go());
```

```
actual:   exit 77 — `b.v.other()` resolves to Pt's own `other`; no refusal
compare:  fn gn<T: Show>(v: T): i64 { return v.other(); } -> error: method 'other' is not in the bound on type
          parameter 'T' (at the definition, called or not)
```

## The question

Should a call on a carrier's `T` field be held to the bound's contract as a call on a `T`-typed name is (refuse
`b.v.other()` under `T: Show`, and an ambiguous method two bounds declare), or keep resolving per instance? (a)
refuse: such a generic stops compiling at its definition; (b) keep: document that the contract covers names only.
Implementation for (a): `_bnd_fsite` (src/frontend/parse_fn.cyr) reports through `_bnd_site`'s two refusals instead
of recording nothing.
