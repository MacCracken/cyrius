# Benchmark regimes — what the recorded numbers mean, and when they changed

`bench-history.csv` and `BENCHMARKS.md` span more than one **measurement regime**. Rows
from different regimes are not comparable, and two of the regimes contain numbers that
are not measurements of the code at all. This file is the ledger of those boundaries;
read it before quoting or diffing a historical row.

Created v6.5.19, from the agnosai filing
`2026-08-11-lib-bench-documents-clock-gettime-at-120ns-it-is-1300ns.md`.

## The regimes

| # | Window | What the micro rows mean |
|---|---|---|
| 1 | 2026-04-05 → 2026-04-14 | Per-iteration clock pair. Floor ~400–490 ns (this box still had a usable TSC). Real work below that is invisible. |
| 2 | 2026-04-14 → 2026-06-16 | **Fabricated.** `_fmt_time`'s `us` branch printed integer microseconds, so every value between 1,000 and 1,999 ns was recorded as exactly `1000`. 2,504 rows — 11 % of the 22,173 in the file — carry the literal value 1000. Fixed at v6.2.15 (PF-01). |
| 3 | 2026-06-16 → 2026-08-11 | Per-iteration clock pair again, but the box lost its TSC to the clocksource watchdog and fell back to HPET, so the floor rose to ~1,320–1,720 ns. **57 of 79 micro rows sit within 20 % of that floor**: they are measurements of the clock, not of the code. |
| 4 | v6.5.19 onward | `bench_run` sizes its own batches and every path subtracts the **measured** timer floor. Micro rows are the code. Every report prints the floor it measured. |

## What is and is not salvageable

- **Floor-pinned rows (regime 3, 57 of 79)** — **not** salvageable. The floor's own
  run-to-run noise is ±50 ns while the true work is 0.4–5 ns, so the signal-to-noise
  ratio is about 0.1. No arithmetic recovers a number that was never in the data.
  Example: `float/f64_from` recorded 1,327 ns and measures ~1 ns.
- **Above-floor rows (regime 3, 22 of 79)** — salvageable by subtracting ~1,420 ns.
  The correction is 0.6 % for `keccak/shake256/4KB` (254,019 ns) and 40 % for
  `vec/push_100` (3,566 → ~2,146).
- **Regime 2's clamped rows** — discard. `1000` there is a formatting artefact.
- **`compiler/*` and `size/*` rows — CLEAN in every regime.** They are timed by
  `date +%s%N` inside `bench_cmd()` (`scripts/bench-history.sh`) and never touch
  `lib/bench.cyr`. **The release-gate headline (`self_compile` ms, `cycc` size) is
  unaffected by any of this** — the growth-tax series is intact.

## The regime-3 → regime-4 step is expected and is not a regression

The first v6.5.19 run shows micro rows dropping by one to three orders of magnitude.
That is the instrument being removed, not the code getting faster. Measured examples,
same commit, same box:

| row | regime 3 | regime 4 |
|---|---|---|
| `freelist/alloc_free_64` | `1us` (floor) | 46 ns |
| `freelist/alloc_free_1KB` | `1us` (floor) | 47 ns |
| `freelist/calloc_64` | `1us` (floor) | 251 ns |
| a bare no-op through `bench_run` | 2,302 ns | 8 ns |

Do **not** bisect this step, and do not treat the first regime-4 delta column as a
perf win. Compare regime-4 runs only against other regime-4 runs.

## Why a single timer constant cannot be written down

One clock read, measured on the four hosts the release gate runs on:

| host | clock path | cost |
|---|---|---|
| dev box (x86_64 Linux, `hpet`) | raw `syscall(228)` | ~1,320–1,720 ns |
| pi (aarch64 Linux) | raw `syscall(228)` | ~3,550 ns (its vDSO: 55 ns) |
| ecb (macOS arm64) | libSystem `clock_gettime_nsec_np` | ~15–32 ns |
| ach (macOS x86_64) | libSystem `clock_gettime_nsec_np` | ~64–68 ns |

A 230× spread. The filing asked for the constant to be corrected to ~1,320 ns; that
value would have been wrong on three of the four hosts, and **4–8× too high** on ecb.
So `lib/bench.cyr` measures it instead — `bench_clock_overhead_ns()`.

⚠ **It also moves between reboots of the same machine.** The TSC-watchdog trip
(`Marking TSC unstable due to clocksource watchdog`) is per-boot and
non-deterministic, and `bench-history.csv` records no clocksource column, so a ~3×
floor shift can appear in the series with nothing in the file explaining it. That is
regime 1 → regime 3 on one machine that never changed hardware.

## The vDSO question

The filing attributed the 11× to cyrius issuing a raw syscall where libc uses the
vDSO. **Not on this host.** libc's vDSO `clock_gettime` measured 2,456 ns against the
raw syscall's 2,277 ns in the same paired run — no benefit, because HPET has no
userspace fast path and Linux's vDSO falls back to the syscall for it. A bare
`syscall(getpid)` is 776 ns, so kernel entry is about a third of the cost and the HPET
read is the rest.

A vDSO binding is still worth having: it is a genuine ~64× win on pi and on any
x86 box with a usable TSC. It is simply a **no-op on this dev box** while `hpet` is
the selected clocksource, so it cannot be justified from this box's numbers alone.
Not scheduled here; recorded so the next person measures before building it.
