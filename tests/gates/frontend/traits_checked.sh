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
#   E  (6.7.6) lib/trait.cyr is the RUN-TIME vtable pattern: its header does not promise `impl`
#      as sugar over it (ADR-007 §7), and it still builds and dispatches
#   TS (6.7.8) a trait member's SIGNATURE is parsed, at the trait, with PARSE_FN_DEF's grammar and
#      words. Before 6.7.8 only its commas were counted (the impl's arity check): junk in a required
#      signature, an unknown type name and junk in a default every impl overrides all compiled.
#      TS1/TS2 the filed repro verbatim (both members report, at `+` and at `1`); TS3 the inherited
#      default (PARSE_FN_DEF parses it for the impl: the same words, once, the trait above or below
#      the impl); TS4 a stray token before the `;`; TS5/TS6 an unknown parameter / return type;
#      TS7 a parameter that is not a name; TS8 junk in an overridden default; TS9 `--syntax-only`
#      (lint) still reports the grammar rows and stays silent on the type-name rows
#   V  (6.7.8) ANTI-VACUOUS: what a fn signature takes still compiles in a member — a struct or an
#      enum declared BELOW the trait, a generic member's own `<U>`, tuples and a multi-value return,
#      `Vec<T>` / `*T` / `**T` / `u128` / `*fn(..)` / a nested generic / `...` / a by-name `Str`
#
# Mutations: make `_tr_check_impl` return at entry -> A1-A4 RED (they build). Make `_tr_prepass`
# skip traits -> A1 fires for every impl and C RED. Drop the FINDFN fallback -> C RED (P_Show_show
# undefined). Drop `_tr_undef_note` -> B2 RED (no note).
# 6.7.8 (dyn D2), each measured RED in a scratch tree: M1 `_tr_sig_check` returns for every default
# member -> TS8 RED (builds). M2 no check between the signature and its `;` -> TS4 RED. M3 the
# inherited-default skip removed -> TS3 RED (reported twice). M4 the walker steps over a `: Type`
# unread -> TS5/TS6 RED. M5 `_trs_err` keeps the panic latch -> TS2 RED (the second member is
# swallowed). M6 the by-name handle arm (`s: Str`, no lib/str.cyr) removed -> V4 RED.
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

# ── E (6.7.6) — lib/trait.cyr is the RUN-TIME pattern, and its header says so ──
# Its header promised "`impl Trait for Type` can be added later as sugar over this pattern" for
# a year after ADR-007 §7 made language traits static (no vtables). Mutation: restore that
# sentence -> E1 RED.
if grep -qiE 'added later as sugar|sugar over this pattern' lib/trait.cyr; then
    bad "E1: lib/trait.cyr promises \`impl\` as sugar over its vtables — language traits dispatch statically (ADR-007 §7)"
elif grep -q 'ADR-007' lib/trait.cyr; then ok "E1: lib/trait.cyr names itself the run-time pattern, distinct from the language's static traits (ADR-007)"
else bad "E1: lib/trait.cyr's header no longer points at ADR-007 — say what it is relative to the language's traits"; fi
printf 'include "lib/trait.cyr"\nfn main(): i64 {\n    var o = int_as_display(42);\n    var s = to_string(o);\n    if (str_eq_cstr(s, "42") == 1) { return 7; }\n    return 1;\n}\nsyscall(60, main());\n' > "$T/e2.cyr"
exits e2 7 "E2: lib/trait.cyr builds and dispatches through its vtable (int_as_display -> to_string)"

# ── TS (6.7.8) — a trait member's signature is parsed ──
at() {   # <name> <line:col> <message fragment>: an error line at that position carrying the message
    grep "^error:<source>:$2: " "$T/$1.err" | grep -qF "$3"
}
refused_at() {   # <name> <message fragment> <line:col> <what>: refused ONCE, at that position
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$4: BUILT (rc 0)"
    elif ! at "$1" "$3" "$2"; then bad "$4: refused, but not as expected at $3: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$4: $n error lines (want 1): $(grep '^error' "$T/$1.err" | tr '\n' '|')"
    else ok "$4: refused once, at $3"; fi
}
REPRO="$ROOT/docs/development/issues/repros/2026-10-09-trait-signature-parameter-list-unparsed.cyr"
if [ ! -f "$REPRO" ]; then bad "TS1/TS2: the filed repro is missing ($REPRO)"
else
    cp "$REPRO" "$T/ts1.cyr"
    build ts1
    n=$(grep -c '^error' "$T/ts1.err")
    if [ "$rc" -eq 0 ]; then bad "TS1/TS2: the filed repro BUILT (rc 0)"
    else
        if at ts1 9:19 "expected ')', got '+'"; then ok "TS1: the repro's required member reports at \`+\` (9:19)"
        else bad "TS1: no \"expected ')', got '+'\" at 9:19: $(grep '^error' "$T/ts1.err" | head -1)"; fi
        if at ts1 10:19 "expected ')', got number 1"; then ok "TS2: ... and its overridden default at \`1\` (10:19)"
        else bad "TS2: no \"expected ')', got number 1\" at 10:19: $(grep '^error' "$T/ts1.err" | tr '\n' '|')"; fi
        if [ "$n" -eq 2 ]; then ok "TS1/TS2: exactly the two reports"; else bad "TS1/TS2: $n error lines (want 2)"; fi
    fi
