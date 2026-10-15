#!/bin/sh
# cx_auto_call_main.sh — 6.7.11. A cx program runs the `fn main` it defines, as every image target
# does: the entry epilogue calls it after the top level and the last-var load, and its return value
# is the exit code (issues/2026-10-11-cx-does-not-auto-call-main.md; the user's decision (a),
# 2026-10-13).
#
# THE DEFECT. The x86, aarch64 (cross and native), Mach-O and PE drivers end the entry with v5.9.37's
# auto-call (`_find_fn_by_name(S, "main", 4)`, then `ECALLTO` when the fn has code). src/main_cx.cyr's
# epilogue was only the last-var load and EEXIT, so on cx `main` never ran: `var g = 3; fn main():
# i64 { return 7; }` exited 7 on x86_64 and qemu-aarch64 and 3 under cxvm, `fn main(): i64 { return
# 7; }` alone exited 0, and a .tcyr that leaves `main` to the epilogue printed nothing and exited 0 —
# a pass that ran no assertion. THE FIX. main_cx.cyr ports the block (no `kernel;` / `shared;` guard:
# cx refuses both before the epilogue). A `main` called at top level AND left to the epilogue runs
# twice, as on every image target (the guide's *the three correct shapes*).
#
# ROWS — each program run NATIVELY (x86_64, the oracle) and on cxvm; both must give the row's answer.
#   A1  the filed repro verbatim (a global, then `fn main` returning 7): exit 7
#   A2  `fn main(): i64 { return 7; }` alone: exit 7
#   A3  `main` called at top level AND left to the epilogue: it runs twice (a counter global, exit
#       n * 10 = 20) and prints its marker line twice
#   A4  `main` called at top level, then an explicit `syscall(60, r)`: it runs once (exit 10)
#   A5  the epilogue's call comes after the top level: `g = g + 1;` at top level, `main` returns g * 10
#       (exit 40)
#   A6  no `fn main` — only `fn mainframe` / `fn mai`: the exit is the last global (3); the lookup is
#       the exact name
#   A7  `main`'s output reaches stdout once, and its own `syscall(60, 5)` is the exit
#   T1-T3  tests/tcyr/crossos/chan_try_send.tcyr, crossos/multi_return.tcyr and
#       math/float_nan_compare.tcyr leave `main` to the epilogue: native and cxvm each print
#       `<N> passed, 0 failed`, N derived from the source (floors 20 / 31 / 41) and exit 0. Before the
#       fix cxvm printed nothing and exited 0.
#   X1-X2  tests/tcyr/crossos/mmap_anon_flag.tcyr and crossos/uid_identity.tcyr: native prints
#       `<N> passed, 0 failed` (N derived, floors 5 / 13); on cxvm their `main` now runs and stops at
#       the cx guest contract — mmap_anon hands back a HOST address (a cxvm trap on the first store)
#       and sys_fstat's buffer is not translated (-EFAULT: 11 passed, 2 failed; 12 / 1 as root, the
#       zeroed buffer's uid then matching euid 0 — the pin takes both, keyed on the fstat line).
#       Filed, not fixed here (a cxvm syscall-translation / guest-mmap design): 2026-10-14-cx-main-
#       running-tcyr-fail-at-guest-contract-limits.md (6.7.12). Each cx leg pins that exact failure,
#       so a fix turns the row RED as an XPASS ("promote it to a T row") and any other failure is RED
#       too.
# Anti-vacuous: the native leg of every row is its control, each .tcyr count is derived from its
# source and held to a floor, and the row count is checked.
#
# COMPILERS. CC=${CYCC:-build/cycc} builds the native legs and — unless CYCC_CX is set — the cx
# compiler from THIS tree's src/main_cx.cyr, and cxvm from programs/cxvm.cyr (CXVM overrides it).
#
# MUTATION LEDGER (6.7.11, measured; the real tree green 24/24):
#   MA1 the `ECALLTO(S, _main_off);` dropped from src/main_cx.cyr (its cycc_cx passed as CYCC_CX)
#       -> RED 10: A1 / A2 / A3 / A5 / A7 cx (exit 3 / 0 / 10 / 4 / 1: the last global), T1-T3 cx
#          (nothing printed, exit 0), X1 / X2 cx (exit 0, nothing printed: "the failure moved")
#   MA2 the call emitted BEFORE the last-var load, which then overwrites main's r0 -> RED 4: A1 /
#       A3 / A5 cx (exit 3 / 10 / 4: the last global) and X2 cx (exit 0, the last global's value
#       instead of 2); A2 and T1-T3 stay green (their last global is 0 or absent)
# Exit 77 = could not run (no compiler at $CC, no timeout(1)); never a SKIP line with exit 0.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
_abs() { case $1 in /*|'') printf '%s' "$1" ;; *) printf '%s/%s' "$(pwd)" "$1" ;; esac; }
CC=$(_abs "${CYCC:-$ROOT/build/cycc}")
CYCC_CX=$(_abs "${CYCC_CX:-}")
CXVM=$(_abs "${CXVM:-}")
G=cx_auto_call_main
[ -x "$CC" ] || { echo "SKIP: $G — no compiler at $CC (exit 77: a SKIP, not a PASS)"; exit 77; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP: $G — no timeout(1) (exit 77: a SKIP, not a PASS)"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0 2>/dev/null || true

if [ -n "$CYCC_CX" ]; then
    [ -x "$CYCC_CX" ] || { echo "FAIL: $G — CYCC_CX=$CYCC_CX is not executable"; exit 1; }
    CX=$CYCC_CX
else
    CX=$T/cycc_cx
    "$CC" < src/main_cx.cyr > "$CX" 2> "$T/eb"; chmod +x "$CX"
    [ -s "$CX" ] || { echo "FAIL: $G — cannot build the cx compiler from src/main_cx.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
fi
if [ -n "$CXVM" ]; then
    [ -x "$CXVM" ] || { echo "FAIL: $G — CXVM=$CXVM is not executable"; exit 1; }
    VM=$CXVM
else
    VM=$T/cxvm
    "$CC" < programs/cxvm.cyr > "$VM" 2> "$T/eb"; chmod +x "$VM"
    [ -s "$VM" ] || { echo "FAIL: $G — cannot build cxvm from programs/cxvm.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
fi

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# build_run LEG SRC OUT — compile SRC for LEG (native / cx) and run it in $T; RC = its exit (or
# "nobuild"), its stdout + stderr in OUT.
build_run() {
    RC=0
    if [ "$1" = native ]; then
        "$CC" < "$2" > "$T/n.bin" 2> "$T/n.err" || RC=nobuild
        [ -s "$T/n.bin" ] || RC=nobuild
        [ "$RC" = nobuild ] && { cp "$T/n.err" "$3"; return; }
        chmod +x "$T/n.bin"; (cd "$T" && timeout 120 ./n.bin > "$3" 2>&1) || RC=$?
    else
        "$CX" < "$2" > "$T/c.cyx" 2> "$T/c.err" || RC=nobuild
        [ -s "$T/c.cyx" ] || RC=nobuild
        [ "$RC" = nobuild ] && { cp "$T/c.err" "$3"; return; }
        (cd "$T" && timeout 120 "$VM" < c.cyx > "$3" 2>&1) || RC=$?
    fi
}

# row NAME WANT_RC MARKER WHAT SOURCE — native, then cxvm; each must exit WANT_RC and, when MARKER
# is set, print MARKER exactly MARKER_N times (default 1). A SOURCE of `@path` is that file verbatim.
MARKER_N=1
row() {
    case $5 in @*) cp "${5#@}" "$T/$1.cyr" ;; *) printf '%b' "$5" > "$T/$1.cyr" ;; esac
    for leg in native cx; do
        build_run "$leg" "$T/$1.cyr" "$T/$1.$leg.out"
        if [ "$RC" = nobuild ]; then bad "$4 ($leg): does not build: $(grep -m1 '^error' "$T/$1.$leg.out")"; continue; fi
        if [ "$RC" != "$2" ]; then bad "$4 ($leg): exit $RC, want $2 $(grep -m1 '^cxvm:' "$T/$1.$leg.out")"; continue; fi
        if [ -n "$3" ]; then
            n=$(grep -cx "$3" "$T/$1.$leg.out")
            if [ "$n" != "$MARKER_N" ]; then bad "$4 ($leg): exit $RC, but '$3' printed $n time(s), want $MARKER_N"; continue; fi
        fi
        ok "$4 ($leg): exit $RC"
    done
}

# Assertion lines outside the arms a Linux / cx build drops (`#ifdef CYRIUS_TARGET_MACOS` / `_WIN` /
# `_AGNOS` … `#endif`; none of these files nests one).
n_lin() { awk '/^[[:space:]]*#ifdef CYRIUS_TARGET_(MACOS|WIN|AGNOS)/{s=1; next} s && /^[[:space:]]*#endif/{s=0; next} !s && /^[[:space:]]*assert(_[a-z]+)?\(/{n++} END{print n+0}' "$1"; }

# tcyr ID FILE FLOOR — native and cxvm each print `<N> passed, 0 failed` (the last line) and exit 0.
tcyr() {
    w=$(n_lin "$2")
    [ "$w" -ge "$3" ] || { bad "$1 $2: only $w assertions in the source (floor $3)"; return; }
    for leg in native cx; do
        build_run "$leg" "$2" "$T/t.$leg.out"
        if [ "$RC" = nobuild ]; then bad "$1 $2 ($leg): does not build: $(grep -m1 '^error' "$T/t.$leg.out")"; continue; fi
        if [ "$RC" = 0 ] && tail -1 "$T/t.$leg.out" | grep -q "^$w passed, 0 failed"; then ok "$1 $2 ($leg): $w passed, 0 failed"
        else bad "$1 $2 ($leg): exit $RC, want '$w passed, 0 failed', got: '$(tail -1 "$T/t.$leg.out")' $(grep -m2 'FAIL' "$T/t.$leg.out" | tr '\n' ' ')"; fi
    done
}

ISSUE=2026-10-14-cx-main-running-tcyr-fail-at-guest-contract-limits.md
# xfail ID FILE FLOOR WANT_RC WANT_LAST WANT_LINE — the native leg is a full pass; the cx leg runs
# `main` (WANT_LINE, a line only `main` prints, is there) and stops exactly as filed: an exit WANT_RC
# matches (an ERE) and the last line WANT_LAST. A full pass on cx is an XPASS: RED, so the row is promoted.
xfail() {
    w=$(n_lin "$2")
    [ "$w" -ge "$3" ] || { bad "$1 $2: only $w assertions in the source (floor $3)"; return; }
    build_run native "$2" "$T/x.native.out"
    if [ "$RC" = 0 ] && tail -1 "$T/x.native.out" | grep -q "^$w passed, 0 failed"; then ok "$1 $2 (native): $w passed, 0 failed"
    else bad "$1 $2 (native): exit $RC, want '$w passed, 0 failed', got: '$(tail -1 "$T/x.native.out")'"; fi
    build_run cx "$2" "$T/x.cx.out"
    if [ "$RC" = 0 ] && tail -1 "$T/x.cx.out" | grep -q "^$w passed, 0 failed"; then
        bad "$1 $2 (cx): XPASS — $w passed, 0 failed under cxvm; the filed limit ($ISSUE) is gone: make this a T row"
    elif printf '%s\n' "$RC" | grep -qxE "$4" && grep -qxF "$6" "$T/x.cx.out" && tail -1 "$T/x.cx.out" | grep -qE "$5"; then
        ok "$1 $2 (cx): main ran ('$6') and stops at the filed guest-contract limit — exit $RC, '$(tail -1 "$T/x.cx.out" | cut -c1-60)' (XFAIL: $ISSUE)"
    else bad "$1 $2 (cx): the failure moved — exit $RC (want $4), last line '$(tail -1 "$T/x.cx.out")' (want /$5/), '$6' $(grep -cxF "$6" "$T/x.cx.out")x"; fi
}

R1=docs/development/issues/repros/2026-10-11-cx-does-not-auto-call-main.cyr
if [ -f "$R1" ]; then row a1 7 "" "A1: the filed repro verbatim" "@$R1"
else bad "A1: the filed repro $R1 is missing"; fi
row a2 7 "" "A2: \`fn main(): i64 { return 7; }\` alone" 'fn main(): i64 { return 7; }\n'
MARKER_N=2
row a3 20 "main-ran" "A3: main called at top level AND left to the epilogue runs twice (n * 10 = 20)" 'var n = 0;\nfn main(): i64 { n = n + 1; syscall(1, 1, "main-ran\\n", 9); return n * 10; }\nvar r = main();\n'
MARKER_N=1
row a4 10 "main-ran" "A4: main called at top level, then syscall(60, r): it runs once" 'var n = 0;\nfn main(): i64 { n = n + 1; syscall(1, 1, "main-ran\\n", 9); return n * 10; }\nvar r = main();\nsyscall(60, r);\n'
row a5 40 "" "A5: the top level runs first (g = g + 1), then main (g * 10)" 'var g = 3;\ng = g + 1;\nfn main(): i64 { return g * 10; }\n'
row a6 3 "" "A6: no fn main — mainframe / mai are not main; the exit is the last global" 'fn mainframe(): i64 { return 9; }\nfn mai(): i64 { return 8; }\nvar g = 3;\n'
row a7 5 "cx-main-out" "A7: main's output reaches stdout once, and its own syscall(60, 5) is the exit" 'var g = 1;\nfn main(): i64 { syscall(1, 1, "cx-main-out\\n", 12); syscall(60, 5); return 0; }\n'

tcyr T1 tests/tcyr/crossos/chan_try_send.tcyr 20
tcyr T2 tests/tcyr/crossos/multi_return.tcyr 31
tcyr T3 tests/tcyr/math/float_nan_compare.tcyr 41

xfail X1 tests/tcyr/crossos/mmap_anon_flag.tcyr 5 1 '^cxvm: guest address out of range: [0-9]+ at pc [0-9]+$' '=== mmap_anon returns memory that is actually writable ==='
# The exit and the last line take either count: the second failure ('owned by sys_geteuid()')
# compares the untranslated buffer's 0 with the euid, so it passes under root (12 passed, 1 failed,
# exit 1); the fstat line is the deterministic pin.
xfail X2 tests/tcyr/crossos/uid_identity.tcyr 13 '[12]' '^1[12] passed, [12] failed \(13 total\)$' '  FAIL: sys_fstat on the probe file succeeded (got 1, expected 0)'

WANT=24
if [ "$fail" -ne 0 ]; then echo "FAIL: $G — $fail row(s) red, $pass green"; exit 1; fi
if [ "$pass" -ne "$WANT" ]; then echo "FAIL: $G — $pass rows ran, want $WANT (a row stopped running)"; exit 1; fi
echo "PASS: $G — $pass/$WANT rows: cx calls the fn main a program defines from the entry epilogue, as natively (the filed repro, main alone, twice when also called, once before an explicit exit, after the top level, the exact name, its output); three .tcyr that leave main to it pass under cxvm, two stop at the filed guest-contract limits"
exit 0
