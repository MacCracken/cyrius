# A parenthesised or computed `**S` argument binds nothing in a generic `pp: **T` call — `st((pps))` runs the i64 base, `tg((pps))` faults — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 release-docs pass on main (after the vectors lane's VC-15,
which implemented 6.7.14's D40 A: a `**S` argument binds T in `fn st<T>(pp: **T)`), x86_64.
**Placement:** 6.7.15 — repair 5 (vectors lane; filed from the 6.7.14 release-docs pass, placed at the 6.7.14 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — `tg((pps))` faults (139) where `tg(pps)` gives 42 (measured on main, x86_64); parentheses around a whole argument are
transparent everywhere else (6.7.13's D19 family, this release's VC-3 for value-form vector arguments).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn tg<T>(pp: **T): i64 { return take(**pp); }
fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; return tg((pps)); }
syscall(60, main());
```

```
tg(pps)          42
tg((pps))        139   (the i64 base: T unbound)
tg(pps + 0)      139
tg<P3>((pps))    42
```

The guide documents the narrower reach and gate rows GK pin it as "bind nothing".

## Fix

The D40 inference reads the argument's `**S` through whole-argument parentheses (the transparency helper the receives
use) and from a computed `pps + n` of a `**S`; flip the GK rows to the bound result.
