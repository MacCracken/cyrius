#!/bin/sh
# syntax_only_flag_pe.sh — 6.6.17. The Windows compiler fork honours `--syntax-only`.
#
# src/main_win.cyr read --version, --strict and --allow-undef and never --syntax-only, so when
# `cyrius lint` started passing it to cycc.exe the flag was ignored: the pre-pass ran a full,
# resolving compile and a file whose only fault was a missing include was reported as broken.
# Rows: the fixture's one fault is an unresolved name — with the flag the compile is clean
# (rc 0), without it rc 1 naming the name (anti-vacuous). Through x86 (the reference), the
# Linux-hosted PE cross (main_win.cyr's /proc/self/cmdline path) and cycc.exe under wine
# (its GetCommandLineW path). wine is emulation, not hardware: real cass runs at the gate.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: syntax_only_flag_pe: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: syntax_only_flag_pe: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: syntax_only_flag_pe: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE prefix, and wine's own HOME / XDG_CACHE_HOME, under $D; the EXIT teardown stops THIS
# prefix's wineserver and removes its server dir, which `wineserver -k` leaves behind.
WP="$D/wine"; mkdir -p "$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
export WINEPREFIX="$WP" HOME="$D/whome" XDG_CACHE_HOME="$D/whome/.cache" WINEDEBUG=-all
"$CC" < src/main_win.cyr > "$D/xwin" 2>/dev/null && chmod +x "$D/xwin" \
  || { echo "FAIL: syntax_only_flag_pe: could not build src/main_win.cyr"; exit 1; }
"$D/xwin" < src/main_win.cyr > "$D/cycc.exe" 2>/dev/null
printf 'fn f(): i64 { return not_declared_anywhere; }\nvar r = f();\n' > "$D/u.cyr"
fail=0; rows=0
# row <label> <cmd...> — the flag must make the compile clean, its absence must not
row() {
  l=$1; shift
  a=0; "$@" --syntax-only < "$D/u.cyr" > "$D/o1" 2> "$D/e1" || a=$?
  b=0; "$@" < "$D/u.cyr" > "$D/o2" 2> "$D/e2" || b=$?
  rows=$((rows + 1))
  [ "$a" = 0 ] || { echo "  FAIL: syntax_only_flag_pe $l: --syntax-only rc $a: $(grep -m1 error "$D/e1")"; fail=$((fail + 1)); }
  { [ "$b" != 0 ] && grep -q "not_declared_anywhere" "$D/e2"; } \
    || { echo "  FAIL: syntax_only_flag_pe $l: without the flag rc $b (want 1, naming the name)"; fail=$((fail + 1)); }
}
row x86 "$CC"
row pe_cross "$D/xwin"
if command -v wine >/dev/null 2>&1 && [ -s "$D/cycc.exe" ]; then row cycc.exe_wine wine "$D/cycc.exe"
else echo "  SKIP (named): cycc.exe under wine — wine is not installed"; fi
if [ "$fail" -ne 0 ]; then echo "FAIL syntax_only_flag_pe: $fail of $rows row(s) red"; exit 1; fi
echo "PASS syntax_only_flag_pe: --syntax-only honoured by x86, the PE cross and cycc.exe ($rows compilers), and its absence still resolves"
exit 0
