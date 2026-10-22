#!/bin/sh
# Gate: an enum's members are separated by `;` or `,` (6.7.16, the user's decision D12, 2026-10-19: "Refuse it by
# name").
#
# THE DEFECT (measured on 6.7.15, x86_64; the shared front end, every target): the member loop of PARSE_ENUM_DEF stepped
# a `;` / `,` after a member when one was there and read the next member wherever the cursor stood, so
# `enum E { A B }` compiled (E.B = 1, as `{ A, B }`), `enum E { A = 1 B = 5 }` too (B = 5), and a `: stack` enum's
# `{ Ok(x) Err(e) }` (issues/archived/2026-10-18-enum-members-need-no-separator.md). Now a member that follows another with no
# separator is ONE error at it, "expected ';' or ',' between enum members" — once per enum (the enum's `}` releases
# the latch, so a second enum reports its own), under --syntax-only too, and a line break is no separator. A trailing
# separator stays valid, `;` and `,` mix, and the separated forms keep their values. A token that cannot start a
# member keeps the loop's own "expected identifier" (S8). 6.7.15's D1 (a) for a struct literal is the twin
# (tests/gates/frontend/struct_literal_type_refused.sh CM).
#
# G (6.7.16, met with issues/archived/2026-10-19-pass-one-enum-member-refusal-swallows-later-declaration-errors.md): a member
# token that is not a name is refused and registers NOTHING (`_enum_mem_name`). It was registered all the same, its
# token value read as a name offset — a number's (6, 7) or a keyword's named whatever stood there in the name table —
# so `enum F { X 6 }` + `enum G { Y 7 }` warned "duplicate symbol 'X' redefined with conflicting value" and an
# unclosed enum one "duplicate symbol 'enum'" per keyword it ran over. The refused member keeps its position.
#
# P (6.7.16, issues/archived/2026-10-19-pass-one-enum-member-refusal-swallows-later-declaration-errors.md): ANY refusal in an
# enum declaration — a member that is not a name ("expected identifier, got number 5" / "got ','"), a payload's
# parameter, the enum's name, its `: stack`, its `{` — ends at the enum's own `}`: pass 1 (no statement resync) held
# its panic latch to the end of the scan, so every later declaration's error was swallowed (`struct Q { a: Foo; }`,
# the next enum's). Pass 1's declaration step (`_tl_decl1`) releases a latch the declaration set when it ended in
# sync — the `}` just stepped, no other `}` and at most one `{` in it; D12's own release (`_enum_sep_end`) is folded
# into it. An enum whose body ran past its `}` keeps the latch: G2 (unclosed, run over a struct), G3 (a payload's
# `( .. )` left open, run into a fn body, whose release printed an invented "unmatched '}' at module scope").
#
# PS (6.7.16, met with the P fix): a struct's and a union's pass-1 refusals — a field that is not a name, a field's
# type (`a: 5`, `*5`, `Vec<5>`), the declaration's name — held the same latch to the end of pass 1 (`struct P { 5; }`
# swallowed `struct Q { a: Foo; }`'s error and the next enum's). `_tl_decl1` takes them too; an unclosed struct run
# over the next declarations keeps the latch (PSC1).
#
# Q (6.7.16, met with the P fix): THE WALKS AFTER PASS 1. Pass 2 (an enum's constructor bodies, a struct's / union's
# skip) and the enum-init walk re-read each declaration; a refusal's repeat there prints nothing but set the latch,
# which held into the next thing parsed — a fn body's first statement (Q1, Q4) or the program's first statement (Q2,
# Q3) lost its error; a refusal pass 2 makes itself (a stack enum's two-field variant) swallowed the same (Q8). Each is
# released at the declaration's `}` (`_tl_decl2`, `_tl_enum_init1`). And pass 2's struct / union skip says nothing
# pass 1 did not: a missing `{` was ERR's invented "unexpected identifier 'a'" beside pass 1's "expected '{'" (Q3, Q6),
# and an unclosed body ran to the watchdog's invented "unexpected end of input (truncated or unbalanced source)" (Q5).
#
# Refusal rows compare the whole diagnostic list and check that no binary was written, on the x86_64, aarch64, cx and
# PE (src/main_win.cyr, 6.7.16) compilers built from this tree (one front end). Acceptance rows run the x86_64 binary and compare the exit code.
#
# MUTATION LEDGER (measured; each mutant built from the fixed tree with the one change):
#   the lane's compiler before F5 (11dfa7bff)      -> RED S1-S7 x86 (each compiled, rc 0); S8 and every A row green
#   `_enum_sep` without its error                   -> RED S1-S7 x86
#   `_enum_sep_end` never releasing the latch       -> RED S5 S6 x86 (the second enum's error swallowed)
#   `_enum_sep` erring on any non-separator token   -> RED S8 x86 (a missing separator said before "expected identifier")
#   `_enum_mem_name` answering the refused token's value (453c5393b's registration) -> RED G1-G3 on every leg
#   the lane's compiler before the P fix (c27ab795f) -> RED G1 P1-P9 on every leg (the later declarations' errors
#                                                      swallowed)
#   `_tl_decl1` never releasing                      -> RED S5 S6 G1 P1-P9 on every leg
#   `_tl_decl_synced` answering 1 always             -> RED G2 G3 PSC1 on every leg (a run-on body's latch released)
#   the lane's compiler before the PS fix (3adc7ae7b) -> RED PS1-PS6 on every leg (the next struct's error swallowed;
#                                                      the enum's printed by pass 2 alone)
#   the lane's compiler before the Q fix (6b80792df) -> RED Q1-Q8 on every leg (Q7: "unexpected '<'", the statement's
#                                                      error swallowed)
#   `_tl_decl2` without its release                 -> RED Q1-Q4 Q7 Q8 on every leg
#   `_tl_enum_init1` without its release            -> RED Q2 on every leg
#   `_tl_skip_body` reporting with ERR again        -> RED Q3 Q4 Q6 Q7 on every leg
#   `_tl_skip_body` without its end-of-file stops   -> RED Q5a Q5c Q5d on every leg (Q5b: the `<..>` stop)
#   (6.7.17, genb) pass 2's struct skip stepping a `<..>` nested (44010cf5f) with the capture stepping past the end
#   of file -> RED Q5b on every leg (pass 2's "expected '{', got end of file" a second line, at the token after it);
#   Q5e / Q5f (`fn f<T`, `enum E<T` at the end of file) one line each (coverage: green on that compiler too)
#   (the f16 review) the lane before it (edcf462c8) -> RED PT1-PT7 on every leg (each header's latch swallowed the
#                                                      rest; PT3 an invented "expected '{', got ';'"; PT7 the statement)
#   `_tl_trait1` stepping one token again           -> RED PT1-PT6 on every leg (pass 1 stopped at the trait)
#   `_tr_hdr_step` without its release              -> RED PT4 PT5 on every leg (the next trait's header swallowed)
#   `_tl_trait2` without `_tl_decl_end`             -> RED PT7 on every leg
#   `_tr_hdr_end` without its declaration stop      -> RED PT5 on every leg (`trait U` took struct Q's body)
# (A mutant's legs other than x86 are built by it from the real tree, so they stay green.)
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=enum_member_separator
[ -x "$CC" ] || { echo "SKIP: $G: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: $G: mktemp -d failed"; exit 77; }
trap 'rm -rf "$D"' EXIT

