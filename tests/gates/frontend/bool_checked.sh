#!/bin/sh
# tests/gates/frontend/bool_checked.sh — 6.7.3 (B2)
#
# A WRITE INTO A BOOL IS CHECKED. The user's decisions (2026-10-07): a bool variable, field,
# parameter, fn return or const accepts only a BOOLEAN value — true / false, a comparison, `!`,
# `&&` / `||`, or another bool — and everything else is refused by name, the literals 0 and 1
# included; a bool READS as the integer 0 or 1 everywhere. The runtime half is
# tests/tcyr/crossos/bool_values.tcyr.
#
#   W  each write form refused once, by name, at the value: a local's initializer (an integer,
#      arithmetic over a boolean — `+ 0`, `* 1`, `0 +`, unary minus, `~` — an untyped variable
#      holding a comparison, an f64, a struct call), plain and compound assignment, a for step
#   A  ANTI-VACUOUS: every boolean producer builds and runs, and a bool reads as 0 / 1
#   R  `true` / `false` are reserved words
#
# Mutations (scratch trees, each RED here — run 2026-10-07): `_BX_IS` answering 1 -> every W row
# BUILDS; the _PLOGIC_ATOM mark dropped -> A1 refused; `_bx_asg` a no-op -> W11 W14 BUILD.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: bool_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: bool_checked: mktemp -d failed"; exit 1; }
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
M='fn main(): i64 {'
E='\nsyscall(60, main());\n'
DI="cannot initialize bool 'b'"
AS="cannot assign a value that is not a bool to bool 'b'"
CO="compound assignment to bool 'b' is refused"

refused w01 "$DI" "W1: var b: bool = 7"            "$M var b: bool = 7; return b; }$E"
refused w02 "$DI" "W2: var b: bool = 1"            "$M var b: bool = 1; return b; }$E"
refused w03 "$DI" "W3: var b: bool = 0"            "$M var b: bool = 0; return b; }$E"
refused w04 "$DI" "W4: = n + 1"                    "$M var n = 3; var b: bool = n + 1; return b; }$E"
refused w05 "$DI" "W5: = (a < b) + 1"              "$M var a = 1; var b: bool = (a < 2) + 1; return b; }$E"
refused w06 "$DI" "W6: = -ok"                      "$M var ok: bool = true; var b: bool = -ok; return b; }$E"
refused w07 "$DI" "W7: = ok + 0 (folds, still a token)" "$M var ok: bool = true; var b: bool = ok + 0; return b; }$E"
refused w08 "$DI" "W8: = ok * 1"                   "$M var ok: bool = true; var b: bool = ok * 1; return b; }$E"
refused w09 "$DI" "W9: = 0 + ok"                   "$M var ok: bool = true; var b: bool = 0 + ok; return b; }$E"
refused w10 "$DI" "W10: = ~ok"                     "$M var ok: bool = true; var b: bool = ~ok; return b; }$E"
refused w11 "$DI" "W11: an untyped var holding a comparison" "$M var x = 3 < 4; var b: bool = x; return b; }$E"
refused w12 "$DI" "W12: = 1.5"                     "$M var b: bool = 1.5; return 0; }$E"
refused w13 "$DI" "W13: = a 24-byte struct call"   'struct Pt { x; y; z; }\nfn mk(): Pt { var p: Pt; p.x = 1; p.y = 2; p.z = 3; return p; }\nfn main(): i64 { var b: bool = mk(); return 0; }\nsyscall(60, main());\n'
refused w14 "$DI" "W14: = an 8-byte struct call"   'struct Q { a; }\nfn mq(): Q { var q: Q; q.a = 1; return q; }\nfn main(): i64 { var b: bool = mq(); return 0; }\nsyscall(60, main());\n'
refused w15 "$AS" "W15: b = 1"                     "$M var b: bool = true; b = 1; return b; }$E"
refused w16 "$AS" "W16: b = !b + 1"                "$M var b: bool = false; b = !b + 1; return 0; }$E"
refused w17 "$AS" "W17: a for step b = 5"          "$M var b: bool = true; for (var i = 0; i < 3; b = 5) { i = i + 1; } return b; }$E"
refused w18 "$CO" "W18: b += 1"                    "$M var b: bool = true; b += 1; return b; }$E"
refused w19 "$CO" "W19: b &= c (both bools)"       "$M var b: bool = false; var c: bool = true; b &= c; return b; }$E"
refused w20 "$CO" "W20: a for step b += 1"         "$M var b: bool = true; for (var i = 0; i < 3; b += 1) { i = i + 1; } return b; }$E"
GI="cannot initialize bool 'G'"
refused w21 "$GI" "W21: a static global = 1"              'var G: bool = 1;\nsyscall(60, G);\n'
refused w22 "$GI" "W22: a static global = true + 0 (folds to 1)" 'var G: bool = true + 0;\nsyscall(60, G);\n'
refused w23 "$GI" "W23: a static global = (7)"            'var G: bool = (7);\nsyscall(60, G);\n'
refused w24 "$GI" "W24: a deferred global = h()"          'fn h(): i64 { return 1; }\nvar G: bool = h();\nsyscall(60, G);\n'
refused w25 "$GI" "W25: a deferred global = 0"            'var G: bool = 0;\nsyscall(60, G);\n'
refused w26 "$GI" "W26: a global after the first statement" 'var x = 1;\nsyscall(60, 0);\nvar G: bool = 5;\n'
refused w27 "cannot assign a value that is not a bool to bool 'G'" "W27: G = 2 in a fn" 'var G: bool = true;\nfn main(): i64 { G = 2; return G; }\nsyscall(60, main());\n'
refused w28 "compound assignment to bool 'G' is refused" "W28: G += 1 in a fn" 'var G: bool = true;\nfn main(): i64 { G += 1; return G; }\nsyscall(60, main());\n'
FS="cannot store a value that is not a bool into bool field 'on'"
SP='struct P { a; on: bool; }\n'
refused w29 "$FS" "W29: p.on = 2"                 "${SP}fn main(): i64 { var p: P; p.a = 1; p.on = 2; return p.on; }$E"
refused w30 "$FS" "W30: a chain h.p.on = 5"       "${SP}struct H { n; p: P; }\nfn main(): i64 { var h: H; h.p.on = 5; return 0; }$E"
refused w31 "$FS" "W31: through a *P parameter"  "${SP}fn set(q: *P): i64 { q.on = 3; return 0; }\nfn main(): i64 { var p: P; set(&p); return 0; }$E"
refused w32 "$FS" "W32: self.on = 1 in an impl"  "${SP}impl P { fn flip(self): i64 { self.on = 1; return 0; } }\nfn main(): i64 { var p: P; p.flip(); return 0; }$E"
refused w33 "$FS" "W33: a positional literal P { 1, 2 }" "${SP}fn main(): i64 { var p = P { 1, 2 }; return p.on; }$E"
refused w34 "$FS" "W34: a named literal on: 7"   "${SP}fn main(): i64 { var p = P { a: 1, on: 7 }; return p.on; }$E"
refused w35 "$FS" "W35: a baked global literal"  "${SP}var G = P { 4, 9 };\nsyscall(60, G.on);\n"
refused w36 "$FS" "W36: a scalar carried into a nested struct's bool leaf" 'struct In { on: bool; x; }\nstruct Out { i: In; y; }\nfn main(): i64 { var o = Out { 5, 6, 7 }; return 0; }\nsyscall(60, main());\n'

