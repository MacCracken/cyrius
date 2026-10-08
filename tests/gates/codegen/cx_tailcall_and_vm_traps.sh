#!/bin/sh
# cx_tailcall_and_vm_traps.sh — cx emits real tail calls, cxvm traps every guest fault instead of
# performing it, and cx narrow stores are width-correct.
#
# 6.6.12 (B06; items Q6, V1-cx; the cxvm host-memory bug). Before it:
#   * the cx ETAILJMP emitted a normal call + epilogue, so every tail recursion grew BOTH VM stacks:
#     `tr(n-1, acc+1)` gave rc 0 at depth 512 and rc 1 at 513 / 1000 / 20,000,000 — the same source
#     exits 0 on x86;
#   * cxvm's 1024-entry call stack had no bound, so the 513th nested frame wrote into the next host
#     allocation (the loaded code); non-tail depth 1000 gave rc 231, 5000 gave 135;
#   * every guest load/store was `_cx_mem + reg` with no check: past 1 MB it read and wrote cxvm's own
#     heap, and guest address 0 (the bytecode copy) stored silently — `store64(0,5)` exited 9 on cxvm,
#     139 on x86. read()/getrandom()/clock_gettime() buffers were translated unchecked the same way;
#   * cx_run's if/elif chain had no trailing arm: an unknown opcode was a silent no-op;
#   * cx EVSTORE_W / EFLSTORE_W were plain 8-byte stores, so a store to a packed narrow global wrote
#     over its neighbours (V1's cx half).
#
# Shell gate, not a .tcyr: the traps are cxvm's exit code + stderr, and hand-made .cyx images are
# the only way to reach the unknown-opcode / stack-underflow / negative-pc arms. Every compiled row
# is ALSO run natively (the same source through build/cycc) wherever native has an answer to compare.
#
# AXES
#   A. tail calls: a 2,000,000-deep self tail recursion exits 0 on cx (61x the deepest non-tail
#      recursion cxvm's stacks can hold, so it only passes in constant stack; the 20,000,000 premise
#      repro passes too — measured 29 s on cxvm, too slow for every check.sh run); mutual tail
#      recursion, a tail call whose arguments are nested calls, a >6-arg tail-shaped call (normal
#      path) and a thin<->wide frame ping-pong all equal native. (6.7.3) A tail call inside a loop:
#      diverted when the loop takes a frame address after it (A3; cx gave 13 where 7 is right),
#      and kept, 2,000,000 deep, when the address comes only after the loop (A4).
#   B. deep NON-tail recursion: depth 1000 and 5000 now return the right value (they gave 231 / 135);
#      a runaway one traps LOUDLY ("cxvm: guest stack overflow") instead of overwriting the program's
#      globals and heap; hand-made images hit the call-stack and data-stack overflow traps and both
#      underflow traps.
#   C. an unknown opcode traps and names itself and its pc: "cxvm: unknown opcode 0xF0 at pc 4".
#   D. guest memory: a store to 0 traps (native: SIGSEGV), a store/load reaching past 1 MB traps, a
#      negative address traps, the last in-range byte works, a syscall buffer past 1 MB answers
#      -EFAULT without reaching the host, and a negative pc traps.
#   E. cx narrow stores: B01's row shapes (handoff B01-cx-rows.cyr, inlined) and statement-arm rows
#      on packed narrow globals and a narrow local seen through its address; each equals native.
#      ⚠ The B01 rows need F's B01 frontend fix too (the for step / compound load) — on a tree
#      without it they are RED natively as well, and the row says so.
#      6.6.13 (M1b): cx's constant PRESTORE (_gv_cx_prestore, parse_decl.cyr) stored 8 bytes too,
#      so before the next narrow global's own initialiser ran, a forward read of it saw the
#      prestored constant's upper bytes (E4: 255 where native gives 0; E5: every width).
#
# MUTATION LEDGER (6.6.12 B06, each by editing the tree and re-running this gate; measured with
# F's B01 frontend applied, since E1 needs it — 24/24 on the real tree)
#   ETAILJMP back to `ECALLFIX; EFNEPI`            -> A1 + A2 RED ("cxvm: guest stack overflow")
#   cxvm's trailing `else` removed                 -> C1 RED (exit 7, no diagnostic)
#   _cx_addr's two checks removed                  -> D1-D6 RED (every one exits 9, silently)
#   _cx_sysbuf translating without checking        -> D8 + D9 RED (156 and 0: the HOST was asked)
#   cx_call_push's bound removed                   -> B3 RED: the call stack overwrote cxvm's
#                                                       loaded code ("unknown opcode 0x04 at pc 0")
#                                                       — the cxvm host-memory bug in one row
#   cx_push's bound removed                        -> B4 RED (exit 0, the overflow went unseen)
#   cx_call_pop / cx_pop underflow checks removed  -> B5 / B6 RED (exit 0)
#   the guest-stack check on `sub sp` removed      -> B2 RED (the runaway recursion is caught only
#                                                       once sp goes negative, after it has
#                                                       overwritten the globals and the heap)
#   the negative-pc check removed                  -> D10 RED (decodes host memory: "... at pc -8")
#   cx EVSTORE_W / EFLSTORE_W back to 8-byte stores -> E1 (59) + E2 (15) + E3 (1) RED
#   (6.6.13) _gv_cx_prestore back to EVSTORE         -> E4 (255) + E5 (7) RED; native stays 0
#   (6.7.3) `_tcp_resolve` always keeps               -> A3 RED (native exits 5, the old wrong value;
#                                                       the frontend is shared, so `both` stops there)
#   (6.7.3) the loop's end never decides              -> A4 RED (native 139: the whole fn's flag
#           (`_tcp_loop_end` returns at once)              diverted the call, the stack overflowed)
#   (the narrow LOADS are width-correct too, but a wide masked load gives the same value except at
#   the very end of the data segment, which no compiled row can place a global at — not a row.)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: cx_tailcall_and_vm_traps — no compiler at $CC (exit 77: a SKIP, not a PASS)"; exit 77; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP: cx_tailcall_and_vm_traps — no timeout(1) (exit 77)"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT

