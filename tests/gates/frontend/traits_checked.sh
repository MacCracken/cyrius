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
#   TV (6.7.15, the user's D9 (a), 2026-10-18) a member's `: Vec<..>` return is refused at the trait, once, with a fn's
#      words ("type 'Vec' cannot be a fn return type" and its note): it compiled, though no impl can define it (an
#      impl's `fn a(self): Vec<i64>` is refused, as any fn's is). TV1 the filed repro verbatim; TV2 a bare `: Vec` and
#      `: Vec<nosuch>` (the element not read after the refusal) — one line each; TV3 a default every impl overrides
#      (checked at the trait), its override `: i64` — the trait's line alone; TV4 `--syntax-only` silent, as a fn's
#      `: Vec<..>` return is; TVK `: i64`, `: *Vec<i64>`, a parameter `v: Vec<i64>` and `(Vec<i64>, i64)` build and run.
#      Filed: docs/development/issues/archived/2026-10-16-trait-member-vec-return-accepted.md
#      Mutants (2026-10-18, a one-edit scratch copy of src/ each, its cycc built from it, CYCC= it): the lane's previous
#      compiler (bd8ad547) -> RED 5: TV1 (both rows), TV2, TV2b (its element's line), TV3 (each built but TV2b); MTV1
#      `_trs_ret_refused` answering 0 -> RED 5: the same; MTV2 `_trs_ret_refused` reporting under --syntax-only -> RED 1: TV4
#   TR (6.7.15, the user's D4 (a), 2026-10-18) an impl method's return type must be its member's: it was never compared
#      (the parameter COUNT was), so `fn c(self): i64` implementing `fn c(self): f64;` compiled and a bounded generic
#      caller declared `: f64` read the integer bits. Compared as forming a dyn compares it (a name by its resolved type,
#      no annotation an i64) and refused at the impl, by name: "'P.c' returns i64, trait 'T' declares f64". TR1 the
#      filed repro; TR2 the bounded-generic caller (exit 2: the bits); TR3 / TR4 a missing annotation either side (at the
#      method's name when the impl has none); TR5 a multi-value return, as written; TR6 the trait below two impls; TR7 a
#      dyn formed above and below the impl adds nothing (it reported "the return type differs" at the site too); TR8 /
#      TR8b a side its own reader refuses reports alone (TR8c, 6.7.16: a method's `*fn( .. )` return too); TRK the agreeing
#      shapes, two impls (131). dyn_checked.sh F8b is
#      this refusal now. Filed: docs/development/issues/archived/2026-10-17-trait-member-u128-return-accepted-and-impl-return-unchecked.md
#      Mutants (2026-10-18, a one-edit scratch copy of src/ each, CYCC= its cycc): the lane's previous compiler
#      (d9273ec3) -> RED 7: TR1-TR7 (each built; TR7 the site's F8 line instead), and dyn_checked.sh F8b; MTR1
#      `_tr_ret_chk` answering 0 -> the same; MTR2 `_tr_rt_bad` answering 0 -> RED 5: TS4 TS6 TV3 TR8 TR8b (a second
#      line), and type_name_refused.sh u128_trait_ret / u128_trait_ret2; MTR3 the dyn hand-off gone -> RED 1: TR7 (two
#      lines), and dyn_checked.sh F8b; MTR4 `_tr_rt_nonret` answering 0 -> RED 1: TR8b
#   TRS (6.7.15, the D4 review fix) one type spelled two ways is ONE type to that check: each return is read as the
#      annotation reader reads it (`_ty_norm_eq`) — a `>>` / `>>>` as two / three closing `>`, a generic struct's
#      all-`i64` list as its base struct (`Box<i64>` IS `Box`, 6.6.10's rule). The first cut compared tokens and
#      refused programs that compiled and ran (exit 4 on the slot-open compiler b2e1f4c4): TRS1 `Box<Box<i64>>` against
#      `Box<Box<i64> >` (the review's shape), TRS2 `Box<i64>` against `Box`, TRS3 `*Box<i64>` against `*Box`,
#      TRS4 a `>>>` close, a nested `Box<Box<i64>>` against `Box<Box>` and an all-i64 list inside a multi-value — each 4
#      (its `d` returns `(b.n, 2)`: 6.7.16's D90 refuses the 16-byte `b` itself as an element);
#      TRS5 / TRS6 a different argument stays refused (`Box<i32>`, `Box<Box<i32> >`), TRS7 a struct that is not the
#      member's. Mutants (2026-10-18, a one-edit scratch copy of src/ each, CYCC= its cycc): the lane's previous compiler
#      (0ca74300) -> RED 4: TRS1-TRS4 (refused); MTRS1 `_tr_ret_differs` back on `_dyn_ty_eq` (normalisation off) -> the
#      same; MTRS2 `_tyn_expand` keeping `>>` one token -> RED 2: TRS1 TRS4; MTRS3 `_tyn_i64_list` answering 0 (no
#      all-i64 fold) -> RED 3: TRS2 TRS3 TRS4
#   TRC (6.7.16) a return refusal does not end the impl's check: `_tr_check_impl` returned on the first method whose
#      return differs, so a second mismatch and a required method left out each appeared only once the line before it
#      was fixed. The refusal sets no panic latch (it consumes nothing), so the walk goes on. TRC1 the filed repro
#      verbatim: exactly three lines (3:28 `P.a`, 3:58 `P.b`, the missing `c`); TRC2 a parameter-count mismatch and
#      TRC3 a method the trait does not declare, each after a return refusal — two lines. Filed:
#      docs/development/issues/2026-10-18-impl-check-stops-at-first-differing-return.md
#      Mutant (2026-10-20): the lane's base compiler (b73e8d5fe, the early return) -> RED 3: TRC1 TRC2 TRC3 (one line)
#   TP (6.7.16) a generic member's own `<U>` reads after a `*fn(..)` in its signature: the signature resolver
#      (`_tn_sig_tparam`) walked back to the NEAREST `fn` token, the fn-pointer type's, and refused `U` as "unknown type".
#      A `fn` behind a `*` is now stepped over. TP1 the filed repro verbatim (exit 5; it was refused at 3:47); TP2 the
#      `*fn` last, a `: U` return (refused at 3:51); TP3 a `U` inside the `*fn(U): i64` itself (refused at 3:34) — each
#      5; TP4 a non-generic member unchanged; TP5 an unknown name after a `*fn(..)` still refused once; TP6 a non-generic
#      fn's `U` after a `*fn(..)` still refused once. Filed:
#      docs/development/issues/2026-10-18-generic-trait-member-type-parameter-unknown-after-fn-pointer-type.md
#      Mutant (2026-10-20): the lane's previous compiler (7a6df215c, no step-over) -> RED 3: TP1 TP2 TP3 (refused)
#   TM (6.7.16, the user's D9, 2026-10-19) a member's return is held to a fn's WHOLE return set, as 6.7.15's D9 / D3 held
#      it for `Vec` / `u128`: `: u8`..`: u64`, `: f32` and an enum are "type 'u8' cannot be a fn return type" with a fn's
#      note, and a `*fn( .. )` return is "a fn-pointer type `*fn( .. )` cannot be a fn return type" — each compiled,
#      though no impl could define it. TM1 the filed repro verbatim: exactly five lines, one per member (it built: exit
#      4), each with the note; TM2 the set a fn returns still compiles and runs (i64, f64, bool, a struct, `*u8`, Result,
#      a member's own `U`, i8 / i16 / i32, cstring, Option, Tagged, `*Color`, `(u8, Color)`, `Box<i64>`, a union,
#      `**u64`); TM3 `--syntax-only` reports the `*fn( .. )` line alone (a fn's `: *fn( .. )` is its grammar refusal
#      there) and is silent on the names (as a fn's are); TM4 V4's `Sd` member, and `**fn( .. )`, refused once at their
#      `*`; TM5 an impl adds no "returns .., trait declares .." line beside the member's refusal (two members, and a
#      default two impls override); TM6 an enum declared below the trait. Filed:
#      docs/development/issues/2026-10-18-trait-member-return-outside-fn-return-set-accepted.md
#      Mutant (2026-10-20): the lane's previous compiler (d4a59f3e4) -> RED 8: TM1 TM1b TM4 TM4b TM6 (built), TM3 (no
#      line), TM5 TM5b (the impl's "returns .., trait declares .." lines instead); TM2 and TM3b green
#   TRR (6.7.16 review) "a side its own reader refuses" counts only names a reader READS: a `<..>` after `Result`,
#      `Option` or an enum is stepped unread, so a `Pt<i64>` inside one is refused by nobody — D7's arm in `_tr_rt_bad`
#      counted it, and a member's `: Result<Pt<i64>>` against an impl's `: i64` compiled (refused by the impl on the
#      lane's base b73e8d5fe). TRR1 that program — the impl's line, once; TRR2 `Option<Pt<i64>>` with a dyn formed above
#      the impl — the impl's line alone (the lane's head printed the site's "the return type differs" instead).
#      Mutant (2026-10-20): the lane's previous compiler (b667c0c69) -> RED 2: TRR1 (built), TRR2 (the site's line)
#      TRR3-TRR6 (D5's shape): a generic struct given more type arguments than it declares is its reader's refusal too
#      (`_ta_over`), so the impl adds no "returns .." line beside "'Box' takes 1 type argument, 2 given": TRR3 the
#      review's dd7 (a member's `: Box<i64, Pt>`, the impl's `: Box`), TRR4 dd8 (the impl's `: Box<i64, Pt>`) — the
#      reader's line alone; TRR5 `Option<Box<i64, Pt>>` (a list no reader reads) keeps the impl's line; TRR6 under
#      `--syntax-only`, where D5 is silent, dd7 keeps the impl's line (lint's one report of it). Mutant (2026-10-20):
#      the lane's head aff3849ff -> RED 2: TRR3 TRR4 (two lines); `_ta_over`'s arm without its `_syntax_only` guard ->
#      RED 1: TRR6 (no line)
#      TRR9 (6.7.16, f16 FG1) `--syntax-only` keeps the impl's "returns .., trait declares .." line where the reader's own
#      refusal is silent under lint, as TRR6 does for D5: a member's `: u8` / `: f32` / enum (D9) and either side's
#      `Pt<i64>` / `i64<u8>` (D7 / 6.7.15's D6) were counted as refused, and lint passed the program (rc 0, no line;
#      6.7.15 printed the line). TRR9-TRR9d the review's dd2 / dd1 / dd3 / dd4, each 6.7.15's text; TRR9e control: an
#      impl's `: u8` against a member's `: i64` stays silent under lint (6.7.15's verdict: a method's `: u8` arm is
#      6.7.15's); TRR9f / TRR9g the method's side (`: *Pt<i64>`, `: i64<u8>`); TRR9h two members, one line each, and
#      TRR9i the full compile of it — the members' refusals alone (unchanged). Filed:
#      docs/development/issues/2026-10-20-lint-silent-on-impl-return-mismatch-member-type-refused.md
#      Mutants (2026-10-21, a scratch copy of src/ with the one change, its cycc): the lane before it (3482cd42e) -> RED 7:
#      TRR9 TRR9b-TRR9d TRR9f-TRR9h (rc 0, no line); `_tr_rt_nr` counting a member's names under lint -> RED 4: TRR9
#      TRR9b TRR9d TRR9h; `_ty_rd_name`'s `_ngt_tail` arm unguarded -> RED 4: TRR9c TRR9f TRR9g TRR9h; `_tr_rt_nr`
#      dropping the method's names under lint too -> RED 1: TRR9e
#   FP (6.7.16, f16 FG2) a fn's `: *fn( .. )` / `: **fn( .. )` / bare `: *fn` return, and a multi-value element, is the
#      member's one line ("a fn-pointer type `*fn( .. )` cannot be a fn return type") at its first `*`, the body read on
#      — it was "expected identifier, got reserved keyword 'fn' (.. rename ..)" and, bare, a cascade; see the block
#   BF (6.7.16, f16 FG2, the user's D91) a member's bare `cb: *fn` / `cb: **fn` parameter is a type, as a fn's: it was
#      "expected '(', got ')'"; see the block
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
    n=$(grep -c '^error' "$T/$1.err" || true)
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
    n=$(grep -c '^error' "$T/$1.err" || true)
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
    n=$(grep -c '^error' "$T/ts1.err" || true)
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
printf "$S"'struct Box<T> { v: T; }\ntrait Sh { fn sh(self, n): i64; fn a(self, v: Vec<i64>, q: *P, w: *u128, cb: *fn(i64, *P): i64, pp: **i64): *Vec<i64>; fn b(self): *P; fn c(self): *u128; fn e(self, m: Box<Vec<Box<i64>>>): (i64, f64); fn f(self, s: Str, c: cstring, ...): Result; fn g(self, e: f64v2, h: bool, i: u8, j: Option, k: Tagged): f64; }\nimpl Sh for P { fn sh(self, n): i64 { return self.v + n; } fn a(self, v, q, w, cb, pp): *Vec<i64> { return 0; } fn b(self): *P { return 0; } fn c(self): *u128 { return 0; } fn e(self, m): (i64, f64) { return (0, 0.5); } fn f(self, s, c, ...): Result { return 0; } fn g(self, e, h, i, j, k): f64 { return 0.5; } }\n'"$TM" > "$T/v4.cyr"
# (6.7.15: V4's impl returns what each member declares — D4 compares them. Its `*fn(..)` RETURN, a member of a trait no
# impl implemented (`Sd`: no impl could define it), is refused since 6.7.16's D9 — TM4.)
exits v4 7 "V4: Vec<T> / *T / **T / *u128 / *fn(..) / a nested generic / ... / a by-name Str (no lib/str.cyr)"

