# The dead-code reachability seed pass is O(call sites × fns): FIXUP dominates a large program's compile — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 infra lane (unit I3), while building the 4,096-run-cap
rows. Pre-existing: the per-hit host scan dates from v5.10.41 / v6.1.5 (`_dce_host_fn`).
**Placement:** 6.7.15 — repair 5 (infratools lane, wave 1, unit I4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — no wrong output; compile time. Every x86 and aarch64 build runs the pass (the DCE note and its
run registry are computed with `CYRIUS_DCE` unset too), so it is not an opt-in cost.
**Affects:** src/backend/x86/fixup.cyr and src/backend/aarch64/fixup.cyr, the seed pass ("Pass A") of FIXUP's
dead-code reachability walk.

## Reproduction

```sh
# n live fns, n dead fns, main calling each live one once
n=16000
awk -v n=$n 'BEGIN { for (i = 0; i < n; i++) { printf "fn d%d(): i64 { return %d; }\n", i, i; printf "fn l%d(x): i64 { return x + 1; }\n", i }
  print "fn main(): i64 { var x = 0;"; for (i = 0; i < n; i++) printf "  x = l%d(x);\n", i
  print "  return x & 255; }"; print "var e = main();"; print "syscall(60, e);" }' > q.cyr
CYRIUS_PROF=1 build/cycc < q.cyr > /dev/null
```

Measured (the 6.7.14 infra lane's compiler, a loaded box — load average ~25 — so read the ratios):

| n | compile | fixup |
|---:|---:|---:|
| 2,000 | 698 ms | 378 ms |
| 4,000 | 1,467 ms | 1,026 ms |
| 8,000 | 4,271 ms | 3,369 ms |
| 16,000 | 15,258 ms | 13,032 ms |
| 30,000 | 58,257 ms | 54,547 ms |

Each doubling multiplies FIXUP by ~3.5-4. At n = 30,000 the 6.7.14 slot-open compiler takes 32.7 s on a quieter box
with `CYRIUS_DCE` unset and 37.8 s with it set — the pass runs either way. cycc's own self-compile under the same
load: `prof: compile 4427 ms (... fixup=1362 ms ...)`, so FIXUP is a large share of `self_compile` too (re-measure on a
quiet box).

## Root cause

The seed pass walks every byte of the code buffer; for each `E8` / `E9` whose rel32 target is a fn start
(`_dce_hash_lookup`, O(1)) it asks which fn contains the call site with `_dce_host_fn` (backend/common/runtime.cyr) —
a linear scan over the whole fn table — to decide whether the call is a root (host < 0). So the pass is
O(call sites × fns). The comment above the pass already says it ("fn starts are rare ... linear lookup per match is
acceptable. For larger binaries a sorted array + bsearch would help").

## Fix direction

Build a start-sorted index of the fn ranges once per FIXUP (6.7.14 added the same shape for the live starts:
`_dce_live_starts` / `_dce_ls_sort`, runtime.cyr) and answer the host query by binary search — or, cheaper still,
walk the code with a cursor over the sorted ranges, since the scan is in address order. Nested ranges (inline
generic instances) need the innermost-or-first-in-index-order answer the linear scan gives today, or the seed set
could change: the decision only needs "is the site inside ANY fn", which a sorted-interval sweep answers exactly.
Rows: the reproduction at n = 16,000 compiles with FIXUP linear in n (e.g. under 10x the n = 2,000 time); cycc's
default output and the `N unreachable fns` notes are byte-identical over the corpus; `self_compile` measured
before / after.
