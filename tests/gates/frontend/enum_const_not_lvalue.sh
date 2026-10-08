#!/bin/sh
# tests/gates/frontend/enum_const_not_lvalue.sh — 6.7.3 (the repair lane)
#
# AN ENUM CONSTANT IS NOT AN LVALUE (user, 2026-10-07): `A = ..`, `A OP= ..` and `&A` are refused
# by name, as 6.7.2 refuses them on a `const`. Before 6.7.3 all three compiled: every read folds to
# the declared value, so the write changed nothing, and `&A` handed out the variant's 8-byte slot.
#
#   N  refused once, by name: plain / compound assignment and `&` in a fn and at top level, the
#      classic-for step (plain and compound), the qualified spelling (`E.A = ..`, `E.A += ..`,
#      `&E.A`), a payload variant (`&Ctor` was the variant's slot, never the constructor)
#   C  ANTI-VACUOUS: a local, a closure capture and a later top-level `var` of the same name stay
#      variables; reads of `A` / `E.A` are unchanged
#
# Mutations (scratch trees, each RED here — run 2026-10-07): the stock 6.7.3 compiler -> N1-N7,
# N11, N12 BUILD and N8-N10 refused only as "undefined variable 'E'"; `_enum_lv_refuse` answering
# 0 -> N1-N9, N11, N12 BUILD; `_asg_lvalue_refused` without its local early-out -> C1 refused;
# `_addr_lvalue_refused` without the closure-capture rung -> C2 refused; `_for_step_assign`
# without its check -> N6, N7 BUILD (and const_checked's L5, L6).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: enum_const_not_lvalue: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: enum_const_not_lvalue: mktemp -d failed"; exit 1; }
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
    chmod +x "$T/$1.bin"; got=0; "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
AS="cannot assign to enum constant 'A'"
AD="cannot take the address of enum constant 'A'"
EN='enum E { A = 5; }\n'
refused n1 "$AS" "N1: A = 6 in a fn" "${EN}"'fn main(): i64 { A = 6; return A; }\nsyscall(60, main());\n'
refused n2 "$AS" "N2: A += 1 in a fn" "${EN}"'fn main(): i64 { A += 1; return A; }\nsyscall(60, main());\n'
refused n3 "$AD" "N3: &A in a fn" "${EN}"'fn main(): i64 { var p = &A; return 0; }\nsyscall(60, main());\n'
refused n4 "$AS" "N4: A = 6 at top level" "${EN}"'A = 6;\nsyscall(60, A);\n'
refused n5 "$AD" "N5: &A at top level" "${EN}"'var p = &A;\nsyscall(60, 0);\n'
refused n6 "$AS" "N6: a for step A = A + 1" "${EN}"'fn main(): i64 { var n = 0; for (var i = 0; i < 3; A = A + 1) { i = i + 1; n = n + 1; } return n; }\nsyscall(60, main());\n'
refused n7 "$AS" "N7: a for step A += 1" "${EN}"'fn main(): i64 { var n = 0; for (var i = 0; i < 3; A += 1) { i = i + 1; n = n + 1; } return n; }\nsyscall(60, main());\n'
refused n8 "$AS" "N8: E.A = 6" "${EN}"'fn main(): i64 { E.A = 6; return E.A; }\nsyscall(60, main());\n'
refused n9 "$AS" "N9: E.A += 1" "${EN}"'fn main(): i64 { E.A += 1; return E.A; }\nsyscall(60, main());\n'
refused n10 "$AD" "N10: &E.A" "${EN}"'fn main(): i64 { var p = &E.A; return 0; }\nsyscall(60, main());\n'
refused n11 "cannot take the address of enum constant 'Okv'" "N11: &Okv of a payload variant" 'include "lib/alloc.cyr"\nenum R { Okv(v); Errv(e); }\nfn main(): i64 { var p = &Okv; return 0; }\nsyscall(60, main());\n'
refused n12 "cannot assign to enum constant 'Sv'" "N12: Sv = 3 on a stack-enum variant" 'enum S: stack { Sv(x); Sn(); }\nfn main(): i64 { Sv = 3; return 0; }\nsyscall(60, main());\n'

exits c1 8 "C1: a local named like an enum constant is a variable" "${EN}"'fn main(): i64 { var A = 1; A = 7; A += 1; var p = &A; return load64(p); }\nsyscall(60, main());\n'
exits c2 10 "C2: &A in a closure is the capture" 'include "lib/alloc.cyr"\n'"${EN}"'fn main(): i64 { var A = 1; var c = |x| { var p = &A; return load64(p) + x; }; return fncall1(c, 9); }\nsyscall(60, main());\n'
exits c3 88 "C3: a later top-level var A is a variable (last definition wins)" "${EN}"'var A = 3;\nfn main(): i64 { A = 7; A += 1; var p = &A; return load64(p) * 10 + A; }\nsyscall(60, main());\n'
exits c4 15 "C4: reads of A and E.A, an array size, a for step on a var" "${EN}"'var g[A];\nfn main(): i64 { var s = 0; for (var i = 0; i < E.A; i += 1) { s = s + 1; } return s + A + E.A; }\nsyscall(60, main());\n'

if [ "$fails" -ne 0 ]; then echo "FAIL: enum_const_not_lvalue — $fails row(s) red"; exit 1; fi
echo "PASS: enum_const_not_lvalue — an enum constant is not an lvalue (N: =, OP=, & — bare, qualified, top level, a for step), and its namesakes stay variables (C)"