fi
TS='trait Sh {\n    fn sh(self, n): i64;\n    fn tw(self, k 1 2): i64 { return 1; }\n}\n'
TI='impl Sh for P {\n    fn sh(self, n): i64 { return self.v + n; }\n}\n'
TM='fn main(): i64 { var p = P { 5 }; return p.sh(2); }\nsyscall(60, main());\n'
printf 'include "lib/syscalls.cyr"\nstruct P { v; }\n'"$TS$TI$TM" > "$T/ts3.cyr"
refused_at ts3 "expected ')', got number 1" 5:19 "TS3: the inherited default (no \`tw\` in the impl) — PARSE_FN_DEF's report"
printf 'include "lib/syscalls.cyr"\nstruct P { v; }\n'"$TI$TS$TM" > "$T/ts3b.cyr"
refused_at ts3b "expected ')', got number 1" 8:19 "TS3b: ... with the trait below its impl"
S='include "lib/syscalls.cyr"\nstruct P { v; }\n'
I='impl Sh for P { fn sh(self, n): i64 { return self.v + n; } }\n'
printf "$S"'trait Sh { fn sh(self, n): i64 foo; }\n'"$I$TM" > "$T/ts4.cyr"
refused_at ts4 "a trait method declaration ends with ';' (required) or a body (a default)" 3:32 "TS4: a stray token between the signature and its ;"
printf "$S"'trait Sh { fn sh(self, n: Nope): i64; }\n'"$I$TM" > "$T/ts5.cyr"
refused_at ts5 "unknown type 'Nope' for parameter 'n'" 3:27 "TS5: an unknown parameter type in a required member"
printf "$S"'trait Sh { fn sh(self, n): Nope2; }\n'"$I$TM" > "$T/ts6.cyr"
refused_at ts6 "unknown type 'Nope2' as a fn return type" 3:28 "TS6: an unknown return type in a required member"
printf "$S"'trait Sh { fn sh(self, 5): i64; }\n'"$I$TM" > "$T/ts7.cyr"
refused_at ts7 "expected identifier, got number 5" 3:24 "TS7: a parameter that is not a name"
printf "$S"'trait Sh { fn sh(self, n): i64; fn tw(self, k 1 2): i64 { return 1; } }\nimpl Sh for P { fn sh(self, n): i64 { return self.v + n; } fn tw(self, k): i64 { return k; } }\n'"$TM" > "$T/ts8.cyr"
refused_at ts8 "expected ')', got number 1" 3:47 "TS8: junk in a default every impl overrides"
printf "$S"'trait Sh {\n    fn sh(self, n + foo bar): i64;\n    fn tw(self, k 1 2): i64 { return 1; }\n    fn a(self, x: Nope): i64;\n    fn b(self): Nope2;\n}\nimpl Sh for P {\n    fn sh(self, n): i64 { return self.v + n; }\n    fn tw(self, k): i64 { return k; }\n    fn a(self, x): i64 { return 0; }\n    fn b(self): i64 { return 0; }\n}\n'"$TM" > "$T/ts9.cyr"
rc=0; "$CC" --syntax-only < "$T/ts9.cyr" > "$T/ts9.bin" 2> "$T/ts9.err" || rc=$?
if [ "$rc" -eq 0 ]; then bad "TS9: --syntax-only passed a trait with two grammar errors"
elif ! at ts9 4:19 "expected ')', got '+'" || ! at ts9 5:19 "expected ')', got number 1"; then bad "TS9: --syntax-only lost a grammar row: $(grep '^error' "$T/ts9.err" | tr '\n' '|')"
elif grep -q "unknown type" "$T/ts9.err"; then bad "TS9: --syntax-only refused a type NAME (it resolves nothing): $(grep 'unknown type' "$T/ts9.err" | head -1)"
else ok "TS9: --syntax-only reports both grammar rows and no type-name row"; fi

