#!/bin/sh
# check: serial — a timing measurement (value form vs a 128-bit reference); under the parallel pool's load it read 190% once (6.7.6), alone 100%; ~190 ms fixtures read by their own CPU time, re-measured up to 3 rounds, since 6.7.16
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
#
# ⚠ AND EVERY TIMED FIXTURE RUNS ~180 ms AND REPORTS ITS OWN CPU TIME, IN MICROSECONDS, BEST OF 5
# (6.7.16). Axes 1 and 2a timed 8-35 ms fixtures by the wall clock in whole ms, where 1 ms is ~7 %
# of a ratio and a few ms of preemption on one side crosses a bound: axis 2a read `_ptr chain 27ms
# vs dispatch-free reference 18ms (150%, bound 135%)` on a correct tree at load ~20 (axis 1 read
# 190 % once, 6.7.6). Longer fixtures alone do not cure it: measured at load ~32 on this 16-thread
# box (20 busy loops beside the usual load), ~180 ms fixtures by the WALL clock in µs read axis 2a
# 94-166 % honest against 135-208 % for the dispatch mutant — no bound separates those — whether
# timed back to back, interleaved, or both pinned to one CPU. The wall clock counts the time a
# fixture waits for a CPU; its own CPU time does not. Each fixture therefore prints
# CLOCK_PROCESS_CPUTIME_ID in µs as it exits (`_cpu_report`, prepended by `build`) and `best_cpu`
# keeps the lowest of 5: at that same load axis 2a read 113-116 % honest, 148-151 % mutant; axis 1
# 90-92 % / 180-193 %. Under load that VARIES (other sessions, load 11-23) the honest reading still
# wanders (2a 82-127 %), so a reading at or over a bound is re-measured, up to 3 rounds
# (`ratio_rounds`), and the axis fails only when every round is over: the regressions these bounds
# guard read over them every round. A reference whose CPU time is under 100,000 µs FAILS by name
# (`too-fast`): these are the regression axes, and a skip would hide them. CHANGELOG [6.7.16];
# issues/archived/2026-10-19-simd-valueform-axis2a-reads-150-percent-under-host-load.md
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || { echo "FAIL: simd_valueform_no_avx_transition: cannot cd to $R"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: simd_valueform_no_avx_transition: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL simd_valueform_no_avx_transition: no build/cycc"; exit 1; }

# Every fixture is compiled behind this head: `_cpu_report()` prints the process's CPU time
# (clock_gettime(CLOCK_PROCESS_CPUTIME_ID = 2), x86_64 228) in µs and a newline. Builtins only, so it
# sits before the fixture's own includes.
cat > "$T/head.cyr" <<'EOF'
fn _cpu_report(): i64 {
    var ts[16];
    syscall(228, 2, &ts);
    var us = load64(&ts) * 1000000 + load64(&ts + 8) / 1000;
    var buf[32];
    var p = 31;
    store8(&buf + p, 10);
    p = p - 1;
    if (us == 0) { store8(&buf + p, 48); p = p - 1; }
    while (us > 0) { store8(&buf + p, 48 + us % 10); us = us / 10; p = p - 1; }
    syscall(1, 1, &buf + p + 1, 31 - p);
    return 0;
}
EOF
build() { cat "$T/head.cyr" "$T/$1.cyr" | "$CC" > "$T/$1" 2>/dev/null || { echo "FAIL simd_valueform_no_avx_transition: $1 fixture did not compile"; exit 1; }; chmod +x "$T/$1"; }
best_cpu() {  # best of 5 of the CPU time the fixture reports, in µs; `x` when a run printed none
  b=999999999; r=0
  while [ $r -lt 5 ]; do
    m=$("$1" 2>/dev/null) || true
    case "$m" in ''|*[!0-9]*) echo x; return 0 ;; esac
    [ "$m" -lt "$b" ] && b=$m
    r=$((r + 1))
  done
  echo $b
}
need_cpu() {  # need_cpu <axis> <fixture> <value>
  case "$3" in ''|*[!0-9]*) echo "FAIL simd_valueform_no_avx_transition $1: the $2 fixture printed no CPU time — fixture broken, nothing to compare"; exit 1 ;; esac
}
# ratio_rounds <axis> <a> <b> <bound>: best_cpu a / best_cpu b, as a percentage, re-measured for up
# to 3 rounds while it reads at or over the bound. Sets RA / RB / RR (the last round's), RN (the
# rounds run) and RLOG (every round's reading). A disagreement is RE-MEASURED, never re-judged: the
# regression each bound guards reads over it on every round, and a FAIL names all three readings.
ratio_rounds() {
  RN=0; RLOG=""
  while [ "$RN" -lt 3 ]; do
    RA=$(best_cpu "$2"); need_cpu "$1" "${2##*/}" "$RA"
    RB=$(best_cpu "$3"); need_cpu "$1" "${3##*/}" "$RB"
    RN=$((RN + 1))
    RR=$(( RA * 100 / RB ))
    RLOG="$RLOG ${RA}us/${RB}us ${RR}%;"
    [ "$RR" -lt "$4" ] && return 0
  done
  return 0
}

