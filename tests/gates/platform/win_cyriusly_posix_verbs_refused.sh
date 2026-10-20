#!/bin/sh
# tests/gates/platform/win_cyriusly_posix_verbs_refused.sh — 6.7.16 (6.7.16's D84)
#
# The Windows cyriusly.exe refuses its POSIX verbs BY NAME, before any output or change, and its
# own verbs keep working.
#
# THE DEFECT (issues/2026-10-19-windows-tarball-ships-cyriusly-whose-verbs-run-bin-sh.md). The
# Windows tarball ships cyriusly.exe since 6.7.16 (it is one of cyrius.cyml's [release] bins), and
# install / update / setup / uninstall / cmdtools run /bin/sh, curl and rm, while `use --global`
# re-points <home>\bin and <home>\lib as links where install.ps1 makes copies. Measured on cass:
# `install 6.7.15` printed "Installing Cyrius 6.7.15..." and exited -1 with no reason, `update`
# printed "Checking for updates..." and a cmd.exe error (rc 255), `uninstall 6.7.14` printed
# "rm -rf failed" with the version still there, `cmdtools list` refused every Windows home as
# "not an absolute path", and `use 6.7.14 --global` failed yet left a bin.cyrtmp.<pid>.<n>
# directory link behind (under wine it reached the HOST's /bin/sh, or "succeeded" and mangled the
# store). The user's decision, 6.7.16's D84 (2026-10-20): ship it; those verbs refuse by name —
# `install` says it is not available on Windows and to install with install.ps1 -Tarball …, exit
# 1; update, setup, uninstall, cmdtools and use --global the same, before touching anything;
# list, version, use <v> (the project pin), --help and --version keep working.
#
# AXES
#   S   STATIC, derived: every `_cmd_*` fn in programs/cyriusly.cyr that reaches a POSIX shell or a
#       link switch (`_cy_run_argv(`, `_exec_shell(`, `_relink_atomic(`) has an
#       `#ifdef CYRIUS_TARGET_WIN` arm calling `_cy_win_refuse(` BEFORE its first such call. A new
#       shell-backed verb cannot ship without one. Anti-vacuous: the scan finds >= 5 such fns, and
#       a synthetic fn with the call and no arm is reported.
#   R1-R6  (wine) install / update / setup / uninstall / cmdtools / use --global: rc 1, the named
#       `cyriusly: <verb> is not available on Windows:` line, nothing on stdout (no "Installing",
#       no "Checking for updates"), the store byte-for-byte as it was (versions\, current, bin\ —
#       a real directory, install.ps1's copy layout — no *.cyrtmp*). install / use --global name
#       the install.ps1 command for THAT version; uninstall the directory to remove.
#   G   the guards before the refusal still answer first: a path-shaped version is "not a version"
#       (RS-04), the active version "Cannot uninstall", a version not installed "not installed"
#       (rc 0, as on POSIX).
#   K1-K6  (wine) list, version, use <v> (the cyrius.cyml pin, written), --help (with the Windows
#       note), --version: rc 0; `use <v>` of a version not installed and `list` of an empty store
#       name install.ps1, never `cyriusly install`.
#   L   STATIC: `_relink_atomic` / `_undo_relink` remove a link only through `_cy_remove_link`,
#       which falls back to RemoveDirectoryW on Windows — a link to a directory is a directory
#       entry DeleteFileW refuses, so a failed switch left its bin.cyrtmp temp link (measured on
#       cass). wine cannot show it; the cass leg runs the extracted fn (_co_relink_probe).
#   wine is NOT hardware: without it the wine axes are a named SKIP (exit 77); the cass leg of
#   scripts/cross-os-selfhost.sh runs R1-R6 and K1-K2 on real Windows.
#
# MUTATION (6.7.16, measured): the tree before the fix -> RED 28 rows: S (6 verbs UNARMED), R1-R6
# (under wine install rc 255 with "Installing Cyrius 6.7.15..." — it reached the HOST's /bin/sh —
# update rc 255, use --global rc 0 with the store changed), and the rows after R6 that read the
# store it changed, plus K4-K6 (the hints named `cyriusly install`, the help had no Windows note);
# install's arm alone removed -> RED S, R1 (5 rows); use --global's arm alone removed -> RED S, R6,
# R6b and the store rows after them (13 rows).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=win_cyriusly_posix_verbs_refused
SRC=programs/cyriusly.cyr
[ -x "$CC" ] || { echo "FAIL: $NAME — $CC not built"; exit 1; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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

# ── axis S — every shell-backed or link-switching verb has a Windows refusal first ─────────
echo "axis S — every _cmd_* fn that reaches /bin/sh or a link switch refuses on Windows first:"
cat > "$T/s.awk" <<'AWK'
function flush() {
    if (fname ~ /^_cmd_/ && first > 0) {
        v = "UNARMED"
        if (armline > 0 && armline < first) { v = "ok" }
        printf "%s %s\n", fname, v
    }
    fname = ""; first = 0; armline = 0; inwin = 0; winref = 0
}
/^fn [A-Za-z_]/ { flush(); fname = $2; sub(/\(.*/, "", fname) }
{
    code = $0
    gsub(/"[^"]*"/, "", code)
    if (code !~ /^[ \t]*#(ifdef|ifndef|endif|else)/) { sub(/#.*/, "", code) }
}
code ~ /^[ \t]*#ifdef[ \t]+CYRIUS_TARGET_WIN([ \t]|$)/ { inwin = 1; winref = 0; next }
code ~ /^[ \t]*#endif/ { if (inwin == 1 && winref == 1 && armline == 0) { armline = FNR }; inwin = 0; next }
inwin == 1 { if (code ~ /_cy_win_refuse\(/) { winref = 1 }; next }
code ~ /(_cy_run_argv|_exec_shell|_relink_atomic)\(/ && code !~ /^fn / { if (first == 0) { first = FNR } }
END { flush() }
AWK
awk -f "$T/s.awk" "$SRC" > "$T/s.out"
NS=$(grep -c . "$T/s.out" || true)
check "the scan finds the shell-backed / link-switching verbs (floor 5, found $NS)" yes "$([ "$NS" -ge 5 ] && echo yes || echo no)"
if grep -q ' UNARMED' "$T/s.out"; then echo "  verbs with no Windows refusal before their shell / link call:"; grep ' UNARMED' "$T/s.out" | sed 's/^/    /'; fi
check "every one refuses on Windows before the call" 0 "$(grep -c ' UNARMED' "$T/s.out" || true)"
cat > "$T/s_self.cyr" <<'EOF'
fn _cmd_armed(): i64 {
    #ifdef CYRIUS_TARGET_WIN
    return _cy_win_refuse("armed", "x");
    #endif
    return _cy_run_argv(0);
}
fn _cmd_bare(): i64 {
    return _exec_shell("x");
}
fn _cmd_late(): i64 {
    var r = _relink_atomic(a, b);
    #ifdef CYRIUS_TARGET_WIN
    return _cy_win_refuse("late", "x");
    #endif
    return r;
}
EOF
awk -f "$T/s.awk" "$T/s_self.cyr" > "$T/s_self.out"
check "  ⭐ ANTI-VACUOUS: a verb with no arm is reported" yes "$(grep -qx '_cmd_bare UNARMED' "$T/s_self.out" && echo yes || echo no)"
check "  …and one whose arm comes AFTER the call" yes "$(grep -qx '_cmd_late UNARMED' "$T/s_self.out" && echo yes || echo no)"
check "  …and an armed one is cleared" yes "$(grep -qx '_cmd_armed ok' "$T/s_self.out" && echo yes || echo no)"

# ── axis L — a link this file removes is removed as a LINK on Windows too (static) ──────────
# `_relink_atomic` removed its temp with sys_unlink alone; on Windows a link to a directory is a
# directory entry DeleteFileW refuses, so a failed switch left bin.cyrtmp.<pid>.<n> behind while
# saying "nothing was changed" (measured on cass). Static here because wine cannot show it (its
# rename of a link over a directory succeeds); the cass leg runs the extracted fn on hardware.
echo "axis L — the link removals go through _cy_remove_link, which removes a directory link on Windows:"
fnbody() { awk -v f="$1" '$0 ~ "^fn " f "\\(" {p=1} p {print} p && /^}/ {exit}' "$SRC"; }
for f in _relink_atomic _undo_relink; do
    b=$(fnbody "$f")
    check "$f: no bare sys_unlink / xunlink" 0 "$(printf '%s\n' "$b" | grep -cE '(sys_unlink|xunlink)\(' || true)"
    check "  …it removes through _cy_remove_link" yes "$(printf '%s\n' "$b" | grep -q '_cy_remove_link(' && echo yes || echo no)"
done
rl=$(fnbody _cy_remove_link)
check "_cy_remove_link falls back to sys_rmdir under CYRIUS_TARGET_WIN" yes \
    "$(printf '%s\n' "$rl" | awk '/#ifdef CYRIUS_TARGET_WIN/{w=1} w && /sys_rmdir\(/{f=1} /#endif/{w=0} END{print (f ? "yes" : "no")}')"

# ── the wine axes ────────────────────────────────────────────────────────────────────────
echo "the Windows cyriusly.exe (wine — NOT hardware; cass is the cross-OS leg):"
if ! command -v wine > /dev/null 2>&1 || ! command -v winepath > /dev/null 2>&1; then
    echo "  SKIP: wine/winepath not installed — R / G / K run on real cass only"
    GATE_SKIPS=1
else
    export WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    # What scripts/release-bins.sh builds for the Windows tarball.
    if ! CYRIUS_TARGET_WIN=1 "$CC" < "$SRC" > "$T/cyriusly.exe" 2> "$T/cy.err" || [ "$(head -c 2 "$T/cyriusly.exe")" != "MZ" ]; then
        echo "  FAIL: could not build $SRC for PE"; grep -E '^error' "$T/cy.err" | head -3; exit 1
    fi
    # The store install.ps1 makes: versions\<v>\{bin,lib}, current, and bin\ / lib\ as real
    # directories holding a COPY of the active version.
    stage() {
        rm -rf "$T/ch" "$T/w" && mkdir -p "$T/ch/versions/6.7.14/bin" "$T/ch/versions/6.7.14/lib" \
            "$T/ch/versions/6.7.15/bin" "$T/ch/versions/6.7.15/lib" "$T/ch/bin" "$T/ch/lib" "$T/w"
        printf '6.7.15' > "$T/ch/current"
        printf 'x' > "$T/ch/bin/cycc.exe"
    }
    snap() { ( cd "$T/ch" && find . | LC_ALL=C sort && cat current ) > "$1"; }
    stage
    snap "$T/snap0"
    CH=$(winepath -w "$T/ch" 2> /dev/null)
    check "wine: the staging path translated (floor)" yes "$([ -n "$CH" ] && echo yes || echo no)"
    wrun() { RC=0; ( cd "$T/w" && CYRIUS_HOME="$CH" timeout 300 wine "$T/cyriusly.exe" "$@" > "$T/out" 2> "$T/err" ) || RC=$?; tr -d '\r' < "$T/out" > "$T/out.u"; tr -d '\r' < "$T/err" > "$T/err.u"; }
    unchanged() { snap "$T/snapN"; cmp -s "$T/snap0" "$T/snapN" && echo yes || echo no; }
    refused() {   # $1 label, $2 verb as named, then the cyriusly arguments
        lab=$1; vb=$2; shift 2
        wrun "$@"
        check "$lab $*: rc 1" 1 "$RC"
        check "  …named: 'cyriusly: $vb is not available on Windows:'" yes "$(has "cyriusly: $vb is not available on Windows: " "$T/err.u")"
        check "  …nothing on stdout" 0 "$(wc -c < "$T/out.u" | tr -d ' ')"
        check "  …the store as it was (no *.cyrtmp*, versions, current, bin\\ untouched)" yes "$(unchanged)"
    }
    refused R1 install install 6.7.15
    check "  …the install.ps1 command for 6.7.15" yes "$(has 'powershell -ExecutionPolicy Bypass -File install.ps1 -Tarball cyrius-6.7.15-x86_64-windows.tar.gz' "$T/err.u")"
    refused R2 update update
    refused R3 setup setup
    refused R4 uninstall uninstall 6.7.14
    check "  …naming the directory to remove" yes "$(grep -qE 'rmdir /s /q ".*\\versions\\6\.7\.14"$' "$T/err.u" && echo yes || echo no)"
    refused R5 cmdtools cmdtools list
    refused R6 "use --global" use 6.7.14 --global
    check "  …the install.ps1 command that activates 6.7.14" yes "$(has 'install.ps1 -Tarball cyrius-6.7.14-x86_64-windows.tar.gz' "$T/err.u")"
    refused R6b "use --global" use --global 6.7.14

    wrun install ../versions
    check "G1 install ../versions: still 'not a version' first, rc 1" "1 yes" "$RC $(has 'cyriusly: not a version: ' "$T/err.u")"
    wrun uninstall 6.7.15
    check "G2 uninstall of the ACTIVE 6.7.15: still refused as active, rc 1" "1 yes" "$RC $(has 'Cannot uninstall active version' "$T/err.u")"
    wrun uninstall 9.9.9
    check "G3 uninstall 9.9.9 (not installed): 'not installed', rc 0" "0 yes" "$RC $(has 'Version 9.9.9 not installed.' "$T/out.u")"
    check "  …and the store as it was" yes "$(unchanged)"

    wrun list
    check "K1 list: rc 0" 0 "$RC"
    check "  …both versions, 6.7.15 active" yes "$(grep -qx '    6.7.14' "$T/out.u" && grep -qx '  \* 6.7.15 (active)' "$T/out.u" && echo yes || echo no)"
    wrun version
    check "K2 version: rc 0, 'cyriusly 6.7.15'" "0 yes" "$RC $(grep -qx 'cyriusly 6.7.15' "$T/out.u" && echo yes || echo no)"
    printf '[package]\nname = "p"\nversion = "0.1.0"\n' > "$T/w/cyrius.cyml"
    wrun use 6.7.14
    check "K3 use 6.7.14 (the project pin): rc 0" 0 "$RC"
    check "  …cyrius.cyml pinned" yes "$(grep -qx 'cyrius = "6.7.14"' "$T/w/cyrius.cyml" && echo yes || echo no)"
    check "  …and the store as it was" yes "$(unchanged)"
    wrun use 9.9.9
    check "K4 use 9.9.9 (not installed): rc 1, install.ps1 named" "1 yes" "$RC $(has 'install.ps1 -Tarball cyrius-9.9.9-x86_64-windows.tar.gz' "$T/err.u")"
    check "  …never 'run: cyriusly install'" no "$(has 'run: cyriusly install' "$T/err.u")"
    wrun --help
    check "K5 --help: rc 0 and the Windows note" "0 yes" "$RC $(has 'On Windows, install, update, setup, uninstall, cmdtools and use --global are not' "$T/out.u")"
    wrun --version
    check "K5b --version: rc 0" 0 "$RC"
    rm -rf "$T/ch/versions"/*
    wrun list
    check "K6 list of an empty store: rc 0, install.ps1 named (not 'cyriusly install')" "0 yes no" "$RC $(has 'install a release with install.ps1' "$T/out.u") $(has 'cyriusly install' "$T/out.u")"
fi

echo ""
if [ "$fails" = "0" ]; then
    if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: $NAME — the wine axes could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
    echo "PASS: $NAME — $NS shell-backed / link-switching verbs refuse by name on Windows with nothing changed; list, version, use <v>, --help, --version work"
    exit 0
fi
echo "FAIL: $NAME — $fails assertion(s) failed"
exit 1
