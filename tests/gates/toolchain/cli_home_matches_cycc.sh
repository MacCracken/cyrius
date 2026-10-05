#!/bin/sh
# cli_home_matches_cycc.sh — 6.6.17. The CLI picks its home by the rule cycc's `lib/` include
# fallback uses (C10, 6.6.16): CYRIUS_HOME when set and non-empty, else HOME/.cyrius; the FIRST
# occurrence of a name wins; an empty value is unset; the whole environment is read.
#
# THE DEFECT: cbt/core.cyr `find_tools` took the LAST duplicate, kept an empty CYRIUS_HOME as the
# home "" and read only the first 32 KB of /proc/self/environ. Measured on the 6.6.17 slot-open
# CLI: duplicate CYRIUS_HOME picked the second, `CYRIUS_HOME=` crashed `cyrius which` (SIGSEGV),
# and with a 40 KB variable ahead of them the CLI saw neither CYRIUS_HOME nor HOME — while cycc,
# under the same environment, read the first CYRIUS_HOME.
#
# Each row runs `cyrius which` (prints <home>/bin/cycc) AND compiles an include-fallback probe
# with the tree's cycc under the SAME environment, built exactly (duplicates and order kept) by a
# small exec helper compiled here; both must name the expected home. Linux only (cycc's fallback
# reads /proc/self/environ).
# PE (under wine when installed): a 600+ B CYRIUS_HOME is picked; GetEnvironmentVariableA was
# given 512, so a longer value left the buffer unwritten and the home read as "".
# Old CLI: rows dup_chome, dup_home, empty_chome, empty_then_set, big_ahead, big_ahead_home and
# pe_long_chome FAIL.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=cli_home_matches_cycc
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
[ -r /proc/self/environ ] || { echo "SKIP: $G: no /proc/self/environ — cycc's include fallback is Linux-only"; exit 77; }
[ "$(uname -m)" = x86_64 ] || { echo "SKIP: $G: the probes exit through x86_64 syscall 60"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
ulimit -c 0 2>/dev/null
VER=$(sed -n 's/^var _VERSION_TOOLCHAIN *= *"\(.*\)";.*/\1/p' src/version_str.cyr)
[ -n "$VER" ] || { echo "FAIL: $G: could not read _VERSION_TOOLCHAIN"; exit 1; }

mkdir -p "$W/cli" "$W/cwd"
"$CC" < cbt/cyrius.cyr > "$W/cli/cyrius" 2> "$W/cli.err" && [ -s "$W/cli/cyrius" ] \
  || { echo "FAIL: $G: cbt/cyrius.cyr does not build:"; tail -3 "$W/cli.err" | sed 's/^/      /'; exit 1; }
cat > "$W/envexec.cyr" <<'EOF'
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/syscalls.cyr"
include "lib/args.cyr"
# envexec NAME=V ... -- PROG ARGS... : exec PROG with exactly this environment, in order.
fn main(): i64 {
    alloc_init();
    args_init();
    var n = argc();
    var ev = alloc(8 * (n + 1));
    var av = alloc(8 * (n + 1));
    var i = 1;
    var ne = 0;
    while (i < n) {
        var a = argv(i);
        i = i + 1;
        if (streq(a, "--") == 1) { break; }
        store64(ev + ne * 8, a);
        ne = ne + 1;
    }
    store64(ev + ne * 8, 0);
    var prog = argv(i);
    var na = 0;
    while (i < n) { store64(av + na * 8, argv(i)); na = na + 1; i = i + 1; }
    store64(av + na * 8, 0);
    sys_execve(prog, av, ev);
    return 127;
}
var r = main();
sys_exit(r);
EOF
"$CC" < "$W/envexec.cyr" > "$W/envexec" 2> "$W/ee.err" && [ -s "$W/envexec" ] \
  || { echo "FAIL: $G: the exec helper does not build:"; tail -3 "$W/ee.err" | sed 's/^/      /'; exit 1; }
chmod +x "$W/cli/cyrius" "$W/envexec"
EE="$W/envexec"

# Homes: A (a CYRIUS_HOME), B/.cyrius (HOME=B), C and C/.cyrius (the duplicates). Each has a
# bin/cycc for `which` and a store slot whose zz_home() names it for cycc's fallback.
mk_home() { mkdir -p "$1/bin" "$1/versions/$VER/lib" && : > "$1/bin/cycc" \
  && printf 'fn zz_home(): i64 { return %s; }\n' "$2" > "$1/versions/$VER/lib/zz_t3.cyr"; }
mk_home "$W/A" 1 && mk_home "$W/B/.cyrius" 2 && mk_home "$W/C" 3 && mk_home "$W/C/.cyrius" 4 \
  || { echo "FAIL: $G: cannot stage the homes"; exit 1; }
printf 'include "lib/zz_t3.cyr"\nsyscall(60, zz_home());\n' > "$W/cwd/p.cyr"
BIG="BIG=$(head -c 40000 /dev/zero | tr '\0' x)"

_label() {
    case "$1" in
        "$W/A/bin/cycc"|1) echo A ;;
        "$W/B/.cyrius/bin/cycc"|2) echo B ;;
        "$W/C/bin/cycc"|3) echo C ;;
        "$W/C/.cyrius/bin/cycc"|4) echo C/.cyrius ;;
        *) echo "none(${1:-})" ;;
    esac
}
row() {   # $1 = row name, $2 = expected label, rest = the environment
    name=$1; want=$2; shift 2
    crc=0; cli=$( cd "$W/cwd" && "$EE" CYRIUS_RESOLVED=1 "$@" -- "$W/cli/cyrius" which 2>/dev/null ) || crc=$?
    [ "$crc" -eq 0 ] || cli="rc=$crc"
    rm -f "$W/cwd/p.bin"
    if ( cd "$W/cwd" && "$EE" "$@" -- "$CC" < p.cyr > p.bin 2> p.err ) && [ -s "$W/cwd/p.bin" ]; then
        chmod +x "$W/cwd/p.bin"; prc=0; "$W/cwd/p.bin" || prc=$?
    else prc="no-compile: $(head -1 "$W/cwd/p.err")"; fi
    got_cli=$(_label "$cli"); got_cc=$(_label "$prc")
    if [ "$got_cli" = "$want" ] && [ "$got_cc" = "$want" ]; then
        echo "  ok: $name — the CLI and cycc both pick $want"
    else
        echo "FAIL: $G: $name — expected $want; the CLI picked $got_cli, cycc picked $got_cc"; FAIL=1
    fi
}

