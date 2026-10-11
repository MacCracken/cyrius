# `gates_never_write_tree.sh` axis 9 cannot see a PE binary run directly through binfmt_misc — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 16; CHANGELOG [6.7.9]) axis 9 now counts a COMMAND WORD that names
> a .exe as a wine run (`exe_run` / `cmd_map` in `wine9.awk`): a path ending .exe, a `$V.exe`, or a variable
> assigned one (`V="$T/a.exe"`, `for V in … a.exe …`), at the head of a simple command — past assignments, if /
> then / do / ! / {, and the run-prefixes time / exec / env / nice / nohup / command / stdbuf / timeout — including
> inside `$( … )` (quoted or not) and backquotes. Such a run must have the same private `WINEPREFIX`, `HOME` and
> `XDG_CACHE_HOME` and the same EXIT teardown as a `wine` call. The issue's verbatim `direct.sh` is flagged at line 7
> (fixture `exe_direct`). Its clean twin, with the prefix exported first, is clean (`c_exe_export`). Survey: none of the
> 459 scripts axis 9 scans runs a .exe directly, so no verdict changed. Each PE written without a .exe name is only
> inspected, never run. Mutation-proven: 13 mutants, each RED. The alternative, a check.sh-wide throwaway prefix and
> `HOME`, was not taken: it would change `HOME` under every gate.

**Status:** ✅ **RESOLVED** in v6.7.9 (the quick lane's bite 16). Filed OPEN — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b: axis 9's detector (the `wine9.awk` heredoc,
extracted verbatim from `tests/gates/toolchain/gates_never_write_tree.sh`) flags a fixture gate that runs
`wine "$T/hello.exe"` with no private prefix, and prints NOTHING for the same gate running `"$T/hello.exe"` directly.
This box registers wine for every MZ image (`/proc/sys/fs/binfmt_misc/DOSWin`: enabled, `interpreter /usr/bin/wine`,
`magic 4d5a`), so the direct run is a wine run in the user's shared `~/.wine` with the user's `HOME`. Whether any gate
does this today was not surveyed (surveyed at the fix: none does).
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — never 7.x.
**Discovered:** the 6.6.17 lanes (roadmap commit 0986fd97, 2026-10-05); filed 2026-10-08 from roadmap.md.
**Severity:** Low — a blind spot in a hygiene gate; no gate is known to use the shape.
**Affects:** `tests/gates/toolchain/gates_never_write_tree.sh` axis 9, 6.6.16 – 6.7.6.

## Summary

Axis 9 (6.6.16 G4, extended 6.6.17) statically requires every gate that runs wine to give it a private `WINEPREFIX`,
`HOME` and `XDG_CACHE_HOME` and an EXIT trap that stops that prefix's wineserver and removes its server dir. "Runs wine"
is defined lexically: `wine` / `wine64` / `winepath` followed by an operand (the regex in the awk's main rule). On a
host with a binfmt_misc entry for PE, executing a `.exe` path runs `/usr/bin/wine` with the inherited environment —
the shared default prefix, the shared wineserver, writes into the user's `~/.cache` — and the scan does not see it.

## Reproduction

```sh
awk '/^cat > "\$W\/wine9.awk" <<.AWK.$/{f=1;next} f&&/^AWK$/{exit} f{print}' \
    tests/gates/toolchain/gates_never_write_tree.sh > wine9.awk
cat > direct.sh <<'EOF'
#!/bin/sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat src/main_win.cyr | build/cycc > "$T/cc_win"
printf 'syscall(60, 0);\n' | "$T/cc_win" > "$T/hello.exe"
chmod +x "$T/hello.exe"
"$T/hello.exe" || exit 1
EOF
sed 's#^"\$T/hello.exe"#wine "$T/hello.exe"#' direct.sh > viawine.sh
awk -f wine9.awk direct.sh     # (no output) — not flagged
awk -f wine9.awk viawine.sh    # 7: runs wine with no private WINEPREFIX, HOME, XDG_CACHE_HOME …
                               # 3: runs wine but no EXIT trap stops this prefix's wineserver …
cat /proc/sys/fs/binfmt_misc/DOSWin   # enabled / interpreter /usr/bin/wine / magic 4d5a
```

## Root cause

`tests/gates/toolchain/gates_never_write_tree.sh`, the axis-9 awk: the "runs wine" match is
`(wine|wine64|winepath)[ \t]+(operand)`; nothing treats the execution of a PE file as a wine call.

## Proposed fix

Extend the "runs wine" rule to a command word that names a `.exe` (a `$VAR/…exe`, `./…exe`, or a variable assigned
one), and add the shape as a self-test fixture (flagged) beside a clean twin with a private prefix exported first.
Alternatively, or in addition, make check.sh's environment refuse the shared prefix outright (export a throwaway
`WINEPREFIX` / `HOME` for the whole run) so a missed shape cannot reach `~/.wine`.
