#!/bin/sh
# lase_simd_pairs.sh — v6.5.53. LASE eliminates redundant 128-bit SIMD store→load pairs.
#
# WHY. v6.5.52 made the value-form SIMD wrappers inline, so a chain became packed ops separated
# by store-then-immediately-reload of the same frame slot. LASE could not see those: it matched
# only the REX.W integer forms `48 89 85` / `48 8B 85`. A 3-link f32v4 chain carried 18 `movupd`
# with 3 of them a dead reload; it now carries 15, and a 2M-iteration chain runs 15 ms -> 14 ms.
#
# ⭐ THE SAFETY PROPERTY IS THE MODRM PIN, and axis 3 exists to keep it. ModRM is
# mod(2) reg(3) rm(3), so 0x85 = mod 10 (disp32), reg 000 (**xmm0**), rm 101 (rbp); xmm1 is
# 0x8D, xmm2 0x95, xmm3 0x9D. Requiring 0x85 on BOTH the store and the load guarantees the
# load's destination is the register the store just wrote — the property the integer LASE gets
# for free because both forms encode rax.
#
# ⛔ TWO SEPARATE INVARIANTS — conflating them is how the next edit miscompiles.
#   ADJACENCY (+8) keeps the 32-byte pair out: a 256-bit value stores `66 0F 11 85 <d_lo>` then
#   `66 0F 11 8D <d_lo+16>`, so store+8 is another STORE (fails the 0x10 test) and independently
#   d_lo != d_lo+16 (fails the disp32 test). The modrm has nothing to do with it.
#   THE REGISTER TEST is load-bearing and guards something else entirely: the LOAD side's
#   register is VARIABLE — ELOAD_F64V2_TO_XMM / ELOAD_F64V4_TO_XMM emit `0x85 + (simd_ord << 3)`
#   for ordinals 0..7 (backend/x86/emit.cyr:3525,3542) — so a value stored from xmm0 is routinely
#   RELOADED INTO xmm2/xmm3 as a later call's second SIMD argument. Delete that load and
#   xmm2/xmm3 hold whatever the previous SIMD call left: a silent wrong vector.
#
# ⚠ MEASURED four ways, because only the interaction is dangerous:
#     pin + strict +8 (shipped) -> 0 deletions / 0 miscompiles
#     pin + relaxed distance    -> 3 deletions / 0 miscompiles
#     no pin + strict +8        -> 0 / 0
#     no pin + relaxed distance -> 6 deletions / **2 MISCOMPILES**
# The register test therefore only LOOKS redundant today, because adjacency happens to exclude
# the cases needing it. Relaxing the distance is the obvious next step (f64v4 pairs sit at
# store+16/+24 and this pass gets nothing for them today) — at which point it is the only thing
# preventing a wrong answer.
#
# ⚠ AXIS 3 IS NOT VACUOUS — an earlier version of this header wrongly said it was. It DOES catch
# the both-relaxed mutation: its fixture yields mutation-visible sites whose NOP-filling flips the
# program's exit code. It is a 3-link f64v4 chain feeding each result back in as the SECOND
# argument, precisely so the ordinal-dependent modrm (xmm2/xmm3) appears and the axis cannot pass
# by accident.
#
# ⚠ The elimination NOP-FILLS in place rather than removing bytes, so nothing moves — no jump
# displacement, no fixup CP, no inline switch-table entry. That is deliberate: the v6.5.20
# miscompile was caused by a pass relocating code without knowing about an inline data table.
#
# ⚠ NO `set -e`: exit codes are DATA.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
CC="$ROOT/build/cycc"
FAIL=0

scan() {   # $1 = binary, prints the count of surviving adjacent store->load same-slot xmm0 pairs
    python3 - "$1" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
ST = bytes([0x66,0x0F,0x11,0x85]); LD = bytes([0x66,0x0F,0x10,0x85])
n = 0
for i in range(len(d) - 16):
    if d[i:i+4] == ST and d[i+8:i+12] == LD and d[i+4:i+8] == d[i+12:i+16]:
        n += 1
print(n)
PY
}

