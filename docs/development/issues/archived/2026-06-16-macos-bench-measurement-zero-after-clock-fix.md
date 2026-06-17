# 2026-06-16 — `lib/bench.cyr` measurements read 0 on arm64-macOS (after the 6.2.13 clock fix); macOS-only, triggered by `bench_new`

> **RESOLVED — v6.2.15.** Root cause was NOT `bench_new`/alloc (the issue's
> hypothesis): it was `bench.now_ns` calling `syscall(SYS_CLOCK_GETTIME, …)` with a
> `var` syscall number. The macOS `__got` clock reroute (`syscall(228)` →
> `_clock_gettime_nsec_np`) is keyed on a **compile-time literal 228**; a `var`
> does not const-fold, so the reroute never fired and a raw Darwin `svc 228` (a
> different BSD call) returned a constant **-9** — so every `now_ns()` was -9,
> `e - s == 0`, and all `bench_*` elapsed collapsed to 0. (`chrono.clock_now_ns`
> uses the literal and was always fine — same path, different spelling.) Linux is
> immune because `svc 228` there genuinely IS `clock_gettime`. **Fix:** literal
> `228` at each `now_ns` call site (macOS + Windows), mirroring `chrono`. Verified
> on real hardware: `now_ns` now advances and `bench_stop` measures a real interval
> on ecb (arm64-macOS) **and** cass (Windows) **and** pi (aarch64-Linux);
> regression `tests/tcyr/bench_elapsed.tcyr`. The broader `var`-number-on-macho/PE
> class (yukti/sakshi) is tracked in
> `2026-06-16-var-syscall-number-defeats-macho-pe-reroute.md`. See CHANGELOG [6.2.15].

> **Class:** follow-on to `2026-06-16-macos-clock-gettime-syscall-228-not-darwin-ported`
> (fixed in 6.2.13/6.2.14 — `chrono.clock_now_ns` and `bench.now_ns` now advance
> on arm64-macOS). The **clock primitive is fixed**, but the `lib/bench.cyr`
> *measurement layer* still reports **0 ns** on arm64-macOS — every
> `bench_start`/`bench_stop`/`bench_run`/`bench_report` elapsed is 0. **Confirmed
> macOS-only**: the identical code measures correctly on x86_64-Linux.
>
> **Status (filed):** triage. Blocks yantra's mobile parity numbers (iOS only
> runs on macOS, so the yantra-side column can't be timed).

## Confirmation it is macOS-specific

Same source, same toolchain line (6.2.14), two hosts:

| host | `bench_new` + `bench_start` / `sleep_ms(100)` / `bench_stop` → elapsed ms |
|------|------:|
| **x86_64-Linux** | **100** ✅ |
| **arm64-macOS** (Ecbatana) | **0** ❌ |

So `cyrius bench` is correct on Linux and dead on macOS.

## Bisection (arm64-macOS, full yantra benchmark include set)

All four probes share the same 15 includes (net…sandhi…sigil…bench) and run on
ecb with 6.2.14. Exit code carries the measured ms.

| probe | body | result |
|-------|------|-------:|
| `now_ns` direct | `a=now_ns(); sleep_ms(100); b=now_ns(); (b-a)/1e6` | **140** ✅ |
| `alloc_init` + `now_ns` | `alloc_init(); a=now_ns(); sleep_ms(100); b=now_ns()` | **172** ✅ |
| `+ bench_new` + struct slot | `alloc_init(); b=bench_new("x"); s=now_ns(); sleep_ms(100); e=now_ns(); store64(b+8,s); (e-load64(b+8))/1e6` | **0** ❌ |
| full `bench_start`/`bench_stop` | `alloc_init(); b=bench_new("x"); bench_start(b); sleep_ms(100); bench_stop(b)` | **0** ❌ |

`now_ns()` and `sleep_ms()` are correct (the first two rows). The regression
appears the moment **`bench_new`** is in play: storing a *known-good* `now_ns`
value into the bench struct (`b+8`) and reading it back no longer yields a
correct delta — `e - load64(b+8)` collapses to 0. So either `bench_new`'s
allocation returns a struct that doesn't round-trip / aliases the caller's stack
on Darwin, or the bench struct write/read interacts with the now_ns path. Either
way it is isolated to `bench_new` + the struct slot, and it is macOS-only.

`bench_start`/`bench_stop` themselves look correct (`store64(b+8, now_ns())` …
`now_ns() - load64(b+8)`), which points the finger at `bench_new`/the struct
allocation rather than the timing arithmetic.

## Impact

- `cyrius bench` produces all-zero results on arm64-macOS.
- yantra's mobile parity benchmark (`programs/benchmarks-mobile.cyr`, on
  `lib/bench.cyr`) cannot produce the yantra-side column — iOS only runs on
  macOS. (The Appium/Python column is fine.) This is the last blocker on a v1.0
  criterion (published mobile parity numbers).

## Suggested next step

Bisect `bench_new` (`lib/bench.cyr:54`) on arm64-macOS — what it allocs and the
struct layout it returns — against a plain stack/heap `store64;load64` round-trip
in the same include context. The 3rd/4th probe pair above is a minimal repro.

## References

- Predecessor: `2026-06-16-macos-clock-gettime-syscall-228-not-darwin-ported.md`
  (clock primitive — fixed 6.2.13).
- Found by: yantra `programs/benchmarks-mobile.cyr` on Ecbatana (arm64 macOS,
  cyrius 6.2.14). Linux control: same bench layer = 100 ms (correct).
