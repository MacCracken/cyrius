#!/bin/sh
# tests/gates/frontend/address_of_field_refused.sh — 6.7.13
#
# `&x.f` — THE ADDRESS OF A STRUCT FIELD — IS NOT CYRIUS: refused by name (the user's D3 (b), 2026-10-15;
# issues/archived/2026-10-14-address-of-field-does-not-parse-guide-cites-it.md). Through 6.7.12 the `&` factor took `&x`
# and stopped at the `.`, so the parse failed on the token after it — `expected ')', got '.'` (`expected ';'` in a
# declaration) — with no word of why, while the guide cited `load64(&s.f)` and `&h.f` as expressions. Now the
# factor refuses it once, as `&a[i]` is (`_addr_field_post`, src/frontend/parse_expr.cyr), consumes its `.f` /
# `.0` / `.m(..)` steps so the parse stays in step, and the guide's two citations are corrected.
#
#   F   refused once, by name, no binary: the filed repro verbatim (a narrow field `load8(&o.g)` of a local), a
#       local's 8 B field, a global's (a top-level initialiser in the declaration zone and after the first
#       statement), a `*E` parameter's, a nested field, a top-level argument, a tuple element `&t.0`, a method
#       `&o.m()`, a field then an index `&o.a[1]` (the field's refusal only)
#   K   kept: `&E.V` keeps its own refusal; `&o`, `&o + 8` and `p.g` through a `*E` (the spellings the message
#       names) compile and read the field; a later error in the file is still reported (the parse in step)
#
# Mutation (2026-10-15, a scratch tree with the one change, its compiler built by the fixed one, this gate run
# with CYCC=that compiler): `_addr_field_post` answering 0 (no refusal) -> RED F1-F10 ("expected ')', got '.'"
# and the like, refused not as expected) and K4 (the parse out of step: a cascade).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: address_of_field_refused: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: address_of_field_refused: mktemp -d failed"; exit 1; }
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
    elif [ -s "$T/$1.bin" ]; then bad "$3: refused but still emitted a binary"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}
exits() {   # <name> <want> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; ( ulimit -c 0; timeout 10 "$T/$1.bin" ) > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
AF='the address of a field is not taken - write `&x + offset` or reach it through a `*T`'
E='struct E { a; g: u8; }\n'
G='struct E { a; g; }\nvar GO = E { 1, 2 };\n'

echo "F. \`&x.f\` refused by name, once, no binary"
# The filed repro, verbatim (it was `expected ')', got '.'`).
refused f01 "$AF" "F1: the filed repro, verbatim: load8(&o.g), a local's narrow field" "struct E { a; g: u8; }\nfn f(): i64 { var o = E { 1, 99 }; return load8(&o.g); }\nsyscall(60, f());\n"
refused f02 "$AF" "F2: var p = &o.g, a local's 8 B field" "${G}fn f(): i64 { var o = E { 1, 2 }; var p = &o.g; return 0; }\nsyscall(60, f());\n"
refused f03 "$AF" "F3: var q = &GO.g, a top-level initialiser (the declaration zone)" "${G}var q = &GO.g;\nsyscall(60, 0);\n"
refused f04 "$AF" "F4: var q = &GO.g after the first statement" "${G}var e = 0;\nsyscall(1, 1, \"\", 0);\nvar q = &GO.g;\nsyscall(60, 0);\n"
refused f05 "$AF" "F5: load8(&p.g), a *E parameter" "${E}fn f(p: *E): i64 { return load8(&p.g); }\nfn main(): i64 { var o = E { 1, 9 }; return f(&o); }\nsyscall(60, main());\n"
refused f06 "$AF" "F6: load64(&o.i.y), a nested field" "struct I { x; y; }\nstruct E { a; i: I; }\nfn f(): i64 { var o: E; o.i.y = 4; return load64(&o.i.y); }\nsyscall(60, f());\n"
refused f07 "$AF" "F7: set(&GO.g), a top-level argument" "${G}fn set(p): i64 { return 0; }\nvar r = set(&GO.g);\nsyscall(60, r);\n"
refused f08 "$AF" "F8: load64(&t.0), a tuple element" "fn f(): i64 { var t = (1, 2); return load64(&t.0); }\nsyscall(60, f());\n"
refused f09 "$AF" "F9: load64(&o.m()), a method's result" "${G}impl E { fn m(self): i64 { return 1; } }\nfn f(): i64 { var o = E { 1, 2 }; return load64(&o.m()) + 1; }\nsyscall(60, f());\n"
refused f10 "$AF" "F10: load64(&o.g[1]), a field then an index: the field's refusal only" "${G}fn f(): i64 { var o = E { 1, 2 }; return load64(&o.g[1]); }\nsyscall(60, f());\n"

echo "K. what stays"
refused k01 "cannot take the address of enum constant 'RED'" "K1: &Color.RED keeps its own refusal" "enum Color { RED, GREEN }\nfn f(): i64 { var p = &Color.RED; return 0; }\nsyscall(60, f());\n"
exits k02 12 "K2: &o and &o + 8 still compile (the struct's address, a byte pointer)" "${G}fn f(): i64 { var o = E { 1, 2 }; return load64(&o) * 10 + load64(&o + 8); }\nsyscall(60, f());\n"
exits k03 99 "K3: the field through a *E (the spelling the refusal names)" "${E}fn f(): i64 { var o = E { 1, 99 }; var p: *E = &o; return p.g; }\nsyscall(60, f());\n"
# The parse stays in step: a later, unrelated error is still reported, and nothing between them.
printf '%b' "${G}fn f(): i64 { var o = E { 1, 2 }; var p = &o.g; return 0; }\nfn h(): i64 { return undefined_name_x; }\nsyscall(60, f() + h());\n" > "$T/k04.cyr"
build k04
if [ "$rc" -eq 0 ]; then bad "K4: BUILT"
elif [ "$(grep -c '^error' "$T/k04.err")" -ne 2 ]; then bad "K4: want 2 errors (the field, then the undefined name): $(grep '^error' "$T/k04.err" | head -3 | tr '\n' '|')"
elif ! grep -qF "$AF" "$T/k04.err" || ! grep -q "undefined variable 'undefined_name_x'" "$T/k04.err"; then bad "K4: not the two expected errors: $(grep '^error' "$T/k04.err" | head -2 | tr '\n' '|')"
else ok "K4: the parse stays in step — a later error is still reported, nothing between"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: address_of_field_refused — $fails row(s) red"; exit 1; fi
echo "PASS: address_of_field_refused — \`&x.f\` is refused by name once (a local, a global in both zones, a *E parameter, a nested field, a narrow field, a top-level argument, a tuple element, a method, a field then an index: F1-F10); &E.V, &o, &o + 8 and p.g through a *E stay, and the parse stays in step (K1-K4)"
