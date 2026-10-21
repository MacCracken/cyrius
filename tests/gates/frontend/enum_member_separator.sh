#!/bin/sh
# Gate: an enum's members are separated by `;` or `,` (6.7.16, the user's decision D12, 2026-10-19: "Refuse it by
# name").
#
# THE DEFECT (measured on 6.7.15, x86_64; the shared front end, every target): the member loop of PARSE_ENUM_DEF stepped
# a `;` / `,` after a member when one was there and read the next member wherever the cursor stood, so
# `enum E { A B }` compiled (E.B = 1, as `{ A, B }`), `enum E { A = 1 B = 5 }` too (B = 5), and a `: stack` enum's
# `{ Ok(x) Err(e) }` (issues/2026-10-18-enum-members-need-no-separator.md). Now a member that follows another with no
# separator is ONE error at it, "expected ';' or ',' between enum members" — once per enum (the enum's `}` releases
# the latch, so a second enum reports its own), under --syntax-only too, and a line break is no separator. A trailing
# separator stays valid, `;` and `,` mix, and the separated forms keep their values. A token that cannot start a
# member keeps the loop's own "expected identifier" (S8). 6.7.15's D1 (a) for a struct literal is the twin
# (tests/gates/frontend/struct_literal_type_refused.sh CM).
#
# G (6.7.16, met with issues/2026-10-19-pass-one-enum-member-refusal-swallows-later-declaration-errors.md): a member
# token that is not a name is refused and registers NOTHING (`_enum_mem_name`). It was registered all the same, its
# token value read as a name offset — a number's (6, 7) or a keyword's named whatever stood there in the name table —
# so `enum F { X 6 }` + `enum G { Y 7 }` warned "duplicate symbol 'X' redefined with conflicting value" and an
# unclosed enum one "duplicate symbol 'enum'" per keyword it ran over. The refused member keeps its position.
#
# P (6.7.16, issues/2026-10-19-pass-one-enum-member-refusal-swallows-later-declaration-errors.md): ANY refusal in an
# enum declaration — a member that is not a name ("expected identifier, got number 5" / "got ','"), a payload's
# parameter, the enum's name, its `: stack`, its `{` — ends at the enum's own `}`: pass 1 (no statement resync) held
# its panic latch to the end of the scan, so every later declaration's error was swallowed (`struct Q { a: Foo; }`,
# the next enum's). Pass 1's declaration step (`_tl_decl1`) releases a latch the declaration set when it ended in
# sync — the `}` just stepped, no other `}` and at most one `{` in it; D12's own release (`_enum_sep_end`) is folded
# into it. An enum whose body ran past its `}` keeps the latch: G2 (unclosed, run over a struct), G3 (a payload's
# `( .. )` left open, run into a fn body, whose release printed an invented "unmatched '}' at module scope").
#
# Refusal rows compare the whole diagnostic list and check that no binary was written, on the x86_64, aarch64 and cx
# compilers built from this tree (one front end). Acceptance rows run the x86_64 binary and compare the exit code.
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
#   `_tl_decl_synced` answering 1 always             -> RED G2 G3 on every leg (a run-on body's latch released)
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

A64=""; CXCC=""
if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
    chmod +x "$D/cc_a64"; A64="$D/cc_a64"
else bad "aarch64: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ]; then
    chmod +x "$D/cc_cx"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr did not build"; fi
LEGS="x86"
[ -n "$A64" ] && LEGS="$LEGS a64"
[ -n "$CXCC" ] && LEGS="$LEGS cx"

comp() {
    CRC=0
    case "$1" in
        x86) timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64) timeout 60 "$A64" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)  timeout 60 "$CXCC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
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
error:<source>:2:18: $F
error:<source>:3:12: expected identifier, got number 6"
refuse P2 "an empty member: enum E { A, , B }" 'enum E { A, , B }
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:13: expected identifier, got ','
error:<source>:2:18: $F
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
error:<source>:2:18: $F"
refuse P5 "its stack: enum E: 5 { A }" 'enum E: 5 { A }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:9: expected stack, got number 5
error:<source>:2:18: $F"
refuse P6 "its brace: enum E A }; a reserved word as a member; pub" 'enum E A }
enum G { match, B }
pub enum H { C 5 }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:8: expected '{', got identifier 'A'
error:<source>:2:10: expected identifier, got reserved keyword 'match' (cannot be used as an identifier; rename the variable/field/fn)
error:<source>:3:16: expected identifier, got number 5
error:<source>:4:18: $F"
refuse P7 "D12's separator, then a member, then a struct" 'enum E { A B }
enum F { X 6 }
struct Q { a: Foo; }
syscall(60, 0);
' "error:<source>:1:12: $M
error:<source>:2:12: expected identifier, got number 6
error:<source>:3:18: $F"
refuse P8 "--syntax-only: the filed repro" 'enum E { A 5 }
struct Q { a: Foo; }
enum F { X 6 }
syscall(60, 0);
' "error:<source>:1:12: expected identifier, got number 5
error:<source>:2:18: $F
error:<source>:3:12: expected identifier, got number 6" --syntax-only
refuse P9 "a refused member keeps its position: B == 2 holds after the release" 'enum E { A, 5, B }
#assert B == 2, "B keeps its position"
struct Q { a: Foo; }
syscall(60, B);
' "error:<source>:1:13: expected identifier, got number 5
error:<source>:3:18: $F"

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
