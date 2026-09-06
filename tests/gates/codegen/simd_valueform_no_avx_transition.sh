#!/bin/sh
# simd_valueform_no_avx_transition.sh — v6.5.60, REWRITTEN v6.5.62.
#
# The fixed-lane SIMD wrappers must not pay a per-call AVX2 dispatch, and the ymm kernel must
# keep its advantage where that advantage is real.
#
# ── v6.5.60's finding (still true) ─────────────────────────────────────────────────────────
# The 256-bit ymm kernel is faster in isolation, but a VALUE-form `f64v4` is moved in and out of
# frame slots by LEGACY-SSE pair moves, so a loop calling `f64v4_add(a, b)` crosses the ISA
# boundary twice per iteration. Dropping AVX2 from the VALUE forms: 1-op loop 23 ms -> 9 ms,
# 3-link chain 68 ms -> 30 ms.
# ⛔ `vzeroupper` is NOT the thing to delete — removing it measured 5.6x WORSE (25 ms -> 139 ms).
#
# ── v6.5.62's finding, and why axis 2 had to be REPLACED ───────────────────────────────────
# ⛔ THIS GATE'S AXIS 2 USED TO ASSERT THE OPPOSITE OF THE TRUTH, BY GREP:
#       grep -q "simd_has_avx2() == 1) { f64v256_add(&r, a_ptr" lib/simd.cyr
# i.e. it REQUIRED the `_ptr` wrappers to keep a per-call AVX2 gate, on the reasoning that "there
# the loop body is all-VEX and the ymm kernel wins about 2x". The kernel claim is right; the
# inference about these WRAPPERS was not, because **every one of them is hard-wired to a constant
# lane count** (f64v4 -> n=4, f32v8 -> n=8). They are not batch loops and never were, so there is
# no long loop for the ymm win to amortize over.
#
# Measured at v6.5.62, one variable at a time, on an 8-slot SOA biquad:
#   call + ymm  (shipped .61)   188-192 us     <- the baseline
#   call + 128  (kernel only)   189-195 us     <- removing ymm changes NOTHING
#   no call + 128 (the fix)     141-148 us     <- removing the CALL is the entire win, ~-25 %
# The dispatch CALL was the cost; the kernel width was irrelevant at a fixed 4 lanes. So the
# fixed-lane wrappers dropped the dispatch, and the raw builtins kept it available for the batch
# use where it genuinely pays (measured: f64v256_add beats f64v_add 1.3x at n=4, 2.4x at n=1024).
#
# ⭐ THE LESSON THIS GATE NOW ENCODES: a grep for an implementation detail is not a property.
# Axis 2 pinned a MECHANISM ("this source line exists"), so it could not tell a regression from a
# fix — it would have gone red on the correct change and stayed green through the wrong one. It
# never had a chance of catching the +59 % that shipped at v6.5.24 either. The axes below measure
# behaviour instead: the ymm kernel must still win at batch n (2b), and the fixed-lane wrappers
# must not be slower than a dispatch-free reference (2a). Same failure family as v6.5.36's enum
# gate, which stayed green through five bad releases by pinning the decoder rather than the value.
#
# ⚠ RATIOS, not absolute times, measured back-to-back on the same box so load moves both halves
# together.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL simd_valueform_no_avx_transition: no build/cycc"; exit 1; }

build() { "$CC" < "$T/$1.cyr" > "$T/$1" 2>/dev/null || { echo "FAIL simd_valueform_no_avx_transition: $1 fixture did not compile"; exit 1; }; chmod +x "$T/$1"; }
best() {  # best of 5, in ms
  b=999999; r=0
  while [ $r -lt 5 ]; do
    s=$(date +%s%N); "$1"; e=$(date +%s%N); m=$(( (e - s) / 1000000 ))
    [ $m -lt $b ] && b=$m
    r=$((r + 1))
  done
  echo $b
}

