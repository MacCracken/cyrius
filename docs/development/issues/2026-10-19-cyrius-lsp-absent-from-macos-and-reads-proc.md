# `cyrius-lsp` does not reach macOS: neither macOS tarball builds it, and the server reads its environment and its own path from `/proc`, which macOS has no — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 checking the `cyrius-lsp` Claude Code plugin (cyrius-plugins 0.2.0) on the
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
