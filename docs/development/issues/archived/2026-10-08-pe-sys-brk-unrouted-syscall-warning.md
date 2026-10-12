# Every PE build that includes `lib/syscalls.cyr` warns "syscall 12 … is not routed" (Windows `sys_brk`) — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 2; CHANGELOG [6.7.9]) the Windows `sys_brk` returns -38 itself and
> issues no `syscall(SYS_BRK, ..)`, and `lib/mmap.cyr`'s `cyr_mprotect` — the same shape, a raw unrouted `syscall(10, ..)`
> warning on every PE build that included `lib/mmap.cyr` (`lib/freelist.cyr`, `lib/thread.cyr`) — gained a
> `CYRIUS_TARGET_WIN` arm returning -38. Both return the -38 they returned before (wine 11.19, before and after); a PE
> build of `lib/syscalls.cyr` + mmap + freelist + thread now warns at nothing, and so does every shipped PE tool but
> the CLI, whose one left (`cbt/deps.cyr:170`, getcwd) is a REAL unrouted call — item 1 of
> `2026-10-08-cli-path-and-reporting-leftovers.md`. The ELF / Mach-O / agnos / cx outputs are byte-identical. No other
> stub in the Windows peer has the shape (a PE build of each `lib/` module surveyed; the warnings left there are real
> Linux-only calls). Row 6.7.9 of `tests/gates/platform/pe_unrouted_warning_names_site.sh`, mutation-proven.

**Status:** ✅ **RESOLVED in v6.7.9** — see the banner above. (Filed: reported 2026-10-08 by the backlog filer for the size / fold items (seen on every PE build it made at 2fb6ad8b); the source was `lib/syscalls_windows.cyr:436`; reproduced 2026-10-11 at cda7fad9.)
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — shipped.
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
