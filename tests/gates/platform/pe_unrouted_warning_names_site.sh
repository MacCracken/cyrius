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

# 6.7.9: the stdlib's Windows stubs issue no unrouted syscall. lib/syscalls_windows.cyr's sys_brk
# and lib/mmap.cyr's cyr_mprotect returned -38 on PE through a raw syscall(12) / syscall(10) that
# no PE route takes, so EVERY PE build that included lib/syscalls.cyr warned at sys_brk, and every
# one that included lib/mmap.cyr (lib/freelist.cyr and lib/thread.cyr pull it in) at cyr_mprotect —
# called or not: a standing false warning that teaches a user to ignore the real ones. Both return
# the -38 themselves now (measured under wine 11.19: -38 from each, before and after). A PE build
# of the four modules that CALLS both stubs warns at nothing; the sub.cyr rows above are its
# anti-vacuous half (the same compiler warns at real unrouted sites).
# Mutants (2026-10-11): sys_brk's body back to `syscall(SYS_BRK, addr)`; cyr_mprotect's
# CYRIUS_TARGET_WIN arm dropped; the arm kept but the syscall(10) arm no longer guarded by
# `#ifndef CYRIUS_TARGET_WIN` (a dead raw call still warns) — each fails this row by name.
printf 'include "lib/syscalls.cyr"\ninclude "lib/mmap.cyr"\ninclude "lib/freelist.cyr"\ninclude "lib/thread.cyr"\nvar r = sys_brk(0) + cyr_mprotect(0, 4096, 0);\nsyscall(60, 0 - r);\n' > "$D/st.cyr"
( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$D/st.cyr" > "$D/st.exe" 2> "$D/st.err" ) \
    || { bad "PE compile of the stdlib-stub probe (syscalls + mmap + freelist + thread) failed:"; head -c 400 "$D/st.err"; echo; }
[ -s "$D/st.exe" ] || bad "PE compile of the stdlib-stub probe produced no binary"
if grep -q 'is not routed' "$D/st.err"; then
    bad "a PE build of lib/syscalls.cyr + mmap + freelist + thread warns an unrouted syscall (a stub that issues a raw call):"
    grep 'is not routed' "$D/st.err" | cut -c1-160
fi

# 6.7.16: a REFUSED call draws its error alone. `syscall(60 0);` (no `,`) stops at the `0`, so the arity the two
# routing warnings judge is unknown: the literal arm warned "syscall 60 with 0 argument(s) is not routed" at 1:1 (its
# walk back to the `syscall` token found no `)`) and the non-literal arm "no Windows-routable syscall of this arity" —
# an invented warning after the one error, at the file's first column. Met beside
# issues/2026-10-20-zone-replay-last-entry-latch-swallows-first-statement-error.md. Mutant: either arm's `_panic` check
# dropped — RF1 / RF2 or RF3 red. RF4 (control): a valid non-literal call at an arity no route takes still warns.
rf() {
    printf '%b' "$2" > "$D/rf.cyr"
    _rc=0; ( cd "$D" && CYRIUS_TARGET_WIN=1 "$CC" < rf.cyr > rf.exe 2> rf.err ) || _rc=$?
    _e=$(grep -c '^error' "$D/rf.err" || true); _w=$(grep -c '^warning' "$D/rf.err" || true)
    if [ "$_rc" = 0 ] || [ "$_e" != 1 ] || [ "$_w" != 0 ] || ! grep -q "^error:<source>:$3: expected ')', got number 0" "$D/rf.err"; then
        bad "$1: a refused call: rc $_rc, $_e error(s) + $_w warning(s), want the $3 error alone:"; grep '^error\|^warning' "$D/rf.err" | cut -c1-160
    fi
}
rf RF1 'syscall(60 0);\nsyscall(60, 2);\n' 1:12
rf RF2 'syscall(7 0);\nsyscall(60, 2);\n' 1:11
rf RF3 'var n = 60;\nsyscall(n 0);\nsyscall(60, 2);\n' 2:11
printf 'var n = 7;\nvar r = syscall(n, 1, 2, 3, 4, 5);\nsyscall(60, 0);\n' > "$D/rf4.cyr"
( cd "$D" && CYRIUS_TARGET_WIN=1 "$CC" < rf4.cyr > rf4.exe 2> rf4.err ) || bad "RF4: the valid non-literal call did not compile"
grep -q '^warning: syscall(<non-literal number>, ...) has no Windows-routable syscall of this arity' "$D/rf4.err" \
    || { bad "RF4: a valid non-literal call at an unrouted arity no longer warns:"; head -c 300 "$D/rf4.err"; echo; }

[ "$fail" = 0 ] || exit 1
echo "PASS: PE unrouted-syscall warning names n, its arity and <file>:<line>:<col>; the routed list is one note (6.6.10); a literal munmap is routed, unwarned, and the PE compiler build warns at neither runtime.cyr nor lex_pp.cyr (6.6.20); the stdlib's sys_brk / cyr_mprotect stubs warn at nothing (6.7.9); a refused call warns at nothing (6.7.16)"