# ── axis 1: no adjacent 128-bit store→load pair survives ──────────────────────────
cat > "$D/chain.cyr" <<'EOF'
include "lib/simd.cyr"
fn chain(a: f32v4, b: f32v4): i64 {
    var t1: f32v4 = f32v4_add(a, b);
    var t2: f32v4 = f32v4_mul(t1, b);
    var t3: f32v4 = f32v4_sub(t2, a);
    return f32v4_lane0(t3);
}
fn main(): i64 { return 0; }
var r = main();
EOF
"$CC" < "$D/chain.cyr" > "$D/chain.bin" 2>/dev/null
LEFT=$(scan "$D/chain.bin")
if [ "$LEFT" != 0 ]; then
    echo "FAIL: axis 1: $LEFT redundant 128-bit SIMD store->load pairs survive — LASE is not"
    echo "        seeing the 66 0F 11 85 / 66 0F 10 85 forms"
    FAIL=1
else echo "  ok: no adjacent 128-bit SIMD store->load pair survives"; fi

# ── axis 2: the chain still computes the RIGHT answer ─────────────────────────────
cat > "$D/val.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: f32v4 = f32v4_make(0x40000000,0x40000000,0x40000000,0x40000000);  # 2.0
    var b: f32v4 = f32v4_splat(0x3F800000);                                   # 1.0
    var t1: f32v4 = f32v4_add(a, b);      # 3.0
    var t2: f32v4 = f32v4_mul(t1, b);     # 3.0
    var t3: f32v4 = f32v4_sub(t2, a);     # 1.0
    if (f32v4_lane0(t1) != 0x40400000) { return 1; }
    if (f32v4_lane0(t2) != 0x40400000) { return 2; }
    if (f32v4_lane0(t3) != 0x3F800000) { return 3; }
    return 0;
}
var r = main();
syscall(60, r);
EOF
"$CC" < "$D/val.cyr" > "$D/val.bin" 2>/dev/null; chmod +x "$D/val.bin" 2>/dev/null
"$D/val.bin"; rc=$?
if [ "$rc" != 0 ]; then
    echo "FAIL: axis 2: eliminating the reload changed the RESULT (link $rc of the chain is wrong)"
    FAIL=1
else echo "  ok: the chain still computes the correct values"; fi

# ── axis 3: ⛔ the 32-byte (f64v4) PAIR path is left alone ─────────────────────────
# Its store is followed by another STORE (modrm 0x8D), so nothing may be eliminated. If a
# future edit relaxes the modrm pin, this axis is what catches it before a wrong answer ships.
cat > "$D/wide.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: f64v4 = f64v4_make(0x4000000000000000, 0x4000000000000000, 0x4000000000000000, 0x4000000000000000);
    var b: f64v4 = f64v4_splat(0x3FF0000000000000);
    var c: f64v4 = f64v4_add(a, b);
    var d: f64v4 = f64v4_mul(a, c);
    var e: f64v4 = f64v4_add(b, d);
    var p = &e;
    if (f64v4_lane0_ptr(p) != 0x401C000000000000) { return 1; }
    if (f64v4_lane3_ptr(p) != 0x401C000000000000) { return 2; }
    return 0;
}
var r = main();
syscall(60, r);
EOF
"$CC" < "$D/wide.cyr" > "$D/wide.bin" 2>"$D/wide.err"; wrc=$?
if [ "$wrc" != 0 ]; then
    echo "FAIL: axis 3 PREMISE: the 256-bit fixture does not compile, so the pair path is NOT"
    echo "        covered. Fix the fixture — do not weaken this axis; it is the one that catches"
    echo "        a relaxed modrm pin turning a high-half store into a low-half load."
    grep -m1 "^error" "$D/wide.err" | sed 's/^/        /'
    FAIL=1
else
    chmod +x "$D/wide.bin"; "$D/wide.bin"; vrc=$?
    if [ "$vrc" != 0 ]; then
        echo "FAIL: axis 3: a 256-bit f64v4 chain produced a WRONG value (lane $vrc) — the modrm"
        echo "        pin has been relaxed and a high-half store paired with a low-half load"
        FAIL=1
    else echo "  ok: 256-bit f64v4 arithmetic still correct (the pair path is untouched)"; fi
fi

if [ "$FAIL" != 0 ]; then echo "FAIL: lase_simd_pairs"; exit 1; fi
echo "PASS lase_simd_pairs (redundant 128-bit SIMD reloads eliminated; values unchanged)"