# ── axis 1 — the VALUE form must not be slower than a hand-written 128-bit reference ────────
# 48,000,000 calls (2,000,000 until 6.7.16: ~9 ms): ~185 ms of CPU each on this box, 1.8x the
# too-fast floor. Measured 2026-10-20 through this gate, three runs each: honest 100-101 % at load
# ~3-6 and 106-107 % at load ~31 (20 busy loops beside the usual load); the value form routed
# through the ymm kernel behind a per-call dispatch (the pre-6.5.60 shape: `if (simd_has_avx2() ==
# 1) { f64v256_add(&r, &a, &b, 4); }` in f64v4_add) 279-293 % and 183-189 % — over the bound on
# every round of every run. Bound 170 % sits between them.
cat > "$T/std.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: f64v4 = f64v4_splat(0x3FF0000000000000);
    var b: f64v4 = f64v4_splat(0x4000000000000000);
    var i = 0;
    while (i < 48000000) { var t: f64v4 = f64v4_add(a, b); i = i + 1; }
    _cpu_report();
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
    while (i < 48000000) { var t: f64v4 = ref_add(a, b); i = i + 1; }
    _cpu_report();
    syscall(60, 0, 0, 0, 0, 0);
    return 0;
}
EOF
build std; build ref
ratio_rounds axis1 "$T/std" "$T/ref" 170
S=$RA; F=$RB; R100=$RR; RN1=$RN
[ "$F" -ge 100000 ] || { echo "FAIL simd_valueform_no_avx_transition axis1: too-fast — the reference ran in ${F}us, under 100,000 (a ratio of short runs is noise; lengthen the fixtures, or the fixture is broken)"; exit 1; }
if [ "$R100" -ge 170 ]; then
  echo "FAIL simd_valueform_no_avx_transition axis1: stdlib value form vs 128-bit reference, CPU time, bound 170%, every round over it:${RLOG}"
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
# 6.7.16: 7,000,000 passes (500,000 until then: ~15 ms), ~195 ms of CPU each on this box.
# Re-measured 2026-10-20 through this gate, three runs each: dispatch-free 96-100 % at load ~3-6 and
# 98-100 % at load ~31; the per-call dispatch mutant (`if (simd_has_avx2() == 1) {
# f64v256_add(&r, a_ptr, b_ptr, 4); }` in f64v4_add_ptr, the v6.5.24-.61 shape) 161-169 % on every
# round at load ~3-6. ⚠ At load ~31 the mutant compresses: 136-146 % on every round of two runs, and
# under 135 % in the third, which axis 2c (the structural backstop below) then failed. The 135 %
# bound still separates them; on a box that loaded, 2c is what holds.
cat > "$T/pstd.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: f64v4 = f64v4_splat(0x3FF0000000000000);
    var b: f64v4 = f64v4_splat(0x4000000000000000);
    var i = 0;
    while (i < 7000000) {
        var t1: f64v4 = f64v4_add_ptr(&a, &b);
        var t2: f64v4 = f64v4_add_ptr(&t1, &b);
        var t3: f64v4 = f64v4_add_ptr(&t2, &b);
        var t4: f64v4 = f64v4_add_ptr(&t3, &b);
        var t5: f64v4 = f64v4_add_ptr(&t4, &b);
        var t6: f64v4 = f64v4_add_ptr(&t5, &b);
        i = i + 1;
    }
    _cpu_report();
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
    while (i < 7000000) {
        var t1: f64v4 = pref_add(&a, &b);
        var t2: f64v4 = pref_add(&t1, &b);
        var t3: f64v4 = pref_add(&t2, &b);
        var t4: f64v4 = pref_add(&t3, &b);
        var t5: f64v4 = pref_add(&t4, &b);
        var t6: f64v4 = pref_add(&t5, &b);
        i = i + 1;
    }
    _cpu_report();
    syscall(60, 0, 0, 0, 0, 0);
    return 0;
}
EOF
build pstd; build pref
ratio_rounds axis2a "$T/pstd" "$T/pref" 135
PS=$RA; PF=$RB; P100=$RR; RN2=$RN
[ "$PF" -ge 100000 ] || { echo "FAIL simd_valueform_no_avx_transition axis2a: too-fast — the reference ran in ${PF}us, under 100,000 (the regression axis must not skip; lengthen the fixtures, or the fixture is broken)"; exit 1; }
if [ "$P100" -ge 135 ]; then
  echo "FAIL simd_valueform_no_avx_transition axis2a: _ptr chain vs dispatch-free reference, CPU time, bound 135%, every round over it:${RLOG}"
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
#
# 6.7.14: THE FIXTURES RUN 150,000 PASSES (were 20,000) AND ARE TIMED IN MICROSECONDS. At 20,000
# each best-of-5 was ~9-13 ms in whole ms, so one ms was ~11 % of the ratio, and under host load
# a check.sh run read `f64v256_add 9ms vs f64v_add 9ms (100%)` and failed the strict bound. Now
# the 128-bit run is ~47 ms on a quiet box, the 256-bit ~25 ms (a 128-bit run under 20 ms is
# reported `too-fast`, by name), and each fixture must exit 0 having computed the right sum in
# its last lane before it is timed: a fixture that does not run its kernel is a loud FAIL, never
# a spectacular ratio.
# THE BOUND IS 90 %, NOT 100 %: with f64v256_add routed through the 128-bit kernel (EMIT_F64V_LOOP
# for EMIT_F64V4_LOOP in parse_expr.cyr's 154-157 arm) the two fixtures are the same code and read
# 98-103 %, so `< 100 %` caught that mutation in only four runs of eight — a coin flip. A tie is
# not a win. The real win reads 52-55 % on a quiet box. Mutation (6.7.14): that routing -> RED,
# eight runs of eight.
# issues/archived/2026-10-16-simd-valueform-axis2b-reads-100-percent-under-host-load.md
# 6.7.16: 600,000 passes (150,000 until then) and the fixtures' own CPU time, as axes 1 and 2a (see
# the header): the 128-bit run ~190 ms, the 256-bit ~100 ms. At 150,000 passes and CPU time the
# routing mutation above read 86 % — a PASS — in one run of four at load ~18; at 600,000 it read
# 96-103 % on every round of four runs, honest 51-57 %. The 20,000 µs too-fast floor (a named skip)
# and the 90 % bound unchanged.
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
    while (k < 600000) { f64v_add(&D, &A, &B, 1024); k = k + 1; }
    var bad = 1;
    if (load64(&D + 1023 * 8) == 0x4008000000000000) { bad = 0; }
    _cpu_report();
    syscall(60, bad, 0, 0, 0, 0);
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
    while (k < 600000) { f64v256_add(&D, &A, &B, 1024); k = k + 1; }
    var bad = 1;
    if (load64(&D + 1023 * 8) == 0x4008000000000000) { bad = 0; }
    _cpu_report();
    syscall(60, bad, 0, 0, 0, 0);
    return 0;
}
EOF
KR_BOUND=90; KD=""
if [ "$HAS_AVX2" -eq 0 ]; then
  KR="skipped(no-AVX2-on-this-host)"
