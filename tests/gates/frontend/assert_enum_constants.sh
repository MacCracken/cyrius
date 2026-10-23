#!/bin/sh
# 6.6.10: `#assert` and array sizes accept enum constants, bare AND qualified.
#
# Before 6.6.10:
#   - `#assert EB == 4` / `#assert E.EB == 4` were refused ("expected number or
#     sizeof()") at top level and in a fn, on every backend — #assert's evaluator
#     predates the enum-constant fold.
#   - `var buf[E.EB]`, `var a: i64[E.EB]` and the fn-local `var b[E.EB]` were refused;
#     only the bare `var buf[EB]` worked (while `syscall(60, E.EB)` compiled).
#   - the sizeof recogniser matched a 6-byte PREFIX, so `#assert sizeofzz(P) == 16`
#     compiled rc 0 as if it were sizeof.
#   - a bad operand printed two errors: the real one and a message-less
#     "#assert failed" cascade.
#   - anything AFTER the operands was skipped unchecked, so `#assert E.EB * 2 == 9;`
#     evaluated E.EB alone and a FALSE assertion compiled rc 0 (so did `#assert 4 == 4
#     junk;`). Only `,`, the message string, `;`, EOF or the next line may follow the
#     operands now.
#   - the cascade guard fired on ANY latched error, so an independent failing #assert
#     after an earlier unresynced error was swallowed; only this assert's own latch counts.
# One shared recogniser (_enum_atom_idx, parse.cyr) now serves #assert and both
# array-size parsers; pass 1 (_assert_skip_atom) steps over the 1- and 3-token forms.
# CHANGELOG [6.6.10]
# ⭐ 6.7.2 (B1, C1): #assert and array sizes are CONST CONTEXTS (the user's decision, 2026-10-07):
# any const expression — arithmetic, `&&` / `||`, consts, sizeof, const fn calls — evaluated by
# the one evaluator (`_ce_*`, parse/fn.cyr), which replaced _EVAL_CONST_ATOM / _enum_atom_idx /
# _assert_skip_atom. So `#assert E.EB * 2 == 8` PASSES and `== 9` FAILS as an assertion (both
# were "no arithmetic inside #assert"); what may follow the expression is unchanged (junk is
# refused), and the refusals name the name (`unknown name 'foo'`, `'p' is a variable`).
#
# 6.6.11 (N4): the qualified form never checked its BASE. `Foo.EB` (no enum Foo) and
# `F.EB` (EB belongs to E) compiled in expressions, #assert and array sizes, `Nope.gz`
# loaded the plain global gz, and with a variant name shared by two enums `A.X` read the
# LAST X. One resolver (_enum_qual_resolve, parse.cyr) serves all three sites now: the
# base must be an enum and the variant must be ITS variant, looked up in that enum.
# An enum NAME may be declared more than once, so the parent is matched by NAME, not id.
# Mutation: make _enum_qual_resolve `return FINDVAR(S, vn);` -> every N4 refusal compiles
# (rc 0) and the shared-name row exits 22 (want 12); match the parent by the FIRST enum of
# that name only -> the re-declared-enum row is refused (`'SB' is not a variant of 'Sig'`).
#
# EQ (6.7.16, issues/archived/2026-10-19-enum-qualified-unknown-member-named-as-unknown-enum.md): `Color.NOPE`, Color a
# declared enum and NOPE declared nowhere, blamed the ENUM — "undefined variable 'Color'" (an expression), "unknown
# name 'Color' in a const context" (a const, a case label, an array size, #assert): the resolver answered such a
# member -1 silently and each caller fell back to its undefined-name report for the base. Now it is the resolver's
# own "'NOPE' is not a variant of 'Color'" at NOPE, in every context: the factor (a chain and a call after it
# consumed), a const context, a global array's element, and the statement / `&` paths that never reached the resolver
# (`Color.NOPE = 4;`, `+= 1`, `Color.NOPE;`, `Color.NOPE();`, `Color.NOPE.x = 1;`, `&Color.NOPE` — which added "the
# address of a field is not taken"); `Color.NOPE2 = 4;` (NOPE2 a global of no enum) and `Color.RED();` there blamed
# Color too (now the resolver's words / `Color.RED;`'s "expected '='"). Each refusal ends in sync, the 6.6.11 reports
# too: the statement after it is parsed and reported (it was lost). A base that is no enum keeps its report (EQC1);
# under --syntax-only an unknown member in run-time code stays opaque (a file read alone may lack the enum's other
# declaration) while a const context names it (EQ9, EQC3). Exact lines on x86_64, PE, Mach-O and the aarch64 / cx
# compilers built from this tree.
# EQ MUTATION LEDGER (each a one-edit copy of the tree, its 2-stage cycc, this gate run from the copy with CYCC=):
#   the lane's compiler before EQ (befee5bc0)         -> RED EQ1-EQ10 on every leg
#   `_enum_qual_bad_any` answering 0 (no report)        -> RED EQ1-EQ10 on every leg
#   `_refuse_in_sync` dropped from `_enum_qual_bad_any` -> RED EQ5-EQ8 on every leg (the next statement lost)
#   ... and from the resolver's two 6.6.11 reports      -> RED EQ7 on every leg
#   `_enum_qual_bad` without its --syntax-only stand-down -> RED EQC3 on every leg
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: assert_enum_constants: no build/cycc"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: assert_enum_constants: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
cd "$ROOT"

