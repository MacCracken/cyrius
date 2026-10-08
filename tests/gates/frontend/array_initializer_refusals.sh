#!/bin/sh
# Gate: a global array initializer `var X: T[N] = { .. }` refuses BY NAME what it cannot mean
# (6.6.16, C1). The values it does take are run on every host by
# tests/tcyr/crossos/global_array_initializer.tcyr; this pins the compile-time half.
#
# ⛔ WHY. Until 6.6.16 the list was a BYTE list whatever the element type, so most of these
# shapes compiled SILENTLY into the wrong bytes: `var a: Pt[2] = {1,2,3,4}` (struct elements),
# `i8v16[2]`, `bool[2]` and `*Pt[2]` lists were bytes, `var a: u8[3] = {1,2,3,4}` overran the
# element count up to the slot's 8 bytes, and the rest failed with messages about the wrong thing
# (`-3` -> `expected number, got '-'`, an enum -> `expected number, got identifier`). Now the list
# is N elements of T, and each shape that cannot be that is refused with its own message, at its
# own token, with no binary.
#
# ROWS. A refusal row must exit non-zero, write NO binary, and print its message exactly once.
#   count      more elements than the array holds (typed: names N), more bytes (the bare list)
#   range      one window per width, -2^(8w-1) .. 2^(8w)-1 (a value that would be TRUNCATED);
#              the bare byte list keeps [0, 255]
#   constant   a call, a variable, a string; a float literal in an integer array
#   type       a struct, a vector, cstring, Str (a struct) — "store the elements explicitly"
#   block      an initializer inside a top-level block (`while`, `if`, `elif`, `else`, `for` and
#              its init clause, a `switch` case / default arm on both dispatch paths, `@unsafe`,
#              a bare `{ }`) — a baked list would hold its values once where a scalar initializer
#              runs every time the block does. `elif` opens no scope, so a scope-depth test would
#              miss it: the parser's nesting depth decides (_pp_depth). A switch arm, `@unsafe`
#              and a for-init parse their statements with no PARSE_PROG body, so they count
#              through _PARSE_STMT_NESTED: before the 6.6.16 review fix a list in a top-level
#              `case 0:` arm compiled and was baked whether or not the arm ran (`var i = 1;
#              switch (i) { case 0: var b: i64[2] = {1,2}; break; } syscall(60, b[1]);` exited
#              2, the scalar sibling 0).
#   enum       a variant named through the wrong enum gets the reference's own message, once —
#              not a second "must be constants" on top of it
#   local      a fn-local list is still not a feature (`expected ';'`, unchanged)
# The CONTROLS compile and run: the same shapes at their legal edges, a module-scope declaration
# after the first statement, one after a switch / `@unsafe` / `for` (the depth is restored, and a
# refusal inside one leaves the next module-scope list accepted), an enum declared below its use,
# and `--syntax-only` (lint's pre-pass) refuses no value — a sibling file's enum is unknown there.
#
# MUTATION LEDGER (6.6.16, each a scratch tree built with the tree's cycc, CYCC= that compiler):
#   1. real tree                                           -> GREEN (41 rows)
#   2. the slot-open compiler                              -> RED, 50 checks
#   2b. d5fcaa38 (the bite before its review fix)          -> RED, 21 checks: the six switch /
#      @unsafe / for-init rows and block_then_module compile
#   3. _gai_stmt's `_pp_depth != 1` -> `GSDEP(S) != 0`      -> RED, 3 checks: the `elif` row compiles
#   3b. _PARSE_STMT_NESTED's two `_pp_depth` bumps removed -> RED, 21 checks: the same seven rows
#   4. _gai_range's window check removed                   -> RED, 12 checks: the four typed range rows
#   5. _gai_bad's report through the reference removed     -> RED, 2 checks: the wrong-enum row
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
[ -x "$CC" ] || { echo "FAIL: array_initializer_refusals: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: array_initializer_refusals: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
fail=0
rows=0
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# refuse <id> <needle> <source>
refuse() {
    rows=$((rows + 1))
    printf '%b' "$3" > "$T/$1.cyr"
    rc=0
    "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    [ "$rc" != 0 ] || bad "$1: compiled (rc 0), want a refusal"
    [ -s "$T/$1.bin" ] && bad "$1: wrote a binary"
    n=$(grep -cF -- "$2" "$T/$1.err")
    [ "$n" = 1 ] || bad "$1: '$2' printed $n times, want 1: $(grep -m1 '^error' "$T/$1.err")"
}
# accept <id> <want-exit> <source> [flags]
accept() {
    rows=$((rows + 1))
    printf '%b' "$3" > "$T/$1.cyr"
    rc=0
    "$CC" ${4:-} < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    if [ "$rc" != 0 ]; then bad "$1: refused (rc $rc): $(grep -m1 '^error' "$T/$1.err")"; return; fi
    [ "$2" = "-" ] && return
    chmod +x "$T/$1.bin"
    xr=0
    "$T/$1.bin" > /dev/null 2>&1 || xr=$?
    [ "$xr" = "$2" ] || bad "$1: the program exited $xr, want $2"
}

# ── count ────────────────────────────────────────────────────────────────────────────────────
refuse count_typed 'more elements than the array holds (2)' 'var a: i64[2] = {1, 2, 3};\nsyscall(60, 0);\n'
refuse count_u8    'more elements than the array holds (3)' 'var a: u8[3] = {1, 2, 3, 4};\nsyscall(60, 0);\n'
refuse count_bare  "more bytes than the array's declared capacity" 'var b[1] = {1, 2, 3, 4, 5, 6, 7, 8, 9};\nsyscall(60, 0);\n'
# ── range ────────────────────────────────────────────────────────────────────────────────────
refuse range_i8_hi  'value 256 does not fit a 1-byte element (-128 .. 255)' 'var a: i8[2] = {1, 256};\nsyscall(60, 0);\n'
refuse range_i8_lo  'value -129 does not fit a 1-byte element' 'var a: i8[1] = {-129};\nsyscall(60, 0);\n'
refuse range_u16    'value 65536 does not fit a 2-byte element (-32768 .. 65535)' 'var a: u16[1] = {0x10000};\nsyscall(60, 0);\n'
refuse range_i32    'does not fit a 4-byte element' 'var a: i32[1] = {0x100000000};\nsyscall(60, 0);\n'
refuse range_bare   'byte-array literal value must be in [0, 255]' 'var b[1] = {256};\nsyscall(60, 0);\n'
refuse range_bare_n 'byte-array literal value must be in [0, 255]' 'var b[1] = {-1};\nsyscall(60, 0);\n'
# ── constant ─────────────────────────────────────────────────────────────────────────────────
# 6.7.4: a list element is a const context (the compile-time evaluator), so a non-constant one is
# refused in that context's words — it names what the element is.
refuse const_call  "'f' is not a \`const fn\`" 'fn f(): i64 { return 1; }\nvar a: i64[2] = {f(), 1};\nsyscall(60, 0);\n'
refuse const_var   "'k' is a variable - a const context takes only constants" 'var k = 1;\nvar a: i64[1] = {k};\nsyscall(60, 0);\n'
refuse const_str   'array initializer elements must be constants' 'var a: i64[1] = {"x"};\nsyscall(60, 0);\n'
refuse const_float 'a float literal initializes only an f64 or f32 array element' 'var a: i64[1] = {1.5};\nsyscall(60, 0);\n'
refuse const_post  "'k' is a variable - a const context takes only constants" 'syscall(1, 1, "", 0);\nvar k = 2;\nvar a: u16[1] = {k};\nsyscall(60, 0);\n'
# ── type ─────────────────────────────────────────────────────────────────────────────────────
refuse type_struct  "an initializer list for an array of 'Pt' is not supported" 'struct Pt { x; y; }\nvar a: Pt[2] = {1, 2, 3, 4};\nsyscall(60, 0);\n'
refuse type_vector  "an initializer list for an array of 'i8v16' is not supported" 'var a: i8v16[2] = {1};\nsyscall(60, 0);\n'
refuse type_cstring "an initializer list for an array of 'cstring' is not supported" 'var a: cstring[2] = {0};\nsyscall(60, 0);\n'
refuse type_str     "an initializer list for an array of 'Str' is not supported" 'include "lib/str.cyr"\nvar a: Str[1] = {0};\nsyscall(60, 0);\n'
refuse type_post    "an initializer list for an array of 'Pt' is not supported" 'struct Pt { x; y; }\nsyscall(1, 1, "", 0);\nvar a: Pt[1] = {1};\nsyscall(60, 0);\n'
# ── block ────────────────────────────────────────────────────────────────────────────────────
B='an array initializer is allowed only at module scope'
refuse block_while "$B" 'var i = 0;\nwhile (i < 1) { var b: i64[2] = {1, 2}; i = i + 1; }\nsyscall(60, 0);\n'
refuse block_if    "$B" 'var i = 0;\nif (i == 0) { var b[1] = {1}; }\nsyscall(60, 0);\n'
refuse block_elif  "$B" 'var i = 1;\nif (i == 0) { i = 2; } elif (i == 1) { var b: u8[2] = {1, 2}; }\nsyscall(60, 0);\n'
refuse block_else  "$B" 'var i = 1;\nif (i == 0) { i = 2; } else { var b: i32[1] = {7}; }\nsyscall(60, 0);\n'
refuse block_for   "$B" 'for (var i = 0; i < 1; i = i + 1) { var b: i64[1] = {5}; }\nsyscall(60, 0);\n'
refuse block_bare  "$B" 'var i = 0;\n{ var b: i64[1] = {5}; }\nsyscall(60, 0);\n'
refuse block_switch_case    "$B" 'var i = 1;\nswitch (i) { case 0: var b: i64[2] = {1, 2}; break; }\nsyscall(60, 0);\n'
refuse block_switch_default "$B" 'var i = 0;\nswitch (i) { case 0: break; default: var b: i64[2] = {1, 2}; }\nsyscall(60, 0);\n'
# four dense cases take x86's jump-table path, a second set of case / default body loops
refuse block_switch_table   "$B" 'var i = 9;\nswitch (i) { case 0: break; case 1: break; case 2: break; case 3: var b[1] = {7}; break; }\nsyscall(60, 0);\n'
refuse block_switch_tdef    "$B" 'var i = 9;\nswitch (i) { case 0: break; case 1: break; case 2: break; case 3: break; default: var b: u8[1] = {7}; }\nsyscall(60, 0);\n'
refuse block_unsafe         "$B" '@unsafe { var b: i64[2] = {1, 2}; }\nsyscall(60, 0);\n'
refuse block_for_init       "$B" 'var s = 0;\nfor (var b: i64[2] = {1, 2}; s < 1; s = s + 1) { }\nsyscall(60, 0);\n'
# ── enum ─────────────────────────────────────────────────────────────────────────────────────
refuse enum_wrong_base "'EA' is not a variant of 'E2'" 'enum E1 { EA = 1; }\nenum E2 { EB = 2; }\nvar a: i64[1] = {E2.EA};\nsyscall(60, 0);\n'
grep -q 'must be constants' "$T/enum_wrong_base.err" && bad "enum_wrong_base: a second, generic message followed the reference's own"
# a refusal inside a switch arm leaves the nesting count as it found it: the module-scope list
# after it is accepted, so the file's ONE error is the arm's (a leaked count would add a second)
refuse block_then_module "$B" 'var i = 0;\nswitch (i) { case 0: var b: i64[1] = {1}; break; }\nvar c: i64[1] = {2};\nsyscall(60, c[0]);\n'
# ── local (unchanged: not a feature) ─────────────────────────────────────────────────────────
refuse local_fn "expected ';', got '='" 'fn f(): i64 { var b: i64[2] = {1, 2}; return b[0]; }\nsyscall(60, f());\n'

# ── controls ─────────────────────────────────────────────────────────────────────────────────
accept ok_count   3   'var a: i64[3] = {1, 2, 3};\nsyscall(60, a[2]);\n'
accept ok_edges   0   'var a: i8[2] = {-128, 255};\nvar u: u16[2] = {-32768, 0xFFFF};\nvar w: i32[2] = {0 - 0x80000000, 0xFFFFFFFF};\nvar b[1] = {0, 255};\nsyscall(60, a[0] + 128 + a[1] + 1 + load8(&b + 1) - 255);\n'
accept ok_post    5   'syscall(1, 1, "", 0);\nvar b: i64[2] = {4, 5};\nsyscall(60, b[1]);\n'
accept ok_after_blocks 9 'var i = 1;\nswitch (i) { case 0: i = 2; break; default: i = 3; }\n@unsafe { i = i + 1; }\nfor (var j = 0; j < 1; j = j + 1) { }\nvar b: i64[2] = {4, 5};\nsyscall(60, b[1] + i);\n'
accept ok_forward 9   'var a: i64[2] = {E.Z, Y};\nenum E { Y = 4; Z = 5; }\nsyscall(60, a[0] + a[1]);\n'
accept ok_float   0   'var f: f64[1] = {-1.5};\nvar g: f32[1] = {2.5};\nif (load64(&f) != 0xBFF8000000000000) { syscall(60, 1); }\nif (load32(&g) != 0x40200000) { syscall(60, 2); }\nsyscall(60, 0);\n'
accept ok_syntax_only - 'var a: i64[2] = {SiblingEnumValue, 1};\nvar b: Pt[1] = {1};\nsyscall(60, 0);\n' --syntax-only

[ "$rows" -ge 41 ] || bad "only $rows rows ran (floor 41)"
if [ "$fail" -ne 0 ]; then
    echo "FAIL: array_initializer_refusals ($fail checks failed over $rows rows)"
    exit 1
fi
echo "PASS: array_initializer_refusals ($rows rows)"
exit 0
