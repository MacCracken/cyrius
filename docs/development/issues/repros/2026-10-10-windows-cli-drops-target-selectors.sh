#!/bin/sh
# Repro for docs/development/issues/2026-10-10-windows-cli-drops-target-selectors.md — run from the repo root.
# from the repo root, on Linux with wine (or on cass with the shipped cyrius.exe / cycc.exe)
W=$(mktemp -d); WP="$W/wine"; mkdir -p "$W/bin" "$W/proj" "$W/h/.cache" "$W/ch"
cat src/main.cyr | build/cycc > "$W/cc" && chmod +x "$W/cc"
"$W/cc" < src/main_win.cyr > "$W/cc_win" && chmod +x "$W/cc_win"
"$W/cc_win" < cbt/cyrius.cyr > "$W/bin/cyrius.exe"; "$W/cc_win" < src/main_win.cyr > "$W/bin/cycc.exe"
printf 'fn main(): i64 { return 7; }\nvar r = main();\nsyscall(60, r);\n' > "$W/proj/hello.cyr"
export WINEPREFIX="$WP" HOME="$W/h" XDG_CACHE_HOME="$W/h/.cache" WINEDEBUG=-all
CH=$(winepath -w "$W/ch")
( cd "$W/proj" && CYRIUS_HOME="$CH" wine "$W/bin/cyrius.exe" build --agnos hello.cyr agnos.out; echo "rc=$?" )
( cd "$W/proj" && CYRIUS_HOME="$CH" wine "$W/bin/cyrius.exe" build --target=x86_64-bare-metal-elf hello.cyr bm.out; echo "rc=$?" )
head -c 2 "$W/proj/agnos.out"; head -c 2 "$W/proj/bm.out"; echo     # MZMZ
WINEPREFIX="$WP" wineserver -k; rm -rf "/tmp/.wine-$(id -u)/server-$(stat -c %D "$WP")-$(printf %x "$(stat -c %i "$WP")")" "$W"
