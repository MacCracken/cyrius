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
#
# 6.6.11 (N4): the qualified form never checked its BASE. `Foo.EB` (no enum Foo) and
# `F.EB` (EB belongs to E) compiled in expressions, #assert and array sizes, `Nope.gz`
# loaded the plain global gz, and with a variant name shared by two enums `A.X` read the
# LAST X. One resolver (_enum_qual_resolve, parse.cyr) serves all three sites now: the
# base must be an enum and the variant must be ITS variant, looked up in that enum.
# Mutation: make _enum_qual_resolve `return FINDVAR(S, vn);` -> every N4 refusal compiles
# (rc 0) and the shared-name row exits 22 (want 12).
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
no "sizeof is a whole word"     'expected a number, sizeof(T) or an enum constant' '#assert sizeofzz(P) == 16;
syscall(60, 7);'
no "bad atom reports once (no #assert-failed cascade)" 'expected a number, sizeof(T) or an enum constant' '#assert foo == 1;
syscall(60, 7);'
no "a VARIABLE base is a field access, not an enum" 'expected a number, sizeof(T) or an enum constant' 'var p = 0;
#assert p.x == 0;
syscall(60, 7);'
AR='no arithmetic inside #assert'
# The comma-less message form is still accepted (tests/gates/diagnostics/
# resolution_excerpt_and_assert_skip.sh axis 3 relies on it) and still printed on failure.
ok "comma-less message after the operands" 7 '#assert E.EB == 4 "fine";
syscall(60, 7);'
no "comma-less message on a failing assert" '#assert failed: nocomma' '#assert E.EB == 5 "nocomma";
syscall(60, 7);'
no "arithmetic after an enum atom (false assert, in a fn)" "$AR" 'fn f(): i64 { #assert E.EB * 2 == 9; return 5; }
syscall(60, f());'
no "arithmetic after an enum atom (true if evaluated)" "$AR" '#assert E.EB * 2 == 8;
syscall(60, 7);'
no "arithmetic between literals" "$AR" '#assert 4 * 2 == 9;
syscall(60, 7);'
no "junk after the comparison" "$AR" '#assert 4 == 4 junk junk;
syscall(60, 7);'
no "junk after a lone atom" "$AR" '#assert 5 junk;
syscall(60, 7);'
no "a bad atom followed by arithmetic still reports once" 'expected a number, sizeof(T) or an enum constant' '#assert foo * 2 == 1;
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

[ "$fail" = 0 ] || exit 1
echo "PASS: #assert and array sizes take enum constants (NAME / Enum.NAME), sizeof is a whole word, nothing trails the operands, no cascade (x86 + aarch64 + cx; 6.6.10)"
