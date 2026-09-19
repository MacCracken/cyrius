# `cyrius lint` cannot pass `--strict-deferrals` to cyrlint: usage error or silently ignored — FIXED

**Status:** ✅ **FIXED in 6.6.5 (bite 8)** — and the fix is much wider than this filing.
The whole CLI shared the defect; see "Corrections to this filing" at the bottom.
**Placement:** shipped — `CHANGELOG.md` [Unreleased]/6.6.5.
**Discovered:** 2026-09-16, mabda 4.1.3 verification sweep (untracked-deferral audit)
**Severity:** Low. There is a working form (`cyrlint` directly). But one of the two wrapper
spellings **silently disables the gate** and exits 0, which a CI step reads as a pass.
**Affects:** cyrius 6.6.4 CLI (cbt/cyrius.cyr, cbt/commands.cyr); unchanged at HEAD 4f3731e8. Component: cli (`cyrius lint` dispatcher, `cbt/cyrius.cyr` + `cbt/commands.cyr`)

## Summary

`cyrlint` supports `--strict-deferrals`: exit 2 when a file has untracked deferral markers.
It accepts the flag before or after the path (`programs/cyrlint.cyr`, `main()` argument
loop). The `cyrius lint` wrapper knows only `--strict`:

- `cbt/cyrius.cyr:1104-1124` (the `lint` dispatcher) takes the **first argument that isn't
  `--strict` as the file** and ignores every later argument except `--strict`.
- `cbt/commands.cyr:1547` `cmd_lint(file, strict)` forwards only `--strict` and the file
  to cyrlint.

So:

| Command | What cyrlint receives | Result |
| --- | --- | --- |
| `cyrius lint --strict-deferrals f.cyr` | `cyrlint --strict-deferrals` (the file is dropped) | cyrlint usage text, **exit 1** on every file |
| `cyrius lint f.cyr --strict-deferrals` | `cyrlint f.cyr` (the flag is dropped) | deferrals reported, **exit 0**: the gate is off |
| `cyrlint --strict-deferrals f.cyr` | as typed | **exit 2** (correct) |
| `cyrlint f.cyr --strict-deferrals` | as typed | **exit 2** (correct) |

The flag-first failure is loud. The flag-last form is the dangerous one. It prints the
same `deferral line N: untracked ...` notes as a plain lint, and nothing in the output says
the flag was ignored.

This is the same argument-parser family as cheat-sheet entry A3 (`cyrius fmt --check
<file>` treats the flag as the file).

## Reproduction

Verified 2026-09-16 on cyrius 6.6.4. Run it with `bash` in any empty directory:

```sh
L=$HOME/.cyrius/versions/6.6.4/bin/cyrlint
printf '# a deferred item with no tracking pointer\nfn f(): i64 { return 0; }\n' > d.cyr
cyrius lint --strict-deferrals d.cyr; echo "exit=$?"   # Usage: cyrlint ...  exit=1
cyrius lint d.cyr --strict-deferrals; echo "exit=$?"   # 1 untracked deferrals  exit=0
cyrius lint d.cyr; echo "exit=$?"                      # 1 untracked deferrals  exit=0
$L --strict-deferrals d.cyr; echo "exit=$?"            # 1 untracked deferrals  exit=2
$L d.cyr --strict-deferrals; echo "exit=$?"            # 1 untracked deferrals  exit=2
```

## Expected vs actual

- **Expected:** `cyrius lint <file> --strict-deferrals` and `cyrius lint --strict-deferrals
  <file>` both forward the flag and exit 2 on an untracked deferral, the same as `cyrlint`.
  An unrecognized flag is an error, never a file name and never silently dropped.
- **Actual:** see the table above.

## Impact on mabda

mabda's CI `Lint` step runs `cyrius lint "$f"` and fails only on `warn ` lines. Deferral
notes never fail it, and the wrapper offers no way to make them fail. Three untracked
deferrals (`programs/native_texture_alloc_e2e.cyr`, `programs/nvidia_kms_scanout.cyr`,
`tests/tcyr/compiler_backend.tcyr`) shipped in every release from 4.1.0 to 4.1.2. The
oldest had been in the tree since 2026-06-20. They were only found by running
`cyrlint --strict-deferrals` by hand during the 4.1.3 sweep.