pass=0; fail=0
ok()  { echo "  ok   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

A64=""; CXCC=""; PECC=""
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
    chmod +x "$D/cc_a64"; A64="$D/cc_a64"
else bad "aarch64: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ]; then
    chmod +x "$D/cc_cx"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr did not build"; fi
if "$CC" < src/main_win.cyr > "$D/cc_pe" 2> /dev/null && [ -s "$D/cc_pe" ]; then
    chmod +x "$D/cc_pe"; PECC="$D/cc_pe"
else bad "pe: src/main_win.cyr did not build"; fi
LEGS="x86"
[ -n "$A64" ] && LEGS="$LEGS a64"
[ -n "$CXCC" ] && LEGS="$LEGS cx"
[ -n "$PECC" ] && LEGS="$LEGS pe"

comp() {
    CRC=0
    case "$1" in
        x86) timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64) timeout 60 "$A64" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)  timeout 60 "$CXCC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        pe)  timeout 60 "$PECC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
}
# refuse ID LABEL SOURCE WANT [FLAG]: rc != 0, exactly the WANT lines, no binary — on every leg.
refuse() {
    printf '%s' "$3" > "$D/$1.cyr"
    printf '%s\n' "$4" > "$D/$1.want"
    for leg in $LEGS; do
        o="$D/$1_$leg"
        comp "$leg" "$D/$1.cyr" "$o" "${5:-}"
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        if [ "$CRC" -eq 0 ]; then bad "$1 $leg: $2: rc 0 — want the refusal"
        elif ! cmp -s "$o.got" "$D/$1.want"; then
            bad "$1 $leg: $2: got $(wc -l < "$o.got") lines: $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ]; then bad "$1 $leg: $2: refused, but a binary was written"
        else ok "$1 $leg: $2"; fi
    done
}
# accept ID LABEL SOURCE EXIT: compiles clean (no diagnostic) and the x86_64 binary exits EXIT.
accept() {
    printf '%s' "$3" > "$D/$1.cyr"
    o="$D/$1_x86"
    comp x86 "$D/$1.cyr" "$o"
    grep -E '^(error|warning)' "$o.err" > "$o.got" || true
    if [ "$CRC" -ne 0 ] || [ ! -s "$o" ]; then bad "$1: $2: compile rc $CRC: $(tr '\n' '|' < "$o.got")"; return; fi
    if [ -s "$o.got" ]; then bad "$1: $2: diagnostics: $(tr '\n' '|' < "$o.got")"; return; fi
    chmod +x "$o"
    xr=0; timeout 10 "$o" > /dev/null 2>&1 || xr=$?
    if [ "$xr" = "$4" ]; then ok "$1: $2 (exit $xr)"; else bad "$1: $2: exit $xr, want $4"; fi
}

