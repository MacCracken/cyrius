# `cyrius-lsp` does not reach macOS: neither macOS tarball builds it, and the server reads its environment and its own path from `/proc`, which macOS has no — RESOLVED

> ✅ **RESOLVED in v6.7.16** (TL-11, `07b9a4130`, with the review fix TL-11r, `bd794af7a` — no decision needed for the server; the tarball half applies 6.7.14's D59 ("Ship every [release] bin, built for aarch64") to the macOS and Windows builders, as the fix direction says — ⚠ beyond D59's text, which named the aarch64 tarball; the Windows cyriusly.exe it began shipping was decided by D84, the user 2026-10-20, in the t16 lane. cyrius-lsp reads HOME and CYRIUS_HOME through getenv, its children's environment from the new lib/io.cyr `env_block(lenp)`, and on macOS its own path through argv(0) + fcntl(F_GETPATH). The macOS and Windows tarballs build every `[release] bins` entry through scripts/release-bins.sh, arch-checked from the bytes (named exclusions: cybs; cyrius-lsp on Windows, which cycc_win refuses), so both macOS tarballs ship bin/cyrius-lsp and bin/cyriusly there is the compiled version manager — whose exec_cmd children ran with an EMPTY environment on macOS until TL-11r built exec_cmd's envp from env_block. Acceptance met on ecb and ach: under `env -i PATH=/usr/bin:/bin` the server built by the host's own cycc finds cycc (by HOME, and with no HOME by its own path) and publishes the error, where the 6.7.15 server logged `cycc not found — diagnostics disabled`. Rows: cli_args_never_dropped.sh axis 15b (the three builders run, every entry read from each tarball; mutants MW1 – MW3 RED); cross-os-selfhost.sh L1 – L3 and C1 on ecb and ach; crossos/env_block_matches_getenv.tcyr; crossos/exec_cmd_forwards_environment.tcyr E1 – E3 (its Windows rows came later, t16's `32d34d66a`). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 checking the `cyrius-lsp` Claude Code plugin (cyrius-plugins 0.2.0) on the
verification hosts: ecb (macOS arm64) has the plugin but no server (`~/.cyrius/bin/cyrius-lsp` absent; its install is
6.6.15, and no macOS release ships one), so the plugin's launcher exits 127 there.
**Placement:** 6.7.16 — Break 2, repair 6 (tools lane, wave 1, unit T4; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Medium — a `[release] bins` tool missing from two of the five platforms, and a Linux-only assumption in
a shipped tool; no boundary is crossed.
**Kind:** tooling (programs/cyrius-lsp.cyr, scripts/build-macos-*-tarball.sh).

## What is wrong (measured 2026-10-19)

1. **The macOS tarballs never build the server.** `scripts/build-macos-arm64-tarball.sh:64` and
   `scripts/build-macos-x86-tarball.sh:63` build a HAND list — `cyrfmt cyrlint cyrdoc cyrius-init cyrsign cxvm cyaudit
   cyrius_api_surface` — not `cyrius.cyml`'s `[release] bins` (`… cyrius-lsp, cyriusly, ts_test_runner, cyrsign-efi, ark,
   cyrld …`). The aarch64 Linux job reads the manifest's list since 6.7.14 (the user's D59: "the manifest's [release]
   bins list is the source of truth for every tarball"); the macOS (and Windows) scripts were not moved to it. So a macOS
   binary install has no `cyrius-lsp` (nor the other bins the hand list omits).
2. **The server is Linux-only at run time.** `programs/cyrius-lsp.cyr` reads its environment from
   `/proc/self/environ` (lines 733, 790, 828, 873, 947 — `HOME`, `PATH`, `CYRIUS_HOME` for compiler discovery, and the
   child environment `_build_envp_from_proc`) and its own path from `/proc/self/exe` (707). On macOS (no `/proc`) every
   read fails: no `HOME`, so `find_cycc()` finds nothing, and diagnostics are off.

## Fix direction

- The macOS (and Windows) tarball scripts take the manifest's `[release] bins` as the aarch64 job does (each entry built
  for the target and arch-checked; an entry with no source fails the step), or name each exclusion with its reason.
- `cyrius-lsp` reads its environment through the stdlib (the process's own `envp` / `getenv` in lib/args.cyr), not
  `/proc/self/environ`; its own executable through the per-OS way the stdlib already uses (`cyrius-init` resolves its
  own path with `F_GETPATH` on macOS), `/proc/self/exe` only on Linux.

## Acceptance

- A macOS arm64 and x86_64 release tarball contains `bin/cyrius-lsp` (the `cli_args_never_dropped.sh` axis that checks
  every tarball script's tool list extended to the manifest list).
- On ecb and ach the installed server answers `initialize`, finds `cycc` and returns diagnostics for a file with an
  error (a crossos-style row driving JSON-RPC, as the Linux LSP gates do), with `PATH` lacking `~/.cyrius/bin`.
