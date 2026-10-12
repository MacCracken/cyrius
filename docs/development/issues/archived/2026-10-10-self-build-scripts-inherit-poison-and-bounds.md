# Eleven scripts build the compiler from `src/` without scrubbing an inherited `CYRIUS_POISON` / `CYRIUS_BOUNDS` — `install.sh` among them — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 10; CHANGELOG [6.7.9]) The eleven listed scripts and a twelfth,
> `scripts/cyriusly`, now run `unset CYRIUS_BOUNDS CYRIUS_POISON` before they build. cyriusly is a shell script with
> no `.sh` suffix; its `setup` arm builds the tools and `cycc_aarch64` from the checkout, and `install.sh
> --refresh-only` installs those builds as they are. The derivation that produced the table missed it. Gate row E4 of
> `tests/gates/frontend/bounds_mode_checked.sh` is DERIVED now and checks both variables. Its set is every shell
> script under `scripts/` and `bootstrap/` (a `.sh`, or a `#!` shell file) whose code names a `src/main*.cyr`
> fork, with a floor of 12; today it finds 15. `cyrius-watch.sh` (a project watcher) and `hooks/pre-commit` (a
> restore hint) are named out. `bootstrap.sh` and `check.sh` name no fork and are checked by name. Row E4b runs
> `CYRIUS_BOUNDS=1 CYRIUS_POISON=1 sh scripts/build-cycc-verify.sh`, which is green; it was rc 3 before the fix,
> because the inherited pair changes cycc(src): 2,092,928 B against 2,053,536 B. Before the fix the E4 block was RED
> on 13 rows. Eleven mutations of the fix and of the gate each turned it RED (the gate's ledger). The CLI's own
> self-builds (`cyrius pulsar`, the on-demand cx compiler / cxvm builds) have the same leak and are filed:
> [2026-10-11-cbt-self-builds-inherit-poison-and-bounds.md](2026-10-11-cbt-self-builds-inherit-poison-and-bounds.md).

**Status:** ✅ **RESOLVED** (v6.7.9, the quick lane's bite 10). Was 🟡 OPEN,
verified 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f, `cycc_merged` 2,053,536 B) with the repro script (read-only; its probes go to a mktemp directory): eleven scripts under `scripts/`
build from `src/main*.cyr` and unset neither variable, and from the same tree `CYRIUS_POISON=1 build/cycc <
src/main.cyr` gives a 2,088,776 B compiler and `CYRIUS_BOUNDS=1` a 2,053,576 B one, each different from `build/cycc`
(a clean build equals it). The five scripts the 6.7.8 C2 lane covered (check.sh, release-gate.sh,
seed-derive-cycc.sh, version-bump.sh, bootstrap/bootstrap.sh) scrub both, and gate row E4 of
`tests/gates/frontend/bounds_mode_checked.sh` pins exactly those five.
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-8b (reported only, `~/.cache/c6/c2/changelog_handoff.md` §
C2-8b); the twelfth candidate, `scripts/build-cycc-verify.sh`, was found re-deriving the list for this filing.
**Severity:** High — a wrong artifact without a diagnostic: run by hand from a shell that exports either variable (a
fuzz session's `CYRIUS_POISON=1`, a bounds-checked test run's `CYRIUS_BOUNDS=1`), `scripts/install.sh` writes a
poisoned or bounds-checked compiler into the install store, the tarball scripts ship one, and the bench / differential
/ cross-OS scripts measure one.
**Affects:** the tree since each variable existed (`CYRIUS_POISON` 6.5.29, `CYRIUS_BOUNDS` 6.7.8); the merged 6.7.8
tip measured.

## Summary

The compiler reads `CYRIUS_POISON` and (6.7.8) `CYRIUS_BOUNDS` from its environment. A script that rebuilds the compiler
itself from `src/` must not let either reach that build, or the compiler it produces is the poisoned / bounds-checked
variant. 6.7.8's C2-8b made the five gate and release scripts unset both before their first build. These do not:

| Script | First `src/` build line |
|---|---|
| `scripts/install.sh` (writes `~/.cyrius/versions/<v>`) | 605 |
| `scripts/cross-os-selfhost.sh` | 161 |
| `scripts/bench-history.sh` | 176 |
| `scripts/differential.sh` | 90 |
| `scripts/build-macos-arm64-tarball.sh` | 32 |
| `scripts/build-macos-x86-tarball.sh` | 41 |
| `scripts/build-windows-tarball.sh` | 31 |
| `scripts/verify-store.sh` | 225 |
| `scripts/mac-selfhost.sh` | 19 |
| `scripts/funcgate-posix.sh` | 63 |
| `scripts/build-cycc-verify.sh` | 39 |

(`scripts/cyrius-watch.sh` also names `src/main.cyr`, as the default entry of a user PROJECT it watches — not a
self-build, so it is not listed.) Each is covered only when called from release-gate.sh, version-bump.sh or check.sh's
staging, which have already scrubbed the environment.

## Reproduction

`docs/development/issues/repros/2026-10-10-self-build-scripts-inherit-poison-and-bounds.sh` — run from the repo root,
`sh <repro>`; it lists every `scripts/*.sh` that builds from `src/` with no scrub, then builds `src/main.cyr` plain,
with `CYRIUS_POISON=1` and with `CYRIUS_BOUNDS=1` into a mktemp directory and compares each to `build/cycc`:

```
no CYRIUS_POISON / CYRIUS_BOUNDS scrub: scripts/bench-history.sh (first src/ build at line 176)
  ... (eleven lines, the table above)
plain build == build/cycc
CYRIUS_POISON=1 build differs from build/cycc (2088776 B)
CYRIUS_BOUNDS=1 build differs from build/cycc (2053576 B)
```

## Root cause

Each listed script invokes `build/cycc < src/main*.cyr` (or `cat src/main.cyr | ./build/cycc`) with the caller's
environment. The compiler reads both variables at startup (`_read_env("CYRIUS_POISON")` in each fork's env block —
see [the CYRIUS_POISON=0 issue](2026-10-10-poison-env-zero-or-empty-turns-mode-on.md) — and `_bnd_env_rung`,
`src/frontend/lex_pp.cyr:5475`).

## Proposed fix

Add `unset CYRIUS_BOUNDS CYRIUS_POISON` before the first build in each listed script (one line each, as the five do),
and extend gate row E4 of `bounds_mode_checked.sh` from its fixed five-script list to every `scripts/*.sh` that builds
from `src/main*.cyr` (derived, with `cyrius-watch.sh` named as the one exclusion), checking both variables — so a new
self-build script cannot miss the scrub.
