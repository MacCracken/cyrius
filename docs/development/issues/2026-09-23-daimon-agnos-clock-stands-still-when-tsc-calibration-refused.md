# agnos: `clock_now_ns` / `clock_now_ms` stand still for the whole boot when the kernel refuses its TSC calibration — OPEN

**Status:** 🟡 **OPEN**: `lib/chrono.cyr` has no fallback for `uptime_us`#95's documented failure
answer.
**Placement:** unpinned — 6.6.x-line backlog.
**Discovered:** 2026-09-23 during daimon 2.4.1, running daimon's AGNOS guest test with QEMU held to
25% of a CPU (to see how it would fare on a slow CI runner).
**Severity:** Medium: a hard failure (every deadline loop spins forever) with a known workaround.
**Affects:** cycc 6.6.1 through 6.6.6 on the agnos target. 6.6.1 is the release where `clock_now_ns`
moved from `uptime_ms`#40 to `uptime_us`#95 (the note above it in `lib/chrono.cyr`).

## Summary

On agnos, `clock_now_ns()` is `sys_uptime_us() * 1000`. The kernel's `#95` answers
`(rdtsc - tsc_base) / tsc_per_us`, or **-1 when its one boot-time TSC calibration was refused**. The
kernel does not calibrate again, so it answers -1 for the rest of the boot. `clock_now_ns` then
returns -1000 every time, and `clock_now_ms` returns 0 every time. Nothing reports an error, and
`clock_now_ms() - t0 < ms` stays true forever. The kernel's own comment on `#95` says it answers -1
and "never a plausible-looking zero". chrono turns that -1 into exactly such a zero.

## Reproduction

The trigger is a refused calibration. agnos 1.57.5 (`kernel/core/main.cyr`, `tsc_calibrate`) counts
TSC cycles across 5 timer ticks and refuses a result below 100 or above 10000 cycles per µs. Measured
in daimon's guest test, agnos 1.57.5 and gnoboot 0.7.2 (the released binaries) under QEMU TCG:

- unrestricted: `tsc: 3192 cycles per microsecond`, and the test passes;
- with the QEMU process held to 25% of a CPU (`systemd-run --user --scope -p CPUQuota=25% qemu-system-x86_64 …`):
  `tsc: calibration REFUSED -- uptime_us will report 0`. Then the first
  `var t0 = clock_now_ms(); while (clock_now_ms() - t0 < 10) { sys_pause(); }` in the test program
  never returned. After 12 minutes there was still no output, with the vCPU thread busy.

The shape of it, in any agnos program built with cycc ≥ 6.6.1, on a boot whose log says
`calibration REFUSED`:

```cyrius
var t0 = clock_now_ms();                  # 0
while (clock_now_ms() - t0 < 10) { }      # 0 - 0 < 10 forever
```

## Root cause

`lib/chrono.cyr`, `clock_now_ns`, agnos branch (`:73`–`:76` in the 6.6.6 snapshot):

```cyrius
#ifdef CYRIUS_TARGET_AGNOS
return sys_uptime_us() * 1000;
#endif
```

The -1 is not checked.

## Proposed fix

Fall back to `uptime_ms`#40 when `#95` answers below 0:

```cyrius
var us = sys_uptime_us();
if (us >= 0) { return us * 1000; }
return sys_uptime_ms() * 1000000;
```

`#40` stands still only for a foreground `run` program (IF cleared), which is the case the 6.6.1
note moved to `#95` for. A background program, a service for example, sees it advance. The case left
over, a foreground program on a boot that refused its calibration, has no working clock at all.
Documenting that would at least make it findable. (Filed with agnos too: a refused calibration
should not be final.)

## Consumer-side workaround

daimon 2.4.1: `daimon_now_ms()` in `src/syscalls.cyr` reads `#95`. Once `#95` answers -1, it reads
`#40` for the rest of the run. Every deadline in daimon goes through it, and daimon's guest programs
use the same fallback.