M="expected ';' or ',' between enum members"

# S — a missing separator is one error at the member after it.
refuse S1 "the filed repro: enum E { A B }" 'enum E { A B }
syscall(60, E.B);
' "error:<source>:1:12: $M"
refuse S2 "the filed repro: enum E { A = 1 B = 5 }" 'enum E { A = 1 B = 5 }
syscall(60, B);
' "error:<source>:1:16: $M"
refuse S3 "a stack enum: { Ok(x) Err(e) }" 'enum E: stack { Ok(x) Err(e) }
fn f(): i64 { var t, v = Err(3); return t * 10 + v; }
syscall(60, f());
' "error:<source>:1:23: $M"
refuse S4 "three members, two missing: once" 'enum E { A B C }
syscall(60, E.C);
' "error:<source>:1:12: $M"
refuse S5 "two enums: each its own error" 'enum E { A B }
enum F { X = 3 Y }
syscall(60, E.B + F.Y);
' "error:<source>:1:12: $M
error:<source>:2:16: $M"
refuse S6 "a line break is no separator (then a second enum)" 'enum E {
    A = 1
    B = 5
}
enum F { X; Y Z; }
syscall(60, B);
' "error:<source>:3:5: $M
error:<source>:5:15: $M"
refuse S7 "--syntax-only: enum E { A B }" 'enum E { A B }
syscall(60, E.B);
' "error:<source>:1:12: $M" --syntax-only
refuse S8 "control: a non-member token keeps 'expected identifier'" 'enum E { A 5 }
syscall(60, E.A);
' "error:<source>:1:12: expected identifier, got number 5"

# G — a refused member registers nothing: no invented "duplicate symbol" warning.
refuse G1 "two enums, each with a number for a member" 'enum F { X 6 }
enum G { Y 7 }
syscall(60, 0);
' "error:<source>:1:12: expected identifier, got number 6
error:<source>:2:12: expected identifier, got number 7"
refuse G2 "an unclosed enum running over a struct and an enum" 'enum E { A 5
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:12: expected identifier, got number 5"
refuse G3 "a payload's ( .. ) running into a fn body" 'enum E: stack { A(x, 5 }
fn f(): i64 { if (1) { return 2; } return 1; }
struct Q { a: Foo; }
syscall(60, f());
' "error:<source>:1:22: expected identifier, got number 5"

