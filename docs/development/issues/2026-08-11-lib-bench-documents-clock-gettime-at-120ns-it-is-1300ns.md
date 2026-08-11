# `lib/bench.cyr` documents `clock_gettime: ~120ns`; it is ~1,320ns on x86_64 Linux

**Status:** 🔴 OPEN — filed from a consumer (agnosai), measured against v6.5.18.
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
