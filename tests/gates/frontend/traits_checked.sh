#!/bin/sh
# tests/gates/frontend/traits_checked.sh — 6.7.0 (arcs A1, A2)
#
# `impl X for T` IS CHECKED AGAINST `trait X`, AND AN AMBIGUOUS PLAIN NAME IS REFUSED.
#
# Before 6.7.0 there was no `trait` keyword: PARSE_IMPL skipped the trait name unread, so
# `impl NoSuchTrait for P` compiled, a method no trait declared compiled, and two traits giving P a
# `size` both became `P_size` (a duplicate-fn warning, the last one bound). Now every error names
# the trait. The runtime half (defaults, qualified names, the collision rules) is
# tests/tcyr/crossos/traits_checked.tcyr.
#
#   A  each refusal, once, with its message: an undeclared trait, a method the trait does not
#      declare, a different parameter count, a required method left out, a trait declared twice,
#      a method declared twice, a non-`fn` member, a member with neither `;` nor a body
#   B  an ambiguous plain name: `p.size()` is refused AT the call naming a qualified spelling;
#      the direct `P_size(p)` fails with the same explanation on its undefined-function report
#   C  ANTI-VACUOUS: a well-formed trait + impls + defaults + qualified calls build and run, a
#      trait declared BELOW its impl included; and a program with no trait at all is untouched
#   D  `trait` is a reserved word: `var trait = 1;` is refused by name
#
# Mutations: make `_tr_check_impl` return at entry -> A1-A4 RED (they build). Make `_tr_prepass`
# skip traits -> A1 fires for every impl and C RED. Drop the FINDFN fallback -> C RED (P_Show_show
# undefined). Drop `_tr_undef_note` -> B2 RED (no note).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: traits_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: traits_checked: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() {   # <name> <message fragment> <what>
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1)"
    else ok "$3: refused once"; fi
}
exits() {   # <name> <want> <what>
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep -E '^(error|warning: undefined)' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
H='include "lib/syscalls.cyr"
struct P { x; }
'
# ── A ──
printf "$H"'impl Nope for P { fn a(self): i64 { return 1; } }\nsyscall(60, 0);\n' > "$T/a1.cyr"
refused a1 "impl of undeclared trait 'Nope' for 'P'" "A1: an undeclared trait"
printf "$H"'trait T { fn a(self): i64; }\nimpl T for P { fn a(self): i64 { return 1; } fn b(self): i64 { return 2; } }\nsyscall(60, 0);\n' > "$T/a2.cyr"
refused a2 "method 'b' is not declared in trait 'T'" "A2: a method the trait does not declare"
printf "$H"'trait T { fn a(self, k): i64; }\nimpl T for P { fn a(self): i64 { return 1; } }\nsyscall(60, 0);\n' > "$T/a3.cyr"
refused a3 "method 'a' takes a different number of parameters than its declaration in trait 'T'" "A3: a different parameter count"
printf "$H"'trait T { fn a(self): i64; fn b(self): i64; }\nimpl T for P { fn a(self): i64 { return 1; } }\nsyscall(60, 0);\n' > "$T/a4.cyr"
refused a4 "impl is missing method 'b', required by trait 'T'" "A4: a required method left out"
printf "$H"'trait T { fn a(self): i64; }\ntrait T { fn b(self): i64; }\nsyscall(60, 0);\n' > "$T/a5.cyr"
refused a5 "duplicate trait 'T'" "A5: a trait declared twice"
printf "$H"'trait T { fn a(self): i64; fn a(self): i64; }\nsyscall(60, 0);\n' > "$T/a6.cyr"
refused a6 "duplicate method 'a' in trait 'T'" "A6: a method declared twice"
printf "$H"'trait T { var x = 1; fn a(self): i64; }\nsyscall(60, 0);\n' > "$T/a7.cyr"
refused a7 "a trait body holds only \`fn\` declarations - in trait 'T'" "A7: a non-fn member"
printf "$H"'trait T { fn a(self): i64 }\nsyscall(60, 0);\n' > "$T/a8.cyr"
refused a8 "ends with ';' (required) or a body (a default)" "A8: a member with neither ; nor a body"

# ── B ──
B='trait A { fn size(self): i64; }
trait B { fn size(self): i64; }
impl A for P { fn size(self): i64 { return 1; } }
impl B for P { fn size(self): i64 { return 2; } }
'
printf "$H$B"'fn main(): i64 { var p = P { 0 }; return p.size(); }\nsyscall(60, main());\n' > "$T/b1.cyr"
build b1
# The method call reports at its site; the backend's undefined-function refusal follows it (one
# reported call, two lines), so this row asks for the site error and a failed compile.
if [ "$rc" -eq 0 ]; then bad "B1: p.size() with two traits BUILT"
elif grep -q "^error:<source>:[0-9]*:[0-9]*: ambiguous method 'P_size': more than one trait gives the type this method - call it by its trait-qualified name, e.g. 'P_A_size'" "$T/b1.err"; then ok "B1: p.size() refused at the call, naming P_A_size"
else bad "B1: p.size() failed without the positioned ambiguity error: $(grep '^error' "$T/b1.err" | head -1)"; fi
printf "$H$B"'fn main(): i64 { var p = P { 0 }; return P_size(p); }\nsyscall(60, main());\n' > "$T/b2.cyr"
build b2
if [ "$rc" -eq 0 ]; then bad "B2: P_size(p) with two traits BUILT"
elif grep -q "note: it is ambiguous - more than one trait gives 'P' this method; call it by its trait-qualified name, e.g. 'P_A_size'" "$T/b2.err"; then ok "B2: P_size(p) fails with the ambiguity note"
else bad "B2: P_size(p) failed without the ambiguity note: $(head -2 "$T/b2.err" | tr '\n' '|')"; fi

# ── C ──
printf "$H"'impl Show for P { fn show(self): i64 { return self.x; } }
trait Show { fn show(self): i64; fn twice(self): i64 { return self.show() * 2; } }
fn main(): i64 { var p = P { 21 }; return p.twice() - P_Show_show(p) + P_twice(p) - 42; }
syscall(60, main());
' > "$T/c1.cyr"
exits c1 21 "C1: trait below its impl; a default; the qualified and plain names"
printf "$H"'impl P { fn get(self): i64 { return self.x; } }
fn main(): i64 { var p = P { 9 }; return p.get(); }
syscall(60, main());
' > "$T/c2.cyr"
exits c2 9 "C2: a program with no trait (an inherent impl only) is untouched"

# ── D ──
printf 'include "lib/syscalls.cyr"\nvar trait = 1;\nsyscall(60, trait);\n' > "$T/d1.cyr"
build d1
if [ "$rc" -eq 0 ]; then bad "D: \`var trait = 1;\` BUILT"
elif grep -q "trait" "$T/d1.err"; then ok "D: \`trait\` is a reserved word, named in the refusal"
else bad "D: refused without naming trait: $(grep '^error' "$T/d1.err" | head -1)"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: traits_checked — $fails row(s) red"; exit 1; fi
echo "PASS: traits_checked — impl X for T is checked against trait X (8 refusals, each named), an ambiguous plain name is refused at a method call and explained on a direct call, well-formed traits build (declared below their impls too), and trait is reserved"
