#!/bin/sh
# strict_pin_every_host.sh — 6.7.12 (D5, the user 2026-10-15). The toolchain-pin drift check runs in
# EVERY host's compiler: a `cyrius.cyml` whose `[package] cyrius = "X.Y.Z"` differs from the
# compiler's version warns, and under CYRIUS_STRICT_PIN=1 (`cyrius build --strict-pin`) fails, rc 1,
# nothing written — on Windows (cycc.exe) and both macOS compilers as on Linux.
#
# THE DEFECT (issues/archived/2026-10-10-strict-pin-and-pie-inert-off-linux.md). `_check_cyml_pin_drift` and
# `_env_var_is_1` (src/frontend/lex.cyr) were wrapped in `#ifdef CYRIUS_TARGET_LINUX`, and the one
# call sat in `_init_cyrius_lib`'s Linux arm, so cycc.exe and the two Mach-O compilers never warned
# and never failed: `--strict-pin` built green on a drifted pin, rc 0, no message (measured on cass
# and under wine). The fix drops the two guards — `_read_env` has a macOS and a PE arm, and the raw
# open / read / close / write / exit are routed on both Macs and rerouted on PE — and calls the check
# from `_init_cyrius_lib` under `#ifdef CYRIUS_TARGET_MACOS` / `CYRIUS_TARGET_WIN`. The Linux call
# is where it was, so the Linux compiler is byte-identical. (`--pie` on the Windows CLI, the issue's
# other half, is refused in win_cli_refuses_foreign_targets.sh W11-W12.)
#
# ROWS
#   L1-L4  the Linux compiler (unchanged): drifted + STRICT rc 1, the error, nothing written; drifted
#          rc 0 + the warning; CYRIUS_NO_WARN_PIN_DRIFT=1 silent; a matching pin silent
#   S1     the PE compiler and the x86_64 / arm64 Mach-O compilers built from this tree carry the
#          check (its error and warning text); the Mach-O ones cannot run here — ecb and ach ran the
#          probe by hand (see the CHANGELOG)
#   S2     each of the three CALLS it: neither `_check_cyml_pin_drift` nor `_env_var_is_1` is in the
#          build's CYRIUS_DCE_VERBOSE=1 dead-fn list
#   W1-W6  (wine, named SKIP without it) cycc.exe: drifted + STRICT rc 1, the exact error, an empty
#          output; drifted rc 0, the warning, an MZ image; NO_WARN + STRICT rc 0, silent, the same
#          image; a matching pin + STRICT silent; no cyrius.cyml + STRICT silent; a `\r\n` manifest
#          reads the same pin
#   W7     (wine) through cyrius.exe: `build --strict-pin` on the drifted pin rc 1, the error, no
#          output; a plain build rc 0 with the warning
# Mutations (measured): the two guards restored (6.7.11's lex.cyr) -> S1 S2 W1 W2 W6 W7 RED; the PE
# call dropped from `_init_cyrius_lib` -> S2 W1 W2 W6 W7 RED; the macOS call dropped -> S2 RED.
set -u
G=strict_pin_every_host
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
WP="$T/wine"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w > /dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
pass=0; fail=0; skips=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
unset CYRIUS_STRICT_PIN CYRIUS_NO_WARN_PIN_DRIFT CYRIUS_BOUNDS CYRIUS_POISON CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE \
    CYRIUS_TARGET_WIN CYRIUS_MACHO CYRIUS_MACHO_ARM CYRIUS_PIE 2> /dev/null || true
