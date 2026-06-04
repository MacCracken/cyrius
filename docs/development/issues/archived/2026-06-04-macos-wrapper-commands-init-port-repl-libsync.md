# 2026-06-04 — macOS: `cyrius init` / `port` / `repl` / `lib sync` broken on a fresh install

> **RESOLVED across v6.0.58 + v6.0.60 (arm64, verified on ecb).**
> - `port` / `repl` (.58): the macOS tarballs now bundle the cyrius-init binary + the
>   cyrius-{init,port,repl}.sh shims — "script not found" gone.
> - `init` (.60): finished the dev-mode-only v5.9.29 install template path — cyrius-init resolves its
>   real binary path on macOS via open(argv0)+fcntl(F_GETPATH), the macOS tarballs bundle
>   `programs/cyrius-init-templates/`, install.sh lands them at `versions/<v>/programs/`. `cyrius init
>   <name>` scaffolds a full project via the BINARY (verified on ecb). Advanced flags still cascade to
>   the bash shim, unchanged.
> - `lib sync` (.60): it's the getdirentries gap — fixed by the dir-listing port
>   (2026-06-02-macos-getdirentries-dir-listing-port.md, also .60).
> The remaining x86-macho tools/wrapper argv item is tracked in
> 2026-06-02-macos-x86-release-no-compiler.md (held — Apple Intel EOL).

**Filed:** 2026-06-04 (found-by-ports: user installed on ecb (real Apple Silicon)
and hit these immediately after a clean install)
**Affected:** the macOS tarballs (`scripts/build-macos-arm64-tarball.sh` +
`scripts/build-macos-x86-tarball.sh`) and, for x86, the wrapper argv path.
**Severity:** High — these are first-touch scaffolding commands; a new macOS user
hits them on `cyrius init` before anything else. arm64-macOS is the SHIPPED
platform, so this is a live regression there, not just an x86 gap.

## Symptoms (verbatim, ecb — arm64-macOS)
```
❯ cyrius init test
error: script not found: /Users/macro/.cyrius/bin/cyrius-init.sh
❯ cyrius port test
error: script not found: /Users/macro/.cyrius/bin/cyrius-port.sh
```
`~/.cyrius/bin` contained only: cycc cycc_aarch64 cyrius cyrfmt cyrlint cyrdoc
cyriusly cyrius-prompt-info — i.e. NO `cyrius-init` binary and NO
`cyrius-{init,port,repl}.sh` shims. yantra also reported `cyrius lib sync` "not
working properly" on macOS (root cause TBD — see Open below).

## Root cause
`cmd_init`/`cmd_init_args` (cbt/project.cyr) try the `cyrius-init` BINARY
(`./build/cyrius-init` or `<home>/bin/cyrius-init`) first, then fall back to the
`cyrius-init.sh` shim (`<scripts_dir>/shims/` or `<home>/bin/`). `cmd_port`
(cbt/project.cyr) is script-only (`cyrius-port.sh`; no binary source exists).
The Linux installer copies the shims from `scripts/shims/` into the version's
`bin/`, but the macOS tarball builders never bundled the `cyrius-init` binary OR
the shims — so on macOS BOTH the binary and the script are absent → "script not
found". `_scripts_dir` resolves to `<home>/bin` when installed (cbt/core.cyr:315),
which is exactly where the missing files were expected.

## Fix (v6.0.58)
`scripts/build-macos-arm64-tarball.sh` + `scripts/build-macos-x86-tarball.sh`:
- build the `cyrius-init` binary (added to the cross-emit tool loop + the Mach-O
  validation loop) so `cyrius init` uses the sovereign PROGRAM, as it should;
- bundle `scripts/shims/cyrius-{init,port,repl}.sh` into the tarball `bin/` so
  `port`/`repl` work and `init` has its flag-matrix fallback.

## Open / still-failing (x86-macOS, being chased under the layer-6 argv work)
On x86-macOS specifically, even with the binary+shims bundled, the build/cycc-path
tools + wrapper (cyrfmt --check, `cyrius build`, `cyrius init`) still don't fully
work because the x86-macho argv/env capture ("layer 6") isn't yet landing for the
COMPLEX programs that exit via an explicit top-level `syscall(60,...)` before the
auto-call-main. The simple argv probe works (argv(K)=75) but cyrfmt --check
returns 1/1 and `cyrius build`/`init` produce no output. Tracked in detail in
[2026-06-02-macos-x86-release-no-compiler.md]. arm64-macOS uses the x28 prologue
(unaffected) — needs ecb re-verification that init/port/repl now work there with
the tarball fix.

## Verify — ON-HARDWARE results (ecb, arm64, v6.0.58 tarball)
Installed the rebuilt arm64 tarball to a scratch home and ran each command:
- **`cyrius port` → FIXED.** Resolves + prints usage (was "script not found").
  The shim bundling closed it. (repl likewise resolves.)
- **`cyrius init` → "script not found" GONE, but does NOT yet scaffold.** Two
  deeper, macOS-specific defects under it (NEW findings, distinct from the shim
  gap):
  1. **`cyrius-init` binary uses `/proc/self/exe`** (programs/cyrius-init.cyr
     `_resolve_templates_dir`, line ~51 `sys_readlink("/proc/self/exe", ...)`) to
     locate itself → resolve `programs/cyrius-init-templates/`. macOS has no
     `/proc`, so readlink fails → templates not found → `_read_repo_version`
     fails → prints "VERSION lookup failed (cascade pending v5.9.29) — falling
     through to bash". Needs a macOS self-location path (`_NSGetExecutablePath`,
     or argv0, or `$CYRIUS_HOME`).
  2. **The templates dir is not bundled** in the tarball at all (nor placed by
     install.sh — it has zero `cyrius-init-templates` refs), so even with macOS
     self-location the binary would find no templates. The expected installed
     location is `~/.cyrius/share/cyrius-init-templates/` (per the binary's
     comment). The bash shim avoids this (inline templates) but then the bash
     fallback **needs `$CYRIUS/VERSION`** (cyrius-init.sh:196) which the install
     doesn't place → `exit 1`, no project. So init needs EITHER the binary made
     macOS-correct + templates bundled, OR (quicker) the install to place
     `$CYRIUS/VERSION` so the bash fallback completes.
- **`cyrius lib sync` → the getdirentries gap.** `cmd_lib_sync`
  (cbt/commands.cyr:356) calls `dir_list()` to enumerate the snapshot lib dir;
  `dir_list` returns empty on macOS (getdents64 not ported to Darwin
  getdirentries). Tracked by [2026-06-02-macos-getdirentries-dir-listing-port.md]
  — `lib sync` is another consumer of it.

## Remaining work (distinct, ordered)
1. **init scaffolding on macOS**: macOS self-location in cyrius-init (drop
   `/proc/self/exe`) + bundle `programs/cyrius-init-templates/` in the tarballs +
   ensure VERSION is reachable (for the bash fallback). 
2. **lib sync**: ride the getdirentries port (separate issue).
3. **x86-macho argv (layer 6)**: needs a reserved register or a non-gvar-reset
   global — see [2026-06-02-macos-x86-release-no-compiler.md].

DONE in v6.0.58: the "script not found" hole itself (cyrius-init binary + the
cyrius-{init,port,repl}.sh shims now ship in both macOS tarballs; port/repl work).