# ── TV (6.7.15, D9) — a member's `: Vec<..>` return is refused at the trait, with a fn's words ──
VR="type 'Vec' cannot be a fn return type"
cat > "$T/tv1.cyr" <<'EOF'
include "lib/vec.cyr"
trait Sh { fn a(self): Vec<i64>; }
fn main(): i64 { return 4; }
syscall(60, main());
EOF
refused_at tv1 "$VR" 2:24 "TV1: the filed repro verbatim (it built: exit 4)"
if grep -qF "note: a return type is a struct" "$T/tv1.err"; then ok "TV1: ... with a fn's note"; else bad "TV1: no return-type note: $(cat "$T/tv1.err" | tr '\n' '|')"; fi
V='include "lib/vec.cyr"\nstruct P { v; }\n'
printf "$V"'trait Sh { fn a(self): Vec; }\nsyscall(60, 4);\n' > "$T/tv2.cyr"
refused_at tv2 "$VR" 3:24 "TV2: a bare : Vec"
printf "$V"'trait Sh { fn b(self): Vec<nosuch>; }\nsyscall(60, 4);\n' > "$T/tv2b.cyr"
refused_at tv2b "$VR" 3:24 "TV2b: : Vec<nosuch> — the element is not read after the refusal"
printf "$V"'trait Sh { fn a(self): Vec<i64> { return 0; } }\nimpl Sh for P { fn a(self): i64 { return 1; } }\nfn main(): i64 { var p = P { 1 }; return p.a(); }\nsyscall(60, main());\n' > "$T/tv3.cyr"
refused_at tv3 "$VR" 3:24 "TV3: a default every impl overrides is checked at the trait — its line alone"
rc=0; "$CC" --syntax-only < "$T/tv1.cyr" > "$T/tv4.bin" 2> "$T/tv4.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/tv4.err"; then ok "TV4: --syntax-only is silent, as for a fn's : Vec<..> return"
else bad "TV4: --syntax-only rc $rc: $(grep '^error' "$T/tv4.err" | head -1)"; fi
printf "$V"'trait Sh { fn a(self): i64; fn b(self): *Vec<i64>; fn c(self, v: Vec<i64>): i64; fn e(self): (Vec<i64>, i64); }\nimpl Sh for P { fn a(self): i64 { return 1; } fn b(self): *Vec<i64> { return 0; } fn c(self, v: Vec<i64>): i64 { return 2; } fn e(self): (Vec<i64>, i64) { return (0, 4); } }\nfn main(): i64 { var p = P { 1 }; var w, k = p.e(); return p.a() + p.c(0) + k; }\nsyscall(60, main());\n' > "$T/tvk.cyr"
exits tvk 7 "TVK: : i64, : *Vec<i64>, a parameter v: Vec<i64> and (Vec<i64>, i64) unchanged"

