#!/bin/sh
# build_config_windows_arm.sh — 6.6.17 (P1 item 1, the PE arm). On Windows the resolved `[build]
# dce` reaches the compiler, and the flags the POSIX arm puts in argv (`--strict`,
# `--allow-undef`, `--syntax-only`) go on cycc.exe's command line.
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
#   axis 2  (anti-vacuous) a plain build -> no `--strict` / `--allow-undef` / `--syntax-only`,
#           CYRIUS_DCE unset.
#   axis 3  `cyrius lint f.cyr` -> its syntax pre-pass hands cycc.exe `--allow-undef` and
#           `--syntax-only`, as the POSIX argv does (6.6.17 review: the PE arm dropped both).
#   axis 4  `cyrius distlib` on cyrius.exe REFUSES by name before any compile, and writes no
#           sidecar. ⚠ 6.6.18 (D4): this axis read "the bundle self-check hands cycc.exe
#           `--allow-undef` only", reached through the one path that let a non-x86-Linux CLI
#           finish distlib — a snapshot-less run, where the verify was SKIPPED and the sidecar
#           published unverified. The verify is the sidecar's only authority now, so that path
#           refuses ("no stdlib snapshot"), and with a snapshot the 6.6.11 per-target refusal
#           applies; the self-check is unreachable on PE. `--allow-undef` on the PE arm is
#           still pinned by axis 3 (lint's pre-pass).
#   axis 6  (6.7.8, C2-7) `--bounds` -> the stub sees CYRIUS_BOUNDS=1; `[build] bounds = false` -> 0
#           (a manifest false must beat the entry's `#bounds`); axis 2 also asserts it unset.
#   axis 7  (6.7.8) the PE arm hands cycc.exe EVERY compiler flag the POSIX arm injects, from the same
#           list (`_cc_flag_inject`): `cyrius build --strict-pin --pie --bounds` -> CYRIUS_STRICT_PIN=1,
#           CYRIUS_PIE=1 and CYRIUS_BOUNDS=1 together; `cyrius fuzz --poison` -> CYRIUS_POISON=1. The arm
#           set only CYRIUS_DCE and CYRIUS_BOUNDS, so the other three never reached cycc.exe (the user's
#           decision, 2026-10-10: fix it). Axis 2 asserts all three unset on a plain build. The arm's
#           source is read by compile_flag_list.sh axes 4-6, which need no wine.
#   axis 5  (6.6.20, CBTB-08) an environment rung longer than 512 bytes is READ on cyrius.exe: a
#           719-byte CYRIUS_DEFINES beats `[build] defines = ["A"]` in `--print-config`, as on
#           POSIX. _cfg_env's PE arm read through a fixed 512-byte buffer, and a longer value was
#           no rung at all — the manifest's defines won silently. A short value is the control
#           (it proves the environment reaches cyrius.exe at all).
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
mkdir -p "$W/whome"
# wine's own HOME / XDG_CACHE_HOME stay under $W too: a fresh prefix writes $HOME/.cache.
export WINEPREFIX="$WP" HOME="$W/whome" XDG_CACHE_HOME="$W/whome/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
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
    memcpy(out + o, "\nbounds=", 8);
    o = o + 8;
    n = syscall(0xF015, "CYRIUS_BOUNDS", eb, 512);
    if (n == 0) { memcpy(out + o, "unset", 5); o = o + 5; }
    else { memcpy(out + o, eb, n); o = o + n; }
    memcpy(out + o, "\nstrict_pin=", 12);
    o = o + 12;
    n = syscall(0xF015, "CYRIUS_STRICT_PIN", eb, 512);
    if (n == 0) { memcpy(out + o, "unset", 5); o = o + 5; }
    else { memcpy(out + o, eb, n); o = o + n; }
    memcpy(out + o, "\npie=", 5);
    o = o + 5;
    n = syscall(0xF015, "CYRIUS_PIE", eb, 512);
    if (n == 0) { memcpy(out + o, "unset", 5); o = o + 5; }
    else { memcpy(out + o, eb, n); o = o + n; }
    memcpy(out + o, "\npoison=", 8);
    o = o + 8;
    n = syscall(0xF015, "CYRIUS_POISON", eb, 512);
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
printf 'fn lib_fn(): i64 { return 1; }\n' > "$W/p/src/lib.cyr"
mkdir -p "$W/p/fuzz"
printf 'var x = 0;\n' > "$W/p/fuzz/h.fcyr"
run() {   # run <extra manifest lines> <verb> [args...]
    m=$1; shift
    printf '[package]\nname = "p"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/p.exe"\n%b' "$m" > "$W/p/cyrius.cyml"
    rm -f "$W/stub.log"
    ( cd "$W/p" && env -u CYRIUS_DCE -u CYRIUS_STRICT -u CYRIUS_BOUNDS -u CYRIUS_STRICT_PIN -u CYRIUS_PIE -u CYRIUS_POISON CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 timeout 300 wine "$W/home/bin/cyrius.exe" "$@" ) > "$W/out" 2>&1 || true
    [ -f "$W/stub.log" ] || { fail "the stub compiler never ran: $(head -3 "$W/out" | tr '\n' ' ')"; return 1; }
    return 0
}
has_flag() { head -1 "$W/stub.log" | grep -q -- " $1"; }

