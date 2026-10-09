# `#pure`'s `#io` / `#alloc` check is silent for a callee defined later — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the tree's `build/cycc`: the repro below prints no warning. The same source with the callees moved above the `#pure` fns prints all four (a plain call, a second plain call, a tail call and a method call).
**Placement:** Break 2 candidate — the user picks (roadmap.md § Break 2) — never 7.x.
**Discovered:** before 2026-10-08 (carried in roadmap.md's backlog); filed 2026-10-08 from roadmap.md.
**Severity:** Low — a missing warning; nothing miscompiles.
**Affects:** cycc ≤ 6.7.6 (the check exists since v5.8.20; the method arm since 6.6.17).

## Summary

A `#pure` fn that calls an `#io` or `#alloc` fn should warn `#pure fn calls #io fn '…'` at the call. The
check reads the callee's `fn_flags` at the call site, but `#io` / `#alloc` are written into those flags
only when the callee's definition is parsed in pass 2. A callee defined below the `#pure` caller therefore
has no flags yet, and the call is silent. This affects every call path: a plain call, a tail call
(`return wr();`) and a method call (`p.m()` with the `impl` later).

`#deprecated` (6.6.16, `_prescan_dep_take`) and `const fn` (6.7.2, `SFCFN` in `_prescan_fn_sig`) already
solved this ordering problem by recording the attribute in pass 1.

## Reproduction

`docs/development/issues/repros/2026-10-08-pure-check-misses-later-defined-callee.cyr`:

```sh
cat docs/development/issues/repros/2026-10-08-pure-check-misses-later-defined-callee.cyr | build/cycc > /tmp/p
# actual:   no warning
# expected: the four warnings the callees-first order prints:
#   warning:<source>:…: #pure fn calls #io fn 'wr'
#   warning:<source>:…: #pure fn calls #alloc fn 'grab'
#   warning:<source>:…: #pure fn calls #io fn 'wr'      (the tail call)
#   warning:<source>:…: #pure fn calls #io fn 'A_m'     (the method)
```

## Root cause

- `src/frontend/parse_fn.cyr:11712-11729` (in `PARSE_FN_DEF`): `_io_pending` / `_alloc_pending` become
  `fn_flags` bits 4 / 5 (16 / 32) only when the definition is parsed in pass 2. They are armed by
  `_tl_arm` (`src/frontend/parse_fn.cyr:10270`).
- `src/frontend/parse_fn.cyr:4064` `_pure_effect_warn` (plain and method calls) and the tail-call copy at
  `src/frontend/parse_fn.cyr:966-981` read `GFLG(callee)` at the call, which is still 0 for a callee
  defined later.
- Pass 1 already records the analogous facts: `src/frontend/parse_fn.cyr:9969` `_prescan_dep_take`
  (`#deprecated`, defined at 10108) and `:9971` `SFCFN` (`const fn`), both in `_prescan_fn_sig` (9933).

## Proposed fix

Record `#io` / `#alloc` in pass 1 the way `#deprecated` is recorded: arm a pass-1-only pending pair
where pass 1 walks the attribute (never the pass-2 `_io_pending`, which is the `_pub_pending`
cross-pass defect `_prescan_dep_take`'s comment warns about). Then OR bits 16 / 32 onto the fn
`_prescan_fn_sig` registers, including impl methods. PARSE_FN_DEF ORs the same bits again. Optionally,
fold the tail-call copy at 966–981 into a call to `_pure_effect_warn`. Add a gate with the repro, which
must print all four warnings.