# ── TR (6.7.15, D4) — an impl method's return type must be its member's ──
RR="'P.c' returns i64, trait 'T' declares f64"
R='include "lib/syscalls.cyr"\nstruct P { x; }\n'
printf 'struct P { x; }\ntrait T { fn c(self): f64; }\nimpl T for P { fn c(self): i64 { return 4; } }\nfn main(): i64 { var p: P = P { 1 }; return p.c(); }\nsyscall(60, main());\n' > "$T/tr1.cyr"
refused_at tr1 "$RR" 3:28 "TR1: the filed repro (an f64 member implemented as : i64; it built: exit 4)"
printf "$R"'trait T { fn c(self): f64; }\nimpl T for P { fn c(self): i64 { return 4; } }\nfn get<X: T>(o: X): f64 { return o.c(); }\nfn main(): i64 { var p: P = P { 1 }; var f = get(p); if (f == 4.0) { return 1; } return 2; }\nsyscall(60, main());\n' > "$T/tr2.cyr"
refused_at tr2 "$RR" 4:28 "TR2: through a bounded generic declared : f64 (it built and read the integer bits: exit 2)"
printf "$R"'trait T { fn c(self); }\nimpl T for P { fn c(self): f64 { return 4.0; } }\nsyscall(60, 0);\n' > "$T/tr3.cyr"
refused_at tr3 "'P.c' returns f64, trait 'T' declares i64" 4:28 "TR3: a member with no return type (i64), an impl's : f64"
printf "$R"'trait T { fn d(self): bool; }\nimpl T for P { fn d(self) { return 1; } }\nsyscall(60, 0);\n' > "$T/tr4.cyr"
refused_at tr4 "'P.d' returns i64, trait 'T' declares bool" 4:19 "TR4: an impl with no return type, a member's : bool — at the method's name"
printf "$R"'trait T { fn e(self): (i64, f64); }\nimpl T for P { fn e(self): (i64, i64) { return (1, 2); } }\nsyscall(60, 0);\n' > "$T/tr5.cyr"
refused_at tr5 "'P.e' returns (i64, i64), trait 'T' declares (i64, f64)" 4:28 "TR5: a multi-value return, as written"
printf "$R"'struct Q { y; }\nimpl T for Q { fn c(self): f64 { return 1.5; } }\nimpl T for P { fn c(self): i64 { return 4; } }\ntrait T { fn c(self): f64; }\nsyscall(60, 0);\n' > "$T/tr6.cyr"
refused_at tr6 "$RR" 5:28 "TR6: the trait below two impls, the one that differs"
printf "$R"'trait T { fn c(self): f64; }\nfn f(q: *P): i64 { var o: dyn T = q; return 0; }\nimpl T for P { fn c(self): i64 { return 4; } }\nfn g(q: *P): i64 { var o: dyn T = q; return 0; }\nsyscall(60, 0);\n' > "$T/tr7.cyr"
refused_at tr7 "$RR" 5:28 "TR7: formed into a dyn above and below the impl — the impl's line alone"
printf "$R"'trait T { fn c(self): Nope; }\nimpl T for P { fn c(self): i64 { return 4; } }\nsyscall(60, 0);\n' > "$T/tr8.cyr"
refused_at tr8 "unknown type 'Nope' as a fn return type" 3:23 "TR8: a member's return its reader refuses — that refusal alone"
printf "$R"'trait T { fn c(self): i64; }\nimpl T for P { fn c(self): u8 { return 4; } }\nsyscall(60, 0);\n' > "$T/tr8b.cyr"
refused_at tr8b "type 'u8' cannot be a fn return type" 4:28 "TR8b: an impl's return a fn's reader refuses (: u8) — that refusal alone"
# 6.7.16: a method's `*fn( .. )` return is PARSE_FN_DEF's refusal; the impl's "'P.d' returns *fn(i64): i64, trait 'T'
# declares i64" line beside it (4:28) was a second report of it. Mutant (2026-10-20): the lane's previous compiler
# (00d27769b, `_tr_rt_bad` reading a `*fn( .. )` on the member side only) -> RED 1: TR8c (two lines). Since f16 FG2 the
# method's refusal is the member's fn-pointer line at the `*` (it was "expected identifier, got reserved keyword 'fn'"
# at 4:29; see FP).
printf "$R"'trait T { fn d(self): i64; }\nimpl T for P { fn d(self): *fn(i64): i64 { return 0; } }\nsyscall(60, 0);\n' > "$T/tr8c.cyr"
refused_at tr8c 'a fn-pointer type `*fn( .. )` cannot be a fn return type' 4:28 "TR8c: an impl's *fn( .. ) return — the fn's own refusal alone"
# ── TRS (6.7.15, the D4 review fix) — one type spelled two ways is one type ──
BX='struct Box<T> { n: i64; v: T; }\nstruct Pt { x: i64; y: i64; }\n'
printf "$BX"'trait T { fn c(self): Box<Box<i64>>; }\nimpl T for Pt { fn c(self): Box<Box<i64> > { var b: Box<Box<i64> >; b.n = 4; return b; } }\nfn main(): i64 { var p: Pt; var r: Box<Box<i64> > = p.c(); return r.n; }\n' > "$T/trs1.cyr"
exits trs1 4 "TRS1: Box<Box<i64>> against Box<Box<i64> > (the review's shape; it was refused)"
printf "$BX"'trait T { fn c(self): Box<i64>; }\nimpl T for Pt { fn c(self): Box { var b: Box; b.n = 4; return b; } }\nfn main(): i64 { var p: Pt; var r: Box = p.c(); return r.n; }\n' > "$T/trs2.cyr"
exits trs2 4 "TRS2: Box<i64> against Box (the base struct)"
printf 'include "lib/alloc.cyr"\n'"$BX"'trait T { fn c(self): *Box<i64>; }\nimpl T for Pt { fn c(self): *Box { var q: *Box = alloc(16); q.n = 4; return q; } }\nfn main(): i64 { var p: Pt; var r: *Box = p.c(); return r.n; }\n' > "$T/trs3.cyr"
exits trs3 4 "TRS3: *Box<i64> against *Box"
printf "$BX"'trait T { fn c(self): Box<Box<Box<i64>>>; fn d(self): (Box<i64>, i64); fn e(self): Box<Box<i64>>; }\nimpl T for Pt {\n  fn c(self): Box<Box<Box> > { var b: Box<Box<Box<i64> > >; b.n = 1; return b; }\n  fn d(self): (Box, i64) { var b: Box; b.n = 1; return (b.n, 2); }\n  fn e(self): Box<Box> { var b: Box<Box>; b.n = 1; return b; }\n}\nfn main(): i64 { var p: Pt; var r: Box<Box<Box>> = p.c(); var w, k = p.d(); var e: Box<Box> = p.e(); return r.n + k + e.n; }\n' > "$T/trs4.cyr"
exits trs4 4 "TRS4: a >>> close, an all-i64 list in a multi-value, a nested Box<Box<i64>> against Box<Box>"
printf "$BX"'trait T { fn c(self): Box<i64>; }\nimpl T for Pt { fn c(self): Box<i32> { var b: Box<i32>; b.n = 4; return b; } }\nfn main(): i64 { return 0; }\n' > "$T/trs5.cyr"
refused_at trs5 "'Pt.c' returns Box<i32>, trait 'T' declares Box<i64>" 4:29 "TRS5: Box<i32> against Box<i64> stays refused"
printf "$BX"'trait T { fn c(self): Box<Box<i64>>; }\nimpl T for Pt { fn c(self): Box<Box<i32> > { var b: Box<Box<i32> >; b.n = 4; return b; } }\nfn main(): i64 { return 0; }\n' > "$T/trs6.cyr"
refused_at trs6 "'Pt.c' returns Box<Box<i32> >, trait 'T' declares Box<Box<i64>>" 4:29 "TRS6: Box<Box<i32> > against Box<Box<i64>> stays refused"
printf "$BX"'trait T { fn c(self): Box<i64>; }\nimpl T for Pt { fn c(self): Pt { var b: Pt; return b; } }\nfn main(): i64 { return 0; }\n' > "$T/trs7.cyr"
refused_at trs7 "'Pt.c' returns Pt, trait 'T' declares Box<i64>" 4:29 "TRS7: a struct that is not the member's stays refused"
# ── TRC (6.7.16) — a return refusal does not end the impl's check ──
lines_are() {   # <name> <what> <line:col|message>...: refused with exactly these error lines, in this order
    nm=$1; what=$2; shift 2
    build "$nm"
    if [ "$rc" -eq 0 ]; then bad "$what: BUILT (rc 0)"; return; fi
    grep '^error' "$T/$nm.err" > "$T/$nm.got" || true
    : > "$T/$nm.want"
    for w in "$@"; do printf 'error:<source>:%s\n' "$w" >> "$T/$nm.want"; done
    if cmp -s "$T/$nm.got" "$T/$nm.want"; then ok "$what: exactly $# lines"
    else bad "$what: got $(tr '\n' '|' < "$T/$nm.got") want $(tr '\n' '|' < "$T/$nm.want")"; fi
}
cat > "$T/trc1.cyr" <<'EOF'
struct P { x; }
trait T { fn a(self): f64; fn b(self): f64; fn c(self): i64; }
impl T for P { fn a(self): i64 { return 1; } fn b(self): i64 { return 2; } }
fn main(): i64 { return 0; }
EOF
lines_are trc1 "TRC1: the filed repro verbatim — both mismatches and the missing method" \
    "3:28: 'P.a' returns i64, trait 'T' declares f64" "3:58: 'P.b' returns i64, trait 'T' declares f64" \
    "3:16: impl is missing method 'c', required by trait 'T'"
