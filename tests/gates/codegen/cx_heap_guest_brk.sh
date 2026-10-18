#!/bin/sh
# cx_heap_guest_brk.sh — 6.7.14 (issues/archived/2026-10-15-cx-static-heap-128k-while-guest-is-8-mib.md). cx's
# alloc() bumps over the guest break cxvm SERVES: brk (12) is answered in guest space (programs/cxvm.cyr
# `_cx_guest_brk`) — the break starts at the image end, grows into the free guest memory below the stack
# while it stays 1 MiB below the live sp, and the guest stack traps at the break.
#
# THE DEFECT. lib/alloc_cx.cyr's heap was a static 128 KB buffer (`_cx_heap_buf`, sized at v6.6.6 for
# the 1 MB guest) written into every allocating .cyx: a program that allocated 16 bytes was a 151,466 B
# .cyx (56 B without alloc), and any program needing more than 128 KB stopped at
# `alloc: cx static heap exhausted (128 KB)` though the 8 MiB guest (6.7.12) had ~7 MiB free —
# tests/tcyr/crossos/audit_walk_fifo.tcyr's two 2 MB walker buffers among them.
#
# ROWS (a cx row also fails on any `cxvm:` fault line it does not expect):
#   H1  3 MiB in 48 pieces of 64 KB: each written and read back, none overlapping (native + cx: exit 0)
#   H2  allocate 64 KB pieces until refused (cx): exit 1 with `alloc: cx heap exhausted at <N> B (the
#       guest break cannot grow by <M> B more)`, N between 6 MiB and 7 MiB for this small program (the
#       message states what the heap reached; it hard-coded "128 KB")
#   H3  a deep recursion after a 6 MiB heap (cx): `cxvm: guest stack overflow, sp <S>` with S below
#       the break the program printed and within two frames of it — the stack never runs into the heap
#   H4  memory the guest stack used earlier reads zero from alloc: a 1000-deep recursion fills ~4 MiB
#       of stack with -1, then a 5 MiB allocation over that range is all zero (native + cx: exit 0)
#   H5  brk itself (cx): brk(0) answers a 16-aligned break; +4096 grows; brk(0) reads it back; 8 MiB
#       (past sp - 1 MiB) is refused with the old break; 1 (below the start) asks; the start shrinks
#       it back; below the start is refused
#   H6  an `alloc(16)` program is a .cyx under 128 KB (it was 151,466 B) and exits 0 on cx
#   H7  audit_walk_fifo.tcyr on cx runs to its summary line with no `alloc:` exhaustion (its mkdir /
#       mknodat rows answer -38 under D55: a separate, staged shape). An x86_64-Linux row: on an
#       aarch64 host cxvm's guest fork runs close and the file stops early (staged:
#       stdlib/2026-10-17-cxvm-forwards-guest-x86-numbers-through-host-renumbering.md)
#   H8  alloc_reset rewinds to the same base and hands back zeroed memory, alloc_used counts (native + cx)
#   H9  an H1 .cyx on a cxvm that does not serve brk (this tree's cxvm with the brk arm cut out — what a
#       pre-6.7.14 cxvm is, under D55) exits 1 naming it: `alloc: this cxvm does not serve brk (12)`
#   H10 a guest that raised its own sp past the segment cannot move the break past it (cx): the probe
#       asks brk for 9 MiB and 1 GiB and exits 40 when both are refused; run as built (the sp check
#       refuses) and with its first instruction (`jmp +1`, asserted `50 01 00 00` so the patch site
#       cannot go stale) overwritten by `movhi r254, 0x8000` (`fe fe 00 80`: sp 0x80800000) — sp is an
#       ordinary guest register, and a break bounded by sp alone was granted past _CX_MEM_SIZE, cxvm
#       then zeroing its own host heap past the segment (6.7.14 review)
#
# MUTATION LEDGER (6.7.14, measured; the real tree green 13/13):
#   MH1 lib/alloc_cx.cyr back to the static buffer (6.7.13) -> RED 8: H1 / H4 / H8 cx, H2 and H7 (each
#       "alloc: cx static heap exhausted (128 KB)"), H3 (no break printed: the 6 MiB alloc stops),
#       H6 (a 151,546 B .cyx), H9 (the static heap never asks for brk, so nothing names the old cxvm)
#   MH2 the zeroing in _cx_guest_brk removed -> RED 1: H4 cx (exit 2: the stack's -1 words come back)
#   MH3 the stack trap compares sp with _cx_image_len again -> RED 1: H3 (the recursion runs down
#       through the 6 MiB heap and traps at sp 21872, the image end)
#   MH4 _cx_guest_brk's sp check removed -> RED 2: H2 (the break passes the live sp: cxvm traps the next
#       frame, `guest stack overflow, sp 8388544`, instead of the named exhaustion), H5 (exit 24: 8 MiB
#       granted)
#   MH5 _cx_guest_brk's segment cap removed (bounded by the live sp alone) -> RED 1: H10 (exit 139: the
#       9 MiB break is granted and the 1 GiB one faults cxvm inside its zeroing loop, no `cxvm:` line)
#
# COMPILERS. CC=${CYCC:-build/cycc} builds the native legs and — unless CYCC_CX is set — the cx
# compiler from THIS tree's src/main_cx.cyr, and cxvm from programs/cxvm.cyr (CXVM overrides it).
# Exit 77 = could not run (no compiler at $CC, no timeout(1)); never a SKIP line with exit 0.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
_abs() { case $1 in /*|'') printf '%s' "$1" ;; *) printf '%s/%s' "$(pwd)" "$1" ;; esac; }
CC=$(_abs "${CYCC:-$ROOT/build/cycc}")
CYCC_CX=$(_abs "${CYCC_CX:-}")
CXVM=$(_abs "${CXVM:-}")
G=cx_heap_guest_brk
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

# build_run LEG SRC OUT [VM] — compile SRC for LEG (native / cx) and run it in $T; RC = its exit (or
# "nobuild"), its stdout + stderr in OUT. The cx leg runs VM (default: the tree's cxvm).
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
        (cd "$T" && timeout 120 "${4:-$VM}" < c.cyx > "$3" 2>&1) || RC=$?
    fi
}
# both NAME WHAT — native (the oracle) and cx each exit 0, no cxvm fault line.
both() {
    for leg in native cx; do
        build_run "$leg" "$T/$1.cyr" "$T/$1.$leg.out"
        if [ "$RC" = nobuild ]; then bad "$2 ($leg): does not build: $(grep -m1 '^error' "$T/$1.$leg.out")"; continue; fi
        if [ "$RC" != 0 ] || grep -q '^cxvm:\|^alloc:' "$T/$1.$leg.out"; then
            bad "$2 ($leg): exit $RC, want 0 $(grep -m1 '^cxvm:\|^alloc:' "$T/$1.$leg.out")"; continue
        fi
        ok "$2 ($leg): exit 0"
    done
}

# H1 3 MiB in 64 KB pieces, written and read back.
cat > "$T/h1.cyr" <<'EOF'
include "lib/alloc.cyr"
var ptrs[48];
fn h1(): i64 {
    var bad = 0;
    var i = 0;
    while (i < 48) {
        var p = alloc(65536);
        if (p == 0) { return 1; }
        store64(&ptrs + i * 8, p);
        var k = 0;
        while (k < 65536) { store64(p + k, i * 1000003 + k); k = k + 512; }
        i = i + 1;
    }
    i = 0;
    while (i < 48) {
        var q = load64(&ptrs + i * 8);
        var k2 = 0;
        while (k2 < 65536) { if (load64(q + k2) != i * 1000003 + k2) { bad = bad | 2; } k2 = k2 + 512; }
        if (i > 0) { if (q < load64(&ptrs + (i - 1) * 8) + 65536) { bad = bad | 4; } }
        i = i + 1;
    }
    return bad;
}
syscall(60, h1());
EOF
both h1 "H1 3 MiB in 48 x 64 KB, written, read back, none overlapping"

# H2 allocate until refused: the named exhaustion, stating the size the heap reached.
cat > "$T/h2.cyr" <<'EOF'
include "lib/alloc.cyr"
var n = 0;
while (n < 100000) {
    var p = alloc(65536);
    store64(p, n);
    store64(p + 65528, n);
    n = n + 1;
}
syscall(60, 7);
EOF
build_run cx "$T/h2.cyr" "$T/h2.out"
hb=$(sed -n 's/^alloc: cx heap exhausted at \([0-9]*\) B (the guest break cannot grow by \([0-9]*\) B more)$/\1/p' "$T/h2.out")
if [ "$RC" = 1 ] && [ -n "$hb" ] && [ "$hb" -ge 6291456 ] && [ "$hb" -lt 7340032 ] && ! grep -q '^cxvm:' "$T/h2.out"; then
    ok "H2 (cx): allocation until refused stops at the named exhaustion, the heap at $hb B"
else bad "H2 (cx): exit $RC, want 1 and 'alloc: cx heap exhausted at <6..7 MiB> B …': $(head -2 "$T/h2.out" | tr '\n' ' ')"; fi

# H3 a deep recursion after a 6 MiB heap traps at the break.
cat > "$T/h3.cyr" <<'EOF'
include "lib/alloc.cyr"
fn put_dec(v): i64 {
    var b[24];
    var i = 23;
    if (v == 0) { store8(&b + i, 48); i = i - 1; }
    while (v > 0) { store8(&b + i, 48 + v % 10); i = i - 1; v = v / 10; }
    syscall(1, 1, &b + i + 1, 23 - i);
    return 0;
}
fn deep(n): i64 {
    var pad[4096];
    store64(&pad, n);
    return deep(n + 1) + load64(&pad);
}
var p = alloc(6291456);
store64(p + 6291448, 9);
syscall(1, 1, "brk=", 4);
put_dec(syscall(12, 0));
syscall(1, 1, "\n", 1);
deep(0);
syscall(60, 5);
EOF
build_run cx "$T/h3.cyr" "$T/h3.out"
b3=$(sed -n 's/^brk=\([0-9]*\)$/\1/p' "$T/h3.out")
s3=$(sed -n 's/^cxvm: guest stack overflow, sp \([0-9]*\) at pc [0-9]*$/\1/p' "$T/h3.out")
if [ "$RC" = 1 ] && [ -n "$b3" ] && [ -n "$s3" ] && [ "$s3" -lt "$b3" ] && [ $((b3 - s3)) -le 9000 ]; then
    ok "H3 (cx): the recursion traps at sp $s3, $((b3 - s3)) B under the break $b3 — never into the heap"
else bad "H3 (cx): exit $RC, break '$b3', trap sp '$s3' (want a 'guest stack overflow' within two 4 KB frames under the break): $(grep -m1 '^cxvm:' "$T/h3.out")"; fi

# H4 memory the stack used earlier comes back zeroed.
cat > "$T/h4.cyr" <<'EOF'
include "lib/alloc.cyr"
fn dirty(n): i64 {
    var pad[4096];
    var k = 0;
    while (k < 4096) { store64(&pad + k, 0 - 1); k = k + 8; }
    if (n == 0) { return 0; }
    return dirty(n - 1) + load64(&pad + 8) + 1;
}
fn h4(): i64 {
    dirty(1000);
    var p = alloc(5242880);
    if (p == 0) { return 1; }
    var k = 0;
    while (k < 5242880) {
        if (load64(p + k) != 0) { return 2; }
        k = k + 8;
    }
    return 0;
}
syscall(60, h4());
EOF
both h4 "H4 after a ~4 MiB-deep recursion wrote -1, a 5 MiB allocation over it reads all zero"

# H5 brk itself.
cat > "$T/h5.cyr" <<'EOF'
var bad = 0;
var b0 = syscall(12, 0);
if (b0 <= 0 || (b0 & 15) != 0) { bad = bad | 1; }
if (syscall(12, b0 + 4096) != b0 + 4096) { bad = bad | 2; }
if (syscall(12, 0) != b0 + 4096) { bad = bad | 4; }
if (syscall(12, 8388608) != b0 + 4096) { bad = bad | 8; }
if (syscall(12, 1) != b0 + 4096) { bad = bad | 16; }
if (syscall(12, b0) != b0) { bad = bad | 32; }
if (syscall(12, b0 - 16) != b0) { bad = bad | 64; }
syscall(60, bad);
EOF
build_run cx "$T/h5.cyr" "$T/h5.out"
if [ "$RC" = 0 ] && ! grep -q '^cxvm:' "$T/h5.out"; then ok "H5 (cx): brk asks, grows, refuses past sp - 1 MiB and below the start, shrinks to the start"
else bad "H5 (cx): exit $RC (1 brk(0), 2 grow, 4 read back, 8 past the stack reserve granted, 16 brk(1), 32 shrink, 64 below the start)"; fi

# H6 an allocating .cyx no longer carries a 128 KB buffer.
printf 'include "lib/alloc.cyr"\nvar p = alloc(16);\nstore64(p + 8, 3);\nsyscall(60, load64(p + 8));\n' > "$T/h6.cyr"
build_run cx "$T/h6.cyr" "$T/h6.out"
sz=$(wc -c < "$T/c.cyx" | tr -d ' ')
if [ "$RC" = 3 ] && [ "$sz" -lt 131072 ]; then ok "H6 (cx): an alloc(16) program is a $sz B .cyx (it was 151,466 B) and runs"
else bad "H6 (cx): exit $RC (want 3), .cyx $sz B (want under 131072: the static heap is gone)"; fi

# H7 audit_walk_fifo.tcyr on cx gets past alloc.
mkdir "$T/h7"
if "$CX" < tests/tcyr/crossos/audit_walk_fifo.tcyr > "$T/h7.cyx" 2> "$T/h7.err" && [ -s "$T/h7.cyx" ]; then
    rc7=0; (cd "$T/h7" && timeout 120 "$VM" < ../h7.cyx > ../h7.out 2>&1) || rc7=$?
    if ! grep -q '^alloc:' "$T/h7.out" && ! grep -q '^cxvm:' "$T/h7.out" && tail -1 "$T/h7.out" | grep -q '^[0-9]* passed, [0-9]* failed'; then
        ok "H7 (cx): audit_walk_fifo.tcyr runs to '$(tail -1 "$T/h7.out")' with no heap exhaustion (exit $rc7)"
    else bad "H7 (cx): audit_walk_fifo.tcyr: $(grep -m1 '^alloc:\|^cxvm:' "$T/h7.out") last line '$(tail -1 "$T/h7.out")'"; fi
else bad "H7 (cx): audit_walk_fifo.tcyr does not compile for cx: $(grep -m1 '^error' "$T/h7.err")"; fi

# H8 alloc_reset rewinds and scrubs.
cat > "$T/h8.cyr" <<'EOF'
include "lib/alloc.cyr"
fn h8(): i64 {
    var bad = 0;
    var p = alloc(1048576);
    var k = 0;
    while (k < 1048576) { store64(p + k, 0 - 1); k = k + 8; }
    if (alloc_used() != 1048576) { bad = bad | 8; }
    alloc_reset();
    if (alloc_used() != 0) { bad = bad | 4; }
    var q = alloc(1048576);
    if (q != p) { bad = bad | 1; }
    k = 0;
    while (k < 1048576) { if (load64(q + k) != 0) { bad = bad | 2; } k = k + 8; }
    return bad;
}
syscall(60, h8());
EOF
both h8 "H8 alloc_reset rewinds to the same base, scrubbed; alloc_used counts"

# H9 a cxvm that does not serve brk is named.
BRK_LINE='            elif (sn == 12) { result = _cx_guest_brk(s2); }   # brk, in guest space (6.7.14)'
if [ "$(grep -cxF "$BRK_LINE" programs/cxvm.cyr)" != 1 ]; then
    bad "H9: programs/cxvm.cyr's brk dispatch line moved — update BRK_LINE so this row still cuts it out"
else
    grep -vxF "$BRK_LINE" programs/cxvm.cyr > "$T/cxvm_nobrk.cyr"
    if "$CC" < "$T/cxvm_nobrk.cyr" > "$T/cxvm_nobrk" 2> /dev/null && [ -s "$T/cxvm_nobrk" ]; then
        chmod +x "$T/cxvm_nobrk"
        build_run cx "$T/h1.cyr" "$T/h9.out" "$T/cxvm_nobrk"
        if [ "$RC" = 1 ] && grep -q '^alloc: this cxvm does not serve brk (12): a .cyx from cycc_cx 6.7.14 or later needs cxvm 6.7.14 or later$' "$T/h9.out"; then
            ok "H9 (cx): on a cxvm that answers brk -38 alloc names it and exits 1"
        else bad "H9 (cx): exit $RC, want 1 and 'alloc: this cxvm does not serve brk (12)': $(head -1 "$T/h9.out")"; fi
    else bad "H9: the brk-less cxvm copy does not build"; fi
fi

# H10 a raised sp does not move the break past the segment.
cat > "$T/h10.cyr" <<'EOF'
var b0 = syscall(12, 0);
var r1 = syscall(12, 9437184);
var r2 = syscall(12, 1073741824);
var bad = 40;
if (r1 != b0) { bad = bad | 1; }
if (r2 != b0) { bad = bad | 2; }
syscall(60, bad);
EOF
if "$CX" < "$T/h10.cyr" > "$T/h10.cyx" 2> "$T/h10.err" && [ -s "$T/h10.cyx" ]; then
    i10=$(od -An -tx1 -j8 -N4 "$T/h10.cyx" | tr -d ' \n')
    rc10=0; (cd "$T" && timeout 120 "$VM" < h10.cyx > h10.out 2>&1) || rc10=$?
    if [ "$i10" != 50010000 ]; then
        bad "H10 (cx): the probe's first instruction is '$i10', want 50010000 (jmp +1) — the patch site moved; update the row"
    elif [ "$rc10" != 40 ] || grep -q '^cxvm:' "$T/h10.out"; then
        bad "H10 (cx): the unpatched probe exits $rc10, want 40 (41: 9 MiB granted, 42: 1 GiB granted) $(grep -m1 '^cxvm:' "$T/h10.out")"
    else
        printf '\376\376\000\200' | dd of="$T/h10.cyx" bs=1 seek=8 conv=notrunc 2> /dev/null
        p10=$(od -An -tx1 -j8 -N4 "$T/h10.cyx" | tr -d ' \n')
        rc10=0; (cd "$T" && timeout 120 "$VM" < h10.cyx > h10.out 2>&1) || rc10=$?
        if [ "$p10" = fefe0080 ] && [ "$rc10" = 40 ] && ! grep -q '^cxvm:' "$T/h10.out"; then
            ok "H10 (cx): with sp raised to 0x80800000 brk still refuses 9 MiB and 1 GiB — the break stays inside the segment"
        else bad "H10 (cx): patched '$p10' (want fefe0080), exit $rc10, want 40 (41: 9 MiB granted past the segment, 139: cxvm faulted zeroing past it) $(grep -m1 '^cxvm:' "$T/h10.out")"; fi
    fi
else bad "H10 (cx): the probe does not compile for cx: $(grep -m1 '^error' "$T/h10.err")"; fi

WANT=13
if [ "$fail" -ne 0 ]; then echo "FAIL: $G — $fail row(s) red, $pass green"; exit 1; fi
if [ "$pass" -ne "$WANT" ]; then echo "FAIL: $G — $pass rows ran, want $WANT (a row stopped running)"; exit 1; fi
echo "PASS: $G — $pass/$WANT rows: cx alloc() bumps over the guest break cxvm serves (3 MiB written and read back, the named exhaustion stating the size it reached, the stack trapping at the break, memory the stack used read back zero, brk's own contract, no 128 KB buffer in the .cyx, audit_walk_fifo past alloc, alloc_reset, a brk-less cxvm named, the break bounded by the segment under a raised sp)"
exit 0