# ── axis 1 — the VALUE form must not be slower than a hand-written 128-bit reference ────────
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
build std; build ref
S=$(best "$T/std"); F=$(best "$T/ref")
[ "$F" -ge 2 ] || { echo "FAIL simd_valueform_no_avx_transition: reference ran in ${F}ms — too fast to compare, fixture broken"; exit 1; }
R100=$(( S * 100 / F ))
if [ "$R100" -ge 170 ]; then
  echo "FAIL simd_valueform_no_avx_transition axis1: stdlib value form ${S}ms vs 128-bit reference ${F}ms (${R100}%, bound 170%)."
  echo "  The f64v4 VALUE forms are paying an AVX<->SSE transition per call again."
  exit 1
fi

# ── axis 2a — THE REGRESSION AXIS (this is the one v6.5.24 needed and nobody had). ──────────
# The fixed-lane `_ptr` wrapper must not be slower than a dispatch-free hand reference.
#
# ⚠ THE FIXTURE IS A 6-LINK CHAIN, AND THE DEPTH IS LOAD-BEARING. A 1-op loop — the obvious
# fixture, and the first one written here — measures the mutant at only 118 % because the loop
# overhead dominates a single wrapper call. Against any bound loose enough not to flake, that
# axis CANNOT FIRE FOR ITS OWN TARGET, which is the vacuous-gate trap this file's header warns
# about. Measured with a 6-link chain: dispatch-free 100 %, per-call dispatch 160 %. Bound 135 %
# sits between them.
cat > "$T/pstd.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: f64v4 = f64v4_splat(0x3FF0000000000000);
    var b: f64v4 = f64v4_splat(0x4000000000000000);
    var i = 0;
    while (i < 500000) {
        var t1: f64v4 = f64v4_add_ptr(&a, &b);
        var t2: f64v4 = f64v4_add_ptr(&t1, &b);
        var t3: f64v4 = f64v4_add_ptr(&t2, &b);
        var t4: f64v4 = f64v4_add_ptr(&t3, &b);
        var t5: f64v4 = f64v4_add_ptr(&t4, &b);
        var t6: f64v4 = f64v4_add_ptr(&t5, &b);
        i = i + 1;
    }
    syscall(60, 0, 0, 0, 0, 0);
    return 0;
}
EOF
cat > "$T/pref.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn pref_add(a_ptr, b_ptr): f64v4 { var r: f64v4; f64v_add(&r, a_ptr, b_ptr, 4); return r; }
fn main(): i64 {
    var a: f64v4 = f64v4_splat(0x3FF0000000000000);
    var b: f64v4 = f64v4_splat(0x4000000000000000);
    var i = 0;
    while (i < 500000) {
        var t1: f64v4 = pref_add(&a, &b);
        var t2: f64v4 = pref_add(&t1, &b);
        var t3: f64v4 = pref_add(&t2, &b);
        var t4: f64v4 = pref_add(&t3, &b);
        var t5: f64v4 = pref_add(&t4, &b);
        var t6: f64v4 = pref_add(&t5, &b);
        i = i + 1;
    }
    syscall(60, 0, 0, 0, 0, 0);
    return 0;
}
EOF
build pstd; build pref
PS=$(best "$T/pstd"); PF=$(best "$T/pref")
[ "$PF" -ge 4 ] || { echo "FAIL simd_valueform_no_avx_transition axis2a: reference ran in ${PF}ms — too fast to compare, fixture broken"; exit 1; }
P100=$(( PS * 100 / PF ))
if [ "$P100" -ge 135 ]; then
  echo "FAIL simd_valueform_no_avx_transition axis2a: _ptr chain ${PS}ms vs dispatch-free reference ${PF}ms (${P100}%, bound 135%)."
  echo "  A per-call simd_has_avx2() dispatch is back in the fixed-lane _ptr wrappers (that cost ~25% from v6.5.24 to .61)."
  exit 1
fi

