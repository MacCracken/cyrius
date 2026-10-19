#!/bin/sh
# check: serial — a timing/scaling measurement; the parallel check.sh runs it alone, after its pool
# double_pointer_pin_scale_linear.sh — 6.7.15. Compile time is LINEAR in the number of distinct `**T` pointees.
#
# THE DEFECT (issues/2026-10-17-pointer-to-pointer-pin-intern-is-a-linear-search.md). A `**T`'s step word pins its
# pointee's word in a table (6.7.13), and `_pp_intern` (src/frontend/parse_types.cyr) found an existing pin by scanning
# every pin so far. 6.7.14 raised the cap from 126 pins to 16383, so the scan ran up to 16383 entries per intern and a
# unit with thousands of distinct pointees compiled in quadratic time. The filed generator, 1024 structs each taken
# through `**S` .. K + 1 stars (1024 x K pins), on x86_64 at 6.7.14:
#
#     K=2 (2048 pins) 199 ms    K=4 (4096) 437 ms    K=8 (8192) 1,224 ms    K=15 (15360) 4,543 ms
#
# Fixed with an open-addressing index over (step word, field entry, struct) beside the pin tables (`_pp_hix`, alloc()'d,
# rebuilt as the tables double); pins keep their first-come numbers (the 657-file tcyr corpus compiles byte-identical
# to the scan's output). After: K=4 351 ms, K=15 1,333 ms.
#
# ⚠ THE ACCEPTANCE IS A RATIO, NOT A WALL-CLOCK BOUND (the globals_scale_linear.sh rule): K=4 and K=15 compiled back
# to back, best of 3 each; 3.75x the pins must cost under 6.0x — linear is ~3.8x, the quadratic scan ~10x.
#   S1 K=4 -> K=15: ratio under 6.0x
#   S2 the K=15 program compiles (rc 0, no error or warning) and its binary exits 0
# The pins' meaning (a pin per pointee and struct, past pin 1500, the 16383 cap) is double_pointer_pin_capacity.sh's.
#
# MUTATION (2026-10-18, measured: `_pp_intern`'s linear scan restored — the tree before this fix, two-stage, with
# CYCC=<it>): S1 RED (K=4 425 ms -> K=15 4,426 ms, 10.4x); S2 green. The fix: 348 ms -> 1,290 ms, 3.7x.
#
# ⚠ NO `set -e`: timings and exit codes are DATA.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=double_pointer_pin_scale_linear
[ -x "$CC" ] || { echo "FAIL: $G: $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT

gen() {  # gen K > file: 1024 structs, each taken through `**S` .. K + 1 stars (the filed generator)
    awk -v K="$1" 'BEGIN{for(i=0;i<1024;i++){printf "struct S%d { a; b; }\n",i; st="*"; for(d=2;d<=K+1;d++){st=st "*";
         printf "fn f%d_%d(pp: %sS%d): i64 { return 0; }\n",i,d,st,i}}
         print "fn main(): i64 { return 0; }"; print "syscall(60, main());"}'
}
best() {  # best-of-3 wall ms for compiling $1 (-1 if any compile fails or prints an error or a warning)
    b=99999999
    for _ in 1 2 3; do
        s=$(date +%s%N)
        "$CC" < "$1" > "$1.bin" 2> "$1.err" || { echo -1; return; }
        e=$(( ($(date +%s%N) - s) / 1000000 ))
        grep -q '^error\|^warning' "$1.err" && { echo -1; return; }
        [ "$e" -lt "$b" ] && b=$e
    done
    echo "$b"
}

NFAIL=0
gen 4 > "$D/k4.cyr"
gen 15 > "$D/k15.cyr"
T1=$(best "$D/k4.cyr")
T2=$(best "$D/k15.cyr")
if [ "$T1" -lt 0 ] || [ "$T2" -lt 0 ]; then
    echo "  FAIL: S2 a compile failed or printed an error or a warning: $(grep -h -m1 '^error\|^warning' "$D/k4.cyr.err" "$D/k15.cyr.err" 2>/dev/null | head -1)"
    NFAIL=$((NFAIL + 1))
else
    chmod +x "$D/k15.cyr.bin"
    "$D/k15.cyr.bin"; rc=$?
    if [ "$rc" != 0 ]; then echo "  FAIL: S2 the 15360-pin program exited $rc, want 0"; NFAIL=$((NFAIL + 1))
    else echo "  ok: S2 the 15360-pin program compiles without an error or a warning and exits 0"; fi
    [ "$T1" -lt 1 ] && T1=1
    R10=$(( T2 * 10 / T1 ))
    if [ "$R10" -ge 60 ]; then
        echo "  FAIL: S1 4096 -> 15360 pins costs ${R10}/10x (${T1}ms -> ${T2}ms, limit 6.0x) — the pin intern is scanning every pin again"
        NFAIL=$((NFAIL + 1))
    else
        echo "  ok: S1 ${T1}ms -> ${T2}ms for 4096 -> 15360 pins — ratio ${R10}/10 (limit 6.0, linear ~3.8)"
    fi
fi
if [ "$NFAIL" -gt 0 ]; then echo "FAIL: $G: $NFAIL rows"; exit 1; fi
echo "PASS $G (pointer-to-pointer pins intern in linear time: 4096 -> 15360 pins under 6x)"
exit 0
