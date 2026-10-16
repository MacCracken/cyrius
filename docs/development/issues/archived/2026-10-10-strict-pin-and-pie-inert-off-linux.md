# `--strict-pin` / CYRIUS_STRICT_PIN does nothing off Linux, and cycc.exe ignores CYRIUS_PIE — RESOLVED

> ✅ **RESOLVED in v6.7.12** (TL-28 (and TL-31, the dead-code floor): the drift check runs in cycc.exe and both macOS compilers — the repro's drifted pin warns, and under `CYRIUS_STRICT_PIN=1` / `cyrius build --strict-pin` fails with `error: cyrius.cyml pins 0.0.1 but cycc is 6.7.12 — toolchain drift (CYRIUS_STRICT_PIN)`, rc 1, nothing written (measured on cass, ecb, ach and under wine; Linux unchanged, x86_64 cycc byte-identical). `cyrius build --pie` from the Windows CLI is refused by name (`error: --pie is not available from the Windows CLI: cycc.exe emits PE only, which has no --pie mode …`, rc 1, nothing written). The user's decision D5, 2026-10-15. Rows: `strict_pin_every_host.sh` L1–L4, S1–S2, W1–W7; `win_cli_refuses_foreign_targets.sh` S4, W11, W12; `build_config_windows_arm.sh` axis 7b; mutations RED. Filed beside it (6.7.13): `--pie` on macOS still writes a plain Mach-O at rc 0 (neither Mach-O compiler reads CYRIUS_PIE). CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — found while fixing the Windows compile arm (6.7.8 C2-8b); the arm now hands cycc.exe
`CYRIUS_STRICT_PIN=1` and `CYRIUS_PIE=1`, and the compiler there does nothing with either.
**Placement:** 6.7.12 — repair 2: the platform release (tools lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D5 — drift on every host; --pie refused by name on Windows.
**Discovered:** 2026-10-10 during 6.7.8 C2-8b (cbt's Windows arm passes `--poison` / `--strict-pin` / `--pie`)
**Severity:** Medium (a CI pin-faithfulness switch that is silently inert on two of the three host OSes)
**Affects:** cycc since v5.11.57 (the drift check), every macOS and Windows compiler

## Summary

`cyrius build --strict-pin` exists so a CI build FAILS when `cyrius.cyml`'s `cyrius = "X.Y.Z"` pin differs from
the compiler's version (v5.11.58). The CLI only hands the compiler `CYRIUS_STRICT_PIN=1`; the check itself is
`_check_cyml_pin_drift` in `src/frontend/lex.cyr`, and both it and `_env_var_is_1` are wrapped in
`#ifdef CYRIUS_TARGET_LINUX`. Only the Linux forks predefine that (`src/main.cyr:1226` in its non-PE / non-Mach-O
/ non-agnos arm, `main_aarch64.cyr`, `main_aarch64_native.cyr`); `main_win.cyr`, `main_x86_macho.cyr` and
`main_aarch64_macho.cyr` predefine `CYRIUS_TARGET_WIN` / `CYRIUS_TARGET_MACOS` instead. So cycc.exe and both
macOS compilers never warn about drift and never fail on it — `--strict-pin` builds green on a drifted pin, rc 0,
no message.

Separately, the PE fork (`src/main_win.cyr`) reads no `CYRIUS_PIE` and takes no `--pie` (only `src/main.cyr:1148`
and the aarch64 forks do), so `cyrius build --pie` on a Windows host writes the same image as a plain build.

Until 6.7.8 neither variable even reached cycc.exe (cbt's Windows arm set only `CYRIUS_DCE` / `CYRIUS_BOUNDS`);
C2-8b fixed the arm (01bfc509), which is how this surfaced. The 6.7.8 plan's note that the arm fix would make `--strict-pin`
"start failing on drift" on Windows does NOT hold — this is why.

## Reproduction

```sh
# a drifted pin
mkdir q && cd q
printf '[package]\nname = "q"\nversion = "0.1.0"\ncyrius = "0.0.1"\n' > cyrius.cyml
printf 'var x = 42;\n' > m.cyr
CYRIUS_STRICT_PIN=1 ../build/cycc < m.cyr > o     # Linux: rc 1,
#   error: cyrius.cyml pins 0.0.1 but cycc is 6.7.8 — toolchain drift (CYRIUS_STRICT_PIN)
```

The native PE compiler (`build/cycc < src/main_win.cyr > cc_win; cc_win < src/main_win.cyr > cycc.exe`), measured
on real Windows (cass, `C:\cyrius-tests`, 2026-10-10) and under wine, same files:

```bat
set CYRIUS_STRICT_PIN=1&& cycc.exe < m.cyr > o1.exe      & rem errorlevel 0, no message
cycc.exe < m.cyr > o0.exe & set CYRIUS_PIE=1&& cycc.exe < m.cyr > o2.exe
fc /b o0.exe o2.exe                                       & rem errorlevel 0: identical
```

(The macOS compilers are the same by construction — `#ifdef CYRIUS_TARGET_LINUX` — not measured on ecb / ach.)

## Consumer-side workaround

Run the pin-faithful CI build on a Linux host.

## Root cause

`src/frontend/lex.cyr` `_env_var_is_1` / `_check_cyml_pin_drift`: `#ifdef CYRIUS_TARGET_LINUX` around both bodies
(verified); the PE fork has no `CYRIUS_PIE` read (verified: `grep CYRIUS_PIE src/main_win.cyr` is empty).

## Proposed fix

- The drift check on PE and Mach-O: read `cyrius.cyml` through each target's file path (the PE and BSD reroutes
  the include reader already uses) and the env through `_read_env`'s PE / macOS arms; then `--strict-pin` fails
  on drift on every host. ⚠ That CHANGES what those builds do (a drifted pin starts warning, and failing under
  `--strict-pin`) — the user's call.
- `--pie` on a Windows host: either refused by name in cbt (PE has no `--pie` mode) or given a meaning
  (`IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE`?). Also the user's call.
- Rows: the drift probe above on cycc.exe (wine + cass) and the Mach-O compilers (ecb, ach), plus a
  `cyrius build --strict-pin` row through cyrius.exe (tests/gates/toolchain/build_config_windows_arm.sh's stub
  already proves the variable arrives).