# P — a refusal in an enum declaration ends at the enum's own `}`: the declarations after it report their own errors.
F="unknown type 'Foo' for struct field 'a'"
refuse P1 "the filed repro: enum E { A 5 }, struct Q { a: Foo; }, enum F { X 6 }" 'enum E { A 5 }
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:12: expected identifier, got number 5
error:<source>:2:15: $F
error:<source>:3:12: expected identifier, got number 6"
refuse P2 "an empty member: enum E { A, , B }" 'enum E { A, , B }
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:13: expected identifier, got ','
error:<source>:2:15: $F
error:<source>:3:12: expected identifier, got number 6"
refuse P3 "a payload's parameter: Some(5), then an enum" 'enum O: stack { Some(5) }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:22: expected identifier, got number 5
error:<source>:2:12: expected identifier, got number 6"
refuse P4 "the enum's name: enum 5 { A }" 'enum 5 { A }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:6: expected identifier, got number 5
error:<source>:2:15: $F"
refuse P5 "its stack: enum E: 5 { A }" 'enum E: 5 { A }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:9: expected stack, got number 5
error:<source>:2:15: $F"
refuse P6 "its brace: enum E A }; a reserved word as a member; pub" 'enum E A }
enum G { match, B }
pub enum H { C 5 }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:8: expected '{', got identifier 'A'
error:<source>:2:10: expected identifier, got reserved keyword 'match' (cannot be used as an identifier; rename the variable/field/fn)
error:<source>:3:16: expected identifier, got number 5
error:<source>:4:15: $F"
refuse P7 "D12's separator, then a member, then a struct" 'enum E { A B }
enum F { X 6 }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:12: $M
error:<source>:2:12: expected identifier, got number 6
error:<source>:3:15: $F"
refuse P8 "--syntax-only: the filed repro" 'enum E { A 5 }
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:12: expected identifier, got number 5
error:<source>:2:15: $F
error:<source>:3:12: expected identifier, got number 6" --syntax-only
refuse P9 "a refused member keeps its position: B == 2 holds after the release" 'enum E { A, 5, B }
#assert B == 2, "B keeps its position"
struct Q { a: Foo; }
syscall(60, B);
' "error:<source>:1:13: expected identifier, got number 5
error:<source>:3:15: $F"

# PS — a struct's or a union's refusal ends at its own `}` too.
refuse PS1 "a field that is not a name: struct P { 5; }, then a struct and an enum" 'struct P { 5; }
struct Q { a: Foo; }
enum E { A 5 }
syscall(60, 0);
' "error:<source>:1:12: expected identifier, got number 5
error:<source>:2:15: $F
error:<source>:3:12: expected identifier, got number 5"
refuse PS2 "a field's type: a: 5, a: *5, a: Vec<5>" 'struct P { a: 5; }
struct R { a: *5; }
struct T { a: Vec<5>; }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:15: expected identifier, got number 5
error:<source>:2:16: expected identifier, got number 5
error:<source>:3:19: expected identifier, got number 5
error:<source>:4:15: $F"
refuse PS3 "the struct's name: struct 5 { a; }" 'struct 5 { a; }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:8: expected identifier, got number 5
error:<source>:2:15: $F"
refuse PS4 "a union's field: union U { 5; }" 'union U { 5; }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:11: expected identifier, got number 5
error:<source>:2:15: $F"
refuse PS5 "a union's name and a union field's type, then an enum" 'union 5 { a; }
union U { a: 5; }
enum E { A 5 }
syscall(60, 0);
' "error:<source>:1:7: expected identifier, got number 5
error:<source>:2:14: expected identifier, got number 5
error:<source>:3:12: expected identifier, got number 5"
refuse PS6 "--syntax-only: PS1" 'struct P { 5; }
struct Q { a: Foo; }
enum E { A 5 }
syscall(60, 0);
' "error:<source>:1:12: expected identifier, got number 5
error:<source>:2:15: $F
error:<source>:3:12: expected identifier, got number 5" --syntax-only
refuse PSC1 "control: an unclosed struct run over two structs keeps the latch" 'struct P { a; 5
struct Q { a: Foo; }
struct R { b: Bar; }
syscall(60, 0);
' "error:<source>:1:15: expected identifier, got number 5"

