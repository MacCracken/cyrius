# The x86_64 release tarball ships without `cyrius-repl.sh` (release.yml looks only in `scripts/`, not `scripts/shims/`) — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 12; CHANGELOG [6.7.9]) release.yml's "Package x86_64 tarball" step
> looks in `scripts/shims/` first, then `scripts/`, as install.sh does, and fails naming any `[release] scripts` entry
> found in neither. Reproduced first: the step run from the tree exited 0 with a tarball whose `bin/` had
> `cyrius-watch.sh` and `cyrius-prompt-info` and no `cyrius-repl.sh`. `ci_installs_the_release_tarball.sh` axis 8
> checks that every listed script is in the tarball's `bin/`, byte-identical to its source and executable, and that
> the installed `cyrius repl` evaluates `return 6 * 7;` to `= 42`. It also runs a fixture checkout: a name in both
> places ships the `shims/` copy, and a name in neither place fails the step. The 6.7.8 step turns all four rows RED.

**Status:** ✅ **RESOLVED** in v6.7.9 (the quick lane's bite 12). Filed OPEN 2026-10-08, verified by reading `.github/workflows/release.yml:132-134` at 2fb6ad8b: the loop copied `scripts/$script` only, and `cyrius-repl.sh` lives in `scripts/shims/`; install.sh looks in `shims/` first (`scripts/install.sh:739-742`, `:1169-1172`).
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — never 7.x.
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
