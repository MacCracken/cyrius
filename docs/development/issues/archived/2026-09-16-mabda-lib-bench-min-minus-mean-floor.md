# `lib/bench.cyr` subtracts a mean timer floor from every window, reports the minimum, and calibrates the floor only once — FIXED

**Status:** ✅ **FIXED in 6.6.5 (bite 6)** — see CHANGELOG [6.6.5] and the corrections at the
bottom of this file.
**Placement:** shipped.
**Discovered:** 2026-09-16, mabda 4.1.3 verification. `make bench-gpu` on the Cezanne dev box
(hpet clocksource, floor 1.274 µs) printed `uniform_buffer_write: 2.825us avg (min=0ns ...)`
and `CSV:uniform_buffer_write,0`.
**Severity:** Medium for benchmark consumers, none at runtime. It never affects shipped code.
It produces **wrong benchmark numbers**: minima that read low or 0, and, with an inflated
floor, averages that read low. A regression gate or history built on those rows follows the
clock rather than the code.

Log paths below are in the 4.1.3 verification scratchpad (`verify-logs/`), not in the repo.
**Affects:** lib/bench.cyr in cyrius 6.6.4; unchanged at HEAD 4f3731e8. Component: stdlib (`lib/bench.cyr`)

## Summary

Three related defects.

### 1. A minimum over windows, net of a mean floor

`bench_clock_overhead_ns()` (`lib/bench.cyr:141`) is the floor. `_bench_calibrate_clock`
(`:112-137`) takes the fastest of 5 batches of 1,024 clock reads, subtracts the fastest empty
loop, and divides by 1,024. That is the **mean** cost of one read in a quiet batch.
`_bench_net` (`:148`) subtracts it from **every** timed window, clamped at 0. Then:

- `bench_stop` (`:186`), `bench_batch_stop` (`:381`) and `bench_run_batch*` (`:296-356`) keep
  `min_ns`, the smallest net window per op.
