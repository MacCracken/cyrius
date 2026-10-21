#!/bin/sh
# Gate: a struct RESULT is type-checked against its struct destination (6.6.11).
#
# THE DEFECTS (measured at 6.6.10, x86_64 Linux — every refusal row below compiled rc 0):
#
#   L4  A struct result of 8 B or less from a METHOD or an OVERLOADED OPERATOR was never compared
#       with its destination: `h.o = y.same()`, `h.o = y + y`, `var z: Odd = y.same()`,
#       `var z: Odd = y + y`, `h.p = y.mq()`, `var z: P8 = y.mq()` stored an Od2 / Q8 into an
#       Odd / P8 silently, and `z = y.same()` drew only "assigning non-pointer to typed pointer".
#       Root cause: `_sc_post` (src/frontend/parse_fn.cyr) returned before recording a result of
#       class 0, so no destination had a sid to compare (and the scalar operator dispatch never
#       called it). Fixed by recording it with `_sc_tmp = -3` (`_sc_post_small`). An exact-
#       register (1/2/4/8 B) struct FIELD skipped every check, the free call `h.p = mkq8()` too:
#       `_fsc_src` (src/frontend/parse_decl.cyr) returned 0 before its call and expression arms.
#   L5  A struct destination ASSIGNED from a FREE call returning a DIFFERENT struct stored one
#       word: `p = mkq()` (24 B), `p = mkr()` (16 B), `z = mkod2()` (3 B), generic `s = mk(r.v)`
#       (the field argument infers T = i64, so the call reaches Box<i64>, not Box<Pt>). The
#       declarations `var z: Odd = mkod2()` and `var s: Box<Pt> = mk(r.v)` were not refused by
#       name either — only the retptr / rax:rdx receives compared the sid. Root cause:
#       `_try_struct_call_assign` (src/frontend/parse.cyr) exited at `cls == 0`, `n <= 1` and
#       the sid test with `return 0` = the scalar store.
#       At TOP LEVEL the same mismatch compiled clean at 9-16 B too (`var GZ: Pt = mkr()`,
#       `= GQ.mr()`: no frame, so no receive compared the sid; the binary SIGSEGV'd reading GZ.x),
#       and the LEADING declaration block — replayed by EMIT_GVAR_INITS, not PARSE_VAR — checked
#       nothing at any size. Fixed in `_scv_call_check` (9-16 B at top level),
#       `_sc_global_mismatch` (-3 and -1) and `_gvi_ann` / `_gvi_expr` (the leading block).
#   L1  (refusal half) `var p: Pt = h.q` / `p = h.q` from a field of a DIFFERENT struct type
#       SIGSEGV'd / copied a word; now a named refusal like every other struct copy.
#
# Refusal rows are checked on the MESSAGE (and that no binary was written), so a row cannot pass
# on an unrelated syntax error. Acceptance rows (same types) are checked against the literal exit
# code AND a CONTROL program that builds the same value field by field (every row, K1-K11: the
# control declares the same struct, assigns each field, and returns the same expression), so an
# acceptance cannot pass by the result path alone.
#
# MUTATION LEDGER (6.6.11, each mutant rebuilt from the fixed tree with the one change):
#   base 6.6.10 build/cycc                                -> RED, 28 of 30 refusal rows + K1
#                                                            (D16 / D24 were already refused)
#   `_sc_post_small` returns before recording              -> RED F3m F3o F8m A3m A8m D3m D3o D8m G3m L3m
#   `_pcmpe_struct_assign`'s type test removed             -> RED A3m A8m A16m
#   `_sca_mismatch` returns 0                              -> RED A3c A16 A24 AG
#   `_scv_call_check` returns 0                            -> RED D3c D8c G16c L3c L16c
#   `_scv_call_check` skips > 8 B at top level too         -> RED G16c L16c
#   `_sc_global_mismatch` checks only -3 (not 9-16 B, -1)  -> RED G16m L16m
#   `_gvi_expr` = a bare PCMPE (no leading-block check)    -> RED L3c L3m L16c L16m
#   `_gvi_ann` never reports the struct annotation         -> RED L3c L3m L16c L16m
#   `_fsc_src` keeps its exact-register `return 0`         -> RED F8m F8c
#   `_fla_arm` never arms                                  -> RED FLd FLa FL8 FL3 (and acceptance K1)
#   `_gen_decl_check` returns 0                            -> RED DG
#   real tree                                              -> GREEN
#
# Z (6.7.9) — THE SAME STRUCT, NO FRAME, IN THE DECLARATION ZONE. A whole METHOD or OPERATOR result
# of 9-16 B (rax:rdx) into a global of the SAME struct before the first top-level statement —
# `var G2: Q = Q0.mk();`, a generic method, `(Q0.mk())`, `Q0 + Q1` — compiled clean (rc 0, no
# diagnostic) on 6.7.0-6.7.8 and SIGSEGV'd at the first `G2.a`: the replay (`_gvi_expr`) ran only
# the type half of PARSE_VAR's top-level check and stored rax, the struct's first WORD, as the
# address of the inline G2. The free call and the same line after a statement were refused by
# name; now the zone is too (`_sc_global_pair`, src/frontend/parse_fn.cyr — the struct half of
# `_sc_global_receive`, shared; 6.7.8's dyn-only `_gvi_dyn_mcall` is subsumed and removed). Each
# refusal is exactly ONE error line: a line refused INSIDE its initialiser (an operand, an argument)
# is not refused again for its result (`_scv_err`, set by `_scv_disarm`). Filed: docs/development/issues/
# 2026-10-10-zone-global-from-method-struct-call-crashes.md (Z1 is its repro verbatim).
#   6.7.8 build/cycc / the 6.7.9 tree before the bite      -> RED Z1 Z3 Z4 Z5 (BUILT), Z11 Z12 Z13 (2 error lines)
#   `_gvi_expr` back on `_sc_global_mismatch` alone        -> RED Z1 Z3 Z4 Z5 (and dyn_checked C9b)
#   `_sc_global_pair` without its `_sc_whole` -1 test      -> RED Z1 Z3 Z4 Z5 Z8 (and dyn_checked C9a C9b)
#   `_sc_global_pair` without its `_scv_err` test (the      -> RED Z9 Z10 Z11 Z12 Z13 (2 error lines; and
#     result refused after a refusal inside the initialiser)     struct_value_codegen L15)
#   the test in `_gvi_expr` only (the zone; bite 19's first    -> RED Z11 Z12 Z13 (2 error lines: the
#     commit)                                                     post-statement line, as on 6.7.8)
#   real tree                                              -> GREEN
#
# PU / PK / RP16 (6.7.11) — `return E;` IN A FN RETURNING THE STRUCT S, E A `*X` OR A DEREFERENCE OF ONE (the
# user's decision 2026-10-13, (a): the struct E points at, at every size; issues/2026-10-13-small-struct-return-of-
# pointer-global-or-call-decision.md). A `*U` of ANOTHER struct — a global, a `: *U` call (the tail-call shape),
# a `*U` field, `*GU`, a `*U` local — is refused by name at 3 / 8 / 16 / 24 B, each the ONE error:
#   a fn returning the struct `S16` takes a value of that struct, or a pointer to one — got `GU16` (a `*U16`)
# Through 6.7.10 the 3 / 8 B rows compiled (the pointer's word, or U's bytes, as the S) and the 16 / 24 B rows were
# refused in other words ("... got `GU16`", "identifier is not a local", "return must be a bare local ..."). PK8 /
# PK16 / PK24 are the same shapes of the fn's own struct: its struct, a copy (the full matrix, every leg:
# tests/tcyr/crossos/struct_ptrmode_return_copy.tcyr, small_struct_handle_line.sh R13). RP16 pins that a generic's
# inline-REPLAYED `return GPT;` is never copied (it is the callee's return; see the row) — and, since 6.7.14, never
# judged by the caller's class either.
# Mutations (each a one-change copy of the fixed src built by the fixed compiler; measured 2026-10-14):
#   the tree before it (the 8 B refusal commit)        -> RED 19: PU3a-c PU8a-c (compiled: the pointer's word),
#                                                         PU16* PU24* (the old messages), PK8 PK16 PK24
#   `_ret_ptr_src` answering -1                        -> RED 12: PU16* PU24* PK16 PK24
#   `_ret_small_ptr` taking a bare local only (as before) -> RED 7: PU3a-c PU8a-c PK8
#   `_tc_small_sret_divert` without its `: *X` line    -> RED 2: PU3b PU8b (`return gu8();` kept its `jmp`)
#   `_ret_ptr_src` without its dereference arm         -> RED 3: PU16d PU24d PK24
#   `_ret_ptr_src` without its GIDEP test               -> RED 1: RP16 (compiled; the binary SIGSEGVs, rc 139)
#     (6.7.14, re-measured 2026-10-16: GREEN — the replay now runs with no struct class (`_inl_replay_body`), so
#     the copy arm is never reached from a replayed `return`; the GIDEP test is a second guard)
#   (6.7.14) `_inl_replay_body` without its mask        -> RED 1: RP16 (refused by the caller's 9-16 B class, as
#                                                         through 6.7.13)
#   real tree                                          -> GREEN (64 refusals, 17 acceptances; 6.7.14: 63 / 18, RP16 accepted)
#
# 6.7.16 (the user's D1, 2026-10-19; TG0-TG12, TG0n, TA1-TA6d, TGX on aarch64 / cx / PE): a struct result over 8 B stored
# in a name typed by T makes the generic a stub (`_gs_var_sres`, `_gs_asg_sres`, src/frontend/parse_fn.cyr).
# (a scratch copy of the tree with the one change, its 2-stage cycc, this gate run from it with CYCC=:)
#   MTG1 the tree before (1135ae069)                    -> RED 19: TG0 TG0n TG1 TG2 TG4-TG12 (compiled, no diagnostic), TG3 (D24's
#                                                         words), TGX on aarch64 / cx / PE
#   MTG2 `_gs_var_sres` answering 0                     -> RED 15: TG0 TG0n TG1-TG3 TG6-TG12 (every `var y: T = ..` row), TGX x3
#   MTG3 `_gs_asg_sres` answering 0                     -> RED 4: TG4 TG4b TG5 TG5b (the assignments)
#   MTG4 `_gs_sres` without its operator / `&f` / method arms -> RED 3: TG6 (the method), TG8 (`fncall0(&mkp)`), TG9 (the operator)
#   MTG5 no rescan at pass 1's end                      -> RED 1: TG10 (mkl declared below gl: pass 1 knew no return)
#   MTG6 `_gs_sres_big` without the size test (`_rcv_big` -> sid > 0) -> RED 2: TA2 TA3 (an 8-byte struct, a `Str`: refused as stubs)
#   MTG7 `_gs_asg_sres` without its `*` test (the review fix) -> RED 3: TA6 TA6b TA6c (`*p = mkp();` made the generic a stub)
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: mktemp -d failed"; exit 77; }
trap 'rm -rf "$D"' EXIT

MF="into a struct field of a different struct type"
MA="into a variable of a different struct/vector type"
MD="fn return struct-id differs from declared var type"
MT="returns a struct by value, and a struct result needs storage in a fn's frame"
pass=0; fail=0; nrefuse=0; naccept=0

refuse() {  # $1 label  $2 expected message  $3 source  [$4 "one" = exactly one error line, or a count]
    printf '%s' "$3" > "$D/r.cyr"
    rc=0
    cat "$D/r.cyr" | "$CC" > "$D/r.bin" 2>"$D/r.err" || rc=$?
    nrefuse=$((nrefuse+1))
    nerr=$(grep -c '^error' "$D/r.err" 2>/dev/null || true)
    want=${4:-}
    [ "$want" = "one" ] && want=1
    if grep -q "$2" "$D/r.err" 2>/dev/null; then
        if [ -s "$D/r.bin" ]; then
            printf '  FAIL: %-34s reported but still emitted a binary\n' "$1"; fail=$((fail+1))
        elif [ -n "$want" ] && [ "$nerr" != "$want" ]; then
            printf '  FAIL: %-34s %s error lines, want exactly %s\n' "$1" "$nerr" "$want"; fail=$((fail+1))
        else
            printf '  ok(refused): %-28s\n' "$1"; pass=$((pass+1))
        fi
    else
        printf '  FAIL: %-34s not refused (rc=%s, first line: %s)\n' \
            "$1" "$rc" "$(grep -v '^note' "$D/r.err" 2>/dev/null | head -1 || echo '(no output)')"
        fail=$((fail+1))
    fi
}

# The error lines EXACTLY (`line:col: message`, each line's `error:<source>:` stripped, joined by `|`), and no
# binary: a row that pins which uses are reported and which stand down. 6.7.16
refuse_at() {  # $1 label  $2 the expected error lines  $3 source
    printf '%s' "$3" > "$D/r.cyr"
    rc=0
    cat "$D/r.cyr" | "$CC" > "$D/r.bin" 2>"$D/r.err" || rc=$?
    nrefuse=$((nrefuse+1))
    got=$(grep '^error' "$D/r.err" 2>/dev/null | sed 's/^error:<source>://' | tr '\n' '|' | sed 's/|$//' || true)
    if [ -s "$D/r.bin" ]; then
        printf '  FAIL: %-34s still emitted a binary (rc=%s)\n' "$1" "$rc"; fail=$((fail+1))
    elif [ "$got" != "$2" ]; then
        printf '  FAIL: %-34s error lines\n    got:  %s\n    want: %s\n' "$1" "$got" "$2"; fail=$((fail+1))
    else
        printf '  ok(refused): %-28s\n' "$1"; pass=$((pass+1))
    fi
}

