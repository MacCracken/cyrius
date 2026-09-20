#!/bin/sh
# Gate: a forward-read CONSTANT global reads its value on cx, like every other target
# (6.6.6 bite 19d).
#
# THE DEFECT (measured at 6.6.5):
#
#     var b = a;
#     var a = 5;
#     syscall(60, b);      x86 / aarch64 / Mach-O / PE: 5      cx: 0
#
# cx opts out of the static-init path on purpose — its globals live in cxvm-allocated memory
# zeroed at startup, so skipping the runtime store would leave them zero. But that makes the
# DEFERRED replay (EMIT_GVAR_INITS, in declaration order) the only thing that gives a global
# its value, so a read ABOVE the declaration saw 0. Everywhere else the constant is baked into
# the file image and position does not matter. `_gv_cx_prestore` already existed for the
# redeclaration and shadow cases — those RECORD a value in gvar_initval — so the fix is to
# record the folded constant for cx too, without setting `sit_lit` (cx keeps its runtime store,
# which writes the same value). src/frontend/parse_decl.cyr.
#
# EXPECTED VALUES are computed a DIFFERENT WAY from the actual, twice over: (1) every row is
# compared against a CONTROL that declares in dependency order, where no target ever needed a
# prestore, and (2) every row is run on the HOST as well, so cx is checked against a second
# implementation rather than against a number written in this file.
#
# ⚠ ROW E IS THE NEGATIVE HALF. A COMPUTED initializer (`var a = cf();`) is NOT constant and
# still runs in declaration order on every target — a forward read of one is 0 by design, and
# the guide says so. A "fix" that prestored everything would change that, so it is pinned.
#
# LEGS: cx (the tree's own main_cx + cxvm — the defect's target), host x86_64, and aarch64
# under qemu-aarch64 when installed. qemu and cxvm are EMULATORS, not hardware.
#
# MUTATION LEDGER (6.6.6):
#   1. the cx record dropped (the 6.6.5 behaviour)      -> RED cx rows A B C
#   2. _gv_cx_prestore made a no-op                     -> RED cx rows A B C F
#   3. the record made unconditional and constant       -> RED cx rows A B C D E
#   4. real tree                                        -> GREEN (6 host + 6 cx + 6 aarch64)
# ⚠ Each mutant is a scratch TREE and the gate is run from inside it, because the cx leg builds
#   `src/main_cx.cyr` from $ROOT — running a mutant merely as CYCC=<mutant> against the real
#   tree builds the REAL cx compiler and every row reads green. That was measured, not assumed.
# ⚠ HONEST GAP: the `sit_lit == 0` condition on the cx record has no killing row. With
#   `sit_lit == 1` the very next branch writes the same gvar_initval slot with the same folded
#   value, so dropping the condition is unobservable. It is defensive.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: cx_forward_read_constant_global: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
NCX=0
NA64=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

build() {
    if ! "$CC" < "$1" > "$2" 2> "$2.err"; then return 1; fi
    [ -s "$2" ] || return 1
    chmod +x "$2"
    return 0
}
build "$ROOT/src/main_cx.cyr" "$WORK/cycc_cx" || { echo "FAIL: could not build src/main_cx.cyr"; exit 1; }
build "$ROOT/programs/cxvm.cyr" "$WORK/cxvm"  || { echo "FAIL: could not build programs/cxvm.cyr"; exit 1; }

host_ec() {
    printf '%b' "$1" > "$WORK/h.cyr"
    if ! build "$WORK/h.cyr" "$WORK/h.bin"; then printf 'CCFAIL'; return 0; fi
    set +e; "$WORK/h.bin" > /dev/null 2>&1; r=$?; set -e
    printf '%s' "$r"
}
cx_ec() {
    printf '%b' "$1" > "$WORK/c.cyr"
    if ! "$WORK/cycc_cx" < "$WORK/c.cyr" > "$WORK/c.cyx" 2>/dev/null; then printf 'CCFAIL'; return 0; fi
    [ -s "$WORK/c.cyx" ] || { printf 'EMPTY'; return 0; }
    set +e; "$WORK/cxvm" < "$WORK/c.cyx" > /dev/null 2>&1; r=$?; set -e
    printf '%s' "$r"
}
A64=""
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if build "$ROOT/src/main_aarch64.cyr" "$WORK/cycc_a64"; then A64="$WORK/cycc_a64"; fi
fi
a64_ec() {
    printf '%b' "$1" > "$WORK/q.cyr"
    if ! "$A64" < "$WORK/q.cyr" > "$WORK/q.bin" 2>/dev/null; then printf 'CCFAIL'; return 0; fi
    [ -s "$WORK/q.bin" ] || { printf 'EMPTY'; return 0; }
    chmod +x "$WORK/q.bin"
    set +e; qemu-aarch64 "$WORK/q.bin" > /dev/null 2>&1; r=$?; set -e
    printf '%s' "$r"
}

