#!/bin/sh
# typed_array_elem_refusals.sh — 6.6.13 (M2): the compile-time half of "a typed array is sized
# by its element". tests/tcyr/crossos/typed_array_elem_size.tcyr proves the SIZES on every
# backend; this gate pins what the sizing change refuses and what it must keep accepting.
#
# WHY. `var a: T[N]` was sized from the integer subscript descriptor, so every element it does
# not describe was sized like a bare `var a[N]` (8 bytes for a local `f64[4]` or `Pt[2]`, 16 for a
# top-level `Pt[2]`), and the declaration block's PREFIX ladder read `i8v16` as an i8 — sized as
# one AND given that integer descriptor, so `g[1]` on a vector global compiled. The fix sizes by
# element and keeps the subscript integer-only. That leaves three compile-time obligations:
#
#   axis 1  a subscript on a NON-integer element is refused, local and global, in both global
#           zones — including the decl-zone vector global that used to compile. With the
#           subscript refused, its stride cannot disagree with the new element size (f32 is
#           now 4 bytes: a stride-8 subscript would be the very overrun this fixes).
#   axis 2  an element type that names nothing is refused BY NAME: an unknown name (local, both
#           global zones), a struct declared BELOW a declaration-zone array (it was silently 8
#           bytes per element), and every bad array of a file is reported, not only the first.
#   axis 3  N * sizeof(T) must not wrap (a wrapped product is the same silent under-size): over
#           2 GiB is refused, typed and bare.
#   axis 4  what must KEEP compiling, and run: bool, an enum declared above or below, cstring,
#           and a generic fn's own `var a: T[N]` (base and instances, default build AND
#           CYRIUS_MONOMORPH=0, including inside a closure) — the generic shape compiled before
#           6.6.13 and the first design would have refused it. `--syntax-only` (what lint runs)
#           resolves nothing, so an unknown element is not an error there.
#
# Mutations (6.6.13, built from scratch copies of src/, measured):
#   _arr_name_ebytes returns 8 before its refusal  -> axis 2 RED, all six rows (rc 0)
#   drop `if (eb != ew)` in PARSE_GVAR_ARR          -> axis 1's four decl-zone integer-vector rows
#                                                     RED (rc 0: the 6.6.12 shape compiles again)
#   drop the _arr_fn_tparam arm                     -> axis 4's two CYRIUS_MONOMORPH=0 rows RED
#                                                     (the default build binds T, so only the
#                                                     unbound mode reaches the token reader)
#   drop PARSE_ARRAY's _arr_size_ok call            -> axis 3's local and post-statement rows RED
# The 6.6.13-open compiler fails 45 checks here (every axis-2 and axis-3 row, the decl-zone
# integer-vector subscripts, and the generic sizes).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: typed_array_elem_refusals: $CC not built"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: typed_array_elem_refusals: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 - expected $2, got $3"; fails=$((fails + 1)); fi
}
# refused <name> <source> <fragment> [<second fragment>]
refused() {
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    ( cd "$ROOT" && "$CC" < "$T/$1.cyr" > "$T/$1.out" 2> "$T/$1.err" ) || rc=$?
    check "$1: exits 1" 1 "$rc"
    check "$1: names '$3'" yes "$(grep -qF -- "$3" "$T/$1.err" && echo yes || echo no)"
    if [ $# -ge 4 ]; then
        check "$1: names '$4'" yes "$(grep -qF -- "$4" "$T/$1.err" && echo yes || echo no)"
    fi
    check "$1: emits no binary" 0 "$(wc -c < "$T/$1.out" | tr -d ' ')"
}
# runs <name> <source> <exit> [<env assignment>]
runs() {
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    if [ $# -ge 4 ]; then ( cd "$ROOT" && env "$4" "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" ) || rc=$?
    else ( cd "$ROOT" && "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" ) || rc=$?; fi
    check "$1: compiles" 0 "$rc"
    if [ "$rc" -ne 0 ]; then echo "       $(grep '^error' "$T/$1.err" | head -1)"; return 0; fi
    chmod +x "$T/$1.bin" 2>/dev/null
    rc=0; "$T/$1.bin" > /dev/null 2>&1 || rc=$?
    check "$1: exits $3" "$3" "$rc"
}

SUB="cannot subscript 'a'"
NOTINT="an f64, f32, bool or struct element is not supported"
P3='struct P3 { x; y; z; }\n'
PT='struct Pt { x; y; }\n'

echo "axis 1 - a subscript on a non-integer element is refused (no stride to disagree with the size):"
refused dz_i8v16_read  'var a: i8v16[4];\nfn f(): i64 { return a[1]; }\nsyscall(60, f());\n' "$SUB" "$NOTINT"
refused dz_u32v4_write 'var a: u32v4[2];\nfn f(): i64 { a[1] = 5; return 0; }\nsyscall(60, f());\n' "$SUB"
refused dz_i16v8_read  'var a: i16v8[2];\nfn f(): i64 { return a[0]; }\nsyscall(60, f());\n' "$SUB"
refused dz_i64v2_read  'var a: i64v2[2];\nfn f(): i64 { return a[0]; }\nsyscall(60, f());\n' "$SUB"
refused dz_f64v2_read  'var a: f64v2[2];\nfn f(): i64 { return a[0]; }\nsyscall(60, f());\n' "$SUB"
refused dz_f32_read    'var a: f32[4];\nfn f(): i64 { return a[1]; }\nsyscall(60, f());\n' "$SUB"
refused dz_struct_read "${P3}var a: P3[2];\nfn f(): i64 { return a[1]; }\nsyscall(60, f());\n" "$SUB"
refused pp_f32_write   'syscall(0, 0, 0, 0);\nvar a: f32[4];\na[1] = 7;\nsyscall(60, 0);\n' "$SUB"
refused pp_vec_read    'syscall(0, 0, 0, 0);\nvar a: i8v16[2];\nsyscall(60, a[1]);\n' "$SUB"
refused loc_f64_read   'fn f(): i64 {\n    var a: f64[4];\n    return a[1];\n}\nsyscall(60, f());\n' "$SUB" "$NOTINT"
refused loc_f32_write  'fn f(): i64 {\n    var a: f32[4];\n    a[3] = 1;\n    return 0;\n}\nsyscall(60, f());\n' "$SUB"
refused loc_struct     "${PT}fn f(): i64 {\n    var a: Pt[2];\n    return a[1];\n}\nsyscall(60, f());\n" "$SUB" "$NOTINT"
refused loc_ptr        'fn f(): i64 {\n    var a: *i64[4];\n    return a[1];\n}\nsyscall(60, f());\n' "$SUB"
refused loc_bool       'fn f(): i64 {\n    var a: bool[4];\n    return a[1];\n}\nsyscall(60, f());\n' "$SUB"
refused loc_vec        'fn f(): i64 {\n    var a: f32v8[2];\n    return a[1];\n}\nsyscall(60, f());\n' "$SUB"
refused loc_generic    "${PT}struct Box<T> { v: T; n; }\nfn f(): i64 {\n    var a: Box<Pt>[2];\n    return a[1];\n}\nsyscall(60, f());\n" "$SUB"

echo "axis 2 - an element type that names nothing is refused by name:"
refused dz_forward_struct "var g: P3[2];\nvar s = 1;\n${P3}syscall(60, s);\n" \
    "array element type 'P3' is declared after the array"
refused dz_unknown     'var g: Nope[3];\nsyscall(60, 0);\n' "unknown array element type 'Nope'"
refused pp_unknown     'syscall(0, 0, 0, 0);\nvar g: Nope[3];\nsyscall(60, 0);\n' "unknown array element type 'Nope'"
refused loc_unknown    'fn f(): i64 {\n    var a: Nope[3];\n    return 0;\n}\nsyscall(60, f());\n' \
    "error:<source>:2:12: unknown array element type 'Nope'"
refused loc_unknown_note 'fn f(): i64 {\n    var a: Nope[3];\n    return 0;\n}\nsyscall(60, f());\n' \
    "note: an element is i8..i64, u8..u64, u128, f32, f64, bool, cstring, an enum"
refused two_bad        'var g: Nope1[3];\nfn f(): i64 {\n    var a: Nope2[3];\n    return 0;\n}\nsyscall(60, f());\n' \
    "unknown array element type 'Nope1'" "unknown array element type 'Nope2'"

echo "axis 3 - N * sizeof(T) must not wrap:"
refused big_local_struct "${P3}fn f(): i64 {\n    var a: P3[0x7FFFFFFF];\n    return 0;\n}\nsyscall(60, f());\n" \
    "array too large: N * sizeof(T) must stay under 2 GiB"
refused big_dz_typed   'var g: i64[0x2000000000000001];\nsyscall(60, 0);\n' "array too large"
refused big_dz_bare    'var g[0x2000000000000001];\nsyscall(60, 0);\n' "array too large"
refused big_pp_vec     'syscall(0, 0, 0, 0);\nvar g: f64v4[0x4000000];\nsyscall(60, 0);\n' "array too large"
runs    big_ok_local   'fn f(): i64 {\n    var a: i64[100000];\n    a[99999] = 7;\n    return a[99999];\n}\nsyscall(60, f());\n' 7

echo "axis 4 - what keeps compiling, and runs:"
runs keep_bool  'fn f(): i64 {\n    var s = 9;\n    var a: bool[4];\n    store64(&a + 24, 1);\n    return s;\n}\nsyscall(60, f());\n' 9
runs keep_enum  'enum Color { RED = 0; BLUE = 1; }\nvar g: Color[3];\nvar s = 5;\nfn f(): i64 {\n    var a: Color[2];\n    return 0;\n}\nstore64(&g + 16, 1);\nsyscall(60, s + f());\n' 5
runs keep_enum_below 'var g: Late[3];\nvar s = 6;\nenum Late { A = 0; B = 1; }\nstore64(&g + 16, 1);\nsyscall(60, s);\n' 6
runs keep_cstring 'fn f(): i64 {\n    var s = 4;\n    var a: cstring[2];\n    store64(&a + 8, "x");\n    return s;\n}\nsyscall(60, f());\n' 4
# The critic's shape (6.6.13 planning): compiled at 6.6.12 under-sized; must compile and size.
GEN="${P3}fn sz<T>(p: T): i64 {\n    var x = 7;\n    var px = &x;\n    var a: T[2];\n    return px - &a;\n}\n"
runs gen_instance "${GEN}syscall(60, sz<P3>(0));\n" 56
runs gen_scalar   "${GEN}syscall(60, sz<i64>(0));\n" 24
runs gen_mono0    "${GEN}syscall(60, sz(0));\n" 24 CYRIUS_MONOMORPH=0
GEN2='fn two<A, B>(p: A, q: B): i64 {\n    var x = 7;\n    var px = &x;\n    var a: B[3];\n    var c = || {\n        var d: A[2];\n        return 0;\n    };\n    return px - &a;\n}\n'
runs gen_closure       "${GEN2}syscall(60, two(1, 2));\n" 32
runs gen_closure_mono0 "${GEN2}syscall(60, two(1, 2));\n" 32 CYRIUS_MONOMORPH=0
printf '%b' 'fn f(): i64 {\n    var a: Nope[3];\n    return 0;\n}\nsyscall(60, f());\n' > "$T/so.cyr"
rc=0; ( cd "$ROOT" && "$CC" --syntax-only < "$T/so.cyr" > "$T/so.out" 2> "$T/so.err" ) || rc=$?
check "syntax_only_unknown: --syntax-only does not resolve the element (exits 0)" 0 "$rc"
check "syntax_only_unknown: no element diagnostic" no "$(grep -qF "array element type" "$T/so.err" && echo yes || echo no)"

if [ "$fails" -ne 0 ]; then echo "FAIL: typed_array_elem_refusals: $fails check(s) failed"; exit 1; fi
echo "PASS: typed_array_elem_refusals"
exit 0
