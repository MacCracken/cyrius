# `lib/bench.cyr` 6.6.5+: a window below the resolution bar resolves only when something slow happens in it, so `min`/`max` are the extremes of the SLOW windows and the printed `min` sits ABOVE the `avg` — OPEN

**Status:** 🟡 **OPEN** — filed by hisab at its 6.6.4 → 6.6.6 bump (3.2.1). Not a regression in any
answer hisab records (hisab's CSV keeps `avg`, which is unaffected: median +0.00% between the 6.6.4
and 6.6.6 instruments on the same compiler), but the `min=`/`max=` fields the same rows print are
now taken over a biased subset and the row says nothing about it.
**Placement:** unpinned — 6.6.x line, the next `lib/bench.cyr` bite. Companion to the 6.6.5
resolution-rule repair (`archived/2026-09-16-mabda-lib-bench-min-minus-mean-floor.md`), which this
is the residue of.
**Discovered:** 2026-09-21, hisab's benchmark suite under 6.6.6: `vec3_add: 16ns avg (min=39ns
max=43ns)` — a minimum 2.4× the mean of the same sample.
**Severity:** Medium — a printed statistic that cannot be what it says it is (a minimum above a
mean), with `bench_min_resolved()` answering 1; no crash, `avg` correct.
**Affects:** `lib/bench.cyr` at cyrius **6.6.5 and 6.6.6** (the resolution rule); 6.6.4 and below
are unaffected by THIS shape (they have the min-minus-mean-floor defect the rule replaced).

## Summary

`_bench_record` (6.6.5) admits a window into `min`/`max` only if
`net >= _BENCH_RESOLVE * (clock read + tick)`; a shorter window still counts toward the total and
the mean. That is right for an isolated short window. But with `bench_run_batch` at a **fixed**
batch whose windows net LESS than the bar — e.g. a 16 ns op × 2000 = 32 µs against a 68 µs bar on
an hpet box — a plain window can **never** resolve. The only windows that cross the bar are those
that contained something slow (an interrupt, a page fault, a rehash, a rare branch), so the
"minimum" is the minimum **of the perturbed windows**, `bench_min_resolved()` says 1 because the
count is non-zero, and the row prints a `min=` above its own `avg`.

`bench_run` has the same exposure one notch weaker: `_bench_chunk_for` sizes each chunk from the
**previous** chunk's per-op cost so that it lands exactly **on** the bar (`want = err·RESOLVE·1000 /
per_ps + 1` — one op of slack against a ~68 µs window). A chunk that ran faster than its predecessor
falls just under and is excluded; one that ran slower is kept. The selection is on the quantity
being measured.

Measured on hisab's suite (80 rows, `bench_run_batch(…, 2000, 200)`, 4 interleaved runs, 6.6.6
compiler for both binaries, box quiet at load 0.5–1.7, hpet, floor 341 ns / tick 340 ns):

| instrument compiled in | rows with `min > avg·1.02` | examples |
|---|---|---|
| `lib/bench.cyr` @ 6.6.4 tag | **0 / 320** | — |
| `lib/bench.cyr` @ 6.6.6 tag | **24 / 320** (7 of the 80 benchmarks, all sub-40 ns ops) | `vec3_add` 16 → min 39 (4/4 runs), `vec3_cross` 27 → 49, `vec2_lerp` 22 → 35, `tonemap_reinhard` 28 → 38, `num_gcd` 24 → 35 |

Every affected row is one whose 2000-op window sits at 30–60 µs, i.e. **below** the 68 µs bar.
Rows whose window clears the bar (`quat_mul` 36 ns × 2000 = 72 µs, `ray_aabb` 43 ns) are consistent
(`min/avg` 0.92–1.00), and `avg` itself is unchanged across the two instruments (median +0.00%,
mean +0.31% over 80 rows; the one row past 10% is `cx_mul`, whose same-binary spread is 14.5%).

## Reproduction

`repros/2026-09-21-hisab-bench-min-above-mean-below-resolution-bar.cyr` — **self-proving**: exit 0
when every resolved `min <= avg`, exit 1 otherwise. It compiles on 6.6.4 too (it uses only the
`_ns` accessors and `bench_clock_overhead_ns()`), so the pair is one file run twice:

```
cyrius build repros/2026-09-21-hisab-bench-min-above-mean-below-resolution-bar.cyr /tmp/rb && /tmp/rb
```

| pin (dir pinned to it, `build -v` compiler line checked) | below-bar rows `min > avg` | control rows | exit |
|---|---|---|---|
| 6.6.4 | 0 / 3 (`avg 20 ns, min 6 ns`) | 0 / 3 (`19 / 18`) | **0** |
| 6.6.5 | **3 / 3** (`avg 20 ns, min 47 ns`) | 0 / 3 (`20 / 19`) | **1** |
| 6.6.6 | **3 / 3** (`avg 20 ns, min 47 ns`) | 0 / 3 (`20 / 19`) | **1** |

The repro makes the slow window **deterministic** instead of waiting for the OS to supply one: the
op is a ~5 ns f64 update through a global, every `period`-th call does a spike sized to ~2× the bar,
and the batch is sized so a plain window nets ~¼ of the bar — exactly one window in three carries a
spike. Under 6.6.5+ only those resolve: `min` = plain + spike/batch ≈ 9× the plain cost, while the
mean is ≈ 3.7× it. **The control** sizes the batch to ~4× the bar so every window resolves, and
`min <= avg` holds there on every pin — which isolates the defect to windows below the bar, not to
the resolution rule as such. The bar is estimated in-file as `100 × 2 × floor` (tick is not
readable on 6.6.4; the estimate is exact on hpet boxes and generous on TSC ones, and the ¼ / 4×
margins absorb either way).

## Root cause

`lib/bench.cyr` 6.6.6, `_bench_record` (~line 438): the admission test
`if (net >= _BENCH_RESOLVE * _bench_err_ns())` is evaluated per window on the window's own `net`.
For a population of windows whose typical `net` is below the bar, the test is a selector for
"slower than typical", so the admitted subset is biased upward and `min` over it is not a minimum
of anything a reader would call the operation. `bench_min_resolved` (~line 538) reports
`load64(b + 56) > 0`, i.e. "at least one window resolved", which is true for the biased subset.

`bench_run` (~line 595): `_bench_chunk_for(ps, err)` targets `net == bar` exactly, so the next
chunk resolves only if it runs at or slower than the previous chunk's per-op figure.

## Proposed fix

Two halves, either of which removes the reported inconsistency; both together remove the bias.

1. **Do not let a row resolve on a minority of its windows.** Resolve `min`/`max` for a row only
   if the *typical* window clears the bar — e.g. require the admitted count to be at least half
   the recorded windows (`load64(b+56) * 2 >= load64(b+48)`) before `bench_min_resolved` answers 1
   and before `bench_min_ps`/`bench_max_ps` return the extremes; otherwise fall back to the mean as
   the unresolved path already does. A row whose windows resolve only when perturbed then prints
   `min = max = avg` with `resolved = 0`, which is what is actually known.
2. **Size chunks with margin.** `_bench_chunk_for` should target a multiple of the bar (4× is what
   the repro's control uses and it resolves every window on this box), not the bar itself; the
   cost is a longer pilot for a fast op, and the pilot already grows geometrically.

A cheaper diagnostic in the meantime: `bench_report` could print the admitted fraction
(`resolved N of M windows`) beside `min=`/`max=`, so a reader can see when the extremes came from
1 window in 200.

## Consumer-side workaround

hisab records `avg` (unaffected) and keeps `min`/`max` as supplementary CSV columns; from 3.2.1 its
`benchmarks.md` notes that the `min_ns`/`max_ns` columns of rows whose fixed 2000-op window is
under the host's bar are taken over perturbed windows only under 6.6.5+. No source change; the
right fix is in the instrument.
