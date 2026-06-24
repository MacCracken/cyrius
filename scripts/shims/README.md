# scripts/shims/

CLI implementation detail — **not** user-facing scripts.

The files in this directory are invoked by the `cyrius` CLI dispatcher (`cbt/cyrius.cyr` → `cbt/quality.cyr`), not run directly by users. They exist as bash because the corresponding cyrius-side port hasn't completed yet.

| Shim                  | CLI verb       | Status                                                                       |
|-----------------------|----------------|------------------------------------------------------------------------------|
| `cyrius-repl.sh`      | `cyrius repl`  | No cyrius port started; bash is sole implementation                          |

The user-facing scripts that have **no** cyrius CLI wrapper stay flat in `scripts/`:

- `bench-history.sh`, `build-cc5-verify.sh`, `check.sh` (already a thin shim to `build/cyrius_check`), `ci.sh`, `cyrius`, `cyrius-prompt-info`, `cyrius-watch.sh`, `cyriusly`, `install.sh`, `mac-diagnose.sh`, `mac-selfhost.sh`, `release-lib.sh`, `version-bump.sh`, `lib/audit-walk.sh`.

## Retirement

Each shim retires when its cyrius-side port reaches feature parity with the bash. When a shim has no caller remaining, the file gets `git rm`'d and the corresponding `cmd_*` fn drops its dispatch.

**`cyrius-init.sh` + `cyrius-port.sh` RETIRED at v6.2.40.** `cyrius init` and `cyrius port` are now served entirely by the native scaffolder `programs/cyrius-init.cyr` (built as `cyrius-init`, in `cyrius.cyml [release].bins`; port mode via the internal `--__mode=port` sentinel). There is no bash fallback — the half-done v5.9.28 port that punted `--lib` / in-place / the flag-matrix / all of port back to bash is gone. `cyrius-repl.sh` is the lone remaining shim.

## Lookup order

The native scaffolder is resolved as a sibling of `cycc`/the other tools via `_tools_dir` (`./build` in dev, `~/.cyrius/bin` in an install) — see `cbt/project.cyr` `_scaffolder_path`. The remaining `cyrius-repl.sh` shim resolves `./scripts/shims/<name>.sh` then `~/.cyrius/bin/<name>.sh`.

## History

Moved to `scripts/shims/` at v5.11.69 as part of the v5.x closeout doc / structure pass. Pre-.69 the three lived flat in `scripts/` alongside genuinely-user-facing scripts, which mis-signaled them as user-facing rather than CLI implementation detail.
