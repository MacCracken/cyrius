#!/bin/sh
# Gate: a `.field` on a CALL RESULT is refused by name wherever it cannot be compiled (6.6.12, R3).
#
# 6.6.12 made `f(mk(p).n)`, `var r = mkp(3).y;` and `mk(p).v.x + 1` compile inside a fn: the
# result lands in a frame temp and the field is loaded from it (`_call_field`,
# src/frontend/parse_expr.cyr). The acceptance rows live in
# tests/tcyr/crossos/generic_struct_inference.tcyr (CF). This gate pins the other half, the
# shapes that must NOT compile, each on its MESSAGE and on no binary being written, so a row
# cannot pass on an unrelated syntax error (every one of these was "expected ';', got '.'" or
# "expected ')', got '.'" on 6.6.11, which this gate would report as not refused):
#
#   T1-T5  AT TOP LEVEL there is no frame to hold the result, for any return class: a register
#          pair (`var G = mkpt(3).y;`), rax (`1 + mk8(2).a`), the retptr (`plus1(mk3(1).a);`),
#          the leading declaration block (`var G = mk3(2).b;` before the first statement) and a
#          struct-typed initialiser (`var G: Pt = mkpt(1).x;`). T3-T5 must be the ONLY error: on
#          6.6.11 T4 and T5 were refused too, but by the call itself, followed by the syntax error.
#   T6/T7  a METHOD on the result at top level — as a bare statement (`mk8(2).bump();`) and as
#          an initialiser (`var G = mk8(2).bump();`) — is refused once: the method's `(..)` is
#          skipped with the refused call, not reported again as "expected ';', got '('". T6 is
#          also the statement position itself, which PARSE_STMT sent to PARSE_FNCALL, so the `.`
#          was "expected ';', got '.'" (the 6.6.12 review find, `_stmt_call_field`).
#   A1     `mk8(1).a = 5;` in a fn: a field of a temporary is not an lvalue — named, exactly once.
#   N1     the callee returns no struct (`plain(3).y`): named, not a syntax error.
#   M1/M2  a struct-typed field of the result into a destination of a DIFFERENT struct type: a
#          `var q: Pt` declaration and a by-value `ptv(p: Pt)` argument, refused by name like the
#          named-receiver forms `var q: Pt = b.q` / `ptv(b.q)`.
#   R1/R2  `return mk3(1).a;` from a `: P3` fn and `return mkpt(1).x;` from a `: Pt` fn get the
#          struct-return diagnostic, not a syntax error (the whole-call return paths now step
#          aside for a call followed by `.field`).
#   S1/S2  --syntax-only (the `cyrius lint` pre-pass): a field of a call to a fn it cannot
#          resolve is NOT a syntax error (S1), and the call's arguments are still parsed, so a
#          grammar error inside them is still reported (S2).
#   G1/G2  (R2) an EXPLICIT generic call as a bare statement at top level, struct-returning
#          (`mkg<i32>(1);`, `mkg<i32>(1).a;`), is refused by name exactly as `mk3(1);` is — it was
#          "expected '=', got '<'" plus two follow-on errors on 6.6.11.
#   G3     (R2) `mu<i32>(3);` on a `#must_use` generic warns that the result is discarded, as the
#          `IDENT (` statement does — and still compiles.
#   C1-C3  (6.6.17) a chain on a METHOD's result (`p.bump().sum()`; acceptance rows in
#          tests/tcyr/crossos/method_chain.tcyr): at top level, as an initialiser (C1) and as a
#          bare statement (C2), refused once with the rest of the chain skipped; in a fn, on a
#          method that returns no struct (C3), named. On 6.6.16 all three were "expected ';' /
#          ')', got '.'".
#
# MUTATION LEDGER (6.6.12, scratch trees, each rebuilt with the one change):
#   base 6.6.11 build/cycc                                  -> RED, 14 of 15 (S2 was already right)
#   `_call_field` without its top-level refusal             -> RED T1..T5 (a binary is emitted)
#   `_call_field` returning 0 for an unresolved callee      -> RED S1
#     under --syntax-only
#   `_call_field` skipping (not parsing) the arguments      -> RED S2
#     under --syntax-only
#   `_return_struct_call` without its `_call_dotted`        -> RED R1 (the syntax error)
#     step-aside
#   `_pair_ret_call_ok` without it                          -> RED R2 — and SILENT: the pair
#     return took `mkpt(1)` whole and a binary was emitted
#   `_refuse_toplevel_pair_init` without it                 -> RED T5 (two errors)
#   no `_stmt_call_field` call in PARSE_STMT (src/frontend/ -> RED T6, A1 ("expected ';', got '.'")
#     parse.cyr)
#   `_call_field`'s refusal not skipping a method's `(..)`   -> RED T6, T7 (two errors)
#   no `_stmt_explicit_generic` call in PARSE_STMT          -> RED G1, G2, G3
#   `_stmt_explicit_generic` without `_must_use_warn`       -> RED G3
#   real tree                                               -> GREEN
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: mktemp -d failed"; exit 77; }
trap 'rm -rf "$D"' EXIT

