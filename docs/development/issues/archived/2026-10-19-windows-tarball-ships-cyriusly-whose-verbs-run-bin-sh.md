# The Windows tarball ships cyriusly.exe since 6.7.16, and its `install` / `update` / `setup` / `cmdtools` run /bin/sh, curl and a POSIX path test: on Windows `install` fails silently (rc -1), `update` prints a cmd.exe error, `cmdtools` refuses every Windows CYRIUS_HOME; programs/cyriusly.cyr still says "Nothing ships a Windows cyriusly" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (TT-12, `d0a305989`, and the TT-12r review fix `9468d291c` — the user's decision D84, 2026-10-20: ship it; those verbs refuse by name. The Windows `cyriusly.exe` refuses `install`, `update`, `setup`, `uninstall`, `cmdtools` and `use --global` (with or without a version) by name, rc 1, before any output or change: `cyriusly: <verb> is not available on Windows: <why>`, then what to do instead — the `install.ps1 -Tarball cyrius-<v>-x86_64-windows.tar.gz` command (`uninstall`: `rmdir /s /q "<home>\versions\<v>"`). The filed repro on cass: `install 6.7.15` → rc 1 and the refusal, nothing on stdout (was "Installing Cyrius 6.7.15...", rc -1); `update` → rc 1 named (was rc 255, a cmd.exe error); `cmdtools list` → rc 1 named (was the not-absolute-home refusal); `uninstall` and `use --global` refused with the store untouched and no `bin.cyrtmp` link left. `list`, `version`, `use <v>` (the project pin), `--help` and `--version` work; every hint they print names install.ps1 and never a refused verb (TT-12r: `use <v>` outside a project, the active-version uninstall guard). `_cy_twin_path` is unreachable on Windows (cmdtools refused first — the filing's second alternative); the `_cy_run_argv` comment is corrected. Found beside it and fixed: TT-13 (`2b2802110`, `_relink_atomic` removes its temporary link as a link on Windows — `_cy_remove_link`; review fix TT-13r `c57646aa5`, the cass probe proves a link can be made first), TT-14 (`a61a55558`, the home is `%USERPROFILE%\.cyrius` with no `CYRIUS_HOME`, `which` prints `<home>\bin\cycc.exe`), and — met while fixing TT-12r — TT-16 (`34992aa76`, the POSIX hints say `cyriusly use <v> --global`) and TT-17 (`a890c6fed`, `update` honours `CYRIUS_HOME`). ⚠ Beyond D84's text: the kept verbs' hints changed, and the operand-shape check, the active-version guard and the not-installed answer still come before the refusal (`uninstall <v>` of a version not installed answers "not installed", rc 0). Rows: the new `tests/gates/platform/win_cyriusly_posix_verbs_refused.sh` (axis S, derived; R1 – R6c, G1 – G3, K1 – K9 under wine; axis L), `cyriusly_version_operand_refused.sh` axis 10 (10a – 10d), the cass leg of `scripts/cross-os-selfhost.sh` (`cyriusly on cass`, `relink on cass`). Mutations: the pre-fix cyriusly.cyr → RED 28 rows; TT-12's → RED 5 (R6c ×3, G2, K9); the cass snippet against the pre-fix binary → `SELFHOST_FAIL` (the leaked `*.cyrtmp*`). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the review of the 6.7.16 tools lane (unit T4, 07b9a4130:
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
