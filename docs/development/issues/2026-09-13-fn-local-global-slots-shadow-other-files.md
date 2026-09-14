# A fn-local struct literal (and an oversized / opted-out array local) is a GLOBAL slot that shadows other files' globals — OPEN

**Status:** 🟡 **OPEN** — pre-existing; surfaced by the v6.6.4 visibility-stamp work (bite ③) and
deliberately NOT packed into it: the fix is a storage-class change (struct-literal locals onto
the per-thread stack-slot mechanism), not a missing check. What v6.6.4 changed: the slot is now
STAMPED with its file's visibility, so the cross-file shadowing that used to be a **silent
miscompile** (the consumer read the private file's fn-local slot) is now a **diagnostic** — one
that names the consumer's own variable, which is the misattribution this filing records.
**Placement:** unpinned — 6.x-line backlog (storage classes / stack structs).
**Discovered:** 2026-09-13, by the adversarial reviewer of the marker-scoping repair, probing
whether the new `PARSE_STRUCT_INIT` stamp could fire inside a fn.
**Severity:** Medium — silent wrong values before 6.6.4 for any two files that use the same
name for a fn-local struct literal and a global; a wrong-named diagnostic after. Not Critical:
the collision needs the same identifier in two files.
**Affects:** every cycc release (struct literals have always registered a global slot;
`PARSE_STRUCT_INIT` is reached from `PARSE_VAR` before the `GINFN` split).

## Summary

```cyrius
# lib/a.cyr (private)                      # main.cyr
private                                    struct P { x; y; }
fn f() { var cfg = P { 1, 2 }; return cfg.x; }
public fn api() { return f(); }            include "lib/a.cyr"
                                           var cfg = 5;
                                           fn main() { return api() + cfg; }   # want 6
```

- **6.6.3 / bite-2 compiler:** builds, runs, returns **2** — `cfg` in `main.cyr` resolves (FINDVAR
  is last-match) to `a.cyr`'s fn-local `cfg` slot, which is a global in the flat namespace.
- **6.6.4:** refused with `'cfg' is private to its file` — pointing at the consumer's OWN `var
  cfg = 5`, because the private file's slot now carries `a.cyr`'s stamp and the lookup lands on
  it. Strictly better than a silent wrong value; still the wrong story.

The same shape for arrays: an in-fn `var big[200000]` (past the per-fn stack budget, so it
falls back to the shared global region) or any array local under `CYRIUS_STACK_ARRAYS=0`.
Default-on stack arrays (v6.3.15) are true locals and are NOT affected.

## Root cause

`src/frontend/parse_decl.cyr`: `PARSE_VAR` dispatches `var x = T { … }` to
`PARSE_STRUCT_INIT`, which always registers at `GVCNT` — a global slot — even with
`GINFN(S) == 1`; `PARSE_ARRAY`'s global-fallback path likewise. `FINDVAR` (parse_types.cyr) is a
single flat last-match table, so a later file's same-named global is shadowed by an earlier
file's fn-local slot. The `_GVAR_VIS` stamp added in v6.6.4 keys on the declaring file and
therefore correctly marks the slot private to `a.cyr`; the misattribution is that FINDVAR
returns that slot for `main.cyr`'s reference instead of `main.cyr`'s own global declared later.

## Why it was not packed into 6.6.4

Making struct-literal locals real locals means routing them through the per-thread stack-slot
mechanism `var arr[N]` locals got at v6.3.13/15 (frame slots + `EFLADDR` addressing +
initialiser stores into the frame), with the `_resolve_field_base_addr` inline rule already
in place for the read side. That is a codegen/storage change across every backend with its own
gate cycle, and a same-arity behaviour change for code that (accidentally) relied on the slot
persisting across calls. The alternative — gating the v6.6.4 stamp on `GINFN != 1` — would
restore the silent miscompile, which is worse. Reason named per the "cannot pack" rule.

## Proposed fix

1. `PARSE_STRUCT_INIT` inside a fn: allocate `ceil(STRUCTSZ/8)` frame slots (the v6.3.15 array
   mechanism, `-1` predecessor markers so `_resolve_field_base_addr` treats it as inline), emit
   the field initialisers as frame stores, register the NAME as a local. Same for the array
   fallback paths where the budget allows.
2. Until then, at minimum: `FINDVAR` should prefer a same-file / same-fn match over a
   last-match from another file's fn-local slot — or the diagnostic should say "shadowed by a
   fn-local slot in `lib/a.cyr:2`" rather than "'cfg' is private to its file".

Gate: the two-file shape above must return 6; the array-fallback shape (`var big[200000]` in a
private fn + `var big = 3` in the consumer) must return 3; a same-file struct-literal local
must keep working (in-tree: `tests/tcyr/lang/advanced.tcyr` and every `T { … }` local).

## Consumer-side workaround

Do not reuse a global's name for a struct-literal local in another file, or declare the
global BEFORE the include (last-match then finds the global — but note it is the *local* slot
that then loses, silently, inside the private file). Prefer heap structs (`var p: T =
alloc(N)`) for locals until this lands.
