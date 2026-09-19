# `cyrius-init` does not build for Windows, so `cyrius init` / `cyrius port` do not exist on a Windows install — OPEN

**Status:** 🟡 **OPEN** — pre-existing (identical at 6.6.4); found while fixing 6.6.5 bite 8.
**Placement:** unpinned — 6.x line (Windows toolchain parity). Not parked to 7.x.
**Discovered:** 2026-09-18, 6.6.5 bite 8 review rounds 2–3, while auditing which delegated
tools the Windows tarball ships (`scripts/build-windows-tarball.sh`).
**Severity:** Medium — two CLI verbs are absent on one shipped target. Not silent: the CLI
reports `tool not found` for `init`/`port` on a Windows install.
**Affects:** `programs/cyrius-init.cyr` cross-built with the PE cross-compiler
(`cat src/main_win.cyr | build/cycc > cc_win; cat programs/cyrius-init.cyr | cc_win`), 6.6.4 and 6.6.5.

## Reproduction

```sh
cat src/main_win.cyr | ./build/cycc > /tmp/cc_win && chmod +x /tmp/cc_win
cat programs/cyrius-init.cyr | /tmp/cc_win > /tmp/ci.exe
# warning: undefined function 'sys_readlink'
# warning: undefined function 'sys_rename'
# error: refusing to emit binary with 2 reachable undefined function(s)
# rc=1, 0-byte output
```

## Cause

`lib/syscalls_windows.cyr` defines neither wrapper, and cyrius-init reaches both unguarded:

- `_self_path` (`programs/cyrius-init.cyr`, "Resolve THIS binary's real path") takes the
  non-macOS arm, `sys_readlink("/proc/self/exe", …)`. Windows needs its own arm — there is no
  `/proc`; the module path is `GetModuleFileNameW`, which is **not** a PE reroute today (a
  compiler change), or an `argv(0)` fallback the function already has for the failure case.
- The `port` driver renames the source tree's files aside with `sys_rename`. PE already routes
  `MoveFileExW` (0xF034), so this half is a stdlib wrapper, not a compiler change.

## Why it was not fixed in bite 8

Bite 8 is the argument-handling release item. This is a Windows-stdlib/port gap (two missing
wrappers, one needing a new PE reroute) plus a packaging decision (the tarball would also need
`programs/cyrius-init-templates`, which the macOS tarballs ship and the Windows one does not).
The argument fix for cyrius-init itself (a second project name used to win silently) did land
in bite 8 and is gated on Linux by `tests/gates/toolchain/cli_args_never_dropped.sh` axis 17.

## Acceptance

- `programs/cyrius-init.cyr` cross-builds for PE with no reachable undefined function;
- `build-windows-tarball.sh` ships `cyrius-init.exe` + the templates, and the `EXE_EXEMPT_cyrius_init`
  exemption in `cli_args_never_dropped.sh` axis 15 is deleted;
- on cass, `cyrius init --dry-run demo` and a real `cyrius init demo` succeed from an installed
  tarball (not a dev tree).
