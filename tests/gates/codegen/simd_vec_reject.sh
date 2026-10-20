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
#
#  1c (6.7.16). The message is the ONLY error: after it the receiver is no struct (sid 0), and nothing reads the
#     vector band as a struct id. Through 6.7.15 the field arms went on with sid `0 - sltype` (2121): `v.m()`
#     built the method name from whatever struct 2120's table entry held and called it — "warning: undefined
#     function 'fn.m'" ('enum.m' for an f64v2) and "error: refusing to emit binary with 1 reachable undefined
#     function(s)" after the message.
#     Mutation: the tree before (404f482da) -> RED 1c on each of the three method rows (measured one at a time:
#     the gate stops at its first failure); the field rows were one error already.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: simd_vec_reject: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 77; }
T=$(mktemp) && [ -f "$T" ] || { echo "FAIL: simd_vec_reject: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
E=$(mktemp) && [ -f "$E" ] || { echo "FAIL: simd_vec_reject: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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

# --- Guard 1c (6.7.16): the message is the only error, in every field / method position ---
for body in 'return v.m();' 'v.m();' 'return v.m(1, 2) + 1;' 'return v.someField.b;' 'v.someField = 1;' 'v.a.b += 2;'; do
    printf 'include "lib/simd.cyr"\nfn main(): i64 {\n    var v: f32v4 = f32v4_splat(0x3F800000);\n    %s\n    return 0;\n}\nvar ec = main();\n' "$body" > "$T"
    rc=0; "$CC" < "$T" > /dev/null 2>"$E" || rc=$?
    nerr=$(grep -c '^error' "$E" || true)
    if [ "$rc" -eq 0 ] || [ "$nerr" -ne 1 ] || ! grep -q '^error.*SIMD vector has no named fields' "$E" || grep -q 'undefined function' "$E"; then
        echo "FAIL: f32v4 \`$body\` — want exactly one error, the SIMD one (rc=$rc, $nerr error lines):"; cat "$E"; exit 1
    fi
done

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

# --- Guard 3 (v6.4.15 SIMD_TC): mismatch rejected in TAIL-CALL position too ---
# `return simdfn(mismatched)` bypasses PARSE_FNCALL via PARSE_RETURN's tail path,
# which used to skip the SIMD-arg type-check. It must now reject the same mismatch.
cat > "$T" <<'EOF'
include "lib/simd.cyr"
fn wrong(a: f32v4, b: f32v4): i64 { return f32v4_lane0(a); }
fn main(): i64 {
    var p: f64v2 = f64v2_make(100, 200);
    return wrong(p, p);
}
var ec = main();
EOF
if "$CC" < "$T" > /dev/null 2>"$E"; then
    echo "FAIL: f64v2 arg to f32v4 param in TAIL position compiled — must reject (SIMD_TC)"; exit 1
fi
grep -q 'callee expects f32v4' "$E" || { echo "FAIL: tail-form mismatch gave wrong error:"; cat "$E"; exit 1; }

# --- Positive control: matching f32v4 tail call compiles clean ---
cat > "$T" <<'EOF'
include "lib/simd.cyr"
fn getlane0(v: f32v4): i64 { return f32v4_lane0(v); }
fn caller(a: f32v4): i64 { return getlane0(a); }
fn main(): i64 {
    var x: f32v4 = f32v4_splat(1);
    return caller(x);
}
var ec = main();
EOF
"$CC" < "$T" > /dev/null 2>&1 || { echo "FAIL: matching f32v4 tail call failed to compile (over-rejection)"; exit 1; }

echo "PASS: f32v4 .field hard-errors (heap-independent; the one error in every field / method position) + mismatched SIMD arg rejected in call + tail position (v6.4.4/.15)"
