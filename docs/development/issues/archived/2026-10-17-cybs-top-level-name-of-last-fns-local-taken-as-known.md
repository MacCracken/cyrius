# cybs: at top level, a name that is a local of the last fn compiled is taken as known (the local table is not reset after a fn) — RESOLVED

> ✅ **RESOLVED in v6.7.15** (IT-3, `7799ebbf3` — no decision needed: a cybs diagnostic: `parse_fn_def`'s tail now zeroes `fn_local_count` after its `in_function` clear (three instructions, no seed label), so the top-level `[` lookup no longer finds the last fn's locals. The filed program (`fn f() { var zz = 1; return zz; }` then `zz[1] = 5;`) gives rc 1 `cybs: undefined variable or function (cybs has no const): zz, at: zz[1] = 5;`, nothing written (it printed the class message). cybs 23,010 → 23,023 B; cybs(src/main.cyr) gen1 byte-identical; the closure and seed-derive OK; gate row S 119,413 / 131,072 B input, 508 / 512 labels. Row: `tests/gates/toolchain/cybs_diagnostics_named.sh` X (the filed program, named zz); mutation (the reset dropped, the 6.7.14 cybs) RED on exactly that row. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — recorded 2026-10-16 by the 6.7.14 infra lane (unit I4, the cybs indexed-store naming bite,
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
