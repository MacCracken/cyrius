#!/bin/sh
# cx_relational_or_equal.sh — `<=` and `>=` produce the right boolean on cx.
#
# v6.6.6. cx has single opcodes for lt/gt/eq/ne but none for lte/gte, so
# `src/backend/cx/emit.cyr` ESETCC synthesizes them as `(a<b)|(a==b)`. The
# strict half was emitted as `lt r0, r1, r0` — destination r0 instead of the
# scratch r2 that the closing `or` reads, AND operands swapped — so:
#   * the strict half was computed backwards and then overwritten by the `eq`;
#   * the `or` folded in whatever r2 held from an EARLIER emit (ESHLIMM's shift
#     immediate is the common writer, so a `g * 8` anywhere before the compare
#     poisoned it).
# `a <= b` / `a >= b` were therefore wrong for every rhs but 0, and wrong even
# for rhs 0 once anything had left r2 non-zero. `<`/`>`/`==`/`!=` are single
# opcodes and were never affected, which is why this hid: `lib/assert.cyr`
# assert_gte/assert_lte failed while assert_gt/assert_lt passed, and
# `lib/vec.cyr` vec_get's `idx >= len` guard aborted on a populated vec.
#
# Shell gate, not a .tcyr, for the cx_multi_return.sh reason: a .tcyr pulls in
# assert/fmt, which the cx backend cannot compile, so a .tcyr structurally
# cannot cover the one target the bug lives on.
#
# Every case is checked TWICE against independently-derived expectations: the
# hard-coded exit code written next to it, and the exit code the SAME source
# produces through the x86 backend (a different compiler fork, a different
# emitter, real hardware). A wrong hard-coded number fails against native; a
# backend that agrees with native for the wrong reason still fails the literal.
#
# Mutation ledger (v6.6.6):
#   real tree                                          -> GREEN (12/12)
#   ESETCC ops 21+22 reverted to `CX_EMIT(S,50,0,1,0)`
#   / `CX_EMIT(S,51,0,1,0)` in a tree copy              -> RED, 7 of 12 axes
#     (lte true+equal, gte true+equal, arg-position, stale-r2 guard, vec_get)
#   op 21 (lte) alone reverted                          -> RED, 3 of 12
#   op 22 (gte) alone reverted                          -> RED, 4 of 12
#   controls (lt/gt/eq/ne) stay GREEN under every mutant, as they must.
# ⚠ Swapping build/cycc does NOT mutate this gate — it builds the cx compiler
# from src/backend/cx/emit.cyr in the WORKING TREE, so an old host compiler still
# picks up the current emitter and the gate passes vacuously (the cx_multi_return
# caveat, which is why the mutants above edit the emitter, not the binary).
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT
[ -x ./build/cycc ] || { echo "FAIL: build/cycc missing"; exit 1; }

cat src/main_cx.cyr | ./build/cycc > "$D/cc" 2>/dev/null
[ -s "$D/cc" ] || { echo "FAIL: cx compiler build produced nothing"; exit 1; }
chmod +x "$D/cc"
cat programs/cxvm.cyr | ./build/cycc > "$D/vm" 2>/dev/null
[ -s "$D/vm" ] || { echo "FAIL: cxvm build produced nothing"; exit 1; }
chmod +x "$D/vm"

pass=0; fail=0
run_case() {  # $1 label  $2 source  $3 expected exit code
    printf '%s' "$2" > "$D/c.cyr"

    # oracle: the same source through the x86 backend
    cat "$D/c.cyr" | ./build/cycc > "$D/c.bin" 2>/dev/null
    [ -s "$D/c.bin" ] || { echo "  FAIL: $1 (empty native binary)"; fail=$((fail+1)); return; }
    chmod +x "$D/c.bin"
    NAT=0
    ( ulimit -c 0; "$D/c.bin" ) >/dev/null 2>&1 || NAT=$?

    cat "$D/c.cyr" | "$D/cc" > "$D/c.cyx" 2>/dev/null
    [ -s "$D/c.cyx" ] || { echo "  FAIL: $1 (empty .cyx)"; fail=$((fail+1)); return; }
    CX=0
    ( ulimit -c 0; timeout 30 "$D/vm" < "$D/c.cyx" ) >/dev/null 2>&1 || CX=$?

    if [ "$NAT" != "$3" ]; then
        printf '  FAIL: %-34s native=%s (want %s) — the expectation itself is wrong\n' "$1" "$NAT" "$3"
        fail=$((fail+1)); return
    fi
    if [ "$CX" = "$3" ]; then
        printf '  ok: %-36s cx=%s native=%s\n' "$1" "$CX" "$NAT"; pass=$((pass+1))
    else
        printf '  FAIL: %-34s cx=%s (want %s, native=%s)\n' "$1" "$CX" "$3" "$NAT"; fail=$((fail+1))
    fi
}

