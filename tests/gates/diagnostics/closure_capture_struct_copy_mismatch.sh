#!/bin/sh
# closure_capture_struct_copy_mismatch.sh — 6.6.13 (M3): the compile-time half of "inside a
# closure, copying a captured struct copies its bytes". tests/tcyr/crossos/closure_capture_struct_copy.tcyr
# runs the copies on every host; this gate pins the TYPE CHECK the copy paths now apply to a capture.
#
# WHY. The field store, struct-literal, assignment and declaration copy paths resolved a source
# name local-then-global, with no rung for a closure capture. A captured struct therefore never
# reached their type checks: copying a captured `Qt` into a `Pt` field, variable or declaration
# compiled clean and stored the capture's ADDRESS (or bound the destination as a pointer into the
# env), where the identical statement on a local is refused by name. With the capture rung in
# place, a capture of a DIFFERENT type takes the same refusal the local form has — and must emit
# no binary.
#
#   axis 1  a captured struct of another type is refused by name in each copy shape: field store
#           `b.v = q`, struct literal `Box { q, 5 }`, assignment `r = q`, declaration
#           `var r: Pt = q` — from an inline capture, a captured by-value parameter and a captured
#           pointer-mode local; and a captured VECTOR into a struct declaration / assignment.
#   axis 2  the same shapes with the RIGHT type still compile and run (the refusal must not
#           over-fire on the capture rung).
#
# Mutations (6.6.13, measured on scratch copies of src/):
#   drop the capture rung in _fsc_name_src      -> axis 1 field-store + literal rows RED (rc 0, or
#                                                  `unexpected '}'` for the literal), and axis 2's
#                                                  ok_field (the address) + ok_literal (no compile)
#   _agc_src_operand without its capture rung   -> axis 1 assignment rows + axis 2 ok_assign RED
#   _try_struct_copy_init without _sci_cap_src  -> axis 1 declaration rows RED (rc 0)
# The 6.6.13-open compiler fails every axis-1 row (each compiled, or failed with `unexpected '}'`
# instead of the by-name refusal) and axis 2's field, literal and assignment rows.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: closure_capture_struct_copy_mismatch: $CC not built"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: closure_capture_struct_copy_mismatch: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
checks=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 - expected $2, got $3"; fails=$((fails + 1)); fi
}
# refused <name> <source> <fragment>
refused() {
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    ( cd "$ROOT" && "$CC" < "$T/$1.cyr" > "$T/$1.out" 2> "$T/$1.err" ) || rc=$?
    check "$1: exits 1" 1 "$rc"
    check "$1: names '$3'" yes "$(grep -qF -- "$3" "$T/$1.err" && echo yes || echo no)"
    check "$1: emits no binary" 0 "$(wc -c < "$T/$1.out" | tr -d ' ')"
}
# runs <name> <source> <exit>
runs() {
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    ( cd "$ROOT" && "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" ) || rc=$?
    check "$1: compiles" 0 "$rc"
    if [ "$rc" -ne 0 ]; then echo "       $(grep '^error' "$T/$1.err" | head -1)"; return 0; fi
    chmod +x "$T/$1.bin" 2>/dev/null
    rc=0; "$T/$1.bin" > /dev/null 2>&1 || rc=$?
    check "$1: exits $3" "$3" "$rc"
}

HDR='include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/fnptr.cyr"\nstruct Pt { x; y; }\nstruct Qt { a; b; }\nstruct Box { v: Pt; n; }\n'
INL='fn f(): i64 {\n    var q: Qt = Qt { 3, 4 };\n    var g = || {\n'
PRM='fn f(q: Qt): i64 {\n    var g = || {\n'
PTR='fn f(): i64 {\n    var q: Qt = alloc(16);\n    q.a = 3;\n    q.b = 4;\n    var g = || {\n'
END='    };\n    return callptr(g);\n}\n'
MAIN_F='alloc_init();\nsyscall(60, f());\n'
MAIN_P='alloc_init();\nvar qq = Qt { 3, 4 };\nsyscall(60, f(qq));\n'
FLD="cannot copy 'q' into a struct field of a different struct type: 'v'"
VAR="cannot copy 'q' into a variable of a different struct/vector type: 'r'"

echo "axis 1 - a captured struct of another type is refused by name:"
refused inl_field   "${HDR}${INL}        var b: Box;\n        b.v = q;\n        return b.v.x;\n${END}${MAIN_F}" "$FLD"
refused inl_literal "${HDR}${INL}        var b = Box { q, 5 };\n        return b.n;\n${END}${MAIN_F}" "$FLD"
refused inl_assign  "${HDR}${INL}        var r: Pt;\n        r = q;\n        return r.x;\n${END}${MAIN_F}" "$VAR"
refused inl_decl    "${HDR}${INL}        var r: Pt = q;\n        return r.x;\n${END}${MAIN_F}" "$VAR"
refused prm_field   "${HDR}${PRM}        var b: Box;\n        b.v = q;\n        return b.v.x;\n${END}${MAIN_P}" "$FLD"
refused prm_assign  "${HDR}${PRM}        var r: Pt;\n        r = q;\n        return r.x;\n${END}${MAIN_P}" "$VAR"
refused prm_decl    "${HDR}${PRM}        var r: Pt = q;\n        return r.x;\n${END}${MAIN_P}" "$VAR"
refused ptr_field   "${HDR}${PTR}        var b: Box;\n        b.v = q;\n        return b.v.x;\n${END}${MAIN_F}" "$FLD"
refused ptr_decl    "${HDR}${PTR}        var r: Pt = q;\n        return r.x;\n${END}${MAIN_F}" "$VAR"
VEC='fn f(): i64 {\n    var q: f32v4;\n    store32(&q, 1);\n    var g = || {\n'
refused vec_decl    "${HDR}${VEC}        var r: Pt = q;\n        return r.x;\n${END}${MAIN_F}" "$VAR"
refused vec_assign  "${HDR}${VEC}        var r: Pt;\n        r = q;\n        return r.x;\n${END}${MAIN_F}" "$VAR"

echo "axis 2 - the same shapes with the right type compile and copy:"
OK='fn f(): i64 {\n    var q: Pt = Pt { 3, 4 };\n    var g = || {\n'
runs ok_field   "${HDR}${OK}        var b: Box;\n        b.v = q;\n        return b.v.x * 10 + b.v.y;\n${END}${MAIN_F}" 34
runs ok_literal "${HDR}${OK}        var b = Box { q, 5 };\n        return b.v.x * 10 + b.v.y;\n${END}${MAIN_F}" 34
runs ok_assign  "${HDR}${OK}        var r: Pt;\n        r = q;\n        return r.x * 10 + r.y;\n${END}${MAIN_F}" 34
runs ok_decl    "${HDR}${OK}        var r: Pt = q;\n        r.x = r.x + 1;\n        return r.x * 10 + r.y;\n${END}${MAIN_F}" 44

# Floor: 11 refusals x 3 checks + 4 runs x 2 checks. A gate that ran fewer checks is broken, not green.
if [ "$fails" -ne 0 ]; then echo "FAIL: closure_capture_struct_copy_mismatch: $fails check(s) failed"; exit 1; fi
if [ "$checks" -lt 41 ]; then echo "FAIL: closure_capture_struct_copy_mismatch: only $checks checks ran (floor 41)"; exit 1; fi
echo "PASS: closure_capture_struct_copy_mismatch ($checks checks)"
exit 0