## Consumer-side workaround

Call `cyrlint` directly, per file:

```sh
for f in src/*.cyr programs/*.cyr tests/tcyr/*.tcyr tests/bcyr/*.bcyr fuzz/*.fcyr; do
  cyrlint --strict-deferrals "$f" || exit 1
done
```

Use the versioned binary (`$HOME/.cyrius/versions/<pin>/bin/cyrlint`) when the pin may
differ from the active toolchain. `~/.cyrius/bin/cyrlint` is whatever version is current.

## Proposed fix

Forward `--strict-deferrals` (and `--exit-with-count`) through the `lint` dispatcher and
`cmd_lint`. Reject any other `-`-prefixed argument with a usage error instead of treating it
as the file. A gate should assert the exit code of all four spellings above.

## Filing

Filed 2026-09-16 from mabda 4.1.3. mabda keeps its own record at
`mabda/docs/development/issues/2026-09-16-cyrius-lint-drops-strict-deferrals.md`.

## Corrections to this filing

Everything measured in this report reproduced exactly on 6.6.4 — all five rows of the
repro, both tables, and the mabda impact. Four things in it are wrong or too narrow, and
they are recorded here rather than edited away, because each one shaped how the fix was
scoped.

1. **"Severity: Low. There is a working form."** — The severity was right for `lint` and
   wrong for the family. The same argument handling is live in every verb, and several of
   its spellings are SILENT AND MUTATING: `cyrius fmt f --chekc` REWRITES the file and
   exits 0; `clean --dryrun` and `cyrius -q clean --dry-run` DELETE `build/`; `lib sync
   --dry` really syncs 110 files over `./lib`; `deps --dry-run` and `deps --verfy` really
   resolve; `build s --strict` writes the binary to a file named `--strict`. "There is a
   working form" is true of all of them and is not a mitigation when the broken form
   reports success.

2. **"Component: cli (`cyrius lint` dispatcher)."** — Refuted. The same shape was measured
   in `fmt`, `doc`, `vet`, `deny`, `check`, `build`, `run`, `test`, `tests`, `bench`,
   `fuzz`, `capacity`, `coverage`, `doctest`, `header`, `api-surface`, `deps`, `clean`,
   `lib sync`, `soak` and `version`, AND in the delegated tools (`cyrlint`, `cyrfmt`,
   `cyrdoc`, `cyaudit`, `cyrius_api_surface`, plus `ark`, `cyrsign`, `cyrld`), AND in
   `lib/flags.cyr` — the stdlib parser whose own header says it exists to replace these
   ad-hoc loops. Fixing only the `lint` dispatcher would have left ~58 of ~60 spellings
   live.

3. **"Proposed fix: forward `--strict-deferrals` (and `--exit-with-count`)."** — Corrected.
   Forwarding `--exit-with-count` as it stood would have forwarded a fail-open: it returns
   the raw warning count as the process exit status, and an exit status is 8 bits, so 256
   warnings exited **0**. `cyrdoc --check` had the identical wrap (256 undocumented → 0,
   257 → 1). Both are clamped to 255 in the tools, and the gate uses a 300-warning fixture
   with the expected value parsed off STDOUT.

