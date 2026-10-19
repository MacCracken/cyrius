#!/bin/sh
# scripts/dev/probe.sh — compile and run every probe in a directory; report each one in a line.
#
# Usage:  sh scripts/dev/probe.sh <dir>
#         OLD_CC=<compiler> sh scripts/dev/probe.sh <dir>     (before / after, side by side)
#         PROBE_TIMEOUT=<s> …                                 (each run's timeout, default 10)
#
# Input:  <dir>/*.cyr (a path from the caller's cwd, or from the repo root) — write them by hand or
#         split one file of `== name` blocks with scripts/dev/probe-split.py. Each probe is compiled
#         FROM the repo root with the repo's build/cycc, so `include "lib/…"` resolves there.
# Output, one probe at a time:
#   default   `<name>: BUILT exit=<rc> warn=<count of warning lines>`, or, when the compile fails,
#             `<name>: rc=<rc> errs=<count of error lines> :: <the first two error lines, |-joined>`
#   OLD_CC    `== <name>`, then for `before` (OLD_CC) and `after` (build/cycc) in turn:
#             `<before|after>: compile rc=<rc> run=<rc or -> stdout=[<first 120 bytes, |-joined>]`
#             and up to six of that compile's stderr lines (notes dropped), indented
# The binaries and compile stderr stay next to each probe: <name>.bin / <name>.err (build/cycc),
# <name>.old.bin / <name>.old.err (OLD_CC). Exit 0 once every probe is reported; 2 on a usage /
# setup error (no <dir>, no probe in it, a compiler that is not executable).
#
# The repo root: this file's ../.., or CYRIUS_REPO. Needs timeout on PATH.
#
# converted to cyrius later: docs/development/issues/2026-10-19-dev-helper-scripts-converted-to-cyrius.md

[ $# = 1 ] || { echo "usage: [OLD_CC=<compiler>] sh scripts/dev/probe.sh <dir>" >&2; exit 2; }
d=$1
# paths from the caller's cwd win; otherwise <dir> is read from the repo root (below)
case "$d" in /*) ;; *) [ -d "$d" ] && d="$(pwd)/$d" ;; esac
OLD=${OLD_CC:-}
case "$OLD" in ""|/*) ;; *) OLD="$(pwd)/$OLD" ;; esac
ROOT=${CYRIUS_REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT" || { echo "probe: cannot cd to $ROOT" >&2; exit 2; }
[ -d "$d" ] || { echo "probe: $1: no such directory (from the caller's cwd or from $ROOT)" >&2; exit 2; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "probe: $CC missing" >&2; exit 2; }
[ -z "$OLD" ] || [ -x "$OLD" ] || { echo "probe: OLD_CC=$OLD_CC is not an executable compiler" >&2; exit 2; }
TO=${PROBE_TIMEOUT:-10}

n=0
for f in "$d"/*.cyr; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    b=${f%.cyr}
    name=$(basename "$b")
    if [ -z "$OLD" ]; then
        "$CC" < "$f" > "$b.bin" 2> "$b.err"; rc=$?
        if [ "$rc" = 0 ]; then
            chmod +x "$b.bin"
            timeout "$TO" "$b.bin" > /dev/null 2>&1; ex=$?
            echo "$name: BUILT exit=$ex warn=$(grep -c '^warning' "$b.err")"
        else
            echo "$name: rc=$rc errs=$(grep -c '^error' "$b.err") :: $(grep '^error' "$b.err" | head -2 | cut -c1-170 | tr '\n' '|')"
        fi
        continue
    fi
    echo "== $name"
    for c in before after; do
        if [ "$c" = before ]; then cc=$OLD; out="$b.old"; else cc=$CC; out=$b; fi
        "$cc" < "$f" > "$out.bin" 2> "$out.err"; rc=$?
        so=""
        if [ "$rc" -eq 0 ] && [ -s "$out.bin" ]; then
            chmod +x "$out.bin"
            timeout "$TO" "$out.bin" > "$out.stdout" 2>&1; ex=$?
            so=$(head -c 120 "$out.stdout" | tr '\n' '|')
            rm -f "$out.stdout"
        else
            ex=-
        fi
        printf '%s: compile rc=%s run=%s stdout=[%s]\n' "$c" "$rc" "$ex" "$so"
        grep -v '^note:' "$out.err" | head -6 | sed 's/^/    /'
    done
done
[ "$n" -gt 0 ] || { echo "probe: no *.cyr in $d" >&2; exit 2; }
exit 0
