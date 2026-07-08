# Windows PE syscall surface has no TerminateProcess — a spawned child cannot be killed

> **RESOLVED v6.4.26** (2026-07-08). Added `syscall(0xF01D, hProcess, uExitCode) →
> kernel32!TerminateProcess` (`ETERMINATE_PE`, the shared 2-arg aligned reroute) + the
> kernel32 import + parse dispatch (argc==3) + cross-fork stubs (aarch64/cx). `lib/process_win.cyr`
> gains `_win_terminate(hProcess, exitCode)` and `_win_wait_timeout(pi, ms, killed_out)`
> (WAIT_TIMEOUT → terminate + reap, returns 137, sets *killed_out). Verified on cass
> (`vr01_win_terminate.tcyr` — spawn 6 s child, 300 ms wait → kill → PASS) + wine; cass/pi/ecb
> `SELFHOST_OK`. thoth can now implement `exec_shell_capture`'s Windows timeout-kill.

**Filed:** 2026-07-08 (thoth 0.20.2 — Windows shell-tool timed capture; the timeout-kill has no primitive).
**Severity:** P2 — blocks a downstream safety feature with no workaround: a spawned Windows process that
exceeds a deadline cannot be terminated, so a hung/timed-out child leaks. Keeps thoth's shell tool
unadvertised on Windows.
**Component:** cyrius Windows PE syscall reroutes (`src/backend/x86/emit.cyr` — the kernel32 `0xF0xx`
dispatch) + `lib/process_win.cyr` (the consumer surface).

## Problem

`lib/process_win.cyr` + the PE reroute table expose the process-spawn/observe primitives —
`CreateProcessW` (0xF005), `WaitForSingleObject` (0xF001, accepts a finite timeout), `GetExitCodeProcess`
(0xF002), `CreatePipe` (0xF004), `SetHandleInformation` (0xF003) — but there is **no `TerminateProcess`**.
The full exposed set today is `0xF001-0xF005` (process) + `0xF006` cmdline + `0xF007-0xF00A` threading +
`0xF00B-0xF00E` TLS + `0xF00F` sleep + `0xF010-0xF011` argv + `0xF012` DXGI + `0xF013-0xF015` module/env +
`0xF016-0xF019` FindFile + `0xF01A` PRNG + `0xF01B` time + `0xF01C` GetCurrentProcessId — none of which can
kill a process.

So a downstream can spawn a child, `WaitForSingleObject(handle, timeout_ms)`, detect `WAIT_TIMEOUT`
(`0x102`), and read its exit code — but has no way to force-terminate a child that ran past the deadline.
thoth 0.20.2 needs exactly this: `exec_shell_capture` runs a shell command under a wall-clock timeout and, on
expiry, must kill the child (the Windows analogue of the POSIX `SIGKILL` / process-group kill in
`src/exec.cyr`). Without a terminate primitive the Windows path can only *detect* the timeout, not enforce
it — a timed-out command leaks, a resource-safety regression — so the shell tool stays unadvertised on
Windows (`shell_supported()` returns 0 there).

## Fix (additive PE reroute)

Add a `TerminateProcess(hProcess, uExitCode)` reroute — a new number in the process range (e.g. `0xF01D`) in
the PE dispatch (`src/backend/x86/emit.cyr`), and a thin verb in `lib/process_win.cyr` (e.g.
`_win_terminate(hProcess)` → `syscall(0xF01D, hProcess, exitcode)`; optionally a `wait_pid_timeout(handle,
ms)` verb that wraps `WaitForSingleObject` + the `WAIT_TIMEOUT` check + `TerminateProcess` + close). Mirrors
the existing `_win_wait_close` shape (`lib/process_win.cyr:169`). `WaitForSingleObject` already accepts a
finite timeout, so only the terminate primitive is missing.

## Acceptance

A cyrius `--win` program can: spawn via `CreateProcessW`, `WaitForSingleObject` with a finite timeout,
observe `WAIT_TIMEOUT` on a long-running child, `TerminateProcess` it, and confirm the child is gone —
verified on a Windows host (e.g. `cass`, Windows 11 x86_64). `lib/process_win.cyr` exposes a terminate/
timed-wait verb. Then thoth 0.20.2 implements `exec_shell_capture`'s Windows timeout-kill and advertises the
shell tool on Windows. (thoth has already proven the minimal-`--win`-build → scp → run-on-cass test pipeline
works, so verification is ready the moment this lands.)