printf 'struct P { x; }\ntrait T { fn a(self): f64; fn b(self, k): i64; }\nimpl T for P { fn a(self): i64 { return 1; } fn b(self): i64 { return 2; } }\nfn main(): i64 { return 0; }\n' > "$T/trc2.cyr"
lines_are trc2 "TRC2: a parameter-count mismatch after a return refusal" \
    "3:28: 'P.a' returns i64, trait 'T' declares f64" \
    "3:16: method 'b' takes a different number of parameters than its declaration in trait 'T'"
printf 'struct P { x; }\ntrait T { fn a(self): f64; }\nimpl T for P { fn a(self): i64 { return 1; } fn z(self): i64 { return 3; } }\nfn main(): i64 { return 0; }\n' > "$T/trc3.cyr"
lines_are trc3 "TRC3: a method the trait does not declare after a return refusal" \
    "3:28: 'P.a' returns i64, trait 'T' declares f64" "3:16: method 'z' is not declared in trait 'T'"

cat > "$T/trk.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct P { x; }
struct Q { y; }
trait T {
    fn a(self): i64;
    fn b(self);
    fn c(self): f64;
    fn d(self): *u128;
    fn e(self): (i64, f64);
    fn f(self): Pt;
    fn g<U>(self, u: U): U;
    fn h(self): Box<Pt>;
    fn i(self): bool;
    fn j(self): i64;
}
impl T for P {
    fn a(self) { return 1; }
    fn b(self): i64 { return 2; }
    fn c(self): f64 { return 1.5; }
    fn d(self): *u128 { return 0; }
    fn e(self): (i64, f64) { return (3, 2.5); }
    fn f(self): Pt { var p: Pt; p.x = 4; p.y = 5; return p; }
    fn g<V>(self, v: V): V { return v; }
    fn h(self): Box<Pt> { var b: Box<Pt>; b.n = 6; return b; }
    fn i(self): bool { return true; }
    fn j(self): i64 { return 7; }
}
impl T for Q {
    fn a(self): i64 { return 10; }
    fn b(self) { return 20; }
    fn c(self): f64 { return 2.5; }
    fn d(self): *u128 { return 0; }
    fn e(self): (i64, f64) { return (30, 1.5); }
    fn f(self): Pt { var p: Pt; p.x = 40; p.y = 50; return p; }
    fn g<U>(self, u: U): U { return u; }
    fn h(self): Box<Pt> { var b: Box<Pt>; b.n = 60; return b; }
    fn i(self): bool { return false; }
    fn j(self): i64 { return 70; }
}
fn main(): i64 {
    var p = P { 1 };
    var q = Q { 2 };
    var r = p.f();
    var k, w = p.e();
    var bx = p.h();
    var s = p.a() + p.b() + r.x + k + bx.n + p.g(8) + p.j();
    var t = q.a() + q.b() + q.j();
    if (p.i()) { s = s + 100; }
    return s + t - 100;
}
syscall(60, main());
EOF
exits trk 131 "TRK: member and impl agree — i64 and none both ways, f64, *u128, (i64, f64), Pt, a generic's U (renamed V), Box<Pt>, bool; two impls"

# ── TP (6.7.16) — a generic member's own <U> after a *fn(..) in its signature ──
cat > "$T/tp1.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { x; }
trait Sh { fn g<U>(self, c: *fn(i64): i64, u: U): U; }
impl Sh for P { fn g<U>(self, c: *fn(i64): i64, u: U): U { return u; } }
fn main(): i64 { var p = P { 1 }; return p.g(0, 5); }
syscall(60, main());
EOF
exits tp1 5 "TP1: the filed repro verbatim — u: U after a *fn(..) (it was refused: unknown type 'U')"
printf "$R"'trait Sh { fn g<U>(self, u: U, c: *fn(i64): i64): U; }\nimpl Sh for P { fn g<U>(self, u: U, c: *fn(i64): i64): U { return u; } }\nfn main(): i64 { var p = P { 1 }; return p.g(5, 0); }\nsyscall(60, main());\n' > "$T/tp2.cyr"
exits tp2 5 "TP2: the *fn(..) last — the : U return after it"
printf "$R"'trait Sh { fn g<U>(self, cb: *fn(U): i64, u: U): U; }\nimpl Sh for P { fn g<U>(self, cb: *fn(U): i64, u: U): U { return u; } }\nfn main(): i64 { var p = P { 1 }; return p.g(0, 5); }\nsyscall(60, main());\n' > "$T/tp3.cyr"
exits tp3 5 "TP3: a U inside the *fn(U): i64 itself"
printf "$R"'trait Sh { fn g(self, c: *fn(i64): i64, u: i64): i64; }\nimpl Sh for P { fn g(self, c: *fn(i64): i64, u: i64): i64 { return u; } }\nfn main(): i64 { var p = P { 1 }; return p.g(0, 5); }\nsyscall(60, main());\n' > "$T/tp4.cyr"
exits tp4 5 "TP4: a non-generic member with a *fn(..) parameter unchanged"
printf "$R"'trait Sh { fn g<U>(self, c: *fn(i64): i64, u: Nope): U; }\nsyscall(60, 4);\n' > "$T/tp5.cyr"
refused_at tp5 "unknown type 'Nope' for parameter 'u'" 3:47 "TP5: an unknown name after a *fn(..) in a generic member stays refused"
printf 'include "lib/syscalls.cyr"\nfn h(c: *fn(i64): i64, u: U): i64 { return 1; }\nsyscall(60, 4);\n' > "$T/tp6.cyr"
refused_at tp6 "unknown type 'U' for parameter 'u'" 2:27 "TP6: a non-generic fn's U after a *fn(..) stays refused"

# ── TM (6.7.16, D9) — a member's return is held to a fn's whole return set ──
cat > "$T/tm1.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { x; }
enum Color { Red, Green }
trait Sh { fn a(self): u8; fn b(self): f32; fn c(self): Color; fn d(self): *fn(i64): i64; fn e(self): u64; }
fn main(): i64 { return 4; }
syscall(60, main());
EOF
FR="cannot be a fn return type"
FP='a fn-pointer type `*fn( .. )` cannot be a fn return type'
lines_are tm1 "TM1: the filed repro verbatim (it built: exit 4) — one line per member" \
    "4:24: type 'u8' $FR" "4:40: type 'f32' $FR" "4:57: type 'Color' $FR" "4:76: $FP" "4:103: type 'u64' $FR"
