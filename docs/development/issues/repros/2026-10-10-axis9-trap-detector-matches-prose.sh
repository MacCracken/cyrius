#!/bin/sh
# Repro for docs/development/issues/2026-10-10-axis9-trap-detector-matches-prose.md — run from the repo root.
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