else
build k128; build k256
for k in k128 k256; do
  rc=0; "$T/$k" > /dev/null || rc=$?
  [ "$rc" = 0 ] || { echo "FAIL simd_valueform_no_avx_transition axis2b: the $k fixture exits $rc, want 0 (its last lane 1.0 + 2.0 = 3.0) — fixture broken, nothing to time"; exit 1; }
done
ratio_rounds axis2b "$T/k256" "$T/k128" "$KR_BOUND"
K2=$RA; K1=$RB
if [ "$K1" -ge 20000 ]; then
  KR=$RR; KD=" (${K2}us/${K1}us)"
  if [ "$KR" -ge "$KR_BOUND" ]; then
    echo "FAIL simd_valueform_no_avx_transition axis2b: the ymm kernel no longer wins at batch n"
    echo "  f64v256_add vs f64v_add over n=1024 x 600,000, CPU time, must be < ${KR_BOUND}%, every round over it:${RLOG}"
    echo "  If ymm stopped paying even in a batch loop, the wrappers' dispatch removal needs re-deciding."
    exit 1
  fi
else
  KR="skipped(too-fast: f64v_add ${K1}us, under 20,000)"
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

echo "PASS simd_valueform_no_avx_transition: value ${S}us/${F}us CPU (${R100}%, round ${RN1}) · _ptr ${PS}us/${PF}us CPU (${P100}%, round ${RN2}) · ymm batch win ${KR}%${KD} · no per-call dispatch · 4 lanes correct"
exit 0
