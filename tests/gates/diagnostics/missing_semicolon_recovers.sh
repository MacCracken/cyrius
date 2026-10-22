#!/bin/sh
# tests/gates/diagnostics/missing_semicolon_recovers.sh — 6.7.17
#
# A STATEMENT MISSING ITS `;` IS ONE ERROR, AND WHAT FOLLOWS IS PARSED: the next fn is not "inside" the last, the next
# statement's own error is reported, and the declaration zone's entry ends where its `;` is missing.
#
# THE DEFECT (measured 6.7.16, x86_64; the frontend, every target). After "expected ';'" the parser consumed the token
# in the `;`'s place: a fn's closing `}` (`return 1 }` — the next fn "defined inside" it, "expected '}', got end of
# file"), or the next statement's keyword (`var a = 1` then `var b = zz;` — `b`'s statement parsed from its second
# token, `zz` never reported). A statement that stepped a stray `{` left its `}` to be taken as the block's end
# ("unexpected ';'", "return outside a fn body"). In the declaration zone pass 1 / pass 2 stepped a `;`-less
# `var g = 1` to the next `;` at depth 0, swallowing the declarations after it and their errors.
# (issues/2026-10-21-statement-missing-semicolon-loses-what-follows.md)
#
# THE FIX. The `;` sites step only a token that is not a recovery point (`_expect_step`, src/common/util.cyr: a `}`,
# EOF, a `;` or a statement keyword stays for the block loop / the statement resync). `_stmt_resync`
# (src/frontend/parse.cyr) first steps through the `}` of each `{` the statement opened and left unclosed
# (`_resync_close`) — unless the statement ended at its own `;`.
#
#   S2  the filing's s2 verbatim (`var a = 1` then `var b = zz;`): the `;`, then `zz`
#   V   a `var` statement's `;` (PARSE_VAR): V1-V4 before an if / while / for / return, V5 before a closure, V6
#       before the fn's `}` (the next fn not "inside" it)
#   P   a statement's `;` (src/frontend/parse.cyr): P1 an assignment before the fn's `}`, P2 / P3 break / continue
#       before the loop's `}`, P4 a method call and P5 an explicit generic call before a `return`
#   S1  the filing's s1 verbatim (`return 1 }`): one error, the next fn not "inside" it
#   R   a `return`'s `;` (src/frontend/parse_fn.cyr): R1 `return 1 }` in a nested block, R2 `return a` before a `var`,
#       R3 a call's return before the fn's `}`
#   F   a C-style `for` header missing one of its two `;`: F1 the condition's, F2 the init's, F3 an assignment
#       init's, F4 both, F5 a header ending at the condition, F6 a compound step — the one `;` error, then the body's
#   D   a `dyn` initializer's `;`: D1 before a `return` (its source ran on to the next `;`: "cannot form dyn Show
#       from this expression"), D2 before the fn's `}`; D3 / D4 a dyn assignment `o = &p` before the `}` / a `return`
#   E   a subscript store's `;` (`a[0] = 1`): E1 before the fn's `}`, E2 before a `return`
#   T   an assignment's terminator (the `term` sites the statement and the classic-for step share): T1 `*q = 5`
#       before the fn's `}`, T2 a struct copy `*q = o` before a `return`, T3 / T4 a field store before the `}` / a
#       `return`, T5 a call's field `gp().n = 5` before the `}`
#   M   a destructure's call missing its `;`: M1 `x, y = two(3)` before the `}`, M2 `var a, b = two(3)` before a
#       `return` — "expected ';'", not "needs a call on the right-hand side"; M3 the control `two(3) + 1` keeps it
#   B   brace accounting: B1 `a = 2 { 3 };` then a later fn's error, B2 the same inside an `if` block
#   K   the S22 control (struct_literal_type_refused.sh): `var P = 3; P { 5 };` keeps its one line, and a later
#       statement's error after it is reported; K3 an unclosed literal ending at its `;` (CT4) — the `}` after it is
#       the fn's
#
# On the parent (db54fb84e) RED: S2 V1-V6 (the keyword or `}` stepped: `zz` lost, "return outside a fn body", "fn 'g'
# is defined inside fn 'f'"); K green. On bc51aa5c6 (before `_resync_close`) RED: B1 B2 (the stray `{`'s `}` closed the
# fn: "unexpected ';'" / "unexpected number 4", "return outside a fn body"). `_resync_close` without its own-`;`
# exemption -> RED K3 ("expected '}', got end of file"). On 99355d191 (before parse.cyr's sites) RED: P1-P5.
# On 11bbb4141 (before parse_fn.cyr's sites) RED: S1 R1-R3. On b91579399 (before `_for_semis`) RED: F1-F6 (the
# init's resync ran into the condition, the step replayed from the token after the missing `;`, the step skip ran
# to a later `)`: "expected '=', got '+'", "unexpected end of input", "undefined variable 'fn'"). On 0b606cc77 (before
# parse_types.cyr's sites and `_dyn_ext`'s keyword stop) RED: D1 D2.
# On c3dea492b (before parse_expr.cyr's sites) RED: E1 E2. On 958534651 (before parse.cyr's `term` sites) RED: T1 T2.
# On 063eeadf7 (before parse_decl.cyr's `term` sites) RED: T3-T5. On ed2f66ae0 (before `_dyn_asg`'s) RED: D3 D4.
# On 36c6cb47f (before `_dt_rhs_end`) RED: M1 M2 ("multi-value destructure needs a call on the right-hand side").
#
# Legs: x86_64, aarch64 and cx (their compilers built from this tree's src) and PE (CYRIUS_TARGET_WIN=1) — the
# frontend is shared; a refusal needs no run.
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=missing_semicolon_recovers
[ -x "$CC" ] || { echo "SKIP: $G: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: $G: mktemp -d failed"; exit 77; }
trap 'rm -rf "$D"' EXIT

