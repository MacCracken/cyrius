#!/bin/sh
# Gate: a malformed `[package].cyrius` pin is REFUSED by name — never joined into a path, never
# executed, never read as "no pin" (6.6.20, CVE-TBD).
#
# THE BUG. `_try_redirect_to_pinned` (cbt/cyrius.cyr) built `<home>/versions/<pin>/bin/cyrius`
# from the raw manifest value and execve'd it before any verb ran; the only check was
# file_exists. A cloned repo that ships an executable `payload/bin/cyrius` and pins
#     cyrius = "../../(...)/proc/self/cwd/payload"
# had its payload run by `cyrius version`, fmt, lint, build, deps — every verb, a bare `cyrius`
# too — verbs that never run repository code. A home-relative pin needs no /proc (so it works
# on macOS), and on Windows a backslash spelling did the same through `_win_redirect_to_pinned`.
# The same value was joined into `<home>/versions/<pin>/...` at six more sites, all reachable
# under the documented CYRIUS_RESOLVED=1 (which skips the redirect): `lib sync` copied from the
# traversed directory into ./lib, `deps` vendored from it and wrote it into cyrius.lock, both
# distlib resolvers, the lib-freshness check — and `--version` / `build --print-config` printed
# it raw, terminal escapes included.
#
# THE FIX. The one reader, `_dep_read_cyml_cyrius_field` (cbt/deps.cyr), refuses a pin that is
# not a version's shape — a leading digit, then only [0-9A-Za-z._-], no `..` — and a present
# pin that is not a string, by name, exit 1. `build --print-config` routes the pin through it.
#
# AXES (Linux; the CLI is built from THIS tree with build/cycc, a throwaway HOME / CYRIUS_HOME)
#   1  /proc/self/cwd traversal: version, --version, build, lint, deps, fmt, bare -> exit 1,
#      named, the repo's payload never runs
#   2  a home-relative traversal (no /proc) and the backslash spelling -> refused, no payload
#   3  CYRIUS_RESOLVED=1 (the redirect skipped): lib sync, deps, version, build --print-config
#      -> refused; nothing copied into lib/, no cyrius.lock, the pin never printed raw
#   4  other malformed shapes: `..`, `v6.6.20`, "", `6.6.20/../x`, an escape byte, an unquoted
#      pin -> refused (the escape shown as \x1b), never read as "no pin"
#   5  controls: no pin and pin == VERSION run; a well-formed absent pin (`_` included) gets the
#      existing "not installed" error, not the shape refusal; a well-formed INSTALLED pin still
#      redirects
#   6  PE (wine): cyrius.exe with a forward-slash and a backslash traversal pin -> refused, the
#      payload .exe never runs; control: a well-formed installed pin still redirects (exit 37).
#      Announced SKIPPED without wine — the cass leg of the release gate is the hardware run.
#
# MUTATION LEDGER (2026-10-06, 6.6.20, wine present): reverting `_dep_read_cyml_cyrius_field` to
# the bare `_mf_str` read turns axes 1, 2, 3, 4 and 6 RED (the payload runs on every verb, exit 37
# under wine; lib sync and deps copy the sentinel into lib/, the lock records `../../snap`, the
# escape byte reaches the terminal); dropping only the `..` test turns the `6..6` row RED (`..`
# alone and `6.6.20/../x` are also caught by the leading-digit and `/` rules); dropping only the
# `_toml_bad` branch turns the unquoted-pin row RED; dropping the --print-config routing in
# `_cfg_resolve_build` turns axis 3's --print-config row RED.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=manifest_pin_shape_refused
VER=$(tr -d '[:space:]' < "$ROOT/VERSION")