- `bench_report` (`:470`) prints that minimum next to the average, and `bench_min_ns` (`:202`)
  hands it to callers (mabda's `CSV:` rows record it).

A window's own clock cost varies from read to read. The minimum over windows of
`op + c_i − mean(c)` is `op − (mean(c) − min(c_i))`, so it reads low by up to that spread, and
reads 0 when the spread exceeds the op. The average stays unbiased. The error per op is divided
by the ops in the window, so single-op windows (`bench_start` / `bench_stop`, or
`bench_batch_stop(b, 1)`) take all of it.

Measured with `lib/bench.cyr` itself (`verify-logs/r2-align/50-benchprobe-local-hpet.log`,
3 runs; the dev box, hpet clocksource):

| | runs 1 / 2 / 3 |
| --- | --- |
| calibrated floor | 1,214 / 1,211 / 1,208 ns |
| one empty window, min / mean | 489 / 1,214; 489 / 1,220; 838 / 1,216 ns |
| empty windows below the floor | 9,460 / 9,193 / 9,403 of 20,000 |
| `getpid` timed one per window (`bench_start`/`bench_stop`), min / avg | **0** / 247; **0** / 356; **0** / 295 ns |
| `getpid`, 128 per window (`bench_batch_stop`), min / avg | 261 / 268; 266 / 278; 258 / 268 ns |

On chew (tsc, window jitter about 5 ns) the same probe shows no bias: one per window reads
min 705 to 709 ns against 708 to 710 ns batched (`r2-align/chew/01-benchprobe-chew-tsc.log`).
The defect scales with clock jitter, which is why it appears on one box and not the other.

`bench_run` (`:242`) is largely immune by construction. It sizes chunks so the floor is at most
1 % of a window, which divides the bias by the chunk size.

### 2. The floor is calibrated once, at first use, and never checked

`bench_clock_overhead_ns` calibrates lazily on its first call and caches the result for the
life of the process. Nothing compares it with the windows actually being measured. If the
~4-6 ms calibration runs during a slow moment, every row of that process subtracts too much,
and the clamp at 0 then pulls **averages** down too, not just minima.

Observed once in the 4.1.3 round-1 verification on chew (tsc)
(`fix-wgpu-programs/06-clock-opprobe-chew-tsc.log`): the calibration returned **3,861 ns**.
The same process measured empty windows at min 727 and mean 1,207 ns. 19,955 of 20,000 empty
windows fell under the floor, and a modelled 700 ns op clamped to 0 in 19,405 of 20,000
windows. The next run on the same boot calibrated 733 ns.

The trigger is **not established**. Round 1 attributed it to a cold CPU, but the round-2
reruns did not reproduce it:

- 3 local runs after 3 s idle, calibrating within 0.5 % of the value after a 500 ms warm-up.
- 3 + 5 runs on chew (intel_pstate powersave) after 5-25 s idle
  (`r2-align/chew/01-*.log`, `02-benchprobe-chew-long-idle.log`), all within 0.5 % as well.

The defect does not depend on the cause. A single unguarded calibration applies whatever the
machine was doing in those few milliseconds to every row. The header's warning that "the floor
moves between reboots" covers boots, not a transient inside one process.

### 3. Integer ns per op

`per_op = elapsed / batch_size` (`:306`, `:327`, `:348`, `:384`; `bench_run` `:256`) truncates to whole
nanoseconds. For ops of a few ns, one unit of truncation is a large fraction of the row, and a
sub-ns shift in the subtracted floor can move a row by a whole unit. In the mabda run below,
`workgroups_2d` goes from 7 to 6.

## Impact on mabda

- **`programs/benchmarks.cyr` (`make bench-gpu`): affected, worked around in 4.1.3.** It warms
  the CPU before calibrating and measures clock jitter right before each row. The uniform-write
  row runs K ops per window, sized so jitter is ≤1 % of a window. A row that reads 0 ns fails
  the run (exit 1). The resource-creating rows must stay at one op per window, so each prints
  its under-read bound (`per-op min may under-read by <= X ns`). The Cezanne run of the new
  benchmarks is still open verification (round-1 review).
- **`tests/bcyr/mabda.bcyr` (`make bench`, CI `Bench` step): marginally affected. No row can
  read 0.** Every row times a batch (10,000 ops per window, or 100 for the two
  `rg_plan_aliasing_stats_*` rows), and the CSV records `bench_min_ns`. Measured on the hpet
  box over 5 interleaved runs with the library floor, no subtraction, and the round-1 inflated
  floor forced to 3,861 ns (`verify-logs/r2-align/53-mabda-bcyr-floor-sensitivity-local-5runs.log`):
  - **10,000-op rows:** within run-to-run spread under every variant, except `workgroups_2d`,
    which reads 6 instead of 7 with the inflated floor (the truncation effect in §3). The worst
    case is (floor − fastest window clock) / 10,000: ≤ 0.07 ns per op with the library floor,
    ≤ 0.34 ns with 3,861 ns.
  - **`rg_plan_aliasing_stats_5` (100 ops per window):** median 827 ns with the library floor,
    799 ns with 3,861 ns. That is −28 ns (−3.4 %), matching the model
    (3,861 − 1,212) / 100 ≈ 26 ns. With the library floor the bias bound is (1,212 − 489) / 100
    ≈ 7 ns (≤ 0.9 %).
  - **`rg_plan_aliasing_stats_30`:** its ~250 ns run-to-run spread swamps a ≤ 26 ns effect.
  - So `bench-history.csv` rows from `mabda.bcyr` are trustworthy to a few percent. The two
    `rg_plan` rows are the ones to discount if a run's printed floor looks inflated against
    earlier runs on the same boot.

## Reproduction (CPU only)

`verify-logs/r2-align/tools/benchprobe.cyr`, built from a mabda checkout with
`cyrius build benchprobe.cyr benchprobe`. It includes `src/lib.cyr` and `lib/bench.cyr`, and
does four things:

1. Calls `_bench_calibrate_clock()` at process start, again after 500 ms of busy work, and a
   third time.
2. Times 20,000 empty `now_ns()` pairs.
3. Sets `_bench_clock_ns` to the warm value and times `syscall(39)` (getpid) with
   `bench_start`/`bench_stop` (one per window) and with `bench_batch_start`/`bench_batch_stop`
   (128 per window).
4. Repeats step 3 with the process-start value.

On an hpet box, step 3's one-per-window row reports `min=0ns` while its average and the
batched row agree at about 260-360 ns.

## Expected vs actual

- **Expected:** a reported minimum is a lower bound on the op, not on the op minus clock jitter.
  The floor subtracted from a process's rows reflects the conditions those rows ran in.
- **Actual:** per-window minima read low or 0 whenever window-to-window clock jitter is
  comparable to the op, and a single calibration taken at a slow moment is subtracted from
  every row of the process.

## Proposed fix

1. Do not subtract a mean from a quantity whose minimum you then report. Either subtract the
   **minimum** single-read cost when computing minima (keeping the mean for averages), or
   report `min` only for windows long enough that jitter is ≤ 1 % of them (what `bench_run`
   already does) and print `min=n/a` otherwise.
2. Check the floor against the run. Re-calibrate (or at least compare) when the first report
   prints, and warn when the median empty window of the run differs from the calibrated floor
   by more than a set fraction. Do the warm-up that mabda's `benchmarks.cyr` now does before
   calibrating.
3. Keep per-op results in sub-ns units (for example fixed-point thousandths), or report a
   batch total alongside the per-op integer.
4. Add a gate: on a host whose empty-window jitter exceeds a few hundred ns, a `getpid` timed
   one per window must not report `min=0`.

## Filing

Filed 2026-09-16 from mabda 4.1.3. mabda keeps its own record at
`mabda/docs/development/issues/2026-09-16-stdlib-bench-min-minus-mean-floor.md`.

---

## Corrections to this filing

Everything the filing MEASURED held up when it was re-measured on the same box. Three of its
conclusions did not, and one of them was the proposed fix.

1. ⛔ **Proposed fix 1's first branch — "subtract the MINIMUM single-read cost when computing
   minima" — DOES NOT WORK, and this was measured before any code was written.** Re-netting
   the very same raw `getpid` windows by the smallest EMPTY window gives **70 / 0 / 0 ns**
   against a true ~280 ns. The reason is visible in the data: the minimum raw `getpid` window
   (907 ns) came out EQUAL to the minimum empty window (907 ns) in 2 of 3 runs. The clock cost
   inside a window that does work is not drawn from the same distribution as an empty window,
   so it dips below any empty-window minimum and **no choice of scalar floor rescues a
   per-window minimum**. The shipped fix is the filing's own second branch — report a min only
   for windows long enough that the clock's error is ≤1 % of them — with two changes: the
   threshold uses the clock's TICK as well as its read cost, and an unresolved row reports the
   **mean** rather than `min=n/a`, because seven consumer repos parse that field as a number.

2. ⛔ **"`bench_run` is largely immune by construction" — it was not.** Its 16-op pilot chunk
   and its short remainder chunk both fed min/max regardless of how the middle chunks were
   sized. Measured: `bench_run(noop, 1e5)` reported `min=0` in **91 of 200** and **120 of 200**
   runs, and cyrius's own `benches/bench_tagged.bcyr` and `benches/bench_float.bcyr` printed
   `min=0ns` on **5 of 14 rows**, with 4 ns rows printing `max=27–60 ns` from pilot garbage.
   Chunk sizing was also blind to clock GRANULARITY, which matters on any coarse-counter host.

3. ⚠ **"The average stays unbiased" — only when no window clamps.** `_bench_net` clamped every
   window at 0, and 88 to 3,584 of 20,000 windows clamped on this box, each contributing more
   than it measured. The fix keeps the RAW total and nets `windows × floor` at read time, which
   removes the bias and also lets a re-measured floor correct rows already accumulated.

4. ⚠ **The re-measured magnitudes differ from the filing's** (same box, different day): the
   floor calibrated 1,317–1,442 ns rather than 1,208–1,214, and 5,027 / 11,210 / 11,157 of
   20,000 empty windows fell below it rather than ~9,300. Same phenomenon, and the filing's
   warning that the floor moves between boots is exactly why.

5. **The slow-calibration trigger (§2) was not reproduced** and does not need to be. The fix is
   structural: calibration warms up, repeats until two rounds agree, and `bench_report`
   re-measures and adopts a LOWER value. Whatever caused chew's 3,861 ns, the process no longer
   subtracts it from every row.

6. **Proposed fix 4 (a live host-jitter gate) was built and rejected as the PRIMARY gate.** The
   crossos test's own header records two live-statistic axes this repo has already shipped —
   one unsatisfiable by construction, one passing about two runs in three. The primary gate is
   a scripted clock with closed-form expected values, mutation-proven ten ways; a one-sided
   live assertion (`a real op never reports a zero minimum`) is kept as a supplement.
   ⚠ And that live assertion is a TRIPWIRE, not the discriminator: with the resolution rule
   reverted in a scratch lib, six assertions went red and every one of them was in the scripted
   axis — the live `bench_min_ps > 0` checks stayed GREEN, because the test calibrates its op
   far above the window size where the defect lives. Both comments now say so.

7. ⛔ **The first cut of the fix over-claimed, and review caught it: "never 0 for real work" is
   FALSE.** It was written into `lib/bench.cyr`'s header, `docs/stdlib-reference.md`, the
   CHANGELOG and correction 1 above. If a row's windows do not in total outlast the clock reads
   that bracketed them (`raw_total <= windows × floor`), `bench_total_ns` clamps at 0, so the
   mean is 0 and the unresolved min/max follow it. Measured: `bench_run(noop, 16)` reported
   min=0 in **69–317 of 500** reps and `bench_run(noop, 100)` in **55 of 500**, while `getpid`
   at both n and a 50-iteration loop at n=16/100/1000 were **0 of 500**. This is NOT the defect
   filed here — that was a 250 ns operation reading 0 beside a mean of 250 — and it cannot be
   fixed by arithmetic: reporting the raw mean would report the CLOCK as the operation, the
   256× inflation v6.5.19 removed. So 0 is kept and NAMED. `bench_sub_floor(b)` is 1 exactly
   there, the report's supplementary line says `SUB-FLOOR ... 0 means below the instrument`,
   and leg (g) of the crossos test pins it closed-form beside a 250 ns control on the same
   scripted clock. All four claim sites are corrected in place rather than quietly edited,
   because a rule that declares one shape of a defect acceptable is what prevents the fix from
   covering it.

### Found while fixing it, and fixed in the same bite

- `lib/bench.cyr` had **no AGNOS arm**: an AGNOS build emitted a raw `syscall 228`, which
  AGNOS does not define (verified with llvm-objdump). `lib/chrono.cyr` moved to `#95` at 6.6.1.
- **macOS was timing at microsecond resolution.** Darwin clock id 6 is `gettimeofday -
  boottime` with `clock_getres == NSEC_PER_USEC`; both bench and chrono now pass id 4.
- **Windows had no sub-millisecond clock at all** — GetTickCount64's tick is 15 ms. New PE
  reroutes 0xF038/0xF039 (QueryPerformanceCounter/Frequency).
- `tests/tcyr/crossos/bench_timer_floor.tcyr` had **measured this exact defect on pi, written
  it up, and declared it correct behaviour** ("that 0 is not a defect") five weeks before this
  filing. That rationale is retired and replaced with the assertion it excused.
- `programs/cyrsign.cyr` carried a dead `include "lib/bench.cyr"`.
- `_bench_measure_tick` could **spin ~9 minutes on a clock that had stopped** (a hardcoded
  100,000,000-iteration guard × 4 rounds at 1.4 µs per read) and then FABRICATED a 1 ns tick —
  the smallest possible error from the most broken possible clock. Bounded now by a read budget
  derived from the measured floor, reporting a measured lower bound or a sentinel priced at one
  second. Found in review; harmless before 6.6.5 only because nothing read the tick.
- `now_ns`'s macOS comment still said **"x86-macho 228 unrouted → HELD"**; `EMACHO_CLOCK_X86`
  has composed `gettimeofday` there since v6.5.16. Corrected, with the two facts a bench needs
  from it (REALTIME, so NTP-steppable; microsecond resolution, so tick 1,000 ns on ach).
- The gate **counted a mutant that failed to COMPILE as killed**, silently, and aborted at
  exit 4 under `bash -eo pipefail` at its own intentionally-failing mutant. Both fixed, plus an
  empty-binary check and a tenth mutant for `bench_sub_floor`.

Found at the SECOND review round of the same bite:

- The QPC fix's first cut made **`lib/chrono.cyr` and `lib/bench.cyr` stop being
  self-sufficient**: both called `sys_qpc_ns()` from `lib/syscalls_windows.cyr`, which neither
  module includes, so a consumer declaring only `"chrono"` (or `"bench"`) in `[deps] stdlib`
  could no longer cross-build for Windows. Both now spell 0xF038/0xF039 raw. A repair that
  breaks a *different* consumer shape is not a repair; the gate's new axis E cross-builds both
  shapes for PE every run.
- **`bench_sub_floor` answered 1 on a stopped clock**, whose floor is 0 — "at or under one
  clock read" against a read of 0 ns. It answers 0 now; the tick sentinel is the discriminator.
- **The tick sentinel was sticky**, so the recovery path this release added never ran: once
  `-1`, no healthy re-measurement could replace it and every row reported the mean for the life
  of the process.
- Axis A of the gate — the ⭐ "the constant must not come back" grep, the stated reason the gate
  exists — **had no control for its own pattern**, so a reworded paragraph or a broken pattern
  would have left it passing over nothing. Axis B's timing-path list was hand-maintained against
  a fixed floor; it is derived now.

### For mabda

No change is required to keep working: every public symbol keeps its name and arity. After the
6.6.5 tag and a re-vendor, `programs/benchmarks.cyr`'s workaround (the jitter probe, the K
sizing, the "may under-read by <= X ns" text) is redundant and its resource-creating rows will
report the mean with `bench_min_resolved(b) == 0` instead of 0 (and, for any row whose whole
window is under one clock read, 0 with `bench_sub_floor(b) == 1`) — `mabda/docs/development/issues/2026-09-16-stdlib-bench-min-minus-mean-floor.md`
can close with this file.
