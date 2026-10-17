#!/bin/sh
# tests/gates/frontend/generic_body_error_once.sh — 6.7.14
#
# AN ERROR INSIDE A GENERIC BODY IS PRINTED ONCE, NOT ONCE PER INSTANCE. A generic fn's body is parsed for its
# base and again for every instance (and an inline replay re-parses a body), and the plain error emitters had no
# latch: `i += 1 2;` in `fn g<T>` called at three types printed "expected ';', got number 2" three times,
# `return zz;` three times for two calls. The emitters (src/common/util.cyr ERR, ERR_EXPECT, ERR_IDENT, ERR_MSG,
# ERRDUPVAR and the shared undefined-name report ERR_UNDEF, which the read, the assignment, `&x` and a `.field`
# base now call) record each report as (its token, its identity) in a table of their own (`_err_dup`), apart
# from `_tn_once`'s byte map, and print a repeat as nothing — `_had_error` and the panic latch set as before, and
# `_err_quiet` keeping the caller's note quiet with it (`_gv_note_blockscoped`, `_ie_no_else`). A different
# message at the same token still prints, and so does the same message at another token.
# Filed: docs/development/issues/2026-10-10-generic-body-errors-reported-per-instance.md
#
#   R   the filed repro, verbatim: rc 1, exactly one `error:<source>:3:40: expected ';', got number 2` (three before)
#   T1-T9  the issue's table, each exactly one error line (before: 1 1 2 3 2 3 2 2 1): the junk step with no call,
#       `g(1)`, `g(1) + g(x)`, three instances, two distinct instances called twice each, `return zz;`, a for-step,
#       a field step (6.7.5), and the `#inline` control
#   D   two DIFFERENT errors in one body (`i += 1 2;` and `return zz;`), three instances: each printed once
#   E1-E6 the other emitters, two instances each: `return );` (ERR), `var i` twice (ERRDUPVAR), an if expression
#       with no else (ERR_MSG — and its note once), `zz = 1;` (the assignment), `return zz.a;` (the `.field` base:
#       its two errors once each), `return &zz;`
#   N   the block-scope note: `tbv` declared in a top-level block, read in a generic body called at two types —
#       one error and one note (three of each before)
#   V   instance-dependent messages at one token: `return v.zz;` called at I, J, I — "unknown field 'zz' on struct
#       'I'" and "... 'J'", one each
#   C   the latch is per token: `i += 1 2; i += 1 3;` in a plain fn reports both
#   S1-S4 a generic STRUCT is parsed again per instance: an unknown field type (`b: nosuch`), an unknown Vec element
#       (`v: Vec<nosuch>`, the field's own refusal) and `b: i32x` (the prefix note too) in `W<T>` instantiated three
#       times give one error and each note once (the review of 3bf60734: 1 error + 4 / 4 / 8 orphan notes); S4 a
#       plain struct's note, the control
#   B   a bound refusal at one token in two instances of the enclosing generic (`gb<T>(x)` in `o<i32>`, `o<i16>`):
#       one error, one note (the second instance's note printed orphaned)
#
# MUTATION LEDGER (2026-10-16; a scratch copy of the tree with the one change, its 2-stage cycc, this gate run with
# CYCC= it):
#   ME1 `_err_dup` answers 0 (no latch)             -> RED R, T3-T8, D, E1-E6 (and E3's note), N (and its note) —
#                                                     the counts of before; V green (an instance parses once)
#   ME2 `_gv_note_blockscoped` without its `_err_quiet` test -> RED N (the note three times, the error once)
#   ME3 `_ie_no_else` without its `_err_quiet` test -> RED E3 (the note twice, the error once)
#   ME4 the identity without the message (`_err_once(S, 0)` in ERR_IDENT) -> RED V (J's line swallowed)
#   ME5 (2026-10-17) `_refuse_field_type`'s notes without their `_err_quiet` test -> RED S1 S2 (the note 4 times), S3
#       (each note 4 times); S4 green. `_vec_elem_refuse`'s notes carry the same test, but no row reaches them as a
#       repeat: `_tn_once` and the panic test return before its error (the test is the guard, not a reachable path)
#   ME6 (2026-10-17) `_bnd_check`'s note without its `_err_quiet` test -> RED B (the note twice)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_body_error_once
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null

fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# erows <id> <src> <want-errors> <what> [<fragment>...]: rc 1, exactly <want-errors> `error:` lines, each
# <fragment> on exactly one of them.
erows() {
    id=$1; src=$2; want=$3; what=$4; shift 4
    erc=0; "$CC" < "$src" > "$D/$id.bin" 2> "$D/$id.err" || erc=$?
    ne=$(grep -c '^error' "$D/$id.err" || true)
    if [ "$erc" -eq 0 ]; then bad "$id: $what compiled (want it refused)"; return; fi
    if [ "$ne" -ne "$want" ]; then bad "$id: $what: $ne error line(s), want $want: $(grep '^error' "$D/$id.err" | tr '\n' ' ')"; return; fi
    for frag in "$@"; do
        nf=$(grep '^error' "$D/$id.err" | grep -cF "$frag" || true)
        if [ "$nf" -ne 1 ]; then bad "$id: $what: '$frag' on $nf error line(s), want 1"; return; fi
    done
    ok "$id: $what: $want error line(s)"
}

echo "R. the filed repro, verbatim"
cat > "$D/r.cyr" <<'XEOF'
struct I { a; b; }
struct J { c; }
fn g<T>(v: T): i64 { var i = 0; i += 1 2; return i; }
fn main(): i64 { var x = I { 1, 2 }; var y = J { 3 }; return g(1) + g(x) + g(y); }
syscall(60, main());
XEOF
erows R "$D/r.cyr" 1 "g(1) + g(x) + g(y) over a junk step" "error:<source>:3:40: expected ';', got number 2"

# body <id> <defs> <main body>: a program with structs I, J, C, the definitions and main
body() {
    printf 'struct I { a; b; }\nstruct J { c; }\nstruct C { n; }\n%s\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$2" "$3" > "$D/$1.cyr"
}
JUNK='fn g<T>(v: T): i64 { var i = 0; i += 1 2; return i; }'
echo "T. the issue's table: each exactly one error line"
body T1 "$JUNK" 'return 0;'
erows T1 "$D/T1.cyr" 1 "no call (the base parse only)" "expected ';', got number 2"
body T2 "$JUNK" 'return g(1);'
erows T2 "$D/T2.cyr" 1 "g(1)" "expected ';', got number 2"
body T3 "$JUNK" 'var x = I { 1, 2 }; return g(1) + g(x);'
erows T3 "$D/T3.cyr" 1 "g(1) + g(x) (2 before)" "expected ';', got number 2"
body T4 "$JUNK" 'var x = I { 1, 2 }; var y = J { 3 }; return g(1) + g(x) + g(y);'
erows T4 "$D/T4.cyr" 1 "three instances (3 before)" "expected ';', got number 2"
body T5 "$JUNK" 'var x = I { 1, 2 }; return g(1) + g(x) + g(2) + g(x);'
erows T5 "$D/T5.cyr" 1 "two distinct instances, twice each (2 before)" "expected ';', got number 2"
body T6 'fn g<T>(v: T): i64 { return zz; }' 'var x = I { 1, 2 }; return g(1) + g(x);'
erows T6 "$D/T6.cyr" 1 "return zz; (3 before)" "undefined variable 'zz' (missing include or enum?)"
body T7 'fn g<T>(v: T): i64 { var i = 0; for (i = 0; i < 3; i += 1 2) { } return i; }' 'var x = I { 1, 2 }; return g(1) + g(x);'
erows T7 "$D/T7.cyr" 1 "a junk for-step (2 before)" "expected ')', got number 2"
body T8 'fn g<T>(v: T): i64 { var c = C { 1 }; for (c.n = 0; c.n < 3; c.n += 1 2) { } return c.n; }' 'var x = I { 1, 2 }; return g(1) + g(x);'
erows T8 "$D/T8.cyr" 1 "a junk field step (2 before)" "expected ')', got number 2"
body T9 '#inline
fn h(n): i64 { var i = 0; i += 1 2; return i; }' 'return h(1) + h(2);'
erows T9 "$D/T9.cyr" 1 "#inline h, called twice (the control)" "expected ';', got number 2"