V=$(tr -d '[:space:]' < VERSION)
ERR="error: cyrius.cyml pins 0.0.1 but cycc is $V — toolchain drift (CYRIUS_STRICT_PIN)"
WARN="warning: cyrius.cyml pins 0.0.1 but cycc is $V — toolchain drift (snapshot may be stale; set CYRIUS_NO_WARN_PIN_DRIFT=1 to silence)"
mkdir -p "$T/d" "$T/m" "$T/n" "$T/r"
printf '[package]\nname = "q"\nversion = "0.1.0"\ncyrius = "0.0.1"\n' > "$T/d/cyrius.cyml"
printf '[package]\nname = "q"\nversion = "0.1.0"\ncyrius = "%s"\n' "$V" > "$T/m/cyrius.cyml"
printf '[package]\r\nname = "q"\r\nversion = "0.1.0"\r\ncyrius = "0.0.1"\r\n' > "$T/r/cyrius.cyml"
for d in d m n r; do printf 'var x = 42;\n' > "$T/$d/m.cyr"; done
magic() { if [ -s "$1" ]; then od -An -tx1 -N2 "$1" | tr -d ' \n'; else echo empty; fi; }
has() { if grep -aqF "$2" "$1" 2> /dev/null; then echo yes; else echo no; fi; }

# ── L: the Linux compiler ───────────────────────────────────────────────────────────────────
lrun() {   # lrun DIR ENV... -> rc; stderr in $T/l.err, output in $T/l.out
    _d=$1; shift; _rc=0
    ( cd "$T/$_d" && env "$@" "$CC" < m.cyr > "$T/l.out" 2> "$T/l.err" ) || _rc=$?
    echo "$_rc"
}
rc=$(lrun d CYRIUS_STRICT_PIN=1)
if [ "$rc" = 1 ] && [ "$(cat "$T/l.err")" = "$ERR" ] && [ ! -s "$T/l.out" ]; then ok "L1 Linux: drifted + STRICT: rc 1, the error, nothing written"
else bad "L1 Linux (rc $rc): $(cat "$T/l.err")"; fi
rc=$(lrun d X=1)
if [ "$rc" = 0 ] && grep -qxF "$WARN" "$T/l.err" && [ -s "$T/l.out" ]; then ok "L2 Linux: drifted: rc 0, the warning, an image"
else bad "L2 Linux (rc $rc): $(cat "$T/l.err")"; fi
rc=$(lrun d CYRIUS_NO_WARN_PIN_DRIFT=1 CYRIUS_STRICT_PIN=1)
r2=$(lrun m CYRIUS_STRICT_PIN=1); e2=$(grep -c 'toolchain drift' "$T/l.err" || true)
if [ "$rc$r2$e2" = "000" ]; then ok "L3/L4 Linux: NO_WARN silences, a matching pin is silent"
else bad "L3/L4 Linux: rc $rc / $r2, drift lines $e2"; fi

# ── S: every host's compiler carries the check ──────────────────────────────────────────────
"$CC" < src/main_win.cyr > "$T/cc_win" 2> /dev/null && chmod +x "$T/cc_win" \
  && "$T/cc_win" < src/main_win.cyr > "$T/cycc.exe" 2> /dev/null && [ -s "$T/cycc.exe" ] \
  || { echo "FAIL: $G: the PE compiler does not build"; exit 1; }
"$CC" < src/main_aarch64.cyr > "$T/cc_x" 2> /dev/null && chmod +x "$T/cc_x" \
  && CYRIUS_MACHO_ARM=1 "$T/cc_x" < src/main_aarch64_macho.cyr > "$T/cycc_macho_arm" 2> /dev/null && [ -s "$T/cycc_macho_arm" ] \
  && CYRIUS_MACHO=1 "$CC" < src/main_x86_macho.cyr > "$T/cycc_macho_x86" 2> /dev/null && [ -s "$T/cycc_macho_x86" ] \
  || { echo "FAIL: $G: a Mach-O compiler does not build"; exit 1; }