[ -x "$CC" ] || { echo "SKIP: $NAME — $CC missing"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
WP="$W/pe/wine"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$W"' EXIT
fail=0
bad() { echo "  FAIL $1"; sed -n '1,4p' "$W/out" 2>/dev/null | sed 's/^/    /'; fail=1; }

# The CLI from THIS tree — never build/cyrius or the store, either of which can be stale.
( cd "$ROOT" && "$CC" < cbt/cyrius.cyr > "$W/cyrius" 2>/dev/null ) && chmod +x "$W/cyrius" \
    || { echo "FAIL: $NAME — could not build the CLI from cbt/cyrius.cyr"; exit 1; }
CLI="$W/cyrius"
H="$W/home/.cyrius"
mkdir -p "$H/versions" "$W/proj/src"
echo 'fn main(): i64 { return 0; }' > "$W/proj/src/main.cyr"

# The payload a hostile checkout ships: it leaves a marker, so "it ran" never depends on output.
mkpayload() {  # mkpayload <dir>
    mkdir -p "$1/bin"
    printf '#!/bin/sh\necho ran >> "%s"\necho "PWNED: $*"\nexit 0\n' "$W/pwned" > "$1/bin/cyrius"
    chmod +x "$1/bin/cyrius"
}
mkpayload "$W/proj/payload"
mkpayload "$W/home/evil/payload"

pin() {  # pin <raw TOML value, quotes included>
    printf '[package]\nname = "pinprobe"\nversion = "0.1.0"\ncyrius = %s\n' "$1" > "$W/proj/cyrius.cyml"
}
nopin() { printf '[package]\nname = "pinprobe"\nversion = "0.1.0"\n' > "$W/proj/cyrius.cyml"; }
run() {  # run <resolved 0|1> <args...> -> RC, $W/out (stdout + stderr), $W/stdout
    _r=$1; shift
    RC=0
    if [ "$_r" = 1 ]; then
        ( cd "$W/proj" && env -u CYRIUS_RESOLVED HOME="$W/home" CYRIUS_HOME="$H" CYRIUS_RESOLVED=1 "$CLI" "$@" ) > "$W/stdout" 2> "$W/stderr" || RC=$?
    else
        ( cd "$W/proj" && env -u CYRIUS_RESOLVED HOME="$W/home" CYRIUS_HOME="$H" "$CLI" "$@" ) > "$W/stdout" 2> "$W/stderr" || RC=$?
    fi
    cat "$W/stdout" "$W/stderr" > "$W/out"
}
refused() {  # refused <label> -> the run exited 1 with the shape refusal and no payload ran
    if [ "$RC" -eq 1 ] && grep -q "is not a version" "$W/stderr" && [ ! -e "$W/pwned" ]; then
        return 0
    fi
    [ -e "$W/pwned" ] && echo "  (the repo's payload RAN: $(wc -l < "$W/pwned" | tr -d ' ') time(s))"
    bad "$1: exit $RC, expected 1 and 'is not a version'"
    rm -f "$W/pwned"
    return 1
}

# ── axis 1: /proc/self/cwd traversal, every verb ──────────────────────────────────────────
if [ -d /proc/self/cwd ]; then
    UP=$(printf '../%.0s' $(seq 1 48))
    pin "\"${UP}proc/self/cwd/payload\""
    a1=0
    for v in version --version build lint deps "fmt src/main.cyr" ""; do
        # shellcheck disable=SC2086 — the verb row is word-split on purpose; "" is a bare `cyrius`
        run 0 $v
        refused "axis 1 ($v)" || a1=1
    done
    [ "$a1" -eq 0 ] && echo "  ok axis 1: a /proc/self/cwd traversal pin is refused on every verb; the payload never ran"
else
    echo "  axis 1 SKIPPED: no /proc/self/cwd on this host (axis 2's home-relative pin covers the shape)"
fi

# ── axis 2: home-relative traversal (no /proc needed) + the backslash spelling ──────────────
pin '"../../evil/payload"'
run 0 build
a2=0; refused "axis 2 (../../evil/payload, build)" || a2=1
pin '"..\\..\\evil\\payload"'
run 0 lint
refused "axis 2 (backslash spelling, lint)" || a2=1
[ "$a2" -eq 0 ] && echo "  ok axis 2: a home-relative and a backslash traversal pin are refused"

# ── axis 3: CYRIUS_RESOLVED=1 — the redirect is skipped, the siblings must refuse too ──────
mkdir -p "$W/home/snap/lib"
for m in syscalls alloc io vec string; do echo "# SENTINEL $m" > "$W/home/snap/lib/$m.cyr"; done
printf '[package]\nname = "pinprobe"\nversion = "0.1.0"\ncyrius = "../../snap"\n[deps]\nstdlib = ["alloc"]\n' > "$W/proj/cyrius.cyml"
a3=0
for v in "lib sync" deps; do
    rm -rf "$W/proj/lib" "$W/proj/cyrius.lock"; mkdir -p "$W/proj/lib"
    # shellcheck disable=SC2086
    run 1 $v
    refused "axis 3 ($v)" || a3=1
    if [ -n "$(ls "$W/proj/lib")" ]; then bad "axis 3 ($v): copied into lib/ from the traversed dir: $(ls "$W/proj/lib" | tr '\n' ' ')"; a3=1; fi
    if [ -e "$W/proj/cyrius.lock" ]; then bad "axis 3 ($v): wrote cyrius.lock: $(tail -1 "$W/proj/cyrius.lock")"; a3=1; fi
done
rm -rf "$W/proj/lib"
run 1 version
refused "axis 3 (version)" || a3=1
if grep -q "manifest-pin:" "$W/stdout"; then bad "axis 3 (version): printed the traversal pin as a manifest-pin line"; a3=1; fi
run 1 build --print-config
refused "axis 3 (build --print-config)" || a3=1
if grep -q "package.cyrius = " "$W/stdout"; then bad "axis 3 (build --print-config): printed the traversal pin raw"; a3=1; fi
[ "$a3" -eq 0 ] && echo "  ok axis 3: under CYRIUS_RESOLVED=1 lib sync, deps, version and --print-config refuse; nothing copied, no lock"

# ── axis 4: other malformed shapes, and an unquoted pin is not "no pin" ────────────────────
a4=0
for p in '".."' '"6..6"' '"v6.6.20"' '""' '"6.6.20/../x"' '"6.6.20 "'; do
    pin "$p"
    run 0 version
    refused "axis 4 (cyrius = $p)" || a4=1
done
pin "\"6.6$(printf '\033')[31mRED\""
run 0 version
refused "axis 4 (an escape byte)" || a4=1
if grep -q "$(printf '\033')" "$W/out"; then bad "axis 4: the refusal echoed a raw ESC byte"; a4=1; fi
grep -q '\\x1b' "$W/stderr" || { bad "axis 4: the escape byte was not shown as \\x1b"; a4=1; }
pin "$VER"
run 0 version
if [ "$RC" -eq 1 ] && grep -q "must be a quoted version string" "$W/stderr"; then :; else
    bad "axis 4 (unquoted cyrius = $VER): exit $RC — a pin that is present but not a string was read as 'no pin'"; a4=1
fi
[ "$a4" -eq 0 ] && echo "  ok axis 4: '..', '6..6', 'v6.6.20', '', a '/', a space, an escape byte and an unquoted pin are refused"

# ── axis 5: controls — well-formed pins keep working ──────────────────────────────────────
a5=0
nopin
run 0 version
[ "$RC" -eq 0 ] || { bad "axis 5 (no pin): exit $RC"; a5=1; }
pin "\"$VER\""
run 0 version
{ [ "$RC" -eq 0 ] && grep -q "^manifest-pin: $VER\$" "$W/stdout"; } || { bad "axis 5 (pin == VERSION): exit $RC"; a5=1; }
pin '"0.0.1-absent_rc"'
run 0 version
{ [ "$RC" -eq 1 ] && grep -q "but cyrius binary is not installed" "$W/stderr" && ! grep -q "is not a version" "$W/stderr"; } \
    || { bad "axis 5 (well-formed absent pin): exit $RC, expected the existing 'not installed' error"; a5=1; }
mkdir -p "$H/versions/9.9.9/bin"
printf '#!/bin/sh\necho "REDIRECTED-9.9.9 $*"\nexit 0\n' > "$H/versions/9.9.9/bin/cyrius"
chmod +x "$H/versions/9.9.9/bin/cyrius"
pin '"9.9.9"'
run 0 version
{ [ "$RC" -eq 0 ] && grep -q "^REDIRECTED-9.9.9 version\$" "$W/stdout"; } || { bad "axis 5 (installed pin 9.9.9): exit $RC, the redirect did not run"; a5=1; }
[ "$a5" -eq 0 ] && echo "  ok axis 5: no pin, pin == VERSION, a well-formed absent pin and an installed pin behave as before"

# ── axis 6: PE — cyrius.exe under wine ────────────────────────────────────────────────────
if ! command -v wine >/dev/null 2>&1 || ! command -v winepath >/dev/null 2>&1; then
    echo "  axis 6 SKIPPED: wine not installed (the cass leg of the release gate runs the PE CLI on hardware)"
else
    export WINEPREFIX="$WP" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    PH="$W/pe/home"; mkdir -p "$PH/.cyrius/versions" "$W/pe/proj" "$W/pe/whome"
    a6=0
    if ! ( cd "$ROOT" && "$CC" < src/main_win.cyr > "$W/pe/cc_win" 2>/dev/null && chmod +x "$W/pe/cc_win" \
            && "$W/pe/cc_win" < cbt/cyrius.cyr > "$W/pe/cyrius.exe" 2>/dev/null ); then
        echo "  FAIL axis 6: could not build cyrius.exe from cbt/cyrius.cyr"; fail=1; a6=1
    else
        printf 'fn main(): i64 { return 37; }\nvar r = main();\nsyscall(60, r);\n' > "$W/pe/probe.cyr"
        ( cd "$ROOT" && "$W/pe/cc_win" < "$W/pe/probe.cyr" > "$W/pe/probe.exe" 2>/dev/null ) \
            || { echo "  FAIL axis 6: could not build the PE probe"; fail=1; a6=1; }
    fi
    if [ "$a6" -eq 0 ]; then
        mkdir -p "$W/pe/evil/payload/bin" "$PH/.cyrius/versions/9.9.9/bin"
        cp "$W/pe/probe.exe" "$W/pe/evil/payload/bin/cyrius.exe"
        cp "$W/pe/probe.exe" "$PH/.cyrius/versions/9.9.9/bin/cyrius.exe"
        HW=$(winepath -w "$PH/.cyrius" 2>/dev/null)
        pe_run() {  # pe_run <raw TOML pin> <verb> -> RC, $W/out
            printf '[package]\nname = "pinprobe"\nversion = "0.1.0"\ncyrius = %s\n' "$1" > "$W/pe/proj/cyrius.cyml"
            RC=0
            ( cd "$W/pe/proj" && env -u CYRIUS_RESOLVED HOME="$W/pe/whome" XDG_CACHE_HOME="$W/pe/whome/.cache" \
                CYRIUS_HOME="$HW" timeout 120 wine "$W/pe/cyrius.exe" "$2" ) > "$W/out" 2>&1 || RC=$?
        }
        # versions\..\..\.. from <pe>/home/.cyrius is <pe>: the payload sits at <pe>/evil/payload
        pe_run '"../../../evil/payload"' version
        { [ "$RC" -eq 1 ] && grep -q "is not a version" "$W/out"; } \
            || { bad "axis 6 (PE, ../../../evil/payload): exit $RC (37 = the payload ran)"; a6=1; }
        pe_run '"..\\..\\..\\evil\\payload"' lint
        { [ "$RC" -eq 1 ] && grep -q "is not a version" "$W/out"; } \
            || { bad "axis 6 (PE, backslash spelling): exit $RC (37 = the payload ran)"; a6=1; }
        pe_run '"9.9.9"' version
        [ "$RC" -eq 37 ] || { bad "axis 6 (PE control, installed 9.9.9): exit $RC, expected the probe's 37"; a6=1; }
        [ "$a6" -eq 0 ] && echo "  ok axis 6: cyrius.exe refuses a forward-slash and a backslash traversal pin; a well-formed pin still redirects"
    fi
fi

[ "$fail" -eq 0 ] || { echo "FAIL: $NAME"; exit 1; }
echo "PASS: $NAME (a [package].cyrius pin that is not a version's shape is refused by name — at the redirect, under CYRIUS_RESOLVED=1, and on PE)"