n=$(grep -c "^  note: a return type is a struct" "$T/tm1.err" || true)
if [ "$n" -eq 5 ]; then ok "TM1b: ... each with a fn's return-type note"; else bad "TM1b: $n notes (want 5)"; fi
cat > "$T/tm2.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { x; }
struct Pt { x; y; }
union Un { a: i64; b: f64; }
struct Box<T> { v: T; n; }
enum Color { Red, Green }
trait Sh {
    fn a(self): i64; fn b(self): f64; fn c(self): bool; fn d(self): Pt; fn e(self): *u8; fn f(self): Result;
    fn g<U>(self, u: U): U; fn h(self): i8; fn i(self): i32; fn j(self): cstring; fn k(self): Option;
    fn l(self): Tagged; fn m(self): *Color; fn n(self): (u8, Color); fn o(self): Box<i64>; fn p(self): Un;
    fn q(self): **u64; fn r(self): i16;
}
impl Sh for P {
    fn a(self): i64 { return 1; }
    fn b(self): f64 { return 1.5; }
    fn c(self): bool { return true; }
    fn d(self): Pt { var t: Pt; t.x = 2; t.y = 3; return t; }
    fn e(self): *u8 { return 0; }
    fn f(self): Result { return 0; }
    fn g<U>(self, u: U): U { return u; }
    fn h(self): i8 { return 4; }
    fn i(self): i32 { return 5; }
    fn j(self): cstring { return 0; }
    fn k(self): Option { return 0; }
    fn l(self): Tagged { return 0; }
    fn m(self): *Color { return 0; }
    fn n(self): (u8, Color) { return (6, 1); }
    fn o(self): Box<i64> { var b: Box<i64>; b.n = 7; return b; }
    fn p(self): Un { var u: Un; u.a = 8; return u; }
    fn q(self): **u64 { return 0; }
    fn r(self): i16 { return 9; }
}
fn main(): i64 {
    var p = P { 1 };
    var t = p.d();
    var w, c = p.n();
    var b = p.o();
    var u = p.p();
    var s = p.a() + t.x + t.y + p.g(10) + p.h() + p.i() + w + c + b.n + u.a + p.r();
    if (p.c()) { s = s + 100; }
    return s - 100;
}
syscall(60, main());
EOF
exits tm2 56 "TM2: what a fn returns still compiles in a member — i64, f64, bool, Pt, *u8, Result, its own U, i8/i16/i32, cstring, Option, Tagged, *Color, (u8, Color), Box<i64>, a union, **u64"
rc=0; "$CC" --syntax-only < "$T/tm1.cyr" > "$T/tm3.bin" 2> "$T/tm3.err" || rc=$?
grep '^error' "$T/tm3.err" > "$T/tm3.got" || true
printf 'error:<source>:4:76: %s\n' "$FP" > "$T/tm3.want"
if [ "$rc" -ne 0 ] && cmp -s "$T/tm3.got" "$T/tm3.want"; then ok "TM3: --syntax-only reports the *fn( .. ) line alone (as it does a fn's : *fn( .. ))"
else bad "TM3: --syntax-only rc $rc: $(tr '\n' '|' < "$T/tm3.got")"; fi
printf 'include "lib/syscalls.cyr"\nstruct P { x; }\nenum Color { Red, Green }\ntrait Sh { fn a(self): u8; fn b(self): f32; fn c(self): Color; fn e(self): u64; }\nsyscall(60, 4);\n' > "$T/tm3b.cyr"
rc=0; "$CC" --syntax-only < "$T/tm3b.cyr" > "$T/tm3b.bin" 2> "$T/tm3b.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/tm3b.err"; then ok "TM3b: --syntax-only is silent on u8 / f32 / an enum / u64, as for a fn's"
else bad "TM3b: --syntax-only rc $rc: $(grep '^error' "$T/tm3b.err" | head -1)"; fi
printf "$R"'trait Sd { fn d(self): *fn(i64): i64; }\nsyscall(60, 4);\n' > "$T/tm4.cyr"
refused_at tm4 "$FP" 3:24 "TM4: V4's Sd member (it built) — refused at its *"
printf "$R"'trait Sd { fn d(self): **fn(i64): i64; }\nsyscall(60, 4);\n' > "$T/tm4b.cyr"
refused_at tm4b "$FP" 3:24 "TM4b: a **fn( .. ) return, at its first *"
printf "$R"'trait T { fn c(self): u8; fn d(self): *fn(i64): i64; }\nimpl T for P { fn c(self): i64 { return 4; } fn d(self): i64 { return 5; } }\nsyscall(60, 0);\n' > "$T/tm5.cyr"
lines_are tm5 "TM5: an impl spelled : i64 adds nothing beside the members' refusals (it said 'P.c' returns i64, trait 'T' declares u8)" \
    "3:23: type 'u8' $FR" "3:39: $FP"
printf "$R"'struct Q { y; }\ntrait T { fn a(self): u16 { return 1; } }\nimpl T for P { fn a(self): i64 { return 2; } }\nimpl T for Q { fn a(self): i64 { return 3; } }\nsyscall(60, 0);\n' > "$T/tm5b.cyr"
lines_are tm5b "TM5b: a default two impls override — the trait's line alone" "4:23: type 'u16' $FR"
printf "$R"'trait T { fn c(self): Color; }\nenum Color { Red, Green }\nsyscall(60, 0);\n' > "$T/tm6.cyr"
refused_at tm6 "type 'Color' $FR" 3:23 "TM6: an enum declared below the trait"

# ── TRR (6.7.16 review) — a reader-refused side is judged by the names a reader reads ──
printf "$R"'struct Pt { x; y; }\ntrait T { fn c(self): Result<Pt<i64>>; }\nimpl T for P { fn c(self): i64 { return 4; } }\nsyscall(60, 0);\n' > "$T/trr1.cyr"
refused_at trr1 "'P.c' returns i64, trait 'T' declares Result<Pt<i64>>" 5:28 "TRR1: a member's : Result<Pt<i64>> (its list unread) against : i64 — the impl's line (it built)"
printf "$R"'struct Pt { x; y; }\ntrait T { fn c(self): Option<Pt<i64>>; }\nfn f(q: *P): i64 { var o: dyn T = q; return 0; }\nimpl T for P { fn c(self): i64 { return 4; } }\nsyscall(60, 0);\n' > "$T/trr2.cyr"
refused_at trr2 "'P.c' returns i64, trait 'T' declares Option<Pt<i64>>" 6:28 "TRR2: ... : Option<Pt<i64>> with a dyn formed above the impl — the impl's line alone"
BR='struct Box<T> { n: i64; v: T; }\nstruct Pt { x; y; }\nstruct P { a; b; }\n'
printf "$BR"'trait T2 { fn sh(self): Box<i64, Pt>; }\nimpl T2 for P { fn sh(self): Box { var b: Box; return b; } }\nfn main(): i64 { return 0; }\n' > "$T/trr3.cyr"
refused_at trr3 "'Box' takes 1 type argument, 2 given" 4:34 "TRR3: dd7 — a member's : Box<i64, Pt>, the impl's : Box — the reader's line alone"
printf "$BR"'trait T2 { fn sh(self): Box; }\nimpl T2 for P { fn sh(self): Box<i64, Pt> { var b: Box; return b; } }\nfn main(): i64 { return 0; }\n' > "$T/trr4.cyr"
refused_at trr4 "'Box' takes 1 type argument, 2 given" 5:39 "TRR4: dd8 — the impl's : Box<i64, Pt> — the reader's line alone"
printf "$BR"'trait T2 { fn sh(self): Option<Box<i64, Pt>>; }\nimpl T2 for P { fn sh(self): i64 { return 1; } }\nfn main(): i64 { return 0; }\n' > "$T/trr5.cyr"
refused_at trr5 "'P.sh' returns i64, trait 'T2' declares Option<Box<i64, Pt>>" 5:30 "TRR5: a member's : Option<Box<i64, Pt>> (its list unread) keeps the impl's line"
rc=0; "$CC" --syntax-only < "$T/trr3.cyr" > "$T/trr6.bin" 2> "$T/trr6.err" || rc=$?
grep '^error' "$T/trr6.err" > "$T/trr6.got" || true
printf "error:<source>:5:30: 'P.sh' returns Box, trait 'T2' declares Box<i64, Pt>\n" > "$T/trr6.want"
if [ "$rc" -ne 0 ] && cmp -s "$T/trr6.got" "$T/trr6.want"; then ok "TRR6: --syntax-only (D5 silent there) keeps dd7's impl line"
else bad "TRR6: --syntax-only rc $rc: $(tr '\n' '|' < "$T/trr6.got")"; fi
# ── TRR9 (6.7.16, f16 FG1) — lint keeps the impl's line where the reader's own refusal is silent under lint ──
lint_is() {   # <name> <what> [line:col message]...: --syntax-only gives exactly these error lines (none: rc 0, silent)
    nm=$1; what=$2; shift 2
    rc=0; "$CC" --syntax-only < "$T/$nm.cyr" > "$T/$nm.bin" 2> "$T/$nm.err" || rc=$?
    grep '^error' "$T/$nm.err" > "$T/$nm.got" || true
    : > "$T/$nm.want"
    for w in "$@"; do printf 'error:<source>:%s\n' "$w" >> "$T/$nm.want"; done
    if [ "$#" -eq 0 ] && [ "$rc" -ne 0 ]; then bad "$what: rc $rc: $(tr '\n' '|' < "$T/$nm.got")"
    elif [ "$#" -ne 0 ] && [ "$rc" -eq 0 ]; then bad "$what: rc 0, no line"
    elif ! cmp -s "$T/$nm.got" "$T/$nm.want"; then bad "$what: got $(tr '\n' '|' < "$T/$nm.got") want $(tr '\n' '|' < "$T/$nm.want")"
    else ok "$what: --syntax-only rc $rc, exactly $# line(s)"; fi
}
PQ='struct P { a; b; }\n'
printf "$PQ"'trait T2 { fn sh(self): u8; }\nimpl T2 for P { fn sh(self): i64 { return 1; } }\nfn f(q: *P): i64 { var o: dyn T2 = q; return 0; }\nfn main(): i64 { return 0; }\n' > "$T/trr9.cyr"
lint_is trr9 "TRR9: dd2 — a member's : u8 (D9, silent under lint) against : i64 keeps the impl's line (6.7.15's)" \
    "3:30: 'P.sh' returns i64, trait 'T2' declares u8"