ERRT=" — toolchain drift (CYRIUS_STRICT_PIN)"
WARNT="set CYRIUS_NO_WARN_PIN_DRIFT=1 to silence"
got="$(has "$T/cycc.exe" "$ERRT") $(has "$T/cycc.exe" "$WARNT") $(has "$T/cycc_macho_x86" "$ERRT") $(has "$T/cycc_macho_x86" "$WARNT") $(has "$T/cycc_macho_arm" "$ERRT") $(has "$T/cycc_macho_arm" "$WARNT")"
if [ "$got" = "yes yes yes yes yes yes" ]; then ok "S1 the PE, x86_64 Mach-O and arm64 Mach-O compilers carry the drift check"
else bad "S1 the check's text in PE / Mach-O x86_64 / Mach-O arm64 (error, warning each): $got"; fi
# S2 — and CALL it: neither fn is in the compiler's own dead-fn list (6.7.11 listed both, the
# bodies stubbed and never called). The list is the build's CYRIUS_DCE_VERBOSE=1 report.
dead() {   # dead STDERR-FILE -> how many of the two fns it lists dead, else "none" for an empty report
    if ! grep -q '^  dead: ' "$1" 2> /dev/null; then echo none; return; fi
    grep -cE '^  dead: (_check_cyml_pin_drift|_env_var_is_1)$' "$1" || true
}
CYRIUS_DCE_VERBOSE=1 "$T/cc_win" < src/main_win.cyr > /dev/null 2> "$T/dw"
CYRIUS_DCE_VERBOSE=1 CYRIUS_MACHO=1 "$CC" < src/main_x86_macho.cyr > /dev/null 2> "$T/dx"
CYRIUS_DCE_VERBOSE=1 CYRIUS_MACHO_ARM=1 "$T/cc_x" < src/main_aarch64_macho.cyr > /dev/null 2> "$T/da"
got="$(dead "$T/dw") $(dead "$T/dx") $(dead "$T/da")"
if [ "$got" = "0 0 0" ]; then ok "S2 each of them calls it (not in its CYRIUS_DCE_VERBOSE dead list)"
else bad "S2 the two fns listed dead in PE / Mach-O x86_64 / Mach-O arm64: $got"; fi

# ── W: cycc.exe under wine ──────────────────────────────────────────────────────────────────
if ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP: W1-W7 — wine is not installed; cass runs the probe on real Windows"
    skips=$((skips+1))
