#!/bin/sh
# simd_valueform_no_avx_transition.sh — v6.5.60. The f64v4 VALUE forms must not pay an
# AVX<->SSE transition on every call.
#
# THE FINDING, measured. The 256-bit ymm kernel really is faster in isolation (n=4: 4 ms vs 6 ms
# for the 128-bit kernel; n=256: 2 ms vs 4 ms). But a VALUE-form `f64v4` is moved in and out of
# frame slots by LEGACY-SSE pair moves, so a loop calling `f64v4_add(a, b)` alternates VEX kernel
# and SSE moves and crosses the ISA boundary twice per iteration. The `vzeroupper` that mitigates
# it is emitted per invocation and costs more than the halved iteration count saves:
#   1-op loop  23 ms -> 9 ms   ·   3-link chain  68 ms -> 30 ms   by dropping AVX2 from the VALUE forms.
#
# ⛔ AND THE `vzeroupper` IS NOT THE THING TO DELETE — that was measured too. Removing it from
# `EMIT_F64V4_LOOP` made the same benchmark **5.6x WORSE** (25 ms -> 139 ms): unmitigated
# AVX-SSE transition penalties are far more expensive than the instruction. It is already the
# cheaper option.
#
# ⭐ The `_ptr` BATCH forms deliberately KEEP their AVX2 gate — there the loop body is all-VEX
# and the ymm kernel wins about 2x. Axis 2 is that control: if a future change strips AVX2 from
# those too, this gate goes red rather than silently giving up the win.
#
# ⚠ RATIO, not absolute time, measured back-to-back on the same box so load moves both halves
# together. Bound 1.7x against a measured ~1.1x and a pre-fix ~2.9x.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL simd_valueform_no_avx_transition: no build/cycc"; exit 1; }

# The stdlib value form, and a hand-written 128-bit-kernel equivalent as the reference.
cat > "$T/std.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: f64v4 = f64v4_splat(0x3FF0000000000000);
    var b: f64v4 = f64v4_splat(0x4000000000000000);
    var i = 0;
    while (i < 2000000) { var t: f64v4 = f64v4_add(a, b); i = i + 1; }
    syscall(60, 0, 0, 0, 0, 0);
    return 0;
}
EOF
cat > "$T/ref.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn ref_add(a: f64v4, b: f64v4): f64v4 { var r: f64v4; f64v_add(&r, &a, &b, 4); return r; }
fn main(): i64 {
    var a: f64v4 = f64v4_splat(0x3FF0000000000000);
    var b: f64v4 = f64v4_splat(0x4000000000000000);
    var i = 0;
    while (i < 2000000) { var t: f64v4 = ref_add(a, b); i = i + 1; }
    syscall(60, 0, 0, 0, 0, 0);
    return 0;
}
EOF
for n in std ref; do
  "$CC" < "$T/$n.cyr" > "$T/$n" 2>/dev/null || { echo "FAIL simd_valueform_no_avx_transition: $n fixture did not compile"; exit 1; }
  chmod +x "$T/$n"
done
best() {  # best of 5, in ms
  b=999999; r=0
  while [ $r -lt 5 ]; do
    s=$(date +%s%N); "$1"; e=$(date +%s%N); m=$(( (e - s) / 1000000 ))
    [ $m -lt $b ] && b=$m
    r=$((r + 1))
  done
  echo $b
}
S=$(best "$T/std"); F=$(best "$T/ref")
[ "$F" -ge 2 ] || { echo "FAIL simd_valueform_no_avx_transition: reference ran in ${F}ms — too fast to compare, fixture broken"; exit 1; }
R100=$(( S * 100 / F ))
if [ "$R100" -ge 170 ]; then
  echo "FAIL simd_valueform_no_avx_transition: stdlib value form ${S}ms vs 128-bit reference ${F}ms (${R100}%, bound 170%)."
  echo "  The f64v4 VALUE forms are paying an AVX<->SSE transition per call again."
  exit 1
fi

# axis 2 — CONTROL: the batch _ptr forms must still use AVX2, where it wins ~2x.
grep -q "simd_has_avx2() == 1) { f64v256_add(&r, a_ptr" "$R/lib/simd.cyr" || {
  echo "FAIL simd_valueform_no_avx_transition axis2: the _ptr batch forms lost their AVX2 gate — that path wins ~2x and must keep it"
  exit 1; }

# axis 3 — correctness of the value form, all four lanes.
cat > "$T/c.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: f64v4 = f64v4_splat(0x3FF0000000000000);
    var b: f64v4 = f64v4_splat(0x4000000000000000);
    var c: f64v4 = f64v4_add(a, b);
    var bad = 0;
    if (f64v4_lane0_ptr(&c) != 0x4008000000000000) { bad = bad + 1; }
    if (f64v4_lane1_ptr(&c) != 0x4008000000000000) { bad = bad + 1; }
    if (f64v4_lane2_ptr(&c) != 0x4008000000000000) { bad = bad + 1; }
    if (f64v4_lane3_ptr(&c) != 0x4008000000000000) { bad = bad + 1; }
    syscall(60, bad, 0, 0, 0, 0);
    return 0;
}
EOF
"$CC" < "$T/c.cyr" > "$T/c" 2>/dev/null && chmod +x "$T/c" && "$T/c"
[ $? -eq 0 ] || { echo "FAIL simd_valueform_no_avx_transition axis3: f64v4_add value form is numerically wrong"; exit 1; }

echo "PASS simd_valueform_no_avx_transition: value form ${S}ms vs ${F}ms reference (${R100}%, bound 170%); _ptr batch keeps AVX2; all 4 lanes correct"
exit 0
