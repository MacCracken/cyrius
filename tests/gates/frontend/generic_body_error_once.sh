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
# Filed: docs/development/issues/archived/2026-10-10-generic-body-errors-reported-per-instance.md
#
#   R   the filed repro, verbatim: rc 1, exactly one `error:<source>:3:40: expected ';', got number 2` (three before)
#   T1-T9  the issue's table, each exactly one error line (before: 1 1 2 3 2 3 2 2 1): the junk step with no call,
#       `g(1)`, `g(1) + g(x)`, three instances, two distinct instances called twice each, `return zz;`, a for-step,
#       a field step (6.7.5), and the `#inline` control
#   D   two DIFFERENT errors in one body (`i += 1 2;` and `return zz;`), three instances: each printed once
#   E1-E6 the other emitters, two instances each: `return );` (ERR), `var i` twice (ERRDUPVAR), an if expression
#       with no else (ERR_MSG — and its note once), `zz = 1;` (the assignment), `return zz.a;` (the `.field` base:
#       its one error once — 6.7.14's cascade fix dropped the 'no struct type' line), `return &zz;`
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
#   W   (6.7.15) A WARNING TOO: WARN (and WARN_AT through it) and the writers that print their own `warning:` line
#       ask `_warn_seen` (src/common/util.cyr) — the same table, keyed on the token and a negative identity of their
#       own (WARN's message; a writer's name and what its text names) — so a repeated parse of a body warns once.
#       W1 the filed repro verbatim (issues/2026-10-17-generic-body-warning-printed-once-per-instance.md: 3 lines
#       before); W2 two different warnings at one token both print (`x.m()` discarding P.m's and Q.m's #must_use);
#       W3 the same warning at two tokens, each once (6 before); W4 an #inline fn's warning, called three times (4)
#   WD  each writer that prints its own warning line, in a generic body at three types: a duplicate match arm, arms
#       over two enums, a non-exhaustive match (PARSE_MATCH, `_match_dup_warn` / `_match_cov_warn`), a #must_use
#       result (4 before), a nested @unsafe, a Str into a cstring parameter, f64 compared with an integer
#       (`_FLT_TYPE_WARN`), an unrouted syscall under CYRIUS_TARGET_WIN=1 (4; its note once), and through the
#       ELF-aarch64 cross compiler (built from this tree, or CYCC_A64) a raw x86_64 syscall number (4,
#       `_sysx_raw_warn`). The Mach-O routing warnings (`_macho_warn_unrouted`, keyed in `_sc_args_done`) need a
#       Mach-O compiler, which runs on macOS only: not a row here — measured by hand on ecb (arm64) and ach (x86_64),
#       4 -> 1 each (2026-10-18, the 6.7.15 generics lane's handoff). The warnings that cannot repeat are left as
#       they were: once per compile (CYRIUS_STACK_ARRAYS=0, the file-map cap, large static data, the undefined-fn
#       pass), a definition's (duplicate fn, #regalloc skipped, #inline ignored for an async fn — an instance does
#       not re-run them), a declaration's (enum / global redefinitions, a struct redefinition, a kernel global's
#       init), the mixed-pair-return prescan, `_DEPRECATED_WARN` (its own `_dep_seen`), the index check
#       (`_tn_once`), and #pure's (an instance is not #pure)
#   A   (6.7.15) AN ERROR A WRITER PRINTS ITSELF (`syscall(SYS_WRITE, 2, "error:", 6)` and its own text, outside the
#       emitters) asks `_derr_seen` (util.cyr) — keyed on the token it reports and an identity of its own (the
#       writer's name and what its text names), the panic latch set on a repeat when the writer sets it.
#       A1 the filed arity repro verbatim (issues/2026-10-16-direct-error-writers-print-once-per-generic-instance.md:
#       3 lines before; the tail arm, a call and an inline replay check one call at three cursors, so `_CHECK_ARITY`
#       keys on the call's `(`, `_ar_site`), A1b an arity error in a declaration's call (3), A2 the filed
#       second-subscript repro verbatim (2); A3 a plain fn's two different bad calls both print; A4 two different
#       arity texts at one token (`x.m(1, 2, 3)` at P and Q) both print
#   DW  each converted writer, in a generic body at three types (3 lines before, DW11 4): `_ends_guard` (a switch
#       over 256 case bodies), `_asg_cap_name`, `_masg_err`, `_agg_kind_err` (a struct, a vector), `_vec_val_err`,
#       `_sval_kind_err`, `_ret_sid_refuse`, `_refuse_pair_return`, `_refuse_struct_tuple_return`,
#       `_refuse_simd_return`, `_check_int_lit_cstring_arg` (and its hint once), `_sar_err`, `_icall_fld_err`,
#       `_mret_fld_err`, `_sub_err`, `_vrcv_err`, `_dt_struct_err`, `_vis_check_var` (two private globals, each
#       once). Left as they were, the writers that cannot repeat: those already once per token or site (`_tn_once`,
#       `_ie_once`, `_vis_seen`, `_nested_fn_seen`, `_assert_rep_ti`, `_err_once`), a reserved intrinsic name
#       (`_inst_name` — the base parse only), the definition's and top-level ones (an async fn's — an async generic
#       is refused, a duplicate fn, `_dl_report`, `_fn_redirect`, `_dsg_report`, `private` per item, a bare-metal
#       include, a global's redeclaration, an array initializer — module scope only, a top-level struct / vector /
#       operator call), the internal `_pd_line_err`, and the fatal exits
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
#   MW1 (2026-10-18) `_warn_seen` answers 0        -> RED W1, W3, W4, WD1-WD9 (the counts of before)
#   MW2 (2026-10-18) WARN without its head         -> RED W1, W3 (the WARN rows); the direct writers green
#   MW3 (2026-10-18) `_must_use_warn`'s identity without what it names -> RED W2 (Q.m's line swallowed)
#   The lane's previous compiler (CYCC) -> RED W1, W3, W4, WD1-WD8; its aarch64 compiler (CYCC_A64) -> RED WD9
#   MD1 (2026-10-18) `_derr_seen` never a repeat   -> RED A1, A1b, A2, DW1-DW19 (DW12's hint too): the counts of before
#   MD2 (2026-10-18) `_CHECK_ARITY` keyed on the cursor, not `_ar_site` -> RED A1 (2 lines: the tail arm's cursor)
#   MD3 (2026-10-18) `_CHECK_ARITY`'s identity without what it names -> RED A4 (Q.m's line swallowed)
#   The warning bite's compiler (CYCC) -> RED A1, A1b, A2, DW1-DW19
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
# E5 is one line since the 6.7.14 frontend lane's cascade fix: the `.field` base's "undefined variable" IS the error, and
# the "no struct type in scope" line that followed it is gone (issues/archived/2026-10-08-diagnostic-cascades-and-locationless-eof-errors.md).
erows E5 "$D/E5.cyr" 1 "return zz.a; (the .field base, 6 before)" "undefined variable 'zz'"
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