MT="returns a struct by value, and a struct result needs storage in a fn's frame"
pass=0; fail=0

# $1 label  $2 expected message  $3 source  [$4 compiler flag]  [$5 "one" = exactly one error line]
refuse() {
    printf '%s' "$3" > "$D/r.cyr"
    rc=0
    if [ -n "${4:-}" ]; then
        cat "$D/r.cyr" | "$CC" "$4" > "$D/r.bin" 2>"$D/r.err" || rc=$?
    else
        cat "$D/r.cyr" | "$CC" > "$D/r.bin" 2>"$D/r.err" || rc=$?
    fi
    if ! grep -q -- "$2" "$D/r.err" 2>/dev/null; then
        printf '  FAIL: %-6s not refused (rc=%s, first line: %s)\n' \
            "$1" "$rc" "$(grep -v '^note' "$D/r.err" 2>/dev/null | head -1 || echo '(no output)')"
        fail=$((fail+1)); return
    fi
    if [ -s "$D/r.bin" ]; then
        printf '  FAIL: %-6s reported but still emitted a binary\n' "$1"; fail=$((fail+1)); return
    fi
    if [ "${5:-}" = "one" ]; then
        n=$(grep -c '^error:' "$D/r.err" || true)
        if [ "$n" != "1" ]; then
            printf '  FAIL: %-6s %s error lines, want exactly 1\n' "$1" "$n"; fail=$((fail+1)); return
        fi
    fi
    printf '  ok(refused): %s\n' "$1"; pass=$((pass+1))
}

T='struct P8 { a: i32; b: i8; }
struct Pt { x; y; }
struct P3 { a; b; c; }
struct Q8 { z; }
struct BQ { q: Q8; k; w; }
fn mk8(a): P8 { var p: P8; p.a = a; p.b = 1; return p; }
fn mkpt(a): Pt { var p: Pt; p.x = a; p.y = 5; return p; }
fn mk3(a): P3 { var r: P3; r.a = a; r.b = a + 1; r.c = a + 2; return r; }
fn mkbq(a): BQ { var b: BQ; b.q.z = a; b.k = 1; b.w = 2; return b; }
fn plus1(a): i64 { return a + 1; }
fn plain(a): i64 { return a; }
fn ptv(p: Pt): i64 { return p.x; }
fn P8_bump(self: P8): i64 { return self.a; }
fn mkg<T>(a: T): P3 { var r: P3; r.a = a; r.b = 1; r.c = 2; return r; }
'

echo "top level — no frame for the result:"
refuse T1 "'mkpt' $MT" "${T}var r = 0; syscall(60, r);
var G = mkpt(3).y;
"
refuse T2 "'mk8' $MT" "${T}var r = 0; syscall(60, r);
var H = 1 + mk8(2).a;
"
refuse T3 "'mk3' $MT" "${T}var r = 0;
plus1(mk3(1).a);
syscall(60, r);
" "" one
refuse T4 "'mk3' $MT" "${T}var G = mk3(2).b;
fn main(): i64 { return G; }
var r = main(); syscall(60, r);
" "" one
refuse T5 "'mkpt' $MT" "${T}var G: Pt = mkpt(1).x;
var r = 0; syscall(60, r);
" "" one

refuse T6 "'mk8' $MT" "${T}var r = 0;
mk8(2).bump();
syscall(60, r);
" "" one
refuse T7 "'mk8' $MT" "${T}var G = mk8(2).bump();
var r = 0; syscall(60, r);
" "" one