pass=0; fail=0
ok()  { echo "  ok   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

A64=""; CXCC=""
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
    chmod +x "$D/cc_a64"; A64="$D/cc_a64"
else bad "aarch64: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ]; then
    chmod +x "$D/cc_cx"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr did not build"; fi
LEGS="x86 pe"
[ -n "$A64" ] && LEGS="$LEGS a64"
[ -n "$CXCC" ] && LEGS="$LEGS cx"

# comp <leg> <src> <out>: compile; rc in CRC
comp() {
    CRC=0
    case "$1" in
        x86) timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        pe)  CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64) timeout 60 "$A64" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)  timeout 60 "$CXCC" < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
}
# row <id> <what> <source> <want-lines>: refused on every leg (rc != 0, no binary), its `error` lines exactly
# <want-lines>, in order
row() {
    printf '%s' "$3" > "$D/$1.cyr"
    printf '%s\n' "$4" > "$D/$1.want"
    for leg in $LEGS; do
        o="$D/$1_$leg"
        comp "$leg" "$D/$1.cyr" "$o"
        grep -E '^error' "$o.err" > "$o.got" || true
        if [ "$CRC" -eq 0 ]; then bad "$1 $leg: $2: rc 0 — want the refusal"
        elif ! cmp -s "$o.got" "$D/$1.want"; then
            bad "$1 $leg: $2: got $(wc -l < "$o.got") lines: $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ]; then bad "$1 $leg: $2: refused, but a binary was written"
        else ok "$1 $leg: $2"; fi
    done
}

UZ="undefined variable 'zz' (missing include or enum?)"

# ---- V: a `var` statement's `;` (PARSE_VAR and the declaration sites, src/frontend/parse_decl.cyr)
row S2 "the filing's s2 verbatim: var a = 1 then var b = zz;" 'fn main(): i64 {
var a = 1
var b = zz;
return a; }
syscall(60, main());
' "error:<source>:3:1: expected ';', got var
error:<source>:3:11: $UZ"

VH='fn f(): i64 {
    var a = 1
