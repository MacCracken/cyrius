# slice_position_refused.sh K2 does not depend on `_sl_ann_at`'s FINDSTRUCT test: deleting it leaves the gate green — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 by the 6.7.11 genfe review on the lane tree (l6711-genfe). A pre-existing
test blind spot from 6.7.8 (C2-6a, row K2); no compiler defect.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the 6.7.11 genfe review, mutating the slice-word fix (3a7febfb).
**Severity:** Low — a gate that reads green over a deleted guard. The guard is live (a program's own generic
`struct slice<T>` in a parameter or pointer position depends on it), but no row exercises it, so a regression there
would ship silently.
**Affects:** tests/gates/frontend/slice_position_refused.sh since 6.7.8.

## Summary

`_sl_ann_at` (src/frontend/parse_types.cyr, beside `_sl_word_builtin`) answers 1 when a token begins a slice type:
`[`, or the word `slice` followed by `<` — unless the program declares its own `struct slice` (the line
`if (FINDSTRUCT(S, noff) > 0) { return 0; }`). Row K2 is the only row about a program's own `struct slice` in those
positions, and it uses the BARE name (`fn f(p: *slice)`, `fn g(s: slice)`): with no `<` after the word,
`_sl_ann_at` has already answered 0 before the FINDSTRUCT test, so K2 passes with or without it.

## Reproduction (the shape a row needs)

```cyrius
struct slice<T> { a: T; n; }
fn f(p: *slice<i64>): i64 { return p.a; }
fn g(s: slice<i64>): i64 { return s.n; }
var B: i64[2];
store64(&B, 5);
store64(&B + 8, 2);
syscall(60, f(&B));
```

```
lane build/cycc (and base 5fb211da):  compiles, exit 5
the mutant (the FINDSTRUCT line deleted from _sl_ann_at):
  error:<source>:2:10: a pointer to a slice is not a type (6.7.8: slices are fn-locals) - pass &s as a plain pointer and read slice_ptr / slice_len
  error:<source>:3:9: a slice cannot be a parameter (6.7.8: slices are fn-locals) - pass &s and read slice_ptr / slice_len, or the pointer and the length
the gate under that mutant: green (the review's log: /home/macro/.cache/c6/s6711/genfe/review/rev/mut/mG4b.log)
```

## Fix direction

Add a K2h row to slice_position_refused.sh: the repro above exits 5 (a generic `struct slice<T>` as a `*slice<i64>`
parameter and a by-value `slice<i64>` parameter), and record in the header's ledger that deleting the FINDSTRUCT line
from `_sl_ann_at` turns it RED. No compiler change.