printf "$PQ"'trait T2 { fn sh(self): u8; }\nfn f(q: *P): i64 { var o: dyn T2 = q; return 0; }\nimpl T2 for P { fn sh(self) { return 1; } }\nfn main(): i64 { return 0; }\n' > "$T/trr9b.cyr"
lint_is trr9b "TRR9b: dd1 — the impl with no return type, the dyn formed above it: at the method's name" \
    "4:20: 'P.sh' returns i64, trait 'T2' declares u8"
printf 'struct Pt { x; y; }\n'"$PQ"'trait T2 { fn sh(self): *Pt<i64>; }\nfn f(q: *P): i64 { var o: dyn T2 = q; return 0; }\nimpl T2 for P { fn sh(self): *Pt { return 0; } }\nfn main(): i64 { return 0; }\n' > "$T/trr9c.cyr"
lint_is trr9c "TRR9c: dd3 — a member's : *Pt<i64> (D7, silent under lint) against : *Pt" \
    "5:30: 'P.sh' returns *Pt, trait 'T2' declares *Pt<i64>"
printf "$PQ"'enum Color { Red, Green }\ntrait T2 { fn sh(self): Color; }\nimpl T2 for P { fn sh(self): i64 { return 1; } }\nfn f(q: *P): i64 { var o: dyn T2 = q; return 0; }\nfn main(): i64 { return 0; }\n' > "$T/trr9d.cyr"
lint_is trr9d "TRR9d: dd4 — a member's enum return against : i64" \
    "4:30: 'P.sh' returns i64, trait 'T2' declares Color"
printf "$PQ"'trait T2 { fn sh(self): i64; }\nimpl T2 for P { fn sh(self): u8 { return 1; } }\nfn main(): i64 { return 0; }\n' > "$T/trr9e.cyr"
lint_is trr9e "TRR9e: control — an impl's : u8 against a member's : i64 stays silent under lint (6.7.15's verdict)"
printf 'struct Pt { x; y; }\n'"$PQ"'trait T2 { fn sh(self): *Pt; }\nimpl T2 for P { fn sh(self): *Pt<i64> { return 0; } }\nfn main(): i64 { return 0; }\n' > "$T/trr9f.cyr"
lint_is trr9f "TRR9f: the method's side — an impl's : *Pt<i64> (6.7.15's D6, silent under lint) against : *Pt" \
    "4:30: 'P.sh' returns *Pt<i64>, trait 'T2' declares *Pt"
printf "$PQ"'trait T2 { fn sh(self): i64; }\nimpl T2 for P { fn sh(self): i64<u8> { return 0; } }\nfn main(): i64 { return 0; }\n' > "$T/trr9g.cyr"
lint_is trr9g "TRR9g: the method's side — an impl's scalar : i64<u8> against : i64" \
    "3:30: 'P.sh' returns i64<u8>, trait 'T2' declares i64"
printf "$PQ"'trait T2 { fn sh(self): f32; fn t(self): i64<u8>; }\nimpl T2 for P { fn sh(self): i64 { return 0; } fn t(self): i64 { return 0; } }\nfn main(): i64 { return 0; }\n' > "$T/trr9h.cyr"
lint_is trr9h "TRR9h: a member's : f32 and its scalar : i64<u8> — one impl line each" \
    "3:30: 'P.sh' returns i64, trait 'T2' declares f32" "3:60: 'P.t' returns i64, trait 'T2' declares i64<u8>"
lines_are trr9h "TRR9i: TRR9h compiled — the members' refusals alone (no impl line beside them)" \
    "2:25: type 'f32' $FR" "2:42: 'i64' takes no type arguments"

# ── FP (6.7.16, f16 FG2) — a fn's fn-pointer return is the member's one line, the body read on ──
# PARSE_FN_DEF's return reader took `: *fn(i64): i64` as a `*T` and met `fn` as a name: "expected identifier, got
# reserved keyword 'fn' (cannot be used as an identifier; rename the variable/field/fn)" — there is nothing to rename;
# a bare `: *fn` (and a nested `: *fn(..): *fn(..)`) went on to read the type's rest as the body ("fn 'main' is defined
# inside fn 'h'", "expected '}', got end of file"); a multi-value element added pass 1's "expected ')', got fn" and
# "'h' returns 2 values". Now the member's words (`_trs_fnp_refuse`) at the type's first `*`, with the return note,
# under --syntax-only too, the type stepped (`_fnp_ty_end`) and the body parsed; pass 1 records nothing for it. A
# member's bare `: *fn;` was "expected '(', got ';'": the same line now. An impl adds no "returns .." line beside a
# method's own refusal (a multi-value element too); a member's multi-value `*fn( .. )` element keeps the impl's line.
# Filed: docs/development/issues/2026-10-20-fn-pointer-return-type-refused-as-reserved-keyword-identifier.md
# Mutants (2026-10-21, a scratch copy of src/ with the one change, its cycc, CYCC= it): the lane before it (d280e29e1)
#   -> RED 18: TR8c FP1-FP8b FP10-FP11b FP13-FP13c; `_ret_ann_alt`'s arm gone -> RED 14 (all but the multi-value rows
#   FP7 FP8 FP8b); `_mret_elem`'s arm gone -> RED 3: FP7 FP8 FP8b; the method-side stand-down gone from `_tr_rt_bad` ->
#   RED 2: FP8 FP8b (the impl's line), and from the dyn hand-off (`_tr_ret_rf`) -> RED 1: FP8 (the site's line); the
#   stand-down on the member's side too -> RED 1: FP9 (it BUILT: nobody refused it); `_trs_ret_fnp` requiring the `(`
#   -> RED 7: FP3 FP4b FP7 FP10 FP11 FP11b FP13c; pass 1 stepping it unrecorded (no `_ret_ptr_annot`, the triage's
#   plan) -> RED 3: FP13 FP13b FP13c (each use "assigning non-pointer to typed pointer"); pass 2 not recording it ->
#   RED 1: FP13b (an instance minted in pass 2)
cat > "$T/fp1.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn h(): *fn(i64): i64 { return 0; }
fn main(): i64 { return 4; }
syscall(60, main());
EOF
lines_are fp1 "FP1: the filed repro verbatim — the fn-pointer line at its *" "2:9: $FP"
n=$(grep -c "^  note: a return type is a struct" "$T/fp1.err" || true)
if [ "$n" -eq 1 ]; then ok "FP1b: ... with a fn's return-type note"; else bad "FP1b: $n notes (want 1)"; fi
printf 'include "lib/syscalls.cyr"\nfn h(): **fn(i64): i64 { return 0; }\nfn main(): i64 { return 4; }\nsyscall(60, main());\n' > "$T/fp2.cyr"
lines_are fp2 "FP2: a **fn( .. ) return — one line at its first *" "2:9: $FP"
printf 'include "lib/syscalls.cyr"\nfn h(): *fn { return 0; }\nfn main(): i64 { return 4; }\nsyscall(60, main());\n' > "$T/fp3.cyr"
lines_are fp3 "FP3: a bare *fn return — one line, no cascade (it read the body as the type)" "2:9: $FP"
lint_is fp1 "FP4: --syntax-only of FP1 — the same line" "2:9: $FP"
lint_is fp3 "FP4b: --syntax-only of FP3 — the same line, no cascade" "2:9: $FP"
printf 'include "lib/syscalls.cyr"\nfn h(): *fn(i64): *fn(i64): i64 { return 0; }\nfn main(): i64 { return 4; }\nsyscall(60, main());\n' > "$T/fp5.cyr"
lines_are fp5 "FP5: a *fn( .. ) whose own return is a *fn( .. ) — one line" "2:9: $FP"
printf 'include "lib/syscalls.cyr"\nfn h(): *fn(i64): i64 { return 1 2; }\nfn main(): i64 { return 4; }\nsyscall(60, main());\n' > "$T/fp6.cyr"
lines_are fp6 "FP6: the body is read on — its own mistake is its own line" "2:9: $FP" "2:34: expected ';', got number 2"
printf 'include "lib/syscalls.cyr"\nfn h(): (*fn(i64): i64, i64) { return (0, 1); }\nfn k(): (i64, *fn) { return (0, 1); }\nfn main(): i64 { var a, b = h(); var c, d = k(); return b + d; }\nsyscall(60, main());\n' > "$T/fp7.cyr"
lines_are fp7 "FP7: a multi-value element *fn( .. ) / bare *fn — one line each (no pass-1 \"expected ')'\", no \"returns 2 values\")" \
    "2:10: $FP" "3:15: $FP"
