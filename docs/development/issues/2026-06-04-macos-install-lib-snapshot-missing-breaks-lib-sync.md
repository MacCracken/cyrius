# macOS install leaves `versions/<v>/lib` missing → `cyrius lib sync` fails

- **Filed**: 2026-06-04
- **Reporter**: yantra (downstream consumer; GitHub Actions `macos-15-arm64` runner)
- **Affects**: at least 6.0.59 and **6.0.61** (the 6.0.61 bump did not fix it)
- **Platform**: macOS arm64 (`macos-15-arm64`, Image `20260527.0100`). **Linux is unaffected.**

## Symptom

On a clean macOS install via the canonical piped installer, `cyrius lib sync`
fails immediately:

```
error: snapshot lib not found at /Users/runner/.cyrius/versions/6.0.61/lib
  run: cyrius install 6.0.61
```

This blocks any consumer that vendors `lib/` via `cyrius lib sync` (e.g. yantra,
whose CI gitignores `lib/` and materializes it from the toolchain snapshot) on
every macOS job.

## What the installer reported (same run)

The piped `scripts/install.sh` ran to completion and printed success, including
the stdlib step:

```
> downloading Cyrius 6.0.61...
> checksum verified
> codesigned macOS binaries (ad-hoc)
> binaries installed
> standard library installed        <-- line 421, AFTER the lib cp
> cyrius-init templates installed
> linking directories...
> PATH added to .bashrc
Cyrius 6.0.61 installed successfully!
```

## Why this is contradictory

`scripts/install.sh` runs under `set -e` (line 17). The download-path stdlib
copy is:

```sh
if [ -d "$EXTRACTED/lib" ]; then
    cp -r "$EXTRACTED/lib" "$CYRIUS_HOME/versions/$VERSION/"   # ~line 420
    info "standard library installed"
fi
```

Under `set -e`, a failing `cp` would abort the script — but the run reached
`installed successfully!`, so the `cp` returned 0. Nothing afterward removes
`versions/<v>/lib` (the "linking directories" step only `rm -rf`s the top-level
`~/.cyrius/{bin,lib}` symlinks, not the versioned dir). So either:

1. the macOS `cp -r "$EXTRACTED/lib" "versions/<v>/"` returns 0 **without**
   producing a populated `versions/<v>/lib` (a BSD-vs-GNU `cp` behavior gap), or
2. `cyrius lib sync` resolves the snapshot path differently on Darwin than the
   path the installer wrote to (symlink/`realpath` resolution, `current`-file
   parsing, etc.).

The release tarball is **not** the problem: `cyrius-6.0.61-aarch64-macos.tar.gz`
contains `cyrius-6.0.61-aarch64-macos/lib/` with 96 `.cyr` files, identical to
the Linux tarball.

## Repro

- macOS arm64 runner, fresh `~/.cyrius`:
  ```sh
  curl -sSf https://raw.githubusercontent.com/MacCracken/cyrius/6.0.61/scripts/install.sh \
    | CYRIUS_VERSION=6.0.61 sh
  cyrius lib sync     # -> error: snapshot lib not found at .../versions/6.0.61/lib
  ```
- The same two commands on x86_64-linux **succeed** (`versions/6.0.61/lib` is
  created with 89 top-level `.cyr`; `cyrius lib sync` copies them). Verified.

## Suggested fixes

- In `scripts/install.sh`, after the stdlib copy, **assert** the result and fail
  loudly if empty — don't let `info "standard library installed"` print when the
  snapshot isn't actually there:
  ```sh
  cp -R "$EXTRACTED/lib" "$CYRIUS_HOME/versions/$VERSION/"   # -R, not -r, on BSD
  [ -n "$(ls -A "$CYRIUS_HOME/versions/$VERSION/lib" 2>/dev/null)" ] \
    || err "stdlib snapshot empty after copy — packaging/cp bug"
  ```
- Audit `cyrius lib sync`'s snapshot-path resolution on Darwin (symlink/realpath,
  `current` parsing) against the path the installer writes.

## Downstream workaround (in place)

yantra's `setup-cyrius` composite action backfills `versions/<v>/lib` straight
from the release tarball when the installer leaves it missing (no-op on Linux).
That unblocks macOS CI today; it should be removed once this is fixed.

## Resolution (cyrius-side — v6.0.62)

Fixed in `scripts/install.sh`'s download/tarball path. Root cause confirmed: the
stdlib copy used the **whole-dir** form `cp -r "$EXTRACTED/lib" "versions/<v>/"`,
which returns 0 on the `macos-15-arm64` runner yet does not produce a populated
`versions/<v>/lib` — while the **bin** copy (which worked) used the contents form
`"$EXTRACTED/bin"/*`. Not reproducible on ecb (a runner-image `cp` quirk on macOS
15.7.7), but the downstream backfill — `mkdir -p $LIBDIR; cp -R .../lib/. $LIBDIR/`
— proved the contents-into-premade-dir pattern works on that exact runner.

The fix moves that proven pattern upstream:
```sh
rm -rf "$CYRIUS_HOME/versions/$VERSION/lib"
mkdir -p "$CYRIUS_HOME/versions/$VERSION/lib"
cp -R "$EXTRACTED/lib/." "$CYRIUS_HOME/versions/$VERSION/lib/"
[ -n "$(ls -A ".../lib")" ] || err "stdlib snapshot empty after copy — packaging/cp bug"
```
plus an `else err` if the tarball has no `lib/` at all, and the same contents
pattern for the `cyrius-init-templates` copy (same latent whole-dir bug). The
fail-loud assert means a packaging regression can never again print "standard
library installed" + succeed while leaving the snapshot missing (the macOS-rot
lesson). **Verified regression-safe on ecb** (real macOS arm64): fixed installer
lands `versions/6.0.61/lib` (90 files) + templates.

**Status: FIXED cyrius-side, pending runner verification.** install.sh is fetched
from the release TAG, so the fix is only live once a tag ships with it. yantra
confirms on its `macos-15-arm64` CI after bumping the pin to **6.0.62**, then
removes the `setup-cyrius` backfill step. Do NOT archive this issue until that
confirmation lands.
