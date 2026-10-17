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
refuse "Z1 the filed repro  (zone method)" "'Q_mk' $MT" 'include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q = Q { self.a + 1, self.b + 2 }; return q; } }
var Q0: Q = Q { 4, 5 };
var G2: Q = Q0.mk();                     # compiles; the binary SIGSEGVs (rc 139); want exit 57
syscall(60, G2.a * 10 + G2.b);
' one
refuse "Z2 = Q0.mk().mk()  (zone chain)" "'Q_mk' $MT" "$ZQ"'var G2: Q = Q0.mk().mk();
syscall(60, G2.a * 10 + G2.b);
' one
refuse "Z3 = Q0.gmk(1)  (zone generic method)" "'Q_gmk' $MT" "$ZQ"'var G2: Q = Q0.gmk(1);
syscall(60, G2.a * 10 + G2.b);
' one
refuse "Z4 = (Q0.mk())  (zone, wrapped)" "'Q_mk' $MT" "$ZQ"'var G2: Q = (Q0.mk());
syscall(60, G2.a * 10 + G2.b);
' one
refuse "Z5 = Q0 + Q1  (zone operator)" "'Q_add' $MT" "$ZQ"'var G2: Q = Q0 + Q1;
syscall(60, G2.a * 10 + G2.b);
' one
refuse "Z6 = mkf()  (zone free call, as ever)" "'mkf' $MT" "$ZQ"'var G3: Q = mkf();
syscall(60, G3.a * 10 + G3.b);
' one
refuse "Z7 = Q0.big()  (zone 24 B, as ever)" "'Q_big' $MT" "$ZQ"'var G4: Q3 = Q0.big();
syscall(60, G4.c);
' one
refuse "Z8 = Q0.mk()  (after a statement)" "'Q_mk' $MT" "$ZQ"'syscall(1, 1, "", 0);
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
# issues/2026-10-14-generic-instance-return-takes-enclosing-fns-struct-return-class.md
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
refuse "U12 var x: i64 = b.mk()  (D24 kept)" "cannot initialise 'x: i64' from 'Q_mk'" "$UQ"'fn main(): i64 { var b = Q { 1, 2 }; var x: i64 = b.mk(); return 0; }'"$E" one

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
refuse "AS0m x = b.mk()  (the filed repro)" "cannot assign 'x: i64' from 'Q_mk', which returns the struct 'Q'" "$(cat $AR-method.cyr)" one
refuse "AS0o x = a + c  (the filed repro)" "cannot assign 'x: i64' from 'Q_add', which returns the struct 'Q'" "$(cat $AR-operator.cyr)" 3
refuse "AS0oy y = a + c  (u8, same)" "cannot assign 'y: u8' from 'Q_add'" "$(cat $AR-operator.cyr)" 3
refuse "AS0og G = a + c  (global, same)" "cannot assign 'G: i64' from 'Q_add'" "$(cat $AR-operator.cyr)" 3
refuse "AS1 x = mkp()  (u8 local)" "cannot assign 'x: u8' from 'mkp'" "$AQ"'fn main(): i64 { var x: u8 = 0; x = mkp(); return x; }'"$E" one
refuse "AS2 x = mkp()  (f64 local)" "cannot assign 'x: f64' from 'mkp'" "$AQ"'fn main(): i64 { var x: f64 = 0.0; x = mkp(); return 7; }'"$E" one
refuse "AS3 G = mkp()  (global, in a fn)" "cannot assign 'G: i64' from 'mkp'" "$AQ"'fn main(): i64 { G = mkp(); return G; }'"$E" one
refuse "AS4 G = mkp()  (global, top level)" "cannot assign 'G: i64' from 'mkp'" "$AQ"'G = mkp();
syscall(60, G);
' one
refuse "AS5 x = b.mk()  (u8 local)" "cannot assign 'x: u8' from 'Q_mk'" "$AQ"'fn main(): i64 { var b = Q { 1, 2 }; var x: u8 = 0; x = b.mk(); return x; }'"$E" one
refuse "AS6 x = b.mk()  (f64 local)" "cannot assign 'x: f64' from 'Q_mk'" "$AQ"'fn main(): i64 { var b = Q { 1, 2 }; var x: f64 = 0.0; x = b.mk(); return 7; }'"$E" one
refuse "AS7 G = B.mk()  (top level)" "cannot assign 'G: i64' from 'Q_mk'" "$AQ"'var B = Q { 1, 2 };
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
refuse "AS15 x = b.mk()  (24 B method)" "cannot assign 'x: i64' from 'Q3_mk'" "$AQ"'fn main(): i64 { var b = Q3 { 1, 2, 3 }; var x: i64 = 0; x = b.mk(); return x; }'"$E" one
refuse "AS16 x = mkp()  (an i64 parameter)" "$AM" "$AQ"'fn f(x: i64): i64 { x = mkp(); return x; }
fn main(): i64 { return f(1); }'"$E" one
refuse "AS17 x = (mkp())  (in parentheses)" "$AM" "$AQ"'fn main(): i64 { var x: i64 = 0; x = (mkp()); return x; }'"$E" one
refuse "AS18 x = mkp()  (a cstring local)" "cannot assign 'x: cstring' from 'mkp'" "$AQ"'fn main(): i64 { var x: cstring = 0; x = mkp(); return 5; }'"$E" one
refuse "AS19 x = mkp()  (a closed block's x: u8)" "$AM" "$AQ"'fn main(): i64 { var x: i64 = 0; if (x == 0) { var x: u8 = 1; x = 2; } x = mkp(); return x; }'"$E" one
refuse "AS20 G = mk3()  (top level, 24 B: no frame)" "$MT" "$AQ"'G = mk3();
syscall(60, G);
' one
refuse "AS21 x = mkp()  (a bool keeps its refusal)" "cannot assign a value that is not a bool to bool 'x'" "$AQ"'fn main(): i64 { var x: bool = false; x = mkp(); return 5; }'"$E" one
refuse "AS22 x = (b.mk())  (in parentheses)" "cannot assign 'x: i64' from 'Q_mk'" "$AQ"'fn main(): i64 { var b = Q { 1, 2 }; var x: i64 = 0; x = (b.mk()); return x; }'"$E" one
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
accept "ZK2 var G2 = Q0.mk()  (untyped: word 1)" "$ZQ"'var G2 = Q0.mk();
syscall(60, G2 * 10);
' 50 "$ZQ"'var G2 = 5;
syscall(60, G2 * 10);
'
accept "ZK3 G2 = Q0.mk() in a fn  (the fix-it)" "$ZQ"'var G2: Q = Q { 0, 0 };
fn init(): i64 { G2 = Q0.mk(); return 0; }
init();
syscall(60, G2.a * 10 + G2.b);
' 57 "$ZQ"'var G2: Q = Q { 0, 0 };
G2.a = 5;
G2.b = 7;
syscall(60, G2.a * 10 + G2.b);
'

echo "struct_result_type_refused: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$fail" -eq 0 ] || exit 1
exit 0
