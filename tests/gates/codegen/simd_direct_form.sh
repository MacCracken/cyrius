#!/bin/sh
# simd_direct_form.sh — v6.5.64. A fixed-lane vector binary op on three `&local` operands must
# emit the DIRECT form (two loads, the packed op, one store) with its result reload ELIDED —
# while a genuine BATCH call must still get the pointer+loop kernel and still be correct.
#
# WHY. Every value-form wrapper in lib/simd.cyr expands to `f32v_add(&r, &a, &b, 4)` /
# `f64v_add(&r, &a, &b, 2)`: a constant lane count and three known frame displacements. The batch
# emitters are memory kernels that pull three POINTERS out of stash slots and loop, so that shape
# cost 28 real instructions and ~15 memory ops for ONE packed op.
#
# ⛔ REMOVING THOSE INSTRUCTIONS IS WORTH ZERO ON ITS OWN — measured before this was built. The
# critical path is 16-byte STORE-TO-LOAD FORWARDS and the pointer machinery is not on it: a
# hand-written replica removing exactly that scaffolding ran 33.99 ms against 33.96 ms. What pays
# is that the direct form leaves the result store and the `return r` reload ADJACENT, so the
# v6.5.53 SLASE peephole collapses them. Hence axis 2 asserts the ELIDED RELOAD: a direct form
# that did not enable SLASE would look correct and buy nothing.
#
# ⚠ AN ABSOLUTE COUNT OF LOOP KERNELS IS THE WRONG TEST, and the first cut of this gate used one.
# Other reachable lib/simd.cyr wrappers legitimately keep their loops — 18 remain even under
# CYRIUS_DCE=1 — so the value-form call site is only a DELTA of 3. The unambiguous signal is the
# direct form's ADJACENT SIGNATURE, which the loop kernel can never produce (it addresses
# (%rdx,%rsi,4), never %rbp).
#
# ⭐ AXIS 3 IS THE ANTI-VACUOUS CONTROL AND IT IS THE IMPORTANT ONE. The fast path is chosen by
# TOKEN LOOKAHEAD and swallows 11 tokens unevaluated. If its preconditions ever loosened — a
# non-constant lane count, an operand that is not a 128-bit vector local — it would emit a
# 16-byte op over the wrong extent. A real batch MUST keep its loop and MUST stay correct over
# all n elements.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL simd_direct_form: no build/cycc"; exit 1; }
command -v objdump >/dev/null 2>&1 || { echo "FAIL simd_direct_form: objdump required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL simd_direct_form: python3 required"; exit 1; }

build() { "$CC" < "$T/$1.cyr" > "$T/$1" 2>/dev/null || { echo "FAIL simd_direct_form: $1 fixture did not compile"; exit 1; }; chmod +x "$T/$1"; }

# ── axes 1 + 2 — the direct form is emitted AND its reload is elided ─────────────────────────
cat > "$T/direct.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: f32v4 = f32v4_make(0x3F800000, 0x40000000, 0x40400000, 0x40800000);
    var b: f32v4 = f32v4_make(0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000);
    var t: f32v4 = f32v4_add(a, b);
    syscall(60, f32v4_lane3(&t) & 0xFF, 0, 0, 0, 0);
    return 0;
}
var e = main();
EOF
build direct
python3 - "$T/direct" <<'PYEOF' || exit 1
import subprocess, sys, re
d = subprocess.run(['objdump','-d','--no-show-raw-insn',sys.argv[1]],capture_output=True,text=True).stdout
ins = [l.split('\t')[-1].strip() for l in d.splitlines() if re.match(r'^\s+[0-9a-f]+:', l)]
LD0 = re.compile(r'^movupd\s+-0x[0-9a-f]+\(%rbp\),%xmm0$')
LD1 = re.compile(r'^movupd\s+-0x[0-9a-f]+\(%rbp\),%xmm1$')
OP  = re.compile(r'^(addps|addpd)\s+%xmm1,%xmm0$')
ST  = re.compile(r'^movupd\s+%xmm0,-0x[0-9a-f]+\(%rbp\)$')
found = elided = 0
for i in range(len(ins) - 4):
    if LD0.match(ins[i]) and LD1.match(ins[i+1]) and OP.match(ins[i+2]) and ST.match(ins[i+3]):
        found += 1
        if ins[i+4].startswith('nop'):
            elided += 1