'
VT='    return a;
}
syscall(60, f());
'
row V1 "var a = 1 then an if" "${VH}    if (a == 1) { a = zz; }
${VT}" "error:<source>:3:5: expected ';', got if
error:<source>:3:25: $UZ"
row V2 "var a = 1 then a while" "${VH}    while (a == 1) { a = zz; }
${VT}" "error:<source>:3:5: expected ';', got while
error:<source>:3:28: $UZ"
row V3 "var a = 1 then a for" "${VH}    for (var i = 0; i < 3; i = i + 1) { a = zz; }
${VT}" "error:<source>:3:5: expected ';', got for
error:<source>:3:47: $UZ"
row V4 "var a = 1 then a return" "${VH}    return zz;
}
syscall(60, f());
" "error:<source>:3:5: expected ';', got return
error:<source>:3:14: $UZ"
row V5 "var a = 1 then a closure" "${VH}    var g = |x| { return x + zz; };
${VT}" "error:<source>:3:5: expected ';', got var
error:<source>:3:32: $UZ"
row V6 "var a = 1 before the fn's }" 'fn f(): i64 { var a = 1 }
fn g(): i64 { return zz; }
syscall(60, f() + g());
' "error:<source>:1:25: expected ';', got '}'
error:<source>:2:24: $UZ"

# ---- P: a statement's `;` (_PARSE_STMT_IMPL and its arms, src/frontend/parse.cyr)
row P1 "an assignment before the fn's }" 'fn f(): i64 { var x = 0; x = 5 }
fn g(): i64 { return zz; }
syscall(60, f() + g());
' "error:<source>:1:32: expected ';', got '}'
error:<source>:2:24: $UZ"
row P2 "break before the loop's }" 'fn f(): i64 {
    var i = 0;
    while (i < 3) { i = i + 1; break }
    return zz;
}
syscall(60, f());
' "error:<source>:3:38: expected ';', got '}'
error:<source>:4:14: $UZ"
row P3 "continue before the loop's }" 'fn f(): i64 {
    var i = 0;
    while (i < 3) { i = i + 1; continue }
    return zz;
}
syscall(60, f());
' "error:<source>:3:41: expected ';', got '}'
error:<source>:4:14: $UZ"
row P4 "a method-call statement before a return" 'struct P { a; }
impl P { fn m(self): i64 { return self.a; } }
fn f(): i64 {
    var p = P { 1 };
    p.m()
    return zz;
}
syscall(60, f());
' "error:<source>:6:5: expected ';', got return
error:<source>:6:14: $UZ"
row P5 "an explicit generic call statement before a return" 'fn id<T>(x: T): T { return x; }
fn f(): i64 {
    id<i64>(1)
    return zz;
}
syscall(60, f());
' "error:<source>:4:5: expected ';', got return
error:<source>:4:14: $UZ"

# ---- R: a `return`'s `;` (PARSE_RETURN's arms, src/frontend/parse_fn.cyr)
row S1 "the filing's s1 verbatim: return 1 } — one error" 'fn h(): i64 { return 1 }
fn main(): i64 { return 2; }
syscall(60, main());
' "error:<source>:1:24: expected ';', got '}'"
row R1 "return 1 } in a nested block" 'fn f(): i64 {
    var a = 1;
    if (a == 1) { return 1 }
    return zz;
}
syscall(60, f());
' "error:<source>:3:28: expected ';', got '}'
error:<source>:4:14: $UZ"
row R2 "return a before a var" 'fn f(): i64 {
    var a = 1;
    return a
    var b = zz;
}
syscall(60, f());
' "error:<source>:4:5: expected ';', got var
error:<source>:4:15: $UZ"
row R3 "return h(1) } (a call's return)" 'fn h(a): i64 { return a; }
fn f(): i64 { return h(1) }
fn g(): i64 { return zz; }
syscall(60, f() + g());
' "error:<source>:2:27: expected ';', got '}'
error:<source>:3:24: $UZ"

# ---- F: a C-style `for` header missing one of its two `;` (PARSE_FOR, src/frontend/parse_ctrl.cyr)
FH='fn f(): i64 {
    var a = 0;
    var b = 0;
