#!/bin/sh
# Gate: on cx a global array initializer stores the SAME BYTES every image target bakes
# (6.6.16, C1).
#
# ⛔ WHY. Every image target now evaluates `var X: T[N] = { .. }` into a blob and copies it into
# the file image (src/frontend/parse_decl.cyr, "Global array initializers"). cx has no file image —
# cxvm allocates the globals and zeroes them — so it alone turns the same blob into run-time
# stores at the replay point (_gai_cx): 8-byte words, the tail BYTE BY BYTE (an 8-byte store past
# a 12-byte array lands on the next global, which is packed right behind it), a zero word skipped
# on a fresh blob and stored when an earlier declaration of the slot wrote the blob too. Two
# implementations of one meaning, so they are run against each other. At the 6.6.16 slot open the
# list was bytes on cx as everywhere: `var T: i64[3] = {1,2,42}; var W: u16[3] = {1,2,42};
# syscall(60, T[2] + W[2] + 100)` exited 100.
#
# HOW. Each row is one program, run on the HOST (x86_64 ELF, the image bake), on cx (the tree's
# own src/main_cx.cyr + programs/cxvm.cyr) and, when qemu-aarch64 is installed, on aarch64 (the
# aarch64 image writer). The program hashes the arrays' bytes (h = h * 31 + byte), writes the 8
# raw bytes of h, and exits with a bitmask of spot checks — so a row fails if the host itself is
# wrong (exit != 0), or if cx / aarch64 disagree with the host on ANY byte (the hash). qemu and
# cxvm are emulators, not hardware: the crossos tcyr runs the image targets on real hosts.
#   A  integer elements i8..u32/i64, range ends, bare and qualified enums, an enum declared BELOW
#   B  f64 / f32 / u128 elements (the f32 narrowing, the u128 high word)
#   C  the bare byte list with a ZERO first word (skipped on a fresh blob) and an enum element
#   D  a 12-byte array with a u8 packed right after it (the tail). ⚠ The neighbour is a REDECLARED
#      constant: cx prestores it and its first entry is superseded, so nothing re-stores it after the
#      array's replay. A plain `var D2: u8 = 0x5A;` is stored AGAIN in declaration order on cx (it
#      keeps its runtime store), which repaired a clobber and hid it — measured: the tail mutant
#      below read GREEN against that shape.
#   E  a redeclared array: the second list writes ZEROS over the first one's bytes (stored, not
#      skipped, because the blob is shared) and keeps the bytes it does not list
#   F  a bare array redeclaring a scalar constant keeps the scalar's other bytes (the seed)
#   G  a declaration after the first top-level statement
#   H  an array entry superseded by a later constant declaration writes nothing
#   I  a 4800-byte array: words far past any short displacement
# MUTATION LEDGER (6.6.16, scratch trees, the gate run from inside each):
#   1. real tree                                            -> GREEN (9 rows + sanity)
#   2. _gai_cx's tail stored as a whole 8-byte word         -> RED, 2 checks: D (the packed neighbour)
#   3. _gai_cx skipping zero words on a SHARED blob         -> RED, 2 checks: E
#   4. _gai_eval's cx call removed                          -> RED, 16 checks: the rows on cx
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
[ -x "$CC" ] || { echo "FAIL: cx_array_initializer: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cx_array_initializer: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
fail=0
rows=0
na64=0
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

"$CC" < src/main_cx.cyr > "$T/cycc_cx" 2> "$T/eb" && [ -s "$T/cycc_cx" ] || { echo "FAIL: cx_array_initializer: cannot build src/main_cx.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
"$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/eb" && [ -s "$T/cxvm" ] || { echo "FAIL: cx_array_initializer: cannot build programs/cxvm.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/cycc_cx" "$T/cxvm"
A64=""
if command -v qemu-aarch64 > /dev/null 2>&1; then
    "$CC" < src/main_aarch64.cyr > "$T/cycc_a64" 2> "$T/eb" && [ -s "$T/cycc_a64" ] || { echo "FAIL: cx_array_initializer: cannot build src/main_aarch64.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
    chmod +x "$T/cycc_a64"
    A64="$T/cycc_a64"
fi

HB='fn hb(h, a, n): i64 { var i = 0; while (i < n) { h = h * 31 + load8(a + i); i = i + 1; } return h; }'
OUT='syscall(1, 1, &h, 8);\nsyscall(60, bad);\n'

# row <id> <body>  (the body declares, sets h and bad; the harness adds the hash fn and the output)
row() {
    rows=$((rows + 1))
    printf '%s\n%b%b' "$HB" "$2" "$OUT" > "$T/$1.cyr"
    if ! "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err"; then bad "$1 host: does not compile: $(grep -m1 '^error' "$T/$1.err")"; return; fi
    chmod +x "$T/$1.bin"
    hr=0; "$T/$1.bin" > "$T/$1.h" 2>/dev/null || hr=$?
    [ "$hr" = 0 ] || bad "$1 host: a spot check failed (exit $hr)"
    [ "$(wc -c < "$T/$1.h")" -eq 8 ] || { bad "$1 host: wrote no hash"; return; }
    if ! "$T/cycc_cx" < "$T/$1.cyr" > "$T/$1.cyx" 2> "$T/$1.cxerr"; then bad "$1 cx: does not compile: $(grep -m1 '^error' "$T/$1.cxerr")"; return; fi
    cr=0; "$T/cxvm" < "$T/$1.cyx" > "$T/$1.c" 2>/dev/null || cr=$?
    [ "$cr" = 0 ] || bad "$1 cx: a spot check failed (exit $cr)"
    cmp -s "$T/$1.h" "$T/$1.c" || bad "$1 cx: the arrays' bytes differ from the host's"
    if [ -n "$A64" ]; then
        na64=$((na64 + 1))
        if ! "$A64" < "$T/$1.cyr" > "$T/$1.a" 2> "$T/$1.aerr"; then bad "$1 aarch64: does not compile"; return; fi
        chmod +x "$T/$1.a"
        ar=0; qemu-aarch64 "$T/$1.a" > "$T/$1.ao" 2>/dev/null || ar=$?
        [ "$ar" = 0 ] || bad "$1 aarch64: a spot check failed (exit $ar)"
        cmp -s "$T/$1.h" "$T/$1.ao" || bad "$1 aarch64: the arrays' bytes differ from the host's"
    fi
}

# The cx toolchain must get a program right that it never got wrong, or every row could agree on
# an error and read green.
printf 'var s = 0;\nvar t = 2;\ns = t * 10;\nsyscall(60, s);\n' > "$T/sane.cyr"
"$T/cycc_cx" < "$T/sane.cyr" > "$T/sane.cyx" 2>/dev/null
sr=0; "$T/cxvm" < "$T/sane.cyx" > /dev/null 2>&1 || sr=$?
[ "$sr" = 20 ] || bad "cx sanity program exited $sr, want 20 (the cx toolchain is broken; the rows would be vacuous)"

row A 'enum CE { CA = 3; CB = 0x40; }
var A1: i64[3] = {1, -2, 0x7FFFFFFFFFFFFFFF};
var A2: i8[4] = {-128, 127, 0xFF, CA};
var A3: u16[3] = {0xFFFF, CE.CB, CA * 2 + 1};
var A4: i32[2] = {-2147483648, CF.CZ};
var A5: u32[2] = {0xFFFFFFFF, 1 << 20};
enum CF { CZ = 77; }
var h = 7;
h = hb(h, &A1, 24); h = hb(h, &A2, 4); h = hb(h, &A3, 6); h = hb(h, &A4, 8); h = hb(h, &A5, 8);
var bad = 0;
if (A1[1] != -2) { bad = bad | 1; }
if (A2[2] != -1) { bad = bad | 2; }
if (A3[2] != 7) { bad = bad | 4; }
if (A4[1] != 77) { bad = bad | 8; }
if (A3[0] + A3[1] + A2[3] != 0xFFFF + 0x40 + 3) { bad = bad | 16; }
'
row B 'var B1: f64[3] = {1.5, -2.25, 0.1};
var B2: f32[4] = {1.5, -0.1, 340282346638528859811704183484516925440.0, 0.00000000000000000000000000000000000000000000140129846432481707};
var B3: u128[2] = {7, -1};
var h = 7;
h = hb(h, &B1, 24); h = hb(h, &B2, 16); h = hb(h, &B3, 32);
var bad = 0;
if (load64(&B1 + 8) != 0xC002000000000000) { bad = bad | 1; }
if (load32(&B2) != 0x3FC00000) { bad = bad | 2; }
if (load32(&B2 + 8) != 0x7F7FFFFF) { bad = bad | 4; }
if (load32(&B2 + 12) != 1) { bad = bad | 8; }
if (load64(&B3 + 16) != -1) { bad = bad | 16; }
if (load64(&B3 + 24) != 0) { bad = bad | 32; }
'
row C 'enum DE { DA = 0x41; }
var C1[2] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 0, DA, 0, 255};
var h = 7;
h = hb(h, &C1, 16);
var bad = 0;
if (load64(&C1) != 0) { bad = bad | 1; }
if (load8(&C1 + 10) != 0x41) { bad = bad | 2; }
if (load8(&C1 + 12) != 255) { bad = bad | 4; }
'
row D 'var D1: u8[12] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
var D2: u8 = 0x11;
var D2: u8 = 0x5A;
var D3: i64 = 0x0123456789ABCDEF;
var D4: u16[3] = {0x1111, 0x2222, 0x3333};
var D5: u8 = 0x6B;
var h = 7;
h = hb(h, &D1, 12); h = hb(h, &D2, 1); h = hb(h, &D3, 8); h = hb(h, &D4, 6); h = hb(h, &D5, 1);
var bad = 0;
if (D2 != 0x5A) { bad = bad | 1; }
if (D3 != 0x0123456789ABCDEF) { bad = bad | 2; }
if (load8(&D1 + 11) != 12) { bad = bad | 4; }
if (D5 != 0x6B) { bad = bad | 8; }
if (D4[2] != 0x3333) { bad = bad | 16; }
'
row E 'var E1[2] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
var E1[2] = {0, 0, 7};
var h = 7;
h = hb(h, &E1, 16);
var bad = 0;
if (load8(&E1) + load8(&E1 + 1) != 0) { bad = bad | 1; }
if (load8(&E1 + 2) != 7) { bad = bad | 2; }
if (load8(&E1 + 3) != 4) { bad = bad | 4; }
if (load8(&E1 + 9) != 10) { bad = bad | 8; }
'
row F 'var F1 = 0x0505;
var F1[1] = {7};
var h = 7;
h = hb(h, &F1, 8);
var bad = 0;
if (load64(&F1) != 0x0507) { bad = bad | 1; }
'
row G 'enum GE { GA = 6; }
var G0 = 1;
syscall(1, 1, "", 0);
var G1: i64[2] = {GE.GA, -1};
var G2[1] = {9, 8};
var G3: u16[2] = {0xFFFF, 2};
var h = 7;
h = hb(h, &G1, 16); h = hb(h, &G2, 8); h = hb(h, &G3, 4);
var bad = 0;
if (G1[0] != 6) { bad = bad | 1; }
if (load8(&G2 + 1) != 8) { bad = bad | 2; }
if (G3[0] != 0xFFFF) { bad = bad | 4; }
'
row H 'var H1[1] = {7};
var H1 = 5;
var h = 7;
h = hb(h, &H1, 8);
var bad = 0;
if (H1 != 5) { bad = bad | 1; }
'
IL=$(awk 'BEGIN { for (i = 0; i < 600; i++) { printf "%s%d", (i ? ", " : ""), (i % 7 == 0 ? 0 : i * 1000003) } }')
row I "var I1: i64[600] = {$IL};
var h = 7;
h = hb(h, &I1, 4800);
var bad = 0;
if (I1[599] != 599 * 1000003) { bad = bad | 1; }
if (I1[598] != 598 * 1000003) { bad = bad | 2; }
if (I1[595] != 0) { bad = bad | 4; }
"

[ "$rows" -ge 9 ] || bad "only $rows rows ran (floor 9)"
if [ "$fail" -ne 0 ]; then
    echo "FAIL: cx_array_initializer ($fail checks failed over $rows rows)"
    exit 1
fi
if [ -n "$A64" ]; then
    echo "PASS: cx_array_initializer ($rows rows: host, cx, aarch64 under qemu)"
else
    echo "PASS: cx_array_initializer ($rows rows: host, cx; aarch64 not run, no qemu-aarch64)"
fi
exit 0
