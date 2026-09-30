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
#   states no element width (N bytes in a fn, N slots at top level), so its subscript is refused
#   rather than guessed; a scalar, a pointer and a `stack var` buffer are not element-typed
#   arrays; a u128 element does not fit one register. An unknown name is `undefined variable`.
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

NOTARR="cannot subscript 'a': \`a[i]\` needs an element-typed array"
echo "axis 1 — the refusals, by name:"
refused bare_local_write 'fn f(): i64 {\n    var a[16];\n    a[1] = 5;\n    return 0;\n}\nsyscall(60, f());\n' \
    "error:<source>:3:6: $NOTARR"
refused bare_local_read  'fn f(): i64 {\n    var a[16];\n    return a[1];\n}\nsyscall(60, f());\n' \
    "error:<source>:3:13: $NOTARR"
refused bare_global_read 'var a[4];\nfn f(): i64 { return a[1]; }\nsyscall(60, f());\n' \
    "error:<source>:2:23: $NOTARR"
refused bare_toplevel_write 'var a[4];\nsyscall(60, 0);\na[2] = 7;\n' \
    "error:<source>:3:2: $NOTARR"
refused scalar_local     'fn f(): i64 {\n    var a = 5;\n    return a[0];\n}\nsyscall(60, f());\n' \
    "error:<source>:3:13: $NOTARR"
refused pointer_local    'var g: i64[2];\nfn f(): i64 {\n    var a: *i64 = &g;\n    return a[0];\n}\nsyscall(60, f());\n' \
    "error:<source>:4:13: $NOTARR"
refused stack_var        'fn f(): i64 {\n    stack var a[16];\n    a[0] = 1;\n    return 0;\n}\nsyscall(60, f());\n' \
    "error:<source>:3:6: $NOTARR"
refused u128_element     'fn f(): i64 {\n    var a: u128[2];\n    return a[0];\n}\nsyscall(60, f());\n' \
    "error:<source>:3:13: cannot subscript 'a': a u128 element does not fit one register"
refused undefined_name   'fn f(): i64 { return nope[1]; }\nsyscall(60, f());\n' \
    "undefined variable 'nope'"

echo "axis 2 — anti-vacuous: the typed spelling of every refused shape runs:"
runs typed_local_write 'fn f(): i64 {\n    var a: u8[16];\n    a[1] = 5;\n    return a[1];\n}\nsyscall(60, f());\n' 5
runs typed_global_read 'var a: i16[4];\nfn f(): i64 { a[1] = 0 - 3; return a[1] + 10; }\nsyscall(60, f());\n' 7
runs typed_toplevel_write 'var a: i32[4];\nsyscall(0, 0, 0, 0);\na[2] = 7;\na[2] *= 6;\nsyscall(60, a[2]);\n' 42
runs typed_i64_local 'fn f(): i64 {\n    var a: i64[4];\n    var i = 3;\n    a[i] = 40;\n    a[i] += 2;\n    return a[3];\n}\nsyscall(60, f());\n' 42

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
echo "PASS: array_subscript_forms — 9 refusals named, 4 typed controls run, the runtime file green by default and under CYRIUS_IR=3, --syntax-only clean, the slice subscript untouched"
exit 0
