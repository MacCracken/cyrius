# 2026-06-16 — `clock_gettime` (syscall 228) not Darwin-ported: monotonic clock dead on arm64-macOS

> **Class:** `lib/chrono.cyr` and `lib/bench.cyr` hard-code the **x86_64-Linux**
> `clock_gettime` syscall number (`228`) on the non-AGNOS path. On aarch64-macOS
> that number is **not** Darwin's `clock_gettime`, so `clock_now_ns()` does not
> advance — a 50 ms sleep measures as **0 ms** — and every wall-clock /
> monotonic timing on macOS reads zero. Same class as the nanosleep `35`→`poll`
> fix (6.0.65), the `net.cyr` Darwin socket port (6.0.59), and `GETDENTS64`
> (6.0.63): a raw x86-Linux syscall number hard-coded in stdlib that means
> something else on aarch64-macho.
>
> **Status (2026-06-16): RESOLVED in v6.2.13 (chose direction #2 — stdlib branch).**
> `chrono.clock_now_ns`/`clock_epoch_secs`/`clock_epoch_ns` + `bench.now_ns` got a
> `#ifdef CYRIUS_TARGET_MACOS` branch using the syscall(228) **return value** (the
> arm64 Mach-O backend routes 228 → libSystem `_clock_gettime_nsec_np`, which
> returns ns in the register and does NOT fill `&ts`) with the **Darwin clock ids**
> (MONOTONIC=6, REALTIME=0, not Linux's 1/0). Verified on real `ecb`:
> `tests/tcyr/clock_monotonic.tcyr` (committed regression) PASSES — clock_now_ns
> advances ~50ms and clock_epoch_secs is a plausible epoch (was a dead 0).
>
> **Folded in (verifying the regression surfaced it): Windows chrono clock was
> ALSO dead** (same class — syscall(228)→GetTickCount64 returns in the register but
> chrono read the unfilled `&ts`). Fixed too: monotonic via the existing GetTickCount64
> route (×1e6 → ns); wall-clock via a **new PE reroute `0xF01B` →
> kernel32!GetSystemTimeAsFileTime** (FILETIME 100ns-since-1601 → Unix epoch, in
> `src/backend/pe/emit.cyr` + `x86/emit.cyr` + `parse_expr.cyr`). Verified on real
> **cass** (clock_monotonic.tcyr PASS) + wine. Clock now works on x86-Linux /
> arm64-macOS / aarch64-Linux / Windows. **x86-macOS (Intel) clock stays dead** —
> 228 is unrouted in the x86-Mach-O backend (pre-existing; that arch is HELD/EOL,
> see 2026-06-02). Closed.
>
> **Status (filed):** triage. Found by yantra's mobile parity benchmark on a real
> arm64 macOS host.

## How this surfaced

yantra's mobile parity benchmark (`programs/benchmarks-mobile.cyr`, on
`lib/bench.cyr`) was run on **Ecbatana** (arm64 macOS, cyrius 6.2.12) against a
live iOS 26.5 simulator + Appium. Every operation reported **`0ns`**:

```
  mobile.open(session): 0ns avg ... [1 iters]
  mobile.source(page xml): 0ns avg ... [20 iters]
  mobile.tap (1x, functional): 0ns avg ... [1 iters]
```

The session was real (it drove Settings and returned page source) — only the
*timings* were zero. Isolated with a minimal probe:

```cyrius
include "lib/syscalls.cyr"
include "lib/chrono.cyr"
fn main() {
    var a = clock_now_ns();
    sleep_ms(50);
    var b = clock_now_ns();
    return (b - a) / 1000000;   # delta in ms
}
var c = main();
syscall(60, c);
```

→ exit code **0** (delta = 0 ms over a 50 ms sleep). `sleep_ms` (poll-based,
fixed in 6.0.65) does sleep; `clock_now_ns()` simply does not advance.

## Root cause (call sites)

Both clock readers issue the raw Linux number on the `#ifndef CYRIUS_TARGET_AGNOS`
path — which **also covers macOS**:

- `lib/chrono.cyr:21` — `clock_now_ns()` → `syscall(228, CLOCK_MONOTONIC, &ts)`
- `lib/chrono.cyr:42`,`:56` — `clock_epoch_secs()` / wall clock →
  `syscall(228, CLOCK_REALTIME, &ts)`
- `lib/bench.cyr:24` — `var SYS_CLOCK_GETTIME = 228;` (used at `:30`,
  `syscall(SYS_CLOCK_GETTIME, CLOCK_MONOTONIC_RAW, &ts)`)

On x86_64-Linux `228` is `clock_gettime` and these work. On aarch64-macOS the
Mach-O backend does not route `228` to Darwin's clock path, so the call is a
no-op / garbage and the timespec stays zero.

## Impact

- **`cyrius bench` is meaningless on arm64-macOS** — all benchmarks read 0 ns.
- Any program timing wall-clock or monotonic elapsed on macOS is broken
  (`chrono.clock_now_ns` / `clock_now_ms` / `clock_epoch_secs`).
- **Blocks yantra's mobile parity numbers**: iOS only runs on macOS, and the
  yantra-side column needs a working clock there. The Appium (Python
  `perf_counter_ns`) column is fine; the yantra column can't be produced until
  this lands. (For the record, the Appium iOS baseline on this host: open ~3.45 s,
  source ~458 ms, find ~91 ms, tap ~2.4 s, flow ~3.9 s.)
- Secondary risk: any elapsed-time/timeout logic that reads `clock_now_ns` on
  macOS sees no progress (yantra's auto-wait happens to pass because elements
  appear fast, but timeout enforcement there is effectively dead).

## Recommended direction (for discussion)

1. **Route `clock_gettime` on Darwin in the Mach-O backend** (preferred — mirrors
   the `net.cyr` / `GETDENTS64` syscall-routing fixes), so the existing `228`
   call sites resolve to Darwin's clock. Darwin arm64 has
   `clock_gettime`/`clock_gettime_nsec_np`; or `mach_absolute_time` +
   `mach_timebase_info` for the monotonic source.
2. **Or** give `chrono` a `#ifdef CYRIUS_TARGET_MACOS` branch with the
   Darwin-correct monotonic source (the same shape as the `sleep_ms` poll fix),
   and have `lib/bench.cyr` call `chrono.clock_now_ns()` instead of its own raw
   `syscall(228)` — single source of truth for the clock.

A value-identical no-op like this is exactly the silent-wrong-output class; a
quick guard would help (cf. the duplicate-symbol guardrail in
`2026-06-14-stdlib-constant-value-collisions.md`).

## References

- Found by: yantra `programs/benchmarks-mobile.cyr` on Ecbatana (arm64 macOS,
  cyrius 6.2.12), iOS 26.5 sim + Appium 3.5.
- Same class: `35`→`poll` nanosleep (6.0.65), `net.cyr` Darwin port (6.0.59),
  `GETDENTS64` (6.0.63).
