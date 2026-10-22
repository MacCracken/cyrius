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

echo "PASS: dx diagnostics — column (:L:C:) + source excerpt + caret; no at-fail noise; a struct named as written (MN1-MN20)"
exit 0
