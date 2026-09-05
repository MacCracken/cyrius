#!/bin/sh
# inline_simd256_return_lanes.sh — v6.5.59. An INLINED 256-bit return must carry all four lanes.
#
# THE DEFECT, silent. The inline-replay path re-parses the callee's body inside the CALLER's
# function context, so `_cur_fn_ret_scalar` / `_cur_fn_ret_pair` still described the CALLER and
# `return r;` in the replayed body emitted the caller's return convention. A 128-bit vector
# survived that by luck — one XMM, which the default path moves anyway — but a **256-bit return
# is a PAIR and its second register was never moved**. An inlined `f64v4` wrapper returned lanes
# 0-1 correct and lanes 2-3 STALE. Exit 0, no diagnostic, wrong numbers.
#
# ⭐ CHECK EVERY LANE. This is the whole lesson. A lane-0 assertion — the obvious thing to write —
# passes while half the vector is wrong, and every existing SIMD test that touches a 256-bit
# value through an inlined wrapper would have kept passing. The defect surfaced only because a
# probe asserted all four. Any future gate over a 256-bit value must do the same.
#
# ⚠ Reachable from ORDINARY user code: a flat `var r: f64v4; f64v_add(&r,&a,&b,4); return r;`
# wrapper is admitted to the inline path (v6.5.58 made the predicate see 4-slot params), so this
# needs no stdlib change and no compiler flag to hit.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL inline_simd256_return_lanes: no build/cycc"; exit 1; }
"$CC" < "$R/src/main.cyr" > "$T/cc" 2>/dev/null || { echo "FAIL inline_simd256_return_lanes: stage1 build failed"; exit 1; }
chmod +x "$T/cc"

cat > "$T/p.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn flat256(a: f64v4, b: f64v4): f64v4 { var r: f64v4; f64v_add(&r, &a, &b, 4); return r; }
fn flat128(a: f64v2, b: f64v2): f64v2 { var r: f64v2; f64v_add(&r, &a, &b, 2); return r; }
fn main(): i64 {
    var bad = 0;
    var a: f64v4 = f64v4_splat(0x3FF0000000000000);
    var b: f64v4 = f64v4_splat(0x4000000000000000);
    var c: f64v4 = flat256(a, b);
    if (f64v4_lane0_ptr(&c) != 0x4008000000000000) { bad = bad + 1; }
    if (f64v4_lane1_ptr(&c) != 0x4008000000000000) { bad = bad + 1; }
    if (f64v4_lane2_ptr(&c) != 0x4008000000000000) { bad = bad + 1; }
    if (f64v4_lane3_ptr(&c) != 0x4008000000000000) { bad = bad + 1; }
    # 128-bit control: it always worked, and must keep working.
    var d: f64v2 = f64v2_make(0x3FF0000000000000, 0x4000000000000000);
    var e: f64v2 = flat128(d, d);
    if (f64v2_lo(e) != 0x4000000000000000) { bad = bad + 1; }
    if (f64v2_hi(e) != 0x4010000000000000) { bad = bad + 1; }
    syscall(60, bad, 0, 0, 0, 0);
    return 0;
}
EOF
"$CC" < "$T/p.cyr" > "$T/p" 2>"$T/e" || { echo "FAIL inline_simd256_return_lanes: fixture did not compile"; sed -n 1,3p "$T/e"; exit 1; }
chmod +x "$T/p"; "$T/p"; B=$?
if [ "$B" -ne 0 ]; then
  echo "FAIL inline_simd256_return_lanes: $B of 6 lane checks wrong."
  echo "  Lanes 2-3 of an inlined 256-bit return are the ones the replay used to drop:"
  echo "  it emitted the CALLER's return convention, which moves one XMM, not a pair."
  exit 1
fi
echo "PASS inline_simd256_return_lanes: all 4 lanes of an inlined 256-bit return survive (128-bit control also green)"
exit 0