echo "top level — an explicit generic call as a bare statement (R2):"
refuse G1 "'mkg\$i32' $MT" "${T}var r = 0;
mkg<i32>(1);
syscall(60, r);
" "" one
refuse G2 "'mkg' $MT" "${T}var r = 0;
mkg<i32>(1).a;
syscall(60, r);
" "" one
printf '%s' "${T}#must_use
fn mu<T>(x: T): T { return x; }
fn m(): i64 { mu<i32>(3); return 0; }
var r = m(); syscall(60, r);
" > "$D/g3.cyr"
rc=0; cat "$D/g3.cyr" | "$CC" > "$D/g3.bin" 2>"$D/g3.err" || rc=$?
if [ "$rc" = 0 ] && grep -q "^warning:<source>:17:17: #must_use result of 'mu' is discarded" "$D/g3.err"; then
    printf '  ok(warned): G3\n'; pass=$((pass+1))
else
    printf '  FAIL: G3     no #must_use warning on `mu<i32>(3);` (rc=%s, first line: %s)\n' "$rc" "$(head -1 "$D/g3.err")"
    fail=$((fail+1))
fi

echo "a chain on a method's result (6.6.17):"
refuse C1 "'Pt_two' $MT" "${T}fn Pt_two(self: Pt): Pt { return mkpt(2); }
fn Pt_sx(self: Pt): i64 { return self.x; }
var gp = Pt { 1, 2 };
var G = gp.two().sx();
var r = 0; syscall(60, r);
" "" one
refuse C2 "'Pt_two' $MT" "${T}fn Pt_two(self: Pt): Pt { return mkpt(2); }
fn Pt_sx(self: Pt): i64 { return self.x; }
var gp = Pt { 1, 2 };
var r = 0;
gp.two().two().sx();
syscall(60, r);
" "" one
refuse C3 "cannot take a field of the result of 'Pt_sx': it does not return a struct" "${T}fn Pt_sx(self: Pt): i64 { return self.x; }
fn m(): i64 { var p = Pt { 1, 2 }; return p.sx().y; }
var r = m(); syscall(60, r);
" "" one

echo "in a fn — named refusals:"
refuse A1 "cannot assign to a field of a call result: the result is a temporary" "${T}fn m(): i64 { mk8(1).a = 5; return 0; }
var r = m(); syscall(60, r);
" "" one
refuse N1 "cannot take a field of the result of 'plain': it does not return a struct" "${T}fn m(): i64 { var r = plain(3).y; return r; }
var r = m(); syscall(60, r);
"
refuse M1 "cannot copy 'q' into a variable of a different struct" "${T}fn m(): i64 { var q: Pt = mkbq(1).q; return q.x; }
var r = m(); syscall(60, r);
"
refuse M2 "cannot pass 'q' to a parameter of a different struct type in a call to 'ptv'" "${T}fn m(): i64 { return ptv(mkbq(1).q); }
var r = m(); syscall(60, r);
"
refuse R1 "struct-return fn: return must be a bare local identifier" "${T}fn f3(): P3 { return mk3(1).a; }
var r = 0; syscall(60, r);
"
refuse R2 "is returned in two registers, so \`return\` takes a local of that struct or a call returning it" "${T}fn fp(): Pt { return mkpt(1).x; }
var r = 0; syscall(60, r);
"

echo "--syntax-only (the lint pre-pass):"
printf '%s' 'fn main(): i64 {
    var r = other(3).y + mkq(1).v.w;
    take(other(2).z, 3);
    return r;
}
' > "$D/s1.cyr"
cat "$D/s1.cyr" | "$CC" --syntax-only > "$D/s1.bin" 2>"$D/s1.err" || true
if grep -q "expected\|unexpected" "$D/s1.err"; then
    printf '  FAIL: S1     a field of an unresolved call read as a syntax error: %s\n' "$(grep "expected" "$D/s1.err" | head -1)"
    fail=$((fail+1))
else
    printf '  ok(silent): S1\n'; pass=$((pass+1))
fi
printf '%s' 'fn main(): i64 {
    var r = other(3 +).y;
    return r;
}
' > "$D/s2.cyr"
cat "$D/s2.cyr" | "$CC" --syntax-only > "$D/s2.bin" 2>"$D/s2.err" || true
if grep -q "unexpected ')'" "$D/s2.err"; then
    printf '  ok(reported): S2\n'; pass=$((pass+1))
else
    printf '  FAIL: S2     the grammar error inside the arguments was not reported\n'; fail=$((fail+1))
fi

echo "call_result_field: $pass passed, $fail failed"
[ "$pass" -ge 18 ] || { echo "FAIL: call_result_field: only $pass of the 18 rows passed"; exit 1; }
[ "$fail" -eq 0 ]
