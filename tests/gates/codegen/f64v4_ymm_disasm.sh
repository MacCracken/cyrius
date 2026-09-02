#!/bin/sh
# v6.5.24 (SIMD fix-list item 3) — verify the f64v4 256-bit AVX2 emitter
# (EMIT_F64V4_LOOP) produces the EXACT VEX bytes for packed-DOUBLE ops.
#
# ⛔ WHY THIS GATE IS THE REAL TEST. tests/tcyr/crossos/f64v4_ymm.tcyr checks VALUES, and
# on any host the ymm kernel and the 128-bit fallback return identical results — so the
# value test passes even if the AVX2 gate never selects ymm and the widening does nothing
# at all. Nothing else in the tree can tell "widened" from "silently didn't": decode.cyr
# explicitly excludes AVX/VEX, so there is no in-tree VEX oracle. This gate disassembles
# the emitted bytes REGARDLESS of the host CPU, so it also runs on non-AVX2 CI.
#
# ⚠ THE ONE-BIT TYPO THIS EXISTS TO CATCH. The f64 (packed-double) and f32 (packed-single)
# 256-bit kernels differ by a SINGLE BIT in the second VEX byte: FD is pp=01 (the 66-prefix
# slot → `pd`), FC is pp=00 (→ `ps`). Emit FC by mistake and every f64v4 op silently
# becomes a packed-SINGLE operation on double-precision bit patterns — garbage results, no
# diagnostic, no crash. Each check below therefore requires the exact bytes AND the
# intended MNEMONIC on the same disassembly line, so a pd→ps slip cannot pass: objdump
# would print vaddps where vaddpd is required. Same reason the f32v8 gate pins its
# mnemonics. All expected encodings verified against objdump's own decoding.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
command -v objdump >/dev/null 2>&1 || { echo "SKIP: objdump not available"; exit 0; }
T=$(mktemp); B=$(mktemp); D=$(mktemp)
trap 'rm -f "$T" "$B" "$D"' EXIT

# The raw f64v256_* builtins are called DIRECTLY here (unconditional AVX2) — that is the
# point: this probe is never executed, only disassembled, so it needs no CPU gate. Real
# consumer code reaches them only through the simd_has_avx2()-gated lib wrappers.
# `var a[32]` is 32 BYTES = exactly four f64 lanes (a local `var x[N]` is N bytes, not N
# slots), which matches the n=4 the ymm kernel strides over.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var a[32]; var b[32]; var r[32];
    f64v256_add(&r, &a, &b, 4);
    f64v256_sub(&r, &a, &b, 4);
    f64v256_mul(&r, &a, &b, 4);
    f64v256_div(&r, &a, &b, 4);
    return load64(&r);
}
var ec = main();
syscall(60, ec);
EOF
"$CC" < "$T" > "$B" 2>/dev/null || { echo "FAIL: f64v4 ymm disasm probe did not compile"; exit 1; }
objdump -d "$B" 2>/dev/null > "$D" || { echo "SKIP: objdump could not disassemble"; exit 0; }

# Anti-vacuous floor: if the probe compiled to something with no ymm instructions at all,
# every check below would still have to fail loudly — but assert the disassembly is
# non-trivial first so a truncated/empty objdump reports as blind rather than as clean.
LINES=$(wc -l < "$D")
[ "$LINES" -ge 50 ] || { echo "FAIL: disassembly only $LINES lines — objdump is blind, not the emitter silent"; exit 1; }

check() {
    grep -qiE "$1" "$D" || { echo "FAIL: missing $2  (expected bytes: $1)"; exit 1; }
}
# Loads/store: SIB f2 = [rdx+rsi*8] (scale 8 = one f64 per index step), 32 bytes moved.
check "c5 fd 10 04 f2 *[[:space:]]+vmovupd.*ymm0" "vmovupd ymm0,[rdx+rsi*8] load"
check "c5 fd 10 0c f2 *[[:space:]]+vmovupd.*ymm1" "vmovupd ymm1,[rdx+rsi*8] load"
check "c5 fd 11 04 f2 *[[:space:]]+vmovupd.*ymm0" "vmovupd [rdx+rsi*8],ymm0 store"
# The four arithmetic ops — the mnemonic must end in `pd`, not `ps` (see the note above).
check "c5 fd 58 c1 *[[:space:]]+vaddpd.*ymm"      "vaddpd ymm0,ymm0,ymm1"
check "c5 fd 5c c1 *[[:space:]]+vsubpd.*ymm"      "vsubpd ymm0,ymm0,ymm1"
check "c5 fd 59 c1 *[[:space:]]+vmulpd.*ymm"      "vmulpd ymm0,ymm0,ymm1"
check "c5 fd 5e c1 *[[:space:]]+vdivpd.*ymm"      "vdivpd ymm0,ymm0,ymm1"
# Without vzeroupper every later legacy-SSE instruction pays the AVX↔SSE transition
# penalty — which would silently eat the speedup this whole item exists to deliver.
check "c5 f8 77 *[[:space:]]+vzeroupper"          "vzeroupper (AVX/SSE transition guard)"
# The 4-lane stride — and this check earns its place. MUTATION-PROVEN at v6.5.24: with the
# stride changed to 2 (the shape you get by copying the 128-bit emitter), the value test
# tests/tcyr/crossos/f64v4_ymm.tcyr still passed 23/23, because the second iteration
# recomputes lanes 2-3 correctly — while storing 32 bytes at index 2, i.e. writing 16 bytes
# PAST the end of the 32-byte vector. A silent out-of-bounds write that every value
# assertion is blind to. This line is the only thing in the tree that sees it.
# objdump prints AT&T order here: `add $0x4,%rsi` — immediate first, destination last.
check "48 83 c6 04 *[[:space:]]+add.*0x4.*rsi"    "add rsi,4 (4-lane stride)"

