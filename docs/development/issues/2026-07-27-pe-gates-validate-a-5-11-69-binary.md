# The two Windows PE behavioural gates have been validating a **cycc 5.11.69** binary for the entire v6.x line

**Discovered:** 2026-07-27, by the v6.4.x closeout code-review pass (shipped findings went out as
v6.4.81; this one is deferred to the v6.4.82 closeout).
**Severity:** **High** — not wrong code, but a *green checkmark that never ran the current compiler*.
This is the exact failure mode `CLAUDE.md`'s Cross-OS principle exists to prevent, and the same shape
as the macOS rot that went undetected for ~9 minors behind a job named "Mach-O ARM64 Native ✓".
**Affects:** `programs/checks/platform_win_macho.cyr` — every release from v6.0.0 through v6.4.81.

## Evidence

```
$ strings -a build/cycc_win_cross | grep -E '^cycc [0-9]'
cycc 5.11.69
$ ls -la build/cycc_win_cross
-rwxr-xr-x 686640 May 19 02:55 build/cycc_win_cross
```

For contrast, `build/cycc_win` — the manifest-managed PE compiler — reports `cycc 6.4.81`.

Both gates rebuild on an **existence-only** trigger:

- `platform_win_macho.cyr:471` `fn _pe_exit_gate()` → `:473` `var cc_pe = _root_path("build/cycc_win_cross");`
  → `:474` `if (file_exists(cc_pe) != 1) { ...build... }`
- `platform_win_macho.cyr:684` `fn _pe_path_apis_gate()` → `:686` same path, `:687` same test

Both are live in the suite (`programs/checks/main.cyr:409`, `:413`). Nothing else in the repo ever
refreshes the artifact:

```
$ grep -rn 'cycc_win_cross' scripts/ .github/ cbt/ programs/ | grep -v platform_win_macho
(no output)
$ grep -n cross_bins cyrius.cyml
cross_bins = ["cycc_aarch64", "cycc_win", "cycc-native-aarch64", "cycc_cx"]
```

`cycc_win_cross` is **not** in the manifest, so `cyrius pulsar` and `install.sh` never refresh it
either.

## Impact

The two Windows PE behavioural gates — `PE syscall(60,42) → exit 42` and `PE kernel32 path APIs`,
both of which SSH to cass — have been exercising a **v5.11.69** compiler on the dev box since
2026-05-19. That covers all of v6.0.x through v6.4.81. They report GREEN for a compiler nobody ships.

The asymmetry is what makes it durable: on CI the file is absent, so it rebuilds fresh — but CI
cannot reach cass and skips the SSH leg. So the gate is stale in exactly the environment where it
actually runs, and fresh in the one where it doesn't.

## Fix

`programs/checks/` only — cycc stays byte-identical.

Mirror the staleness trigger `scripts/check.sh` already uses for `build/cyrius_check` (`-nt` against
the newest source) instead of the existence test at `:474` and `:687`. Simplest correct version:
drop the guard and always rebuild from `src/main_win.cyr` through `CC_PATH` before the SSH step.

Delete the stale `build/cycc_win_cross` as part of the fix so the next `check.sh` regenerates it.

Consider folding the artifact onto the manifest-managed `build/cycc_win` name so it is covered by
`cyrius pulsar` / install refresh and cannot fall out of the tracked set again.

## Acceptance criteria

1. `build/cycc_win_cross` (or its replacement) reports the **current** `VERSION` after a plain
   `sh scripts/check.sh`, verified with `strings -a … | grep '^cycc '`.
2. Mutation-proven: touch `src/main_win.cyr`, re-run `check.sh`, and confirm the artifact is
   rebuilt — a gate that cannot detect a stale binary is the bug being fixed here.
3. Both `_pe_exit_gate` and `_pe_path_apis_gate` still pass on real cass.

## Placement

v6.4.82 closeout (mechanical/judgment pass) or the first v6.5.x patch. **Not 7.x** — this is
toolchain/runtime.