exits a1 255 "A1: every boolean producer into a local (true, false, <, !, &&, ||, parens, another bool, !!, f64_lt, a for step)" "$M var a = 3; var t: bool = true; var f: bool = false; var c: bool = a < 4; var d: bool = !a; var e: bool = (a > 1) && (a < 9); var g: bool = c || d; var h: bool = (c); var i: bool = ((a == 3)); var j: bool = c; var k: bool = !!a; var l: bool = f64_lt(1.0, 2.0); t = c; t = !t; t = a != 3; t = d && c; for (var q = 0; q < 2; t = q > 0) { q = q + 1; } return t + c * 2 + e * 4 + g * 8 + h * 16 + i * 32 + j * 64 + k * 128 + l * 256 + f; }\nsyscall(60, main() % 256);\n"
exits a2 10 "A2: a bool reads as 0 / 1 (n + ok, ok * 4)" "$M var ok: bool = true; var n = 5 + ok; var m = ok * 4; return n + m; }$E"
exits a3 7 "A3: a condition still takes an integer" "$M var n = 7; if (n) { return n; } return 0; }$E"
exits a4 127 "A4: bool globals — static, deferred, parenthesised, a comparison, !, read into a local" 'var A: bool = true;\nvar B: bool = false;\nvar C: bool = (true);\nvar D: bool = 3 < 4;\nfn h(): i64 { return 1; }\nvar E: bool = h() == 1;\nvar F: bool = !0;\nfn main(): i64 { var l: bool = A; B = A && D; return A + B * 2 + C * 4 + D * 8 + E * 16 + F * 32 + l * 64; }\nsyscall(60, main());\n'
exits a6 255 "A6: bool fields — a store, a chain, literals, a global literal, self, a method reading one" 'struct P { a; on: bool; }\nstruct H { n; p: P; }\nimpl P { fn flip(self): i64 { self.on = !self.on; return 0; } fn is(self): i64 { var b: bool = self.on; return b; } }\nvar G = P { 4, true };\nfn main(): i64 { var p: P; p.a = 1; p.on = p.a > 0; var q = P { a: 2, on: false }; var r = P { 3, (1 < 2) }; var h: H; h.p.on = true; var l: bool = p.on; q.flip(); var m: bool = q.on && r.on; return p.on + q.on * 2 + r.on * 4 + h.p.on * 8 + l * 16 + m * 32 + G.on * 64 + p.is() * 128; }\nsyscall(60, main() % 256);\n'
exits a5 0 "A5: a global after the first statement takes a comparison" 'var x = 1;\nsyscall(60, 0);\nvar G: bool = x > 0;\n'

refused r1 "reserved keyword 'true'"  "R1: var true"  'var true = 1;\nsyscall(60, 1);\n'
refused r2 "reserved keyword 'false'" "R2: fn false" 'fn false(): i64 { return 0; }\nsyscall(60, 1);\n'

if [ "$fails" -ne 0 ]; then echo "FAIL: bool_checked — $fails row(s) red"; exit 1; fi
echo "PASS: bool_checked — every write into a bool takes a boolean value (W), every boolean producer runs and a bool reads as 0 / 1 (A), true / false are reserved (R)"
