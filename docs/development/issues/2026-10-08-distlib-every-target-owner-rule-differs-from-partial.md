# `cyrius distlib`: the every-target owner rule and the partial-target rule still disagree on ties and on in-unit declarers — OPEN

**Status:** 🟡 **OPEN** — reported 2026-10-08 by the 6.7.7 distlib lane after its fix (commit 7b977e32): byte order now decides a tie among non-fold leaves on the every-target path, where the partial path prefers the dispatcher whose peer declares the name or refuses by name. A rough scan of 6.7.6's `lib/` found no such tie, so it does not bite today.
**Placement:** unpinned — 6.x-line backlog (which rule is right is the user's call) — never 7.x.
**Discovered:** 2026-10-08 by the 6.7.7 distlib lane (out of its scope); filed 2026-10-08.
**Severity:** Low — latent: no tie exists in `lib/` today.
**Affects:** cbt ≤ 6.7.7

## Summary

Two differences remain between `_distlib_leaf_defining` (the every-target path, fixed for directory order in 6.7.7)
and `_distlib_partial_owner`:

1. **Ties among non-fold leaves.** Every-target takes the first non-fold declarer in byte order; the partial rule
   prefers the dispatcher whose peer declares the name and otherwise refuses by name. Should the every-target path
   refuse a tie by name too?
2. **The 6.6.18 D3 rule** (skip a declarer already in the unit that still left the name undefined) is applied only on
   the partial path. If byte order puts such a declarer first on the every-target path, nothing is added and the name
   falls through to the D2 "still undefined" warning.

## Proposed fix

Share one owner-selection helper between the two paths (fold exclusion, D3 skip, tie handling), with a gate row for a
two-non-fold-leaf tie.