# ── V (6.7.8) — what a fn signature takes still compiles in a member ──
# (V2 calls the bounded generic member as `P_bnd(p, p)`: the method spelling `p.bnd(p)` runs the i64 base —
# issues/archived/2026-10-10-generic-method-call-runs-i64-base.md, filed by the same lane.)
printf 'include "lib/syscalls.cyr"\ntrait Sh { fn sh(self, q: Qt): Qt; }\nstruct Qt { x; y; z; }\nstruct P { v; }\nimpl Sh for P { fn sh(self, q: Qt): Qt { return q; } }\nfn main(): i64 { var p = P { 5 }; var q = Qt { 1, 2, 3 }; var r = p.sh(q); return r.y * 10 + r.z; }\nsyscall(60, main());\n' > "$T/v1.cyr"
exits v1 23 "V1: a member naming a struct declared BELOW the trait"
printf "$S"'trait Sh { fn sh(self, c: Color): i64; }\nimpl Sh for P { fn sh(self, c: Color): i64 { return c + self.v; } }\nenum Color { Red, Green, Blue }\nfn main(): i64 { var p = P { 5 }; return p.sh(Color.Blue); }\nsyscall(60, main());\n' > "$T/v1b.cyr"
exits v1b 7 "V1b: a member naming an enum declared below everything that uses it"
printf "$S"'trait Show { fn show(self): i64; }\nimpl Show for P { fn show(self): i64 { return self.v; } }\ntrait Sh { fn sh(self, n): i64; fn pick<U>(self, u: U): U; fn bnd<V: Show>(self, v: V): i64; }\nimpl Sh for P { fn sh(self, n): i64 { return self.v + n; } fn pick<U>(self, u: U): U { return u; } fn bnd<V: Show>(self, v: V): i64 { return v.show(); } }\nfn main(): i64 { var p = P { 5 }; return p.sh(2) + p.pick(30) + P_bnd(p, p); }\nsyscall(60, main());\n' > "$T/v2.cyr"
exits v2 42 "V2: a generic member's own <U>, and a bounded <V: Show>"
printf "$S"'trait Sh { fn sh(self, t: (i64, f64), k): i64; fn two(self): (i64, f64); }\nimpl Sh for P { fn sh(self, t: (i64, f64), k): i64 { return self.v + t.0 + k; } fn two(self): (i64, f64) { return (1, 2.0); } }\nfn main(): i64 { var p = P { 5 }; var t: (i64, f64) = (2, 1.5); var a, b = p.two(); return p.sh(t, 1) * 10 + a; }\nsyscall(60, main());\n' > "$T/v3.cyr"
exits v3 81 "V3: a tuple parameter and a multi-value return"
printf "$S"'struct Box<T> { v: T; }\ntrait Sh { fn sh(self, n): i64; fn a(self, v: Vec<i64>, q: *P, w: *u128, cb: *fn(i64, *P): i64, pp: **i64): Vec<i64>; fn b(self): *P; fn c(self): u128; fn d(self): *fn(i64): i64; fn e(self, m: Box<Vec<Box<i64>>>): (i64, f64); fn f(self, s: Str, c: cstring, ...): Result; fn g(self, e: f64v2, h: bool, i: u8, j: Option, k: Tagged): f64; }\nimpl Sh for P { fn sh(self, n): i64 { return self.v + n; } fn a(self, v, q, w, cb, pp): i64 { return 0; } fn b(self): i64 { return 0; } fn c(self): i64 { return 0; } fn d(self): i64 { return 0; } fn e(self, m): i64 { return 0; } fn f(self, s, c, ...): i64 { return 0; } fn g(self, e, h, i, j, k): i64 { return 0; } }\n'"$TM" > "$T/v4.cyr"
exits v4 7 "V4: Vec<T> / *T / **T / *u128 / *fn(..) / a nested generic / ... / a by-name Str (no lib/str.cyr)"

if [ "$fails" -ne 0 ]; then echo "FAIL: traits_checked — $fails row(s) red"; exit 1; fi
echo "PASS: traits_checked — impl X for T is checked against trait X (8 refusals, each named), an ambiguous plain name is refused at a method call and explained on a direct call, well-formed traits build (declared below their impls too), trait is reserved, lib/trait.cyr is the run-time vtable pattern, and every trait member's signature is parsed (TS1-TS9 with the filed repro verbatim; V1-V4 still build)"
