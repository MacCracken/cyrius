# scripts/folds/

Release helpers for the **folded stdlibs** — the language's own stdlib repos that `lib/` vendors
(the list is [`docs/ecosystem.md`](../../docs/ecosystem.md)). Development tools, not shipped: no
tarball or installer copies this folder. They are Python and shell for now; their conversion to
cyrius is filed as
[`2026-10-19-dev-helper-scripts-converted-to-cyrius.md`](../../docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md).

| File | What it does |
|---|---|
| `sibci.sh` | runs one fold release's full GitHub CI locally, isolated, and prints one summary line |
| `run-ci.py` | the step runner `sibci.sh` calls: a repo's `.github/workflows/*.yml` `run:` steps with GitHub's shell semantics |
| `cymlcheck.py` | TOML-parses each part of a `.cyml` file (a manifest, or vidya's `[[entries]]` files) and counts the errors |

## When it is used

**Every fold release, before it is handed to the user for tagging**: run `sibci.sh` on the fold at
the release commit and read the summary. CLAUDE.md § *Ecosystem & stdlib*: a fold's CI runs
isolated — a clean `git archive` copy, a throwaway `HOME` + `CYRIUS_HOME`, GitHub's shell
semantics — never by hand-extracted steps. Folds only: a consumer's CI is never run from here.

`cymlcheck.py` is used whenever a `.cyml` file is edited by hand — vidya's entry files at each
release close, a fold's or this repo's `cyrius.cyml` — to compare the error count before and after.

## Usage

```sh
scripts/folds/sibci.sh <fold> <commit-or-tag> [workdir]
#   e.g.  scripts/folds/sibci.sh sankoch <release-commit>
#   several at once (one "<fold> <commit>" per line in list):
awk '{print $1, $2}' list | xargs -P4 -n2 scripts/folds/sibci.sh

python3 scripts/folds/run-ci.py <copy> --list          # the steps and shells it would run
python3 scripts/folds/cymlcheck.py <root> [<file>...]  # <file>s relative to <root>
#   e.g.  python3 scripts/folds/cymlcheck.py . cyrius.cyml
#         python3 scripts/folds/cymlcheck.py ../vidya      # every tracked content/**.cyml
```

The summary line is `<fold> @ <commit> (pin <v>): rc=N ok=N fail=N skip=N`; the step log is
`<workdir>/<fold>/ci.log`. `<fold>` is the fold's NAME under `$CYRIUS_FOLDS_ROOT`, never a path:
a path exits 2 before anything is removed, and a bad fold or commit (no pin read from the
archive's `cyrius.cyml`) exits 2 before the store is copied, each with a named message. **Read
`ok=N`, never `rc=0` alone**: a copy with no runnable step still reads `rc=0 ok=0`. Exit 1 means
an argument is missing or the run could not set up its shim or enter the copy; otherwise the exit
status is 0 and the summary line is the verdict.

| Variable | Default | Meaning |
|---|---|---|
| `CYRIUS_FOLDS_ROOT` | `$HOME/Repos` | where the fold checkouts live |
| `CYRIUS_STORE` | `$HOME/.cyrius/versions` | the installed toolchain store; the fold's pin must be a slot in it (exit 2 otherwise) |
| `CYRIUS_SCRATCH` | `${XDG_CACHE_HOME:-$HOME/.cache}/c6` | scratch root: the workdir is `$CYRIUS_SCRATCH/sibci`. A `[workdir]` argument beats it |
| `CI_JOB`, `CI_TIMEOUT` | all jobs, 1500 s | passed through to `run-ci.py`: one job only, the per-step timeout |

## What the isolation is

- **The copy** is `git archive <commit>` — committed files only — with every `path = "../X"` dep
  line in its `cyrius.cyml` commented out (a path dep beats a tag and would read the local
  worktree, not the release).
- **`CYRIUS_HOME`** is a throwaway holding a COPY of the store's slot for the fold's pin and an
  EMPTY `deps/`, so every dep tag is fetched from GitHub; **`HOME`** is a throwaway too, so a CI
  "Install Cyrius toolchain" step can never reach the live `~/.cyrius`.
- **`PATH`** is reset to the slot's `bin/`, a per-run qemu shim and `/usr/local/bin:/usr/bin:/bin`.
  The shim links `qemu-aarch64-static` (the name CI images use) to the caller's `qemu-aarch64`,
  made at run time in a `mktemp -d` under the workdir; with no `qemu-aarch64` it is empty.
- **The steps** run under `run-ci.py`: a step's own `shell:`, else the job's, else the
  workflow's; `bash` is `bash --noprofile --norc -eo pipefail`, unspecified is `bash -e` (no
  pipefail), `sh` is `sh -e`. `uses:` steps, and the steps whose NAME starts with the
  Cyrius-toolchain install (`Install Cyrius`, `Install cyrius`), `Checkout`, `Upload`, `Cache`,
  `Set up` or `Setup `, are skipped (the throwaway `CYRIUS_HOME` stands in for them); every other
  install step runs. Release workflows are skipped unless `--include-release`. A step that fails because `sudo` needs a password is a
  named `SKIP`, never a pass; a `continue-on-error: true` step that fails is a NON-GATING `FAIL`
  line; an undefined `${{ }}` expression renders empty, as on GitHub.
- **Not isolated:** `/tmp`, network ports, background processes and the caller's other
  environment variables (an exported `CYRIUS_BOUNDS` / `CYRIUS_POISON` / `CYRIUS_COVERAGE`
  reaches every step's compile, which GitHub never sees). yantra's browser jobs write fixed
  `/tmp` names (`/tmp/yc-ci`, `/tmp/chromium.log`, `/tmp/chromedriver.log`,
  `/tmp/geckodriver.log`, `/tmp/wkd.log`) and bind ports 9222 / 9515 / 4444; its Android / iOS
  jobs, where Appium installs, write `/tmp/appium.log` and `/tmp/ios-ci.tcyr` and bind 4723.
  Never run two yantra runs at once (the `xargs -P` form included), and remove those names
  afterwards.

## Known local-vs-GitHub differences

A job that needs a browser driver, an emulator or a Mac the dev box does not have fails here and
not on GitHub — read which job a `FAIL` line names before calling it a release defect. yantra's
`e2e-firefox` (geckodriver), `e2e-webkit` (WebKitGTK's WebKitWebDriver), `e2e-android` (Appium +
UiAutomator2) and `e2e-ios` jobs are the standing case; its Chromium jobs run where Chromium and
chromedriver are installed. The browser jobs leave their driver processes running after the step
(the workflow backgrounds them): stop them by PID afterwards.
