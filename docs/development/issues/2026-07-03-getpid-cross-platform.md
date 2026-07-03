# `getpid()` / `getppid()` return wrong values on Windows + macOS (cross-platform gap)

**Filed:** 2026-07-03 (surfaced by the v6.3.43 VR-01 platform-variant tcyr —
`tests/tcyr/vr01_process_smoke.tcyr` — running on real cass + ecb hardware).
**Severity:** P3 — a correctness gap in a rarely-used stdlib path; no consumer
blocked today. Documented + smoke-covered; the value-correctness fix is tracked here.

## Symptom

`lib/process.cyr`'s `getpid()` / `getppid()` (`= sys_getpid()` / `sys_getppid()`)
return an incorrect value on two of the three cross-OS targets:

- **Windows (cass):** `getpid()` / `getppid()` are **documented 0-returning stubs**
  — `lib/process_win.cyr:294` (`fn getpid(): i64 { return 0; }`), because the v6.0.51
  Windows process-creation arc routes process *creation* and left self-PID
  (`GetCurrentProcessId`) out of scope. So both return `0`.
- **macOS (ecb):** `SYS_GETPID = 39` in `lib/syscalls_macos.cyr:44` — but that is the
  **Linux** getpid number. BSD `getpid` is syscall **20**. The macho backend rewrites
  each Linux number to `0x2000000 | n` (`src/backend/x86/emit.cyr`), so `getpid` on
  macOS issues `0x2000027` — a *different* BSD syscall — and returns garbage / an
  error, not the process's PID. (`getppid` is BSD 39 = `0x2000027`; the Linux number
  for getppid is 110, so it's mistranslated the same way.)
- **Linux:** correct (getpid=39, getppid=110 are the real Linux numbers).

## Fix

- **macOS:** add a `getpid` (Linux 39 → BSD 20) and `getppid` (Linux 110 → BSD 39)
  entry to the macho syscall-number translation table (the `0x2000000|BSD` rewrite in
  `src/backend/x86/emit.cyr` — a codegen change, needs fixpoint + seed + cross-OS
  re-validation), OR define macOS-specific `sys_getpid`/`sys_getppid` in
  `lib/syscalls_macos.cyr` that issue the correct BSD number directly.
- **Windows:** wire `getpid` → `GetCurrentProcessId` via a new PE syscall reroute
  (0xF0xx) in `src/backend/pe/emit.cyr` + `lib/process_win.cyr` (the parent PID has no
  cheap Win32 equivalent — `CreateToolhelp32Snapshot` walk — so `getppid` can stay a
  documented stub or return `-1`).

## Coverage today

`tests/tcyr/vr01_process_smoke.tcyr` asserts only the portable truth — the identity
path is **callable without faulting** and `getpid` is **stable** across calls — and
guards the positive-PID value assertion to Linux (`#ifndef CYRIUS_TARGET_WIN` +
`#ifndef CYRIUS_TARGET_MACOS`). When this is fixed, tighten that fixture to assert a
positive PID on the fixed platform(s).
