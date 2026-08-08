#!/bin/sh
# v6.4.8 (SIMD Phase 4 R1) — verify the f32v8 256-bit AVX2 emitter (EMIT_F32V8_LOOP)
# produces the EXACT VEX bytes. There is no in-tree VEX oracle (decode.cyr explicitly
# excludes AVX/VEX), and the value-checking simd_f32v8.tcyr only exercises the AVX2 path
# at runtime on an AVX2 host (else it takes the SSE fallback). This gate disassembles the
# emitted bytes REGARDLESS of the host CPU — catching a vvvv/opcode byte-order typo (the
# invisible wrong-register class the CLAUDE.md closeout warns about) even on non-AVX2 CI.
# All expected encodings were assembled + round-trip-verified with llvm-mc.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
command -v objdump >/dev/null 2>&1 || { echo "SKIP: objdump not available"; exit 0; }
T=$(mktemp); B=$(mktemp); D=$(mktemp)
trap 'rm -f "$T" "$B" "$D"' EXIT

cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var a[32]; var b[32]; var c[32]; var r[32];
    f32v8_add(&r, &a, &b, 8);
    f32v8_sub(&r, &a, &b, 8);
    f32v8_mul(&r, &a, &b, 8);
    f32v8_fma(&r, &a, &b, &c, 8);
    var dsum = f32v8_dot(&a, &b, 8);
    return load32(&r) + dsum;
}
var ec = main();
syscall(60, ec);
EOF
"$CC" < "$T" > "$B" 2>/dev/null || { echo "FAIL: f32v8 disasm probe did not compile"; exit 1; }
objdump -d "$B" 2>/dev/null > "$D" || { echo "SKIP: objdump could not disassemble"; exit 0; }

# Each check requires the EXACT bytes AND the intended mnemonic on the same line —
# proving byte sequence X decodes to instruction Y (a vvvv typo would decode to a
# different %ymm register and this would miss it).
check() {
    grep -qiE "$1" "$D" || { echo "FAIL: missing $2  (expected bytes: $1)"; exit 1; }
}
check "c5 fc 10 04 b2 *[[:space:]]+vmovups.*ymm0" "vmovups ymm0,[rdx+rsi*4] load"
check "c5 fc 10 0c b2 *[[:space:]]+vmovups.*ymm1" "vmovups ymm1,[rdx+rsi*4] load"
check "c5 fc 58 c1 *[[:space:]]+vaddps.*ymm"      "vaddps ymm0,ymm0,ymm1"
check "c5 fc 5c c1 *[[:space:]]+vsubps.*ymm"      "vsubps ymm0,ymm0,ymm1"
check "c5 fc 59 c1 *[[:space:]]+vmulps.*ymm"      "vmulps ymm0,ymm0,ymm1"
check "c5 fc 11 04 b2 *[[:space:]]+vmovups.*ymm0" "vmovups [rdx+rsi*4],ymm0 store"
check "c5 f8 77 *[[:space:]]+vzeroupper"          "vzeroupper (AVX/SSE transition guard)"
# R2 (v6.4.9): the 3-byte VEX (C4) fma + the 8-lane dot reduce.
check "c4 e2 7d b8 d1 *[[:space:]]+vfmadd231ps.*ymm"  "vfmadd231ps ymm (FMA3, 3-byte VEX)"
check "c4 e3 7d 19 d1 01 *[[:space:]]+vextractf128"   "vextractf128 xmm1,ymm2,1 (3-byte VEX + imm8)"
check "c5 e8 58 d1 *[[:space:]]+vaddps.*xmm"          "vaddps xmm2,xmm2,xmm1 (L=0 128-bit fold)"

echo "PASS: f32v8 256-bit AVX2 emits exact VEX bytes (vmovups/vaddps/vsubps/vmulps/vfmadd231ps/vextractf128 ymm + vzeroupper)"
