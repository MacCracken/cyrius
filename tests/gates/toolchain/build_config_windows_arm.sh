#!/bin/sh
# build_config_windows_arm.sh — 6.6.17 (P1 item 1, the PE arm). On Windows the resolved `[build]
# dce` reaches the compiler, and a `--strict` argument is passed through as on POSIX.
#
# WHY: Win32 has no fork/execve, so compile()'s Windows arm hands `cmd /s /c "cc" < src > out` to
# CreateProcessW — and that arm passed NEITHER: no CYRIUS_DCE in the child's environment (POSIX
# appends it to envp), no `--strict` on the command line (POSIX puts it in argv). `[build] dce`
# would have been inert on cyrius.exe. (`--strict` has had no effect in cycc since 6.3.2; it is
# passed through for parity, and `[build] strict` is held — see build_config_precedence.sh.)
#
# HOW: a STUB compiler (a PE program standing in for cycc.exe) writes the command line it was
# started with (GetCommandLineW) and the CYRIUS_DCE it inherited (GetEnvironmentVariableA) to a
# log; the tree's cyrius.exe runs it under a PRIVATE wine prefix.
#   axis 1  [build] dce = true + `cyrius build --strict` -> the stub sees `--strict` and
#           CYRIUS_DCE=1.
#   axis 2  (anti-vacuous) neither -> no `--strict`, CYRIUS_DCE unset.
# wine is not hardware: the release gate's cass leg is the verification on real Windows.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: build_config_windows_arm: no compiler at $CC"; exit 77; }
command -v wine >/dev/null 2>&1 || { echo "SKIP: build_config_windows_arm: needs wine (exit 77: a SKIP, not a PASS)"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: build_config_windows_arm: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
WP="$W/wine"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$W"' EXIT
export WINEPREFIX="$WP" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }

"$CC" < src/main_win.cyr > "$W/cc_win" 2>/dev/null && chmod +x "$W/cc_win" \
    || { echo "FAIL: build_config_windows_arm: could not build the PE cross compiler"; exit 1; }
mkdir -p "$W/home/bin" "$W/p/src"
"$W/cc_win" < cbt/cyrius.cyr > "$W/home/bin/cyrius.exe" 2>/dev/null && [ -s "$W/home/bin/cyrius.exe" ] \
    || { echo "FAIL: build_config_windows_arm: cbt/cyrius.cyr does not build for PE"; exit 1; }
wine cmd /c exit 0 > /dev/null 2>&1 || true            # create the prefix before winepath needs it
LOGW=$(winepath -w "$W/stub.log" 2>/dev/null)
[ -n "$LOGW" ] || { echo "FAIL: build_config_windows_arm: winepath could not map the log path"; exit 1; }
LOGC=$(printf '%s' "$LOGW" | sed 's/\\/\\\\/g')
cat > "$W/stub.cyr" <<CYR
include "lib/io.cyr"
fn main(): i64 {
    alloc_init();
    var out = alloc(9000);
    var o = 0;
    var cl = syscall(61446);                   # GetCommandLineW (UTF-16LE)
    var i = 0;
    while (o < 8000) {
        if (load8(cl + i) == 0 && load8(cl + i + 1) == 0) { break; }
        store8(out + o, load8(cl + i));
        o = o + 1;
        i = i + 2;
    }
    memcpy(out + o, "\ndce=", 5);
    o = o + 5;
    var eb = alloc(600);
    var n = syscall(0xF015, "CYRIUS_DCE", eb, 512);   # GetEnvironmentVariableA
    if (n == 0) { memcpy(out + o, "unset", 5); o = o + 5; }
    else { memcpy(out + o, eb, n); o = o + n; }
    store8(out + o, 10);
    o = o + 1;
    file_write_all("$LOGC", out, o);
    return 0;
}
var r = main();
syscall(60, r);
CYR
"$W/cc_win" < "$W/stub.cyr" > "$W/home/bin/cycc.exe" 2> "$W/stub.err" && [ -s "$W/home/bin/cycc.exe" ] \
    || { echo "FAIL: build_config_windows_arm: the stub compiler does not build:"; tail -3 "$W/stub.err"; exit 1; }
printf 'fn main(): i64 { return 0; }\nvar r = main();\n' > "$W/p/src/main.cyr"
run() {   # run <extra [build] lines> [cli args...]
    m=$1; shift
    printf '[package]\nname = "p"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/p.exe"\n%b' "$m" > "$W/p/cyrius.cyml"
    rm -f "$W/stub.log"
    ( cd "$W/p" && env -u CYRIUS_DCE -u CYRIUS_STRICT CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 timeout 300 wine "$W/home/bin/cyrius.exe" build "$@" ) > "$W/out" 2>&1 || true
    [ -f "$W/stub.log" ] || { fail "the stub compiler never ran: $(head -3 "$W/out" | tr '\n' ' ')"; return 1; }
    return 0
}

if run 'dce = true\n' --strict; then
    grep -q ' --strict' "$W/stub.log" || fail "axis 1: cyrius build --strict did not put --strict on cycc.exe's command line: $(head -1 "$W/stub.log")"
    grep -qx 'dce=1' "$W/stub.log" || fail "axis 1: [build] dce = true did not reach cycc.exe as CYRIUS_DCE=1: $(tail -1 "$W/stub.log")"
fi
[ "$FAIL" = 0 ] && echo "  ok axis 1: [build] dce and --strict reach cycc.exe (CYRIUS_DCE=1 in its environment, --strict on its command line)"
x=$FAIL
if run ''; then
    grep -q ' --strict' "$W/stub.log" && fail "axis 2: --strict reached cycc.exe with no strict configured"
    grep -qx 'dce=unset' "$W/stub.log" || fail "axis 2: CYRIUS_DCE reached cycc.exe with no dce configured: $(tail -1 "$W/stub.log")"
fi
[ "$FAIL" = "$x" ] && echo "  ok axis 2: with neither configured, cycc.exe sees no --strict and no CYRIUS_DCE"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: build_config_windows_arm (dce and --strict reach the compiler on the PE arm, under wine)"