else
    export WINEPREFIX="$WP" HOME="$T/whome" XDG_CACHE_HOME="$T/whome/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    mkdir -p "$T/whome"
    wine cmd /c exit 0 > /dev/null 2>&1 || true   # create the prefix before a timed row
    wrun() {   # wrun DIR ENV... -> rc; stderr (CR stripped) in $T/w.err, output in $T/$DIR/o.exe
        _d=$1; shift; _rc=0
        ( cd "$T/$_d" && env "$@" timeout 300 wine "$T/cycc.exe" < m.cyr > o.exe 2> "$T/w.raw" ) || _rc=$?
        tr -d '\r' < "$T/w.raw" > "$T/w.err"
        echo "$_rc"
    }
    rc=$(wrun d CYRIUS_STRICT_PIN=1)
    if [ "$rc" = 1 ] && [ "$(cat "$T/w.err")" = "$ERR" ] && [ "$(magic "$T/d/o.exe")" = empty ]; then
        ok "W1 cycc.exe: drifted + STRICT: rc 1, the exact error, nothing written"
    else bad "W1 cycc.exe (rc $rc, output $(magic "$T/d/o.exe")): $(cat "$T/w.err")"; fi
    rc=$(wrun d X=1); cp "$T/d/o.exe" "$T/w2.exe" 2> /dev/null
    if [ "$rc" = 0 ] && [ "$(cat "$T/w.err")" = "$WARN" ] && [ "$(magic "$T/d/o.exe")" = 4d5a ]; then
        ok "W2 cycc.exe: drifted: rc 0, the warning, an MZ image"
    else bad "W2 cycc.exe (rc $rc, output $(magic "$T/d/o.exe")): $(cat "$T/w.err")"; fi
    rc=$(wrun d CYRIUS_NO_WARN_PIN_DRIFT=1 CYRIUS_STRICT_PIN=1)
    if [ "$rc" = 0 ] && [ ! -s "$T/w.err" ] && cmp -s "$T/d/o.exe" "$T/w2.exe"; then
        ok "W3 cycc.exe: NO_WARN + STRICT: rc 0, silent, the same image"
    else bad "W3 cycc.exe (rc $rc): $(cat "$T/w.err")"; fi
    rc=$(wrun m CYRIUS_STRICT_PIN=1)
    if [ "$rc" = 0 ] && [ ! -s "$T/w.err" ] && [ "$(magic "$T/m/o.exe")" = 4d5a ]; then ok "W4 cycc.exe: a matching pin + STRICT: silent"
    else bad "W4 cycc.exe (rc $rc): $(cat "$T/w.err")"; fi
    rc=$(wrun n CYRIUS_STRICT_PIN=1)
    if [ "$rc" = 0 ] && [ ! -s "$T/w.err" ] && [ "$(magic "$T/n/o.exe")" = 4d5a ]; then ok "W5 cycc.exe: no cyrius.cyml + STRICT: silent"
    else bad "W5 cycc.exe (rc $rc): $(cat "$T/w.err")"; fi
    rc=$(wrun r CYRIUS_STRICT_PIN=1)
    if [ "$rc" = 1 ] && [ "$(cat "$T/w.err")" = "$ERR" ]; then ok "W6 cycc.exe: a CRLF manifest reads the same pin (rc 1, the error)"
    else bad "W6 cycc.exe (rc $rc): $(cat "$T/w.err")"; fi
    # W7 — through the Windows CLI: `cyrius build --strict-pin` hands cycc.exe CYRIUS_STRICT_PIN=1 (6.7.8)
    mkdir -p "$T/wb/bin" "$T/wb/ch" && cp "$T/cycc.exe" "$T/wb/bin/cycc.exe" \
      && "$T/cc_win" < cbt/cyrius.cyr > "$T/wb/bin/cyrius.exe" 2> /dev/null && [ -s "$T/wb/bin/cyrius.exe" ] \
      || bad "W7 setup: the PE CLI does not build"
    CH=$(winepath -w "$T/wb/ch" 2> /dev/null)
    rm -f "$T/d/o.exe"
    rc=0; ( cd "$T/d" && CYRIUS_HOME="$CH" CYRIUS_RESOLVED=1 timeout 300 wine "$T/wb/bin/cyrius.exe" build --strict-pin m.cyr o.exe ) > "$T/w7.raw" 2>&1 || rc=$?
    r2=0; ( cd "$T/d" && CYRIUS_HOME="$CH" CYRIUS_RESOLVED=1 timeout 300 wine "$T/wb/bin/cyrius.exe" build m.cyr o2.exe ) > "$T/w7b.raw" 2>&1 || r2=$?
    # (the CLI's `compile … [x86_64] ` progress text shares the diagnostic's line)
    if [ "$rc" = 1 ] && tr -d '\r' < "$T/w7.raw" | grep -qF "$ERR" && [ ! -s "$T/d/o.exe" ] \
       && [ "$r2" = 0 ] && tr -d '\r' < "$T/w7b.raw" | grep -qF "$WARN" && [ "$(magic "$T/d/o2.exe")" = 4d5a ]; then
        ok "W7 cyrius.exe build --strict-pin on the drifted pin: rc 1, the error, no output; without it rc 0 + the warning"
    else bad "W7 cyrius.exe (strict rc $rc, plain rc $r2): $(tr -d '\r' < "$T/w7.raw" | tr '\n' ' ') || $(tr -d '\r' < "$T/w7b.raw" | tr '\n' ' ')"; fi
    _wine_down
fi

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
[ "$skips" -eq 0 ] || exit 77
exit 0