_run() {  # $1 source-file -> echoes the exit code, or X when nothing was emitted
    cat "$1" | "$CC" > "$D/a.bin" 2>"$D/a.err" || true
    if [ -s "$D/a.bin" ]; then
        chmod +x "$D/a.bin"
        r=0
        ( ulimit -c 0; timeout 60 "$D/a.bin" ) >/dev/null 2>&1 || r=$?
        echo "$r"
    else
        echo "X"
    fi
}

accept() {  # $1 label  $2 source  $3 expected exit  $4 field-by-field control source
    naccept=$((naccept+1))
    printf '%s' "$2" > "$D/a1.cyr"
    got=$(_run "$D/a1.cyr")
    printf '%s' "$4" > "$D/a2.cyr"
    ctl=$(_run "$D/a2.cyr")
    if [ "$ctl" != "$3" ]; then
        printf '  FAIL: %-34s CONTROL gave %s, want %s — the expectation is wrong\n' "$1" "$ctl" "$3"
        fail=$((fail+1)); return
    fi
    if [ "$got" = "$3" ]; then
        printf '  ok(accepted): %-27s exit=%s (control %s)\n' "$1" "$got" "$ctl"; pass=$((pass+1))
    else
        printf '  FAIL: %-34s exit=%s, want %s (control %s)\n' "$1" "$got" "$3" "$ctl"
        fail=$((fail+1))
    fi
}

# Odd / Od2 are different 3 B structs; P8 / Q8 different 8 B ones; Pt 16 B (rax:rdx), Q 24 B
# (retptr), R2 a second 16 B struct. `same` / `mq` are methods, `Od2_add` an operator.
T='struct Odd { a: i8; b: i16; }
struct Od2 { c: i16; d: i8; }
struct P8 { x: i32; y: i32; }
struct Q8 { z: i64; }
struct Pt { x; y; }
struct R2 { a; b; }
struct Q { a; b; c; }
struct H { o: Odd; t: i8; u: i32; }
struct HP { p: P8; k; }
struct HQ { q: Q; n; }
impl Od2 { fn same(self): Od2 { var r: Od2; r.c = 1; r.d = 2; return r; } }
impl Q8 { fn mq(self): Q8 { var r: Q8; r.z = 5; return r; } }
impl Odd { fn dup(self): Odd { var r: Odd; r.a = 3; r.b = 4; return r; } }
impl P8 { fn dup(self): P8 { var r: P8; r.x = 6; r.y = 7; return r; } }
impl Q { fn mr(self): R2 { var r: R2; r.a = 1; r.b = 2; return r; } }
fn Od2_add(p: Od2, q: Od2): Od2 { var r: Od2; r.c = 1; r.d = 2; return r; }
fn Odd_add(p: Odd, q: Odd): Odd { var r: Odd; r.a = p.a + q.a; r.b = p.b + q.b; return r; }
fn mkod2(): Od2 { var r: Od2; r.c = 1; r.d = 2; return r; }
fn mkodd(): Odd { var r: Odd; r.a = 5; r.b = 6; return r; }
fn mkq8(): Q8 { var r: Q8; r.z = 5; return r; }
fn mkp8(): P8 { var r: P8; r.x = 8; r.y = 9; return r; }
fn mkq(): Q { var q: Q; q.a = 1; q.b = 2; q.c = 3; return q; }
fn mkr(): R2 { var q: R2; q.a = 1; q.b = 2; return q; }
'
G='struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct RB { v: Pt; n; }
fn mk<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 5; return b; }
'
E='
var r = main(); syscall(60, r);
'

echo "refusals — a struct result stored into a struct destination of another type:"
refuse "F3m h.o = y.same()  (3 B method)" "$MF" "$T"'fn main(): i64 { var y: Od2; var h: H; h.o = y.same(); return 0; }'"$E"
refuse "F3o h.o = y + y  (3 B operator)" "$MF" "$T"'fn main(): i64 { var y: Od2; var h: H; h.o = y + y; return 0; }'"$E"
refuse "F8m h.p = y.mq()  (8 B method)" "$MF" "$T"'fn main(): i64 { var y: Q8; var h: HP; h.p = y.mq(); return 0; }'"$E"
refuse "F8c h.p = mkq8()  (8 B free call)" "$MF" "$T"'fn main(): i64 { var h: HP; h.p = mkq8(); return 0; }'"$E"
refuse "A3m z = y.same()  (3 B method)" "$MA" "$T"'fn main(): i64 { var y: Od2; var z: Odd; z = y.same(); return 0; }'"$E"
refuse "A8m z = y.mq()  (8 B method)" "$MA" "$T"'fn main(): i64 { var y: Q8; var z: P8; z = y.mq(); return 0; }'"$E"
refuse "A3c z = mkod2()  (3 B free call)" "$MA" "$T"'fn main(): i64 { var z: Odd; z = mkod2(); return 0; }'"$E"
refuse "A16m p = y.mr()  (16 B method)" "$MA" "$T"'fn main(): i64 { var y: Q; var p: Pt; p.x = 9; p.y = 9; p = y.mr(); return p.x; }'"$E"
refuse "A16 p = mkr()  (16 B rax:rdx)" "$MA" "$T"'fn main(): i64 { var p: Pt; p.x = 9; p.y = 9; p = mkr(); return p.x; }'"$E"
refuse "A24 p = mkq()  (24 B retptr)" "$MA" "$T"'fn main(): i64 { var p: Pt; p.x = 9; p.y = 9; p = mkq(); return p.x; }'"$E"
refuse "AG  s = mk(r.v)  (generic)" "$MA" "$G"'fn main(): i64 { var r: RB; r.v.x = 2; r.v.y = 7; r.n = 1; var s: Box<Pt>; s.n = 0; s = mk(r.v); return s.n; }'"$E"
refuse "D3m var z: Odd = y.same()" "$MD" "$T"'fn main(): i64 { var y: Od2; var z: Odd = y.same(); return 0; }'"$E"
refuse "D3o var z: Odd = y + y" "$MD" "$T"'fn main(): i64 { var y: Od2; var z: Odd = y + y; return 0; }'"$E"
refuse "D8m var z: P8 = y.mq()" "$MD" "$T"'fn main(): i64 { var y: Q8; var z: P8 = y.mq(); return 0; }'"$E"
refuse "D3c var z: Odd = mkod2()" "$MD" "$T"'fn main(): i64 { var z: Odd = mkod2(); return 0; }'"$E"
refuse "D8c var z: P8 = mkq8()" "$MD" "$T"'fn main(): i64 { var z: P8 = mkq8(); return 0; }'"$E"
refuse "D16 var p: Pt = mkr()" "$MD" "$T"'fn main(): i64 { var p: Pt = mkr(); return p.x; }'"$E"
refuse "D24 var p: Pt = mkq()" "$MD" "$T"'fn main(): i64 { var p: Pt = mkq(); return p.x; }'"$E"
refuse "DG  var s: Box<Pt> = mk(r.v)" "$MD" "$G"'fn main(): i64 { var r: RB; r.v.x = 2; r.v.y = 7; r.n = 1; var s: Box<Pt> = mk(r.v); return s.n; }'"$E"
# G3m — a top-level declaration AFTER the first top-level statement (PARSE_VAR's global arm,
# `_sc_global_receive`); the leading declaration block is replayed by EMIT_GVAR_INITS instead.
refuse "G3m var GZ: Odd = GY.same()  (top)" "$MD" "$T"'var GY = Od2 { 1, 2 };
GY.c = 3;
var GZ: Odd = GY.same();
syscall(60, 0);
'
# The same three results into a TOP-LEVEL struct-typed global, both after the first top-level
# statement (PARSE_VAR: `_scv_call_check`, `_sc_global_receive`) and in the LEADING declaration
# block (replayed by EMIT_GVAR_INITS through `_gvi_expr`). A 9-16 B result has no frame there:
# before this row it compiled clean and SIGSEGV'd reading GZ.x.
refuse "G16c var GZ: Pt = mkr()  (top)" "$MD" "$T"'var GQ = Q { 1, 2, 3 };
GQ.a = 4;
var GZ: Pt = mkr();
syscall(60, GZ.x);
'
refuse "G16m var GZ: Pt = GQ.mr()  (top)" "$MD" "$T"'var GQ = Q { 1, 2, 3 };
GQ.a = 4;
var GZ: Pt = GQ.mr();
syscall(60, GZ.x);
'
refuse "L3c var GZ: Odd = mkod2()  (lead)" "$MD" "$T"'var GZ: Odd = mkod2();
syscall(60, 0);
'
refuse "L3m var GZ: Odd = GY.same()  (lead)" "$MD" "$T"'var GY = Od2 { 1, 2 };
var GZ: Odd = GY.same();
syscall(60, 0);
'
refuse "L16c var GZ: Pt = mkr()  (lead)" "$MD" "$T"'var GZ: Pt = mkr();
syscall(60, GZ.x);
'
refuse "L16m var GZ: Pt = GQ.mr()  (lead)" "$MD" "$T"'var GQ = Q { 1, 2, 3 };
var GZ: Pt = GQ.mr();
syscall(60, GZ.x);
'
refuse "FLd var p: Pt = h.q  (field src)" "$MA" "$T"'fn main(): i64 { var h: HQ; h.n = 1; var p: Pt = h.q; return p.x; }'"$E"
refuse "FLa p = h.q  (field src)" "$MA" "$T"'fn main(): i64 { var h: HQ; h.n = 1; var p: Pt; p.x = 0; p.y = 0; p = h.q; return p.x; }'"$E"
refuse "FL8 z = h.p  (8 B field src)" "$MA" "$T"'struct HQ8 { p: Q8; }
fn main(): i64 { var h: HQ8; var z: P8; z = h.p; return 0; }'"$E"
refuse "FL3 var z: Od2 = h.o  (3 B field)" "$MA" "$T"'fn main(): i64 { var h: H; var z: Od2 = h.o; return 0; }'"$E"

# Z (6.7.9) — the SAME struct into a declaration-zone global: no frame for a 9-16 B result, refused
# by name exactly once, as the free call and the post-statement line are (see the header).
ZQ='include "lib/syscalls.cyr"
struct Q { a; b; }
struct E { a; }
struct Q3 { a; b; c; }
impl Q {
    fn mk(self): Q { var q = Q { self.a + 1, self.b + 2 }; return q; }
    fn gmk<T>(self, x: T): Q { var q = Q { self.a + x, self.b + 2 }; return q; }
    fn big(self): Q3 { var r = Q3 { 1, 2, 3 }; return r; }
}
impl E { fn mk(self): E { var e = E { self.a + 3 }; return e; } }
fn Q_add(x: Q, y: Q): Q { var r = Q { x.a + y.a, x.b + y.b }; return r; }
fn mkf(): Q { var q = Q { 5, 7 }; return q; }
var Q0: Q = Q { 4, 5 };
var Q1: Q = Q { 1, 2 };
var E0: E = E { 4 };
'
echo "the declaration zone — a 9-16 B struct result of the SAME struct has no frame (6.7.9):"
refuse "Z1 the filed repro  (zone method)" "'Q\.mk' $MT" 'include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q = Q { self.a + 1, self.b + 2 }; return q; } }
var Q0: Q = Q { 4, 5 };
var G2: Q = Q0.mk();                     # compiles; the binary SIGSEGVs (rc 139); want exit 57
syscall(60, G2.a * 10 + G2.b);
' one
refuse "Z2 = Q0.mk().mk()  (zone chain)" "'Q\.mk' $MT" "$ZQ"'var G2: Q = Q0.mk().mk();
syscall(60, G2.a * 10 + G2.b);
' one
refuse "Z3 = Q0.gmk(1)  (zone generic method)" "'Q\.gmk' $MT" "$ZQ"'var G2: Q = Q0.gmk(1);
syscall(60, G2.a * 10 + G2.b);
' one
refuse "Z4 = (Q0.mk())  (zone, wrapped)" "'Q\.mk' $MT" "$ZQ"'var G2: Q = (Q0.mk());
syscall(60, G2.a * 10 + G2.b);
' one
refuse "Z5 = Q0 + Q1  (zone operator)" "'Q_add' $MT" "$ZQ"'var G2: Q = Q0 + Q1;
syscall(60, G2.a * 10 + G2.b);
' one
refuse "Z6 = mkf()  (zone free call, as ever)" "'mkf' $MT" "$ZQ"'var G3: Q = mkf();
syscall(60, G3.a * 10 + G3.b);
' one
refuse "Z7 = Q0.big()  (zone 24 B, as ever)" "'Q\.big' $MT" "$ZQ"'var G4: Q3 = Q0.big();
syscall(60, G4.c);
' one
refuse "Z8 = Q0.mk()  (after a statement)" "'Q\.mk' $MT" "$ZQ"'syscall(1, 1, "", 0);
var G2: Q = Q0.mk();
syscall(60, G2.a * 10 + G2.b);
' one
# A line refused INSIDE its initialiser is that refusal alone: the result is not refused again.
refuse "Z9 = Q0 + Q0.mk()  (zone, right operand)" "the right operand of 'Q_add' is passed by address" "$ZQ"'var G2: Q = Q0 + Q0.mk();
syscall(60, G2.a);
' one
refuse "Z10 = Q0.gmk(nope)  (zone, bad argument)" "undefined variable 'nope'" "$ZQ"'var G2: Q = Q0.gmk(nope);
syscall(60, G2.a);
' one
# ... and after a statement, through the same `_sc_global_pair` (6.7.9: before it, two error lines).
refuse "Z11 = Q0 + Q0.mk()  (after, right operand)" "the right operand of 'Q_add' is passed by address" "$ZQ"'syscall(1, 1, "", 0);
var G2: Q = Q0 + Q0.mk();
syscall(60, G2.a);
' one
refuse "Z12 = Q0.mk() + Q1  (after, left operand)" "the left operand of 'Q_add' is passed by address" "$ZQ"'syscall(1, 1, "", 0);
var G2: Q = Q0.mk() + Q1;
syscall(60, G2.a);
' one
refuse "Z13 = Q0.gmk(nope)  (after, bad argument)" "undefined variable 'nope'" "$ZQ"'syscall(1, 1, "", 0);
var G2: Q = Q0.gmk(nope);
syscall(60, G2.a);
' one