# wrows <id> <src> <want> <what> <fragment>...: exactly <want> positional `warning:<` lines, each <fragment> on
# exactly one of them. The compile's rc is not read (a warning does not refuse). WCC: the compiler (default $CC);
# WWIN=1 compiles with CYRIUS_TARGET_WIN=1.
wrows() {
    id=$1; src=$2; want=$3; what=$4; shift 4
    wc=${WCC:-$CC}
    if [ "${WWIN:-0}" = 1 ]; then CYRIUS_TARGET_WIN=1 "$wc" < "$src" > "$D/$id.bin" 2> "$D/$id.err" || true
    else "$wc" < "$src" > "$D/$id.bin" 2> "$D/$id.err" || true; fi
    nw=$(grep -c '^warning:<' "$D/$id.err" || true)
    if [ "$nw" -ne "$want" ]; then bad "$id: $what: $nw warning line(s), want $want: $(grep '^warning:<' "$D/$id.err" | cut -c1-110 | tr '\n' ' ')"; return; fi
    for frag in "$@"; do
        nf=$(grep '^warning:<' "$D/$id.err" | grep -cF "$frag" || true)
        if [ "$nf" -ne 1 ]; then bad "$id: $what: '$frag' on $nf warning line(s), want 1"; return; fi
    done
    ok "$id: $what: $want warning line(s)"
}
# wbody <id> <defs> <g's body>: g<T> called at i64, P and Q
wbody() {
    printf 'include "lib/syscalls.cyr"\nstruct P { a; b; }\nstruct Q { c; d; e; }\n%s\nfn g<T>(x: T): i64 { %s }\nfn run(): i64 { var u = P { 1, 2 }; var w = Q { 1, 2, 3 }; return g(1) + g(u) + g(w); }\nsyscall(60, run());\n' "$2" "$3" > "$D/$1.cyr"
}

