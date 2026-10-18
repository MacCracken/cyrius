# cybs: at top level, a name that is a local of the last fn compiled is taken as known (the local table is not reset after a fn) — OPEN

**Status:** 🟡 **OPEN** — recorded 2026-10-16 by the 6.7.14 infra lane (unit I4, the cybs indexed-store naming bite,
b26ae2418) as a known limit in its handoff and not filed; filed 2026-10-17 by the 6.7.14 release-docs pass (a deferral
is real only when filed).
**Placement:** 6.7.15 — repair 5 (infratools lane, wave 1, unit I2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — a diagnostic of cybs (the bootstrap compiler, which builds only src/ and bootstrap/asm.cyr): the
named "undefined variable" the 6.7.14 bite added is not given for this shape; the class message prints instead, as
before 6.7.14.

## Reproduction

A file cybs compiles, with a fn whose local is `zz`, then a top-level indexed store to an undeclared `zz`:

```cyrius
fn f() { var zz = 1; return zz; }
zz[1] = 5;
```

cybs (the seed's bootstrap compiler, `bootstrap/cybs.cyr`) prints the class message (with its `x[i]` hint) where the
same store with no such fn before it names `zz` (row X of tests/gates/toolchain/cybs_diagnostics_named.sh, "the
top-level `zz[1] = 5;` names zz").

## Root cause

cybs does not reset its local-name table when a fn body ends, so at top level the last fn's locals are still found by
the lookup that decides "known name → class message" vs "unknown → name it".

## Fix

Reset (or scope) cybs's local table at the end of each fn body, mind the seed's label budget (gate row S of
cybs_call_arity_named.sh), and add the shape to cybs_diagnostics_named.sh X: the top-level store after a fn whose local
has the name, named. Seed-derive.
