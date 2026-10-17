#!/bin/sh
# tests/gates/frontend/array_subscript_forms.sh — 6.6.12
#
# `a[i]`, `a[i] = v` and `a[i] OP= v` on an element-typed array `var a: T[N]` (T = i8..i64,
# u8..u64), local or global. Before 6.6.12 the language had no subscript at all — `return a[1];`
# was `expected ';', got '['` and `a[i] = 5;` was `expected '=', got '['` — so the only spelling
# was `store64(&a + i * 8, v)`. The runtime rows (every width, sign extension, store truncation,
# canaries, compound operators, the for step, closures) are tests/tcyr/crossos/
# typed_array_subscript.tcyr, which runs on every cross-OS host; this gate holds what a .tcyr
# cannot:
#
# AXIS 1 — the REFUSALS, each by name at file:line:col, exit 1, no binary. A bare `var a[N]`
#   and a `stack var` buffer state no element width (N bytes in a fn, N slots at top level), so
#   their subscript is refused rather than guessed; a scalar is no array; a u128 element does not
#   fit one register; a struct element array is refused NAMING that shape (it is a `var a: T[N]`,
#   so the bare/scalar explanation alone would misdescribe it). An unknown name is `undefined
#   variable`. 6.7.8 (C2-4a): a `*T` and an f64 / f32 / bool element array subscript (axis 2);
#   tests/gates/frontend/pointer_subscript_checked.sh holds their rows and the pointer refusals.
# AXIS 2 — ANTI-VACUOUS: the typed spelling of every refused shape compiles and runs.
# AXIS 3 — the runtime file under CYRIUS_IR=3 (the IR passes rewrite around unrecorded raw
#   bytes: a signed element load read wrong there until it recorded itself) and by default.
# AXIS 4 — `--syntax-only` (what `cyrius lint` runs) accepts every valid form.
# AXIS 5 — a slice local keeps its own bounds-checked `s[i]` (lib/slice.cyr), untouched.
#
# MUTATION PROOF (6.6.12):
#   * drop `if (_arr_sub_read(S, noff) == 1) { return 0; }` from _PARSE_FACTOR_IMPL
#     -> axes 2-4 RED (`expected ';', got '['`).
#   * drop `if (_arr_sub_stmt(S, noff) == 1) { return 0; }` from _PARSE_STMT_IMPL -> axes 2-4 RED.
#   * make `_arr_desc` answer 8 for `ew <= 0` (a bare array read as i64 slots)
#     -> axis 1's four bare rows RED (they compile).
#   * drop `if (w < 0) { _IR_REC0(S, IR_RAW_EMIT); }` in _arr_sub_load -> axis 3's IR=3 row RED.
#     (Since 6.7.14 the record is x86 EFIELD_LOAD_W's `width < 0` arm; dropping it -> axis 3 RED, measured.)
#   * drop " - its element is a struct, pointer, enum, string or vector" from the typed-array
#     refusal in _sub_refuse -> axis 1's two struct naming rows RED (6.7.8, measured).
#   * 6.7.8 (C2-4a): `_sub_bare` answering 0 -> the five bare rows RED (the untyped-name text); a
#     non-pointer local taken as a `*i64` -> the bare / scalar / stack rows compile; the C2-3b
#     compiler -> RED the eight re-derived refusal texts and the four axis-2 rows a 6.7.8 subscript
#     opened (pointer_local, f64_global, f32_local, bool_global).
#   * drop the slice guard in _arr_sub_read -> axis 5 RED (the slice is refused as not an array).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: array_subscript_forms — $CC not built"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: array_subscript_forms: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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
    ( cd "$T" && "$CC" < "$T/$1.cyr" > "$T/$1.out" 2> "$T/$1.err" ) || rc=$?
    check "$1: exits 1" 1 "$rc"
    check "$1: names '$3'" yes "$(grep -qF -- "$3" "$T/$1.err" && echo yes || echo no)"
    check "$1: emits no binary" 0 "$(wc -c < "$T/$1.out" | tr -d ' ')"
}
# runs <name> <printf-fmt> <want-exit>   (compiled from $ROOT so lib/ includes resolve)
runs() {
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    ( cd "$ROOT" && "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" ) || rc=$?
    check "$1: compiles" 0 "$rc"
    chmod +x "$T/$1.bin" 2>/dev/null
    rc=0; "$T/$1.bin" > /dev/null 2>&1 || rc=$?
    check "$1: exits $3" "$3" "$rc"
}

# 6.7.8 (C2-4a): the texts are re-derived — a bare array, a scalar, a struct element each by name.
BARE="cannot subscript 'a': a bare \`var a[N]\` states no element width"
NOTARR="cannot subscript 'a': it is not a typed array, a *T or a slice local"
# A struct element array IS `var a: T[N]`, so the refusal must name that shape rather than
# explain it away as a bare array or a scalar (6.6.12 B20 review).
NOTINT="its element is a struct, pointer, enum, string or vector"
echo "axis 1 — the refusals, by name:"
refused bare_local_write 'fn f(): i64 {\n    var a[16];\n    a[1] = 5;\n    return 0;\n}\nsyscall(60, f());\n' \
    "error:<source>:3:6: $BARE"
refused bare_local_read  'fn f(): i64 {\n    var a[16];\n    return a[1];\n}\nsyscall(60, f());\n' \
    "error:<source>:3:13: $BARE"
refused bare_global_read 'var a[4];\nfn f(): i64 { return a[1]; }\nsyscall(60, f());\n' \
    "error:<source>:2:23: $BARE"
refused bare_toplevel_write 'var a[4];\nsyscall(60, 0);\na[2] = 7;\n' \
    "error:<source>:3:2: $BARE"
