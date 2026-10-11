#!/bin/sh
# Gate: a CONSTANT global holds its value from program start on cx, like every other target — a
# forward read sees it (6.6.6 bite 19d) and its initializer is never evaluated again at run time
# (6.7.9).
#
# THE DEFECTS:
#
#     var b = a;
#     var a = 5;
#     syscall(60, b);      x86 / aarch64 / Mach-O / PE: 5      cx at 6.6.5: 0
#
#     var Q = (0 - 0x7FFFFFFFFFFFFFFF - 1) / (0 - 1);      folds to INT_MIN (6.6.20)
#                          x86 / aarch64: INT_MIN              cx at 6.7.8: SIGFPE (136)
#
# The image targets bake a folded nonzero global into the file image (the static-init path) and
# never run its initializer. cx opted out of that path and kept the deferred replay
# (EMIT_GVAR_INITS, in declaration order) as the thing that gave a global its value. 6.6.6
# patched the forward read by recording the folded value for cx too (_gv_cx_prestore stores it at
# startup) — but the replay stayed, so cx evaluated the initializer AGAIN at run time: cxvm's
# `idiv` traps on INT_MIN / -1 (rows G H), the replay re-stored a constant over a value an
# earlier initializer's call had written (row I), and the replay order moved the implicit exit's
# "last var" (row J). 6.7.9 drops the opt-out: cx takes the static-init path, and the prestore
# is what gives it the value. src/frontend/parse_decl.cyr (PARSE_GVAR_REG, _gv_cx_prestore).
#
# EXPECTED VALUES are computed a DIFFERENT WAY from the actual, twice over: (1) every row is
# compared against a CONTROL — the same program declared in dependency order, or the same value
# spelled without the folded division — and (2) every row is run on the HOST as well, so cx is
# checked against a second implementation rather than against a number written in this file.
#
# ⚠ ROW E IS THE NEGATIVE HALF. A COMPUTED initializer (`var a = cf();`) is NOT constant and
# still runs in declaration order on every target — a forward read of one is 0 by design, and
# the guide says so. A "fix" that prestored everything would change that, so it is pinned.
# ⚠ NOT HERE: a folded ZERO (`var R = INT_MIN % -1;`) and an enum-named fold keep their run-time
# store on EVERY target (6.6.20's CHANGELOG), so they trap on x86 natively as on cx — cx agrees.
#
# LEGS: cx (the tree's own main_cx + cxvm — the defect's target), host x86_64, and aarch64
# under qemu-aarch64 when installed. qemu and cxvm are EMULATORS, not hardware.
#
# MUTATION LEDGER (6.7.9; 6.6.6's rows A-F re-proved on the new mechanism):
#   1. the 6.7.8 tree (the cx opt-out + 6.6.6's cx record)  -> RED cx rows G H I J
#   2. the opt-out restored alone (no cx record)            -> RED cx rows G H I J (A B C hold:
#      6.6.16's _gvk_pre records a deferred constant entry too, so the 6.6.6 record was redundant)
#   3. _gv_cx_prestore made a no-op                         -> RED cx sanity + rows A B C F G H
#   4. real tree                                            -> GREEN (10 host + 10 cx + 10 aarch64)
# ⚠ Each mutant is a scratch TREE and the gate is run from inside it, because the cx leg builds
#   `src/main_cx.cyr` from $ROOT — running a mutant merely as CYCC=<mutant> against the real
#   tree builds the REAL cx compiler and every row reads green. That was measured, not assumed.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: cx_forward_read_constant_global: cannot cd to $ROOT"; exit 1; }
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

# G — the 6.7.9 filed repro: a folded INT_MIN / -1 is the static value, never divided again at
#     run time (cxvm's `idiv` trapped). The control spells INT_MIN without the division.
_row G 7 'var cfq = (0 - 0x7FFFFFFFFFFFFFFF - 1) / (0 - 1);\nsyscall(60, (cfq == (0 - 0x7FFFFFFFFFFFFFFF - 1)) * 7);\n' \
         'var cfq = 0 - 0x7FFFFFFFFFFFFFFF - 1;\nsyscall(60, (cfq == (0 - 0x7FFFFFFFFFFFFFFF - 1)) * 7);\n'
# H — the same with INT_MIN spelled as hex.
_row H 8 'var cfq = 0x8000000000000000 / (0 - 1);\nsyscall(60, (cfq == 0x8000000000000000) * 8);\n' \
         'var cfq = 0x8000000000000000;\nsyscall(60, (cfq == 0x8000000000000000) * 8);\n'
# I — an EARLIER initializer's call writes a later constant global: the constant was the value
#     from program start, so the call's write stands (cx's replay stored 5 over it).
_row I 9 'fn cfs(): i64 { cfa = 9; return 1; }\nvar cfd = cfs();\nvar cfa = 5;\nsyscall(60, cfa);\n' \
         'fn cfs(): i64 { cfa = 9; return 1; }\nvar cfa = 5;\nvar cfd = cfs();\nsyscall(60, cfa);\n'
# J — the implicit exit (no syscall): the last var is the last REPLAYED one, as on the image
#     targets — a constant declared after a computed global no longer moves it on cx.
_row J 9 'fn cff(): i64 { return 9; }\nvar cfy = cff();\nvar cfx = 5;\n' \
         'fn cff(): i64 { return 9; }\nvar cfx = 5;\nvar cfy = cff();\n'

# Anti-vacuity: the floor is DERIVED from this file's own row calls, and the cx leg must have
# run every one of them.
WANT=$(grep -cE '^_row [A-Z] ' "$0")
[ "$NROWS" -eq "$WANT" ] || bad "only $NROWS rows ran; this file spells $WANT"
[ "$NCX" -eq "$WANT" ] || bad "the cx leg ran $NCX of $WANT rows"
if [ -z "$A64" ]; then echo "  SKIP: aarch64 leg (qemu-aarch64 or the aarch64 fork unavailable)"; GATE_SKIPS=$((${GATE_SKIPS:-0} + 1)); fi

if [ "$NFAIL" -gt 0 ]; then
    echo "FAIL: cx_forward_read_constant_global: $NFAIL checks over $NROWS rows"
    exit 1
fi
# 6.6.11 (K1): an axis that could not run makes the gate a SKIP (77), never a PASS.
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: cx_forward_read_constant_global — $GATE_SKIPS axis/leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: a constant global holds its value from program start on cx as on every other target, never re-evaluated ($NROWS host + $NCX cx + $NA64 aarch64-under-qemu)"
exit 0
