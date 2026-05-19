# scripts/shims/

CLI implementation detail — **not** user-facing scripts.

The files in this directory are invoked by the `cyrius` CLI dispatcher (`cbt/cyrius.cyr` → `cbt/project.cyr` / `cbt/quality.cyr`), not run directly by users. They exist as bash because the corresponding cyrius-side port hasn't completed yet.

| Shim                  | CLI verb       | Status                                                                       |
|-----------------------|----------------|------------------------------------------------------------------------------|
| `cyrius-init.sh`      | `cyrius init`  | Partial port (v5.9.28): `programs/cyrius-init.cyr` handles `--bin`; bash fallback handles `--lib` / in-place / flag-matrix until the port completes |
| `cyrius-port.sh`      | `cyrius port`  | No cyrius port started; bash is sole implementation                          |
| `cyrius-repl.sh`      | `cyrius repl`  | No cyrius port started; bash is sole implementation                          |

The user-facing scripts that have **no** cyrius CLI wrapper stay flat in `scripts/`:

- `bench-history.sh`, `build-cc5-verify.sh`, `check.sh` (already a thin shim to `build/cyrius_check`), `ci.sh`, `cyrius`, `cyrius-prompt-info`, `cyrius-watch.sh`, `cyriusly`, `install.sh`, `mac-diagnose.sh`, `mac-selfhost.sh`, `release-lib.sh`, `version-bump.sh`, `lib/audit-walk.sh`.

## Retirement

Each shim retires when its cyrius-side port reaches feature parity with the bash. The CLI dispatcher tries the cyrius binary first (signaling deferred-feature fall-through via exit code 2), then falls back to the shim. When a shim has no fall-through path remaining, the file gets `git rm`'d and the corresponding `cmd_*` fn's fallback branch drops.

## Lookup order

The CLI dispatcher resolves shims in this order (per `cbt/project.cyr` + `cbt/quality.cyr`):

1. `./scripts/shims/<name>.sh` — in-repo dev path (this directory).
2. `~/.cyrius/bin/<name>.sh` — installed toolchain path (flat at install time).

The flat installed path is preserved for back-compat with consumers that grep `$CYRIUS_HOME/bin/` for shim scripts. `scripts/install.sh` looks in both `scripts/shims/` and `scripts/` when populating the install snapshot.

## History

Moved to `scripts/shims/` at v5.11.69 as part of the v5.x closeout doc / structure pass. Pre-.69 the three lived flat in `scripts/` alongside genuinely-user-facing scripts, which mis-signaled them as user-facing rather than CLI implementation detail.
