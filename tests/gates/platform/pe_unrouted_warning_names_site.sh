#!/bin/sh
# 6.6.10: the PE "unrouted literal syscall" warning names the NUMBER, its ARITY and the
# SITE. It was one 1,471-byte line — "warning: syscall(n, ...) on CYRIUS_TARGET_WIN=1
# routes n=0,1,2,..." — repeated verbatim for every site and naming none of them, so the
# warnings left in a PE compiler build (7 of them) could not be attributed to a call.
# Now: `warning:<file>:<line>:<col>: syscall N with K argument(s) is not routed ...`,
# the column at the call's `syscall` token, and the routed-number list as a note printed
# ONCE per compile. CHANGELOG [6.6.10]
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: pe_unrouted_warning_names_site: no build/cycc"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pe_unrouted_warning_names_site: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT

fail=0
bad() { echo "FAIL: pe_unrouted_warning_names_site: $*"; fail=1; }

# Two unrouted sites in an INCLUDED file (so the file name is not <source>): an unknown
# number (12, brk), and a routed number at the wrong arity (2, open, with 4 arguments).
printf '# line 1\nfn z(p): i64 {\n    var a = syscall(12, 0);\n    if (p == 1) { a = a + syscall(2, 1, 2, 3, 4); }\n    return a;\n}\n' > "$D/sub.cyr"
printf 'include "sub.cyr"\nvar r = z(1);\nsyscall(60, 0);\n' > "$D/m.cyr"
( cd "$D" && CYRIUS_TARGET_WIN=1 "$CC" < m.cyr > m.exe 2> m.err ) || bad "PE compile failed:"
grep -q '^warning:sub.cyr:3:13: syscall 12 with 1 argument(s) is not routed on CYRIUS_TARGET_WIN=1' "$D/m.err" \
    || { bad "site 1 (sub.cyr:3:13, syscall 12, 1 arg) not named:"; head -c 400 "$D/m.err"; echo; }
grep -q '^warning:sub.cyr:4:27: syscall 2 with 4 argument(s) is not routed on CYRIUS_TARGET_WIN=1' "$D/m.err" \
    || { bad "site 2 (sub.cyr:4:27, syscall 2, 4 args) not named:"; head -c 400 "$D/m.err"; echo; }
n=$(grep -c '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/m.err")
[ "$n" = 1 ] || bad "the routed-number note printed $n times, want once per compile"
# Every warning starts a line (the note's length includes its newline).
w=$(grep -o 'warning:sub.cyr' "$D/m.err" | wc -l)
l=$(grep -c '^warning:sub.cyr' "$D/m.err")
[ "$w" = 2 ] && [ "$l" = 2 ] || bad "$w site warnings, $l at a line start — want 2 and 2"

[ "$fail" = 0 ] || exit 1
echo "PASS: PE unrouted-syscall warning names n, its arity and <file>:<line>:<col>; the routed list is one note (6.6.10)"
