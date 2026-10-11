# A declaration-zone global set from a METHOD returning a 9-16 byte struct compiles and crashes at startup — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: the repro compiles clean (rc 0, no diagnostic) and the binary dies of SIGSEGV (rc 139). The same with
the installed 6.7.0, 6.7.3, 6.7.5, 6.7.6 and 6.7.7 compilers (6.7.0 is where an inherent `impl Q {` starts to parse).
The free-call form (`var G3: Q = mkf();`), the same method line after the first top-level statement, and a 24-byte
method result are each refused by name ("'Q_mk' returns a struct by value, and a struct result needs storage in a
fn's frame — call it inside a fn").
**Placement:** 6.7.13 — repair 3, the globals lane (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-10 —
never 7.x (the fix is the user's call, asked at that release's open: a program that compiles today is refused).
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane, bite D6 (a dyn destination; D6 refuses that form for a
dyn, `_gvi_dyn_mcall`, gate row C9b).
**Severity:** High — a clean build of a program that cannot run (SIGSEGV before `main`), with no diagnostic.
**Affects:** cycc 6.7.0 – 6.7.8, x86_64 measured (the replay is shared frontend code)

## Summary

A global declared before the first top-level statement (the declaration zone) is initialised by a replay of its
initialiser. A 9-16 byte struct result comes back in rax:rdx and the replay has no frame to receive it. For a whole
free call that is refused by name (6.6.6 / 6.6.11, `_refuse_toplevel_pair_init`), and after the first statement
PARSE_VAR refuses the method form too. In the zone a METHOD call (`Q0.mk()`) gets neither: the replay stores rax —
the struct's first WORD — into the global's slot as if it were the address of an inline struct, and the first
`G2.a` dereferences it.

## Reproduction

`docs/development/issues/repros/2026-10-10-zone-global-from-method-struct-call-crashes.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q = Q { self.a + 1, self.b + 2 }; return q; } }
var Q0: Q = Q { 4, 5 };
var G2: Q = Q0.mk();                     # compiles; the binary SIGSEGVs (rc 139); want exit 57
syscall(60, G2.a * 10 + G2.b);
```

```
actual:   compile rc 0, no diagnostic; run: Segmentation fault, rc 139
expected: refused by name, as `var G3: Q = mkf();` in the same place and this line after a statement are:
          error: 'Q_mk' returns a struct by value, and a struct result needs storage in a fn's frame — call it inside a fn
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

`_gvi_expr` (`src/frontend/parse_decl.cyr:5257`) calls `_refuse_toplevel_pair_init`
(`src/frontend/parse_fn.cyr:4468`), which returns at its first test for a method call: `_gcall_open(S, ti)` on the
receiver name `Q0` finds no `(`. It then parses the initialiser with the struct-copy arms up and stores rax. 6.7.8
added the method case for a dyn destination only (`_gvi_dyn_mcall`, `src/frontend/parse_types.cyr:1818`).

## Proposed fix

Refuse a whole METHOD call returning a 9-16 byte struct in the zone replay by name, the way `_gvi_dyn_mcall` does for
a dyn — generalise that helper to any struct destination (the method's return class from `_ret_agg_class`). Rows: the
repro (refused, rc 1, the named message); a chain `Q0.mk().mk()`; a generic method; an 8-byte method result (stays
legal: it fits rax); the free-call and post-statement forms unchanged.

## Consumer-side workaround

Initialise the global inside a fn (`fn init() { G2 = Q0.mk(); }`) or declare it after the first top-level statement
(where the same line is refused by name, so the build says what to do).