# PT — a trait's refused header ends at the trait's end (6.7.16, the f16 review): pass 1 steps the trait (its body, or
# past a `;`, or to the next declaration) and goes on; pass 2 reports the header and releases its latch there; a member's
# refusal releases it at the trait's `}` (PT7: the program's first statement was swallowed).
refuse PT1 "trait 5 { }, then a struct, an enum and a fn's mistake" 'trait 5 { }
struct Q { a: Foo; }
enum F { X 6 }
fn f(): i64 { return zz; }
syscall(60, f());
' "error:<source>:1:7: expected identifier, got number 5
error:<source>:2:15: $F
error:<source>:3:12: expected identifier, got number 6
error:<source>:4:22: undefined variable 'zz' (missing include or enum?)"
refuse PT2 "trait T 5 { }" 'trait T 5 { }
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:9: expected '{', got number 5
error:<source>:2:15: $F
error:<source>:3:12: expected identifier, got number 6"
refuse PT3 "trait T<X> { fn m(self): i64; }: no member read as a top-level fn" 'trait T<X> { fn m(self): i64; }
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:8: expected '{', got '<'
error:<source>:2:15: $F
error:<source>:3:12: expected identifier, got number 6"
refuse PT4 "trait T: U { .. } and trait { .. } (no name)" 'trait T: U { fn m(self): i64; }
trait { fn m(self): i64; }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:8: expected '{', got ':'
error:<source>:2:7: expected identifier, got '{'
error:<source>:3:15: $F"
refuse PT5 "trait T; and a trait with no body before a struct" 'trait T;
trait U
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:8: expected '{', got ';'
error:<source>:3:1: expected '{', got struct
error:<source>:3:15: $F
error:<source>:4:12: expected identifier, got number 6"
refuse PT6 "--syntax-only: PT1's header" 'trait 5 { }
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:7: expected identifier, got number 5
error:<source>:2:15: $F
error:<source>:3:12: expected identifier, got number 6" --syntax-only
refuse PT7 "a trait member's refusal, then the program's first statement" 'trait T { var x; }
syscall(60, 1 2);
' "error:<source>:1:11: a trait body holds only \`fn\` declarations - in trait 'T'
error:<source>:2:15: expected ')', got number 2"

