# The aarch64-linux release tarball ships none of the `[release] scripts` — RESOLVED

> ✅ **RESOLVED in v6.7.14** (PL-9, `d42a13466` + `f80c9fa68` (the user's decision D59, 2026-10-16: "Ship every [release] bin, built for aarch64"; the scripts half extends 6.7.12's D4). release.yml's aarch64 step stages the three [release] scripts through `scripts/release-scripts.sh` before its first compile. The x86_64 step now calls the same helper, so all four POSIX builders read the list one way. The step also builds every `[release] bins` entry with the native aarch64 compiler and arch-checks each. cybs, the seed-assembled x86_64 bootstrap compiler, has no aarch64 form and is the one entry not built. `programs/cyrld.cyr` opens its output through `sys_open`: the raw `SYS_OPEN` does not exist on aarch64, and the x86_64 output is byte-identical. The filed static check now finds the helper call. The step, run locally, built a tarball whose bin/ holds 19 files (6.7.13's held 4): the 16 bins and the 3 scripts. A pi install smoke ran 26 of 27 rows (`cyrius build` / `test` / `repl`, cyrius-watch.sh, cyrfmt, cyrlint, cyrius-lsp, …). The 27th, ts_test_runner, fails because the aarch64 compiler has no TS front end (filed, 6.7.15). Rows: new `tests/gates/toolchain/release_tarballs_ship_release_scripts.sh` (static: each of the four builders calls the helper once, before its first compile; mutants a – d RED). New `tests/gates/toolchain/aarch64_tarball_ships_release_bins.sh` (runs the step: exactly the 16 bins, each an AArch64 ELF, plus the 3 scripts; a missing source fails by name; the packaged tools run under qemu; mutants a – f RED). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN**. Read 2026-10-15 from the 6.7.12 darwin lane's tree (l6712-darwin @ f60df9df). Filed from
unit D3. That unit made both macOS tarballs ship every `cyrius.cyml` `[release] scripts` entry, through the new
`scripts/release-scripts.sh` (issues/archived/2026-10-11-macos-tarballs-omit-cyrius-watch-decision.md, the user's decision
D4, 2026-10-15: ship every [release] script). The same check over the other POSIX tarball builders shows one that
still ships none.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (platform lane, wave 1, unit P3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D59 — Ship every [release] bin, built for aarch64.
**Severity:** Low. An aarch64 Linux binary install has no `cyrius-repl.sh`, `cyrius-watch.sh` or
`cyrius-prompt-info`. `cyrius repl` resolves `~/.cyrius/bin/cyrius-repl.sh` (scripts/shims/README.md, *Lookup
order*), so a binary-installed aarch64 Linux box has no `cyrius repl`.
**Affects:** `.github/workflows/release.yml`, the `build-aarch64` job's *Package aarch64 tarball* step.

## Reproduction (static: the step runs only in the release workflow)

`cyrius.cyml`:

```
scripts = ["cyrius-repl.sh", "cyrius-watch.sh", "cyrius-prompt-info"]
```

| Builder | What it ships from `[release] scripts` |
|---|---|
| `release.yml` *Package x86_64 tarball* | all three, by its `for script in $SCRIPTS` loop (shims/ first, fails on a miss: 6.7.9) |
| `scripts/build-macos-x86-tarball.sh` | all three, through `sh scripts/release-scripts.sh "$WORK/$STAGE/bin"` (6.7.12) |
| `scripts/build-macos-arm64-tarball.sh` | all three, the same way (6.7.12) |
| `release.yml` *Package aarch64 tarball* | **none**: it copies `cycc`, `cyrsign`, `cyrius`, `cyrius-init` and `scripts/cyriusly` into `bin/`, then `chmod +x "$STAGE/bin"/*` |

```sh
sed -n '/name: Package aarch64 tarball/,/tar czf/p' .github/workflows/release.yml | grep -nE 'SCRIPTS|release-scripts|cyrius-repl|cyrius-watch|prompt-info'
# (no output)
```

install.sh installs whatever the tarball's `bin/` holds (`for _eb in "$EXTRACTED/bin"/*`), so nothing adds the three
at install time.

## Root cause

The aarch64 step was written as a hand list (cycc, cyrsign, cyrius, cyrius-init, cyriusly) and never read the
manifest's `scripts` array. The x86_64 step reads it, and since 6.7.12 both macOS builders do too.

## Fix direction (for whoever places it)

Add `sh scripts/release-scripts.sh "$STAGE/bin"` to the step (run from the checkout root, as the macOS builders do).
It parses `[release] scripts`, looks in scripts/shims/ then scripts/, and fails the step on an entry it cannot find.
The x86_64 step's inline loop could call the same helper, leaving one copy of the parse.
`tests/gates/toolchain/macos_tarball_ships_release_scripts.sh` axis 1 is the model for a static row over release.yml.
Whether the aarch64 tarball should match the x86_64 one is the user's packaging call. It also lacks cyrfmt / cyrlint
/ cyrdoc and the other bins the x86_64 tarball ships.