echo "6.7.11 — a *U of another struct returned from a struct fn is refused by name, at every size:"
MU="takes a value of that struct, or a pointer to one — got"
refuse "PU3a 3 B: return GU3;" "$MU \`GU3\` (a \`\\*U3\`)" "$(printf 'struct S3 { a: i8; b: i8; c: i8; }\nstruct U3 { x: i8; y: i8; z: i8; }\nstruct W3 { pu: *U3; }\nvar GU3: *U3 = 0;\nfn gu3(): *U3 { return GU3; }\nfn f(): S3 { return GU3; }\nfn main(): i64 { var r: S3 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU3b 3 B: return gu3();" "$MU \`gu3\` (a \`\\*U3\`)" "$(printf 'struct S3 { a: i8; b: i8; c: i8; }\nstruct U3 { x: i8; y: i8; z: i8; }\nstruct W3 { pu: *U3; }\nvar GU3: *U3 = 0;\nfn gu3(): *U3 { return GU3; }\nfn f(): S3 { return gu3(); }\nfn main(): i64 { var r: S3 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU3c 3 B: var w: W3; return w.pu;" "$MU \`pu\` (a \`\\*U3\`)" "$(printf 'struct S3 { a: i8; b: i8; c: i8; }\nstruct U3 { x: i8; y: i8; z: i8; }\nstruct W3 { pu: *U3; }\nvar GU3: *U3 = 0;\nfn gu3(): *U3 { return GU3; }\nfn f(): S3 { var w: W3; return w.pu; }\nfn main(): i64 { var r: S3 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU3d 3 B: return *GU3;" "$MU \`\\*GU3\` (a \`U3\`)" "$(printf 'struct S3 { a: i8; b: i8; c: i8; }\nstruct U3 { x: i8; y: i8; z: i8; }\nstruct W3 { pu: *U3; }\nvar GU3: *U3 = 0;\nfn gu3(): *U3 { return GU3; }\nfn f(): S3 { return *GU3; }\nfn main(): i64 { var r: S3 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU3e 3 B: var pu: *U3 = GU3; return (pu);" "$MU \`pu\` (a \`\\*U3\`)" "$(printf 'struct S3 { a: i8; b: i8; c: i8; }\nstruct U3 { x: i8; y: i8; z: i8; }\nstruct W3 { pu: *U3; }\nvar GU3: *U3 = 0;\nfn gu3(): *U3 { return GU3; }\nfn f(): S3 { var pu: *U3 = GU3; return (pu); }\nfn main(): i64 { var r: S3 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU8a 8 B: return GU8;" "$MU \`GU8\` (a \`\\*U8\`)" "$(printf 'struct S8 { v; }\nstruct U8 { u; }\nstruct W8 { pu: *U8; }\nvar GU8: *U8 = 0;\nfn gu8(): *U8 { return GU8; }\nfn f(): S8 { return GU8; }\nfn main(): i64 { var r: S8 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU8b 8 B: return gu8();" "$MU \`gu8\` (a \`\\*U8\`)" "$(printf 'struct S8 { v; }\nstruct U8 { u; }\nstruct W8 { pu: *U8; }\nvar GU8: *U8 = 0;\nfn gu8(): *U8 { return GU8; }\nfn f(): S8 { return gu8(); }\nfn main(): i64 { var r: S8 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU8c 8 B: var w: W8; return w.pu;" "$MU \`pu\` (a \`\\*U8\`)" "$(printf 'struct S8 { v; }\nstruct U8 { u; }\nstruct W8 { pu: *U8; }\nvar GU8: *U8 = 0;\nfn gu8(): *U8 { return GU8; }\nfn f(): S8 { var w: W8; return w.pu; }\nfn main(): i64 { var r: S8 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU8d 8 B: return *GU8;" "$MU \`\\*GU8\` (a \`U8\`)" "$(printf 'struct S8 { v; }\nstruct U8 { u; }\nstruct W8 { pu: *U8; }\nvar GU8: *U8 = 0;\nfn gu8(): *U8 { return GU8; }\nfn f(): S8 { return *GU8; }\nfn main(): i64 { var r: S8 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU8e 8 B: var pu: *U8 = GU8; return (pu);" "$MU \`pu\` (a \`\\*U8\`)" "$(printf 'struct S8 { v; }\nstruct U8 { u; }\nstruct W8 { pu: *U8; }\nvar GU8: *U8 = 0;\nfn gu8(): *U8 { return GU8; }\nfn f(): S8 { var pu: *U8 = GU8; return (pu); }\nfn main(): i64 { var r: S8 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU16a 16 B: return GU16;" "$MU \`GU16\` (a \`\\*U16\`)" "$(printf 'struct S16 { v; w; }\nstruct U16 { u; t; }\nstruct W16 { pu: *U16; }\nvar GU16: *U16 = 0;\nfn gu16(): *U16 { return GU16; }\nfn f(): S16 { return GU16; }\nfn main(): i64 { var r: S16 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU16b 16 B: return gu16();" "$MU \`gu16\` (a \`\\*U16\`)" "$(printf 'struct S16 { v; w; }\nstruct U16 { u; t; }\nstruct W16 { pu: *U16; }\nvar GU16: *U16 = 0;\nfn gu16(): *U16 { return GU16; }\nfn f(): S16 { return gu16(); }\nfn main(): i64 { var r: S16 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU16c 16 B: var w: W16; return w.pu;" "$MU \`pu\` (a \`\\*U16\`)" "$(printf 'struct S16 { v; w; }\nstruct U16 { u; t; }\nstruct W16 { pu: *U16; }\nvar GU16: *U16 = 0;\nfn gu16(): *U16 { return GU16; }\nfn f(): S16 { var w: W16; return w.pu; }\nfn main(): i64 { var r: S16 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU16d 16 B: return *GU16;" "$MU \`\\*GU16\` (a \`U16\`)" "$(printf 'struct S16 { v; w; }\nstruct U16 { u; t; }\nstruct W16 { pu: *U16; }\nvar GU16: *U16 = 0;\nfn gu16(): *U16 { return GU16; }\nfn f(): S16 { return *GU16; }\nfn main(): i64 { var r: S16 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU16e 16 B: var pu: *U16 = GU16; return (pu);" "$MU \`pu\` (a \`\\*U16\`)" "$(printf 'struct S16 { v; w; }\nstruct U16 { u; t; }\nstruct W16 { pu: *U16; }\nvar GU16: *U16 = 0;\nfn gu16(): *U16 { return GU16; }\nfn f(): S16 { var pu: *U16 = GU16; return (pu); }\nfn main(): i64 { var r: S16 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU24a 24 B: return GU24;" "$MU \`GU24\` (a \`\\*U24\`)" "$(printf 'struct S24 { v; w; x; }\nstruct U24 { u; t; s; }\nstruct W24 { pu: *U24; }\nvar GU24: *U24 = 0;\nfn gu24(): *U24 { return GU24; }\nfn f(): S24 { return GU24; }\nfn main(): i64 { var r: S24 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU24b 24 B: return gu24();" "$MU \`gu24\` (a \`\\*U24\`)" "$(printf 'struct S24 { v; w; x; }\nstruct U24 { u; t; s; }\nstruct W24 { pu: *U24; }\nvar GU24: *U24 = 0;\nfn gu24(): *U24 { return GU24; }\nfn f(): S24 { return gu24(); }\nfn main(): i64 { var r: S24 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU24c 24 B: var w: W24; return w.pu;" "$MU \`pu\` (a \`\\*U24\`)" "$(printf 'struct S24 { v; w; x; }\nstruct U24 { u; t; s; }\nstruct W24 { pu: *U24; }\nvar GU24: *U24 = 0;\nfn gu24(): *U24 { return GU24; }\nfn f(): S24 { var w: W24; return w.pu; }\nfn main(): i64 { var r: S24 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU24d 24 B: return *GU24;" "$MU \`\\*GU24\` (a \`U24\`)" "$(printf 'struct S24 { v; w; x; }\nstruct U24 { u; t; s; }\nstruct W24 { pu: *U24; }\nvar GU24: *U24 = 0;\nfn gu24(): *U24 { return GU24; }\nfn f(): S24 { return *GU24; }\nfn main(): i64 { var r: S24 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU24e 24 B: var pu: *U24 = GU24; return (pu);" "$MU \`pu\` (a \`\\*U24\`)" "$(printf 'struct S24 { v; w; x; }\nstruct U24 { u; t; s; }\nstruct W24 { pu: *U24; }\nvar GU24: *U24 = 0;\nfn gu24(): *U24 { return GU24; }\nfn f(): S24 { var pu: *U24 = GU24; return (pu); }\nfn main(): i64 { var r: S24 = f(); return 0; }\nsyscall(60, main());\n')" one


# A generic's straight-line body is REPLAYED inline at its call, and the replayed `return` is the CALLEE's: the
# 6.7.11 `*S` copy never runs there (copied, it was a struct where the call's pointer belongs — SIGSEGV, rc 139),
# and since 6.7.14 the caller's 9-16 B class does not judge it either (through 6.7.13 it was refused, "... two
# registers ... got `GPT`"): the row compiles, and `return p;` copies the struct p points at — 55.
# issues/archived/2026-10-14-generic-instance-return-takes-enclosing-fns-struct-return-class.md
accept "RP16 a generic's replayed return GPT; in a : S16 fn" 'struct S16 { v; w; }
var G16 = S16 { 4, 5 };
var GPT: *S16 = 0;
fn gq<T>(): *S16 { return GPT; }
fn f(): S16 { GPT = &G16; var p: *S16 = gq<i64>(); p.v = p.v + 1; return p; }
fn main(): i64 { var r: S16 = f(); return r.v * 10 + r.w; }
syscall(60, main());
' 55 'struct S16 { v; w; }
fn f(): S16 { var r: S16; r.v = 5; r.w = 5; return r; }
fn main(): i64 { var r: S16 = f(); return r.v * 10 + r.w; }
syscall(60, main());
'

# ... and the struct the `*S` points at, from a global / call / field / dereference (6.7.11; the VALUES at every
# size, every leg, are tests/tcyr/crossos/struct_ptrmode_return_copy.tcyr).
accept "PK8 return GP8; (a *S8 global): its struct" 'struct S8 { v; }
var G8 = S8 { 0 };
var GP8: *S8 = 0;
fn f(): S8 { return GP8; }
fn main(): i64 { G8.v = 9; GP8 = &G8; var r: S8 = f(); G8.v = 0; return r.v; }
syscall(60, main());
' 9 'struct S8 { v; }
fn main(): i64 { var r: S8; r.v = 9; return r.v; }
syscall(60, main());
'
accept "PK16 return gp16(); (a : *S16 call): its struct" 'struct S16 { v; w; }
var G16 = S16 { 0, 0 };
fn gp16(): *S16 { return &G16; }
fn f(): S16 { return gp16(); }
fn main(): i64 { G16.v = 4; G16.w = 5; var r: S16 = f(); G16.v = 0; return r.v * 10 + r.w; }
syscall(60, main());
' 45 'struct S16 { v; w; }
fn main(): i64 { var r: S16; r.v = 4; r.w = 5; return r.v * 10 + r.w; }
syscall(60, main());
'
accept "PK24 return *w.p; (a dereference of a *S24 field)" 'struct S24 { v; w; x; }
struct W { p: *S24; }
var G24 = S24 { 0, 0, 0 };
fn f(w: W): S24 { return *w.p; }
fn main(): i64 { G24.v = 1; G24.w = 2; G24.x = 3; var w: W; w.p = &G24; var r: S24 = f(w); G24.x = 0; return r.v * 100 + r.w * 10 + r.x; }
syscall(60, main());
' 123 'struct S24 { v; w; x; }
fn main(): i64 { var r: S24; r.v = 1; r.w = 2; r.x = 3; return r.v * 100 + r.w * 10 + r.x; }
syscall(60, main());
'

