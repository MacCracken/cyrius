#!/bin/sh
# tests/gates/frontend/if_expr_checked.sh — 6.7.4 (B3)
#
# THE IF-EXPRESSION. The user's decisions (2026-10-08): `if (c) { a } elif (d) { b } else { e }` where
# an expression is parsed; ONE expression per branch, `else` required, only the taken branch runs;
# every branch the same kind — integer (pointers and bools included), f64, f32, or one struct type of
# 8 bytes or less (the result keeps it); a struct value over 8 bytes refused; anywhere an expression
# goes, const contexts included. The runtime half is tests/tcyr/crossos/if_expr_values.tcyr.
#
#   R  refused once, by name, at the right token
#   A  ANTI-VACUOUS: built and run — values, only the taken branch, the join's flag / fold resets
#   C  const contexts: the compile-time evaluator runs the taken arm, walks the rest
#
# Mutations (scratch trees, each RED here — run 2026-10-08): the join's `_flags_reflect_rax = 0`
# removed -> A4; every `_cfo` clear at the join removed (the helper's and both PARSE_INTRIN callers')
# -> A5; the final `_BX_MARK` dropped -> A8; the `_FBR_MARK` at the join dropped -> A6; the merge
# accepting every kind -> R8-R11 R17 R18 BUILD; the struct classifier answering "a word" -> R12-R18;
# `else` optional -> R1 R2; the `;` check dropped -> R3; the evaluator running every arm -> C1 C2
# (`1 / 0` faults, a false cycle); `_cst_kind_peek` answering 0 for an unevaluated const -> R24 C3;
# the deferred re-check removed -> R24 BUILDS. (The three peephole-tracker resets and the
# SESVAR / `_esv_name` reset are defensive: no row kills them.)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: if_expr_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: if_expr_checked: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() {   # <name> <message fragment> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}
exits() {   # <name> <want> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
E='\nsyscall(60, f(1));\n'
MIX="if expression branches differ in type"
BIG="an if expression branch cannot be a struct value over 8 bytes"

refused r01 "an if expression needs an else" "R1: no else"            "fn f(c): i64 { var x = if (c) { 1 }; return x; }$E"
refused r02 "an if expression needs an else" "R2: elif, no else"      "fn f(c): i64 { var x = if (c) { 1 } elif (c > 1) { 2 }; return x; }$E"
refused r03 "holds one expression, without ';'" "R3: a ';' in a branch" "fn f(c): i64 { var x = if (c) { 1; } else { 2 }; return x; }$E"
refused r04 "takes one expression, not a statement" "R4: a var in a branch" "fn f(c): i64 { var x = if (c) { var t = 1 } else { 2 }; return x; }$E"
refused r05 "takes one expression, not a statement" "R5: a return in a branch" "fn f(c): i64 { var x = if (c) { return 1 } else { 2 }; return x; }$E"
refused r06 "an if expression branch needs a value" "R6: an empty branch" "fn f(c): i64 { var x = if (c) { } else { 2 }; return x; }$E"
refused r07 "holds a value, not an assignment" "R7: an assignment in a branch" "fn f(c): i64 { var y = 0; var x = if (c) { y = 1 } else { 2 }; return x; }$E"
refused r08 "$MIX: an integer here, an f64 before it" "R8: f64 then an integer" "fn f(c): i64 { var x = if (c) { 1.5 } else { 2 }; return 0; }$E"
refused r09 "$MIX: an f64 here, an integer before it" "R9: an integer then f64_sqrt(..)" "fn f(c): i64 { var x = if (c) { 2 } else { f64_sqrt(4.0) }; return 0; }$E"
refused r10 "$MIX: an f32 here, an f64 before it" "R10: f64 then f32_from(..)" "fn f(c): i64 { var x = if (c) { 1.5 } else { f32_from(2) }; return 0; }$E"
refused r11 "declare it \`: f64\`" "R11: an untyped float variable is an integer (the note)" "fn f(c): i64 { var u = 1.5; var x = if (c) { u } else { 2.5 }; return 0; }$E"
refused r12 "$BIG: struct 'Big'" "R12: a 24-byte struct local" 'struct Big { a; b; c; }\nfn f(c): i64 { var p: Big; var x = if (c) { p } else { 0 }; return 0; }\nsyscall(60, f(1));\n'
refused r13 "$BIG: struct 'Big'" "R13: a 24-byte struct call" 'struct Big { a; b; c; }\nfn mk(): Big { var p: Big; p.a = 1; p.b = 2; p.c = 3; return p; }\nfn f(c): i64 { var x = if (c) { 0 } else { mk() }; return 0; }\nsyscall(60, f(1));\n'
refused r14 "$BIG: struct 'Big'" "R14: a parenthesised 24-byte struct (p)" 'struct Big { a; b; c; }\nfn f(c): i64 { var p: Big; var x = if (c) { (p) } else { 0 }; return 0; }\nsyscall(60, f(1));\n'
refused r15 "$BIG: struct 'P16'" "R15: a 16-byte struct field" 'struct P16 { a; b; }\nstruct H { k; p: P16; }\nfn f(c): i64 { var h: H; var x = if (c) { h.p } else { 0 }; return 0; }\nsyscall(60, f(1));\n'
refused r16 "cannot be a vector or u128 value" "R16: an f64v2 local" "fn f(c): i64 { var v: f64v2; var x = if (c) { v } else { 0 }; return 0; }$E"
refused r17 "$MIX: struct 'T1' here, struct 'S1' before it" "R17: two small struct types" 'struct S1 { v; }\nstruct T1 { w; }\nfn f(c): i64 { var a: S1; a.v = 1; var t: T1; t.w = 2; var z = if (c) { a } else { t }; return 0; }\nsyscall(60, f(1));\n'
refused r18 "$MIX: an integer here, struct 'S1' before it" "R18: a small struct and an integer" 'struct S1 { v; }\nfn f(c): i64 { var a: S1; a.v = 1; var z = if (c) { a } else { 0 }; return 0; }\nsyscall(60, f(1));\n'
refused r19 "cannot initialize bool 'b'" "R19: an integer branch into a bool (B2)" "fn f(c): i64 { var b: bool = if (c) { 1 } else { false }; return b; }$E"
refused r20 "a \`: stack\` enum returns two values" "R20: a value-form pair" 'enum R : stack { Ok(v); Err(e); }\nfn f(c): i64 { var x = if (c) { Ok(1) } else { 0 }; return 0; }\nsyscall(60, f(1));\n'
refused r21 "an if expression needs an else" "R21: a const with no else" 'const X = if (1) { 1 };\nsyscall(60, 0);\n'
refused r22 "$MIX: an integer here, an f64 before it" "R22: a const mixing f64 and an integer" 'const X = if (1) { 1.5 } else { 2 };\nsyscall(60, 0);\n'
refused r23 "$MIX: an integer here, a string before it" "R23: a const mixing a string and an integer" 'const S = if (1) { "a" } else { 0 };\nsyscall(60, 0);\n'
refused r24 "$MIX: an f64 here, an integer before it" "R24: an untaken arm's forward f64 const (re-checked when every const is known)" 'const A = if (true) { 1 } else { B };\nconst B = 2.5;\nsyscall(60, A);\n'
refused r25 "$MIX: an integer here, an f64 before it" "R25: a const fn body's mix is reported once (by the parser)" 'const fn g(x) { return if (x) { 1.5 } else { 2 }; }\nsyscall(60, 0);\n'
refused r26 "holds one expression, without ';'" "R26: a ';' in a const's branch" 'const X = if (1) { 1; } else { 2 };\nsyscall(60, 0);\n'

exits a01 35  "A1: if / else, both ways"          "fn f(c): i64 { return if (c) { 3 } else { 5 }; }\nsyscall(60, f(1) * 10 + f(0));\n"
exits a02 100 "A2: an elif chain"                  "fn g(n): i64 { return if (n == 0) { 10 } elif (n == 1) { 20 } elif (n == 2) { 30 } else { 40 }; }\nsyscall(60, g(0) + g(1) + g(2) + g(7));\n"
exits a03 212 "A3: only the taken branch runs"     'var cnt = 0;\nfn bump(v): i64 { cnt = cnt + 1; return v; }\nfn h(c): i64 { return if (c) { bump(1) } else { bump(2) }; }\nfn main(): i64 { var a = h(1); var b = h(0); return cnt * 100 + a * 10 + b; }\nsyscall(60, main() % 256);\n'
exits a04 33  "A4: an if-expression as a condition (the join resets the flags)" "fn f(c, x, y, z): i64 { if (if (c) { x } else { y + z }) { return 7; } return 3; }\nsyscall(60, f(1, 0, 5, 6) * 10 + f(0, 1, 0, 0));\n"
exits a05 43  "A5: a literal branch then + 3 (no fold across the join)" "fn g(c): i64 { return if (c) { 1 } else { 0 } + 3; }\nsyscall(60, g(1) * 10 + g(0));\n"
exits a06 86  "A6: float-builtin branches keep the float flag (f64_sqrt * 2)" "fn f(c, a, b): i64 { return f64_to(if (c) { f64_sqrt(a) } else { f64_sqrt(b) } * f64_from(2)); }\nsyscall(60, f(1, f64_from(16), f64_from(9)) * 10 + f(0, f64_from(16), f64_from(9)));\n"
exits a07 35  "A7: typed f64 branches"             "fn f(c): i64 { var x: f64 = if (c) { 1.5 } else { 2.5 }; return f64_to(x * 2.0); }\nsyscall(60, f(1) * 10 + f(0));\n"
exits a08 10  "A8: a bool result (B2)"             "fn f(c, n): i64 { var b: bool = if (c) { n > 0 } else { false }; return b; }\nsyscall(60, f(1, 5) * 10 + f(0, 5) + f(1, 0) * 100);\n"
exits a09 33  "A9: pointer branches"               "fn f(c): i64 { var a = 11; var b = 22; var p = if (c) { &a } else { &b }; return load64(p); }\nsyscall(60, f(1) + f(0));\n"
exits a10 49  "A10: a small struct keeps its type" 'struct S1 { v; }\nfn mk(n): S1 { var s: S1; s.v = n; return s; }\nfn f(c): i64 { var a = mk(4); var b = mk(9); var z: S1 = if (c) { a } else { b }; return z.v; }\nsyscall(60, f(1) * 10 + f(0));\n'
exits a11 104 "A11: ... and dispatches its operator" 'struct S1 { v; }\nfn mk(n): S1 { var s: S1; s.v = n; return s; }\nfn S1_add(a: S1, b: S1): S1 { var r: S1; r.v = a.v + b.v; return r; }\nfn f(c): i64 { var a = mk(4); var b = mk(9); var z: S1 = if (c) { a } else { b } + mk(100); return z.v; }\nsyscall(60, f(1));\n'
exits a12 92  "A12: as the 7th argument"           "fn f7(a, b, c, d, e, g, h): i64 { return a + h; }\nfn f(c): i64 { return f7(1, 2, 3, 4, 5, 6, if (c) { 40 } else { 50 }); }\nsyscall(60, f(1) + f(0));\n"
exits a13 111 "A13: nested if-expressions"         "fn f(c): i64 { return if (c) { if (c > 1) { 100 } else { 10 } } else { 1 }; }\nsyscall(60, f(2) + f(1) + f(0));\n"
exits a14 7   "A14: a global initializer"          'var A = 3;\nvar G = if (A > 2) { 7 } else { 9 };\nsyscall(60, G);\n'
exits c01 249 "C1: every const context — consts, an elif const, an array size, #assert, an enum value, a recursive const fn, an untaken 1 / 0, a bool const, a string const, a local const, a case label" 'const D = 1;\nconst X = if (D) { 10 } else { 20 };\nconst Y = if (D == 0) { 1 } elif (D == 1) { 2 } else { 3 };\nvar arr: i64[if (D) { 4 } else { 8 }];\n#assert X == 10\nenum E { EA = if (D) { 5 } else { 6 }; }\nconst fn fact(n) { return if (n <= 1) { 1 } else { n * fact(n - 1) }; }\nconst F = fact(5);\nconst Z = if (D) { 7 } else { 1 / 0 };\nconst B = if (D) { true } else { false };\nconst S = if (D) { "dbg" } else { "rel" };\nfn main(): i64 { const L = if (X > 5) { 3 } else { 4 }; var b: bool = B; var s = 0; switch (2) { case if (D) { 2 } else { 3 }: s = 1; default: s = 0; } return X + Y + EA + F + Z + L + b + s + load8(S); }\nsyscall(60, main() % 256);\n'
exits c02 2 "C2: an untaken arm naming a forward const is no cycle" 'const A = if (true) { 1 } else { B };\nconst B = A;\nsyscall(60, A + B);\n'
exits c03 3 "C3: an untaken arm's forward const of the same kind" 'const A = if (true) { 1.5 } else { B };\nconst B = 2.5;\nfn main(): i64 { return f64_to(A * 2.0); }\nsyscall(60, main());\n'
exits a15 3   "A15: a statement-start if is still the if statement" "fn f(c): i64 { var r = 0; if (c) { r = 3; } else { r = 4; } return r; }$E"

if [ "$fails" -ne 0 ]; then echo "FAIL: if_expr_checked — $fails row(s) red"; exit 1; fi
echo "PASS: if_expr_checked — the if-expression's refusals (R) and its values (A)"
