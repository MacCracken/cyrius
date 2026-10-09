# The x86_64 release tarball ships without `cyrius-repl.sh` (release.yml looks only in `scripts/`, not `scripts/shims/`) — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-08 by reading `.github/workflows/release.yml:132-134` at 2fb6ad8b: the loop copies `scripts/$script` only, and `cyrius-repl.sh` lives in `scripts/shims/`; install.sh looks in `shims/` first (`scripts/install.sh:739-742`, `:1169-1172`).
**Placement:** unpinned — 6.x-line backlog — never 7.x.
**Discovered:** 2026-10-08 by the 6.7.7 install lane (out of its scope); filed 2026-10-08.
**Severity:** Low — `cyrius repl` is missing from tarball installs.
**Affects:** release.yml since the shims move

## Summary

`cyrius.cyml`'s `[release] scripts` lists `cyrius-repl.sh`, `cyrius-watch.sh` and `cyrius-prompt-info`. The x86_64
"Package x86_64 tarball" step copies each from `scripts/$script` and silently skips a missing one, so the shim moved
to `scripts/shims/` never ships.

## Proposed fix

Look in `scripts/shims/` first, as install.sh does, and fail the step when a listed script is found in neither place.
The 6.7.7 gate `ci_installs_the_release_tarball.sh` runs this step's body, so it can assert every listed script lands.