echo "D. two different errors in one body, three instances: each once"
body D 'fn g<T>(v: T): i64 { var i = 0; i += 1 2; return zz; }' 'var x = I { 1, 2 }; var y = J { 3 }; return g(1) + g(x) + g(y);'
erows D "$D/D.cyr" 2 "i += 1 2; and return zz; (6 before)" "expected ';', got number 2" "undefined variable 'zz'"

echo "E. the other emitters, two instances each"
body E1 'fn g<T>(v: T): i64 { return ); }' 'var x = I { 1, 2 }; return g(1) + g(x);'
erows E1 "$D/E1.cyr" 1 "return ); (ERR, 3 before)" "unexpected ')'"
body E2 'fn g<T>(v: T): i64 { var i = 0; var i = 1; return i; }' 'var x = I { 1, 2 }; return g(1) + g(x);'
erows E2 "$D/E2.cyr" 1 "a duplicate var (ERRDUPVAR, 2 before)" "duplicate variable"
body E3 'fn g<T>(v: T): i64 { var k = if (1) { 1 }; return k; }' 'var x = I { 1, 2 }; return g(1) + g(x);'
erows E3 "$D/E3.cyr" 1 "an if expression with no else (ERR_MSG, 2 before)" "an if expression needs an else"
nn=$(grep -c 'note: at the start of a statement' "$D/E3.err" || true)
if [ "$nn" -eq 1 ]; then ok "E3: its note once"; else bad "E3: its note $nn times, want 1"; fi
body E4 'fn g<T>(v: T): i64 { zz = 1; return 0; }' 'var x = I { 1, 2 }; return g(1) + g(x);'
erows E4 "$D/E4.cyr" 1 "zz = 1; (the assignment, 3 before)" "undefined variable 'zz'"
body E5 'fn g<T>(v: T): i64 { return zz.a; }' 'var x = I { 1, 2 }; return g(1) + g(x);'
erows E5 "$D/E5.cyr" 2 "return zz.a; (the .field base, 6 before)" "undefined variable 'zz'" "no struct type in scope for 'zz'"
body E6 'fn g<T>(v: T): i64 { return &zz; }' 'var x = I { 1, 2 }; return g(1) + g(x);'
erows E6 "$D/E6.cyr" 1 "return &zz; (3 before)" "undefined variable 'zz'"

echo "N. the block-scope note follows its error: once"
cat > "$D/n.cyr" <<'XEOF'
struct I { a; b; }
if (1 == 1) { var tbv = 5; }
fn g<T>(v: T): i64 { return tbv; }
fn main(): i64 { var x = I { 1, 2 }; return g(1) + g(x); }
syscall(60, main());
XEOF
erows N "$D/n.cyr" 1 "tbv out of scope in a generic body" "undefined variable 'tbv'"
nn=$(grep -c "^note: 'tbv' was declared inside a top-level block" "$D/N.err" || true)
if [ "$nn" -eq 1 ]; then ok "N: its note once"; else bad "N: its note $nn times, want 1"; fi

echo "V. different messages at one token both print"
body V 'fn g<T>(v: T): i64 { return v.zz; }' 'var x = I { 1, 2 }; var y = J { 3 }; return g(x) + g(y) + g(x);'
erows V "$D/V.cyr" 2 "v.zz at I, J, I" "unknown field 'zz' on struct 'I'" "unknown field 'zz' on struct 'J'"