row plain           A  CYRIUS_HOME="$W/A" HOME="$W/B"
row order           A  HOME="$W/B" CYRIUS_HOME="$W/A"
row dup_chome       A  CYRIUS_HOME="$W/A" CYRIUS_HOME="$W/C" HOME="$W/B"
row dup_home        B  HOME="$W/B" HOME="$W/C"
row empty_chome     B  CYRIUS_HOME= HOME="$W/B"
row empty_then_set  B  CYRIUS_HOME= CYRIUS_HOME="$W/A" HOME="$W/B"
row big_ahead       A  "$BIG" CYRIUS_HOME="$W/A" HOME="$W/B"
row big_ahead_home  B  "$BIG" HOME="$W/B"

# ── PE: a CYRIUS_HOME of 512+ B (GetEnvironmentVariableA was given 512, so a longer value left
# the buffer unwritten and the home read as "") ─────────────────────────────────────────────
if command -v wine > /dev/null 2>&1; then
    export WINEPREFIX="$W/wine" XDG_CACHE_HOME="$W/xdg" WINEDEBUG=-all
    trap 'wineserver -k > /dev/null 2>&1; rm -rf "$W"' EXIT
    D100=$(head -c 100 /dev/zero | tr '\0' d)
    LONG="$W/$D100/$D100/$D100/$D100/$D100/$D100"
    mkdir -p "$LONG/bin" && : > "$LONG/bin/cycc.exe"
    if "$CC" < src/main_win.cyr > "$W/cc_win" 2> /dev/null && chmod +x "$W/cc_win" \
       && CYRIUS_TARGET_WIN=1 "$W/cc_win" < cbt/cyrius.cyr > "$W/cli/cyrius.exe" 2> /dev/null && [ -s "$W/cli/cyrius.exe" ]; then
        got=$( cd "$W/cwd" && CYRIUS_HOME="Z:$LONG" CYRIUS_RESOLVED=1 timeout 180 wine "$W/cli/cyrius.exe" which 2> /dev/null | tr -d '\r' ) || true
        if [ "$got" = "Z:$LONG/bin/cycc.exe" ]; then echo "  ok: pe_long_chome — cyrius.exe picks a ${#LONG}-B CYRIUS_HOME"
        else echo "FAIL: $G: pe_long_chome — cyrius.exe with a ${#LONG}-B CYRIUS_HOME printed '$(printf '%s' "$got" | head -c 60)'"; FAIL=1; fi
    else
        echo "FAIL: $G: pe_long_chome — the PE CLI does not build from the tree"; FAIL=1
    fi
else
    echo "  SKIP (named): pe_long_chome — wine is not installed"
fi

[ "$FAIL" = 0 ] || exit 1
echo "PASS: $G"
exit 0
