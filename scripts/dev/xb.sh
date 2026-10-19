#!/bin/sh
# scripts/dev/xb.sh — build ONE program for four targets, run each, print the four exit codes.
#
# Usage:  sh scripts/dev/xb.sh <file.cyr|file.tcyr>
#         XB_REBUILD=1 sh scripts/dev/xb.sh <file>       (rebuild the cross compilers first)
#
# Targets:
#   x86  build/cycc, run natively
#   a64  a cross compiler built from the aarch64 fork, run under qemu-aarch64
#   cx   a cross compiler built from the cx fork, the bytecode run by programs/cxvm.cyr
#   pe   CYRIUS_TARGET_WIN=1 build/cycc, run under wine (timeout 120 s) with a private WINEPREFIX
#
# Input:  the program — a path from the caller's cwd, or from the repo root; compiled FROM the repo
#         root, so its `include "lib/…"` lines resolve there. The repo's build/cycc, src/ and
#         programs/cxvm.cyr.
# Output: one line on stdout, `<name>: x86=<rc> a64=<rc> cx=<rc> pe=<rc>` (`BUILD(<rc>)` where that
#         target's compile failed). Exit 0 once that line is printed; 2 on a usage / setup error.
#         Each target's binary and compile stderr stay in the scratch dir for a look:
#         <scratch>/xb/<repo-key>/<name>.{x,a,cyx,exe} and .{x,a,cx,w}.err.
#
# The two cross compilers and cxvm are cached in <scratch>/xb/<repo-key>/ (one cache per checkout:
# <repo-key> is the cksum of the repo path) and rebuilt — into a temp, then renamed — when one is
# missing, when any src/**.cyr is newer than the aarch64 compiler, or with XB_REBUILD=1. They are
# built in the DEFAULT mode: CYRIUS_BOUNDS / CYRIUS_POISON / CYRIUS_COVERAGE are unset for those
# builds only (gate row E4); the program under test keeps the caller's environment. Nothing is
# written to build/.
#
# Scratch: CYRIUS_SCRATCH, default ${XDG_CACHE_HOME:-$HOME/.cache}/c6 (the wine prefix and its HOME
# live in <scratch>/xb/wp and <scratch>/xb/wh, shared by every checkout). The repo root: this file's
# ../.., or CYRIUS_REPO. Needs qemu-aarch64, wine and timeout on PATH.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md

[ $# = 1 ] || { echo "usage: sh scripts/dev/xb.sh <file.cyr|file.tcyr>" >&2; exit 2; }
f=$1
# a path from the caller's cwd wins; otherwise it is read from the repo root (below)
case "$f" in /*) ;; *) [ -f "$f" ] && f="$(pwd)/$f" ;; esac
ROOT=${CYRIUS_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT" || { echo "xb: cannot cd to $ROOT" >&2; exit 2; }
[ -f "$f" ] || { echo "xb: $1: no such file (from the caller's cwd or from $ROOT)" >&2; exit 2; }
[ -x build/cycc ] || { echo "xb: $ROOT/build/cycc missing" >&2; exit 2; }

SCRATCH=${CYRIUS_SCRATCH:-${XDG_CACHE_HOME:-$HOME/.cache}/c6}
XB="$SCRATCH/xb"
W="$XB/$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)"
mkdir -p "$W" || { echo "xb: cannot create $W" >&2; exit 2; }

# _xb_build <out> <source>: build/cycc(<source>) -> <out>, via a temp so a failed build never
# leaves a broken <out> that looks newer than src/.
_xb_build() {
    T=$(mktemp "$W/.build.XXXXXX") && [ -f "$T" ] || { echo "xb: mktemp in $W failed" >&2; exit 2; }
    if build/cycc < "$2" > "$T" 2> "$1.build.err" && [ -s "$T" ]; then
        chmod +x "$T" && mv -f "$T" "$1" && return 0
    fi
    rm -f "$T"
    echo "xb: building $1 from $2 failed: $(grep -m1 '^error' "$1.build.err")" >&2
    exit 2
}
if [ "${XB_REBUILD:-0}" = 1 ] || [ ! -x "$W/cc_a64" ] || [ ! -x "$W/cc_cx" ] || [ ! -x "$W/cxvm" ] \
   || [ -n "$(find src -newer "$W/cc_a64" -name '*.cyr' | head -1)" ]; then
    # cc_a64 is the freshness stamp, so it is built LAST: a failed build leaves it older than
    # src/ and the next run retries all three.
    (
        unset CYRIUS_BOUNDS CYRIUS_POISON CYRIUS_COVERAGE
        _xb_build "$W/cc_cx" src/main_cx.cyr
        _xb_build "$W/cxvm" programs/cxvm.cyr
        _xb_build "$W/cc_a64" src/main_aarch64.cyr
    ) || exit 2
fi

n=$(basename "$f")
b="$W/$n"
build/cycc < "$f" > "$b.x" 2> "$b.x.err"; rx=$?
if [ "$rx" = 0 ]; then chmod +x "$b.x"; "$b.x" > /dev/null 2>&1; ex=$?; else ex="BUILD($rx)"; fi
"$W/cc_a64" < "$f" > "$b.a" 2> "$b.a.err"; ra=$?
if [ "$ra" = 0 ]; then chmod +x "$b.a"; qemu-aarch64 "$b.a" > /dev/null 2>&1; ea=$?; else ea="BUILD($ra)"; fi
"$W/cc_cx" < "$f" > "$b.cyx" 2> "$b.cx.err"; rc=$?
if [ "$rc" = 0 ]; then "$W/cxvm" < "$b.cyx" > /dev/null 2>&1; ec=$?; else ec="BUILD($rc)"; fi
CYRIUS_TARGET_WIN=1 build/cycc < "$f" > "$b.exe" 2> "$b.w.err"; rw=$?
if [ "$rw" = 0 ]; then
    mkdir -p "$XB/wp" "$XB/wh"
    WINEPREFIX="$XB/wp" HOME="$XB/wh" XDG_CACHE_HOME="$XB/wh/.cache" WINEDEBUG=-all \
        WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d" timeout 120 wine "$b.exe" > /dev/null 2>&1
    ew=$?
else
    ew="BUILD($rw)"
fi
echo "$n: x86=$ex a64=$ea cx=$ec pe=$ew"