# Q — the walks after pass 1 end each declaration's refusal at its `}` too, and add nothing to pass 1's.
refuse Q1 "a refused enum, then a fn body's first statement" 'enum E { A 5 }
fn f(): i64 { var a = 1 2; return a; }
syscall(60, f());
' "error:<source>:1:12: expected identifier, got number 5
error:<source>:2:25: expected ';', got number 2"
refuse Q2 "a refused enum, then the program's first statement" 'enum E { A 5 }
syscall(60, 1 2);
syscall(60, zz);
' "error:<source>:1:12: expected identifier, got number 5
error:<source>:2:15: expected ')', got number 2
error:<source>:3:13: undefined variable 'zz' (missing include or enum?)"
refuse Q3 "a struct with no {: one error, then the program's first statement" 'struct P a; }
syscall(60, 1 2);
syscall(60, zz);
' "error:<source>:1:10: expected '{', got identifier 'a'
error:<source>:2:15: expected ')', got number 2
error:<source>:3:13: undefined variable 'zz' (missing include or enum?)"
refuse Q4 "a struct with no {, then a fn body's first statement" 'struct P a; }
fn f(): i64 { var a = 1 2; return a; }
syscall(60, f());
' "error:<source>:1:10: expected '{', got identifier 'a'
error:<source>:2:25: expected ';', got number 2"
refuse Q5a "an unclosed struct at the end of file" 'struct P {
' "error:<source>:1:11: expected '}', got end of file"
refuse Q5b "an unclosed generic header at the end of file" 'struct P<T
' "error:<source>:1:11: expected '{', got end of file"
refuse Q5e "an unclosed fn type-parameter list at the end of file" 'fn f<T
' "error:<source>:1:7: expected '(', got end of file"
refuse Q5f "an unclosed enum type-parameter list at the end of file" 'enum E<T
' "error:<source>:1:9: expected '{', got end of file"
refuse Q5c "an unclosed union at the end of file" 'union U {
' "error:<source>:1:10: expected '}', got end of file"
refuse Q5d "an unclosed generic struct, a field's unknown type" 'struct P<T> { a; b: Foo
' "error:<source>:1:21: unknown type 'Foo' for struct field 'b'
error:<source>:1:24: expected '}', got end of file"
refuse Q6 "a union with no {: one error, then a struct's" 'union U a; }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:9: expected '{', got identifier 'a'
error:<source>:2:15: $F"
# 6.7.17 (the user's D5): a generic union is refused by name in pass 1 ("a union takes no type parameters"), its list
# stepped in both passes — the program's first statement still reports its own
refuse Q7 "a generic union (D5's refusal), then the program's first statement" 'union U<T> { a; }
syscall(60, 1 2);
' "error:<source>:1:8: a union takes no type parameters
error:<source>:2:15: expected ')', got number 2"
refuse Q8 "pass 2's own refusal (a stack enum's two fields), then a fn body's" 'enum E: stack { A(x, y) }
fn f(): i64 { var a = 1 2; return a; }
syscall(60, f());
' "error:<source>:1:25: stack enum variant takes 0 or 1 fields (the pair holds tag + one payload)
error:<source>:2:25: expected ';', got number 2"

# U (6.7.16, issues/archived/2026-10-20-malformed-enum-member-use-cascades-no-struct-type-in-scope.md) — a USE of an enum whose
# body was refused is not a second error. The member loop registered the refused token's VALUE as a member's name
# offset, so `enum E { A 5 }` declared a constant named whatever the name pool held at offset 5 — "E" — and `E.A` was
# a field access on it: "no struct type in scope for 'E'" in the zone (U1, U2: since the zone's per-entry latch
# release), after the first statement (U3) and in a fn's later statement (U4). The token is stepped, never
# registered, and the enum's name is entered as reported, so a member the body never declared stands down (U5 `E.A`
# of `enum E { 5 }`, a store U6, a method call U7, the bare name U8). Controls: a name declared nowhere is still
# reported (U9 `Z.A`, A a member: "'Z' is not an enum"; U10 `Z.Q`: "undefined variable 'Z'"). RED on the lane before
# this bite: U1-U8 (each a second error).
UE="error:<source>:1:12: expected identifier, got number 5"
U5E="error:<source>:1:10: expected identifier, got number 5"
UF='fn f(): i64 { var z = 1; z = 2; '
refuse U1 "the zone: enum E { A 5 } then var q = E.A" 'enum E { A 5 }
var a = 1;
var q = E.A;
syscall(60, 0);
' "$UE"
refuse U2 "the zone's first entry: var q = E.A" 'enum E { A 5 }
var q = E.A;
syscall(60, 0);
' "$UE"
refuse U3 "after the first statement: var q = E.A" 'enum E { A 5 }
var a = 1;
a = 2;
var q = E.A;
syscall(60, 0);
' "$UE"
refuse U4 "a fn's later statement: var q = E.A" 'enum E { A 5 }
'"$UF"'var q = E.A; return q; }
syscall(60, f());
' "$UE"
refuse U5 "a member the body never declared: E.A of enum E { 5 }" 'enum E { 5 }
'"$UF"'var q = E.A; return q; }
syscall(60, f());
' "$U5E"
refuse U6 "... stored: E.A = 3" 'enum E { 5 }
'"$UF"'E.A = 3; return 0; }
syscall(60, f());
' "$U5E"
refuse U7 "... called: E.A(3)" 'enum E { 5 }
'"$UF"'E.A(3); return 0; }
syscall(60, f());
' "$U5E"
refuse U8 "... the bare name: var q = E" 'enum E { 5 }
'"$UF"'var q = E; return q; }
syscall(60, f());
' "$U5E"
refuse U9 "control: Z.A (A a member, Z declared nowhere)" 'enum E { A 5 }
var a = 1;
a = 2;
var q = Z.A;
syscall(60, 0);
' "$UE
error:<source>:4:9: 'Z' is not an enum"
refuse U10 "control: Z.Q (both declared nowhere)" 'enum E { 5 }
'"$UF"'var q = Z.Q; return q; }
syscall(60, f());
' "$U5E
error:<source>:2:41: undefined variable 'Z'"

# A — the separated forms compile, with the values they always had.
accept A1 "{ A, B } (E.B)" 'enum E { A, B }
syscall(60, E.B);
' 1
accept A2 "a trailing separator: { A, B, }" 'enum E { A, B, }
syscall(60, E.B);
' 1
accept A3 "{ A; B; }" 'enum E { A; B; }
syscall(60, E.B);
' 1
accept A4 "mixed: { A; B, C; D }" 'enum E { A; B, C; D }
syscall(60, E.D);
' 3
accept A5 "{ A = 1, B = 5 }" 'enum E { A = 1, B = 5 }
syscall(60, B);
' 5
accept A6 "a stack enum: { Ok(x), Err(e) }" 'enum E: stack { Ok(x), Err(e) }
fn f(): i64 { var t, v = Err(3); return t * 10 + v; }
syscall(60, f());
' 13
accept A7 "one member per line, each with its separator" 'enum E {
    A = 1,
    B = 5;
    C
}
syscall(60, B + C);
' 11

echo "$G: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
