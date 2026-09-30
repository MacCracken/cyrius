#!/bin/sh
# tests/gates/frontend/sizeof_whole_name.sh — 6.6.11
#
# `sizeof(T)` and the `mulh64` intrinsic match WHOLE names.
#
# AXIS 1 — both sizeof sites (the expression in PARSE_FACTOR and #assert's constant
#   evaluator) sized a scalar by the PREFIX-only `_scalar_name_width`: sizeof(i16v8) was 2,
#   sizeof(i8zz) 1, sizeof(i32q) 4, and `#assert sizeof(i16v8) == 2` PASSED. 6.6.10 fixed the
#   same prefix test for struct/union/Vec FIELDS (`_field_scalar_width`) only. A non-scalar
#   name now falls through to the struct lookup and is refused by name, the same answer
#   sizeof(f64v2) already gave.
# AXIS 2 — ANTI-VACUOUS: sizeof(i8/i16/i32/i64) and a struct still size, in an expression,
#   in a fn, at top level and under #assert.
# AXIS 3 — PARSE_FACTOR also matched `mulh64` by a 6-byte prefix, so a user fn named
#   `mulh64x(a, b)` compiled as the intrinsic (the high word of a*b, 0 for small args):
#   silent wrong code. It must call the fn, in an expression and in a tail `return`.
#   (`return mulh64(..)` / `return sizeof(..)` themselves are pinned on every backend by
#   tests/tcyr/crossos/return_intrinsic_values.tcyr.)
#
# MUTATION PROOF (6.6.11):
#   * parse_expr.cyr sizeof: `_field_scalar_width` back to `_scalar_name_width`
#     -> the expression rows of axis 1 RED (rc 0, value 2/1/4).
#   * parse.cyr _EVAL_CONST_ATOM: the same swap -> the #assert rows of axis 1 RED.
#   * parse_expr.cyr: the mulh64 arm back to the 6-byte prefix test -> axis 3 RED (0, want 7).
#
# Exit 77 = could not run (no compiler); never 0 for that.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: sizeof_whole_name — $CC not built"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "SKIP: sizeof_whole_name: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 77; }
trap 'rm -rf "$T"' EXIT
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
# refused <name> <printf-fmt> <want-stderr-substring>
refused() {
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    "$CC" < "$T/$1.cyr" > "$T/$1.out" 2> "$T/$1.err" || rc=$?
    check "$1: exits 1" 1 "$rc"
    check "$1: names '$3'" yes "$(grep -qF -- "$3" "$T/$1.err" && echo yes || echo no)"
    check "$1: emits no binary" 0 "$(wc -c < "$T/$1.out" | tr -d ' ')"
}
# runs <name> <printf-fmt> <want-exit>
runs() {
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    "$CC" < "$T/$1.cyr" > "$T/$1" 2> "$T/$1.err" || rc=$?
    check "$1: compiles" 0 "$rc"
    chmod +x "$T/$1"
    rc=0; "$T/$1" || rc=$?
    check "$1: exits $3" "$3" "$rc"
}

echo "axis 1 — sizeof of a name that only STARTS like a scalar is refused:"
refused sz_i16v8     'syscall(60, sizeof(i16v8));\n'                              'sizeof: unknown type'
refused sz_i8zz      'syscall(60, sizeof(i8zz));\n'                               'sizeof: unknown type'
refused sz_i32q      'syscall(60, sizeof(i32q));\n'                               'sizeof: unknown type'
refused sz_in_fn     'fn f(): i64 { var k = sizeof(i16v8); return k; }\nvar r = f();\n' 'sizeof: unknown type'
refused sz_global    'var G = sizeof(i16zz);\nsyscall(60, G);\n'                  'sizeof: unknown type'
refused as_i16v8     '#assert sizeof(i16v8) == 2, "x";\nvar r = 0;\n'             '#assert: unknown type in sizeof'
refused as_i8zz      '#assert sizeof(i8zz) == 1;\nvar r = 0;\n'                   '#assert: unknown type in sizeof'

echo "axis 2 — ANTI-VACUOUS: the whole scalar names and a struct still size:"
runs sz_scalars 'syscall(60, sizeof(i8) + sizeof(i16) * 10 + sizeof(i32) * 50);\n' 221
runs sz_fn      'struct P3 { a; b; c; }\nfn f(): i64 { var k = sizeof(i64) + sizeof(P3); return k; }\nsyscall(60, f());\n' 32
runs sz_assert  '#assert sizeof(i8) == 1;\n#assert sizeof(i16) == 2;\n#assert sizeof(i32) == 4;\n#assert sizeof(i64) == 8, "i64";\nsyscall(60, 5);\n' 5

echo "axis 3 — a user fn named mulh64x is a CALL, not the intrinsic:"
runs mh_expr 'fn mulh64x(a, b): i64 { return a + b; }\nsyscall(60, mulh64x(3, 4));\n' 7
runs mh_tail 'fn mulh64x(a, b): i64 { return a + b; }\nfn g(): i64 { return mulh64x(3, 4); }\nsyscall(60, g());\n' 7
# ANTI-VACUOUS: the intrinsic itself: 2^63 * 16 = 2^67, high word 8
runs mh_intr 'syscall(60, mulh64(0x8000000000000000, 16));\n' 8

echo ""
if [ "$fails" = 0 ]; then
    echo "PASS: sizeof_whole_name — sizeof and mulh64 match whole names"
    exit 0
fi
echo "FAIL: sizeof_whole_name — $fails assertion(s) failed"
exit 1