echo "axis 1 — <= and >= in an if guard (all three orderings):"
run_case "3 <= 7" 'fn m(): i64 { var a = 3; var b = 7; if (a <= b) { return 21; } return 0; }
var r = m(); syscall(60, r);
' 21
run_case "7 <= 7" 'fn m(): i64 { var a = 7; var b = 7; if (a <= b) { return 22; } return 0; }
var r = m(); syscall(60, r);
' 22
run_case "9 <= 7 (false)" 'fn m(): i64 { var a = 9; var b = 7; if (a <= b) { return 23; } return 0; }
var r = m(); syscall(60, r);
' 0
run_case "100 >= 32" 'fn m(): i64 { var a = 100; var b = 32; if (a >= b) { return 31; } return 0; }
var r = m(); syscall(60, r);
' 31
run_case "32 >= 32" 'fn m(): i64 { var a = 32; var b = 32; if (a >= b) { return 32; } return 0; }
var r = m(); syscall(60, r);
' 32
run_case "31 >= 32 (false)" 'fn m(): i64 { var a = 31; var b = 32; if (a >= b) { return 33; } return 0; }
var r = m(); syscall(60, r);
' 0

echo "axis 2 — the assert(a >= b, name) shape: a comparison as a CALL ARGUMENT:"
run_case "chk(a >= b) true" 'fn chk(cond, tag): i64 { if (cond == 1) { return tag; } return 0; }
fn m(): i64 { var a = 100; var b = 32; return chk(a >= b, 41); }
var r = m(); syscall(60, r);
' 41
run_case "chk(a <= b) false" 'fn chk(cond, tag): i64 { if (cond == 1) { return tag; } return 42; }
fn m(): i64 { var a = 100; var b = 32; return chk(a <= b, 41); }
var r = m(); syscall(60, r);
' 42

echo "axis 3 — a power-of-two multiply earlier leaves the scratch non-zero:"
run_case "g*8 then size <= 0 guard" 'var zend = 0;
var ZSLOTS = 16384;
fn zinit(): i64 { zend = ZSLOTS * 8; return 0; }
fn zalloc(size): i64 { if (size <= 0) { return 0; } return size; }
var q = zinit();
var a = zalloc(64);
syscall(60, a);
' 64

echo "axis 4 — the vec_get bounds-guard shape (idx >= len on a populated vec):"
run_case "vget(0) of a 1-element vec" 'var vdata = 0;
var vlen = 0;
var velem0 = 0;
fn vget(idx): i64 {
    if (idx < 0) { return 91; }
    if (idx >= vlen) { return 92; }
    return load64(vdata + idx * 8);
}
fn m(): i64 { velem0 = 11; vdata = &velem0; vlen = 1; return vget(0); }
var r = m(); syscall(60, r);
' 11

echo "axis 5 — controls: the single-opcode comparisons must stay right:"
run_case "< > == != still right" 'fn m(): i64 { var a = 3; var b = 7; var n = 0;
    if (a < b) { n = n + 1; }
    if (b > a) { n = n + 2; }
    if (a == 3) { n = n + 4; }
    if (a != b) { n = n + 8; }
    if (b < a) { n = n + 16; }
    return n; }
var r = m(); syscall(60, r);
' 15
run_case "g*8 then size < 1 guard" 'var zend = 0;
var ZSLOTS = 16384;
fn zinit(): i64 { zend = ZSLOTS * 8; return 0; }
fn zalloc(size): i64 { if (size < 1) { return 0; } return size; }
var q = zinit();
var a = zalloc(64);
syscall(60, a);
' 64

echo "cx_relational_or_equal: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
