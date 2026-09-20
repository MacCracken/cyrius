# `cyrius-init` does not build for Windows, so `cyrius init` / `cyrius port` do not exist on a Windows install — FIXED

**Status:** ✅ **FIXED in 6.6.6 (bite 6)** — pre-existing (identical at 6.6.4); found while fixing 6.6.5 bite 8.
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

## Resolution (6.6.6, bite 6)

Reproduced verbatim on HEAD before the fix (`rc=1`, 0-byte output, the two named
`undefined function` warnings). Closed in three pieces:

1. **A new PE reroute, `0xF03A` → `kernel32!GetModuleFileNameW(NULL, wbuf, cch)`**
   (`src/backend/x86/emit.cyr` `EGETMODFILENAME_PE`, registered in
   `src/backend/pe/emit.cyr`, dispatched from `_PE_ROUTE_MODULEPATH` in
   `src/frontend/parse_expr.cyr`, stubbed in the aarch64 and cx emitters). Like the
   `GetCommandLineW` route it hands back the raw UTF-16 and the narrowing happens in
   cyrius (`_args_w2u8`), so no new hand-assembly loop. cycc 1,310,864 → 1,310,936 B.
2. **Two wrappers in `lib/syscalls_windows.cyr`** — `sys_rename` (REAL: the already
   live `0xF034`/MoveFileExW) and `sys_self_exe_w` (the new route).
   `programs/cyrius-init.cyr`'s `_self_path` grew a Windows arm that uses the second of
   these and normalises `\` → `/` once, so every `/`-scanning path helper below it keeps
   working unchanged. ⚠ A third wrapper — `sys_readlink` returning `-38`/ENOSYS — was in
   the first cut and was **removed in review**: see the last correction below.
3. **Packaging** — `scripts/build-windows-tarball.sh` ships `cyrius-init.exe` **and**
   `programs/cyrius-init-templates`, and `scripts/install.ps1` copies `programs\` into
   both `versions\<v>\` and the active home (it copied only `bin\` and `lib\`, so the
   templates would never have reached a Windows install — the binary would have shipped
   and run and then reported `missing template` for every file it should write). The
   `EXE_EXEMPT_cyrius_init` exemption in `cli_args_never_dropped.sh` axis 15 is deleted.

**Verified on cass (real Windows 10.0.26200), not wine:** `cyrius-init.exe --dry-run demo`
and a real `cyrius-init.exe demo` both `rc=0` from a **relative** `..\bin\cyrius-init.exe`
in a foreign working directory, 0 `missing template` lines, 0 `scaffold INCOMPLETE`, the
rendered `cyrius.cyml` carrying no `{PROJ}` and valid UTF-8; `--__mode=port` `rc=0` with
`rust-old/Cargo.toml` moved across and the `.gitignore` appended.

Gated by `tests/gates/toolchain/cyrius_init_builds_for_pe.sh` (mutation ledger in its
header) — axis 2 derives its tool list from the tarball script, so "it is in the packaging
list" can never again be mistaken for "it builds".

## Corrections to this filing

- **"or an `argv(0)` fallback the function already has for the failure case" was not a
  viable option.** On Windows `argv[0]` is whatever the parent wrote on the command line
  — it can be relative, or a bare name resolved through PATH — and `_resolve_templates_dir`
  needs that path's GRANDPARENT. Measured: with the reroute stubbed out and the fallback
  taken, invoking the exe as `..\bin\cyrius-init.exe` from a different directory exits 1
  with no file written. It compiles and passes a `--dry-run`, which is why the gate runs
  the binary from a relative path rather than trusting the build.
- **The acceptance list was one item short.** It named the tarball's templates but not
  `install.ps1`, which copies only `bin\` and `lib\`; without the third piece the
  templates reach the tarball and stop there.
- **The line numbers drifted** — `sys_rename` was at `:1054`, not `:1007`, by the time
  this was fixed.
- **The first cut of the fix defined `sys_readlink` for PE; review removed it.** The
  filing's Cause section frames the readlink arm as needing "its own arm", which it does —
  but the arm is `sys_self_exe_w`, not a readlink stub. Measured: with the scaffolder's
  call behind `#ifndef CYRIUS_TARGET_WIN`, deleting the `-38` stub leaves the PE build
  byte-identical (rc=0, `MZ`, 155,648 B, 0 undefined fns). All it changed was the
  diagnostic — and the shape it would have silenced is this filing's own:
  `readlink("/proc/self/exe")` compiles for PE with a stub present and then degrades to
  `argv(0)`, which is the half-fix the gate's axes 3-4 exist to catch. `lib/io.cyr`'s
  `xreadlink` is the portable façade for callers that want a degrade. Axis 5 now pins the
  absence.