if found == 0:
    print('FAIL simd_direct_form axis1: no direct-form sequence emitted.')
    print('  Expected adjacent: movupd -d(%rbp),%xmm0 / movupd -d(%rbp),%xmm1 / addps %xmm1,%xmm0 / movupd %xmm0,-d(%rbp)')
    print('  The constant-lane &local call still went through the pointer+loop kernel.')
    sys.exit(1)
if elided == 0:
    print('FAIL simd_direct_form axis2: %d direct-form sequence(s), but NONE had the result reload elided.' % found)
    print('  SLASE did not collapse the store/reload pair, so the direct form removed instructions')
    print('  without removing the store-to-load forward that is what actually costs time.')
    sys.exit(1)
print('  axis1+2 ok: %d direct-form sequence(s), %d with the reload elided' % (found, elided))
PYEOF

# ── axis 3 — CONTROL: a genuine 16-lane BATCH keeps its loop and stays correct ───────────────
cat > "$T/batch.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
var A[128]; var B[128]; var D[128];
fn main(): i64 {
    var i = 0;
    while (i < 16) { store32(&A + i * 4, 0x3F800000); store32(&B + i * 4, 0x3F800000); i = i + 1; }
    f32v_add(&D, &A, &B, 16);
    var bad = 0;
    var k = 0;
    while (k < 16) { if (load32(&D + k * 4) != 0x40000000) { bad = bad + 1; } k = k + 1; }
    syscall(60, bad, 0, 0, 0, 0);
    return 0;
}
var e = main();
EOF
build batch
BSIB=$(objdump -d --no-show-raw-insn "$T/batch" 2>/dev/null | grep -cE 'movups .*\(%rdx,%rsi,4\)')
if [ "$BSIB" -eq 0 ]; then
  echo "FAIL simd_direct_form axis3: a 16-lane BATCH call lost its loop kernel."
  echo "  The direct form writes exactly 16 bytes; taking it for a real batch corrupts elements 4..15."
  exit 1
fi
"$T/batch"; BRC=$?
[ "$BRC" -eq 0 ] || { echo "FAIL simd_direct_form axis3: 16-lane batch computed ${BRC} wrong element(s)"; exit 1; }

# ── axis 4 — CONTROL: &GLOBAL operands must not take the direct form, and must not clobber ───
cat > "$T/globalop.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
var A[64]; var B[64]; var D[64];
fn main(): i64 {
    var guard = 0x5A5A5A5A;
    var i = 0;
    while (i < 4) { store32(&A + i * 4, 0x3F800000); store32(&B + i * 4, 0x3F800000); i = i + 1; }
    f32v_add(&D, &A, &B, 4);
    var bad = 0;
    if (load32(&D) != 0x40000000) { bad = bad + 1; }
    if (guard != 0x5A5A5A5A) { bad = bad + 2; }
    syscall(60, bad, 0, 0, 0, 0);
    return 0;
}
var e = main();
EOF
build globalop
"$T/globalop"; SRC=$?
[ "$SRC" -eq 0 ] || { echo "FAIL simd_direct_form axis4: &global operands mis-handled (code ${SRC}; +2 = guard clobbered)"; exit 1; }

