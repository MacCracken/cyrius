# agnos-portability sweep residuals (v6.2.39) — sakshi clock, defensive landmine gates, winsize-needs-gate-fix

**Filed:** 2026-06-23 (cyrius-side, during the v6.2.39 agnos-wrapper batch review).
**Severity:** mixed — one MEDIUM reachable degradation (sakshi), several LOW latent
landmines (not agnos-reachable), one deferred speculative add (winsize).
**Component:** stdlib agnos portability (`CYRIUS_ARCH_X86`-predefined-on-agnos trap +
unguarded raw `syscall(NN)` in host-only modules).

## Context

v6.2.39 fixed the **reachable, fail-OPEN** class (result/bounds/overflow `syscall(60)`
aborts no-op'd on agnos) and added net_config #61 + signal constants. A cross-lib
sweep surfaced these RESIDUALS, deferred out of .39 (cross-repo folds + non-reachable
latent sites + a gate-design conflict):

## 1. sakshi clock calibration on agnos — MEDIUM (reachable, degraded-not-crash) — FOLD

`lib/sakshi.cyr:214` (`_sk_clock_now_ns_raw`, `syscall(228)` clock_gettime) and `:250`
(`_sk_clock_init`, `syscall(35)` Linux nanosleep) sit under `#ifdef CYRIUS_ARCH_X86`
with **no agnos exclusion** — and `CYRIUS_ARCH_X86` is predefined on agnos (the
documented sakshi-class trap the file's own header warns about). Reachable on agnos via
`sakshi_span_enter → _sk_now_ns → _sk_clock_init` (consumers: yantra/yukti/log). On
agnos #228 is undefined (→ -1) and #35 = agnos `sysinfo` (wrong) → TSC calibrates
against garbage → bogus freq (no crash). **Fix:** add a `#ifdef CYRIUS_TARGET_AGNOS`
branch FIRST in both fns (mirror `chrono.cyr`: `sys_uptime_ms()*1e6` anchor,
`sys_sleep_ms(10)` window), exclude the ARCH_X86 syscall(228)/(35) body under
`#ifndef CYRIUS_TARGET_AGNOS`. **sakshi is a FOLD → fix in `~/Repos/sakshi` src, bump,
re-fold** (do NOT hand-edit `lib/sakshi.cyr`).

## 2. Latent landmines — LOW (NOT agnos-reachable; defensive `#ifndef AGNOS` gates)

Raw Linux `syscall(NN)` with no agnos guard, but no realistic agnos consumer reaches
them (agnos is static-only / these are host dynamic-linking / desktop modules):
- **`lib/mmap.cyr`** (`syscall(9/10/11)` mmap/mprotect/munmap → mis-dispatch to
  mkdir/rmdir/mount on agnos). Host/desktop heap path; canonical agnos heap is
  `alloc_agnos.cyr` (#27). [native cyrius]
- **`lib/dynlib.cyr`** (ELF .so loader — `syscall(2/3/0/5/9/158)`). Agnos is static-only,
  no dynamic linking. [native cyrius]
- **`lib/fdlopen.cyr`** (setuid foreign-glibc dlopen — `syscall(2/0/3/4/5/6/9/10)` not
  under its existing `#ifdef CYRIUS_TARGET_LINUX` guards). Linux-host-only. [native cyrius]
- **`lib/yantra.cyr`** (`syscall(54)` setsockopt, `syscall(60)` exit) — CDP browser
  automation, desktop-only. [FOLD → upstream + refold]

**Fix:** gate each module's public surface behind `#ifndef CYRIUS_TARGET_AGNOS`
(fail-closed on agnos) so an accidental agnos include can't mis-dispatch. Defense-in-depth,
not urgent — no agnos program reaches these today.

## (resolved in .39) winsize #60

winsize #60 **shipped in v6.2.39** (`SYS_WINSIZE=60` + `sys_winsize`) — consumed by
agnsh / darshana tty sizing / kii / the desktop. The `_agnos_emit_gate` collision (#60
== the Linux exit number) was fixed by making the emit gate's probe peer-independent
(`programs/agnos_emit_probe.cyr` no longer includes the syscall peer), so the compiler's
EEXIT is the sole `mov eax,60` source and the scan stays precise while agnos uses #60.
No longer a residual.
