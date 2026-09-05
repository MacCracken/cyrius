# Compile time is superlinear in function count — 4× the fns costs 17× the time

**Status:** 🟠 **20x FASTER at v6.5.50 — the second contributor is FIXED and it was NOT either of
the two this file predicted. A third, much smaller one remains.** 60,000-fn fixture:
**43.6 s (v6.5.41) -> 23.9 s (v6.5.42) -> 1.0 s (v6.5.50).** 32,000 fns: 4,562 -> 405 ms.

⭐ **THE SECOND QUADRATIC TERM WAS `LEXID`, BUCKETING ON IDENTIFIER LENGTH ALONE.**
`bucket = klen` (saturated at 255) put every identifier of the same length on ONE dedup chain, so
the per-lookup walk over that chain *was* the O(N^2) scan the index was added at v5.10.40 to
remove — reintroduced for any realistic unit, because real code is full of same-length names.
`f0..f59999` is ~50,000 entries on a single chain. The key now mixes length with the first, middle
and last byte across 16,384 buckets. Output is byte-identical (dedup is still an exact byte-compare
and the canonical offset is still first-occurrence in source order, so only chain ORDER moves).
`lexid_heads` grew 2,048 -> 131,072 B with NO relocation, absorbing the 128 KB hole freed at
0x457C900 by v6.4.21. Gate: `tests/gates/frontend/lexid_buckets_by_content.sh`.

⛔ **BOTH CANDIDATES THIS FILE NAMED WERE RULED OUT — do not re-investigate them.**
* `_fnt_grow`'s rehash-and-copy: it doubles (`nc = _fnt_cap * 2`), so it is amortized-linear by
  construction. Ruled out by inspection.
* The DCE reachability walk over `live[]`: DCE is OFF by default (`CYRIUS_DCE=1` opts in), so it
  never ran in any of these measurements. Ruled out.
Also ruled out by measurement: the hash-table LOAD FACTOR (at equal 52 % load, 34k fns costs
16.9 us/fn and 70k costs 29.7 — and higher load measured *cheaper* per fn), and the object emitter
(`object;` and plain-executable forms scale identically).

**WHAT REMAINS, and it is now precisely localized.** Cost is nearly flat WITHIN a `_fnt_cap`
generation (34k -> 60k fns: +76 % fns for +29 % time) and jumps at the boundary (60k -> 70k: +17 %
fns for +182 % time), then flattens again. The residual is the **cost of an individual
`_fnt_grow`**, not its frequency-times-size product: one grow at the 65536 -> 131072 boundary costs
~1,145 ms, which is far more than copying 17 tables x 8.9 MB should take. Probe: growing 4x instead
of 2x (half the grows) cut a 34,000-fn compile 571 -> 231 ms. That is a candidate FIX, not a
diagnosis — it was reverted unverified, since it trades memory for time and the underlying reason
one grow costs a second is still unexplained. **Next step is to instrument `_fnt_grow` directly**
(the box has no `perf`, and `ptrace_scope=1` blocks gdb from attaching to a running compile).

⚠ **`CYRIUS_PROF`'s phase labels are misleading and cost time in this investigation.** It reports
`gvar=2408 parse=0` on a 120k-fn unit; `_prof_gvar_end` is stamped after the WHOLE two-pass parse
(`src/main.cyr:1829`), so "gvar" is the entire front end and "parse" is always ~0.

⭐ **The suspected cause was the right one, and it was confirmed by measurement before being fixed rather than after.** `REGFN`'s REVERSE overload registration walked EVERY already-registered fn for each new one, looking for a sibling named `<my_name>_<suffix>` — quadratic by construction (~1.8x10⁹ name comparisons at 60k fns). Disabling it outright took the same fixture 43.5 s → 23.6 s, i.e. **it was 46 % of total compile time**, and its share grows with the square.

**The fix is three hash lookups replacing the walk**, and it is *exactly* equivalent rather than an approximation: the scan was looking for a fn whose name is the concatenation `<my_name>` ++ `<suffix>`, so direct lookups of those three names find precisely the same set. ⚠ `_FINDFN_CSTR` could NOT be used — it is itself a linear scan, so three calls would have made it worse; the fix probes the hash table directly (4-byte slots since v6.5.40). Equivalence is *verified*, not argued: **cycc's output is byte-identical** on three independently-compiled programs, and the self-host fixpoint holds.

