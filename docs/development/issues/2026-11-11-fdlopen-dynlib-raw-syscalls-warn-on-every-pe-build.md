# `lib/fdlopen.cyr` and `lib/dynlib.cyr` make six raw syscalls with no PE route, so every `--win` build that links sandhi warns — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18, 2026-11-11. The repro exits 1.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-11, by ushma's Rust → Cyrius port (M0 probe 10, `ushma/docs/development/port-parity.md` §3).
**Reporter:** ushma 2.0.0 port (`ushma/docs/development/ushma-port-plan.md` §8)
**Severity:** Low. The ELF loaders can't run on Windows anyway, and the warning says so. But it is a stdlib warning
in every PE build of an HTTP client, so a project with warning-free gates must filter `lib/`. A filter that broad
would also hide a real one.
**Affects:** cyrius 6.7.18 stdlib.

## Summary

`cyrius build --win` of anything that links fdlopen and dynlib (sandhi does) prints six warnings of this form:
"syscall N with K argument(s) is not routed on CYRIUS_TARGET_WIN=1; it returns -38 (-ENOSYS) on Windows. Guard the
call with #ifdef CYRIUS_TARGET_WIN, use the stdlib wrapper, or add a PE reroute."

| Site | Call |
|---|---|
| `lib/fdlopen.cyr:472` | `syscall(4, …)`: stat |
| `lib/fdlopen.cyr:530` | `syscall(5, …)`: fstat |
| `lib/fdlopen.cyr:626` | `syscall(10, …)`: mprotect |
| `lib/fdlopen.cyr:954` | `syscall(6, …)`: lstat |
| `lib/dynlib.cyr:674` | `syscall(5, …)`: fstat |
| `lib/dynlib.cyr:950` | `syscall(158, …)`: arch_prctl |

After DCE, every `[lib.ai]` consumer of ushma's bundle still prints the `dynlib.cyr:674` warning in its PE build.

## Reproduction

`repros/2026-11-11-fdlopen-dynlib-raw-syscalls-warn-on-every-pe-build.sh` builds a three-line program calling
`dynlib_open` with `--win`, lists the six sites and exits 1.

## Proposed fix

The warning's own advice applies. The loaders map ELF objects, which has no meaning on PE, so guard their bodies
with `#ifdef CYRIUS_TARGET_WIN` and return 0 ("not found"), as the callers already handle. Or route the stat calls
through the stdlib's wrappers, which have PE implementations.

## Consumer-side workaround

ushma's `scripts/gates.sh` ignores diagnostics located in `lib/` (`^warning:lib/`).
