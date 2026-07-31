# No general-purpose sort in `lib/` — the compiler's own frontend hand-rolls two, and consumers keep re-deriving it

**Status:** ✅ **RESOLVED in cyrius 6.5.4** — `vec_sort_by(v, cmp)` + `vec_select_nth(v, k, cmp)`
shipped in `lib/vec.cyr` (introsort: median-of-3 Hoare quicksort, insertion cutoff 16, heapsort
depth-limit fallback; O(1) extra memory; O(n) already-ordered fast path). Gated by
`tests/tcyr/vec_sort.tcyr` (59 assertions, mutation-proven 7/8). Named `vec_sort_by` per this
filing's naming constraint — bare `vec_sort` stays itihas's. See CHANGELOG [6.5.4].

**Original status:** 🟡 OPEN — verified against cyrius **6.4.86**: an exhaustive grep of `~/.cyrius/lib`
for `sort|qsort|msort|heapsort|merge_sort|sift|partition|pivot|select|nth` finds **no
general-purpose ordering routine**. The three name hits are unrelated internals (a query-result
sorter in yukti, a bucket sort in mabda, a scheduler heuristic). `lib/vec.cyr` and `lib/slice.cyr`
have no ordering surface at all.
**Placement:** unpinned — **6.x-line stdlib backlog**. `lib/vec.cyr` is the natural home; ~55 lines
for both functions.
**Discovered:** 2026-07-28 while planning the AgnosAI Rust→Cyrius port. `load_testing.rs` computes
p50/p95/p99 over a 100k-entry latency vector, and the only reusable prior art in the ecosystem is
`itihas`'s O(n²) `vec_sort`.
**Severity:** Medium — no hard failure, but consumers either re-derive it or ship a quadratic sort
on data whose size they do not control.
**Affects:** cyrius 6.4.86 and every earlier version.

## Summary

There is no `vec_sort_by` / `vec_select_nth` in the stdlib. Two consequences, and the second is
the one that motivated this filing:

**1. The compiler hand-rolls it, twice, in its own frontend.**

- `src/frontend/parse_fn.cyr:3892` — insertion sort over three parallel raw arrays, by `first_cp`
  ascending with an `lidx` tie-break. Its own comment: *"Insertion sort — iv_n is small (≤ 256)."*
- `src/frontend/parse_fn.cyr:4198` — insertion sort of NOP runs by CP, 16-byte stride into a raw
  region, bounded `nrn ≤ 1024`.

Both are correct and both are bounded, so neither is a bug. They are cited because the maintainer
reached for the missing primitive twice inside cyrius itself — which is a stronger signal about
stdlib surface than any consumer count.

**2. Consumers re-derive it, and two independently wrote O(n log n).**

I am deliberately **not** shipping a precise count. An earlier sweep of this claimed "75 sorts
across 30 repos"; auditing it dropped ~20 of those as vendored `dist/` bundles counted under a
second repo's name, `.tcyr`/`.bcyr` copies of the same author's own `src` function, and things
that are not sorts at all (topological orderings, Lomuto partitions, ordered B-tree insert). The
defensible statement is a **floor of ~26 first-party repos** carrying at least one hand-written
ordering routine, verified by reading the loops rather than trusting names or comments.

The strongest evidence is not the quadratic ones. It is that **`darshini` (`src/render.cyr:129`)
and `stiva` (`src/convert.cyr:610`) each independently implemented a real O(n log n) sort** —
darshini a recursive merge sort with an insertion cutoff at 16, stiva a bottom-up iterative merge.
Two teams paid to build the same primitive because it was not there.

**The name is already taken.** `itihas/src/util.cyr:57` defines `vec_sort(v, cmp)` — **unprefixed,
generic, comparator-driven**: exactly the signature a stdlib addition would want, in cyrius's
single flat namespace. Any `vec_sort` added to `lib/vec.cyr` collides with it under
last-definition-wins. `sankhya/src/util.cyr:88` carries the same function byte-identically as
`sk_vec_sort`, which is the pattern that works today.

## Measurements

Compiled and run against cyrius 6.4.86 on x86-64 Linux. Random i64 input, comparison through a
genuine `fncall2` indirect call in every algorithm, input regenerated from a master copy **outside**
the timed window. Correctness verified against an independent counting-sort reference over 96
randomized trials with heavy duplicates (`mod 50`), quickselect checked for every `k` on a fresh
copy, plus the all-identical-keys case that hangs a naive Lomuto partition.

| n | insertion | heapsort | 3× quickselect (p50/p95/p99) |
|---|---|---|---|
| 1,000 | 3.64 ms | 0.358 ms | 0.087 ms |
| 10,000 | 363.8 ms | 5.00 ms | 0.884 ms |
| 50,000 | 9.281 s | 29.4 ms | 4.64 ms |
| 100,000 | **36.93 s** | **63.4 ms** | **8.51 ms** |

**Three caveats, stated because they weaken the numbers:**

- **This is the average case only.** Insertion sort is O(n) on nearly-sorted input, and
  nearly-sorted is exactly what several of these consumers feed it — directory listings, ascending
  post IDs, an already-priority-ordered route table. **Heapsort would lose those.** That argues for
  a hybrid with an insertion cutoff, which is precisely what darshini already built, rather than
  for plain heapsort.
- **582× is an upper bound, not a typical figure.** Routing both algorithms through an fnptr
  inflates the ratio, because insertion performs O(n²) comparisons to heapsort's O(n log n), and
  roughly a third of the surveyed consumer sorts are type-specific with the comparison inlined.
- The reverse-sorted worst case is not in the table above.

## Proposed fix

Two functions in `lib/vec.cyr`, ~55 lines total:

- **`vec_sort_by(v, cmp)`** — the ordering primitive. Recommend a hybrid: merge or heap for the
  bulk, insertion below a cutoff (~16), which keeps the O(n) nearly-sorted case that consumers
  currently get for free from their hand-rolled insertion sorts. If a single algorithm is
  preferred, heapsort is O(n log n) *worst* case with O(1) extra memory and no recursion depth —
  merge sort needs an n-slot scratch, which is a real cost at 100k.
- **`vec_select_nth(v, k, cmp)`** — Hoare quickselect, median-of-3. Percentiles never needed a
  full sort; this is the larger practical win for the case that prompted the filing.

**Naming matters more than usual here.** `vec_sort` is already occupied by `itihas` in the flat
namespace, so `vec_sort_by` (or any name that is not bare `vec_sort`) avoids breaking it.

**One consumer must be excluded from any migration.** `drishti/src/av1_mv.cyr:358`
`av1_mv_stack_sort` is a bubble sort with the `new_end` bound — that is AV1 spec §7.10.2.14's
*prescribed* sort, and replacing it with a faster one would be a conformance bug. It is a caveat,
not a candidate.

## Consumer-side workaround

AgnosAI vendors both functions locally as `src/order.cyr`, prefixed `ai_*`, specifically **not**
defining a bare `vec_sort`. That is the workaround available to every consumer, and ~26 of them
have independently taken some version of it — which is the argument for the stdlib carrying it
once instead.
