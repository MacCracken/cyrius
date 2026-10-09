# Every PE build that includes `lib/syscalls.cyr` warns "syscall 12 … is not routed" (Windows `sys_brk`) — OPEN

**Status:** 🟡 **OPEN** — reported 2026-10-08 by the backlog filer for the size / fold items (seen on every PE build it made at 2fb6ad8b); the source is `lib/syscalls_windows.cyr:436`.
**Placement:** 6.7.11 — Break 2, repair 2: the platform release (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 2026-10-08 by a backlog filer (out of its scope); filed 2026-10-08.
**Severity:** Low — a standing false warning on every PE user build trains users to ignore the unrouted-syscall warning, which exists to catch real ones.
**Affects:** cycc ≤ 6.7.6, PE target

## Summary

`lib/syscalls_windows.cyr` keeps a `sys_brk` wrapper on purpose (Windows has no brk; the wrapper fails closed), but
its body issues the raw `syscall(12, …)` that the PE backend has no route for, so the compiler's
"syscall 12 with 1 argument(s) is not routed" warning fires on every PE build that includes `lib/syscalls.cyr` —
whether or not the program calls `sys_brk`.

## Reproduction

Cross-build any program that includes `lib/syscalls.cyr` for PE (`CYRIUS_TARGET_WIN=1`, or `cyrius build --win`) and
read stderr: the warning names syscall 12 at `lib/syscalls_windows.cyr:436`.

## Proposed fix

Make the Windows `sys_brk` return its fail-closed value without emitting the raw syscall (it is a stub — `return 0 - 38;`
or the peer's ENOSYS spelling), so the warning stays meaningful. Check the other Windows stubs for the same shape.
