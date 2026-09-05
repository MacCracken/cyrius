#!/bin/sh
# aggregate_copy_all_words.sh — v6.5.57. Copying an aggregate copies EVERY word.
#
# THE DEFECT (P1, silent wrong values, pre-existing). `dst = src;` for any aggregate wider than
# one 8-byte slot copied only the FIRST word. A two-field struct kept `x` and left `y` at its old
# value; an `f32v4` kept lane 0 and dropped lanes 2-3. Exit 0, no diagnostic. The DECLARATION form
# had been correct since the struct-byval work; the assignment path never got the equivalent.
#
# ⭐ IT WAS REPORTED AS A SIMD BUG AND IT IS NOT ONE. A plain struct truncates identically, and
# structs are far more common — fixing only the vector arm would have left the usual case live.
# Axis 1 is therefore a struct, deliberately, and the vector axes come after it.
#
# ⭐ THE THIRD FIX IS THE ONE WORTH KNOWING ABOUT — A LATENT REGISTER-ALLOCATOR BUG. An
# aggregate's fields are reached as `lea rcx,[rbp+base]` then `mov [rcx+off]`, so ONLY the base
# slot ever appears as an `[rbp+disp32]` reference. The picker's safety scan sees rbp disps, so an
# aggregate's second and later words were invisible to it and it could promote one to a register
# while the field write that really sets it went through rcx. That was latent for as long as the
# picker has existed, because those words were referenced at most once — below the `count > 1`
# candidacy threshold. Adding the assignment copy supplies the second reference and trips it, so
# the first attempt at this fix made `b.y` read 11 instead of 22 in axis 4's shape. Proven by
# construction: the same source compiled with `CYRIUS_REGALLOC_PICKER_CAP=0` was correct.
#
# ⚠ AXIS 4 IS THE LOAD-BEARING AXIS and it must keep THREE aggregates live. With only two, the
# picker never reaches the threshold and a build with the exclusion removed still passes.
#
# ⚠ Axis 6 is the CONTROL: a scalar assignment must still work, so the fix cannot pass by turning
# every assignment into a multi-word copy.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL aggregate_copy_all_words: no build/cycc"; exit 1; }
"$CC" < "$R/src/main.cyr" > "$T/cc" 2>/dev/null || { echo "FAIL aggregate_copy_all_words: stage1 build failed"; exit 1; }
chmod +x "$T/cc"

cat > "$T/p.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
struct P2 { x; y; }
struct P4 { a; b; c; d; }
fn main(): i64 {
    var bad = 0;
    # axis 1 — struct assignment, the common case
    var a: P2; a.x = 11; a.y = 22;
    var c: P2; c.x = 0; c.y = 0;
    c = a;
    if (c.x == 11) { if (c.y == 22) { bad = bad + 0; } else { bad = bad + 1; } }
    # axis 2 — 4-slot struct, assignment and declaration
    var f1: P4; f1.a = 7; f1.b = 8; f1.c = 9; f1.d = 10;
    var f2: P4; f2.a = 0; f2.b = 0; f2.c = 0; f2.d = 0;
    f2 = f1;
    if (f2.a == 7) { if (f2.d == 10) { bad = bad + 0; } else { bad = bad + 1; } }
    var f3: P4 = f1;
    if (f3.d == 10) { bad = bad + 0; } else { bad = bad + 1; }
    # axis 3 — vectors, both forms
    var v1: f32v4 = f32v4_make(0x3F800000, 0x40000000, 0x40400000, 0x40800000);
    var v2: f32v4 = f32v4_splat(0);
    v2 = v1;
    if (f32v4_lane0(v2) == 0x3F800000) { if (f32v4_lane3(v2) == 0x40800000) { bad = bad + 0; } else { bad = bad + 1; } }
    var v3: f32v4 = v1;
    if (f32v4_lane3(v3) == 0x40800000) { bad = bad + 0; } else { bad = bad + 1; }
    var d1: f64v2 = f64v2_make(0x3FF0000000000000, 0x4000000000000000);
    var d2: f64v2 = f64v2_splat(0);
    d2 = d1;
    if (f64v2_lo(d2) == 0x3FF0000000000000) { if (f64v2_hi(d2) == 0x4000000000000000) { bad = bad + 0; } else { bad = bad + 1; } }
    # axis 4 — THREE live aggregates: a declaration copy, then an assignment copy. This is the
    # shape that exposed the register-allocator bug; the earlier local must survive.
    var g: P2; g.x = 41; g.y = 42;
    var h: P2 = g;
    var k: P2; k.x = 0; k.y = 0;
    k = g;
    if (h.y == 42) { if (k.y == 42) { bad = bad + 0; } else { bad = bad + 1; } }
    # axis 5 — self-assignment must not corrupt
    var m: P2; m.x = 5; m.y = 6;
    m = m;
    if (m.x == 5) { if (m.y == 6) { bad = bad + 0; } else { bad = bad + 1; } }
    # axis 6 — CONTROL: scalars still assign
    var x = 5; var y = 0; y = x;
    if (y == 5) { bad = bad + 0; } else { bad = bad + 1; }
    syscall(60, bad, 0, 0, 0, 0);
    return 0;
}
EOF
"$T/cc" < "$T/p.cyr" > "$T/p" 2>"$T/e" || { echo "FAIL aggregate_copy_all_words: probe did not compile"; sed -n 1,3p "$T/e"; exit 1; }
# ⚠ The probe exits with a FAILURE COUNT, not a bitmask. An exit code is 8 bits: the first cut of
# this gate summed nine axes to 511, which the shell reported as 255 — the same truncation that
# once scored 256 real failures as a PASS in proj-tcyr. A count cannot overflow into a pass.
chmod +x "$T/p"; "$T/p"; G=$?
if [ "$G" -ne 0 ]; then
  echo "FAIL aggregate_copy_all_words: $G of 9 axes failed."
  echo "  axes: struct-assign, P4-assign, P4-decl, f32v4-assign, f32v4-decl, f64v2-assign,"
  echo "        THREE-live-aggregates (the regalloc axis), self-assign, scalar-control"
  exit 1
fi
echo "PASS aggregate_copy_all_words: struct+vector, assign+decl, 2/4-slot, 3-live-aggregates, self-assign, scalar control"
exit 0
