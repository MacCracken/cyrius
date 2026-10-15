# A generic that forwards its `T` to a bounded generic is refused at `f64` when the bound has no `impl … for i64`: `o(h)` says "uses its type parameter as a struct" — OPEN

**Status:** 🟡 **OPEN** — the shape the 6.7.11 bounded-f64 fix left out (its brief: "a forwarder ... stays refused with
the struct-stub text"); measured 2026-10-14 by the 6.7.11 genfe lane (unit G1) before and after that fix: unchanged.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 genfe lane) — never 7.x.
**Discovered:** 2026-10-14, 6.7.11 genfe G1 (the out-of-scope note of
[2026-10-11-bounded-generic-f64-impl-needs-i64-impl.md](2026-10-11-bounded-generic-f64-impl-needs-i64-impl.md))
**Severity:** Medium — valid source is refused, and the message is wrong twice (no `T` is used as a struct; the note
names `i64`, the impl the call does not need). Workaround: a dummy `impl Show for i64`.
**Affects:** cycc 6.7.1 (bounds) through the 6.7.11 genfe tree, every target (the check is frontend)

## Summary

6.7.11 made a by-value bounded call (`x.show()` in `fn gb<T: Show>(x: T)`) a TRAIT use, so `gb(h)` / `gb<f64>(h)`
with only `impl Show for f64` compile and call the f64 impl. A generic that FORWARDS its own `T` to `gb` is still a
transitive stub: `_gs_use` mode 1 (src/frontend/parse_fn.cyr) counts `return gb(x);` as a struct use whenever
`_bnd_base_bad(gb)` holds — i.e. whenever i64 fails gb's bound — so `o`'s base is the dead stub, which has no scalar
instance, and `o(h)` / `o<f64>(h)` are refused with the struct-stub text plus a note naming `i64`. With both impls
the forwarder is right (`o(h) * 10 + o(3)` = 56).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
fn gb<T: Show>(x: T): i64 { return x.show(); }
fn o<T>(x: T): i64 { return gb(x); }
fn main(): i64 { var h: f64 = 1.5; return o(h); }
syscall(60, main());
```

```
error:<source>:6:45: generic 'o' has no i64 (or other scalar) instance: it uses its type parameter as a struct (a '.field' on a T-typed value, directly or in a generic it forwards T to) — pass a struct argument, or name a struct type argument
    fn main(): i64 { var h: f64 = 1.5; return o(h); }
                                                ^
  note: the bound on type parameter 'T' needs `impl Show for i64`, and there is none
expected: compiles; exit 5
```

`return o<f64>(h);` is refused the same way (6:50). Measured on the genfe tree before and after the bounded-f64 fix.

## Root cause

`_gs_use` mode 1 marks a forwarding call a struct use when the callee's base is invalid for ANY reason, the bound's
included (`if ((GFGM(S, cfi) & 3) == 0) { if (_bnd_base_bad(S, cfi) == 0) { return 0; } }`). A bound-invalid base is
invalid for i64 only, not for every scalar: the forwarder's own base should then be "bound-invalid at i64" (skipped,
an i64 call refused naming i64), not the struct stub that refuses every scalar.

## Proposed fix

Propagate the bound judgment, not the stub: a forward into a generic whose base is bound-invalid makes the forwarder's
i64 base invalid the same way (`_bnd_base_bad`'s judgment, transitively), and leaves its f64 / struct instances alone.
Rows: the repro (exit 5) and `o<f64>(h)` on every fork; `o(3)` with only the f64 impl refused naming `impl Show for
i64` (not the struct-stub text); both impls unchanged (56); a two-level forward `o2(h)` → `o(x)` → `gb(x)`.