printf "$R"'trait T { fn d(self): (i64, i64); }\nfn f(q: *P): i64 { var o: dyn T = q; return 0; }\nimpl T for P { fn d(self): (*fn(i64): i64, i64) { return (0, 1); } }\nfn g(q: *P): i64 { var o: dyn T = q; return 0; }\nsyscall(60, 0);\n' > "$T/fp8.cyr"
lines_are fp8 "FP8: an impl's multi-value *fn( .. ) element, a dyn formed above and below — the method's line alone" "5:29: $FP"
lint_is fp8 "FP8b: ... under --syntax-only" "5:29: $FP"
printf "$R"'trait T { fn d(self): (*fn(i64): i64, i64); }\nimpl T for P { fn d(self): (i64, i64) { return (0, 1); } }\nsyscall(60, 0);\n' > "$T/fp9.cyr"
lines_are fp9 "FP9: control — a member's multi-value *fn( .. ) element (read on by its reader) keeps the impl's line" \
    "4:28: 'P.d' returns (i64, i64), trait 'T' declares (*fn(i64): i64, i64)"
printf "$R"'trait T { fn d(self): *fn; }\nsyscall(60, 0);\n' > "$T/fp10.cyr"
lines_are fp10 "FP10: a member's bare : *fn return — the fn-pointer line (it was \"expected '(', got ';'\")" "3:23: $FP"
printf "$R"'trait T { fn d(self): i64; }\nfn f(q: *P): i64 { var o: dyn T = q; return 0; }\nimpl T for P { fn d(self): *fn { return 0; } }\nsyscall(60, 0);\n' > "$T/fp11.cyr"
lines_are fp11 "FP11: an impl's bare *fn return, a dyn formed above — the method's line alone (no impl line, no cascade)" "5:28: $FP"
printf "$R"'trait T { fn d(self): *fn; }\nimpl T for P { fn d(self): *fn { return 0; } }\nsyscall(60, 0);\n' > "$T/fp11b.cyr"
lines_are fp11b "FP11b: a member and its method both : *fn — one line each" "3:23: $FP" "4:28: $FP"
printf 'include "lib/syscalls.cyr"\nfn one(x: i64): i64 { return x; }\nfn ap(cb: *fn(i64): i64): i64 { return fncall1(cb, 2); }\nfn aq(cb: *fn): i64 { return 1; }\nfn ar(cb: **fn): i64 { return 1; }\nfn pu(): *u8 { return 0; }\nfn main(): i64 { return ap(&one) + aq(&one) + ar(0) + pu(); }\nsyscall(60, main());\n' > "$T/fp12.cyr"
exits fp12 4 "FP12: control — *fn( .. ) / bare *fn / **fn parameters and a : *u8 return unchanged"
fpuse() {   # <name> <what> <want-line>: exactly that one error and no warning (a refused return's uses add nothing)
    build "$1"
    grep -E '^(error|warning)' "$T/$1.err" > "$T/$1.got" || true
    printf 'error:<source>:%s\n' "$3" > "$T/$1.want"
    if [ "$rc" -ne 0 ] && cmp -s "$T/$1.got" "$T/$1.want"; then ok "$2: the one error, no warning"
    else bad "$2: rc $rc: $(tr '\n' '|' < "$T/$1.got")"; fi
}
printf 'include "lib/syscalls.cyr"\nfn main(): i64 { var q: *i32 = h(); var r = h() + 1; var s: *u8 = h(); return 4; }\nfn h(): *fn(i64): i64 { return 0; }\nsyscall(60, main());\n' > "$T/fp13.cyr"
fpuse fp13 "FP13: a forward call's result into *i32 / *u8 adds no \"assigning non-pointer to typed pointer\"" "3:9: $FP"
printf 'include "lib/syscalls.cyr"\nfn h<T>(x: T): *fn(T): i64 { return 0; }\nfn main(): i64 { var q: *i32 = h(1); var w: *u8 = h<i32>(2); return 4; }\nsyscall(60, main());\n' > "$T/fp13b.cyr"
fpuse fp13b "FP13b: a generic's — an explicit instance minted in pass 2 too" "2:16: $FP"
printf "$R"'impl P { fn h(self): *fn { return 0; } }\nfn main(): i64 { var p = P { 1 }; var q: *i32 = p.h(); return 4; }\nsyscall(60, main());\n' > "$T/fp13c.cyr"
fpuse fp13c "FP13c: an inherent method's bare *fn return, its call into *i32" "3:22: $FP"

# ── BF (6.7.16, f16 FG2, the user's D91) — a member's bare `*fn` parameter is a type, as a fn's ──
# The trait reader's `*fn` arm required the `(` ("expected '(', got ')'"), though 6.7.11's D34 (b) gave a fn's
# parameter a bare `*fn` and the impl's own method compiled with it. Now `cb: *fn` / `cb: **fn` read as a fn's do; a
# member's bare `: *fn` RETURN stays refused (FP10's line). BF1 the filed bf.cyr verbatim (exit 3); BF2 `cb: **fn`;
# BF3 --syntax-only of BF1 (rc 0); BF4 a bare `*fn` inside a member's `*fn( .. )` list and as its own return, and a
# `**fn` in the list — as a fn's parameter reader reads them; BF5 a member's `cb: *fn(i64): i64` unchanged; BF6 a
# member's bare `*fn` against a method's `cb: i64` — the impl compiles (parameter types are not compared by the impl
# check, the guide's word; dyn_checked.sh F8bf3 is the formed-dyn guard).
# Filed: docs/development/issues/2026-10-20-trait-member-bare-fn-pointer-parameter-refused.md
# Mutant (2026-10-21): the lane before it (6ee893493) -> RED 5: BF1-BF4 BF6 ("expected '(', got ')'")
cat > "$T/bf1.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { x; }
trait T { fn e(self, cb: *fn): i64; }
impl T for P { fn e(self, cb: *fn): i64 { return 3; } }
fn main(): i64 { var p = P { 1 }; return p.e(0); }
syscall(60, main());
EOF
exits bf1 3 "BF1: the filed repro verbatim (it was \"expected '(', got ')'\")"
printf "$R"'trait T { fn e(self, cb: **fn): i64; }\nimpl T for P { fn e(self, cb: **fn): i64 { return 3; } }\nfn main(): i64 { var p = P { 1 }; return p.e(0); }\nsyscall(60, main());\n' > "$T/bf2.cyr"
exits bf2 3 "BF2: a member's cb: **fn"
lint_is bf1 "BF3: --syntax-only of BF1 — clean"
printf "$R"'trait T { fn e(self, cb: *fn(*fn, **fn): *fn): i64; }\nimpl T for P { fn e(self, cb: *fn(*fn, **fn): *fn): i64 { return 4; } }\nfn main(): i64 { var p = P { 1 }; return p.e(0); }\nsyscall(60, main());\n' > "$T/bf4.cyr"
exits bf4 4 "BF4: a bare *fn / **fn inside a member's *fn( .. ) list and as its own return"
printf "$R"'fn one(x: i64): i64 { return x + 1; }\ntrait T { fn e(self, cb: *fn(i64): i64): i64; }\nimpl T for P { fn e(self, cb: *fn(i64): i64): i64 { return fncall1(cb, 4); } }\nfn main(): i64 { var p = P { 1 }; return p.e(&one); }\nsyscall(60, main());\n' > "$T/bf5.cyr"
exits bf5 5 "BF5: a member's cb: *fn(i64): i64 unchanged"
printf "$R"'trait T { fn e(self, cb: *fn): i64; }\nimpl T for P { fn e(self, cb: i64): i64 { return 6; } }\nfn main(): i64 { var p = P { 1 }; return p.e(0); }\nsyscall(60, main());\n' > "$T/bf6.cyr"
exits bf6 6 "BF6: a member's bare *fn against a method's cb: i64 — the impl check compares no parameter types"