echo "W. a warning in a generic body is printed once (6.7.15)"
cat > "$D/w1.cyr" <<'XEOF'
include "lib/syscalls.cyr"
struct P { a; b; }
struct Q { c; d; e; }
fn g<T>(x: T): i64 { var q = 5; var p: *i64 = q; return 1; }
fn run(): i64 { var u = P { 1, 2 }; var w = Q { 1, 2, 3 }; return g(1) + g(u) + g(w); }
syscall(60, run());
XEOF
wrows W1 "$D/w1.cyr" 1 "the filed repro, verbatim (3 before)" "warning:<source>:4:48: assigning non-pointer to typed pointer"
cat > "$D/w2.cyr" <<'XEOF'
struct P { a; b; }
struct Q { c; d; e; }
impl P {
    #must_use
    fn m(self): i64 { return 1; }
}
impl Q {
    #must_use
    fn m(self): i64 { return 2; }
}
fn g<T>(x: T): i64 { x.m(); return 0; }
fn run(): i64 { var u = P { 1, 2 }; var w = Q { 1, 2, 3 }; return g(u) + g(w) + g(u); }
syscall(60, run());
XEOF
wrows W2 "$D/w2.cyr" 2 "two different warnings at one token (x.m() at P and Q) both print" "11:27: #must_use result of 'P.m' is discarded" "11:27: #must_use result of 'Q.m' is discarded"
wbody W3 '' 'var q = 5; var p: *i64 = q; var p2: *i64 = q; return 1;'
wrows W3 "$D/W3.cyr" 2 "the same warning at two tokens, three instances: each once (6 before)" "5:48: assigning non-pointer" "5:66: assigning non-pointer"
cat > "$D/w4.cyr" <<'XEOF'
#inline
fn h(n): i64 { return n + 1.5; }
fn run(): i64 { return h(1) + h(2) + h(3); }
syscall(60, run());
XEOF
wrows W4 "$D/w4.cyr" 1 "an #inline fn's warning, called three times: once (4 before)" "2:30: integer arithmetic with an f64 right operand"
echo "WD. the writers that print their own warning line, three instances each"
wbody WD1 'enum E { EA; EB; }' 'var e = EA; var r = 0; match e { EA => { r = 1; } EA => { r = 2; } EB => { r = 3; } } return r;'
wrows WD1 "$D/WD1.cyr" 1 "a duplicate match arm (3 before)" "duplicate match arm 'EA'"
wbody WD2 'enum E { EA; EB; }
enum F { FA; FB; }' 'var e = EA; var r = 0; match e { EA => { r = 1; } FA => { r = 2; } } return r;'
wrows WD2 "$D/WD2.cyr" 1 "match arms over two enums (3 before)" "match arms span multiple enums"
wbody WD3 'enum E { EA; EB; EC; }' 'var e = EA; var r = 0; match e { EA => { r = 1; } } return r;'
wrows WD3 "$D/WD3.cyr" 1 "a non-exhaustive match (3 before)" "non-exhaustive match over enum 'E' — covers 1 of 3 variants"
wbody WD4 '#must_use
fn mu(): i64 { return 1; }' 'mu(); return 0;'
wrows WD4 "$D/WD4.cyr" 1 "a #must_use result discarded (4 before)" "#must_use result of 'mu' is discarded"
wbody WD5 '' '@unsafe { @unsafe { var z = 1; } } return 0;'
wrows WD5 "$D/WD5.cyr" 1 "a nested @unsafe (3 before)" "nested @unsafe block"
wbody WD6 'include "lib/str.cyr"
fn cs(n, s: cstring): i64 { return 0; }' 'var sk = str_from("ab"); return cs(0, sk);'
wrows WD6 "$D/WD6.cyr" 1 "a Str passed to a cstring parameter (3 before)" "passing Str-typed 'sk' to 'cs'"
wbody WD7 '' 'var f: f64 = 1.5; var i = 3; if (f < i) { return 1; } return 0;'
wrows WD7 "$D/WD7.cyr" 1 "f64 compared with an integer (3 before)" "comparison mixes f64 and integer operands"
wbody WD8 '' 'return syscall(91, 0, 0);'
WWIN=1 wrows WD8 "$D/WD8.cyr" 1 "an unrouted syscall on CYRIUS_TARGET_WIN=1 (4 before)" "syscall 91 with 2 argument(s) is not routed on CYRIUS_TARGET_WIN=1"
nn=$(grep -c 'note: CYRIUS_TARGET_WIN=1 routes' "$D/WD8.err" || true)
if [ "$nn" -eq 1 ]; then ok "WD8: its note once"; else bad "WD8: its note $nn times, want 1"; fi
# the ELF-aarch64 compiler: CYCC_A64 when given (a mutant's), else built from this tree's src/main_aarch64.cyr
if [ -n "${CYCC_A64:-}" ]; then cp "$CYCC_A64" "$D/cc_a64"; else "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null || true; fi
if [ -s "$D/cc_a64" ]; then
    chmod +x "$D/cc_a64"
    WCC="$D/cc_a64" wrows WD9 "$D/WD8.cyr" 1 "a raw x86_64 syscall number on ELF-aarch64 (4 before)" "raw syscall 91 is x86_64 \`fchmod\`; on ELF-aarch64 that number is \`capset\`"
