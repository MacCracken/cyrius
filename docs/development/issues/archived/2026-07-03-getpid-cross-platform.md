# `getpid()` / `getppid()` return wrong values on Windows + macOS (cross-platform gap)

> **RESOLVED v6.3.44.** The filing under-counted the breakage — running the tightened
> `vr01_process_smoke.tcyr` (positive-PID assertions) on **real ecb (aarch64-macOS)**
> surfaced that **getpid was ALSO broken on aarch64-macho**, not just getppid. The key
> fact the filing missed: the macho syscall xlat is arch-specific in its SOURCE numbers —
> x86-macho feeds the BSD-numbered `syscalls_macos.cyr` (getpid 39, getppid 110), but
> **aarch64-macho feeds `syscalls_aarch64_linux.cyr` (getpid 172, getppid 173)**
> (`lib/syscalls.cyr:69`). So:
> - **macOS getpid**: x86-macho 39→20 worked since v6.0.02, but **aarch64-macho 172 was
>   untranslated** → getpid ran an untranslated svc and returned positive GARBAGE (the old
>   callable-only smoke passed on it). Fixed: aarch64 ESYSXLAT `172→20`.
> - **macOS getppid**: both broken — x86-macho 110 untranslated, aarch64-macho 173
>   untranslated (returned 0). Fixed: x86 `_msx(S,110,0x2000027)` + aarch64 `173→39`
>   (`cmp x8,#173; movz x16,#39`, llvm-mc-verified, disasm-confirmed).
> - **Windows getpid**: a 0-returning stub → `kernel32!GetCurrentProcessId` via a new 0xF01C
>   PE reroute (`_pe_ensure_getcurpid` + `EGETCURPID_PE` + parse_expr dispatch;
>   `lib/process_win.cyr`). **Windows getppid** stays a documented 0-stub (no cheap Win32 eq).
>
> Verified on real hardware: **ecb** `diag → getpid>0 AND getppid>0`, raw `syscall(172)`/`(173)`
> both positive; **cass** Windows getpid via the PE import. `_macho_arm_routes` whitelist +
> `vr01_process_smoke.tcyr` tightened. Fixpoint + seed-derive byte-identical. **LESSON: the
> macho syscall SOURCE numbers differ by arch — a getpid fix that only reasons about the x86
> table misses the aarch64-macho stdlib entirely.** See CHANGELOG [6.3.44].

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