# nrow <id> <want> <fragment> <what>: exactly <want> lines of $D/<id>.err hold <fragment>
nrow() {
    nn=$(grep -cF "$3" "$D/$1.err" || true)
    if [ "$nn" -eq "$2" ]; then ok "$1: $4 ($nn)"; else bad "$1: $4: $nn line(s), want $2"; fi
}
echo "S. a generic STRUCT's field notes follow their error: once (the struct is parsed again per instance)"
SFN='note: a field type is a struct or union declared above it'
SPN="note: 'i32x' is not 'i32'"
printf 'struct Pt { x; y; }\nstruct W<T> { a: T; b: nosuch; }\nfn main(): i64 { var a: W<i32>; var b: W<Pt>; var c: W<i16>; return 0; }\nsyscall(60, main());\n' > "$D/S1.cyr"
erows S1 "$D/S1.cyr" 1 "an unknown field type in W<T>, three instances" "unknown type 'nosuch' for struct field 'b'"
nrow S1 1 "$SFN" "its note once (an orphan per repeat before the fix: 1 error, 4 notes)"
printf 'include "lib/vec.cyr"\nstruct Pt { x; y; }\nstruct W<T> { a: T; v: Vec<nosuch>; }\nfn main(): i64 { var a: W<i32>; var b: W<Pt>; var c: W<i16>; return 0; }\nsyscall(60, main());\n' > "$D/S2.cyr"
erows S2 "$D/S2.cyr" 1 "an unknown Vec element in W<T>, three instances" "unknown type 'nosuch' for struct field 'v'"
nrow S2 1 "$SFN" "its note once"
printf 'struct Pt { x; y; }\nstruct W<T> { a: T; b: i32x; }\nfn main(): i64 { var a: W<i32>; var b: W<Pt>; var c: W<i16>; return 0; }\nsyscall(60, main());\n' > "$D/S3.cyr"
erows S3 "$D/S3.cyr" 1 "i32x in W<T>, three instances" "unknown type 'i32x' for struct field 'b'"
nrow S3 1 "$SPN" "its prefix note once"
nrow S3 1 "$SFN" "its field-type note once"
printf 'struct W { a; b: nosuch; }\nfn main(): i64 { var a: W; return 0; }\nsyscall(60, main());\n' > "$D/S4.cyr"
erows S4 "$D/S4.cyr" 1 "control: an unknown field type in a plain struct" "unknown type 'nosuch' for struct field 'b'"
nrow S4 1 "$SFN" "control: its note"

echo "B. a bound refusal's note follows its error: once (the same refusal in another instance is a repeat)"
cat > "$D/B.cyr" <<'XEOF'
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
fn gb<T: Show>(x: T): i64 { return 1; }
fn o<T>(x: T): i64 { return gb<T>(x); }
fn f(): i64 { var a: i32 = 3; var b: i16 = 4; return o<i32>(a) + o<i16>(b); }
syscall(60, f());
XEOF
erows B "$D/B.cyr" 1 "gb<T>(x) in o<i32> and o<i16>" "generic 'gb': its type argument does not implement trait 'Show'"
nrow B 1 "note: the bound on type parameter 'T' needs" "its note once (the i16 instance's printed orphaned before the fix)"

echo "C. the latch is per token"
cat > "$D/c.cyr" <<'XEOF'
fn f(): i64 { var i = 0; i += 1 2; i += 1 3; return i; }
syscall(60, f());
XEOF
erows C "$D/c.cyr" 2 "two junk steps in a plain fn" "got number 2" "got number 3"

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
echo "PASS: $G — an error in a generic body is printed once: the filed repro (R), the issue's table (T1-T9), two different errors (D), the other emitters and their notes (E, N), instance-dependent messages (V), a generic struct's field notes (S) and a bound refusal's note (B) once with their error, and the per-token control (C)"