# The cx toolchain must answer a program it never got wrong, or every row could agree on an
# error code and read green.
CXS=$(cx_ec 'var cxs = 0;\nvar cxt = 2;\ncxs = cxt * 10;\nsyscall(60, cxs);\n')
[ "$CXS" = "20" ] || bad "cx sanity program gave $CXS, want 20 (the cx toolchain is broken; rows would be vacuous)"

# _row <id> <want> <test> <control-declared-in-order>
_row() {
    NROWS=$((NROWS + 1))
    _id=$1; _w=$2; _t=$3; _c=$4
    h=$(host_ec "$_t");  hc=$(host_ec "$_c")
    [ "$hc" = "$_w" ] || bad "row $_id: host CONTROL gave $hc, want $_w (the gate's own premise is off)"
    [ "$h"  = "$_w" ] || bad "row $_id: host gave $h, want $_w"
    NCX=$((NCX + 1))
    x=$(cx_ec "$_t");   xc=$(cx_ec "$_c")
    [ "$xc" = "$_w" ] || bad "cx row $_id: CONTROL gave $xc, want $_w"
    [ "$x"  = "$_w" ] || bad "cx row $_id: gave $x, want $_w (cx must agree with every other target)"
    if [ -n "$A64" ]; then
        NA64=$((NA64 + 1))
        q=$(a64_ec "$_t")
        [ "$q" = "$_w" ] || bad "aarch64 row $_id: gave $q, want $_w"
    fi
}

# A — the filed repro: a bare forward-read of a literal constant.
_row A 5 'var cfb = cfa;\nvar cfa = 5;\nsyscall(60, cfb);\n' \
         'var cfa = 5;\nvar cfb = cfa;\nsyscall(60, cfb);\n'
# B — the forward read is part of an EXPRESSION, so the value must be there before the
#     replay evaluates it, not merely present by the end.
_row B 12 'var cfb = cfa * 2;\nvar cfa = 6;\nsyscall(60, cfb);\n' \
          'var cfa = 6;\nvar cfb = cfa * 2;\nsyscall(60, cfb);\n'
# C — TWO forward reads, folded: both constants must be prestored, not just the first.
_row C 5 'var cfb = CFA | CFB;\nvar CFA = 1;\nvar CFB = 4;\nsyscall(60, cfb);\n' \
         'var CFA = 1;\nvar CFB = 4;\nvar cfb = CFA | CFB;\nsyscall(60, cfb);\n'
# D — a forward read of a ZERO constant. The record is skipped for 0 (BSS is already zero and
#     gvar_initval uses 0 as "unrecorded"), so this row pins that the skip is still correct.
_row D 7 'var cfb = cfa;\nvar cfa = 0;\nvar cfc = cfb + 7;\nsyscall(60, cfc);\n' \
         'var cfa = 0;\nvar cfb = cfa;\nvar cfc = cfb + 7;\nsyscall(60, cfc);\n'
# E — THE NEGATIVE HALF: a COMPUTED initializer is not a constant and still runs in
#     declaration order on every target, so a forward read of one is 0. Prestoring everything
#     would change a documented behaviour. The control here spells the same 0 without a
#     forward reference at all.
_row E 0 'fn cff(): i64 { return 3; }\nvar cfb = cfa;\nvar cfa = cff();\nsyscall(60, cfb);\n' \
         'fn cff(): i64 { return 3; }\nvar cfz = 0;\nvar cfa = cff();\nvar cfb = cfz;\nsyscall(60, cfb);\n'
# F — a REDECLARATION whose later definition is constant wins from program start, on cx too.
#     This is the case _gv_cx_prestore already served; it must not be disturbed.
_row F 9 'var cfa = 5;\nvar cfb = cfa;\nvar cfa = 9;\nsyscall(60, cfb);\n' \
         'var cfa = 9;\nvar cfb = cfa;\nsyscall(60, cfb);\n'

# Anti-vacuity: the floor is DERIVED from this file's own row calls, and the cx leg must have
# run every one of them.
WANT=$(grep -cE '^_row [A-Z] ' "$0")
[ "$NROWS" -eq "$WANT" ] || bad "only $NROWS rows ran; this file spells $WANT"
[ "$NCX" -eq "$WANT" ] || bad "the cx leg ran $NCX of $WANT rows"
if [ -z "$A64" ]; then echo "  SKIP: aarch64 leg (qemu-aarch64 or the aarch64 fork unavailable)"; fi

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: cx_forward_read_constant_global: $NFAIL checks over $NROWS rows"
    exit 1
fi
echo "PASS: a forward-read constant global reads its value on cx as on every other target ($NROWS host + $NCX cx + $NA64 aarch64-under-qemu)"
exit 0
