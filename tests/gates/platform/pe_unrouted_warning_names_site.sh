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

# 6.6.20: the PE compiler's own build (install.sh's cycc_win recipe) does not warn at READFILE's
# three openat shims in src/frontend/lex.cyr. Each is the `else` arm of `if (SYS_OPEN == 2)`,
# dead in a PE compiler (main_win.cyr: SYS_OPEN = 2), and its 4-argument open is not a PE
# route, so every cycc_win build printed three "not routed" warnings for calls that cannot run
# — noise that buries a real one. They are compiled out under CYRIUS_TARGET_WIN.
( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < src/main_win.cyr > "$D/cycc_win" 2> "$D/cw.err" ) \
    || bad "the PE compiler (CYRIUS_TARGET_WIN=1, src/main_win.cyr) did not build:"
[ -s "$D/cycc_win" ] || bad "the PE compiler build produced no binary"
nlex=$(grep -c '^warning:src/frontend/lex\.cyr:[0-9]*:[0-9]*: syscall [0-9]* with [0-9]* argument(s) is not routed' "$D/cw.err" || true)
[ "$nlex" = 0 ] || { bad "the cycc_win build warns $nlex unrouted syscall(s) in src/frontend/lex.cyr:"; grep 'lex\.cyr:' "$D/cw.err" | head -c 400; echo; }
# Anti-vacuous: the sub.cyr rows below run the SAME compiler and require it to warn at two real
# unrouted sites, so a compiler that stopped warning altogether cannot pass this row with them.

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

# 6.6.20: munmap (11) at argc 3 is ROUTED (kernel32!VirtualFree, EMUNMAP_PE) — the note lists it
# and a literal call draws NO warning. Before 6.6.20 it was unrouted: every PE build of
# lib/freelist.cyr warned at both munmap sites and the call returned -38, leaking the mapping.
# The negative row is what catches a lost LITERAL arm (`_PE_ROUTE_FLUSH`): the unrouted-literal
# fallback runs the runtime switch, which routes 11 too, so behaviour alone cannot see it.
grep '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/m.err" | grep -q 'n=0,1,2,3,8,9,11,35,' \
    || bad "the routed-number note does not list 11 (munmap)"
printf 'fn u(p): i64 { return syscall(11, p, 4096); }\nvar r = u(0);\nsyscall(60, 0);\n' > "$D/mu.cyr"
( cd "$D" && CYRIUS_TARGET_WIN=1 "$CC" < mu.cyr > mu.exe 2> mu.err ) || bad "PE compile of the munmap probe failed:"
[ -s "$D/mu.exe" ] || bad "PE compile of the munmap probe produced no binary"
if grep -q 'syscall 11 with' "$D/mu.err"; then
    bad "a literal syscall(11, p, len) still warns as unrouted on PE:"; head -c 300 "$D/mu.err"; echo
fi

# 6.6.20: the PE COMPILER's own build warns only where a call is really unrouted. Built with
# install.sh's cycc_win recipe (src/main_win.cyr through `CYRIUS_TARGET_WIN=1 build/cycc`); the
# warnings are the source's, so the tarball's two-step build prints the same ones. runtime.cyr's
# CYRIUS_SYMS openat shim is the `SYS_OPEN != 2` arm, dead in a PE compiler (main_win.cyr:
# SYS_OPEN = 2), and is compiled out under CYRIUS_TARGET_WIN; lex_pp.cyr's munmap of its 24 MB
# preprocessor buffer is routed (VirtualFree) and now frees it. Before 6.6.20 both warned in
# every PE compiler build. Built once per run: a row that already made "$D/cycc_win" and its
# stderr "$D/cw.err" is reused.
if [ ! -s "$D/cycc_win" ]; then
    ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < src/main_win.cyr > "$D/cycc_win" 2> "$D/cw.err" ) \
        || bad "the PE compiler (CYRIUS_TARGET_WIN=1, src/main_win.cyr) did not build:"
fi
[ -s "$D/cycc_win" ] || bad "the PE compiler build produced no binary"
for f in runtime.cyr lex_pp.cyr; do
    if grep -q "^warning:src/[a-z/]*/$f:[0-9]*:[0-9]*: syscall [0-9]* with [0-9]* argument(s) is not routed" "$D/cw.err"; then
        bad "the PE compiler build still warns an unrouted syscall in $f:"; grep "/$f:" "$D/cw.err" | head -c 300; echo
    fi
done

[ "$fail" = 0 ] || exit 1
echo "PASS: PE unrouted-syscall warning names n, its arity and <file>:<line>:<col>; the routed list is one note (6.6.10); a literal munmap is routed, unwarned, and the PE compiler build warns at neither runtime.cyr nor lex_pp.cyr (6.6.20)"
