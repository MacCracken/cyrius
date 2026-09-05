#!/bin/sh
# simd_param_inline_reach.sh — v6.5.58. The SIMD-param inline gate must SEE a wide parameter
# whatever its width, not only the two-128-bit-param case.
#
# THE DEFECT. `_fn_has_simd_param(S, pc)` (`src/common/util.cyr`) scanned local slots
# `[0, pc)`. A parameter wider than 8 bytes occupies `slots` consecutive locals — (slots-1)
# ANONYMOUS FILLERS carrying the name sentinel -1, and THEN its named slot, which is the one
# holding the SLTYPE. So parameter k's type sits at an index that grows with every wide param
# before it, and the fixed `[0, pc)` window contained it only when `slots-1 < pc` — i.e. only
# for TWO 128-bit params. A SINGLE 128-bit param (named slot 1, window {0}) and EVERY 256-bit
# param (4 slots) were invisible, so those wrappers were never admitted to the inline-replay
# path and still emitted a `call` per chain link.
#
# ⭐ SAME OFF-BY-SLOT BUG v6.5.52 FIXED IN `SFINL`, left unfixed in the predicate that decides
# whether to look at all. Fixing a slot-index consumer without fixing the guard in front of it
# leaves the feature dark for exactly the inputs the guard mis-scans.
#
# ⚠ AXIS 2 IS THE CONTROL and it is what stops this gate being satisfied by "inline everything".
# A wrapper with i64 params must keep its call: general inlining is default-OFF for a measured
# reason (+25.6 % on cycc at v1.11.3), and `_fn_has_simd_param` exists precisely to admit the
# SIMD wrappers WITHOUT enabling it.
#
# ⚠ Axis 1's bound is a FIXTURE CONSTANT, not a universal one. It was 35 before the fix and 30
# after, on this exact fixture with these includes; the bound sits between them. If the fixture
# or lib/simd.cyr changes, re-measure it — do not nudge it to make the gate pass.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL simd_param_inline_reach: no build/cycc"; exit 1; }
"$CC" < "$R/src/main.cyr" > "$T/cc" 2>/dev/null || { echo "FAIL simd_param_inline_reach: stage1 build failed"; exit 1; }
chmod +x "$T/cc"
command -v llvm-objdump >/dev/null 2>&1 || { echo "FAIL simd_param_inline_reach: llvm-objdump missing"; exit 1; }

# axis 1 — a ONE-param 128-bit wrapper and a ONE-param 256-bit wrapper must both inline.
cat > "$T/a1.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn one128(v: f32v4): f32v4 { var r: f32v4; f32v_add(&r, &v, &v, 4); return r; }
fn one256(v: f64v4): f64v4 { var r: f64v4; f64v_add(&r, &v, &v, 4); return r; }
fn main(): i64 {
    var x: f32v4 = f32v4_splat(0x3F800000);
    var y: f64v4 = f64v4_splat(0x3FF0000000000000);
    var a: f32v4 = one128(x);
    var b: f32v4 = one128(a);
    var c: f64v4 = one256(y);
    var d: f64v4 = one256(c);
    # ⚠ Compare IN-PROGRAM and exit with a sentinel. Returning the raw lane bits does not work:
    # 0x40800000 & 0xFF is 0, so a correct answer would be indistinguishable from a zeroed one.
    var ok = 0;
    if (f32v4_lane0(b) == 0x40800000) { ok = ok + 1; }
    if (f32v4_lane3(b) == 0x40800000) { ok = ok + 2; }
    syscall(60, ok, 0, 0, 0, 0);
    return 0;
}
EOF
"$CC" < "$T/a1.cyr" > "$T/a1" 2>/dev/null || { echo "FAIL simd_param_inline_reach: axis1 fixture did not compile"; exit 1; }
N=$(llvm-objdump -d "$T/a1" 2>/dev/null | grep -c callq)
if [ "$N" -gt 31 ]; then
  echo "FAIL simd_param_inline_reach axis1: $N callq (bound 31; 30 with the fix, 35 without)."
  echo "  A 1-param 128-bit or 256-bit SIMD wrapper is not reaching the inline-replay path."
  exit 1
fi

# axis 1b — and the inlined result must be CORRECT, not merely smaller.
chmod +x "$T/a1"; "$T/a1"; G=$?
[ "$G" -eq 3 ] || { echo "FAIL simd_param_inline_reach axis1b: inlined wrapper gave $G, expected 3 (1.0 doubled twice = 4.0 in lanes 0 and 3)"; exit 1; }

# axis 2 — CONTROL: an i64-param wrapper must NOT be inlined. General inlining stays off.
cat > "$T/a2.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn plain(v): i64 { return v + v; }
fn main(): i64 {
    var a = plain(3);
    var b = plain(a);
    syscall(60, b, 0, 0, 0, 0);
    return 0;
}
EOF
"$CC" < "$T/a2.cyr" > "$T/a2" 2>/dev/null || { echo "FAIL simd_param_inline_reach: axis2 fixture did not compile"; exit 1; }
C=$(llvm-objdump -d "$T/a2" 2>/dev/null | grep -c callq)
[ "$C" -ge 2 ] || { echo "FAIL simd_param_inline_reach axis2 (control): only $C callq — an i64-param fn was inlined, so general inlining leaked on"; exit 1; }
chmod +x "$T/a2"; "$T/a2"; [ $? -eq 12 ] || { echo "FAIL simd_param_inline_reach axis2: control returned wrong value"; exit 1; }

echo "PASS simd_param_inline_reach: 1-param 128-bit and 256-bit wrappers inline ($N callq, bound 31), result correct, i64 control still calls"
exit 0