# U (6.7.14, issues/archived/2026-10-16-unknown-annotation-type-cascades-into-d24-refusal.md) — an UNKNOWN annotation type
# over a struct result is refused ONCE, "unknown type 'Foo'": D24's "cannot initialise 'x: Foo' from 'Q_mk', which
# returns the struct 'Q'" followed it on the same line (the free call since 6.7.11, the `&f` call, a method and an
# operator since 6.7.13, `*Foo` / `**Foo` under D14), and the zone's top-level line too. D24 does not judge an
# annotation refused at its name (`_rcv_ann_refd`, parse_decl.cyr); the declaration parses on as a plain i64.
#   the tree before (the `_rcv_ann_refd` test removed)  -> RED 11: U0-U10 (2 error lines each); U11 U12 green
echo "6.7.14 — an unknown annotation type over a struct result is refused once (no D24 cascade):"
MU="unknown type 'Foo'"
UQ='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 333; q.b = 4; return q; } }
fn mkq(): Q { var q: Q; q.a = 333; q.b = 4; return q; }
fn Q_add(a: Q, c: Q): Q { var q: Q; q.a = a.a + c.a; q.b = 7; return q; }
struct P3 { a; b; c; }
fn mk3(a): P3 { var r: P3 = P3 { a, a + 1, a + 2 }; return r; }
'
refuse "U0 var x: Foo = b.mk()  (the filed repro)" "$MU" 'include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 333; q.b = 4; return q; } }
fn main(): i64 {
    var b = Q { 1, 2 };
    var x: Foo = b.mk();
    return 0;
}
syscall(60, main());
' one
refuse "U1 var x: Foo = mkq()  (free call)" "$MU" "$UQ"'fn main(): i64 { var x: Foo = mkq(); return 0; }'"$E" one
refuse "U2 var x: Foo = mk3(5)  (24 B)" "$MU" "$UQ"'fn main(): i64 { var x: Foo = mk3(5); return 0; }'"$E" one
refuse "U3 var x: Str = a + c  (operator)" "unknown type 'Str'" "$UQ"'fn main(): i64 { var a = Q { 1, 2 }; var c = Q { 3, 4 }; var x: Str = a + c; return 0; }'"$E" one
refuse "U4 var x: Foo = fncall0(&mkq)" "$MU" "$UQ"'fn main(): i64 { var x: Foo = fncall0(&mkq); return 0; }'"$E" one
refuse "U5 var x: *Foo = mkq()" "$MU" "$UQ"'fn main(): i64 { var x: *Foo = mkq(); return 0; }'"$E" one
refuse "U6 var x: *Foo = b.mk()" "$MU" "$UQ"'fn main(): i64 { var b = Q { 1, 2 }; var x: *Foo = b.mk(); return 0; }'"$E" one
refuse "U7 var x: **Foo = mkq()" "$MU" "$UQ"'fn main(): i64 { var x: **Foo = mkq(); return 0; }'"$E" one
refuse "U8 var x: Foo = (mkq())" "$MU" "$UQ"'fn main(): i64 { var x: Foo = (mkq()); var y = x + 1; return x; }'"$E" one
refuse "U9 var x: Foo = mkq()  (top, zone)" "$MU" "$UQ"'var x: Foo = mkq();
syscall(60, 0);
' one
refuse "U10 var x: Foo = b.mk()  (top, zone)" "$MU" "$UQ"'var b = Q { 1, 2 };
var x: Foo = b.mk();
syscall(60, 0);
' one
refuse "U11 var x: Foo = 5  (control)" "$MU" "$UQ"'fn main(): i64 { var x: Foo = 5; return 0; }'"$E" one
refuse "U12 var x: i64 = b.mk()  (D24 kept)" "cannot initialise 'x: i64' from 'Q\.mk'" "$UQ"'fn main(): i64 { var b = Q { 1, 2 }; var x: i64 = b.mk(); return 0; }'"$E" one

# U13-U28 (6.7.15, issues/archived/2026-10-17-refused-annotation-type-cascades-at-field-uses.md) — a USE of a variable or parameter
# whose annotation was refused says nothing more: each `.field` read, field store and `.m()` on it printed "no struct type
# in scope for 'x'; a '.field' access needs its struct declaration" after the "unknown type 'Foo'" line (the declaration
# parses on as a plain i64). `_tn_refuse_var` (parse_types.cyr) marks it with the late-declaration refusal's stand-down
# (`_ann_refd_mark` / `_ann_refd_said`, parse_fn_def.cyr), per (fn, name) — a local / parameter in its fn, a global at top
# level and in every fn body. The controls: an untyped `y.a`, another fn's untyped `x`, a global named like a refused
# parameter of a fn — each still "no struct type in scope". A top-level `var P: *Foo` global took a garbage struct type
# through 6.7.15 (`P.a` added "unknown field 'a' on struct '<some name>'"); 6.7.16 stands it down too
# (issues/2026-10-18-global-pointer-to-unknown-type-reads-first-struct.md; rows: type_name_refused.sh axis 7).
#   the tree before (`_tn_refuse_var` = `_tn_refuse`, no mark)  -> RED 12: U13-U24 (2-4 error lines each); U25-U28 green
echo "6.7.15 — a use of a variable whose annotation was refused is not a second error:"
MS="no struct type in scope for"
refuse "U13 var x: Foo = 5; return x.a;  (the filed repro)" "$MU" 'include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 333; q.b = 4; return q; } }
fn mkq(): Q { var q: Q; q.a = 333; q.b = 4; return q; }
fn main(): i64 {
    var x: Foo = 5;
    return x.a;
}
syscall(60, main());
' one
refuse "U14 var x: Foo = b.mk(); x.a = 1;  (store)" "$MU" "$UQ"'fn main(): i64 { var b = Q { 1, 2 }; var x: Foo = b.mk(); x.a = 1; return 0; }'"$E" one
refuse "U15 fn f(q: *Foo) { return q.a; }  (param)" "unknown type 'Foo' for parameter 'q'" "$UQ"'fn f(q: *Foo): i64 { return q.a; }
fn main(): i64 { return 0; }'"$E" one
refuse "U16 var x: Foo = 5; return x.m();" "$MU" "$UQ"'fn main(): i64 { var x: Foo = 5; return x.m(); }'"$E" one
refuse "U17 var X: Foo = 5; X.a  (top, zone)" "$MU" "$UQ"'var X: Foo = 5;
syscall(60, X.a);
' one
refuse "U18 var X: Foo = 5; X.a  (after a stmt)" "$MU" "$UQ"'var a = 1;
a = 2;
var X: Foo = 5;
X.a = 3;
syscall(60, X.a);
' one
refuse "U19 fn reads a refused zone global X.a" "$MU" "$UQ"'var X: Foo = 5;
fn g(): i64 { X.b = 1; return X.a + X.m(); }
syscall(60, g());
' one
refuse "U20 var p: *Foo = 0; return p.a;" "unknown type 'Foo' as the target of pointer 'p'" "$UQ"'fn main(): i64 { var p: *Foo = 0; return p.a; }'"$E" one
refuse "U21 fn f(q: Foo) { return q.a; }  (by value)" "unknown type 'Foo' for parameter 'q'" "$UQ"'fn f(q: Foo): i64 { return q.a; }
fn main(): i64 { return 0; }'"$E" one
refuse "U22 a generic's two instances" "$MU" "$UQ"'fn g<T>(v: T): i64 { var y: Foo = 5; return y.a; }
fn main(): i64 { return g(1) + g(2); }'"$E" one
refuse "U23 in a closure body" "$MU" "$UQ"'fn main(): i64 { var f = |k| { var x: Foo = 5; return x.a + k; }; return fncall1(f, 0); }'"$E" one
refuse "U24 each use: x.a = 3; x.b += 1; x.a + x.m()" "$MU" "$UQ"'fn main(): i64 { var x: Foo = 5; x.a = 3; x.b += 1; return x.a + x.m(); }'"$E" one
refuse "U25 control: var y = 5; return y.a;" "$MS 'y'" "$UQ"'fn main(): i64 { var y = 5; return y.a; }'"$E" one
refuse "U26 control: another fn's untyped x" "$MS 'x'" "$UQ"'fn f(): i64 { var x: Foo = 5; return 0; }
fn g(): i64 { var x = 5; return x.a; }
fn main(): i64 { return f() + g(); }'"$E" 2
refuse "U27 control: a global named like a refused param" "$MS 'q'" "$UQ"'fn f(q: *Foo): i64 { return 0; }
var q = 5;
syscall(60, q.a);
' 2
refuse "U28 control: a local named like a refused global" "$MS 'X'" "$UQ"'var X: Foo = 5;
fn g(): i64 { var X = 5; return X.a; }
syscall(60, g());
' 2

# SH1-SH12 (6.7.16, issues/2026-10-18-refused-annotation-stand-down-silences-a-shadowing-block-variable.md) — THE STAND-DOWN
# IS THE VARIABLE'S, NOT ITS NAME'S. U13-U28's record was (fn, name), so a same-named variable in a nested or sibling
# block had its own genuine "no struct type in scope" silenced: SH1 (the filed repro, verbatim) printed only 4:12. The
# record now holds the refused declaration's slot, bound when it registers (`_ann_refd_bind`, parse_fn_def.cyr: a
# local, a parameter, a slice, a global after the fold), and a use stands down only on that slot. Each row: the exact
# error lines — the refused variable's own uses (SH2's outer `x.a`) still say nothing, the shadow's are reported.
#   the tree before (`_ann_refd_said` matching (scope, name) only)   -> RED 10: SH1 SH3-SH11 (the shadow's line missing)
#   the binding never made (`_ann_refd_bind` returning 0)           -> RED 10: as above (every record stays pending)
#   `_param_record` not binding                                      -> RED 1: SH4
#   `_gv_last_marks` not binding                                     -> RED 2: SH5 SH6
#   real tree                                                        -> GREEN
echo "6.7.16 — the refused-annotation stand-down is the refused variable's, not every same-named one's:"
SN="no struct type in scope for"
SA="; a '.field' access needs its struct declaration (missing include?)"
refuse_at "SH1 the filed repro (block shadow)" "4:12: unknown type 'Foo' for variable 'x'|5:35: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 {
    var x: Foo = 5;
    if (1) { var x = 7; return x.a; }
    return 0;
}
syscall(60, main());
'
refuse_at "SH2 the refused x's own x.a: silent" "4:12: unknown type 'Foo' for variable 'x'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 {
    var x: Foo = 5;
    if (1) { var y = x.a; x.b = 2; }
    return x.a + x.m();
}
syscall(60, main());
'
refuse_at "SH3 a sibling block's refused x" "4:21: unknown type 'Foo' for variable 'x'|5:35: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 {
    if (1) { var x: Foo = 5; var y = x.a; }
    if (1) { var x = 7; return x.a; }
    return 0;
}
syscall(60, main());
'
refuse_at "SH4 a refused parameter, shadowed" "3:9: unknown type 'Foo' for parameter 'x'|4:35: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn f(x: Foo): i64 {
    if (1) { var x = 7; return x.a; }
    return x.a;
}
syscall(60, f(1));
'
refuse_at "SH5 top level after a stmt, block" "5:8: unknown type 'Foo' for variable 'x'|6:36: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct Q { a; b; }
var y = 1;
y = 2;
var x: Foo = 5;
if (1) { var x = 7; syscall(60, x.a); }
syscall(60, x.a);
'
refuse_at "SH6 a zone global, top-level block" "3:8: unknown type 'Foo' for variable 'X'|6:28: $SN 'X'$SA" 'include "lib/syscalls.cyr"
struct P { a; }
var X: Foo = 5;
var y = 1;
y = 2;
if (1) { var X = 7; y = X.a; }
syscall(60, X.a + y);
'
refuse_at "SH7 a refused late struct's annotation" "4:1: a \`struct\` declaration must come before the first top-level statement (line 3)|7:35: $SN 'q'$SA" 'include "lib/syscalls.cyr"
var a = 1;
a = 2;
struct Q { y; }
fn f(): i64 {
    var q: Q = 0;
    if (1) { var q = 7; return q.y; }
    return q.y;
}
syscall(60, f());
'
refuse_at "SH8 a refused struct's literal" "4:1: a \`struct\` declaration must come before the first top-level statement (line 3)|7:35: $SN 'q'$SA" 'include "lib/syscalls.cyr"
var a = 1;
a = 2;
struct Q { y; }
fn f(): i64 {
    var q = Q { 5 };
    if (1) { var q = 7; return q.y; }
    return q.y;
}
syscall(60, f());
'
refuse_at "SH9 the shadow's store and method" "4:12: unknown type 'Foo' for variable 'x'|5:29: $SN 'x'; a '.field' assignment needs its struct declaration (missing include?)|7:35: $SN 'x'; a method call needs its struct declaration (missing include?)" 'include "lib/syscalls.cyr"
struct P { a; }
fn f(): i64 {
    var x: Foo = 5;
    if (1) { var x = 7; x.a = 3; }
    x.a = 4;
    if (1) { var x = 8; return x.m(); }
    return x.m();
}
syscall(60, f());
'
refuse_at "SH10 a generic's two instances" "4:12: unknown type 'Foo' for variable 'x'|5:35: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct P { a; }
fn g<T>(v: T): i64 {
    var x: Foo = 5;
    if (1) { var x = 7; return x.a; }
    return x.a;
}
syscall(60, g(1) + g<i32>(2));
'
refuse_at "SH11 in a closure body" "4:39: unknown type 'Foo' for variable 'x'|4:78: $SN 'x'$SA" 'include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct P { a; }
fn main(): i64 { var f = |k| { var x: Foo = 5; if (1) { var x = 7; return x.a; } return x.a + k; }; return fncall1(f, 0); }
syscall(60, main());
'
refuse_at "SH12 a redeclared zone global (folded)" "4:8: unknown type 'Foo' for variable 'X'" 'include "lib/syscalls.cyr"
struct P { a; }
var X = 1;
var X: Foo = 5;
syscall(60, X.a);
'

