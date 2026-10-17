# A global redeclared with a different type is refused, then a declaration-zone initializer between the two declarations is refused again for reading it — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 frontend lane (l6714-frontend, unit F4, b86fdb8a) and on
the lane's base compiler (c0d6d1ba), x86_64 (the frontend: every target alike).
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16 by the 6.7.14 frontend lane, unit F4, beside
issues/2026-10-08-redeclared-global-bool-reads-own-stamp.md (D9 (a) makes `var G: bool = true; var X: bool = G;
var G = 5;` a type change; the second error below appears for every type change, before and after it).
**Severity:** Low — a diagnostic cascade (one mistake, two errors); the build is refused either way.
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
var G: bool = true;
var X: bool = G;
var G: i32 = 5;
syscall(60, G);
```

```
error:<source>:3:12: global 'G' redeclared with a different type or size (a global has one definition; rename one)
error:<source>:2:15: cannot initialize bool 'X' with a value that is not a bool
```

The same with a struct global (`var G = P { 1, 2 }; var X = G.b; var G = 5;`): the type change, then "no struct type
in scope for 'G'; a '.field' access needs its struct declaration (missing include?)" at `G.b`. Since 6.7.14 (D9 (a))
`var G: bool = true; var X: bool = G; var G = 5;` gives the same pair.

Expected: the type-change error alone.

## Root cause

`_gv_fold` (src/frontend/parse_decl.cyr), on a shape mismatch, reports `_gv_shape_err` and returns the new
registration's own index, so the refused declaration becomes a SECOND global of the same name. The declaration-zone
replay (EMIT_GVAR_INITS) resolves `G` in X's initializer with FINDVAR (last match) — the refused second declaration,
in its other shape — and judges X's value against it.

## Proposed fix

Keep the refused registration out of name resolution (e.g. register it under the earlier global's slot, or mark it so
FINDVAR prefers the first declaration once `_gv_shape_err` has fired), so a reader between the two sees the first
declaration's shape and reports nothing more. Rows beside global_redeclaration_one_definition.sh row I: the three
pairs above give exactly one error.