if run 'dce = true\n' build --strict; then
    has_flag --strict || fail "axis 1: cyrius build --strict did not put --strict on cycc.exe's command line: $(head -1 "$W/stub.log")"
    grep -qx 'dce=1' "$W/stub.log" || fail "axis 1: [build] dce = true did not reach cycc.exe as CYRIUS_DCE=1: $(sed -n 2p "$W/stub.log")"
fi
[ "$FAIL" = 0 ] && echo "  ok axis 1: [build] dce and --strict reach cycc.exe (CYRIUS_DCE=1 in its environment, --strict on its command line)"
x=$FAIL
if run '' build; then
    has_flag --strict && fail "axis 2: --strict reached cycc.exe with no strict configured"
    has_flag --allow-undef && fail "axis 2: --allow-undef reached cycc.exe from a plain build"
    has_flag --syntax-only && fail "axis 2: --syntax-only reached cycc.exe from a plain build"
    grep -qx 'dce=unset' "$W/stub.log" || fail "axis 2: CYRIUS_DCE reached cycc.exe with no dce configured: $(sed -n 2p "$W/stub.log")"
    grep -qx 'bounds=unset' "$W/stub.log" || fail "axis 2: CYRIUS_BOUNDS reached cycc.exe with no bounds configured: $(sed -n 3p "$W/stub.log")"
    for v in strict_pin pie poison; do
        grep -qx "$v=unset" "$W/stub.log" || fail "axis 2: $v reached cycc.exe from a plain build: $(grep "^$v=" "$W/stub.log")"
    done
fi
[ "$FAIL" = "$x" ] && echo "  ok axis 2: a plain build hands cycc.exe no --strict, --allow-undef, --syntax-only, CYRIUS_DCE, CYRIUS_BOUNDS, CYRIUS_STRICT_PIN, CYRIUS_PIE or CYRIUS_POISON"
# axis 6 (6.7.8, C2-7): the bounds-checked mode crosses the PE arm as the POSIX arm injects it —
# `--bounds` as CYRIUS_BOUNDS=1, a manifest `false` as CYRIUS_BOUNDS=0 (it must beat the entry's
# `#bounds` line, cycc's lowest rung).
x=$FAIL
if run '' build --bounds; then
    grep -qx 'bounds=1' "$W/stub.log" || fail "axis 6: cyrius build --bounds did not reach cycc.exe as CYRIUS_BOUNDS=1: $(sed -n 3p "$W/stub.log")"
fi
if run 'bounds = false\n' build; then
    grep -qx 'bounds=0' "$W/stub.log" || fail "axis 6: [build] bounds = false did not reach cycc.exe as CYRIUS_BOUNDS=0: $(sed -n 3p "$W/stub.log")"
fi
[ "$FAIL" = "$x" ] && echo "  ok axis 6: --bounds reaches cycc.exe as CYRIUS_BOUNDS=1, [build] bounds = false as CYRIUS_BOUNDS=0"
# axis 7 (6.7.8): every compiler flag the POSIX arm injects crosses the PE arm — several at once.
x=$FAIL
if run '' build --strict-pin --pie --bounds; then
    for v in strict_pin pie bounds; do
        grep -qx "$v=1" "$W/stub.log" || fail "axis 7: cyrius build --strict-pin --pie --bounds: $v did not reach cycc.exe as 1: $(grep "^$v=" "$W/stub.log")"
    done
    grep -qx 'poison=unset' "$W/stub.log" || fail "axis 7: CYRIUS_POISON reached cycc.exe from a build without --poison"