"$CC" < src/main_cx.cyr > "$D/cc" 2> "$D/cc.err"; [ -s "$D/cc" ] || { echo "FAIL: cannot build the cx compiler from src/main_cx.cyr"; exit 1; }
"$CC" < programs/cxvm.cyr > "$D/vm" 2> "$D/vm.err"; [ -s "$D/vm" ] || { echo "FAIL: cannot build cxvm from programs/cxvm.cyr"; exit 1; }
chmod +x "$D/cc" "$D/vm"

pass=0; fail=0
ok()  { printf '  ok: %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail+1)); }

# cx_run SRC [secs] -> sets CXRC and CXERR (stderr's first line) for SRC compiled by the tree's cx
cx_run() {
    printf '%s' "$1" > "$D/c.cyr"
    CXRC=255; CXERR=''
    "$D/cc" < "$D/c.cyr" > "$D/c.cyx" 2> "$D/c.cerr" || { CXERR="cx compile failed: $(grep -v '^note' "$D/c.cerr" | head -1)"; CXRC=-1; return; }
    CXRC=0; ( ulimit -c 0; timeout "${2:-60}" "$D/vm" < "$D/c.cyx" ) > /dev/null 2> "$D/c.verr" || CXRC=$?
    CXERR=$(head -1 "$D/c.verr")
}
nat_run() {
    printf '%s' "$1" > "$D/n.cyr"
    NATRC=-1
    "$CC" < "$D/n.cyr" > "$D/n.bin" 2> /dev/null || return
    chmod +x "$D/n.bin"; NATRC=0
    { ( ulimit -c 0; timeout 60 "$D/n.bin" ) > /dev/null 2>&1 || NATRC=$?; } 2> /dev/null
}
# both LABEL SRC WANT: cx and native must both exit WANT
both() {
    nat_run "$2"; cx_run "$2" "${4:-60}"
    if [ "$NATRC" != "$3" ]; then bad "$1: native exits $NATRC, want $3 (the expectation itself is wrong, or the native frontend lacks a fix this row needs)"; return; fi
    if [ "$CXRC" = "$3" ]; then ok "$1 (cx $CXRC = native)"; else bad "$1: cx exits $CXRC (want $3, native $NATRC)${CXERR:+ — $CXERR}"; fi
}
# trap_src LABEL SRC PATTERN: cxvm must exit 1 with a stderr line matching PATTERN
trap_src() {
    cx_run "$2" 60
    if [ "$CXRC" = 1 ] && printf '%s' "$CXERR" | grep -q "$3"; then ok "$1 ($CXERR)"
    else bad "$1: cx exits $CXRC with '${CXERR}', want 1 and /$3/"; fi
}
# trap_img LABEL HEXWORDS PATTERN: a hand-made .cyx (header CYX\1 + entry 0) of little-endian words
trap_img() {
    # octal escapes, not \x: dash's printf has no \x
    : > "$D/i.cyx"
    printf 'CYX\001\000\000\000\000' >> "$D/i.cyx"
    for w in $2; do
        for b in $(printf '%s' "$w" | sed 's/\(..\)/\1 /g'); do printf "\\$(printf '%03o' "0x$b")" >> "$D/i.cyx"; done
    done
    IRC=0; ( ulimit -c 0; timeout 10 "$D/vm" < "$D/i.cyx" ) > /dev/null 2> "$D/i.err" || IRC=$?
    IERR=$(head -1 "$D/i.err")
    if [ "$IRC" = 1 ] && printf '%s' "$IERR" | grep -q "$3"; then ok "$1 ($IERR)"
    else bad "$1: cxvm exits $IRC with '${IERR}', want 1 and /$3/"; fi
}

echo "A. tail calls"
both "A1 2,000,000-deep self tail recursion" 'fn tr(n, acc): i64 {
    if (n == 0) { return acc; }
    return tr(n - 1, acc + 1);
}
var r = tr(2000000, 0);
if (r == 2000000) { syscall(60, 0); }
syscall(60, 3);
' 0 240
both "A2 tail calls: mutual, nested-call args, >6 args, thin<->wide frames" 'fn is_even(n): i64 { if (n == 0) { return 1; } return is_odd(n - 1); }
fn is_odd(n): i64 { if (n == 0) { return 0; } return is_even(n - 1); }
fn add(a, b): i64 { return a + b; }
fn mul(a, b): i64 { var t = a * b; return t; }
fn nest(n, acc, k): i64 {
    if (n == 0) { return acc + k; }
    return nest(n - 1, add(acc, mul(n, 2)), add(k, 1));
}
fn big(a, b, c, d, e, f, g): i64 { return a + b + c + d + e + f + g; }
fn call7(n): i64 { return big(n, 1, 2, 3, 4, 5, 6); }
fn thin(n): i64 { if (n == 0) { return 5; } return wide(n - 1, n, n); }
fn wide(n, a, b): i64 { var l1 = a; var l2 = b; var l3 = l1 + l2; var l4 = l3; var l5 = l4; var l6 = l5; if (n == 0) { return l6; } return thin(n - 1); }
fn main(): i64 {
    var r = 0;
    if (is_even(300000) == 1) { r = r + 1; }
    if (is_odd(300001) == 1) { r = r + 2; }
    if (nest(100000, 0, 0) == 10000200000) { r = r + 4; }
    if (call7(10) == 31) { r = r + 8; }
    if (thin(200000) == 5) { r = r + 16; }
    if (thin(200001) == 2) { r = r + 32; }
    return r;
}
syscall(60, main());
' 63 240
# 6.7.3 — a tail call inside a loop is decided at the end of its outermost loop: diverted when the
# loop takes a frame address after it (cx read 13 where 7 is right: the `jmp` freed the frame `x`
# points into), kept otherwise — here with the address taken only after the loop, which the whole
# fn's flag would have diverted (a 2,000,000-deep recursion then overflows cxvm's stacks).
both "A3 an in-loop tail call before 'x = &s' diverts (6.7.3)" 'struct P3 { a; b; c; }
fn rd(p, k) {
    var j1 = 901; var j2 = 902; var j3 = 903; var j4 = 904; var j5 = 905; var j6 = 906;
    return load64(p) + load64(p + 8) + load64(p + 16) + k + (j1 + j2 + j3 + j4 + j5 + j6) - 5421;
}
fn f(k) {
    var s = P3 { 1, 2, 3 };
    var x = 0;
    var i = 0;
    while (i < 2) {
        if (i == 1) { return rd(x, k); }
        x = &s;
        i = i + 1;
    }
    return 0;
}
syscall(60, f(1));
' 7
both "A4 2,000,000-deep in-loop self tail call, the address taken after the loop (6.7.3)" 'struct P3 { a; b; c; }
fn after(n, acc): i64 {
    var s = P3 { 1, 2, 3 };
    while (1) {
        if (n == 0) { break; }
        return after(n - 1, acc + 1);
    }
    var x = &s;
    return acc + load64(x + 8) - 2;
}
var r = after(2000000, 0);
if (r == 2000000) { syscall(60, 0); }
syscall(60, 3);
' 0 240

