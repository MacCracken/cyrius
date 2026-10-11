# `gates_never_write_tree.sh` axis 9 takes any line holding ` trap ` and a trailing ` 0` as the EXIT trap — a prose label fails a clean wine gate — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f): axis 9's
detector (the `wine9.awk` heredoc, extracted verbatim from `tests/gates/toolchain/gates_never_write_tree.sh`) prints
nothing for a clean wine fixture (private `WINEPREFIX` / `HOME` / `XDG_CACHE_HOME`, a `_wine_down` teardown in its
EXIT trap) and FAILS the same fixture with one added line `check "the trap gate" 0`: "runs wine but no EXIT trap
stops this prefix's wineserver ... and removes its server dir ...: check "the trap gate" 0".
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-6a (two of its gate labels tripped it; the bite reworded
the labels rather than change the detector).
**Severity:** Low — a false RED in a hygiene gate (loud, never a false pass); the workaround is rewording a label.
**Affects:** `tests/gates/toolchain/gates_never_write_tree.sh` axis 9, since its teardown rule (6.6.17)

## Summary

Axis 9 statically checks every gate that runs wine: the gate's LAST `trap … EXIT` line (plus the fns it calls) must
stop its private prefix's wineserver and remove that server's dir. It finds "the last EXIT trap" with a pattern that
matches the word `trap` preceded by start-of-line / whitespace / `;` / `&` / `|` and ANY whitespace-delimited `EXIT`
or `0` later on the line. Comments are stripped first, but string contents are not — so a later test line whose
label contains the word "trap" and which ends in an expected exit code `0` (`check "the trap gate" 0`,
`exits t9 0 "... trap ..."`) becomes "the last EXIT trap", the real teardown is never read, and the gate is reported
as having none.

## Reproduction

```sh
W=$(mktemp -d)
awk '/^cat > "\$W\/wine9.awk" <<.AWK.$/{f=1;next} f&&/^AWK$/{exit} f{print}' \
    tests/gates/toolchain/gates_never_write_tree.sh > "$W/wine9.awk"
{ printf 'T=$(mktemp -d) && [ -d "$T" ] || { echo no; exit 1; }\nWP="$T/wine"\n'
  printf '_wine_down() {\n    [ -d "$WP" ] || return 0\n'
  printf '    _ws="/tmp/.wine-$(id -u)/server-$(stat -c %%D "$WP")-$(printf %%x "$(stat -c %%i "$WP")")"\n'
  printf '    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true\n    rm -rf "$_ws" || true\n}\n'
  printf 'trap '"'"'_wine_down; rm -rf "$T"'"'"' EXIT\n'
  printf 'export WINEPREFIX="$WP" HOME="$T/h" XDG_CACHE_HOME="$T/h/.cache" WINEDEBUG=-all\nwine "$T/a.exe"\n'; } > "$W/clean.sh"
cp "$W/clean.sh" "$W/prose.sh"; printf 'check "the trap gate" 0\n' >> "$W/prose.sh"
awk -f "$W/wine9.awk" "$W/clean.sh"     # nothing (clean)
awk -f "$W/wine9.awk" "$W/prose.sh"     # 12: runs wine but no EXIT trap stops this prefix's wineserver ...
rm -rf "$W"
```

## Root cause

The awk's function-body pass (`gates_never_write_tree.sh`, in the `wine9.awk` heredoc that starts at `:1055`):

```awk
if (s ~ /(^|[ \t;&|])trap[ \t]/ && s ~ /[ \t](EXIT|0)([ \t;]|$)/) lasttrap = L
```

The two tests are independent: `trap` anywhere on the line (inside a quoted label included), and `EXIT` / `0`
anywhere after whitespace. A real trap is `trap '<body>' EXIT` (or `0`) with `trap` as the COMMAND word and the
signal list after its quoted body.

## Proposed fix

Match `trap` as a command word (at the start of a simple command: line start or after `;` / `&&` / `||` / `{` /
`then` / `do`, optionally after whitespace), followed by one quoted or bare argument, followed by a signal list
containing `EXIT` or `0` — or, simpler, strip double-quoted strings before testing, as comments already are. Add the
prose fixture beside the existing ones (`$W/fx9/…`) as a must-stay-clean case, and keep every current fixture's
verdict (the self-test lists them); the bite-6a mutation ledger gives two real labels that tripped it.

## Consumer-side workaround

Avoid the word "trap" in a test label on a line that ends in ` 0`.
