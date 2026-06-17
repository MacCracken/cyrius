# Runtime bench suite is blind — PF-01/02/03

> **PF-01 RESOLVED — v6.2.15.** (1) `_fmt_time` now prints a zero-padded 3-digit
> fraction in the µs branch (and s/ms for consistency) via `_fmt_pad3`, so sub-2µs
> benches show real resolution (e.g. `mulmod/binary_slow 1.466us`, not the pinned
> `1us`) and `bench-history.sh` parses them exactly (`1.050us`→1050ns, padding
> verified). (2) The tool-compile loop guard was checking `programs/${tool}.bcyr`
> (never exists) — fixed to `programs/${tool}.cyr` and `cybs` dropped; `compiler/
> {cyrfmt,cyrlint,cyrdoc,ark}` are now recorded. (3) The 8 orphan `.bcyr`
> (str/freelist/interning/keccak/mulmod/regalloc/shortcircuit/switch) are wired
> into Tiers 1–3 and now produce history (bench_mulmod's stale `lib/u128.cyr`
> include was repointed to `lib/bayan.cyr` after the v6.1.25 carve). A full run now
> appends 86 entries (was ~42). **PF-02** (alloc CAS-lock single-threaded fast
> path) and **PF-03** (per-release phase attribution) remain OPEN — must land
> before v6.4.x. See CHANGELOG [6.2.15].

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../audit/2026-06-10-deep-dive-review.md))
**Severity:** High (it silently defeats the "benchmark every release" gate and
blocks the v6.4.x/v6.5.x perf arcs from measuring their own wins)
**Affects:** `lib/bench.cyr`, `scripts/bench-history.sh`, `benches/*.bcyr` 6.1.31

## PF-01 — integer-µs truncation floor flat-lines the micro-benches (P1)

`_fmt_time`'s µs branch prints integer µs with no fractional digit (unlike the
s/ms branches), and `bench-history.sh:80` parses the printed string. So every
string/alloc/vec/tagged/float/fmt/hashmap entry has recorded **exactly
1000–2000 ns since 2026-04-16** (`bench-history.csv` from line 262; the latest
run has 37/42 tier1/2 benches pinned at exactly 1000 ns — only the 3 multi-op
benches still move). A 1.0→1.9 µs (+90 %) codegen regression is invisible. The
per-op harness overhead is ~240 ns (`bench.cyr:12`), so the resolution can't see
the wins the v6.4.x regalloc/copy-prop work targets.

Also dead: the **tool-compile loop** tests `programs/${tool}.bcyr` which never
exists (`bench-history.sh:171-175`; `programs/` has zero `.bcyr` — the
`.cyr→.bcyr` flip at `4563d3fe`); and **8 of 15 `.bcyr`** (including
`bench_regalloc`) have no history.

**Fix:** print fractional µs in `_fmt_time` (one line, mirror the ms branch) or
emit raw ns; fix the `:172` condition to `programs/${tool}.cyr`; add the 8 orphan
`.bcyr` to a tier. **Must land before v6.4.x** — the pinned "bench-delta
evaluation" slot (`roadmap_6.md:468`) cannot measure regalloc/copy-prop with a
1 µs-resolution harness.

## PF-02 — alloc() throughput regressed 3–6× (P2)

Every `alloc()` takes a CAS spinlock + 2 fences even in single-threaded programs
(`alloc.cyr:197-208`; lock added v6.0.64). CSV corroborates:
`alloc/burst_100x64` 909–990 ns (04-14) → 6 µs from the first post-gap run
(06-08) — ~9 ns→~60 ns per alloc; `vec/push_1000` 16–17 µs → 20–22 µs (+25 %).
Shipped invisibly in the v6.0.x bench gap.

**Fix:** add a single-threaded fast path — a `_threads_active` flag set by
`thread_create`/clone before the child runs; `alloc()` skips acquire/release
while 0. Restores the ~10 ns bump path for the dominant single-threaded case
(cycc itself).

## PF-03 — per-release bench records no phase attribution (P2)

v5.10.0 shipped per-phase timing (`CYRIUS_PROF=1`:
preprocess/lex/gvar/parse/fixup/emit/write, `main.cyr:896-1925`) explicitly
"measure first, then optimize the slow phase", but `bench-history.sh:161` runs
plain `cat src/main.cyr | $CC` — 40+ runs since 06-08 captured zero phase data.
The v6.5.x perf-refactor's own "first-step audit" wants exactly this.

**Fix:** extend tier3 to also run one `CYRIUS_PROF=1` self-compile and append
per-phase rows (`compiler/phase_lex`, `phase_parse`, `phase_fixup`, …) to the
CSV. Near-zero cost; by v6.5.x entry the cycle has a phase-resolved trend.

## Status

Filed 2026-06-10. PF-01 is a prerequisite for the v6.4.x bench-delta slot and the
v6.5.x perf-refactor minor — recommended before either opens.