# ── IB (6.7.16, f16 FF5) — a member of an impl body that is not a `fn` is one error, by name ──
# PARSE_IMPL's loop took directives, `pub` and `fn`; anything else ended it at "expected '}', got struct" (`var`, `enum`,
# a number), the `}` it wanted taken for that token, so the member's own braces and the rest of the body were read as
# top-level code ("expected '=', got '{'", "undefined variable 'z'", "undefined variable 'Q'") and the methods after it
# were never defined. Now "an impl body holds only `fn` definitions - in impl 'A'" (`- in impl 'Tr' for 'A'`), as a
# trait body's A7, at the member; it is stepped (`_impl_member_bad`: through its `;` or its own braces), its names
# entered as reported, and the body read on in sync; pass 1 steps it too, so the methods after it are registered. Each
# row on five legs (x86_64, PE and Mach-O env legs, the aarch64 / cx compilers built from this tree): the exact error
# lines, rc != 0, no binary. IB1 a struct member, the method after it called; IB2 a `var`, a stray number after the
# last method; IB3 an enum member of a trait impl; IB4 the struct's name used before and after the impl (an earlier
# fn's `q: *Q`, `Q { 1 }`) adds nothing; IB5 --syntax-only of IB1; IB6 control: directives, `pub` methods and a
# `#deprecated` one still build (run on x86_64: 7); IB7 a mistake in the method after the member is its own error.
# Mutants (2026-10-21, a scratch copy of the tree with the one change, its 2-stage cycc, this gate run from it):
#   the lane before it (bf1a3a6b2)                         -> RED IB1-IB5 IB7, 30 (the old "expected '}', got .." cascade)
#   PARSE_IMPL's loop ending at the member (pass 1 stepping) -> RED IB1-IB5 IB7, 30
#   `_prescan_impl_body` ending at the member               -> RED IB4, 5 (the struct's name not entered before `g`'s
#                                                              `q: *Q` is read)
#   `_impl_member_bad` keeping the report's latch          -> RED IB7, 5 (the method's own mistake swallowed)
IL="x86 pe macho"
if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> /dev/null && [ -s "$T/cc_a64" ]; then chmod +x "$T/cc_a64"; IL="$IL a64"
else bad "IB: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> /dev/null && [ -s "$T/cc_cx" ]; then chmod +x "$T/cc_cx"; IL="$IL cx"
else bad "IB: src/main_cx.cyr did not build"; fi
IBN=0
ibc() {   # <leg> <src> <out> [cc-arg]: rc in IRC
    IRC=0
    case "$1" in
        x86)   timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || IRC=$? ;;
        pe)    CYRIUS_TARGET_WIN=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || IRC=$? ;;
        macho) CYRIUS_MACHO=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || IRC=$? ;;
        a64)   timeout 60 "$T/cc_a64" ${4:-} < "$2" > "$3" 2> "$3.err" || IRC=$? ;;
        cx)    timeout 60 "$T/cc_cx" ${4:-} < "$2" > "$3" 2> "$3.err" || IRC=$? ;;
    esac
}
ibrow() {   # <id> <what> <source> <want-lines> [cc-arg]
    printf '%s' "$3" > "$T/$1.cyr"
    printf '%s\n' "$4" > "$T/$1.want"
    for leg in $IL; do
        o="$T/$1_$leg"
        ibc "$leg" "$T/$1.cyr" "$o" "${5:-}"
        IBN=$((IBN + 1))
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$IRC" -eq 0 ]; then bad "$1 $leg: $2: rc 0"
        elif ! cmp -s "$o.got" "$T/$1.want"; then bad "$1 $leg: $2: got $(wc -l < "$o.got") lines: $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ] && [ -z "${5:-}" ]; then bad "$1 $leg: $2: refused, but a binary was written"
        else ok "$1 $leg: $2"; fi
    done
}
IM='an impl body holds only `fn` definitions - in impl'
IZ="undefined variable 'zz' (missing include or enum?)"
ibrow IB1 "a struct member; the method after it is defined" 'struct A { y; }
impl A { struct Q { z; } fn m(self): i64 { return 1; } }
var a: A = A { 1 };
syscall(60, a.m() + zz);
' "error:<source>:2:10: $IM 'A'
error:<source>:4:23: $IZ"
ibrow IB2 "a var member, a stray number after the last method" 'struct A { y; }
impl A { var x = 1; fn m(self): i64 { return 1; } 5 }
var a: A = A { 1 };
syscall(60, a.m() + zz);
' "error:<source>:2:10: $IM 'A'
error:<source>:2:51: $IM 'A'
error:<source>:4:23: $IZ"
ibrow IB3 "an enum member of a trait impl" 'struct A { y; }
trait Tr { fn m(self): i64; }
impl Tr for A { enum E { X } fn m(self): i64 { return 1; } }
var a: A = A { 1 };
syscall(60, a.m() + zz);
' "error:<source>:3:17: $IM 'Tr' for 'A'
error:<source>:5:23: $IZ"
ibrow IB4 "the refused member's name used before and after the impl" 'struct A { y; }
fn g(q: *Q): i64 { return q.z; }
impl A { struct Q { z; } fn m(self): i64 { return 1; } }
fn h(): i64 { var q = Q { 1 }; return q.z; }
syscall(60, g(0) + h() + zz);
' "error:<source>:3:10: $IM 'A'
error:<source>:5:28: $IZ"
ibrow IB7 "a mistake in the method after a member is its own error" 'struct A { y; }
impl A { var x = 1; fn m(self): i64 { return 1 2; } }
var a: A = A { 1 };
syscall(60, a.m() + zz);
' "error:<source>:2:10: $IM 'A'
error:<source>:2:48: expected ';', got number 2
error:<source>:4:23: $IZ"
ibrow IB5 "--syntax-only: IB1's shape" 'struct A { y; }
impl A { struct Q { z; } fn m(self): i64 { return 1; } }
var a: A = A { 1 };
syscall(60, a.m());
' "error:<source>:2:10: $IM 'A'" --syntax-only
printf 'struct A { y; }\nimpl A {\n    #must_use\n    fn m(self): i64 { return 3; }\n    pub fn n(self): i64 { return 4; }\n    #deprecated("old")\n    fn o(self): i64 { return 0; }\n}\nvar a: A = A { 1 };\nsyscall(60, a.m() + a.n());\n' > "$T/ib6.cyr"
for leg in $IL; do
    ibc "$leg" "$T/ib6.cyr" "$T/ib6_$leg"
    IBN=$((IBN + 1))
    if [ "$IRC" -ne 0 ] || [ ! -s "$T/ib6_$leg" ] || grep -qE '^(error|warning)' "$T/ib6_$leg.err"; then bad "IB6 $leg: a well-formed impl: rc $IRC: $(grep -E '^(error|warning)' "$T/ib6_$leg.err" | tr '\n' '|')"
    elif [ "$leg" = x86 ]; then chmod +x "$T/ib6_x86"; got=0; "$T/ib6_x86" || got=$?
        if [ "$got" -eq 7 ]; then ok "IB6 x86: a well-formed impl (directives, pub) builds: exit 7"; else bad "IB6 x86: exit $got, want 7"; fi
    else ok "IB6 $leg: a well-formed impl builds"; fi
done
[ "$IBN" -ge 35 ] || bad "IB: the rows ran $IBN row-legs (floor 35) - rows or legs were lost"

if [ "$fails" -ne 0 ]; then echo "FAIL: traits_checked — $fails row(s) red"; exit 1; fi
echo "PASS: traits_checked — impl X for T is checked against trait X (8 refusals, each named), an ambiguous plain name is refused at a method call and explained on a direct call, well-formed traits build (declared below their impls too), trait is reserved, lib/trait.cyr is the run-time vtable pattern, and every trait member's signature is parsed (TS1-TS9 with the filed repro verbatim; V1-V4 still build); a member's \`: Vec<..>\` return is refused at the trait, once (TV, 6.7.15); an impl method's return type must be its member's, one type however it is spelled (TR, TRS, 6.7.15), and a return refusal does not end the impl's check (TRC, 6.7.16); a generic member's own <U> reads after a *fn(..) (TP, 6.7.16); a member's return is held to a fn's whole return set (TM, 6.7.16), and a reader-refused side is judged by the names a reader reads (TRR, 6.7.16); a fn's fn-pointer return is that line too, once, the body read on (FP, 6.7.16), and a member takes a bare *fn parameter (BF, 6.7.16); a non-fn member of an impl body is one error, the body read on (IB, 6.7.16)"
