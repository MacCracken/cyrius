# `clock_now_ns()` uses the one AGNOS clock that is frozen in ring-3 foreground programs — the same repo documents the trap

**Status:** 🟡 **OPEN** — `lib/chrono.cyr` still binds the AGNOS monotonic clock to `uptime_ms`#40.
**Placement:** unpinned — 6.6.x-line backlog. Small, self-contained.
**Discovered:** 2026-09-07 during the sakshi 2.5.0 P(-1) hardening audit
**Severity:** High
**Affects:** cycc 6.2.6 (where the AGNOS binding was introduced) through 6.6.0

## Summary

`clock_now_ns()` — the stdlib's general-purpose monotonic clock — reads
`sys_uptime_ms()` (#40) on AGNOS. That is the one monotonic source that does not
work for the programs most likely to call it.

A **foreground `run` program executes with IF cleared** (only `/bin/agnsh` gets
`IF=1`), so the 100 Hz timer ISR never fires, `timer_ticks` never advances, and
`#40` is **frozen for the program's entire run**. Anything timing itself with it
measures exactly zero, forever, with no error.

This is not a new discovery — **cyrius already documents it**, two files away
from the code that walks into it:

`lib/syscalls_x86_64_agnos.cyr:1202-1207`

> `uptime_us()` — MICROSECOND monotonic clock, read via rdtsc so it works with
> INTERRUPTS DISABLED. This is not a nicer `uptime_ms`: a FOREGROUND `run`
> program executes with IF cleared, so the 100 Hz timer never fires and
> `sys_uptime_ms` (#40, which reads timer_ticks) is FROZEN for that program's
> entire run — anything timing itself with #40 on that path measures zero.
> rdtsc needs no interrupts, so **#95 is the only correct clock there.**

`lib/chrono.cyr:21-23`

```cyrius
fn clock_now_ns(): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    return sys_uptime_ms() * 1000000;
    #endif
```

So the wrapper documents the trap and the general-purpose clock takes it. AGNOS's
own ABI note (`agnos/docs/development/agnos-userland-abi.md`, row 95) records that
this cost **two iron burns on the 3D arc's rung-10 gate** before it was understood.

The `chrono.cyr` comment above the function explains the v6.2.6 reasoning — that
`228=clock_gettime` is out of AGNOS's range and "#40 always was the agnos path".
That was correct when written; `#95` did not exist yet. It does now.

## Reproduction

Any ring-3 foreground program on AGNOS:

```cyrius
include "lib/chrono.cyr"

fn main(): i64 {
    var t0 = clock_now_ns();
    # ... any amount of work, or sleep_ms(500) ...
    var t1 = clock_now_ns();
    return t1 - t0;          # always 0 when launched as a foreground `run`
}
```

Expected: a positive elapsed nanosecond count.
Actual: `0`, every time, because both reads return the same frozen `timer_ticks`.

Launched from `/bin/agnsh` (which has `IF=1`) it works, which is what makes this
hard to catch — it reproduces only on the foreground path.

## Root cause

`lib/chrono.cyr:22` — `return sys_uptime_ms() * 1000000;` inside the
`CYRIUS_TARGET_AGNOS` branch of `clock_now_ns()`.

Not speculation: both the AGNOS kernel ABI and cyrius's own syscall wrapper
document the frozen-`#40` behaviour explicitly, and `sys_uptime_us()` (#95) is
already defined and documented in `lib/syscalls_x86_64_agnos.cyr:1220`.

## Proposed fix

Prefer `#95`, fall back to `#40`, and check the documented negative sentinel:

```cyrius
fn clock_now_ns(): i64 {
    #ifdef CYRIUS_TARGET_AGNOS
    var us = sys_uptime_us();
    if (us >= 0) { return us * 1000; }
    var ms = sys_uptime_ms();
    if (ms < 0) { return 0; }
    return ms * 1000000;
    #endif
```

`#95` returns **-1** (never a plausible-looking `0`) when calibration was
refused, which is exactly what makes the fallback safe to distinguish. It is also
microsecond- rather than 10 ms-granular, so this improves resolution 10,000× on
the path where it already worked.

⚠ `#95` collides with Linux `umask(mask)` and the wrapper is nullary, so
off-AGNOS it would read garbage from `rdi` as a mask and **succeed**, returning
the old umask as a plausible timestamp while changing the process's file-creation
mask. The `#ifdef CYRIUS_TARGET_AGNOS` gate is the only barrier — keep the call
inside it. (`lib/syscalls_x86_64_agnos.cyr:1213-1219` carries this warning.)

## Consumer-side workaround

**sakshi 2.5.1** ships exactly the fix above in its own
`_sk_clock_now_ns_raw` (`src/clock.cyr`), so every AGNOS consumer of sakshi's
tracing/span timing is covered without waiting for this. sakshi had the identical
defect — its comment even said it "mirrors chrono.cyr's agnos clock", which is
how this was found.

Verified on the sakshi side that `95` const-folds to a `mov eax,95` immediate in
the `--agnos` build (3 sites) and appears **zero** times in the x86_64 Linux
build, confirming the ifdef gate holds.

## Also worth a look

`lib/sakshi.cyr:206` is a vendored snapshot of sakshi carrying the same
`syscall(40) * 1000000`. It resolves by re-vendoring sakshi ≥ 2.5.1 rather than
by an edit here.