else bad "WD9: src/main_aarch64.cyr did not build"; fi

echo "A. an error a writer prints itself (outside the emitters): once (6.7.15)"
cat > "$D/a1.cyr" <<'XEOF'
struct I { a; b; }
fn h(a): i64 { return a; }
fn g<T>(v: T): i64 { return h(1, 2); }
fn main(): i64 { var x = I { 1, 2 }; return g(1) + g(x); }
syscall(60, main());
XEOF
erows A1 "$D/a1.cyr" 1 "the filed arity repro, verbatim (3 before)" "error:<source>:3: 'h' expects 1 argument, got 2"
cat > "$D/a2.cyr" <<'XEOF'
struct I { a; b; }
fn g<T>(v: T): i64 { var a: i64[2]; return a[0][1]; }
fn main(): i64 { var x = I { 1, 2 }; return g(1) + g(x); }
syscall(60, main());
XEOF
wbody A1b 'fn h(a): i64 { return a; }' 'var r = h(1, 2); return r;'
erows A1b "$D/A1b.cyr" 1 "an arity error in a declaration's call, three instances (3 before)" "'h' expects 1 argument, got 2"
erows A2 "$D/a2.cyr" 1 "the filed second-subscript repro, verbatim (2 before)" "error:<source>:2:48: a subscript's result is an element, not an array - a second [..] is not supported"
cat > "$D/a3.cyr" <<'XEOF'
fn h(a): i64 { return a; }
fn k(a, b): i64 { return a + b; }
fn f(): i64 {
    var r = h(1, 2);
    return r + k(1, 2, 3);
}
syscall(60, f());
XEOF
erows A3 "$D/a3.cyr" 2 "control: two different bad calls in a plain fn both print" "4: 'h' expects 1 argument, got 2" "5: 'k' expects 2 arguments, got 3"
cat > "$D/a4.cyr" <<'XEOF'
struct P { a; b; }
struct Q { c; d; e; }
impl P { fn m(self, k): i64 { return k; } }
impl Q { fn m(self, k, j): i64 { return k + j; } }
fn g<T>(x: T): i64 { return x.m(1, 2, 3); }
fn run(): i64 { var u = P { 1, 2 }; var w = Q { 1, 2, 3 }; return g(u) + g(w) + g(u); }
syscall(60, run());
XEOF
erows A4 "$D/a4.cyr" 2 "two different arity errors at one token (x.m at P and Q) both print" "'P.m' expects 1 argument, got 3" "'Q.m' expects 2 arguments, got 3"
echo "DW. each writer that prints its own error line, in a generic body at three types: once"
wbody DW1 '' "var k = 0; switch (k) { $(i=0; while [ $i -lt 257 ]; do printf 'case %d: { k = 1; } ' $i; i=$((i+1)); done) } return k;"
erows DW1 "$D/DW1.cyr" 1 "a switch over 256 case bodies (3 before)" "too many case/arm bodies in one switch/match (max 256)"
wbody DW2 '' 'var n = 1; var f = |y| { n = 2; return y; }; return 0;'
erows DW2 "$D/DW2.cyr" 1 "a captured name assigned in a closure (3 before)" "'n' is captured by value; a captured name is not assignable in a closure"
wbody DW3 'fn two(): (i64, i64) { return (1, 2); }' 'var a = 0; var b = 0; a, a = two(); return a + b;'
erows DW3 "$D/DW3.cyr" 1 "a multi-value assignment naming one variable twice (3 before)" "a multi-value assignment re-assigns each variable once - this one is named twice"
wbody DW4 'struct Pt { x; y; }
fn ri(p: *i64): i64 { return 0; }' 'var s: Pt; s.x = 1; return ri(s);'
erows DW4 "$D/DW4.cyr" 1 "a struct local into a word pointer (3 before)" "cannot pass 's' to a parameter that is not a pointer to its struct type in a call to 'ri' - pass &s for its address"
wbody DW5 'fn rv(p: *i64): i64 { return 0; }' 'var v: f64v2; return rv(v);'
erows DW5 "$D/DW5.cyr" 1 "a vector local into a word pointer (3 before)" "cannot pass 'v' to a parameter that is not a pointer to its vector type in a call to 'rv' - pass &v for its address"
wbody DW6 'struct Pt { x; y; }
fn bv(p: Pt): i64 { return 0; }' 'var b: f64v2; return bv(b);'
erows DW6 "$D/DW6.cyr" 1 "a vector into a by-value struct (3 before)" "cannot pass 'b' to a by-value struct parameter in a call to 'bv' - a vector is not a struct"
wbody DW7 'struct Pt { x; y; }
struct W { s: Pt; }
fn ri(p: *i64): i64 { return 0; }' 'var w2: W; return ri(w2.s);'
erows DW7 "$D/DW7.cyr" 1 "a struct field's value into a word pointer (3 before)" "a struct value is no address"
# gbody <id> <defs> <main's body>: the definitions (a generic gr<T> among them) and a run() calling it
gbody() {
    printf 'include "lib/syscalls.cyr"\nstruct P { a; b; }\nstruct Q { c; d; e; }\n%s\nfn run(): i64 { var u = P { 1, 2 }; var w = Q { 1, 2, 3 }; %s }\nsyscall(60, run());\n' "$2" "$3" > "$D/$1.cyr"
}
gbody DW8 'struct Pt { x; y; z; }
struct Pu { x; y; z; }
fn gr<T>(x: T): Pt { var q: Pu; var pq: *Pu = &q; return *pq; }' 'return gr(1).x + gr(u).x + gr(w).x;'
erows DW8 "$D/DW8.cyr" 1 "a struct return of another struct's pointer (3 before)" "a fn returning the struct \`Pt\` takes a value of that struct, or a pointer to one — got \`*pq\` (a \`Pu\`)"
gbody DW9 'struct S9 { a; b; }
fn gr<T>(x: T): S9 { return 5; }' 'return gr(1).a + gr(u).a + gr(w).a;'
erows DW9 "$D/DW9.cyr" 1 "a 9-16 byte struct return of a number (3 before)" "a fn returning the 9-16 byte struct \`S9\` is returned in two registers"
gbody DW10 'struct Big { a; b; c; }
fn gr<T>(x: T): Big { return (1, 2); }' 'return gr(1).a + gr(u).a + gr(w).a;'
erows DW10 "$D/DW10.cyr" 1 "a struct return of a tuple (3 before)" "a fn returning the struct \`Big\` returns that struct — \`(a, b)\` is a tuple, another type"
gbody DW11 'fn gr<T>(x: T): f64v2 { return 5; }' 'var a = gr(1); var b = gr(u); var c = gr(w); return 0;'
erows DW11 "$D/DW11.cyr" 1 "a vector return of a number (4 before)" "a vector-returning fn carries its result in a fixed register pair"
wbody DW12 'fn cs(s: cstring): i64 { return 0; }' 'var r = cs(5); return r;'
erows DW12 "$D/DW12.cyr" 1 "an integer literal into a cstring parameter (3 before)" "passing integer literal 5 to 'cs' which expects a cstring"
nh=$(grep -c 'hint: the value is a NUMBER' "$D/DW12.err" || true)
if [ "$nh" -eq 1 ]; then ok "DW12: its hint once"; else bad "DW12: its hint $nh times, want 1"; fi
wbody DW13 'fn vv(v: f64v2): i64 { return 0; }' 'var r = vv(5); return r;'
erows DW13 "$D/DW13.cyr" 1 "a number into a value-form vector parameter (3 before)" "a value-form vector argument to 'vv' is a local of its type"
wbody DW14 'struct R { v; }' 'var fp = 0; return fncall0(fp).v;'
erows DW14 "$D/DW14.cyr" 1 "a field of fncall0 through a value (3 before)" "cannot take a field of the result of 'fncall0': its callee is a value"
wbody DW15 'fn two(): (i64, i64) { return (1, 2); }' 'var r = two().a; return r;'
erows DW15 "$D/DW15.cyr" 1 "a field of a multi-value call (3 before)" "cannot take a field of the result of 'two': it returns 2 values"
wbody DW16 '' 'var n = 5; return n[1];'
erows DW16 "$D/DW16.cyr" 1 "a subscript of a plain local (3 before)" "cannot subscript 'n': it is not a typed array"
wbody DW17 '' 'var v: f64v2 = 5; return 0;'
erows DW17 "$D/DW17.cyr" 1 "a number into a value-form vector local (3 before)" "a value-form vector local is initialised only from a local of its type"
wbody DW18 'struct Big { a; b; c; }
fn mkb(): Big { var r: Big; r.a = 1; return r; }' 'var a, b = mkb(); return a;'
erows DW18 "$D/DW18.cyr" 1 "a destructure of a struct return (3 before)" "cannot destructure 'mkb' - it returns struct 'Big', which is not in registers"
mkdir -p "$D/vis"
printf 'private\nvar pg = 5;\nvar pg2 = 6;\n' > "$D/vis/privmod.cyr"
printf 'include "privmod.cyr"\nstruct P { a; b; }\nstruct Q { c; d; e; }\nfn g<T>(x: T): i64 {\n    var a = pg;\n    var b = pg2;\n    return a + b;\n}\nfn run(): i64 { var u = P { 1, 2 }; var w = Q { 1, 2, 3 }; return g(1) + g(u) + g(w); }\nsyscall(60, run());\n' > "$D/vis/main.cyr"
vrc=0; ( cd "$D/vis" && "$CC" < main.cyr > main.bin 2> main.err ) || vrc=$?
nv1=$(grep -c "^error.*'pg' is private to its file" "$D/vis/main.err" || true)
nv2=$(grep -c "^error.*'pg2' is private to its file" "$D/vis/main.err" || true)
if [ "$vrc" -eq 0 ]; then bad "DW19: a private global read in a generic body compiled (want it refused)"
elif [ "$nv1" -eq 1 ] && [ "$nv2" -eq 1 ]; then ok "DW19: two private globals read in a generic body at three types: each once (3 each before)"
else bad "DW19: 'pg' $nv1 and 'pg2' $nv2 lines, want 1 and 1"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
echo "PASS: $G — an error in a generic body is printed once: the filed repro (R), the issue's table (T1-T9), two different errors (D), the other emitters and their notes (E, N), instance-dependent messages (V), a generic struct's field notes (S) and a bound refusal's note (B) once with their error, and the per-token control (C); a warning once (W, WD); an error a writer prints itself once (A, DW)"
