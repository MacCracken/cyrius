# Two timing-sensitive .tcyr fail under CPU contention, and the corpus gates and cross-OS legs run them beside other work: `bench_timer_floor.tcyr` fails 6 of 16 runs 16-way parallel, `tls_native_ccs_deadline.tcyr` exited 5 under CYRIUS_IR=3 inside check.sh — check.sh / the release gate go red on a correct tree — RESOLVED

> ✅ **RESOLVED in v6.7.16** (PP-13, `f575dccd8` — no decision needed (a test and gate defect). `bench_timer_floor.tcyr`'s three live comparisons re-measure both sides for up to 5 rounds and fail only when every round disagrees (a `retry:` line names each disagreement); the two rows with a bias every round shares were re-shaped — the independent floor in 32 batches of 512 reads (5 of 4,096 held a preemption in every batch on an oversubscribed box), the slow-op row over 640 ops (64 was 2 windows). `# corpus: serial` on `bench_timer_floor.tcyr` and `tls_native_ccs_deadline.tcyr` makes `coverage_mode_corpus.sh` and `ir3_dce_corpus.sh` run them one at a time after their worker pool (the set derived by grep). The filed 16-way loop's class, re-measured 24-way on the 16-thread dev box: 19 of 24 RED before (41 of 48 48-way), 0 of 24 in three runs and 0 of 48 in two after; check.sh then read 573 / 573 beside the four cross-OS legs, both corpus gates running all 671 `.tcyr`. Rows: axis S in both corpus gates (≥ 2 marked files; the marked files ran in the serial pass, the rest in the pool; each serial run started after the pool's last ended), and `bench_timer_floor_measured.sh` axis D2b, which builds the file against two deterministic-defect stdlibs on every run and requires each retried row RED after `round 5 of 5`. Mutations each RED: the honouring dropped (M5, MS1), the serial runs backgrounded (M6), the floor raised (MS2), `_btf_retry` answering 1 after its last round, `_BTF_ROUNDS = 1`. ⚠ `tls_native_ccs_deadline.tcyr` did not reproduce (here or in the triage): it carries the marker only, no retry; the check driver's own serial `.tcyr` phase runs beside check.sh's gate pool and does not read the marker (there the retry covers `bench_timer_floor`, as on the cross-OS legs, which run one file at a time). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 platform lane (branch l6716-platform, unit P2, tree
86dafdc49; the unit changed only programs/cxvm.cyr, a cx fixture, a cx gate's comments, docs and
scripts/cross-os-selfhost.sh — nothing either test compiles or runs).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 platform lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; p16 lane, wave 3, unit PP4) — never 7.x.
**Severity:** Medium — a release-gate flake: `sh scripts/check.sh` and the cross-OS legs go red on a correct
tree and nothing names the cause as load (no ledger id; no boundary).
**Found:** running the unit's gates. Four red results, each green when rerun alone:
- `sh scripts/check.sh` (16-CPU box, the cass cross-OS leg running beside it): coverage_mode_corpus.sh
  `FAIL R ir3: tests/tcyr/crypto/tls_native_ccs_deadline.tcyr exits 0 plain, 5 under the mode`, and
  ir3_dce_corpus.sh `FAIL C tests/tcyr/crypto/tls_native_ccs_deadline.tcyr exits 5 under CYRIUS_IR=3
  CYRIUS_DCE=1`. Rerun alone: ir3_dce_corpus.sh PASS (664 / 664); the file under `CYRIUS_IR=3 CYRIUS_DCE=1`
  4 / 4 exit 0 from the repo root, plain 4 / 4.
- coverage_mode_corpus.sh rerun alone: `FAIL R x86: tests/tcyr/crossos/bench_timer_floor.tcyr exits 1 plain,
  0 under the mode` (its own 8 workers are the contention).
- `sh scripts/cross-os-selfhost.sh cass crossos`, run while the ecb / ach / pi legs ran from the same box:
  `ran 663 passed, 1 failed on cass — failing: bench_timer_floor.tcyr`. The same file on cass alone: 15 / 15
  exit 0; the cass leg rerun alone: 664 / 664.

## Reproduction

```sh
cycc < tests/tcyr/crossos/bench_timer_floor.tcyr > btf && chmod +x btf
for i in $(seq 1 16); do ( rc=0; ./btf > btf_$i.out 2>&1 || rc=$?; echo "$i rc=$rc" ) & done; wait
grep -h FAIL btf_*.out | sort | uniq -c
```

```text
(16 CPUs) 10 runs rc=0, 5 runs rc=1, 1 run rc=2
      2   FAIL: bench_clock_overhead_ns() agrees with an independent measurement (got 0, expected 1)
      4   FAIL: bench_run does not report MORE than the batched path for a sub-floor op (it was 256x) (got 1, expected 0)
      1   FAIL: bench_run matches an independently timed slow op (got 0, expected 1)
```

Run one at a time, the same binary exits 0 every time.

## Root cause

Both files assert wall-clock relations: bench_timer_floor.tcyr compares the bench framework's self-measured
clock floor and its per-op figures against independent measurements taken moments apart (`_btf_agree`), which
a descheduled thread breaks; tls_native_ccs_deadline.tcyr runs a forked peer under receive timeouts and
deadlines. The corpus gates run the whole corpus on their own worker pools (half the CPUs, at most 8), and the
cross-OS legs run on hosts the caller may load in parallel, so the timing rows share the CPU with other tests.
bench_timer_floor.tcyr's header says every assertion is relative "on purpose" (host speed), but relative
holds only while both measurements see the same scheduling.

## Fix direction

Run the timing rows alone: either mark the files (a `# corpus: serial` marker the corpus gates and the
cross-OS lib-test honour by running them after the pool), or have the assertions retry a disagreement a bounded
number of times before failing (a real regression — the 256× inflation it guards — reproduces every time).