fail=0
bad() { echo "FAIL: assert_enum_constants: $*"; fail=1; }

HDR='enum E { EA = 1; EB = 4; }
enum F { FC = 5; }
var gz = 9;
struct P { x; y; }'

# ok LABEL WANT_EXIT SOURCE — must compile and exit WANT_EXIT
ok() {
    printf '%s\n%s\n' "$HDR" "$3" > "$D/t.cyr"
    if ! "$CC" < "$D/t.cyr" > "$D/t.bin" 2> "$D/t.err"; then
        bad "$1: refused:"; grep '^error' "$D/t.err" | head -3; return 0
    fi
    chmod +x "$D/t.bin"; rc=0; "$D/t.bin" || rc=$?
    [ "$rc" = "$2" ] || bad "$1: exit $rc, want $2"
}
# no LABEL PATTERN SOURCE — must be refused with exactly ONE error line matching PATTERN
no() {
    printf '%s\n%s\n' "$HDR" "$3" > "$D/t.cyr"
    if "$CC" < "$D/t.cyr" > "$D/t.bin" 2> "$D/t.err"; then bad "$1: compiled, want refused"; return 0; fi
    n=$(grep -c '^error' "$D/t.err")
    [ "$n" = 1 ] || { bad "$1: $n errors, want exactly 1:"; grep '^error' "$D/t.err" | head -3; }
    grep -q "$2" "$D/t.err" || { bad "$1: error does not match '$2':"; head -2 "$D/t.err"; }
}

ok "bare #assert, top level"      7 '#assert EB == 4;
syscall(60, 7);'
ok "qualified #assert, top level" 7 '#assert E.EB == 4;
#assert EA < E.EB;
syscall(60, 7);'
ok "#assert in a fn, both forms"  3 'fn f(): i64 { #assert E.EB == 4; #assert EB > EA; return 3; }
syscall(60, f());'
ok "#assert after the first statement" 7 'var z = 1;
#assert E.EB == 4;
#assert sizeof(P) == 16;
syscall(60, 7);'
ok "wrapped qualified #assert, then a fn (pass-1 alignment)" 9 '#assert E.EB == 4,
  "wrapped";
fn g(): i64 { return 9; }
syscall(60, g());'
no "failing qualified #assert"  '#assert failed: nope' '#assert E.EB == 5, "nope";
syscall(60, 7);'
no "sizeof is a whole word"     "unknown fn 'sizeofzz'" '#assert sizeofzz(P) == 16;
syscall(60, 7);'
no "bad atom reports once (no #assert-failed cascade)" "unknown name 'foo'" '#assert foo == 1;
syscall(60, 7);'
no "a VARIABLE base is a field access, not an enum" "'p' is a variable" 'var p = 0;
#assert p.x == 0;
syscall(60, 7);'
AR='#assert: expected `,` or `;` after the expression'
# The comma-less message form is still accepted (tests/gates/diagnostics/
# resolution_excerpt_and_assert_skip.sh axis 3 relies on it) and still printed on failure.
ok "comma-less message after the operands" 7 '#assert E.EB == 4 "fine";
syscall(60, 7);'
no "comma-less message on a failing assert" '#assert failed: nocomma' '#assert E.EB == 5 "nocomma";
syscall(60, 7);'
no "arithmetic after an enum atom (false assert, in a fn) — evaluated (6.7.2)" '#assert failed' 'fn f(): i64 { #assert E.EB * 2 == 9; return 5; }
syscall(60, f());'
ok "arithmetic after an enum atom (true) — evaluated (6.7.2)" 7 '#assert E.EB * 2 == 8;
syscall(60, 7);'
no "arithmetic between literals — evaluated (6.7.2)" '#assert failed' '#assert 4 * 2 == 9;
syscall(60, 7);'
no "junk after the comparison" "$AR" '#assert 4 == 4 junk junk;
syscall(60, 7);'
no "junk after a lone atom" "$AR" '#assert 5 junk;
syscall(60, 7);'
no "a bad atom followed by arithmetic still reports once" "unknown name 'foo'" '#assert foo * 2 == 1;
syscall(60, 7);'