fi
if run '' fuzz --poison fuzz/h.fcyr; then
    grep -qx 'poison=1' "$W/stub.log" || fail "axis 7: cyrius fuzz --poison did not reach cycc.exe as CYRIUS_POISON=1: $(grep '^poison=' "$W/stub.log")"
fi
[ "$FAIL" = "$x" ] && echo "  ok axis 7: --strict-pin, --pie and --bounds reach cycc.exe together (CYRIUS_STRICT_PIN=1, CYRIUS_PIE=1, CYRIUS_BOUNDS=1), fuzz --poison as CYRIUS_POISON=1"
x=$FAIL
if run '' lint src/main.cyr; then
    has_flag --allow-undef || fail "axis 3: lint's pre-pass did not hand cycc.exe --allow-undef: $(head -1 "$W/stub.log")"
    has_flag --syntax-only || fail "axis 3: lint's pre-pass did not hand cycc.exe --syntax-only: $(head -1 "$W/stub.log")"
fi
[ "$FAIL" = "$x" ] && echo "  ok axis 3: lint's syntax pre-pass hands cycc.exe --allow-undef and --syntax-only"
x=$FAIL
printf '[package]\nname = "p"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/p.exe"\n\n[lib]\nmodules = ["src/lib.cyr"]\n' > "$W/p/cyrius.cyml"
rm -f "$W/stub.log"
d4rc=0; ( cd "$W/p" && env -u CYRIUS_DCE -u CYRIUS_STRICT CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 timeout 300 wine "$W/home/bin/cyrius.exe" distlib ) > "$W/out" 2>&1 || d4rc=$?
[ "$d4rc" -ne 0 ] || fail "axis 4: cyrius.exe distlib exited 0 — the sidecar cannot be verified on this host"
grep -q 'NOT written' "$W/out" || fail "axis 4: cyrius.exe distlib did not refuse by name: $(head -3 "$W/out" | tr '\n' ' ')"
[ -f "$W/p/dist/p.deps" ] && fail "axis 4: cyrius.exe distlib wrote an unverified sidecar"
[ "$FAIL" = "$x" ] && echo "  ok axis 4: cyrius.exe distlib refuses by name (rc $d4rc) and writes no unverified sidecar"

x=$FAIL
printf '[package]\nname = "p"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/p.exe"\ndefines = ["A"]\n' > "$W/p/cyrius.cyml"
LONG=$(i=0; while [ $i -lt 60 ]; do [ $i -gt 0 ] && printf ','; printf 'D%03d_xxxxxx' $i; i=$((i + 1)); done)
[ "${#LONG}" -gt 512 ] || fail "axis 5 fixture: CYRIUS_DEFINES is ${#LONG} bytes (must be past 512)"
pc() {   # pc <CYRIUS_DEFINES value>: cyrius.exe build --print-config, its build.defines line in $W/pc
    ( cd "$W/p" && env -u CYRIUS_DCE CYRIUS_DEFINES="$1" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 timeout 300 wine "$W/home/bin/cyrius.exe" build --print-config ) > "$W/out" 2>&1 || true
    grep 'build.defines' "$W/out" | tr -d '\r' > "$W/pc"
}
pc Z
grep -qF '["Z"]  (environment: CYRIUS_DEFINES)' "$W/pc" || fail "axis 5 control: a short CYRIUS_DEFINES did not reach cyrius.exe's --print-config: $(head -c 200 "$W/pc"; head -2 "$W/out" | tr '\n' ' ')"
pc "$LONG"
grep -qF '"D059_xxxxxx"]  (environment: CYRIUS_DEFINES)' "$W/pc" \
    || fail "axis 5: a ${#LONG}-byte CYRIUS_DEFINES was not read on cyrius.exe (the manifest's value won): $(head -c 200 "$W/pc")"
[ "$FAIL" = "$x" ] && echo "  ok axis 5: a ${#LONG}-byte CYRIUS_DEFINES beats [build] defines on cyrius.exe (a short one is the control)"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: build_config_windows_arm (dce, bounds, --strict-pin, --pie, --poison, --strict, --allow-undef, --syntax-only reach the compiler on the PE arm; an environment rung past 512 bytes is read; under wine)"