# UC (6.7.16, issues/2026-10-18-untyped-closure-capture-field-use-says-undefined-variable.md) — `.field`, a field store and
# `.m()` ON AN UNTYPED CLOSURE CAPTURE take the `sid == 0` arms an untyped local takes. PARSE_FIELD_LOAD's and
# PARSE_FIELD_STORE's capture rung (`_CL_CAP_FIELD_IDX`) answered for a struct capture only, so an untyped one fell to
# the globals and "undefined variable 'x'" — at the right column, naming the wrong fault; after a refused annotation it
# was a second error (the stand-down looked up no capture). Now the rung (`_cl_cap_fld_any`, parse_decl.cyr) hands any
# capture on as its capture-band index with sid 0: "no struct type in scope for 'x'" in the field / store / method
# wording, a captured vector's "SIMD vector has no named fields", and the refused-annotation stand-down, which resolves
# the capture to its declaring fn's slot through any nesting (`_cl_cap_origin`, parse_expr.cyr: the closure context
# keeps its host fn, `_cl_host_fn`, and the enclosing context, `_cl_ctx_up`). The same arm calls a bounded scalar T's
# member on a captured receiver (`|| v.show()` at T = i64 was "undefined variable 'v'": tests/tcyr/crossos/
# trait_bounds.tcyr K1-K9). `--syntax-only` stays silent (UC12). A capture named like a GLOBAL keeps today's reading
# (the global's field) — refusing it stops a program compiling: the user's call, not this gate's.
# (Mutants: a scratch copy of src/ with the one change, CYCC= its compiler; CPX's cross compilers come from it too.)
#   the tree before (4b6958340)                         -> RED 21: UC0-UC2 UC5-UC11 UC13 UC14 ("undefined variable"),
#                                                          CPX UC0-UC2 on aarch64 / cx / PE
#   `_cl_cap_fld_any` = `_CL_CAP_FIELD_IDX` (the rung)   -> RED 21: the same
#   `_ann_refd_said` without its capture arm             -> RED 9: UC2 UC7-UC11 (a second, no-struct error), CPX UC2 x3
#   `_cl_cap_origin` not following `_cl_ctx_up`          -> RED 2: UC8 UC10 (a capture of a capture)
echo "6.7.16 — .field / a field store / .m() on an untyped closure capture is an untyped local's:"
SM="; a method call needs its struct declaration (missing include?)"
SS="; a '.field' assignment needs its struct declaration (missing include?)"
UCA='include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x = 5; var f = |k| { return x.a + k; }; return fncall1(f, 0); }
syscall(60, main());
'
UCB='include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x = 5; var f = |k| { x.a = k; return x.m(); }; return fncall1(f, 0); }
syscall(60, main());
'
UCC='include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x: Foo = 5; var f = |k| { return x.a + k; }; return fncall1(f, 0); }
syscall(60, main());
'
refuse_at "UC0 |k| x.a + k  (the filed repro)" "3:54: $SN 'x'$SA" "$UCA"
refuse_at "UC1 x.a = k; x.m()  (store, method)" "3:47: $SN 'x'$SS|3:62: $SN 'x'$SM" "$UCB"
refuse_at "UC2 var x: Foo = 5; |k| x.a  (refused)" "3:25: unknown type 'Foo' for variable 'x'" "$UCC"
refuse_at "UC3 control: outside the closure" "3:39: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x = 5; return x.a; }
syscall(60, main());
'
accept "UC4 control: a struct-typed capture" 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct Q { a; b; }
fn main(): i64 { alloc_init(); var x: Q = Q { 1, 2 }; var f = |k| { return x.a + k; }; return fncall1(f, 0); }
syscall(60, main());
' 1 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x: Q = Q { 1, 2 }; return x.a; }
syscall(60, main());
'
refuse_at "UC5 a captured f64v2's .a" "3:57: SIMD vector has no named fields" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var v: f64v2; var f = |k| { return v.a + k; }; return fncall1(f, 0); }
syscall(60, main());
'
refuse_at "UC6 a nested closure's capture of a capture" "3:68: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x = 5; var f = |k| { var g = |j| { return x.a + j; }; return fncall1(g, k); }; return fncall1(f, 0); }
syscall(60, main());
'
refuse_at "UC7 refused: store, method, field" "3:25: unknown type 'Foo' for variable 'x'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x: Foo = 5; var f = |k| { x.a = k; return x.m() + x.b; }; return fncall1(f, 0); }
syscall(60, main());
'
refuse_at "UC8 refused, read by a nested closure" "3:25: unknown type 'Foo' for variable 'x'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x: Foo = 5; var f = |k| { var g = |j| { return x.a + j; }; return fncall1(g, k); }; return fncall1(f, 0); }
syscall(60, main());
'
refuse_at "UC9 refused in a closure, nested read" "3:39: unknown type 'Foo' for variable 'x'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var f = |k| { var x: Foo = 5; var g = |j| { return x.a + j; }; return fncall1(g, k); }; return fncall1(f, 0); }
syscall(60, main());
'
refuse_at "UC10 refused, two closures deep" "3:25: unknown type 'Foo' for variable 'x'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x: Foo = 5; var f = |k| { var g = |j| { var h = || x.a; return fncall0(h) + j; }; return fncall1(g, k); }; return fncall1(f, 0); }
syscall(60, main());
'
refuse_at "UC11 a refused parameter, captured" "3:10: unknown type 'Foo' for parameter 'q'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn h(q: *Foo): i64 { var f = |k| { return q.a + k; }; return fncall1(f, 0); }
fn main(): i64 { return 0; }
syscall(60, main());
'
refuse_at "UC13 the shadow of a refused x, captured" "3:25: unknown type 'Foo' for variable 'x'|3:84: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x: Foo = 5; if (1 == 1) { var x = 7; var f = |k| { return x.a + k; }; return fncall1(f, 0); } return 0; }
syscall(60, main());
'
refuse_at "UC14 y.m<i64>(1) on a capture" "3:58: $SN 'y'$SM" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var y = 5; var f = |k| { return y.m<i64>(1) + k; }; return fncall1(f, 0); }
syscall(60, main());
'
# UC12: --syntax-only (cyrius lint) — silent, rc 0, as for an untyped local.
for so in UCA UCB UCC; do
    eval "src=\$$so"
    printf '%s' "$src" > "$D/so.cyr"
    rc=0; "$CC" --syntax-only < "$D/so.cyr" > /dev/null 2> "$D/so.err" || rc=$?
    nrefuse=$((nrefuse+1))
    if [ "$rc" -eq 0 ] && ! grep -q '^error\|^warning' "$D/so.err"; then
        printf '  ok(silent): UC12 --syntax-only %s\n' "$so"; pass=$((pass+1))
    else
        printf '  FAIL: UC12 --syntax-only %s rc=%s: %s\n' "$so" "$rc" "$(head -1 "$D/so.err")"; fail=$((fail+1))
    fi
done