⛔ **A SECOND QUADRATIC CONTRIBUTOR REMAINS AND THIS FILING STAYS OPEN FOR IT.** 23.9 s for 60,000 functions is still far off linear — the 28,000-fn baseline in the CI comment was ~8 s, so roughly 2.1x the functions still costs ~3x the time. The remaining candidates from the original list are untouched and now easier to see with the dominant term removed:
* `_fnt_grow`'s rehash-and-copy of ~16 parallel tables (amortized-linear in theory; rule it out by measurement, not by argument).
* The DCE reachability walk over `live[]`, which may be quadratic in cross-fn references rather than in fns.

⚠ **And the fixture that used to exercise this is gone.** v6.5.40 moved the `capacity` gate's trip source off `fn_table` to `string_data` precisely because tripping it needed 111,412 fns at 2 m 17 s — so **no gate exercises a large fn count any more**, and this curve is unobserved. Acceptance item 3 (a bench entry) matters more now than when it was written.
is present before the v6.5.40 limits cascade; the cascade is only what made it *reachable*.
**Placement:** unpinned — 6.x-line backlog. Codegen/compiler performance, so **never 7.x**.
**Discovered:** 2026-09-02 while re-sizing the `capacity` CI fixture after the fn ceiling went
32,768 → 131,072. Tripping the 85 % check needs 111,412 fns, and generating that fixture is what
surfaced the cost.
**Severity:** Medium — nothing is wrong today, but it sets the practical ceiling well below the
new hard caps, which is precisely the audience v6.5.40 just widened for.

## Measurement

Identical source shape (`fn fN() { return N; }`, one per line, `object;` prelude), compiled with
`build/cycc` on the same quiet box:

| fns | source | wall time |
|---|---|---|
| 28,000 | ~0.8 MB | **~8 s** (recorded in the pre-existing CI comment) |
| 112,000 | 3.2 MB | **2 m 17 s** (`134.7 s` user) |

4× the functions, **~17× the time**. Linear would predict ~32 s.

## Why it matters now, and only now

The fn table's hard ceiling was 32,768 until v6.5.40, so nobody could get far enough up the curve
for it to bite — 28,000 fns at ~8 s was the most anyone could reach. The ceiling is now 131,072,
and real consumers run about **1,009 fns/MB** (thoth: 12,107 fns across 12 MB of lib+src). At the
new 24 MB preprocess ceiling a real project lands near **24,000 fns**, which is fine. But the caps
now permit ~131k, and a project that grows into them would meet a compile time that is not
linear in its size.

⚠ **This is the reason the `capacity` CI fixture moved off `fn_table` to `string_data`** — see
`.github/workflows/ci.yml` and `programs/checks/heap_audit.cyr::_capacity_gate`. A gate that costs
2 m 17 s is not one anybody keeps. That workaround is fine, but it means **no gate now exercises a
large fn count at all**, so this curve is unobserved.

## Not yet root-caused

Deliberately not guessed at. Candidates worth measuring before choosing one, in rough order of
suspicion:

* `_fnt_grow` rehashes the name-hash and copies ~16 parallel tables on every doubling. That is
  amortized-linear in principle, but v6.5.40 halved the initial cap (8192 → 4096, because the
  hash slots widened to 4 B and the fixed 16 KB regions now hold 4096) so a large program does
  one *extra* grow. Amortization says this cannot explain 17×, but it should be ruled out first.
* The DCE pass: `live[]` is a bitmap over fns, and the reachability walk may be quadratic in
  cross-fn references rather than in fns.
* `REGFN`'s REVERSE overload-registration scan (`parse_fn.cyr`) walks **every already-registered
  fn** for each new one looking for `<name>_str`/`_int`/`_cstr` siblings. That is O(n²) in fn
  count by construction, and at n=112,000 it is ~6×10⁹ name comparisons. **This is the strongest
  candidate and the cheapest to confirm** — bound or index it and re-time.

## Acceptance

1. Root cause identified by measurement (per-phase timings via `CYRIUS_STATS` / the existing
   `compiler/phase_*` bench keys), not by inspection.
2. A fixture at ≥100,000 fns compiles in time proportional to the 28,000-fn baseline within a
   stated factor.
3. A bench entry so the curve stays observed — the fixture that used to cover this was removed.