# ── axis 5 — correctness of both widths, EVERY lane, add/mul/div ─────────────────────────────
cat > "$T/lanes.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var bad = 0;
    var a: f32v4 = f32v4_make(0x3F800000, 0x40000000, 0x40400000, 0x40800000);
    var b: f32v4 = f32v4_make(0x3F800000, 0x3F800000, 0x3F800000, 0x3F800000);
    var s: f32v4 = f32v4_add(a, b);
    if (f32v4_lane0(&s) != 0x40000000) { bad = bad + 1; }
    if (f32v4_lane1(&s) != 0x40400000) { bad = bad + 1; }
    if (f32v4_lane2(&s) != 0x40800000) { bad = bad + 1; }
    if (f32v4_lane3(&s) != 0x40A00000) { bad = bad + 1; }
    var p: f64v2 = f64v2_make(0x4024000000000000, 0x4034000000000000);
    var q: f64v2 = f64v2_make(0x4000000000000000, 0x4000000000000000);
    var r: f64v2 = f64v2_mul(p, q);
    if (load64(&r + 0) != 0x4034000000000000) { bad = bad + 1; }
    if (load64(&r + 8) != 0x4044000000000000) { bad = bad + 1; }
    var d: f64v2 = f64v2_div(p, q);
    if (load64(&d + 0) != 0x4014000000000000) { bad = bad + 1; }
    if (load64(&d + 8) != 0x4024000000000000) { bad = bad + 1; }
    syscall(60, bad, 0, 0, 0, 0);
    return 0;
}
var e = main();
EOF
build lanes
"$T/lanes"; LRC=$?
[ "$LRC" -eq 0 ] || { echo "FAIL simd_direct_form axis5: ${LRC} lane(s) wrong across f32v4/f64v2 add/mul/div"; exit 1; }

# ── axis 6 — THE INLINE-PARAM COPY MUST NOT BE READ BACK (v6.5.65) ──────────────────────────
# The inline replay copies each value-form argument into a fresh callee param slot:
#     movupd -e(%rbp),%xmm0      <- read the caller's local
#     movupd %xmm0,-d(%rbp)      <- write the param slot   (the COPY)
#     ...
#     movupd -d(%rbp),%xmmN      <- read it back            (a 16-byte store-to-load FORWARD)
# That read-back is what v6.5.65 removes, by having the emitter read -e directly. Forwards are
# the critical path — measured `.64`: removing 22 instructions per link WITHOUT removing a
# forward bought exactly 1.00x — so a value test cannot see this and it must be asserted on the
# emitted code or it regresses silently.
#
# ⚠ THE FIRST CUT OF THIS AXIS FLAGGED ANY load-after-store WITHIN 4 INSTRUCTIONS AND WAS WRONG:
# it also caught the legitimate producer->consumer dependency from `f32v4_make` building the
# operands, so it fired on the FIXED compiler too. What is redundant is specifically reading back
# a slot whose only content is a COPY of another slot — that is the pattern matched below.
python3 - "$T/direct" <<'PYEOF' || exit 1
import subprocess, sys, re
d = subprocess.run(['objdump','-d','--no-show-raw-insn',sys.argv[1]],capture_output=True,text=True).stdout
ins = [l.split('\t')[-1].strip() for l in d.splitlines() if re.match(r'^\s+[0-9a-f]+:', l)]
LDX = re.compile(r'^movupd\s+(-0x[0-9a-f]+)\(%rbp\),%xmm0$')
STX = re.compile(r'^movupd\s+%xmm0,(-0x[0-9a-f]+)\(%rbp\)$')
ANYLD = re.compile(r'^movupd\s+(-0x[0-9a-f]+)\(%rbp\),%xmm[01]$')
copies = {}          # param slot -> source slot, for slots written by a verbatim copy
readback = 0
for i in range(len(ins)):
    m = STX.match(ins[i])
    if m and i > 0:
        src = LDX.match(ins[i-1])
        copies[m.group(1)] = src.group(1) if src else None
        continue
    r = ANYLD.match(ins[i])
    if r and r.group(1) in copies and copies[r.group(1)] is not None:
        readback += 1
if readback:
    print('FAIL simd_direct_form axis6: %d read-back(s) of an inline-param COPY.' % readback)
    print('  The emitter is loading the copied param slot instead of the caller local it was')
    print('  copied from. That is a 16-byte store-to-load forward and is what actually costs time.')
    sys.exit(1)
print('  axis6 ok: no inline-param copy is read back')
PYEOF

echo "PASS simd_direct_form: direct form emitted + reload elided + no operand forward · 16-lane batch keeps its loop and is correct · &global safe · all lanes correct both widths"
exit 0