# N4 (6.6.11): the base of `Base.NAME` must be NAME's own enum, at every site.
NE="'Foo' is not an enum"
NV="'EB' is not a variant of 'F'"
no "expr: an unknown base"                "$NE" 'var a = Foo.EB;
syscall(60, a);'
no "expr: another enum's variant"         "$NV" 'var b = F.EB;
syscall(60, b);'
no "expr: another enum's variant, in a fn" "$NV" 'fn f(): i64 { return F.EB; }
syscall(60, f());'
no "expr: a plain global through a non-enum" "'Nope' is not an enum" 'var c = Nope.gz;
syscall(60, c);'
no "expr: a plain global through an enum" "'gz' is not a variant of 'E'" 'var c = E.gz;
syscall(60, c);'
no "#assert: an unknown base"             "$NE" '#assert Foo.EB == 4, "x";
syscall(60, 7);'
no "#assert: another enum's variant"      "$NV" '#assert F.EB == 4;
syscall(60, 7);'
no "array size: another enum's variant"   "$NV" 'var arr[F.EB];
syscall(60, 7);'
no "typed array size: an unknown base"    "$NE" 'var arr: i64[Foo.EB];
syscall(60, 7);'
no "fn-local array size: another enum's variant" "$NV" 'fn f(): i64 { var b[F.EB]; return 0; }
syscall(60, f());'
# ANTI-VACUOUS: each enum's own variants, at every site.
ok "expr + #assert + array size through the right enums" 9 'var arr[F.FC];
#assert F.FC == 5;
fn f(): i64 { var b[F.FC]; #assert E.EB == 4; return F.FC + E.EB; }
syscall(60, f());'
# A variant name shared by two enums: each qualified access reads ITS enum's constant (the
# bare name keeps "last definition wins", with its warning).
printf '%s\n' 'enum A { X = 1; }' 'enum B { X = 2; }' '#assert A.X == 1;' '#assert B.X == 2;' \
    'var q[A.X];' 'syscall(60, A.X * 10 + B.X);' > "$D/dup.cyr"
if "$CC" < "$D/dup.cyr" > "$D/dup" 2> "$D/dup.err"; then
    chmod +x "$D/dup"; rc=0; "$D/dup" || rc=$?
    [ "$rc" = 12 ] || bad "shared variant name: exit $rc, want 12 (A.X read B's X)"
else
    bad "shared variant name: refused:"; grep '^error' "$D/dup.err" | head -3
fi

# An enum NAME may be declared more than once (lib/syscalls*.cyr each declare `Signal`): a
# qualified variant resolves through ANY enum of that name, and only a name in none is refused.
printf '%s\n' 'enum Sig { SA = 1; }' 'enum Sig { SB = 2; }' '#assert Sig.SB == 2;' 'var q[Sig.SA];' \
    'syscall(60, Sig.SA * 10 + Sig.SB);' > "$D/dupenum.cyr"
if "$CC" < "$D/dupenum.cyr" > "$D/dupenum" 2> "$D/dupenum.err"; then
    chmod +x "$D/dupenum"; rc=0; "$D/dupenum" || rc=$?
    [ "$rc" = 12 ] || bad "a re-declared enum name: exit $rc, want 12"
else
    bad "a re-declared enum name: refused:"; grep '^error' "$D/dupenum.err" | head -3
fi
printf '%s\n' 'enum Sig { SA = 1; }' 'enum Sig { SB = 2; }' 'enum T { SC = 3; }' 'syscall(60, Sig.SC);' > "$D/dupenum2.cyr"
if "$CC" < "$D/dupenum2.cyr" > /dev/null 2> "$D/dupenum2.err"; then bad "a re-declared enum name: Sig.SC compiled, want refused"
else grep -q "'SC' is not a variant of 'Sig'" "$D/dupenum2.err" || bad "a re-declared enum name: Sig.SC refused for another reason: $(head -1 "$D/dupenum2.err")"; fi

# An earlier, unresynced error must not swallow an independent failing #assert: both report.
printf '%s\n%s\n' "$HDR" 'struct Q { a; b: ; }
#assert 1 == 2, "real2";
syscall(60, 7);' > "$D/t.cyr"
if "$CC" < "$D/t.cyr" > "$D/t.bin" 2> "$D/t.err"; then
    bad "earlier error + failing #assert: compiled, want refused"
else
    n=$(grep -c '^error' "$D/t.err")
    [ "$n" = 2 ] || { bad "earlier error + failing #assert: $n errors, want 2:"; grep '^error' "$D/t.err" | head -3; }
    grep -q '#assert failed: real2' "$D/t.err" || bad "earlier error + failing #assert: the assert failure was swallowed"
fi

# Array sizes: the qualified form must produce the SAME binary as the bare form.
arr() {
    printf '%s\n' "$HDR" "var buf[$1];" "var a: i64[$1];" "var tail = 77;" \
        "fn f(): i64 { var b[$1]; var i = 0; while (i < $1) { store64(&buf + i * 8, i); store64(&a + i * 8, i * 2); i = i + 1; } store64(&b, 5); return load64(&buf + 24) + load64(&a + 24) + load64(&b) + tail; }" \
        "var z = 1;" "var late[$1];" "store64(&late + 24, 1);" "syscall(60, f() + load64(&late + 24));"
}
arr EB > "$D/ab.cyr"
arr E.EB > "$D/aq.cyr"
if "$CC" < "$D/ab.cyr" > "$D/ab" 2>/dev/null && "$CC" < "$D/aq.cyr" > "$D/aq" 2> "$D/aq.err"; then
    cmp -s "$D/ab" "$D/aq" || bad "arrays: var buf[E.EB] (top level, typed, fn-local, after the first statement) differs from var buf[EB]"
    chmod +x "$D/aq"; rc=0; "$D/aq" || rc=$?
    [ "$rc" = 92 ] || bad "arrays: exit $rc, want 92"
else
    bad "arrays: a qualified size was refused:"; grep '^error' "$D/aq.err" | head -3
fi

# The frontend is shared: the qualified forms compile on the aarch64 and cx backends too
# (cross compilers built from source, so a revert cannot hide behind a stale binary).
printf '%s\n%s\n' "$HDR" 'fn f(): i64 { #assert E.EB == 4; var b[E.EB]; return 3; }
#assert E.EB == 4;
var buf[E.EB];
syscall(60, f());' > "$D/x.cyr"
for fork in main_aarch64 main_cx; do
    if "$CC" < "src/$fork.cyr" > "$D/cc_$fork" 2>/dev/null; then
        chmod +x "$D/cc_$fork"
        "$D/cc_$fork" < "$D/x.cyr" > "$D/x_$fork" 2> "$D/x_$fork.err" || { bad "$fork: qualified forms refused:"; grep '^error' "$D/x_$fork.err" | head -2; }
        # 6.6.11 (N4): and the wrong-enum form is refused there too
        printf '%s\n%s\n' "$HDR" 'fn f(): i64 { return F.EB; }
syscall(60, f());' > "$D/xw.cyr"
        if "$D/cc_$fork" < "$D/xw.cyr" > /dev/null 2> "$D/xw_$fork.err"; then bad "$fork: F.EB compiled, want refused"
        else grep -q "'EB' is not a variant of 'F'" "$D/xw_$fork.err" || bad "$fork: F.EB refused for another reason: $(head -1 "$D/xw_$fork.err")"; fi
    else
        bad "$fork: cross-compiler build failed"
    fi
done

# ── EQ — a member declared nowhere, after a base that is an enum: "'NOPE' is not a variant of 'Color'" ──
EA64=""; ECX=""
if "$CC" < src/main_aarch64.cyr > "$D/eq_a64" 2> /dev/null && [ -s "$D/eq_a64" ]; then chmod +x "$D/eq_a64"; EA64="$D/eq_a64"
else bad "EQ: src/main_aarch64.cyr did not build"; fi
if "$CC" < src/main_cx.cyr > "$D/eq_cx" 2> /dev/null && [ -s "$D/eq_cx" ]; then chmod +x "$D/eq_cx"; ECX="$D/eq_cx"
else bad "EQ: src/main_cx.cyr did not build"; fi
ELEGS="x86 pe macho"
[ -n "$EA64" ] && ELEGS="$ELEGS a64"
[ -n "$ECX" ] && ELEGS="$ELEGS cx"
eqcomp() {
    CRC=0
    case "$1" in
        x86)   timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        pe)    CYRIUS_TARGET_WIN=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        macho) CYRIUS_MACHO=1 timeout 60 "$CC" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        a64)   timeout 60 "$EA64" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
        cx)    timeout 60 "$ECX" ${4:-} < "$2" > "$3" 2> "$3.err" || CRC=$? ;;
    esac
}
EQN=0
# eq ID WHAT SOURCE WANT [FLAG]: refused on every leg (rc != 0, no binary), its error / warning lines exactly WANT
eq() {
    printf '%s' "$3" > "$D/$1.cyr"
    printf '%s\n' "$4" > "$D/$1.want"
    for leg in $ELEGS; do
        o="$D/$1_$leg"
        eqcomp "$leg" "$D/$1.cyr" "$o" "${5:-}"
        grep -E '^(error|warning)' "$o.err" > "$o.got" || true
        EQN=$((EQN + 1))
        if [ "$CRC" -eq 0 ]; then bad "$1 $leg: $2: rc 0 - want the refusal"
        elif ! cmp -s "$o.got" "$D/$1.want"; then bad "$1 $leg: $2: got $(wc -l < "$o.got") lines: $(tr '\n' '|' < "$o.got")"
        elif [ -s "$o" ]; then bad "$1 $leg: $2: refused, but a binary was written"; fi
    done
}
NC="'NOPE' is not a variant of 'Color'"
eq EQ1 "the filed repro: a const, then a fn's expression" 'enum Color { RED, GREEN }
const K = Color.NOPE;
fn main(): i64 { var y = Color.NOPE; return y; }
syscall(60, main() + K);
' "error:<source>:2:17: $NC
error:<source>:3:32: $NC"
eq EQ2 "a case label (two)" 'enum Color { RED, GREEN }
fn f(y): i64 { switch (y) { case Color.NOPE: return 1; case Color.NOPE2: return 3; default: return 2; } return 0; }
syscall(60, f(1));
' "error:<source>:2:40: $NC
error:<source>:2:67: 'NOPE2' is not a variant of 'Color'"
eq EQ3 "array sizes: a typed global, a global, a local; then a statement" 'enum R { A, B }
var g: i64[R.NOPE];
var arr[R.NOPE];
fn f(): i64 { var a: i64[R.NOPE]; var p = 1 2; return 0; }
syscall(60, f());
' "error:<source>:2:14: 'NOPE' is not a variant of 'R'
error:<source>:3:11: 'NOPE' is not a variant of 'R'
error:<source>:4:28: 'NOPE' is not a variant of 'R'
error:<source>:4:45: expected ';', got number 2"
eq EQ4 "#assert, and a global array's element" 'enum Color { RED, GREEN }
#assert Color.NOPE == 1, "m"
var ga[2] = {Color.NOPE, 2};
syscall(60, 0);
' "error:<source>:2:15: $NC
error:<source>:3:20: $NC"
eq EQ5 "the statement and & forms, each then the next statement" 'enum Color { RED, GREEN }
fn f(): i64 {
    var p = 0;
    Color.NOPE = 4;
    p = 1 2;
    Color.NOPE += 1;
    Color.NOPE;
    Color.NOPE();
    var s = &Color.NOPE;
    p = 1 3;
    Color.NOPE.x = 1;
    return zz;
}
syscall(60, f());
' "error:<source>:4:11: $NC
error:<source>:5:11: expected ';', got number 2
error:<source>:6:11: $NC
error:<source>:7:11: $NC
error:<source>:8:11: $NC
error:<source>:9:20: $NC
error:<source>:10:11: expected ';', got number 3
error:<source>:11:11: $NC
error:<source>:12:12: undefined variable 'zz' (missing include or enum?)"
eq EQ6 "the value forms: a chain, a call, a range bound; each then the next statement" 'enum Color { RED, GREEN }
fn f(): i64 {
    var a = Color.NOPE.x;
    a = 1 2;
    var b = Color.NOPE(5);
    a = 1 3;
    for i in 0..Color.NOPE { a = i; }
    a = 1 4;
    return 0;
}
syscall(60, f());
' "error:<source>:3:19: $NC
error:<source>:4:11: expected ';', got number 2
error:<source>:5:19: $NC
error:<source>:6:11: expected ';', got number 3
error:<source>:7:23: $NC
error:<source>:8:11: expected ';', got number 4"
eq EQ7 "the 6.6.11 reports end in sync too; a top-level statement" 'enum Color { RED, GREEN }
enum F { FC }
var gz = 1;
syscall(60, Color.GREEN);
var q = F.RED;
syscall(60, 1 2);
var r = Nope.gz;
syscall(60, 1 3);
var z = Color.NOPE;
syscall(60, 1 4);
' "error:<source>:5:11: 'RED' is not a variant of 'F'
error:<source>:6:15: expected ')', got number 2
error:<source>:7:9: 'Nope' is not an enum
error:<source>:8:15: expected ')', got number 3
error:<source>:9:15: $NC
error:<source>:10:15: expected ')', got number 4"
eq EQ8 "a generic at two instances: once" 'enum Color { RED, GREEN }
fn g<T>(x: T): i64 { var y = Color.NOPE; y = 1 2; return y; }
fn f(): i64 { return g(1) + g<i32>(2); }
syscall(60, f());
' "error:<source>:2:36: $NC
error:<source>:2:48: expected ';', got number 2"
eq EQ9 "--syntax-only: a const context names the member" 'enum Color { RED, GREEN }
const K = Color.NOPE;
syscall(60, K);
' "error:<source>:2:17: $NC" --syntax-only
eq EQ10 "Color.NOPE2 (a global of no enum) and Color.RED() as statements" 'enum Color { RED, GREEN }
var NOPE2 = 1;
fn f(): i64 {
    Color.RED();
    Color.NOPE2 = 4;
    return Color.NOPE2;
}
syscall(60, f());
' "error:<source>:4:14: expected '=', got '('
error:<source>:5:11: 'NOPE2' is not a variant of 'Color'
error:<source>:6:18: 'NOPE2' is not a variant of 'Color'"
eq EQC1 "control: a base that is no enum keeps its report" 'fn f(): i64 { return Nope.NOPE; }
syscall(60, f());
' "error:<source>:1:22: undefined variable 'Nope'"
# EQC2 control: Color.RED runs, on every target's compiler (x86 run).
printf '%s' 'enum Color { RED, GREEN }
const K = Color.GREEN;
fn f(y): i64 { switch (y) { case Color.GREEN: return 7; default: return 2; } return 0; }
syscall(60, f(K) + Color.GREEN);
' > "$D/eqc2.cyr"
for leg in $ELEGS; do
    eqcomp "$leg" "$D/eqc2.cyr" "$D/eqc2_$leg"; EQN=$((EQN + 1))
    if [ "$CRC" -ne 0 ] || [ ! -s "$D/eqc2_$leg" ]; then bad "EQC2 $leg: Color.GREEN refused: $(head -1 "$D/eqc2_$leg.err")"; fi
done
if [ -s "$D/eqc2_x86" ]; then chmod +x "$D/eqc2_x86"; rc=0; "$D/eqc2_x86" || rc=$?; [ "$rc" = 8 ] || bad "EQC2 x86: exit $rc, want 8"; fi
# EQC3 control: under --syntax-only, an unknown member in run-time code stays opaque (rc 0, nothing said).
printf '%s' 'enum Color { RED, GREEN }
fn f(): i64 { Color.NOPE = 1; Color.NOPE(); return Color.NOPE; }
syscall(60, f());
' > "$D/eqc3.cyr"
for leg in $ELEGS; do
    eqcomp "$leg" "$D/eqc3.cyr" "$D/eqc3_$leg" --syntax-only; EQN=$((EQN + 1))
    if [ "$CRC" -ne 0 ] || grep -qE '^(error|warning)' "$D/eqc3_$leg.err"; then bad "EQC3 $leg: --syntax-only: rc $CRC: $(head -1 "$D/eqc3_$leg.err")"; fi
done
[ "$EQN" -ge 65 ] || bad "EQ: ran $EQN row-legs (floor 65)"

[ "$fail" = 0 ] || exit 1
echo "PASS: #assert and array sizes take enum constants (NAME / Enum.NAME), sizeof is a whole word, nothing trails the operands, no cascade (x86 + aarch64 + cx; 6.6.10); a member of no enum is named, not its enum (EQ, 6.7.16: $EQN row-legs)"