# ── axis 2b — CONTROL: the ymm kernel must still WIN at batch n, or dropping the wrapper
#     dispatch would have thrown away something real. Measured on the raw builtins, which no
#     wrapper edit can route around.
#
# ⛔ CAPABILITY-GUARDED, AND WITHOUT THE GUARD THIS AXIS FAILS OPEN. Calling `f64v256_*`
# directly executes VEX unconditionally; on a pre-AVX2 x86 host that is SIGILL / Windows
# STATUS_ILLEGAL_INSTRUCTION (0xC000001D). The crash is INSTANT, so `best()` would record a
# near-zero time for the 256-bit fixture, the ratio would look spectacular, and the axis would
# report a huge ymm win while measuring a crash. Found for real: the sibling `.tcyr` shipped this
# same unguarded pattern and turned the release gate RED on cass (Intel Celeron J4125 —
# Goldmont Plus, SSE4.2, no AVX2). Probe first, and SAY when the axis is skipped.
cat > "$T/hasavx.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 { syscall(60, simd_has_avx2(), 0, 0, 0, 0); return 0; }
var e = main();
EOF
build hasavx
if "$T/hasavx"; then HAS_AVX2=0; else HAS_AVX2=1; fi
cat > "$T/k128.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
var A[8192]; var B[8192]; var D[8192];
fn main(): i64 {
    var i = 0;
    while (i < 1024) { store64(&A + i * 8, 0x3FF0000000000000); store64(&B + i * 8, 0x4000000000000000); i = i + 1; }
    var k = 0;
    while (k < 20000) { f64v_add(&D, &A, &B, 1024); k = k + 1; }
    syscall(60, 0, 0, 0, 0, 0);
    return 0;
}
EOF
cat > "$T/k256.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
var A[8192]; var B[8192]; var D[8192];
fn main(): i64 {
    var i = 0;
    while (i < 1024) { store64(&A + i * 8, 0x3FF0000000000000); store64(&B + i * 8, 0x4000000000000000); i = i + 1; }
    var k = 0;
    while (k < 20000) { f64v256_add(&D, &A, &B, 1024); k = k + 1; }
    syscall(60, 0, 0, 0, 0, 0);
    return 0;
}
EOF
if [ "$HAS_AVX2" -eq 0 ]; then
  KR="skipped(no-AVX2-on-this-host)"
else
build k128; build k256
K1=$(best "$T/k128"); K2=$(best "$T/k256")
if [ "$K1" -ge 2 ] && [ "$K2" -ge 1 ]; then
  KR=$(( K2 * 100 / K1 ))
  if [ "$KR" -ge 100 ]; then
    echo "FAIL simd_valueform_no_avx_transition axis2b: the ymm kernel no longer wins at batch n"
    echo "  f64v256_add ${K2}ms vs f64v_add ${K1}ms over n=1024 (${KR}%, must be < 100%)."
    echo "  If ymm stopped paying even in a batch loop, the wrappers' dispatch removal needs re-deciding."
    exit 1
  fi
else
  KR="skipped(too-fast)"
fi
fi

# ── axis 2c — no fixed-lane wrapper may reintroduce a per-call dispatch. Cheap structural
#     backstop for axis 2a on a box too noisy to time. `fmadd`/`dot` legitimately keep a
#     dispatch (their two paths are NOT bit-identical — fused vs two roundings, and a different
#     reduction order) but must read the CACHED GLOBAL, never call the probe per invocation.
if grep -qE "if \(simd_has_(avx2|fma)\(\) == 1\)" "$R/lib/simd.cyr"; then
  echo "FAIL simd_valueform_no_avx_transition axis2c: a per-call simd_has_avx2()/simd_has_fma() dispatch is back in lib/simd.cyr:"
  grep -nE "if \(simd_has_(avx2|fma)\(\) == 1\)" "$R/lib/simd.cyr" | sed 's/^/    /'
  echo "  Fixed-lane wrappers must be flat, or (fmadd/dot) test _avx2_cache/_fma_cache directly."
  exit 1
fi

# ── axis 3 — correctness of the value form, all four lanes ──────────────────────────────────
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
build c
"$T/c" || { echo "FAIL simd_valueform_no_avx_transition axis3: f64v4_add value form is numerically wrong"; exit 1; }

echo "PASS simd_valueform_no_avx_transition: value ${S}ms/${F}ms (${R100}%) · _ptr ${PS}ms/${PF}ms (${P100}%) · ymm batch win ${KR}% · no per-call dispatch · 4 lanes correct"
exit 0
