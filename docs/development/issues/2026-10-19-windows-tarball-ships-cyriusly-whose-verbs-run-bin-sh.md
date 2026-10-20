# The Windows tarball ships cyriusly.exe since 6.7.16, and its `install` / `update` / `setup` / `cmdtools` run /bin/sh, curl and a POSIX path test: on Windows `install` fails silently (rc -1), `update` prints a cmd.exe error, `cmdtools` refuses every Windows CYRIUS_HOME; programs/cyriusly.cyr still says "Nothing ships a Windows cyriusly" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the review of the 6.7.16 tools lane (unit T4, 07b9a4130:
scripts/release-bins.sh builds every `[release] bins` entry for the Windows tarball, cyriusly included; it shipped no
cyriusly before). Measured by the lane's review-fix step on cass (C:\cyrius-tests, a `.bat` reading %errorlevel%) and
under wine (a private prefix), with cyriusly.exe built from the l6716-tools tree as the tarball builds it
(`CYRIUS_TARGET_WIN=1 cycc < programs/cyriusly.cyr`; T4's runs covered only `--help` / `--version`).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 tools review, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; t16 lane, wave 3, unit TT3) — never 7.x.
**Decision (user, 2026-10-20, the found issues' round):** D84 — Ship it; those verbs refuse by name.
**Severity:** Low — a shipped binary whose shell-backed verbs cannot work on its platform: `install` prints
"Installing Cyrius <v>..." and stops with rc -1 and no reason, so a user reads it as a network or install failure.
`use`, `version`, `list`, `uninstall`, `--help`, `--version` are native and run.
**Kind:** tooling (programs/cyriusly.cyr's Windows arms; scripts/release-bins.sh's Windows list — the user's call which).

## Reproduction

```sh
CYRIUS_TARGET_WIN=1 ./build/cycc < programs/cyriusly.cyr > cyriusly.exe     # what release-bins.sh windows builds
```

On cass, from a `.bat` in C:\cyrius-tests\<dir> with `set CYRIUS_HOME=C:\cyrius-tests\<dir>\ch`:

```text
cyriusly.exe install 6.7.15     ->  stdout "Installing Cyrius 6.7.15..."   stderr (nothing)            rc=-1
cyriusly.exe update             ->  stdout "Checking for updates..."       stderr "The system cannot find the path specified."   rc=255
cyriusly.exe cmdtools list      ->  stderr "cyriusly: cmdtools: the install home is not an absolute path: 'C:\cyrius-tests\<dir>\ch'
                                            set CYRIUS_HOME to an absolute path; cyriusly never resolves the shell twin from the current directory"   rc=1
```

(Under wine, `install` instead reaches the HOST's /bin/sh through wine's Unix-path mapping and fails inside the
installer script — `[: missing ']'`, rc 255 — which no Windows machine does.)

## Root cause

- `_cmd_install` (programs/cyriusly.cyr ~760) and `_cmd_cmdtools` push `/bin/sh` into `_cy_run_argv`, which on PE is
  `exec_vec` (CreateProcessW): there is no `/bin/sh`, the spawn fails, and the verb returns -1 with nothing said.
- `_cmd_update` hands a bash line (`LATEST=$(curl … | grep … | sed …)`) to `exec_cmd`, which on Windows is
  `cmd.exe /s /c` (lib/process_win.cyr): cmd cannot run it.
- `_cy_twin_path` takes a home as absolute only when it starts with `/`, so every Windows CYRIUS_HOME (`C:\…`) is
  refused.
- The comment above `_cy_run_argv` (~635) reads "Nothing ships a Windows cyriusly — the verbs it runs are /bin/sh, curl
  and rm — but the file keeps compiling": true until 07b9a4130, whose release-bins.sh excludes only cybs, cycc, cyrius
  and (on Windows) cyrius-lsp.

## Fix direction (the user's call)

Either release-bins.sh names `cyriusly` as a Windows exclusion with that reason (cli_args_never_dropped.sh axis 15b's
REL_EXEMPT list gains it; the Windows install keeps no version manager, as before 6.7.16), or cyriusly's shell-backed
verbs get Windows arms that refuse by name ("cyriusly install is POSIX-only on Windows: …"), `_cy_twin_path` reads a
drive-rooted path as absolute or refuses cmdtools on Windows by name, and the comment is corrected. Row: the Windows
cyriusly's `install` / `update` / `cmdtools` on wine and on the cass leg end with a named refusal and a non-zero rc,
never a silent -1.