# AS (6.7.14, the user's decision D27 (a), 2026-10-16; issues/2026-10-16-struct-call-result-assigned-to-scalar-keeps-
# first-word.md) — a struct result over 8 B ASSIGNED to a scalar (a local, a parameter or a global declared `: i64`,
# `: u8`, `: f64`, `: cstring`, any annotation naming no struct) is refused with D24's words, "cannot assign 'x: i64'
# from 'mkp', which returns the struct 'Q' - declare 'x: Q' or bind a field", once per statement: the free call, a
# method, an operator, a known `&f` callee, a classic-for init and step, in parentheses, in a fn and at top level.
# Through 6.7.13 each stored the struct's first word, narrowed (the three filed repros exited 77), silently. A struct of
# 8 B or less and a `Str` keep their word (AK1 AK2); a `: bool` keeps its own refusal (AS21); over 16 B at top level the
# call's no-frame refusal is the one error (AS20). The destination's annotation is its declaration's in scope (AS19:
# a closed block's `var x: u8` is not the `x: i64` assigned).
#   the tree before (6.7.14 receives R2)                 -> RED 25: every AS row but AS20 AS21 (compiled)
#   `_try_struct_call_assign` without its `_asa_call`    -> RED 12: AS0 AS1-AS4 AS12-AS14 AS16-AS19
#   `_pcmpe_struct_assign` without its `_asa_rec`        -> RED 13: AS0m AS0o AS0oy AS0og AS5-AS11 AS15 AS22
#   `_asa_back` not stepping over a closed `}` / `)`     -> RED 1: AS19 (named 'x: u8')
#   `_asa_back` without its `_asa_for_hdr` (AF, below)   -> RED 8: AF1-AF4 AF6 (built), AF5 AFK1 AFK2 (the outer 'x: i64')
echo "6.7.14 (D27) — a struct result over 8 B assigned to a scalar is refused by name:"
AR=docs/development/issues/repros/2026-10-16-struct-call-result-assigned-to-scalar-keeps-first-word
AM="cannot assign 'x: i64' from 'mkp', which returns the struct 'Q' - declare 'x: Q' or bind a field"
AQ='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
struct Q3 { a; b; c; }
struct P1 { a; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn mk3(): Q3 { var q: Q3; q.a = 333; q.b = 4; q.c = 5; return q; }
fn mk1(): P1 { var q: P1; q.a = 333; return q; }
impl Q { fn mk(self): Q { var q: Q; q.a = 333; q.b = 4; return q; } }
impl Q3 { fn mk(self): Q3 { var q: Q3; q.a = 333; return q; } }
fn Q_add(l: *Q, r: *Q): Q { var q: Q; q.a = l.a + r.a; q.b = l.b + r.b; return q; }
var G: i64 = 0;
var GU: u8 = 0;
'
refuse "AS0 x = mkp()  (the filed repro)" "$AM" "$(cat $AR.cyr)" one
refuse "AS0m x = b.mk()  (the filed repro)" "cannot assign 'x: i64' from 'Q\.mk', which returns the struct 'Q'" "$(cat $AR-method.cyr)" one
refuse "AS0o x = a + c  (the filed repro)" "cannot assign 'x: i64' from 'Q_add', which returns the struct 'Q'" "$(cat $AR-operator.cyr)" 3
refuse "AS0oy y = a + c  (u8, same)" "cannot assign 'y: u8' from 'Q_add'" "$(cat $AR-operator.cyr)" 3
refuse "AS0og G = a + c  (global, same)" "cannot assign 'G: i64' from 'Q_add'" "$(cat $AR-operator.cyr)" 3
refuse "AS1 x = mkp()  (u8 local)" "cannot assign 'x: u8' from 'mkp'" "$AQ"'fn main(): i64 { var x: u8 = 0; x = mkp(); return x; }'"$E" one
refuse "AS2 x = mkp()  (f64 local)" "cannot assign 'x: f64' from 'mkp'" "$AQ"'fn main(): i64 { var x: f64 = 0.0; x = mkp(); return 7; }'"$E" one
refuse "AS3 G = mkp()  (global, in a fn)" "cannot assign 'G: i64' from 'mkp'" "$AQ"'fn main(): i64 { G = mkp(); return G; }'"$E" one
refuse "AS4 G = mkp()  (global, top level)" "cannot assign 'G: i64' from 'mkp'" "$AQ"'G = mkp();
syscall(60, G);
' one
refuse "AS5 x = b.mk()  (u8 local)" "cannot assign 'x: u8' from 'Q\.mk'" "$AQ"'fn main(): i64 { var b = Q { 1, 2 }; var x: u8 = 0; x = b.mk(); return x; }'"$E" one
refuse "AS6 x = b.mk()  (f64 local)" "cannot assign 'x: f64' from 'Q\.mk'" "$AQ"'fn main(): i64 { var b = Q { 1, 2 }; var x: f64 = 0.0; x = b.mk(); return 7; }'"$E" one
refuse "AS7 G = B.mk()  (top level)" "cannot assign 'G: i64' from 'Q\.mk'" "$AQ"'var B = Q { 1, 2 };
G = B.mk();
syscall(60, G);
' one
refuse "AS8 x = a + c  (f64 local)" "cannot assign 'x: f64' from 'Q_add'" "$AQ"'fn main(): i64 { var a = Q { 300, 2 }; var c = Q { 33, 2 }; var x: f64 = 0.0; x = a + c; return 7; }'"$E" one
refuse "AS9 x = fncall0(&mkp)" "$AM" "$AQ"'fn main(): i64 { var x: i64 = 0; x = fncall0(&mkp); return x; }'"$E" one
refuse "AS10 x = callptr(&mkp)  (u8)" "cannot assign 'x: u8' from 'mkp'" "$AQ"'fn main(): i64 { var x: u8 = 0; x = callptr(&mkp); return x; }'"$E" one
refuse "AS11 GU = fncall0(&mkp)  (top level)" "cannot assign 'GU: u8' from 'mkp'" "$AQ"'GU = fncall0(&mkp);
syscall(60, GU);
' one
refuse "AS12 for (..; ..; x = mkp())  (a step)" "$AM" "$AQ"'fn main(): i64 { var x: i64 = 0; var i = 0; for (i = 0; i < 1; x = mkp()) { i = i + 1; } return x; }'"$E" one
refuse "AS13 for (x = mkp(); ..)  (an init)" "$AM" "$AQ"'fn main(): i64 { var x: i64 = 0; for (x = mkp(); x < 0; x = x + 1) { } return x; }'"$E" one
refuse "AS14 x = mk3()  (24 B)" "cannot assign 'x: i64' from 'mk3', which returns the struct 'Q3'" "$AQ"'fn main(): i64 { var x: i64 = 0; x = mk3(); return x; }'"$E" one
refuse "AS15 x = b.mk()  (24 B method)" "cannot assign 'x: i64' from 'Q3\.mk'" "$AQ"'fn main(): i64 { var b = Q3 { 1, 2, 3 }; var x: i64 = 0; x = b.mk(); return x; }'"$E" one
refuse "AS16 x = mkp()  (an i64 parameter)" "$AM" "$AQ"'fn f(x: i64): i64 { x = mkp(); return x; }
fn main(): i64 { return f(1); }'"$E" one
refuse "AS17 x = (mkp())  (in parentheses)" "$AM" "$AQ"'fn main(): i64 { var x: i64 = 0; x = (mkp()); return x; }'"$E" one
refuse "AS18 x = mkp()  (a cstring local)" "cannot assign 'x: cstring' from 'mkp'" "$AQ"'fn main(): i64 { var x: cstring = 0; x = mkp(); return 5; }'"$E" one
refuse "AS19 x = mkp()  (a closed block's x: u8)" "$AM" "$AQ"'fn main(): i64 { var x: i64 = 0; if (x == 0) { var x: u8 = 1; x = 2; } x = mkp(); return x; }'"$E" one
refuse "AS20 G = mk3()  (top level, 24 B: no frame)" "$MT" "$AQ"'G = mk3();
syscall(60, G);
' one
refuse "AS21 x = mkp()  (a bool keeps its refusal)" "cannot assign a value that is not a bool to bool 'x'" "$AQ"'fn main(): i64 { var x: bool = false; x = mkp(); return 5; }'"$E" one
refuse "AS22 x = (b.mk())  (in parentheses)" "cannot assign 'x: i64' from 'Q\.mk'" "$AQ"'fn main(): i64 { var b = Q { 1, 2 }; var x: i64 = 0; x = (b.mk()); return x; }'"$E" one
accept "AK1 x = mk1()  (8 B: the word)" "$AQ"'fn main(): i64 { var x: i64 = 0; x = mk1(); var y: u8 = 0; y = mk1(); return x - 300 + y; }'"$E" 110 \
    "$AQ"'fn main(): i64 { var x: i64 = 333; var y: u8 = 77; return x - 300 + y; }'"$E"
accept "AK2 x = mks()  (a Str: the handle)" 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn mks(): Str { return str_from("abcde"); }
fn main(): i64 { alloc_init(); var x: i64 = 0; x = mks(); var s: Str = x; return s.len(); }
syscall(60, main());
' 5 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn main(): i64 { alloc_init(); var s: Str = str_from("abcde"); return s.len(); }
syscall(60, main());
'
accept "AK3 x = mkp().a  (bind a field)" "$AQ"'fn main(): i64 { var x: i64 = 0; x = mkp().a; var b = Q { 1, 2 }; var y: u8 = 0; y = b.mk().b; return x - 300 + y; }'"$E" 37 \
    "$AQ"'fn main(): i64 { var x: i64 = 333; var y: u8 = 4; return x - 300 + y; }'"$E"
# AF — a classic-for header's `var` is in its body's scope, though the walk steps over the header as a closed `( )`
# (`_asa_for_hdr`, the 6.7.14 receives review): the header's `x: u8` is the destination (AF1-AF4 AF6 stored the word
# silently, exit 77; AF5 was refused naming the outer 'x: i64'), and an untyped header `x` shadowing an outer `x: i64`
# is that untyped `x` (AFK1 AFK2: through 6.7.14's review they were refused naming the outer 'x: i64'; through 6.7.14
# they kept the word, exit 77; since 6.7.15's D33 an untyped destination is refused, naming the header's 'x').
refuse "AF1 for (var x: u8 ..) { x = mkp(); }" "cannot assign 'x: u8' from 'mkp'" "$AQ"'fn main(): i64 { var r = 0; for (var x: u8 = 0; x < 1; x = x + 1) { x = mkp(); r = x; } return r; }'"$E" one
refuse "AF2 for (var x: u8 ..) { x = b.mk(); }" "cannot assign 'x: u8' from 'Q\.mk'" "$AQ"'fn main(): i64 { var r = 0; var b = Q { 1, 2 }; for (var x: u8 = 0; x < 1; x = x + 1) { x = b.mk(); r = x; } return r; }'"$E" one
refuse "AF3 for (var x: u8 ..) { x = a + c; }" "cannot assign 'x: u8' from 'Q_add'" "$AQ"'fn main(): i64 { var r = 0; var a = Q { 300, 2 }; var c = Q { 33, 2 }; for (var x: u8 = 0; x < 1; x = x + 1) { x = a + c; r = x; } return r; }'"$E" one
refuse "AF4 for (var x: u8 ..) { x = fncall0(&mkp); }" "cannot assign 'x: u8' from 'mkp'" "$AQ"'fn main(): i64 { var r = 0; for (var x: u8 = 0; x < 1; x = x + 1) { x = fncall0(&mkp); r = x; } return r; }'"$E" one
refuse "AF5 for (var x: u8 ..) { if (..) { x = mkp(); } }" "cannot assign 'x: u8' from 'mkp'" "$AQ"'fn main(): i64 { var x: i64 = 0; var r = 0; for (var x: u8 = 0; x < 1; x = x + 1) { if (r == 0) { x = mkp(); } r = x; } return r; }'"$E" one
refuse "AF6 for (var x: u8 ..) { x = mkp(); }  (top level)" "cannot assign 'x: u8' from 'mkp'" "$AQ"'var r = 0;
for (var x: u8 = 0; x < 1; x = x + 1) { x = mkp(); r = x; }
syscall(60, r);
' one
UM="cannot assign 'x' from 'mkp', which returns the struct 'Q' - declare 'x: Q' or bind a field"
refuse "AFK1 x: i64; for (var x = 0 ..) { x = mkp(); }" "$UM" "$AQ"'fn main(): i64 { var x: i64 = 0; var r = 0; for (var x = 0; x < 1; x = x + 1) { x = mkp(); r = x; } return r; }'"$E" one
refuse "AFK2 x: i64; for (var a, x = two() ..) { x = mkp(); }" "$UM" "$AQ"'fn two(): (i64, i64) { return (1, 2); }
fn main(): i64 { var x: i64 = 0; var r = 0; for (var a, x = two(); a < 2; a = a + 1) { x = mkp(); r = x; } return r; }'"$E" one

# AP (6.7.15, the user's decision D32 (a), 2026-10-18; issues/2026-10-17-struct-result-assigned-to-pointer-or-untyped-
# scalar-keeps-first-word.md) — a struct result over 8 B ASSIGNED to a `*T` (a local, a parameter or a global declared
# `*i64`, `*u8`, `**Q`, any `*T` but `*S` of the result's own struct) is refused with D14's words, "cannot assign
# 'p: *i64' from 'mkp', which returns the struct 'Q' - declare 'p: Q' and take `&p`", once: the free call, a method, an
# operator, a known `&f` callee, a for step, in parentheses, in a fn and at top level. Through 6.7.14 each stored the
# struct's first word as the pointer (the filed repro faulted at `*p`, 139), with no diagnostic or only the
# typed-pointer warning. A `*Q` destination of the same struct copies through the pointer, as since 6.7.10 (APK1); a
# struct of 8 B or less keeps its word (APK2).
# AU (the user's decision D33 (a)) — the same into an UNTYPED destination (`var x = 0;`, an untyped parameter or
# global, a destructure name, a for-in name, a closure's parameter): D27's words without an annotation, "cannot assign
# 'x' from 'mkp', which returns the struct 'Q' - declare 'x: Q' or bind a field". Through 6.7.14 each kept the first
# word (the filed repro exited 77). 8 B or less and a `Str` keep their word (AUK1 AUK3); a variable declared from the
# struct copies (AUK2); a closure's capture keeps its own one refusal (AUK4).
#   the tree before (6.7.15 receives R3, D31's commit)   -> RED 31: AP0-AP13, AU0-AU14, AFK1 AFK2 (compiled)
#   the tree before D33 (D32's commit)                   -> RED 17: AU0-AU14 AFK1 AFK2 (compiled)
#   `_asa_judge` without its `_asa_ptr` arm               -> RED 14: AP0-AP13 (compiled)
#   `_asa_judge` without its untyped (`a == 0`) arm       -> RED 17: AU0-AU14 AFK1 AFK2 (compiled)
#   `_asa_ann` answering 0 for a name that is no variable -> RED 1: AUK5 (two errors)
# `_asa_ptr`'s own-struct test is a guard no row reaches: a `*Q` destination of the result's struct is a handle,
# copied before `_asa_refuse` (APK1 builds and copies with the test removed — measured).
echo "6.7.15 (D32 / D33) — a struct result over 8 B assigned to a *T or an untyped variable is refused by name:"
PM="cannot assign 'p: \*i64' from 'mkp', which returns the struct 'Q' - declare 'p: Q' and take \`&p\`"
PQ="$AQ"'var GP: *i64 = 0;
var GW = 0;
fn two(): (f64, f64) { return (1.5, 2.5); }
'
refuse "AP0 p = mkp() into *i64  (the filed repro)" "$PM" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn main(): i64 {
    var p: *i64 = 0;
    p = mkp();
    return *p;
}
syscall(60, main());
' one
refuse "AP1 p = mkp()  (a *u8 local)" "cannot assign 'p: \*u8' from 'mkp', which returns the struct 'Q' - declare 'p: Q' and take" "$PQ"'fn main(): i64 { var p: *u8 = 0; p = mkp(); return 1; }'"$E" one
refuse "AP2 p = mkp()  (a *i64 parameter)" "$PM" "$PQ"'fn f(p: *i64): i64 { p = mkp(); return 1; }
fn main(): i64 { return f(0); }'"$E" one
refuse "AP3 GP = mkp()  (a *i64 global, in a fn)" "cannot assign 'GP: \*i64' from 'mkp'.* take \`&GP\`" "$PQ"'fn main(): i64 { GP = mkp(); return 1; }'"$E" one
refuse "AP4 GP = mkp()  (top level)" "cannot assign 'GP: \*i64' from 'mkp'" "$PQ"'GP = mkp();
syscall(60, 1);
' one
refuse "AP5 p = b.mk()  (a method)" "cannot assign 'p: \*i64' from 'Q\.mk', which returns the struct 'Q'" "$PQ"'fn main(): i64 { var b = Q { 1, 2 }; var p: *i64 = 0; p = b.mk(); return 1; }'"$E" one
refuse "AP6 p = a + c  (an operator)" "cannot assign 'p: \*i64' from 'Q_add'" "$PQ"'fn main(): i64 { var a = Q { 1, 2 }; var c = Q { 3, 4 }; var p: *i64 = 0; p = a + c; return 1; }'"$E" one
refuse "AP7 p = fncall0(&mkp)" "$PM" "$PQ"'fn main(): i64 { var p: *i64 = 0; p = fncall0(&mkp); return 1; }'"$E" one
refuse "AP8 p = callptr(&mkp)  (*u8)" "cannot assign 'p: \*u8' from 'mkp'" "$PQ"'fn main(): i64 { var p: *u8 = 0; p = callptr(&mkp); return 1; }'"$E" one
refuse "AP9 for (..; ..; p = mkp())  (a step)" "$PM" "$PQ"'fn main(): i64 { var p: *i64 = 0; for (var i = 0; i < 1; p = mkp()) { i = i + 1; } return 1; }'"$E" one
refuse "AP10 p = mk3()  (24 B)" "cannot assign 'p: \*i64' from 'mk3', which returns the struct 'Q3' - declare 'p: Q3'" "$PQ"'fn main(): i64 { var p: *i64 = 0; p = mk3(); return 1; }'"$E" one
refuse "AP11 p = (mkp())  (in parentheses)" "$PM" "$PQ"'fn main(): i64 { var p: *i64 = 0; p = (mkp()); return 1; }'"$E" one
refuse "AP12 GP = B.mk()  (top level, a method)" "cannot assign 'GP: \*i64' from 'Q\.mk'" "$PQ"'var B = Q { 1, 2 };
GP = B.mk();
syscall(60, 1);
' one
refuse "AP13 p = mkp()  (a **Q local)" "cannot assign 'p: \*\*Q' from 'mkp'" "$PQ"'fn main(): i64 { var q: Q; var pq: *Q = &q; var p: **Q = &pq; p = mkp(); return 1; }'"$E" one
accept "APK1 p = mkp() into *Q  (copies through p)" "$PQ"'fn main(): i64 { var q: Q; q.a = 1; q.b = 2; var p: *Q = &q; p = mkp(); return q.b - 400; }'"$E" 44 \
    "$PQ"'fn main(): i64 { var q: Q; q.a = 333; q.b = 444; return q.b - 400; }'"$E"
accept "APK2 p = mk1() into *i64  (8 B: the word)" "$PQ"'fn main(): i64 { var p: *i64 = 0; p = mk1(); var w = p; return w - 300; }'"$E" 33 \
    "$PQ"'fn main(): i64 { var p = 333; return p - 300; }'"$E"
refuse "AU0 x = mkp() into var x = 0  (the filed repro)" "$UM" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn main(): i64 {
    var x = 0;
    x = mkp();
    return x;
}
syscall(60, main());
' one
refuse "AU1 x = mkp()  (an untyped parameter)" "$UM" "$PQ"'fn f(x): i64 { x = mkp(); return x; }
fn main(): i64 { return f(0); }'"$E" one
refuse "AU2 GW = mkp()  (an untyped global, in a fn)" "cannot assign 'GW' from 'mkp', which returns the struct 'Q' - declare 'GW: Q' or bind a field" "$PQ"'fn main(): i64 { GW = mkp(); return GW; }'"$E" one
refuse "AU3 GW = mkp()  (top level)" "cannot assign 'GW' from 'mkp'" "$PQ"'GW = mkp();
syscall(60, GW);
' one
refuse "AU4 a = mkp()  (a destructure name)" "cannot assign 'a' from 'mkp'" "$PQ"'fn main(): i64 { var q, a = two(); a = mkp(); return 1; }'"$E" one
refuse "AU5 x = b.mk()  (a method)" "cannot assign 'x' from 'Q\.mk', which returns the struct 'Q'" "$PQ"'fn main(): i64 { var b = Q { 1, 2 }; var x = 0; x = b.mk(); return x; }'"$E" one
refuse "AU6 x = a + c  (an operator)" "cannot assign 'x' from 'Q_add'" "$PQ"'fn main(): i64 { var a = Q { 1, 2 }; var c = Q { 3, 4 }; var x = 0; x = a + c; return x; }'"$E" one
refuse "AU7 x = fncall0(&mkp)" "$UM" "$PQ"'fn main(): i64 { var x = 0; x = fncall0(&mkp); return x; }'"$E" one
refuse "AU8 x = callptr(&mkp)" "$UM" "$PQ"'fn main(): i64 { var x = 0; x = callptr(&mkp); return x; }'"$E" one
refuse "AU9 for (..; ..; x = mkp())  (a step)" "$UM" "$PQ"'fn main(): i64 { var x = 0; for (var i = 0; i < 1; x = mkp()) { i = i + 1; } return x; }'"$E" one
refuse "AU10 x = mk3()  (24 B)" "cannot assign 'x' from 'mk3', which returns the struct 'Q3'" "$PQ"'fn main(): i64 { var x = 0; x = mk3(); return x; }'"$E" one
refuse "AU11 x = (mkp())  (in parentheses)" "$UM" "$PQ"'fn main(): i64 { var x = 0; x = (mkp()); return x; }'"$E" one
# AU12's leading `var t` puts the closure's parameter off slot 0, which Q_add's `l: *Q` left typed; since 6.7.16 the
# parameter is untyped in any slot (CP0-CP7 below).
refuse "AU12 |x| { x = mkp(); }  (a closure's parameter)" "$UM" "$PQ"'fn main(): i64 { var t = 1; var k = |x| { x = mkp(); return x; }; return callptr(k, t); }'"$E" one
refuse "AU13 for x in 0..3 { x = mkp(); }  (a for-in name)" "$UM" "$PQ"'fn main(): i64 { for x in 0..3 { x = mkp(); } return 1; }'"$E" one
accept "AUK1 x = mk1() into var x = 0  (8 B: the word)" "$PQ"'fn main(): i64 { var x = 0; x = mk1(); return x - 300; }'"$E" 33 \
    "$PQ"'fn main(): i64 { var x = 333; return x - 300; }'"$E"
accept "AUK2 var x = mkp(); x = mkp();  (copies)" "$PQ"'fn main(): i64 { var x = mkp(); x.b = 1; x = mkp(); return x.b - 400; }'"$E" 44 \
    "$PQ"'fn main(): i64 { var x: Q; x.a = 333; x.b = 444; return x.b - 400; }'"$E"
accept "AUK3 x = mks() into var x = 0  (a Str: the handle)" 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn mks(): Str { return str_from("abcde"); }
fn main(): i64 { alloc_init(); var x = 0; x = mks(); var s: Str = x; return s.len(); }
syscall(60, main());
' 5 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn main(): i64 { alloc_init(); var s: Str = str_from("abcde"); return s.len(); }
syscall(60, main());
'
refuse "AU14 GW2 = mkp()  (a global destructure name declared below)" "cannot assign 'GW2' from 'mkp'" "$PQ"'fn main(): i64 { GW2 = mkp(); return 1; }
var GW1, GW2 = two();'"$E" one
refuse "AUK5 undefx = mkp()  (an undefined name: its own error)" "undefined variable 'undefx'" "$PQ"'fn main(): i64 { undefx = mkp(); return 1; }'"$E" one
refuse "AUK4 t = mkp() on a capture  (its own refusal)" "'t' is captured by value; a captured name is not assignable in a closure" "$PQ"'fn main(): i64 { var t = 0; var k = |y| { t = mkp(); return t + y; }; return callptr(k, 0); }'"$E" one

# CP (6.7.16, issues/2026-10-18-closure-parameter-keeps-an-earlier-fns-slot-type.md) — A CLOSURE'S PARAMETER IS UNTYPED
# IN EVERY SLOT. The closure prologue (`_PARSE_FACTOR_IMPL`'s `|params|` arm) wrote only a parameter's name and depth
# word; the slot's type word (GLTYPE) and slice word are kept per slot INDEX across fns, so a parameter in the slot an
# earlier fn's typed local or parameter used (here `fn h(w: *Q)`, slot 0) was read as that type: `x.b`, `x.m()` and
# `x.b = 5` compiled through *Q and faulted (rc 0, exit 139), and `x = mkp()` copied the struct through x (exit 139)
# where D33 refuses it. Now each parameter (and the hidden env slot) is declared by `_cl_param_slot` (parse_fn.cyr),
# which resets the type words as PARSE_FN_DEF's untyped parameter does: each is refused as an untyped name's. CP6 /
# CP7: a plain use is unchanged (exit 42), and an earlier `fn h(w: f64)` no longer makes `x + 1` "f64 arithmetic with
# a non-f64 right operand". CPX (the end): CP0 / CP1 from the aarch64, cx and PE compilers.
#   the tree before (13200c3d1)                          -> RED 7: CP0-CP5 (compiled), CP7 (the f64 warning)
#   `_cl_param_slot` without its SLTYPE reset            -> RED 7: the same
#   the env slot left on its old writes                  -> GREEN (no use reads the env slot's type: a guard)
echo "6.7.16 — a closure's parameter is untyped whatever an earlier fn left in its slot:"
NSF="no struct type in scope for 'x'; a '.field' access needs its struct declaration (missing include?)"
CPA='include "lib/syscalls.cyr"
struct Q { a; b; }
fn h(w: *Q): i64 { return 0; }
fn main(): i64 { var k = |x| { return x.b; }; return callptr(k, 0); }
syscall(60, main());
'
CPB='include "lib/syscalls.cyr"
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn h(x: *Q): i64 { return 0; }
fn main(): i64 { var k = |x| { x = mkp(); return x; }; return callptr(k, 0); }
syscall(60, main());
'
refuse_at "CP0 |x| x.b after fn h(w: *Q)  (the filed repro)" "4:42: $NSF" "$CPA"
refuse_at "CP1 |x| { x = mkp(); }  (the filed D33 row)" "5:36: $UM" "$CPB"
refuse_at "CP2 |x| x.m()  (a method)" "5:42: no struct type in scope for 'x'; a method call needs its struct declaration (missing include?)" 'include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn m(self): i64 { return self.b; } }
fn h(w: *Q): i64 { return 0; }
fn main(): i64 { var k = |x| { return x.m(); }; return callptr(k, 0); }
syscall(60, main());
'
refuse_at "CP3 |x| { x.b = 5; }  (a field store)" "4:36: no struct type in scope for 'x'; a '.field' assignment needs its struct declaration (missing include?)" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn h(w: *Q): i64 { return 0; }
fn main(): i64 { var k = |x| { x.b = 5; return 0; }; return callptr(k, 0); }
syscall(60, main());
'
refuse_at "CP4 after fn h(w: Q)  (a struct by value)" "4:42: $NSF" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn h(w: Q): i64 { return 0; }
fn main(): i64 { var k = |x| { return x.b; }; return callptr(k, 0); }
syscall(60, main());
'
refuse_at "CP5 a capturing closure (env slot 0, x slot 1)" "4:54: $NSF" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn h(v, w: *Q): i64 { return 0; }
fn main(): i64 { var t = 2; var k = |x| { return x.b + t; }; return callptr(k, 0); }
syscall(60, main());
'
refuse_at "CPK1 control: var t = 1; first  (another slot)" "4:53: $NSF" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn h(w: *Q): i64 { return 0; }
fn main(): i64 { var t = 1; var k = |x| { return x.b; }; return callptr(k, t); }
syscall(60, main());
'
accept "CP6 |x| x + 1 after fn h(w: *Q)" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn h(w: *Q): i64 { return 0; }
fn main(): i64 { var k = |x| { return x + 1; }; return callptr(k, 41); }
syscall(60, main());
' 42 'include "lib/syscalls.cyr"
fn main(): i64 { var k = |x| { return x + 1; }; return callptr(k, 41); }
syscall(60, main());
'
# CP7: the value AND a silent compile (the stale f64 slot type warned "f64 arithmetic with a non-f64 right operand").
printf '%s' 'include "lib/syscalls.cyr"
fn h(w: f64): i64 { return 0; }
fn main(): i64 { var k = |x| { return x + 1; }; return callptr(k, 41); }
syscall(60, main());
' > "$D/cp7.cyr"
naccept=$((naccept+1))
cp7=$(_run "$D/cp7.cyr")
if [ "$cp7" = 42 ] && ! grep -q '^warning\|^error' "$D/a.err"; then
    printf '  ok(accepted): %-27s exit=42, no diagnostic\n' "CP7 |x| x + 1 after fn h(w: f64)"; pass=$((pass+1))
else
    printf '  FAIL: %-34s exit=%s, want 42 and no diagnostic (%s)\n' "CP7 |x| x + 1 after fn h(w: f64)" "$cp7" \
        "$(grep '^warning\|^error' "$D/a.err" | head -1)"; fail=$((fail+1))
fi

echo "acceptances — the same shapes with matching types, and the right VALUE:"
accept "K1 var p: Pt = b.v" 'struct Pt { x; y; }
struct Box { v: Pt; n; }
fn main(): i64 { var b: Box; b.v.x = 3; b.v.y = 4; b.n = 9; var p: Pt = b.v; return p.x * 10 + p.y; }'"$E" 34 'struct Pt { x; y; }
fn main(): i64 { var p: Pt; p.x = 3; p.y = 4; return p.x * 10 + p.y; }'"$E"
accept "K2 h.o = x.dup()  (3 B method)" "$T"'fn main(): i64 { var x: Odd; var h: H; h.t = 1; h.o = x.dup(); return h.o.a * 10 + h.o.b + h.t * 100; }'"$E" 134 \
    "$T"'fn main(): i64 { var h: H; h.t = 1; h.o.a = 3; h.o.b = 4; return h.o.a * 10 + h.o.b + h.t * 100; }'"$E"
accept "K3 z = x.dup()  (3 B method)" "$T"'fn main(): i64 { var x: Odd; var z: Odd; z = x.dup(); return z.a * 10 + z.b; }'"$E" 34 \
    "$T"'fn main(): i64 { var z: Odd; z.a = 3; z.b = 4; return z.a * 10 + z.b; }'"$E"
accept "K4 var z: Odd = x + x  (operator)" "$T"'fn main(): i64 { var x: Odd; x.a = 1; x.b = 2; var z: Odd = x + x; return z.a * 10 + z.b; }'"$E" 24 \
    "$T"'fn main(): i64 { var z: Odd; z.a = 2; z.b = 4; return z.a * 10 + z.b; }'"$E"
accept "K5 var z: P8 = x.dup()  (8 B)" "$T"'fn main(): i64 { var x: P8; var z: P8 = x.dup(); return z.x * 10 + z.y; }'"$E" 67 \
    "$T"'fn main(): i64 { var z: P8; z.x = 6; z.y = 7; return z.x * 10 + z.y; }'"$E"
accept "K6 h.p = mkp8()  (8 B free call)" "$T"'fn main(): i64 { var h: HP; h.k = 1; h.p = mkp8(); return h.p.x * 10 + h.p.y + h.k * 100; }'"$E" 189 \
    "$T"'fn main(): i64 { var h: HP; h.k = 1; h.p.x = 8; h.p.y = 9; return h.p.x * 10 + h.p.y + h.k * 100; }'"$E"
accept "K7 var z: Odd = mkodd()" "$T"'fn main(): i64 { var z: Odd = mkodd(); var w: Odd; w = mkodd(); return z.a * 10 + w.b; }'"$E" 56 \
    "$T"'fn main(): i64 { var z: Odd; z.a = 5; z.b = 6; var w: Odd; w.a = 5; w.b = 6; return z.a * 10 + w.b; }'"$E"
accept "K8 s = mk(p)  (generic, same T)" "$G"'fn main(): i64 { var p: Pt; p.x = 2; p.y = 7; var s: Box<Pt>; s.n = 0; s = mk(p); return s.v.x + s.v.y * 10 + s.n * 100; }'"$E" 60 \
    "$G"'fn main(): i64 { var s: Box<Pt>; s.v.x = 2; s.v.y = 7; s.n = 5; return s.v.x + s.v.y * 10 + s.n * 100; }'"$E"
# Top level, same types: the leading block's check (`_gvi_expr`) and PARSE_VAR's global arm
# must leave a matching <= 8 B result alone. Controls set the same global field by field.
accept "K9 var GZ: Odd = mkodd()  (lead)" "$T"'var GZ: Odd = mkodd();
syscall(60, GZ.a * 10 + GZ.b);
' 56 "$T"'var GZ = Odd { 0, 0 };
GZ.a = 5;
GZ.b = 6;
syscall(60, GZ.a * 10 + GZ.b);
'
accept "K10 var GZ: Odd = mkodd()  (top)" "$T"'var GY = Od2 { 7, 8 };
GY.c = 3;
var GZ: Odd = mkodd();
syscall(60, GZ.a * 10 + GZ.b);
' 56 "$T"'var GY = Od2 { 7, 8 };
GY.c = 3;
var GZ = Odd { 0, 0 };
GZ.a = 5;
GZ.b = 6;
syscall(60, GZ.a * 10 + GZ.b);
'
accept "K11 var GZ: Od2 = GY.same()  (lead)" "$T"'var GY = Od2 { 7, 8 };
var GZ: Od2 = GY.same();
syscall(60, GZ.c * 10 + GZ.d);
' 12 "$T"'var GY = Od2 { 7, 8 };
var GZ = Od2 { 0, 0 };
GZ.c = 1;
GZ.d = 2;
syscall(60, GZ.c * 10 + GZ.d);
'

accept "ZK1 var GE: E = E0.mk()  (zone 8 B)" "$ZQ"'var GE: E = E0.mk();
syscall(60, GE.a);
' 7 "$ZQ"'var GE = E { 0 };
GE.a = 7;
syscall(60, GE.a);
'
# 6.7.15 (the user's D35 (a), 2026-10-18): an untyped global from a 9-16 B method is refused as the annotated one is —
# this row pinned it holding the first word (exit 50) through 6.7.14
# (issues/archived/2026-10-17-top-level-untyped-method-operator-or-known-callee-struct-result-keeps-word.md)
refuse "ZK2 var G2 = Q0.mk()  (untyped 16 B: refused)" "'Q.mk' returns a struct by value, and a struct result needs storage in a fn's frame" "$ZQ"'var G2 = Q0.mk();
syscall(60, G2 * 10);
' one
accept "ZK3 G2 = Q0.mk() in a fn  (the fix-it)" "$ZQ"'var G2: Q = Q { 0, 0 };
fn init(): i64 { G2 = Q0.mk(); return 0; }
init();
syscall(60, G2.a * 10 + G2.b);
' 57 "$ZQ"'var G2: Q = Q { 0, 0 };
G2.a = 5;
G2.b = 7;
syscall(60, G2.a * 10 + G2.b);
'

# CPX (6.7.16) — the closure rows (CP0 CP1, UC0-UC2) from every cross compiler built from this tree (the frontend is
# shared; this pins it). The cross compilers are built from the tree's src/, so a mutant is a tree mutant.
echo "6.7.16 — the closure rows (CP, UC) from the aarch64, cx and PE compilers:"
echo "=== a struct result stored in a name typed by T (6.7.16, the user's D1, 2026-10-19): no scalar instance ==="
# `var y: T = mkp();` (`y = mkp();`, `p = mkp();` into a `*T` / `**T`) with mkp's struct over 8 B: each scalar instance
# refused the line by name (6.7.11's D24, 6.7.14's D27, 6.7.15's D32), but the base — the T = i64 instance — was exempt
# (`_rcv_tp_base`), so `g(5)` / `g(u)` kept the struct's first word (the filed repro: 77, 333 mod 256). The generic is a
# stub now: its scalar calls are refused by name, the note naming the line. A struct of 8 B or less and a `Str` are one
# word, which a scalar keeps; the struct instance copies. docs/development/issues/2026-10-18-generic-instance-t-
# annotation-takes-struct-first-word.md
TG0='include "lib/syscalls.cyr"
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn g<T>(x: T): i64 { var y: T = mkp(); return y; }
fn main(): i64 { var u: u8 = 5; return g(u); }
syscall(60, main());
'
TGM="generic 'g' has no i64 (or other scalar) instance"
refuse "TG0 the filed repro verbatim: g(u)" "$TGM" "$TG0" one
if grep -q "^  note: <source>:4:26: 'g' stores a struct result over 8 bytes in 'y', typed by its type parameter\$" "$D/r.err"; then
    printf '  ok(refused): %-28s\n' "TG0n the note names 4:26"; pass=$((pass+1))
else printf '  FAIL: %-34s %s\n' "TG0n the note" "$(grep '^  note' "$D/r.err" | head -1)"; fail=$((fail+1)); fi
TH='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
struct Q { a; b; }
struct Q8 { a; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn mk8(): Q8 { var q: Q8; q.a = 21; return q; }
fn mks(): Str { return str_from("abc"); }
impl Q { fn mk(self): Q { var q: Q; q.a = 301; q.b = 2; return q; } }
fn Q_add(a: Q, c: Q): Q { var q: Q; q.a = a.a + c.a; q.b = 1; return q; }
fn g<T>(x: T): i64 { var y: T = mkp(); return y; }
fn ga<T>(x: T): i64 { var y: T = x; y = mkp(); return 9; }
fn gpa<T>(y: T): i64 { y = mkp(); return 9; }
fn gp<T>(x: T): i64 { var p: *T = &x; p = mkp(); return 9; }
fn gpp<T>(x: T): i64 { var pp: **T = 0; pp = mkp(); return 9; }
fn gm<T>(x: T): i64 { var b: Q; var y: T = b.mk(); return 9; }
fn gw<T>(x: T): i64 { var y: T = ((mkp())); return 9; }
fn gf<T>(x: T): i64 { var y: T = fncall0(&mkp); return 9; }
fn go<T>(x: T): i64 { var a: Q; a.a = 300; var c: Q; c.a = 1; var y: T = a + c; return 9; }
fn gl<T>(x: T): i64 { var y: T = mkl(); return 9; }
fn k<T>(x: T): i64 { return g(x); }
fn g8<T>(x: T): i64 { var y: T = mk8(); return y; }
fn gs<T>(x: T): i64 { var y: T = mks(); return 9; }
fn gq<T>(x: T): i64 { var y: T = mkp(); return y.b - 400; }
fn gqa<T>(x: T): i64 { var y: T = x; y = mkp(); return y.b - 400; }
fn gqp<T>(x: T): i64 { var p: *T = &x; p = mkp(); return x.b - 400; }
fn gd<T>(x: T): i64 { var p: *T = &x; *p = mkp(); return 9; }
fn gdd<T>(x: T): i64 { var p: *T = &x; var pp: **T = &p; **pp = mkp(); return 9; }
fn gdq<T>(x: T): i64 { var p: *T = &x; *p = mkp(); return x.b - 400; }
fn mkl(): Q { var q: Q; q.a = 1; q.b = 2; return q; }
'
TE='
syscall(60, main());
'
refuse "TG1 g(5)" "$TGM" "$TH"'fn main(): i64 { return g(5); }'"$TE" one
refuse "TG2 g<i64>(5)" "$TGM" "$TH"'fn main(): i64 { return g<i64>(5); }'"$TE" one
refuse "TG3 g<i32>(5): the stub's words (D24's before)" "$TGM" "$TH"'fn main(): i64 { return g<i32>(5); }'"$TE" one
refuse "TG4 y = mkp(); (var y: T) at i64 (D27)" "generic 'ga' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return ga(5); }'"$TE" one
refuse "TG4b y = mkp(); (a y: T parameter)" "generic 'gpa' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gpa(5); }'"$TE" one
refuse "TG5 p = mkp(); (p: *T) at i64 (D32)" "generic 'gp' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gp(5); }'"$TE" one
refuse "TG5b pp = mkp(); (pp: **T)" "generic 'gpp' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gpp(5); }'"$TE" one
refuse "TG6 var y: T = b.mk(); (a method)" "generic 'gm' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gm(5); }'"$TE" one
refuse "TG7 var y: T = ((mkp())); (wrapped)" "generic 'gw' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gw(5); }'"$TE" one
refuse "TG8 var y: T = fncall0(&mkp);" "generic 'gf' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gf(5); }'"$TE" one
refuse "TG9 var y: T = a + c; (Q_add)" "generic 'go' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return go(5); }'"$TE" one
refuse "TG10 the callee declared below the generic" "generic 'gl' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gl(5); }'"$TE" one
refuse "TG11 k(5): a generic forwarding its T to g" "generic 'k' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return k(5); }'"$TE" one
refuse "TG12 &g" "$TGM" "$TH"'fn main(): i64 { var f = &g; return 1; }'"$TE" one
accept "TA1 g(q) at T = Q copies (y.b 444)" "$TH"'fn main(): i64 { var q: Q; q.a = 7; q.b = 8; return gq(q); }'"$TE" 44 'syscall(60, 44);'
accept "TA2 an 8 B result into y: T at i64 keeps its word" "$TH"'fn main(): i64 { return g8(5); }'"$TE" 21 'syscall(60, 21);'
accept "TA3 a Str result into y: T at i64 keeps its word" "$TH"'fn main(): i64 { alloc_init(); return gs(5); }'"$TE" 9 'syscall(60, 9);'
accept "TA4 y = mkp(); at T = Q copies" "$TH"'fn main(): i64 { var q: Q; q.a = 7; q.b = 8; return gqa(q); }'"$TE" 44 'syscall(60, 44);'
accept "TA5 p = mkp(); (p: *T) at T = Q copies through p" "$TH"'fn main(): i64 { var q: Q; q.a = 7; q.b = 8; return gqp(q); }'"$TE" 44 'syscall(60, 44);'
# TA6-TA6d: a store THROUGH the pointer is not one of D1's lines — it compiled at every instance before the stub rule
# (41ca7d41c: g(5) and g<i32>(5) rc 0) and still does; whether it is judged is its own question (the review's filing).
accept "TA6 *p = mkp(); (p: *T) at i64: not a stub" "$TH"'fn main(): i64 { return gd(5); }'"$TE" 9 'syscall(60, 9);'
accept "TA6b *p = mkp(); at gd<i32>(5)" "$TH"'fn main(): i64 { return gd<i32>(5); }'"$TE" 9 'syscall(60, 9);'
accept "TA6c **pp = mkp(); (pp: **T) at i64" "$TH"'fn main(): i64 { return gdd(5); }'"$TE" 9 'syscall(60, 9);'
accept "TA6d *p = mkp(); at T = Q copies through p" "$TH"'fn main(): i64 { var q: Q; q.a = 7; q.b = 8; return gdq(q); }'"$TE" 44 'syscall(60, 44);'

cross_rows() {  # $1 the leg's name
    refuse_at "CPX [$1] CP0" "4:42: $NSF" "$CPA"
    refuse_at "CPX [$1] CP1" "5:36: $UM" "$CPB"
    refuse_at "CPX [$1] UC0" "3:54: $SN 'x'$SA" "$UCA"
    refuse_at "CPX [$1] UC1" "3:47: $SN 'x'$SS|3:62: $SN 'x'$SM" "$UCB"
    refuse_at "CPX [$1] UC2" "3:25: unknown type 'Foo' for variable 'x'" "$UCC"
    refuse "TGX [$1] TG0" "$TGM" "$TG0" one
}
CC0=$CC
if "$CC0" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
    chmod +x "$D/cc_a64"; CC="$D/cc_a64"; cross_rows aarch64
else printf '  FAIL: aarch64: src/main_aarch64.cyr did not build\n'; fail=$((fail+1)); fi
if "$CC0" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ]; then
    chmod +x "$D/cc_cx"; CC="$D/cc_cx"; cross_rows cx
else printf '  FAIL: cx: src/main_cx.cyr did not build\n'; fail=$((fail+1)); fi
CC=$CC0; CYRIUS_TARGET_WIN=1; export CYRIUS_TARGET_WIN
cross_rows pe
unset CYRIUS_TARGET_WIN

echo "struct_result_type_refused: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$fail" -eq 0 ] || exit 1
exit 0
