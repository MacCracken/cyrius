# No stable sort: `vec_sort_by` (introsort) reorders equal keys, and ports must carry their own merge sort — open

**Status:** 🟡 **OPEN** (feature request) — verified on cyrius 6.7.18 (x86_64), 2026-11-11.
**Discovered:** 2026-11-11, by pravash's Rust → Cyrius port (M0 step 9, probe 5). impetus asked for the same at its M0
(its port plan §8, "Collections", not filed; its solvers sort on a total key instead).
**Reporter:** pravash 2.0.0 port (conversion ledger L9; `pravash/docs/development/pravash-port-plan.md` §8).
**Severity:** **Medium.** Deterministic simulations need a reproducible order among equal keys, so each port carries
its own merge sort.

## Summary

`vec_sort_by` is introsort, so elements with equal keys come out in an order that depends on the algorithm, not on
the input order. For a simulation that sorts particles by a spatial key (a Morton code: every particle in one cell
shares it), the order among equals decides the order of every later sum, and so the bits. A stable sort makes that
order the input order, which anyone can reproduce.

pravash's oracle uses Rust's `sort_unstable_by_key` (ipnsort). Its probe 5 found that ipnsort's tie order differs from
the stable order at 75–94% of positions on tie-heavy inputs, and that no reasonable port reproduces ipnsort. So
pravash sorts stably on (key, input index), a documented divergence (its ADR 0002 #3), and needs a stable sort to do
it.

## Reproduction

[`repros/2026-11-11-no-stable-sort.cyr`](repros/2026-11-11-no-stable-sort.cyr), from the repo root:

```sh
cyrius build docs/development/issues/repros/2026-11-11-no-stable-sort.cyr /tmp/stable
/tmp/stable; echo "exit=$?"
# adjacent equal-key pairs out of input order: 125     (256 elements, 8 keys)
# exit=1
```

`vec_sort_by` isn't documented as stable, so this is not a defect in it. The repro shows what a stable sort would
change.

## Ask

**`vec_sort_stable_by(v, cmp)`**: a stable sort with the same comparator contract. A merge sort with a caller-provided
(or internally allocated, then freed) buffer of n words would do, plus a slice form for typed stride arrays if the
stdlib has one.

## Notes from the consumer (pravash M4 part b, 2026-11-12)

pravash's stand-in is a bottom-up merge sort over index words, `_pv_msort(idx, n, tmp, cmp, ctx)` in
`src/neighbor.cyr` (its ledger row L9), shared by the SPH neighbour grid and `sort_by_zorder`. Pinned to one core,
1,000 elements:
- **100–106 µs a sort,** about 10 ns a comparison, most of it the `fncall3` to the comparator (two loads and a
  compare). That is half of `sort_by_zorder`'s 191 µs, against Rust's 95 µs for the whole of `sort_unstable_by_key`.
- A stable sort in the stdlib would serve pravash with the same contract (`cmp(ctx, a, b)` negative, 0 or positive)
  and a caller buffer of n words. pravash's parity rows for both users are class A, so a conversion must keep the
  order on (key, input index) exactly.
