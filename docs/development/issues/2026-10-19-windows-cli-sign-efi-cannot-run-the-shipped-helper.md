# The Windows CLI's `cyrius sign-efi` says "cyrsign-efi helper not found (Linux-only …)" while the Windows tarball ships `cyrsign-efi.exe` beside it, and the message's build hint names a source that does not exist — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 tools lane (unit T4). Since T4 the macOS and Windows tarballs
ship every `[release] bins` entry (issues/2026-10-19-cyrius-lsp-absent-from-macos-and-reads-proc.md), cyrsign-efi among
them. Measured on the Windows tarball scripts/build-windows-tarball.sh builds from the l6716-tools tree, under wine
(a private prefix); `cyrsign-efi.exe --help` itself runs there and on cass (usage, rc 0).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 tools lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; t16 lane, wave 3, unit TT3) — never 7.x.
**Severity:** Low — a CLI verb that cannot reach a binary the install ships; the helper runs when called directly.
**Kind:** tooling (cbt/cyrius.cyr).

## Reproduction

```sh
sh scripts/build-windows-tarball.sh dist && tar xzf dist/cyrius-*-x86_64-windows.tar.gz
wine cyrius-*-x86_64-windows/bin/cyrius.exe sign-efi --help      # cyrsign-efi.exe is in the same bin/
```

```text
error: sign-efi: cyrsign-efi helper not found (Linux-only; build it with `cyrius build programs/cyrsign_efi.cyr build/cyrsign-efi`)
```

The same verb from the arm64 macOS tarball on ecb runs the helper: `Usage: cyrsign-efi <pe-in> <key.der> <cert.der> <pe-out>`.

## Root cause

cbt/cyrius.cyr's `sign-efi` arm (~757-781) hands the helper to `sys_execve`, which is a `-1` stub on PE
(lib/syscalls_windows.cyr), so on Windows it always falls through to the error, whatever is installed. The CLI's other
tool spawns reached Windows through CreateProcessW in 6.6.5 / 6.6.6 (tests/gates/platform/cbt_fork_sites_have_pe_arm.sh);
this exec site has no PE arm. The error text was written when the helper existed only on Linux: it says "Linux-only",
which macOS (since 6.7.16) contradicts, and its hint names `programs/cyrsign_efi.cyr` — the source is
`programs/cyrsign-efi.cyr`.

## Fix direction

A PE arm for the `sign-efi` exec (spawn the helper and answer its exit code, as `run_tool_vec` does on PE), and the
message corrected: no "Linux-only", the real source name. Row: the Windows CLI under wine (and the cass leg) runs
`sign-efi --help` through the shipped helper.
