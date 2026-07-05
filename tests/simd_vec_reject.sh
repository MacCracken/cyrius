#!/bin/sh
# v6.4.4 (SIMD Phase 1) regression: the f32v4 descriptor sentinel (-2121) must
# NOT be misread as a struct id. Two guards, both surfaced by adversarial review:
#
#  1. `v.field` on a SIMD-vector local must hard-error ("no named fields"), NOT
#     let `0 - sltype` (2121) escape the 1024-entry struct tables into an OOB
#     read in BUILD_METHOD_NAME / FINDFIELD. The error must be heap-INDEPENDENT
#     (identical with N structs prepended) — proving no out-of-bounds struct
#     name/field-count read is happening.
#
#  2. A value-form SIMD arg whose type mismatches the callee's SIMD param (e.g.
#     f64v2 where f32v4 is expected) must be REJECTED when the ABI engages
#     (a SIMD-returning callee, mask != 0), not silently run addps over f64
#     bit patterns. f32v4 (mask code 3) is distinguished from f64v2 (1).
#
# Value-form SIMD params are non-PE (SysV XMM ABI), so the mismatch check is
# gated behind a Linux/macOS host; the field guard is arch-independent.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
T=$(mktemp); E=$(mktemp)
trap 'rm -f "$T" "$E"' EXIT

# --- Guard 1: f32v4 .field hard-errors cleanly ---
cat > "$T" <<'EOF'
include "lib/simd.cyr"
fn main(): i64 {
    var v: f32v4 = f32v4_splat(0x3F800000);
    return v.someField;
}
var ec = main();
EOF
if "$CC" < "$T" > /dev/null 2>"$E"; then
    echo "FAIL: f32v4 .field compiled — must hard-error (OOB struct-table escape)"; exit 1
fi
grep -q 'SIMD vector has no named fields' "$E" || { echo "FAIL: f32v4 .field gave wrong error:"; cat "$E"; exit 1; }

# --- Guard 1b: heap-independence — 60 structs prepended, SAME error ---
{ i=0; while [ "$i" -lt 60 ]; do echo "struct Z$i { a: i64; }"; i=$((i + 1)); done; cat "$T"; } > "$T.2"
if "$CC" < "$T.2" > /dev/null 2>"$E"; then
    rm -f "$T.2"; echo "FAIL: f32v4 .field (with structs) compiled — must hard-error"; exit 1
fi
grep -q 'SIMD vector has no named fields' "$E" || { rm -f "$T.2"; echo "FAIL: heap-dependent error (OOB read):"; cat "$E"; exit 1; }
rm -f "$T.2"

# --- Guard 2: mismatched SIMD arg rejected when the ABI engages ---
cat > "$T" <<'EOF'
include "lib/simd.cyr"
fn combine(a: f32v4, b: f32v4): f32v4 { return f32v4_add(a, b); }
fn main(): i64 {
    var x: f64v2 = f64v2_make(1, 2);
    var y: f64v2 = f64v2_make(3, 4);
    var r: f32v4 = combine(x, y);
    return f32v4_lane0(r);
}
var ec = main();
EOF
if "$CC" < "$T" > /dev/null 2>"$E"; then
    echo "FAIL: f64v2 args to f32v4 params compiled — must reject (type confusion)"; exit 1
fi
grep -q 'callee expects f32v4' "$E" || { echo "FAIL: mismatch gave wrong error:"; cat "$E"; exit 1; }

# --- Positive control: matching f32v4 args compile clean ---
cat > "$T" <<'EOF'
include "lib/simd.cyr"
fn combine(a: f32v4, b: f32v4): f32v4 { return f32v4_add(a, b); }
fn main(): i64 {
    var x: f32v4 = f32v4_splat(1);
    var y: f32v4 = f32v4_splat(2);
    var r: f32v4 = combine(x, y);
    return f32v4_lane0(r);
}
var ec = main();
EOF
"$CC" < "$T" > /dev/null 2>&1 || { echo "FAIL: matching f32v4 combine() failed to compile"; exit 1; }

echo "PASS: f32v4 .field hard-errors (heap-independent) + mismatched SIMD arg rejected (v6.4.4)"