echo "B. deep non-tail recursion and the VM stacks"
for n in 1000 5000; do
    both "B1 non-tail recursion depth $n returns the right value" "fn nt(n): i64 { if (n == 0) { return 0; } var x = nt(n - 1); return x + 1; }
var r = nt($n);
if (r == $n) { syscall(60, 0); }
syscall(60, 3);
" 0
done
trap_src "B2 runaway non-tail recursion traps loudly" 'var G = 77;
fn nt(n): i64 { if (n == 0) { return G; } var x = nt(n - 1); return x + 1; }
syscall(60, nt(10000000));
' '^cxvm: guest stack overflow, sp [0-9]* at pc [0-9]*$'
#               call +0 (0x60 00 00 00) forever: the call stack overflows, nothing touches guest memory
trap_img "B3 call-stack overflow" '60000000' '^cxvm: call stack overflow, depth 65536 at pc 0$'
#               push r0; jmp -1
trap_img "B4 data-stack overflow" '80000000 50ffffff' '^cxvm: data stack overflow, depth 65536 at pc 0$'
trap_img "B5 call-stack underflow (ret on an empty stack)" '61000000' '^cxvm: call stack underflow, depth 0 at pc 0$'
trap_img "B6 data-stack underflow (pop on an empty stack)" '81000000' '^cxvm: data stack underflow, depth 0 at pc 0$'

