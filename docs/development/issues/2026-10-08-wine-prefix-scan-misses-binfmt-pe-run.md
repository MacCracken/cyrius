# `gates_never_write_tree.sh` axis 9 cannot see a PE binary run directly through binfmt_misc — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b: axis 9's detector (the `wine9.awk` heredoc,
extracted verbatim from `tests/gates/toolchain/gates_never_write_tree.sh`) flags a fixture gate that runs
`wine "$T/hello.exe"` with no private prefix, and prints NOTHING for the same gate running `"$T/hello.exe"` directly.
This box registers wine for every MZ image (`/proc/sys/fs/binfmt_misc/DOSWin`: enabled, `interpreter /usr/bin/wine`,
`magic 4d5a`), so the direct run is a wine run in the user's shared `~/.wine` with the user's `HOME`. Whether any gate
does this today was not surveyed.
**Placement:** unpinned — 6.x-line backlog — never 7.x.
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
