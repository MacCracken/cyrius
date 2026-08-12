# `lib/bench.cyr` documents `clock_gettime: ~120ns`; it is ~1,320ns on x86_64 Linux

**Status:** ✅ RESOLVED v6.5.19 — the framework measures its own floor.

> **Resolution.** `bench_clock_overhead_ns()` calibrates one clock read at first use;
> every timing path subtracts it; `bench_run` sizes its own batches; `bench_report`
> prints the floor it measured. `docs/development/benchmark-regimes.md` is the ledger
> for the historical rows. Gates: `tests/tcyr/crossos/bench_timer_floor.tcyr`,
> `tests/gates/toolchain/bench_timer_floor_measured.sh`.
>
> **Three corrections to this filing, all measured rather than argued:**
>
> 1. ⚠ **"Correct the constant" was not implementable.** One clock read costs
>    ~1,320–1,720 ns here, ~3,550 ns on pi, ~15–32 ns on ecb and ~64–68 ns on ach — a
>    **230× spread across the four hosts the release gate runs on**. The requested
>    ~1,320 ns would have been wrong on three of them and 4–8× too HIGH on ecb.
> 2. ⚠ **The stated cause is wrong on this host.** libc's vDSO `clock_gettime` measured
>    the SAME as the raw syscall (2,456 vs 2,277 ns in one paired run): the clocksource
>    is `hpet` — the kernel dropped the TSC at boot — and HPET has no userspace fast
>    path, so Linux's vDSO falls back to the syscall. Kernel entry alone is 776 ns; the
>    rest is the HPET read. The cost is the box's clocksource, not the syscall choice.
>    A vDSO binding is still a real ~64× win on pi and on any normal-TSC box.
> 3. ⭐ **It was not "a single wrong line", and the interesting part is not the comment.**
>    Four numbers and two thresholds derived from the same figure. `120` fed **no
>    arithmetic anywhere in the tree** — but it is what made per-iteration timing look
>    affordable, and all 18 benches use `bench_run`, which wrapped a clock pair around
>    every iteration. The same no-op read **2,302 ns through `bench_run` and 9 ns
>    batched**; **57 of 79 recorded micro rows** are that floor rather than the code.
>    Fixing only line 6 would have left every one of them wrong.
>
> `compiler/*` and `size/*` rows are timed by `bench_cmd` and are unaffected — the
> release-gate `self_compile` / `cycc`-size series is intact.

**Filed as:** 🔴 OPEN — from a consumer (agnosai), measured against v6.5.18.
**Severity:** Medium. The constant is wrong by **11x**, it is the one every benchmark in the
ecosystem implicitly subtracts, and it is stated as fact in the header consumers are told to
read for "the full overhead-vs-batching guidance".

## The claim

`lib/bench.cyr:5-9`:

```cyr
# Overhead costs (x86_64 Linux):
#   clock_gettime:     ~120ns per call
#   fncall0 dispatch:  ~6ns per call (indirect call via function pointer)
#   direct call:       ~3ns per call
#   inline operation:  ~2ns per iteration
```

## The measurement

```cyr
fn _b_clock(): i64 {
    var n = 2000000;
    var b = bench_new("clock_epoch_secs");
    bench_batch_start(b);
    for (var i = 0; i < n; i = i + 1) { clock_epoch_secs(); }
    bench_batch_stop(b, n);
    bench_report(b);
    return 0;
}
```

```
clock_epoch_secs: 1.315us avg  [2000000 iters]
clock_now_ns:     1.318us avg  [2000000 iters]
```

Reproduced **1.315–1.347 µs across eight runs** on two machines-worth of sessions, at
2,000,000 iterations each. It is now a permanent row —
`clock_epoch_secs_baseline` in `agnosai/benches/fleet.bcyr` — precisely so the figure stops
being an assertion in a comment.

## Why it is 11x

`lib/chrono.cyr:75` issues a **raw** `syscall(228, CLOCK_REALTIME, &ts)`. That is a real
kernel entry. The ~120ns figure is what `clock_gettime` costs through the **vDSO**, which is
how libc serves it on Linux and which Cyrius does not use here. So the documented number is
plausibly correct for a different implementation of the same call — which is what makes it
easy to keep.

The other three constants in that block are consistent with what agnosai measures
(`benches/harness.bcyr`'s `noop` reads **2ns**, matching "direct call: ~3ns"), so this is a
single wrong line rather than a stale block.

## Why it matters beyond the number

Consumers subtract it. agnosai's `benches/fleet.bcyr` decomposes two rows as "one clock plus
the work", and with the documented constant that decomposition is wrong by ~1.2 µs per
clock — enough to invert which term dominates. In our case:

| row | measured | with 1.32 µs clock | with the documented 120 ns |
|---|---|---|---|
| `fleet_reach_barrier_3nodes` | 2.045 µs | clock is **~64%** | clock is ~6% |

Two readers of the same benchmark reach opposite conclusions about where the time goes, and
the one who trusts the header is wrong. It was reported to us as a fabricated number on
exactly those grounds, and re-measuring is what settled it.

## Expected

Correct the constant, and ideally say *why* it is what it is — "a raw `syscall(228)`, not the
vDSO path libc takes" is the part that stops it drifting back. If the vDSO path is a future
option, that is worth a line too, since an 11x cut to the timing floor would change how
small a shape is worth benchmarking at all.

⚠ Worth checking whether the same applies on aarch64 and macOS, which this filing does not
cover — the constants block claims x86_64 Linux specifically, and only that was measured.

## Repro

```sh
cd any-cyrius-project
# put the harness above in benches/clock.bcyr
cyrius bench benches/clock.bcyr
```
