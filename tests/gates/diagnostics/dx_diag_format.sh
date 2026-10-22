#!/bin/sh
# v6.4.60 (DX diagnostics): assert cycc's error output carries a COLUMN and a
# SOURCE-EXCERPT with a caret — the format is
#     error:<source>:LINE:COL: <message>
#         <offending source line>
#             ^
# Regression guard for the packed-tok_lines offset (lex.cyr ADDTOK / util.cyr
# GTLINE mask + GTOFF) and the _err_head / _err_col / _err_excerpt emitter path.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 77; }
T=$(mktemp) && [ -f "$T" ] || { echo "FAIL: dx_diag_format: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
E=$(mktemp) && [ -f "$E" ] || { echo "FAIL: dx_diag_format: mktemp failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -f "$T" "$E"' EXIT

# A missing-semicolon error → "expected ';', got return"; the offending token is
# `return` at column 5 of line 3.
printf 'fn main(): i64 {\n    var x = 42\n    return x;\n}\n' > "$T"
if "$CC" < "$T" > /dev/null 2>"$E"; then
    echo "FAIL: the broken program compiled clean — expected a parse error"; exit 1
fi

# 1) COLUMN: error:<file>:LINE:COL:  (two numeric fields after the filename)
grep -Eq '^error:[^:]*:[0-9]+:[0-9]+: ' "$E" || { echo "FAIL: no :LINE:COL: column in the diagnostic:"; cat "$E"; exit 1; }
# 2) exact location — `return` starts at column 5 of line 3
grep -q ':3:5: ' "$E" || { echo "FAIL: wrong line:column (want :3:5:):"; cat "$E"; exit 1; }
# 3) the CARET line — leading spaces then a single ^
grep -Eq '^ +\^$' "$E" || { echo "FAIL: no caret excerpt line:"; cat "$E"; exit 1; }
# 4) the offending SOURCE line appears in the excerpt
grep -q 'return x;' "$E" || { echo "FAIL: source excerpt missing the offending line:"; cat "$E"; exit 1; }
# 5) the retired internal `at fail:` table dump must NOT reappear
grep -q 'at fail:' "$E" && { echo "FAIL: the retired 'at fail:' capacity dump is back:"; cat "$E"; exit 1; }

# ── 6.7.17 (FD1): a struct is named as the source spells it — a generic instance `B<i32>`, never the struct table's
# minted `B$i32` — in every refusal that names one, and an instance's refusal prints once. Each row: exactly one
# line carrying the wanted text, and no `$` anywhere in the output.
mn() {   # <row> <wanted text> <program>
    printf '%s\n' "$3" > "$T"
    if (cd "$ROOT" && "$CC" < "$T" > /dev/null 2>"$E"); then echo "FAIL: $1 compiled clean"; exit 1; fi
    n=$(grep -cF -- "$2" "$E" || true)
    [ "$n" = 1 ] || { echo "FAIL: $1: want one line naming \"$2\", got $n:"; cat "$E"; exit 1; }
    if grep -q '\$' "$E"; then echo "FAIL: $1: a mangled struct name:"; cat "$E"; exit 1; fi
}
BI='struct B<T> { v: T; }'
B3='struct B<T> { v: T; w: i64; u: i64; }'
MK3='fn mk(): B<i32> { var b: B<i32>; return b; }'
mn MN1 "error:<source>:2:38: unknown field 'zq' on struct 'B<i32>'" "$BI
fn main(): i64 { var x: B<i32>; x.zq = 1; return 0; }
syscall(60, main());"
mn MN2 "unknown field 'zq' on struct 'B<i32>'" "$BI
fn main(): i64 { var x: B<i32>; var y = x.zq; return y; }
syscall(60, main());"
mn MN3 "unknown field 'zq' on struct 'B<i32>'" "$BI
fn main(): i64 { var x: B<i32>; var p: *B<i32> = &x; p.zq = 1; return 0; }
syscall(60, main());"
mn MN4 "unknown field 'zq' on struct 'B<i32>'" "$BI
struct O { b: B<i32>; }
fn main(): i64 { var o: O; var y = o.b.zq; return y; }
syscall(60, main());"
mn MN5 "which returns the struct 'B<i32>' - declare 'g: B<i32>' or bind a field" "$B3
$MK3
var g = 0;
fn main(): i64 { g = mk(); return 0; }
syscall(60, main());"
mn MN6 "cannot initialise 'x: i64' from 'mk', which returns the struct 'B<i32>' - declare 'x: B<i32>'" "$B3
$MK3
fn main(): i64 { var x: i64 = mk(); return 0; }
syscall(60, main());"
mn MN7 "cannot assign 'x: i64' from 'mk', which returns the struct 'B<i32>' - declare 'x: B<i32>'" "$B3
$MK3
fn main(): i64 { var x: i64 = 0; x = mk(); return 0; }
syscall(60, main());"
mn MN8 "step with p + i to an element of struct 'B<i32>'" "$BI
fn main(): i64 { var b: B<i32>; var p: *B<i32> = &b; var y = p[0]; return y; }
syscall(60, main());"
mn MN9 'a fn returning the 9-16 byte struct `B<Q>` is returned in two registers' "struct Q { a; }
struct B<T> { v: T; w: T; }
struct C { a; b; }
fn mk(c: C): B<Q> { return c; }
fn main(): i64 { return 0; }
syscall(60, main());"
mn MN10 'a fn returning the struct `B<i32>` returns that struct — `ret2` writes two values' "$B3
fn mk(q: i64): B<i32> { ret2(1, 2); }
fn main(): i64 { return 0; }
syscall(60, main());"
mn MN11 'a fn returning the struct `B<i32>` takes a value of that struct, or a pointer to one — got `gq(&q)` (a `*Q`)' "$B3
struct Q { a; b; c; }
fn gq(q: *Q): *Q { return q; }
fn f(): B<i32> { var q: Q; return gq(&q); }
fn main(): i64 { return 0; }
syscall(60, main());"
mn MN12 "cannot destructure 'mk' - it returns struct 'B<i32>', which is not in registers" "$B3
$MK3
fn main(): i64 { var a, c = mk(); return a; }
syscall(60, main());"
mn MN13 "a multi-value call 'g2' is not a struct 'B<i32>' argument" "struct B<T> { v: T; w: i64; }
fn g2(x): (i64, i64) { return (x, x + 1); }
fn take(t: B<i32>): i64 { return 0; }
fn main(): i64 { return take(g2(5)); }
syscall(60, main());"
mn MN14 "a multi-value call 'g2' does not initialize struct 'B<i32>'" "struct B<T> { v: T; w: i64; }
fn g2(x): (i64, i64) { return (x, x + 1); }
fn main(): i64 { var p: B<i32> = g2(5); return 0; }
syscall(60, main());"
mn MN15 "cannot capture 'mk' into tuple (i64, i64) - it returns struct 'B<i32>', not a tuple" "$B3
$MK3
fn main(): i64 { var t: (i64, i64) = mk(); return 0; }
syscall(60, main());"
mn MN16 "an if expression branch cannot be a struct value over 8 bytes: struct 'B<i32>'" "struct B<T> { v: T; w: i64; }
fn main(): i64 { var b: B<i32>; var c = 1; var y = if (c == 1) { b } else { 2 }; return 0; }
syscall(60, main());"
mn MN17 'no `impl Tr for B<i32>` - a dyn Tr is formed only from a type that implements Tr' "trait Tr { fn m(self): i64; }
$BI
fn main(): i64 { var b: B<i32>; var d: dyn Tr = &b; return 0; }
syscall(60, main());"
TB='trait Show { fn show(self): i64; }
struct R { r; }
struct Box<T: Show> { v: T; n; }
struct UB<T> { v: T; }'
mn MN18 'needs `impl Show for UB<i32>`, and there is none' "$TB
fn f(): i64 { var b: Box<UB<i32>>; return 5; }
syscall(60, 7);"
mn MN19 'needs `impl Show for UB<UB<R>>`, and there is none' "include \"lib/vec.cyr\"
$TB
impl Show for R { fn show(self): i64 { return self.r; } }
fn f(): i64 { var w: Vec<Box<UB<UB<R>>>> = 0; return 5; }
syscall(60, 7);"
# An instance's refusal inside a generic fn's body, which is parsed once per instance: once (its record is keyed by
# the struct, not by the scratch offset its spelling is written at).
mn MN20 "error:<source>:2:42: unknown field 'zq' on struct 'B<i32>'" "$BI
fn g<T>(a: T): i64 { var x: B<i32>; x.zq = 1; return 0; }
fn main(): i64 { return g(1) + g(2.0); }
syscall(60, main());"

# ── 6.7.17 (the user's D34): an undefined name is reported AT THE NAME — its line and column, and the caret under it
# (it was the token after it: `return zq + 1;` 1:28 under the `+`). Each row: the head line exactly, the excerpt line
# exactly, the caret under the column. Every undefined-name writer: the read, `&x`, a `.field` base (load, store, a
# wrap's `(x)`), the assignment, the for step, a subscript base, a multi-value target.
xm() {   # <row> <head> <excerpt> <col> <program> [<dir>]
    printf '%b' "$5" > "$T"
    if (cd "${6:-$ROOT}" && "$CC" < "$T" > /dev/null 2>"$E"); then echo "FAIL: $1 compiled clean"; exit 1; fi
    grep -qxF -- "$2" "$E" || { echo "FAIL: $1: no head line '$2':"; cat "$E"; exit 1; }
    grep -qxF -- "    $3" "$E" || { echo "FAIL: $1: no excerpt line '    $3':"; cat "$E"; exit 1; }
    cl=$(grep -A1 -xF -- "    $3" "$E" | sed -n 2p)
    want=$(printf '%*s^' $(($4 + 3)) '')
    [ "$cl" = "$want" ] || { echo "FAIL: $1: the caret is not under column $4: '$cl'"; cat "$E"; exit 1; }
}
MI=" (missing include or enum?)"
xm CR1 "error:<source>:1:25: undefined variable 'zq'$MI" 'fn main(): i64 { return zq + 1; }' 25 'fn main(): i64 { return zq + 1; }\nsyscall(60, main());\n'
xm CR2 "error:<source>:1:25: undefined variable 'zz'$MI" 'fn main(): i64 { return zz; }' 25 'fn main(): i64 { return zz; }\nsyscall(60, main());\n'
FB='fn main(): i64 {\n    var x = 1;\n'
FE='    return 0;\n}\nsyscall(60, main());\n'
xm CR3 "error:<source>:3:5: undefined variable 'zw'" '    zw = x + 1;' 5 "$FB"'    zw = x + 1;\n'"$FE"
xm CR4 "error:<source>:3:5: undefined variable 'zw'" '    zw += 2;' 5 "$FB"'    zw += 2;\n'"$FE"
xm CR5 "error:<source>:3:13: undefined variable 'zw'" '    var a = zw.b;' 13 "$FB"'    var a = zw.b;\n'"$FE"
xm CR6 "error:<source>:3:5: undefined variable 'zw'" '    zw.c = 1;' 5 "$FB"'    zw.c = 1;\n'"$FE"
xm CR7 "error:<source>:3:14: undefined variable 'zw'" '    var a = (zw).b;' 14 "$FB"'    var a = (zw).b;\n'"$FE"
xm CR8 "error:<source>:3:14: undefined variable 'zw'" '    var p = &zw;' 14 "$FB"'    var p = &zw;\n'"$FE"
xm CR9 "error:<source>:3:13: undefined variable 'zw'$MI" '    var r = zw[0];' 13 "$FB"'    var r = zw[0];\n'"$FE"
xm CR10 "error:<source>:3:28: undefined variable 'zw'" '    for (var i = 0; i < 3; zw = i + 1) { }' 28 "$FB"'    for (var i = 0; i < 3; zw = i + 1) { }\n'"$FE"
xm CR11 "error:<source>:4:8: undefined variable 'zw'" '    x, zw = two();' 8 'fn two(): (i64, i64) { return (1, 2); }\n'"$FB"'    x, zw = two();\n'"$FE"
# An assignment whose value holds a statement (a closure body's): at the assignment's name, not the inner `t` (the
# review of FD1: the inner statement overwrote the name token the report reads).
xm CR13 "error:<source>:3:5: undefined variable 'zw'" '    zw = |a| { var t = 1; t = t + 1; return a; };' 5 "$FB"'    zw = |a| { var t = 1; t = t + 1; return a; };\n'"$FE"
# A generic body parsed once per instance reports its undefined name once, at the name.
xm CR12 "error:<source>:1:29: undefined variable 'zq'$MI" 'fn g<T>(a: T): i64 { return zq + 1; }' 29 'fn g<T>(a: T): i64 { return zq + 1; }\nfn main(): i64 { return g(1) + g(2.0); }\nsyscall(60, main());\n'
[ "$(grep -c '^error:' "$E")" = 1 ] || { echo "FAIL: CR12: the instance's report is not once:"; cat "$E"; exit 1; }

# ── 6.7.17 (met in FD1): the struct-return refusals printed their head line alone, where every other error shows
# its source line and the caret: EX1 the 9-16 B pair class, EX2 a call returning another struct, EX3 a tuple literal,
# EX4 `&q` of a handle.
xm EX1 'error:<source>:4:28: a fn returning the 9-16 byte struct `B<Q>` is returned in two registers, so `return` takes a local of that struct or a call returning it — got `c`' 'fn mk(c: C): B<Q> { return c; }' 28 'struct Q { a; }\nstruct B<T> { v: T; w: T; }\nstruct C { a; b; }\nfn mk(c: C): B<Q> { return c; }\nfn main(): i64 { return 0; }\nsyscall(60, main());\n'
xm EX2 'error:<source>:4:35: a fn returning the struct `B<i32>` takes a value of that struct, or a pointer to one — got `gq(&q)` (a `*Q`)' 'fn f(): B<i32> { var q: Q; return gq(&q); }' 35 'struct B<T> { v: T; w: i64; u: i64; }\nstruct Q { a; b; c; }\nfn gq(q: *Q): *Q { return q; }\nfn f(): B<i32> { var q: Q; return gq(&q); }\nfn main(): i64 { return 0; }\nsyscall(60, main());\n'
xm EX3 'error:<source>:2:20: a fn returning the struct `Q` returns that struct — `(a, b)` is a tuple, another type' 'fn f(): Q { return (1, 2); }' 20 'struct Q { a; b; c; }\nfn f(): Q { return (1, 2); }\nsyscall(60, 0);\n'
xm EX4 'error:<source>:4:52: a fn returning the struct `S8` takes a value of that struct, or a pointer to one — `&q` is the address of q'"'"'s slot, not a struct — return q' 'fn h(): S8 { var q: S8 = alloc(8); q.v = 3; return &q; }' 52 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\nstruct S8 { v; }\nfn h(): S8 { var q: S8 = alloc(8); q.v = 3; return &q; }\nfn main(): i64 { alloc_init(); var c: S8 = h(); return c.v == 3; }\nsyscall(60, main());\n'

# ── 6.7.17 (FD1): a diagnostic past an in-line expansion reports the SOURCE column, and its excerpt is the source line
# — not the expanded one (a `#derive`'s generated fns flattened onto the struct's `}` line; a macro call's body). Each
# row: the head line exactly, the excerpt line exactly, the caret under the column.
UZ="undefined variable 'zz' (missing include or enum?)"
ADD='#define ADD(a, b) ((a) + (b) + (a) + (b))\n'
xm XM1 "error:<source>:2:25: $UZ" 'struct Q { y; } var w = zz;' 25 '#derive(accessors)\nstruct Q { y; } var w = zz;\nsyscall(60, 0);\n'
xm XM2 "error:<source>:2:21: $UZ" 'var x = ADD(1, 2) + zz;' 21 "${ADD}"'var x = ADD(1, 2) + zz;\nsyscall(60, 0);\n'
xm XM3 "error:<source>:2:33: $UZ" 'var x = ADD(1, 2) + ADD(3, 4) + zz;' 33 "${ADD}"'var x = ADD(1, 2) + ADD(3, 4) + zz;\nsyscall(60, 0);\n'
xm XM4 "error:<source>:3:7: $UZ" ' 2) + zz;' 7 "${ADD}"'var x = ADD(1,\n 2) + zz;\nsyscall(60, 0);\n'
xm XM5 "error:<source>:2:9: $UZ" 'var x = ID(1);' 9 '#define ID(a) ((a) + zz)\nvar x = ID(1);\nsyscall(60, 0);\n'
xm XM6 "error:<source>:4:11: $UZ" '} var w = zz;' 11 '#derive(accessors)\nstruct Q {\n    y;\n} var w = zz;\nsyscall(60, 0);\n'
xm XM7 "error:<source>:2:29: $UZ" 'var x = ADD(ADD(1, 2), 3) + zz;' 29 "${ADD}"'var x = ADD(ADD(1, 2), 3) + zz;\nsyscall(60, 0);\n'
xm XM8 "error:<source>:3:48: $UZ" 'struct Q { y; } var w = ADD(1, 2) + 1; var v = zz;' 48 \
    "${ADD}"'#derive(accessors)\nstruct Q { y; } var w = ADD(1, 2) + 1; var v = zz;\nsyscall(60, 0);\n'
# An included file's line: the macro (defined in the entry) expanded there, and a derive the include pass expands.
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: dx_diag_format: mktemp -d failed"; exit 1; }
printf 'var y = ADD(1, 2) + zz;\n' > "$D/inc_m.cyr"
xm XM9 "error:inc_m.cyr:1:21: $UZ" 'var y = ADD(1, 2) + zz;' 21 "${ADD}"'include "inc_m.cyr"\nsyscall(60, 0);\n' "$D"
printf '#derive(accessors)\nstruct Q { y; } var w = zz;\n' > "$D/inc_d.cyr"
xm XM10 "error:inc_d.cyr:2:25: $UZ" 'struct Q { y; } var w = zz;' 25 'include "inc_d.cyr"\nsyscall(60, 0);\n' "$D"
rm -rf "$D"
# The lexer's head reads the same map: a stray byte past a macro call is at its source column.
printf '#define ADD(a, b) ((a) + (b) + (a) + (b))\nvar x = ADD(1, 2) + 1; var y = 5 $ 1;\nsyscall(60, 0);\n' > "$T"
if "$CC" < "$T" > /dev/null 2>"$E"; then echo "FAIL: XM11 compiled clean"; exit 1; fi
grep -q '^error:<source>:2:34: ' "$E" || { echo "FAIL: XM11: the lexer's column is not the source's (want 2:34):"; cat "$E"; exit 1; }

echo "PASS: dx diagnostics — column (:L:C:) + source excerpt + caret; no at-fail noise; a struct named as written (MN1-MN20); an undefined name at the name (CR1-CR13); every struct-return refusal with its excerpt (EX1-EX4); past an in-line expansion the source column and line (XM1-XM11)"
exit 0
