#!/bin/sh
# tests/gates/platform/win_cli_sign_efi_spawns.sh — 6.7.16
#
# `cyrius sign-efi` reaches the cyrsign-efi helper the install ships beside the CLI, on Windows
# too, and a missing helper is named by its real path and source.
#
# THE DEFECT (issues/2026-10-19-windows-cli-sign-efi-cannot-run-the-shipped-helper.md). The verb
# exec'd the helper in place with `sys_execve`, a `return 0 - 1` stub on PE, so the Windows CLI
# fell through to its error whatever was installed: the 6.7.16 Windows tarball ships
# bin\cyrsign-efi.exe, and `cyrius.exe sign-efi --help` beside it gave rc 127 and
#   error: sign-efi: cyrsign-efi helper not found (Linux-only; build it with
#          `cyrius build programs/cyrsign_efi.cyr build/cyrsign-efi`)
# — "Linux-only" (macOS ships the helper too) and a source name that does not exist
# (programs/cyrsign-efi.cyr). cyrius.exe now runs the helper as a CHILD (`_win_spawn_vec`, the
# `_win_redirect_to_pinned` shape) and exits with its code; every target names a missing helper
# (`.exe` on Windows) and the real source, and a POSIX execve that fails on an installed helper
# names the error. The static half — every exec-in-place `sys_execve` in cbt/ has a PE arm — is
# axis 7 of tests/gates/platform/cbt_fork_sites_have_pe_arm.sh; the hardware half is the cass
# leg of scripts/cross-os-selfhost.sh.
#
# ROWS
#   L1  the Linux CLI, no helper: rc 127, `not installed at <home>/bin/cyrsign-efi`, the real
#       source named, no "Linux-only", no `cyrsign_efi.cyr`.
#   L2  the Linux CLI with a Linux cyrsign-efi beside it: `sign-efi --help` rc 0, `Usage: cyrsign-efi`.
#   L3  the helper there but not executable: rc 127, `could not run <path> (execve error 13)`.
#   W1  (wine) cyrius.exe with the real cyrsign-efi.exe in its bin\: `sign-efi --help` rc 0 and
#       `Usage: cyrsign-efi` on stdout — the filed repro.
#   W2  (wine) `sign-efi` with no arguments: the helper's own refusal and ITS exit code (2).
#   W3  (wine) a probe cyrsign-efi.exe: the argument tail (one with a space) reaches it whole and
#       its exit code (37) is cyrius.exe's.
#   W4  (wine) no helper: rc 127, `cyrsign-efi.exe` and programs/cyrsign-efi.cyr named, no
#       "Linux-only".
#   wine is NOT hardware: without it the W rows are a named SKIP (exit 77).
#
# MUTATION (6.7.16, measured): the gate run against a copy of the tree with cbt/cyrius.cyr's
# sign-efi arm restored to 0ba98b3bf's -> RED L1 L3 W1 W2 W3 W4 (W1: rc 127, the filed line);
# the Windows arm alone removed -> RED W1 W2 W3; the `.exe` in the Windows message dropped ->
# RED W4.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=win_cli_sign_efi_spawns
[ -x "$CC" ] || { echo "FAIL: $NAME — $CC not built"; exit 1; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix and wine's own HOME / XDG_CACHE_HOME under $T; the EXIT teardown stops
# THIS prefix's wineserver and removes its server dir (the sibling wine gates' shape).
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT

fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$1" "$2" && echo yes || echo no; }

# ── the Linux CLI ───────────────────────────────────────────────────────────────────────
echo "the Linux CLI:"
mkdir -p "$T/lh/bin" "$T/lw"
if ! "$CC" < cbt/cyrius.cyr > "$T/lh/bin/cyrius" 2> "$T/cli.err" || [ ! -s "$T/lh/bin/cyrius" ]; then
    echo "  FAIL: could not build cbt/cyrius.cyr"; grep -E '^error' "$T/cli.err" | head -3; exit 1
fi
chmod +x "$T/lh/bin/cyrius"
lrun() { RC=0; ( cd "$T/lw" && CYRIUS_HOME="$T/lh" timeout 120 "$T/lh/bin/cyrius" "$@" > "$T/out" 2> "$T/err" ) || RC=$?; }
lrun sign-efi --help
check "L1 no helper: rc 127" 127 "$RC"
check "  …named where it was looked for" yes "$(has "sign-efi: the cyrsign-efi helper is not installed at $T/lh/bin/cyrsign-efi (" "$T/err")"
check "  …and the real source (programs/cyrsign-efi.cyr)" yes "$(has 'cyrius build programs/cyrsign-efi.cyr build/cyrsign-efi' "$T/err")"
check "  …not 'Linux-only', not cyrsign_efi.cyr" no "$(grep -qE 'Linux-only|cyrsign_efi' "$T/err" && echo yes || echo no)"
if ! "$CC" < programs/cyrsign-efi.cyr > "$T/lh/bin/cyrsign-efi" 2> "$T/se.err" || [ ! -s "$T/lh/bin/cyrsign-efi" ]; then
    echo "  FAIL: could not build programs/cyrsign-efi.cyr"; grep -E '^error' "$T/se.err" | head -3; fails=$((fails + 1))
else
    chmod +x "$T/lh/bin/cyrsign-efi"
    lrun sign-efi --help
    check "L2 the helper beside the CLI: sign-efi --help rc 0" 0 "$RC"
    check "  …its usage on stdout" yes "$(has 'Usage: cyrsign-efi <pe-in> <key.der> <cert.der> <pe-out>' "$T/out")"
    chmod -x "$T/lh/bin/cyrsign-efi"
    lrun sign-efi --help
    check "L3 the helper not executable: rc 127" 127 "$RC"
    check "  …the failed execve named, with its error" yes "$(has "sign-efi: could not run $T/lh/bin/cyrsign-efi (execve error 13)" "$T/err")"
fi

# ── the Windows CLI, under wine ─────────────────────────────────────────────────────────
echo "the Windows CLI (wine — NOT hardware; cass is the cross-OS leg):"
if ! command -v wine > /dev/null 2>&1 || ! command -v winepath > /dev/null 2>&1; then
    echo "  SKIP: wine/winepath not installed — W1-W4 run on real cass only"
    GATE_SKIPS=1
else
    export WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    if ! "$CC" < src/main_win.cyr > "$T/cc_win" 2> "$T/ccw.err"; then
        echo "  FAIL: could not build the PE cross compiler"; grep -E '^error' "$T/ccw.err" | head -3; exit 1
    fi
    chmod +x "$T/cc_win"
    build_pe() {
        if ! "$T/cc_win" < "$1" > "$2" 2> "$T/bp.err" || [ "$(head -c 2 "$2")" != "MZ" ]; then
            echo "  FAIL: could not cross-build $1 for PE"; grep -E '^error' "$T/bp.err" | head -3; fails=$((fails + 1)); return 1
        fi
    }
    mkdir -p "$T/wh/bin" "$T/ww"
    build_pe cbt/cyrius.cyr "$T/wh/bin/cyrius.exe" || exit 1
    build_pe programs/cyrsign-efi.cyr "$T/se.exe" || exit 1
    # The probe that stands in for the helper: 37 when argv = [x, "a b", c]; 40-43 name the miss.
    cat > "$T/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/args.cyr"
fn main(): i64 {
    alloc_init();
    args_init();
    if (argc() != 3) { return 40; }
    if (streq(argv(1), "a b") == 0) { return 41; }
    if (streq(argv(2), "c") == 0) { return 42; }
    return 37;
}
var r = main();
syscall(60, r);
EOF
    build_pe "$T/probe.cyr" "$T/probe.exe" || exit 1
    HW=$(winepath -w "$T/wh" 2> /dev/null)
    check "wine: the staging path translated (floor)" yes "$([ -n "$HW" ] && echo yes || echo no)"
    wrun() { RC=0; ( cd "$T/ww" && CYRIUS_HOME="$HW" timeout 300 wine "$T/wh/bin/cyrius.exe" "$@" > "$T/out" 2> "$T/err" ) || RC=$?; tr -d '\r' < "$T/out" > "$T/out.u"; tr -d '\r' < "$T/err" > "$T/err.u"; }

    cp "$T/se.exe" "$T/wh/bin/cyrsign-efi.exe"
    wrun sign-efi --help
    check "W1 cyrsign-efi.exe beside cyrius.exe: sign-efi --help rc 0 (the filed repro: 127)" 0 "$RC"
    check "  …the helper's usage on stdout" yes "$(has 'Usage: cyrsign-efi <pe-in> <key.der> <cert.der> <pe-out>' "$T/out.u")"
    check "  …and no 'not found' line" no "$(grep -qE 'not found|not installed' "$T/err.u" && echo yes || echo no)"
    wrun sign-efi
    check "W2 no arguments: the helper's own exit code (2)" 2 "$RC"
    check "  …and its own refusal" yes "$(has 'cyrsign-efi: missing required argument' "$T/err.u")"
    cp "$T/probe.exe" "$T/wh/bin/cyrsign-efi.exe"
    wrun sign-efi "a b" c
    check "W3 a probe helper: the tail reaches it whole, its exit code (37) is ours (40-42 a wrong argv)" 37 "$RC"
    rm -f "$T/wh/bin/cyrsign-efi.exe"
    wrun sign-efi --help
    check "W4 no helper: rc 127" 127 "$RC"
    check "  …naming the .exe it looked for" yes "$(grep -qE 'sign-efi: the cyrsign-efi helper is not installed at .*cyrsign-efi\.exe \(' "$T/err.u" && echo yes || echo no)"
    check "  …and the real source" yes "$(has 'programs/cyrsign-efi.cyr' "$T/err.u")"
    check "  …not 'Linux-only'" no "$(has 'Linux-only' "$T/err.u")"
fi

echo ""
if [ "$fails" = "0" ]; then
    # An axis that could not run makes the gate a SKIP (77), never a PASS (6.6.11, K1).
    if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: $NAME — the wine rows could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
    echo "PASS: $NAME — the Linux CLI names a missing / unrunnable helper; cyrius.exe runs cyrsign-efi.exe (usage, its exit codes, the argument tail) and names a missing one"
    exit 0
fi
echo "FAIL: $NAME — $fails assertion(s) failed"
exit 1
