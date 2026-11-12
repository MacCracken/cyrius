# The `syscalls` leaf has no monotonic clock, so a library that wants one carries `chrono` or a literal — OPEN

**Status:** 🟡 **OPEN** — verified 2026-11-09 against cyrius 6.7.18 (`31c24ca9b`).
- **No wrapper in `syscalls`:** every Linux and macOS peer defines
  `CLOCK_MONOTONIC = 1` (`lib/syscalls_x86_64_linux.cyr:332`,
  `lib/syscalls_aarch64_linux.cyr:558`, `lib/syscalls_macos.cyr:461`). No
  `syscalls*.cyr` file has a `SYS_CLOCK_GETTIME` constant or a
  `sys_clock_gettime` wrapper.
- **Only `chrono` reads the clock:** the one portable monotonic read is
  `clock_now_ns()` in `lib/chrono.cyr:94`, which spells `syscall(228, …)` raw.

**Placement:** unpinned — 6.x-line backlog. It is a `syscalls`-leaf wrapper and
its peers, plus a two-line change to `chrono`. No compiler change.
**Filed:** 2026-11-09 from taar 0.9.1 (the per-resolve deadline in its roadmap,
0.8.x). yo 0.8.0 and dig 0.5.2 are the other evidence.
**Severity:** Low. Nobody is blocked: a program can depend on `chrono` or issue
the number itself. The cost lands on small libraries and tools, which pay an
826-line, 57-function date-and-time module, or a syscall literal, for one
clock read.
**Affects:** `lib/syscalls_*.cyr` (every peer) and `lib/chrono.cyr`.

## Summary

Reading a monotonic clock is the one time primitive a timeout needs, and the
`syscalls` leaf does not offer it. A consumer has two choices:

- **Depend on `chrono`** for `clock_now_ns()`. That is correct on every target,
  including the reroutes:
  - arm64 macOS returns nanoseconds instead of filling the timespec;
  - x86 macOS uses `mach_absolute_time`;
  - Windows uses QPC;
  - AGNOS uses `uptime_us`#95, with `uptime_ms` behind it.

  The cost is a stdlib leaf of dates, local time and formatting that the caller
  does not otherwise use.
- **Issue the number itself.** yo does today, in
  `yo/src/platform_linux.cyr:42` (`_LX_SYS_CLOCK_GETTIME = 228`) and `:532`, with
  its own timespec. dig did the same until its 0.5.2, which moved to `chrono` to
  drop the last arch-guarded literal in `src/platform_linux.cyr` (113 / 228).
  This is the pattern the ecosystem's syscall rules warn against: a literal that
  happens to remap on aarch64 today, and gets none of `chrono`'s macOS or Windows
  handling.

## Repro

[`repros/2026-11-09-syscalls-has-no-monotonic-clock.cyr`](repros/2026-11-09-syscalls-has-no-monotonic-clock.cyr)
includes only `lib/syscalls.cyr` and reads the clock twice around a 10 ms
sleep. Today the build is refused: `undefined function
'sys_clock_monotonic_ns'`. Once the wrapper lands it exits 0.

```
cyrius build docs/development/issues/repros/2026-11-09-syscalls-has-no-monotonic-clock.cyr /tmp/smc
/tmp/smc; echo "exit=$?"
```

## Who it reaches

| Consumer | Today | Wants |
|---|---|---|
| **taar** (net substrate for yo / dig / whirl) | No clock. Its resolver bounds each *call* (8 receives × timeout, 16 TCP reads × timeout), not each *resolve*. | One deadline per resolve. Its rule is to add no stdlib leaf a consumer lacks, and yo does not carry `chrono`. yo is adding it (its roadmap 0.8.x), which unblocks taar, but a clock is a `syscalls`-sized need. |
| **yo** (ping) | A raw `syscall(228, CLOCK_MONOTONIC, …)`; AGNOS `sys_uptime_ms() * 1000`. | The same clock without a literal. Moving to `chrono` per its roadmap. |
| **dig** | `chrono` since 0.5.2, for this one function. | Unchanged; it could drop `chrono` if `syscalls` had the clock. |

## The ask

A monotonic read in the leaf every program already includes:

```cyrius
# Nanoseconds from a monotonic clock (CLOCK_MONOTONIC, or each target's
# equivalent). Not wall time; only differences are meaningful.
fn sys_clock_monotonic_ns(): i64
```

- **Linux:** add `SYS_CLOCK_GETTIME`, which is 228 on x86_64 and 113 on
  aarch64, in each per-arch enum. Add `sys_clock_gettime(clk, ts)` in
  `lib/syscalls_linux_common.cyr`, which `sys_clock_monotonic_ns` calls.
- **macOS, Windows, AGNOS:** these peers get the bodies that `chrono`'s
  `clock_now_ns` carries today, verbatim:
  - **macOS:** the 228 reroutes returning nanoseconds (id 4 on arm64);
  - **Windows:** `_chrono_qpc_ns`;
  - **AGNOS:** `sys_uptime_us()`, falling back to `sys_uptime_ms()` (including
    `chrono`'s `_chrono_agnos_ms40` latch).
- **`chrono`:** `clock_now_ns()` becomes `return sys_clock_monotonic_ns();`. It
  keeps its name and answers the same, so no `chrono` consumer changes.

The name is free across `~/Repos`, so the flat namespace is safe. The
macOS/Windows/AGNOS bodies already exist and are already tested through
`chrono`; this moves them a layer down rather than writing new ones.

## What taar does meanwhile

Its waits are bounded per call, and its roadmap carries the per-resolve deadline
as waiting on this issue or on every consumer carrying `chrono`. yo's roadmap
now has the `chrono` item, so whichever lands first unblocks it.