'
FT='    return b;
}
syscall(60, f());
'
row F1 "the condition's ; missing: for (var i = 0; i < 3 i = i + 1)" "${FH}    for (var i = 0; i < 3 i = i + 1) { b = zz; }
${FT}" "error:<source>:4:27: expected ';', got identifier 'i'
error:<source>:4:46: $UZ"
row F2 "the init's ; missing: for (var i = 0 i < 3; i = i + 1)" "${FH}    for (var i = 0 i < 3; i = i + 1) { b = zz; }
${FT}" "error:<source>:4:20: expected ';', got identifier 'i'
error:<source>:4:46: $UZ"
row F3 "an assignment init's ; missing: for (a = 0 a < 3; a = a + 1)" "${FH}    for (a = 0 a < 3; a = a + 1) { b = zz; }
${FT}" "error:<source>:4:16: expected ';', got identifier 'a'
error:<source>:4:42: $UZ"
row F4 "both missing: for (var i = 0 i < 3)" "${FH}    for (var i = 0 i < 3) { b = zz; }
${FT}" "error:<source>:4:20: expected ';', got identifier 'i'
error:<source>:4:35: $UZ"
row F5 "the step missing with its ;: for (var i = 0; i < 3)" "${FH}    for (var i = 0; i < 3) { b = zz; }
${FT}" "error:<source>:4:26: expected ';', got ')'
error:<source>:4:36: $UZ"
row F6 "a compound step after the missing ;: for (var i = 0; i < 3 i += 1)" "${FH}    for (var i = 0; i < 3 i += 1) { b = zz; }
${FT}" "error:<source>:4:27: expected ';', got identifier 'i'
error:<source>:4:43: $UZ"

# ---- D: a `dyn` initializer's `;` (src/frontend/parse_types.cyr)
DH='trait Show { fn show(self): i64; }
struct P { a; b; }
impl Show for P { fn show(self): i64 { return self.a; } }
'
row D1 "var o: dyn Show = &p then a return" "${DH}fn f(): i64 {
    var p = P { 1, 2 };
    var o: dyn Show = &p
    return zz;
}
syscall(60, f());
" "error:<source>:7:5: expected ';', got return
error:<source>:7:14: $UZ"
row D2 "var o: dyn Show = &p before the fn's }" "${DH}fn f(): i64 {
    var p = P { 1, 2 };
    var o: dyn Show = &p }
fn g(): i64 { return zz; }
syscall(60, f() + g());
" "error:<source>:6:26: expected ';', got '}'
error:<source>:7:24: $UZ"

row D3 "a dyn assignment o = &p before the fn's }" "${DH}fn f(): i64 {
    var p = P { 1, 2 };
    var o: dyn Show = &p;
    o = &p }
fn g(): i64 { return zz; }
syscall(60, f() + g());
" "error:<source>:7:12: expected ';', got '}'
error:<source>:8:24: $UZ"
row D4 "a dyn assignment o = &p then a return" "${DH}fn f(): i64 {
    var p = P { 1, 2 };
    var o: dyn Show = &p;
    o = &p
    return zz;
}
syscall(60, f());
" "error:<source>:8:5: expected ';', got return
error:<source>:8:14: $UZ"

# ---- E: a subscript store's `;` (src/frontend/parse_expr.cyr)
row E1 "a[0] = 1 before the fn's }" 'fn f(): i64 {
    var a: i64[4];
    a[0] = 1 }
fn g(): i64 { return zz; }
syscall(60, f() + g());
' "error:<source>:3:14: expected ';', got '}'
error:<source>:4:24: $UZ"
row E2 "a[0] = 1 then a return" 'fn f(): i64 {
    var a: i64[4];
    a[0] = 1
    return zz;
}
syscall(60, f());
' "error:<source>:4:5: expected ';', got return
error:<source>:4:14: $UZ"

# ---- T: an assignment's terminator (the `term` sites: `*p = v`, a struct copy, `a, b = f()`, a field store)
row T1 "*q = 5 before the fn's }" 'fn f(): i64 {
    var x = 0;
    var q: *i64 = &x;
    *q = 5 }
