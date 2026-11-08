#!/bin/sh
# repros/2026-10-29-dce-keeps-literals-of-dead-code.sh
#
# A 100 000-byte string literal reachable only from a dead fn, built with
# CYRIUS_DCE=1. DCE removes the fn and keeps the literal. Three programs:
#   without  — `fn main` alone
#   global   — plus `var _BIG = "<literal>";` read only by a dead fn
#   fnlocal  — plus a dead fn holding the literal as a local
#
# Measured on cyrius 6.7.18, x86_64 Linux:
#   without    4 456 B   literal in image: 0
#   global   104 472 B   literal in image: 1   (note: 1 unreachable fns, 60 bytes)
#   fnlocal  104 464 B   literal in image: 1   (note: 1 unreachable fns, 64 bytes)
#
# Usage: sh 2026-10-29-dce-keeps-literals-of-dead-code.sh

set -eu
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
BIG=$(head -c 100000 /dev/zero | tr '\0' 'q')
TAIL='fn main() { return 0; }
var exit_code = main(); syscall(60, exit_code);'

printf '%s\n' "$TAIL" > "$W/without.cyr"
printf 'var _BIG = "%s";\nfn unused() { return load8(_BIG); }\n%s\n' "$BIG" "$TAIL" > "$W/global.cyr"
printf 'fn unused() { var b = "%s"; return load8(b); }\n%s\n' "$BIG" "$TAIL" > "$W/fnlocal.cyr"

cyrius --version | head -1
for p in without global fnlocal; do
    ( cd "$W" && CYRIUS_DCE=1 cyrius build "$p.cyr" "$p" >/dev/null 2>&1 )
    printf '%-8s %8d B   literal in image: %s\n' "$p" "$(wc -c < "$W/$p")" \
        "$(LC_ALL=C grep -a -c qqqqqqqqqqqqqqqqqqqq "$W/$p" || true)"
done
