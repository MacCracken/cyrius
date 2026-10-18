# embed_build.sh axis 6 times ONE embed build against ONE baseline build, and the 2x bound flakes under host load — the slot-open tree fails it too — RESOLVED

> ✅ **RESOLVED in v6.7.14** (IN-16, `3002cdfc2` + `8c099f08d` (no decision needed: a gate): axis 6 times each build three times, alternating, checks the round trip on every sample and compares the minimums against the unchanged `2 × base + 200` ms bound — the proposed min-of-N (noise only lengthens a sample). Under load ~9 – 12 a run whose second pair alone (1941 vs 817 ms) crossed its bound passed on its minimums (1527 / 817). The mutation is still RED: B0b's interning index reverted, 13,366 vs 1,104 ms. Found in passing: under `bash -eo pipefail` the gate stopped at axis 3 with rc 1 and no verdict (its build helpers returned 1 for a refused build); it reaches its verdict now. Row: `embed_build.sh` axis 6, PASS under `sh` and `bash -eo pipefail`. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 by the 6.7.12 fixfirst lane gate. check.sh (`CYRIUS_CHECK_JOBS=4`, the
gate run alone after the pool as its `# check: serial` header asks, but beside other sessions' work: load average
13-19 on 16 cores) failed it: "axis 6: [embed] build took 1697 ms, the same bytes included last 693 ms — over 2x".
Re-run alone it passes on the lane tree four times in four (1099 / 581, 1118 / 581, 1146 / 581, 1220 / 733 ms), and a
scratch copy of the SLOT-OPEN tree (`git archive 7f57e532`, its own `build/cycc`) failed it once in three at load ~6
("[embed] build took 1421 ms, the same bytes included last 593 ms"; the other two 1159 / 659 and 1069 / 594) — so the
failure is the gate's sampling, not the lane (whose diff touches neither cbt/, lib/ nor the gate).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (infra lane, wave 1, unit I5; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — a false RED in check.sh / release-gate step 3 on a loaded box (the release gate runs the cross-OS
legs beside check.sh); it costs a re-run, and a re-run that passes teaches readers to ignore the row.
**Kind:** bug (gate).

## Reproduction

```sh
# from a checkout of 7f57e532 (or any 6.7.12 lane tree), on a box with other work running (load ~6 on 16 cores):
for i in 1 2 3; do sh tests/gates/toolchain/embed_build.sh 2>&1 | grep 'axis 6'; done
```

```
  ok axis 6: 2,000,000 B + stdlib + 3,000 literals round-trips; 1159 ms vs 659 ms hand-written-last
  ok axis 6: 2,000,000 B + stdlib + 3,000 literals round-trips; 1069 ms vs 594 ms hand-written-last
  FAIL: axis 6: [embed] build took 1421 ms, the same bytes included last 593 ms — over 2x: the embed sits FIRST in the pool, so cycc's literal interning is paying for it (B0b)
```

## Root cause

tests/gates/toolchain/embed_build.sh axis 6 takes one wall-clock sample of each build (`date +%s%N` around `br`) and
requires `emb_ms < 2 * base_ms + 200`. The quiet-box ratio is ~1.77 (the gate's own header), so the margin is ~12 % of
one sample; a scheduling hiccup during the longer embed build alone crosses it. `# check: serial` keeps check.sh's own
pool off it but not the release gate's concurrent cross-OS legs or other work on the host.

## Proposed fix

Take the minimum of N (3-5) alternating samples of each build before comparing (the regression it guards, B0b's
interning index, was 12.4 s vs 0.87 s — a 14x signal, so min-of-N keeps full sensitivity), or compare the compiler's
own work for the two units (e.g. an instrumented intern-scan count) instead of wall time. Keep the mutation: with B0b's
index reverted the row must still go RED.