echo "C. unknown opcode"
#               movi r0, 7; <0xF0>; <0xFA>; halt
# The probe byte sits in the unallocated 0xF0-0xFC band, far from the growth frontier: it was
# 0x6E until 6.6.13 made 0x6E ftrunc, and C1 then saw the NEXT unknown byte. CHANGELOG [6.6.13]
trap_img "C1 unknown opcode names itself and its pc" '01000700 F0000000 FA000000 00000000' '^cxvm: unknown opcode 0xF0 at pc 4$'

echo "D. guest memory"
nat_run 'store64(0, 5);
var v = load64(0);
syscall(60, 9);
'
if [ "$NATRC" = 139 ]; then ok "D0 native answers a store to 0 with SIGSEGV (139)"; else bad "D0 native store to 0 exited $NATRC, want 139"; fi
trap_src "D1 store64 to guest 0 traps" 'store64(0, 5);
syscall(60, 9);
' '^cxvm: guest address out of range: 0 at pc [0-9]*$'
trap_src "D2 load8 from guest 7 traps (the null page is [0, 8))" 'var v = load8(7);
syscall(60, 9);
' '^cxvm: guest address out of range: 7 at pc'
trap_src "D3 store64 reaching past 1 MB traps" 'store64(1048572, 5);
syscall(60, 9);
' '^cxvm: guest address out of range: 1048572 at pc'
trap_src "D4 load64 reaching past 1 MB traps" 'var v = load64(1048569);
syscall(60, 9);
' '^cxvm: guest address out of range: 1048569 at pc'
trap_src "D5 store8 at 1 MB traps" 'store8(1048576, 1);
syscall(60, 9);
' '^cxvm: guest address out of range: 1048576 at pc'
trap_src "D6 a negative guest address traps" 'store64(0 - 8, 1);
syscall(60, 9);
' '^cxvm: guest address out of range: -8 at pc'
cx_run 'var v = load8(1048575) + load64(1048568);
syscall(60, 9);
'
if [ "$CXRC" = 9 ]; then ok "D7 the last in-range byte and qword load"; else bad "D7 in-range loads at the top of 1 MB exited $CXRC ($CXERR), want 9"; fi
cx_run 'var r = syscall(1, 1, 1048570, 100);
syscall(60, 0 - r);
'
if [ "$CXRC" = 14 ]; then ok "D8 write() from a buffer reaching past 1 MB answers -EFAULT"; else bad "D8 write() past 1 MB exited $CXRC ($CXERR), want 14 (-EFAULT)"; fi
cx_run 'var r = syscall(0, 0, 1048570, 100);
syscall(60, 0 - r);
'
if [ "$CXRC" = 14 ]; then ok "D9 read() into a buffer reaching past 1 MB answers -EFAULT"; else bad "D9 read() past 1 MB exited $CXRC ($CXERR), want 14 (-EFAULT)"; fi
#               jmp -2 at pc 0 -> pc -8
trap_img "D10 a jump to a negative pc traps" '50feffff' '^cxvm: jump to a negative code offset: -8 at pc 0$'

