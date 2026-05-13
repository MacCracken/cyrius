# Cap-drift detector — comments-vs-cap-literals consistency gate

**Filed:** 2026-05-13 (during v5.11.49 vidya cleanup sweep)
**Severity:** Medium — recurring class; multiple confirmed instances across v3.4.x → v5.11.x; current safety net is "consumers notice at the OLD threshold."
**Affects:** All capped buffers in `src/main.cyr` heap-map + per-region commentary. The class is the *drift between cap commentary and actual cap literals*, not any single specific cap.

## Summary

Caps drift out of sync with their documentation. The buffer gets expanded; the cap check, comment, or doc reference *doesn't*. The bug sits latent until a downstream workload crosses the OLD threshold — at which point the consumer hits a cryptic error that the comments suggest shouldn't happen yet.

Per `field_notes/compiler/gotchas.cyml::stale_fixed_cap_drift` (tag `recurring` since v3.4.20):

> Cap checks drift out of sync with the actual buffer size. The buffer gets expanded; the cap check / comment / docs DON'T. Bug sits latent until a downstream workload crosses the OLD threshold.

Confirmed historical instances:

- v3.4.20 — first observation
- v5.7.7 — fixup table cap 256K → 1M; comments still referenced "256K" for 3 slots
- v5.7.36 — distlib per-module cap 64KB → 256KB; sandhi 1.3.3 fold hit the stale comment first
- v5.11.18 — identifier buffer 128KB → 256KB; warn-threshold comment in `programs/check.cyr` had to be hand-bumped
- v5.11.19 — fn_table 4096 → 8192; capacity-gate stress fixture had to be hand-bumped from 3500 → 7000 fns

Each surface required a manual sweep through the source + comments + docs to catch all reference sites.

## Proposed fix

A `_cap_drift_gate()` in `programs/check.cyr` that:

1. Scans `src/main.cyr` for `var <NAME>_CAP = <LITERAL>;` patterns + the heap-map comment block for each region.
2. Scans `src/frontend/lex.cyr`, `src/frontend/parse.cyr`, and other consumers for *literal* cap references (e.g. `if (foo >= 262144)`, `if (np >= 131072)`).
3. Asserts every literal cap-reference in code matches the canonical cap declaration.
4. Asserts every cap-mention in `# comments` near the declarations matches the literal cap.

Failure mode: gate prints `mismatch: <name> declared as N at <file:line>, but found literal M at <file:line2>` — pinpoints the drift site.

## Sketch

```cyrius
fn _cap_drift_gate(): i64 {
    var label = "cap-drift detector — comments and code literals match canonical declarations";
    var caps = vec_new();
    # Parse src/main.cyr for canonical cap declarations
    # Match pattern: var ([A-Z_]+_CAP|[A-Z_]+_LIMIT|[A-Z_]+_SIZE) = (\d+);
    # ... walk src/, look for literal mentions ...
    # ... walk comments for "256K" / "128 KB" / "1 MB" style refs near caps ...
    # ... compare; fail on mismatch ...
}
```

## Alternative considered: codegen at compile time

cyrius doesn't have a build-time macro / generate step. The cap values are currently `var X_CAP = 131072;` literals — no centralized const-table that other sites reference symbolically. Adding such a table would let consumers reference `IDENT_BUF_CAP` symbolically instead of the literal `131072`, and drift would be impossible by construction.

Two paths:

- **Sweep gate** (this issue): catch drift after the fact via static analysis in `programs/check.cyr`. Lower-effort; works with the existing literal style.
- **Centralize caps in a header-like module**: refactor to `lib/_caps.cyr` (or similar) with all cap constants exported, and rewrite all callers to use the symbolic name. Higher-effort; structurally eliminates drift.

The sweep gate is the right level for this slot. Centralization is the v6.x consideration if drift keeps recurring even with the gate.

## Pin

- Absorber buffer (v5.11.49 → v5.11.67) — natural fit; modest scope (~80 LoC + a few test cases).
- Could share a slot with another sovereignty / polish item depending on slot allocation.

## Acceptance bar

1. `_cap_drift_gate()` registered in `programs/check.cyr`; check.sh count bumps by 1.
2. Gate passes against current `src/`.
3. Negative test: introduce a deliberate drift (change `var X_CAP = 262144;` to `262144` in code but leave `# X cap: 128KB` in comments), gate FAILs with line-precise diagnostic.
4. CHANGELOG entry; gotcha entry `stale_fixed_cap_drift` updated to reference the gate.

## Related

- `field_notes/compiler/gotchas.cyml::stale_fixed_cap_drift`
- `programs/check.cyr::_capacity_gate` (per-cap consumer-stress gates; different surface — verifies caps are sufficient, not that comments match)
- CHANGELOG history: v5.7.7 fixup-cap raise, v5.7.36 distlib cap raise, v5.11.18 identifier-buffer raise, v5.11.19 fn_table raise (each surfaced a drift sweep)