fn g(): i64 { return zz; }
syscall(60, f() + g());
' "error:<source>:4:12: expected ';', got '}'
error:<source>:5:24: $UZ"
row T2 "a struct copy *q = o then a return" 'struct P { n; m; }
fn f(): i64 {
    var p = P { 1, 2 };
    var o = P { 3, 4 };
    var q: *P = &p;
    *q = o
    return zz;
}
syscall(60, f());
' "error:<source>:7:5: expected ';', got return
error:<source>:7:14: $UZ"

row T3 "a field store p.n = 5 before the fn's }" 'struct P { n; m; }
fn f(): i64 {
    var p = P { 1, 2 };
    p.n = 5 }
fn g(): i64 { return zz; }
syscall(60, f() + g());
' "error:<source>:4:13: expected ';', got '}'
error:<source>:5:24: $UZ"
row T4 "a field store p.n = 5 then a return" 'struct P { n; m; }
fn f(): i64 {
    var p = P { 1, 2 };
    p.n = 5
    return zz;
}
syscall(60, f());
' "error:<source>:5:5: expected ';', got return
error:<source>:5:14: $UZ"
row T5 "a call's field gp().n = 5 before the fn's }" 'struct P { n; m; }
var gq = P { 1, 2 };
fn gp(): *P { return &gq; }
fn f(): i64 { gp().n = 5 }
fn g(): i64 { return zz; }
syscall(60, f() + g());
' "error:<source>:4:26: expected ';', got '}'
error:<source>:5:24: $UZ"

# ---- M: a destructure's call missing its `;` is "expected ';'", not "needs a call on the right-hand side"
row M1 "x, y = two(3) before the fn's }" 'fn two(a) { return (a, 4); }
fn f(): i64 {
    var x = 0;
    var y = 0;
    x, y = two(3) }
fn g(): i64 { return zz; }
syscall(60, f() + g());
' "error:<source>:5:19: expected ';', got '}'
error:<source>:6:24: $UZ"
row M2 "var a, b = two(3) then a return" 'fn two(a) { return (a, 4); }
fn f(): i64 {
    var a, b = two(3)
    return zz;
}
syscall(60, f());
' "error:<source>:4:5: expected ';', got return
error:<source>:4:14: $UZ"
row M3 "control: x, y = two(3) + 1; keeps its refusal" 'fn two(a) { return (a, 4); }
fn f(): i64 {
    var x = 0;
    var y = 0;
    x, y = two(3) + 1;
    return zz;
}
syscall(60, f());
' "error:<source>:5:12: multi-value destructure needs a call on the right-hand side
error:<source>:6:14: $UZ"

# ---- B: brace accounting (`_resync_close`)
row B1 "a = 2 { 3 }; then a later fn's error" 'fn f(): i64 { var a = 1; a = 2 { 3 }; return a; }
fn g(): i64 { return zz; }
syscall(60, f() + g());
' "error:<source>:1:32: expected ';', got '{'
error:<source>:2:24: $UZ"

row B2 "the same in an if block, two statements inside the braces" 'fn f(): i64 {
    var a = 1;
    if (a == 1) { a = 2 { 3; 4 } }
    return zz;
}
syscall(60, f());
' "error:<source>:3:25: expected ';', got '{'
error:<source>:4:14: $UZ"

# ---- K: the S22 control
row K1 "S22 verbatim: var P = 3; P { 5 };" 'struct P { a; }
fn run(): i64 { var P = 3; P { 5 }; return 0; }
syscall(60, run());
' "error:<source>:2:30: expected '=', got '{'"

row K2 "S22, then a later error" 'struct P { a; }
fn run(): i64 { var P = 3; P { 5 }; return zz; }
syscall(60, run());
' "error:<source>:2:30: expected '=', got '{'
error:<source>:2:46: $UZ"

row K3 "control: an unclosed literal var p = P { 1, 2; (CT4) — the } after is the fn's" 'struct P { a; b; }
fn run(): i64 { var p = P { 1, 2; return p.b; }
fn g(): i64 { return zz; }
syscall(60, run() + g());
' "error:<source>:2:33: expected '}', got ';'
error:<source>:3:24: $UZ"

echo "$G: $pass passed, $fail failed (legs: $LEGS)"
[ "$fail" -eq 0 ] || exit 1
exit 0