echo "E. cx narrow stores (V1's cx half)"
both "E1 B01 row shapes (for step, compound step/load, u16, i8)" 'var P_A: u8 = 5;
var P_B: u8 = 7;
var P_C: u8 = 9;
var P_D: u8 = 13;
var K_A: u8 = 5;
var K_B: u8 = 7;
var S_A: u8 = 4;
var S_B: u8 = 1;
var S_E: i8 = 0 - 4;
var S_F: i8 = 0 - 1;
var H_A: u16 = 3;
var H_B: u16 = 0x1234;
fn go(): i64 {
    var bad = 0;
    for (P_A = 250; P_A != 252; P_A = P_A + 1) { }
    if (P_A != 252 || P_B != 7 || P_C != 9 || P_D != 13) { bad = bad | 1; }
    for (K_A = 254; K_A != 1; K_A += 1) { }
    if (K_A != 1 || K_B != 7) { bad = bad | 2; }
    var i: u8 = 5;
    for (i = 254; i != 1; i += 1) { }
    i >>= 1;
    if (i != 0) { bad = bad | 4; }
    S_A >>= 1;
    if (S_A != 2 || S_B != 1) { bad = bad | 8; }
    S_E += 1;
    if (S_E != 0 - 3 || S_F != 0 - 1) { bad = bad | 16; }
    for (H_A = 0xFFFE; H_A != 1; H_A += 1) { }
    if (H_A != 1 || H_B != 0x1234) { bad = bad | 32; }
    var c: i8 = 0 - 8;
    c /= 2;
    if (c != 0 - 4) { bad = bad | 64; }
    return bad;
}
syscall(60, go());
' 0
both "E2 statement-arm stores to packed narrow globals keep their neighbours" 'var A: u8 = 5;
var B: u8 = 7;
var C: u16 = 0x1234;
var E: u16 = 9;
var F: u32 = 1;
var G: u32 = 2;
var H: i8 = 0 - 3;
var I: i8 = 4;
fn go(): i64 {
    var bad = 0;
    A = 250;
    if (A != 250 || B != 7) { bad = bad | 1; }
    C = 0xFFFF;
    if (C != 0xFFFF || E != 9) { bad = bad | 2; }
    F = 0xFFFFFFFF;
    if (F != 0xFFFFFFFF || G != 2) { bad = bad | 4; }
    H = 0 - 100;
    if (H != 0 - 100 || I != 4) { bad = bad | 8; }
    return bad;
}
syscall(60, go());
' 0
both "E3 a narrow local store writes only its own width" 'fn go(): i64 {
    var x: u8 = 0;
    store64(&x, 0x1122334455667788);
    x = 1;
    if (load64(&x) != 0x1122334455667701) { return 1; }
    var y: u16 = 0;
    store64(&y, 0x1122334455667788);
    y = 2;
    if (load64(&y) != 0x1122334455660002) { return 2; }
    var z: u32 = 0;
    store64(&z, 0x1122334455667788);
    z = 3;
    if (load64(&z) != 0x1122334400000003) { return 3; }
    return 0;
}
syscall(60, go());
' 0
both "E4 cx prestore of a constant narrow global keeps the next one (a forward read sees its own init)" 'fn getb(): i64 { return b; }
var a: i8 = 0 - 1;
var c: u8 = getb();
var b: u8 = 0;
syscall(60, c);
' 0
both "E5 cx prestore at every narrow width: the reader before the pair, the pair intact" 'fn get8(): i64 { return B8; }
fn get16(): i64 { return B16; }
fn get32(): i64 { return B32; }
var C8: u8 = get8();
var A8: i8 = 0 - 1;
var B8: u8 = 0;
var S8 = 0x0102030405060708;
var C16: u16 = get16();
var A16: i16 = 0 - 1;
var B16: u16 = 0;
var S16 = 0x0102030405060708;
var C32: u32 = get32();
var A32: i32 = 0 - 1;
var B32: u32 = 0;
var r = 0;
if (C8 != 0 || A8 != 0 - 1 || B8 != 0) { r = r | 1; }
if (C16 != 0 || A16 != 0 - 1 || B16 != 0) { r = r | 2; }
if (C32 != 0 || A32 != 0 - 1 || B32 != 0) { r = r | 4; }
syscall(60, r);
' 0

echo "cx_tailcall_and_vm_traps: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
echo "PASS: cx_tailcall_and_vm_traps (cx tail calls run in constant stack; cxvm traps every guest fault; cx narrow stores are width-correct)"
