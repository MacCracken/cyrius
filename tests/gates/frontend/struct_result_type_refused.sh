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
pass=0; fail=0; nrefuse=0; naccept=0

refuse() {  # $1 label  $2 expected message  $3 source
    printf '%s' "$3" > "$D/r.cyr"
    rc=0
    cat "$D/r.cyr" | "$CC" > "$D/r.bin" 2>"$D/r.err" || rc=$?
    nrefuse=$((nrefuse+1))
    if grep -q "$2" "$D/r.err" 2>/dev/null; then
        if [ -s "$D/r.bin" ]; then
            printf '  FAIL: %-34s reported but still emitted a binary\n' "$1"; fail=$((fail+1))
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
impl Mk for Od2 { fn same(self): Od2 { var r: Od2; r.c = 1; r.d = 2; return r; } }
impl Mk for Q8 { fn mq(self): Q8 { var r: Q8; r.z = 5; return r; } }
impl Mk for Odd { fn dup(self): Odd { var r: Odd; r.a = 3; r.b = 4; return r; } }
impl Mk for P8 { fn dup(self): P8 { var r: P8; r.x = 6; r.y = 7; return r; } }
impl Mk for Q { fn mr(self): R2 { var r: R2; r.a = 1; r.b = 2; return r; } }
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

echo "struct_result_type_refused: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$fail" -eq 0 ] || exit 1
exit 0