refused scalar_local     'fn f(): i64 {\n    var a = 5;\n    return a[0];\n}\nsyscall(60, f());\n' \
    "error:<source>:3:13: $NOTARR"
refused stack_var        'fn f(): i64 {\n    stack var a[16];\n    a[0] = 1;\n    return 0;\n}\nsyscall(60, f());\n' \
    "error:<source>:3:6: $BARE"
refused u128_element     'fn f(): i64 {\n    var a: u128[2];\n    return a[0];\n}\nsyscall(60, f());\n' \
    "error:<source>:3:13: cannot subscript 'a': a u128 element does not fit one register"
refused struct_local     'struct Pt { x; y; }\nfn f(): i64 {\n    var a: Pt[4];\n    return a[1];\n}\nsyscall(60, f());\n' \
    "$NOTINT"
refused struct_global    'struct Pt { x; y; }\nvar a: Pt[4];\nfn f(): i64 { return a[1]; }\nsyscall(60, f());\n' \
    "$NOTINT"
refused undefined_name   'fn f(): i64 { return nope[1]; }\nsyscall(60, f());\n' \
    "undefined variable 'nope'"

echo "axis 2 — anti-vacuous: the typed spelling of every refused shape runs:"
runs typed_local_write 'fn f(): i64 {\n    var a: u8[16];\n    a[1] = 5;\n    return a[1];\n}\nsyscall(60, f());\n' 5
runs typed_global_read 'var a: i16[4];\nfn f(): i64 { a[1] = 0 - 3; return a[1] + 10; }\nsyscall(60, f());\n' 7
runs typed_toplevel_write 'var a: i32[4];\nsyscall(0, 0, 0, 0);\na[2] = 7;\na[2] *= 6;\nsyscall(60, a[2]);\n' 42
runs typed_i64_local 'fn f(): i64 {\n    var a: i64[4];\n    var i = 3;\n    a[i] = 40;\n    a[i] += 2;\n    return a[3];\n}\nsyscall(60, f());\n' 42
# 6.7.8 (C2-4a): refused until 6.7.8, now subscripted — a `*T` local and f64 / f32 / bool arrays.
runs pointer_local 'var g: i64[2];\nfn f(): i64 {\n    g[0] = 5;\n    var a: *i64 = &g;\n    return a[0];\n}\nsyscall(60, f());\n' 5
runs f64_global 'var a: f64[4];\nfn f(): i64 { a[1] = 1.5; a[1] *= 2.0; if (a[1] == 3.0) { return 7; } return 1; }\nsyscall(60, f());\n' 7
runs f32_local 'fn f(): i64 {\n    var a: f32[4];\n    a[0] = 2.5;\n    a[1] = 0.0;\n    return (load32(&a) >> 24) + load32(&a + 4);\n}\nsyscall(60, f());\n' 64
runs bool_global 'var a: bool[4];\nfn f(): i64 { a[1] = true; if (a[1]) { return 3; } return 0; }\nsyscall(60, f());\n' 3

echo "axis 3 — the runtime file by default and under CYRIUS_IR=3:"
TC="$ROOT/tests/tcyr/crossos/typed_array_subscript.tcyr"
[ -f "$TC" ] || { echo "FAIL: array_subscript_forms — $TC missing"; exit 1; }
for mode in default 3; do
    rc=0
    if [ "$mode" = default ]; then ( cd "$ROOT" && "$CC" < "$TC" > "$T/tc_$mode" 2> "$T/tc_$mode.err" ) || rc=$?
    else ( cd "$ROOT" && CYRIUS_IR=$mode "$CC" < "$TC" > "$T/tc_$mode" 2> "$T/tc_$mode.err" ) || rc=$?; fi
    check "typed_array_subscript.tcyr ($mode): compiles" 0 "$rc"
    chmod +x "$T/tc_$mode" 2>/dev/null
    rc=0; "$T/tc_$mode" > "$T/tc_$mode.out" 2>&1 || rc=$?
    check "typed_array_subscript.tcyr ($mode): exits 0" 0 "$rc"
    check "typed_array_subscript.tcyr ($mode): no FAIL row" 0 "$(grep -c 'FAIL' "$T/tc_$mode.out")"
    check "typed_array_subscript.tcyr ($mode): ran its rows" yes "$(grep -qE '^[1-9][0-9]* passed, 0 failed' "$T/tc_$mode.out" && echo yes || echo no)"
done

echo "axis 4 — --syntax-only accepts every valid form:"
rc=0; ( cd "$ROOT" && "$CC" --syntax-only < "$TC" > /dev/null 2> "$T/so.err" ) || rc=$?
check "typed_array_subscript.tcyr: --syntax-only exits 0" 0 "$rc"
check "typed_array_subscript.tcyr: --syntax-only reports nothing" 0 "$(grep -c 'error' "$T/so.err")"

echo "axis 5 — a slice local keeps its bounds-checked subscript:"
runs slice_subscript 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/slice.cyr"\nfn f(): i64 {\n    var buf: u8[4];\n    store8(&buf + 2, 9);\n    var s: slice<u8> = 0;\n    slice_set(&s, &buf, 4);\n    return s[2];\n}\nalloc_init();\nsyscall(60, f());\n' 9

if [ "$fails" -ne 0 ]; then
    echo "FAIL: array_subscript_forms — $fails check(s) failed"
    exit 1
fi
echo "PASS: array_subscript_forms — 10 refusals named, 8 typed controls run, the runtime file green by default and under CYRIUS_IR=3, --syntax-only clean, the slice subscript untouched"
exit 0