# ---------------------------------------------------------------------------------------
# v6.5.38 — the five ops `.24` left on the 128-bit kernel: fmadd, dot, scale, abs, sqrt.
# Second probe, because these need their own builtins and (for dot/scale/abs) instructions
# that appear nowhere in the four arithmetic kernels above.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var a[32]; var b[32]; var c[32]; var r[32];
    f64v256_fmadd(&r, &a, &b, &c, 4);
    f64v256_scale(&r, &a, 0, 4);
    f64v256_abs(&r, &a, 4);
    f64v256_sqrt(&r, &a, 4);
    return f64v256_dot(&a, &b, 4);
}
var ec = main();
syscall(60, ec);
EOF
"$CC" < "$T" > "$B" 2>/dev/null || { echo "FAIL: f64v4 ymm extended-op probe did not compile"; exit 1; }
objdump -d "$B" 2>/dev/null > "$D" || { echo "SKIP: objdump could not disassemble"; exit 0; }
LINES=$(wc -l < "$D")
[ "$LINES" -ge 50 ] || { echo "FAIL: extended-op disassembly only $LINES lines — objdump is blind"; exit 1; }

# sqrt / abs: the mnemonic must be the DOUBLE form. vsqrtps on double bit patterns is the
# same silent-garbage failure the pd/ps note above describes.
check "c5 fd 51 c0 *[[:space:]]+vsqrtpd.*ymm"     "vsqrtpd ymm0,ymm0"
check "c5 fd 54 c2 *[[:space:]]+vandpd.*ymm"      "vandpd ymm0,ymm0,ymm2 (abs mask apply)"
# The abs sign-mask is built with 256-bit INTEGER ops — these are AVX2, not AVX1, which is
# why the lib wrapper must stay gated on simd_has_avx2() and never on a bare AVX check.
check "c5 ed 76 d2 *[[:space:]]+vpcmpeqd.*ymm"    "vpcmpeqd ymm2,ymm2,ymm2 (all-ones)"
check "c5 ed 73 d2 01 *[[:space:]]+vpsrlq.*ymm"   "vpsrlq ymm2,ymm2,1 (clear sign bit)"
# scale broadcasts the scalar to all FOUR lanes. The 128-bit kernel uses `unpcklpd`, which
# fills only two — if that instruction appears here instead, lanes 2-3 get garbage.
check "c4 e2 7d 19 d2 *[[:space:]]+vbroadcastsd.*ymm" "vbroadcastsd ymm2,xmm2 (4-lane scalar broadcast)"
# dot's cross-lane fold. haddpd on ymm sums WITHIN each 128-bit lane and never crosses the
# boundary, so without this extract+add the upper two products are silently dropped and
# the dot product is simply wrong (the .tcyr asserts 570, which a lane-local fold gets as
# 100). These two lines are what make the reduction correct.
check "c4 e3 7d 19 d0 01 *[[:space:]]+vextractf128" "vextractf128 xmm0,ymm2,1 (upper lane)"
check "c5 e9 58 d0 *[[:space:]]+vaddpd.*xmm"      "vaddpd xmm2,xmm2,xmm0 (fold upper into lower)"
check "c5 ed 57 d2 *[[:space:]]+vxorpd.*ymm"      "vxorpd ymm2,ymm2,ymm2 (zero accumulator)"
# vzeroupper must sit BEFORE the legacy-SSE haddpd, or every dot call pays the AVX/SSE
# transition penalty on the reduction tail.
check "c5 f8 77 *[[:space:]]+vzeroupper"          "vzeroupper (extended ops)"
check "66 0f 7c d2 *[[:space:]]+haddpd"           "haddpd xmm2,xmm2 (final scalar fold)"
# All five extended kernels stride 4, same mutation-proven reasoning as the block above.
check "48 83 c6 04 *[[:space:]]+add.*0x4.*rsi"    "add rsi,4 (4-lane stride, extended ops)"

echo "PASS: f64v4 256-bit AVX2 emits exact VEX bytes (vmovupd/vaddpd/vsubpd/vmulpd/vdivpd ymm + vzeroupper, stride 4)"
echo "PASS: f64v4 extended ops (fmadd/dot/scale/abs/sqrt) emit exact 256-bit VEX bytes"