4. **"This is the same argument-parser family as cheat-sheet entry A3 (`cyrius fmt --check
   <file>` treats the flag as the file)."** — A3 itself has been fixed since v6.5.28;
   `cyrius fmt --check a.cyr` exits 1 with the file untouched. mabda's cheat sheet
   (`mabda/docs/development/2026-04-30-toolchain-issues.md:92`) is stale on that row. The
   FAMILY was still live in `fmt`, just through different spellings.

Also refuted while checking the surrounding docs: `docs/guides/cyrius-guide.md` (6.6.4 line 1136, the Linter section) said a
bare `cyrius lint` lints all of the stdlib (it printed usage and exited 1), line 2724
documented `cyrius build --pie` (the build loop had no `--pie` arm, so it errored — the
flag is real as of 6.6.5), and vidya's `language/tooling.cyml` advertised `cyrius doc
--serve [port]` and `cyrius lint --check`. All four are corrected in this release.
⚠ *Corrected in review round 3:* this paragraph first said neither of those two "has ever
existed". `cyrius lint --check` never did, but **`cyrius doc --serve [port]` did** — the
pre-v5.x bash dispatcher shipped it (commit `85742876`, 2026-04-09: HTML docs served via
Python's `http.server`) and it went away when that dispatcher was replaced (around
`c5466a84` / `2e51a929`). It has never existed in the native CLI. And "all four corrected"
was not yet true either: `tooling.cyml` still listed `cyrlint --check` in its audit list
until round 3.

And one thing the filing got exactly right and should be repeated: **the flag-last form is
the dangerous one**, because it prints the same notes as a plain lint and nothing in the
output says the flag was ignored. That is the property the new gate is built around — axis
4 puts the defect in the LAST file precisely so a fix that only handles operand 0 cannot
pass.

## Round-2 review of the fix (same bite)

The first cut of the fix was reviewed before it shipped, and the review found the family one
level further out — recorded here because two of the findings are the filed shape itself:

- `cyriusly` (a shipped `[release].bins` entry) had the flag-last drop verbatim:
  `cyriusly use 6.6.4 --globl` dropped the typo and took the LOCAL-pin path at exit 0, and
  `cyriusly install --dry-run` really started an install of a version named `--dry-run`.
- The fix's own multi-file `cyrlint` tail exited **0** on `good.cyr missing.cyr
  --exit-with-count` (it returned the count and discarded the read error), and `cyrius lint`
  took the MAX over per-file runs where `cyrlint` takes the SUM.
- The new Windows spawn was unreachable on the shipped layout: tools were looked up without
  the `.exe` suffix the tarball ships, and two tools were missing from the tarball entirely.
- `cyrius run p.cyx a b c` handed its arguments to cxvm, which ignores them — now refused.

All fixed in 6.6.5 together with the rest; the gate grew from 310 to 478 assertions and every
new row was mutation-run. Details: `CHANGELOG.md` 6.6.5, the bite-8 bullet.

## Round-3 review of the fix (same bite)

A second review found the filed flag switched off one more way, and the Windows half still
not working on the shipped layout:

- **`--exit-with-count` switched `--strict-deferrals` off.** cyrlint returned the count
  before the strict checks, so `cyrius lint d.cyr --strict-deferrals --exit-with-count`
  exited **0** on this filing's own repro — newly reachable, because the wrapper could not
  forward both flags before. The exit code is now max(count, strict verdict).
- **Windows `cyrius lint` failed closed with cycc.exe present** (the round-2 claim had been
  measured without it): the syntax pre-pass's private temp dir was a literal `/tmp` plus a raw
  `syscall(39)`, unrouted on PE (-38 every time). And `cyrius run/test/tests/bench/fuzz`
  never ran the program on Windows at all (`run_binary_timed` was still fork/waitpid).
  Both fixed; a wine leg in the gate and a cass leg in `scripts/cross-os-selfhost.sh` now
  run `cyrius.exe lint` both ways and `cyrius.exe run argc a b c`.
- The rest of the family: a repeated value flag kept the last value (`--features a --features
  b` resolved `b` only), `cyrius-init`/`ts_test_runner`/`cyrld` let the last operand win,
  `cyrsign-efi` wrote its output to a file named `--dry-run`, `cyaudit deny` wrapped at 256,
  `coverage --min -1` switched the gate off, `deps --dry-run` passed with no manifest, and the
  macOS tarballs shipped neither `cyaudit` nor `cyrius_api_surface`. All fixed; the gate is at
  579 assertions, its fixtures are hermetic (HOME as well as CYRIUS_HOME), and axis 2 now
  greps for the unknown-option error rather than the bare token — which is how several rows
  had been passing on 6.6.4 itself. Details: `CHANGELOG.md` 6.6.5, the bite-8 bullet.
