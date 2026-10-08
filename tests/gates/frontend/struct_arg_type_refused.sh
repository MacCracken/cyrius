#!/bin/sh
# Gate: a struct ARGUMENT is type-checked against its parameter (6.7.3, the repair lane).
#
# THE DEFECT (measured on 6.7.3's slot-open build/cycc, x86_64 Linux; every refusal row below
# compiled clean there, exit 0, no diagnostic): an argument's struct type was compared with its
# parameter's only for a struct-typed FIELD into an address-passed parameter (`take(r.v)`,
# 6.6.12). Everything else was pushed as it came and the callee read it with its OWN layout:
#   `bq(p)`, p: Pt (16 B) into `fn bq(b: Q)` (24 B)     -> b.c read past p: 0 (the filed repro)
#   `bs(mk1(p))`, a Box<Pt> into `fn bs(b: Box)`        -> 4 (b.v.y) where n is 8 (the filed repro)
#   a global Pt into bq                                 -> 97, whatever follows it in .data
#   a forwarded by-value parameter, a tail call         -> a stack word (56, 184 on one run)
#   `q + p` with `fn Q_add(a: Q, b: Q)`                 -> 1; `q + mkp()`, `q + p.dup()` -> SIGSEGV
#   `sl(p)` into `fn sl(s: Str)`                        -> SIGSEGV (139)
#   `gx(b)`, b: Box<Pt>, `fn gx<T>(b: Box<T>)`          -> 4 where 8 is right (T is not inferred
#                                                          through Box<T>: the BASE gx ran)
# and every other form below read the wrong struct silently. The RECEIVE path has refused the same
# mismatch since 6.6.6 (`var q: Q = p;` -> "cannot copy 'p' into a variable of a different
# struct/vector type"), so the argument path was the gap.
#
# THE RULE (the user's, 6.7.3): an argument whose STATIC struct type differs from its parameter's
# recorded struct (SFPSID — the instance's for a generic; a generic instance where the base is
# declared, and the reverse, included) is refused by name, in the 6.6.12 field arm's words:
#   cannot pass '<arg>' to a parameter of a different struct type in a call to '<fn>'
# <arg> is the variable, the called fn, the method fn or the field. Covered: inline, pointer-mode
# and `*T` locals; a global (in a fn and at top level); a closure capture; a free call (a generic
# instance included); a method or operator result (<= 8 B, 9-16 B and > 16 B); a whole field; the
# three argument loops (a call, a method's arguments, a tail call); a callee defined after the
# call (pass 1); a by-value struct of 8 B or less and a `Str` handle parameter (recorded since
# 6.7.3); an operator's two operands (parameters 0 and 1 of the operator fn); a method's `self`
# (parameter 0). STAYS ACCEPTED (no static struct): an untyped value or local, `&p` (as the receive
# path accepts `var q: *Q = &p`), a literal, a call returning an integer or a pointer, a fn pointer.
#
# Refusal rows are checked on the MESSAGE, that it is the ONE `^error`, and that no binary was
# written. Acceptance rows are checked against the exit code AND a field-by-field CONTROL;
# `compiles` rows (an accepted shape whose value is meaningless) only that a binary is written.
# The runtime half (every accepted form, every fork) is tests/tcyr/crossos/struct_arg_type_accepted.tcyr.
#
# MUTATION LEDGER (6.7.3, each mutant built from the fixed tree with the one change; measured):
#   base 6.7.3 build/cycc                              -> RED, all 44 refusal rows (compiled clean)
#   `_sarg_type_err` always returns 0                  -> RED, all 44 refusal rows
#   the local arm's `_sarg_type_err` dropped           -> RED R1 R3 R4a R4b R4c R10 R11 R12 R13b R14
#                                                         R15 R16 R17 R18 R18b R19 R20 R26 R33a R34a
#   the whole-call check in `_try_push_struct_addr_arg` dropped
#                                                      -> RED R2 R8
#   the `_push_struct_expr_arg` check dropped          -> RED R9
#   the global / capture checks dropped                -> RED R5 R6 / R7
#   `_psid_plain` returns 0 (no by-value / handle record)
#                                                      -> RED R13a R21 R22 R23 R24 R24b R25 R26b R26c
#                                                         R30 R33b R34b
#   `_sc_post` without the -4 record                   -> RED R24 R28b
#   `_fpk_note` records nothing                        -> RED R25
#   `_op_arg_check` returns 0                          -> RED R27 R28 R28b R29 R30
#   `_op_lhs_check` returns 0                          -> RED R31
#   the method-receiver check dropped                  -> RED R32
#   `_psid_def_note` writes a redefined fn's record    -> RED A9 (a false refusal)
#   real tree                                          -> GREEN (44 refusal rows, 9 acceptance rows)
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: mktemp -d failed"; exit 77; }
trap 'rm -rf "$D"' EXIT

MA="to a parameter of a different struct type in a call to"
pass=0; fail=0; nrefuse=0; naccept=0

refuse() {  # $1 label  $2 expected message  $3 source — the message must be the ONE error
    printf '%s' "$3" > "$D/r.cyr"
    rc=0
    cat "$D/r.cyr" | "$CC" > "$D/r.bin" 2>"$D/r.err" || rc=$?
    nrefuse=$((nrefuse+1))
    nerr=$(grep -c '^error' "$D/r.err" 2>/dev/null || true)
    if grep -q "$2" "$D/r.err" 2>/dev/null; then
        if [ -s "$D/r.bin" ]; then
            printf '  FAIL: %-46s reported but still emitted a binary\n' "$1"; fail=$((fail+1))
        elif [ "$nerr" != 1 ]; then
            printf '  FAIL: %-46s refused, then %s more error(s): %s\n' "$1" "$((nerr-1))" \
                "$(grep '^error' "$D/r.err" | sed -n 2p)"
            fail=$((fail+1))
        else
            printf '  ok(refused): %-40s\n' "$1"; pass=$((pass+1))
        fi
    else
        printf '  FAIL: %-46s not refused (rc=%s, first line: %s)\n' \
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
        printf '  FAIL: %-46s CONTROL gave %s, want %s — the expectation is wrong\n' "$1" "$ctl" "$3"
        fail=$((fail+1)); return
    fi
    if [ "$got" = "$3" ]; then
        printf '  ok(accepted): %-39s exit=%s (control %s)\n' "$1" "$got" "$ctl"; pass=$((pass+1))
    else
        printf '  FAIL: %-46s exit=%s, want %s (control %s): %s\n' "$1" "$got" "$3" "$ctl" \
            "$(grep '^error' "$D/a.err" 2>/dev/null | head -1)"
        fail=$((fail+1))
    fi
}

compiles() {  # $1 label  $2 source — accepted: no error, a binary written (its value is not the point)
    naccept=$((naccept+1))
    printf '%s' "$2" > "$D/c.cyr"
    rc=0
    cat "$D/c.cyr" | "$CC" > "$D/c.bin" 2>"$D/c.err" || rc=$?
    if [ "$rc" = 0 ] && [ -s "$D/c.bin" ] && ! grep -q '^error' "$D/c.err"; then
        printf '  ok(compiles): %-39s\n' "$1"; pass=$((pass+1))
    else
        printf '  FAIL: %-46s refused (rc=%s): %s\n' "$1" "$rc" "$(grep '^error' "$D/c.err" | head -1)"
        fail=$((fail+1))
    fi
}

T='struct Pt { x; y; }
struct Q { a; b; c; }
struct S1 { u; }
struct T1 { w; }
struct V2 { a; b; }
struct Box<T> { v: T; n; }
struct H { p: Pt; q: Q; t: T1; s: S1; }
fn mk1<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn mkp(): Pt { var p: Pt; p.x = 3; p.y = 4; return p; }
fn mkq(): Q { var q: Q; q.a = 1; q.b = 2; q.c = 7; return q; }
fn mkt1(): T1 { var t: T1; t.w = 9; return t; }
fn mks1(): S1 { var s: S1; s.u = 5; return s; }
fn bq(b: Q): i64 { return b.c; }
fn bqp(b: *Q): i64 { return b.c; }
fn bs(b: Box): i64 { return b.n; }
fn bi(b: Box<Pt>): i64 { return b.n; }
fn bs1(b: S1): i64 { return b.u; }
fn bs1p(b: *S1): i64 { return b.u; }
fn tt<T>(x: T, y: T): i64 { return y.y + 0; }
fn gx<T>(b: Box<T>): i64 { return b.n; }
impl Pt { fn dup(self): Pt { var r: Pt; r.x = self.x; r.y = self.y; return r; } }
impl Pt { fn takeq(self, b: Q): i64 { return b.c; } }
impl Pt { fn t1(self): T1 { var r: T1; r.w = self.x; return r; } }
impl Pt { fn s1(self): S1 { var r: S1; r.u = self.x; return r; } }
impl Pt { fn v2(self): V2 { var r: V2; r.a = self.x; r.b = self.y; return r; } }
impl Pt { fn mq(self): Q { var r: Q; r.a = self.x; r.b = self.y; r.c = 6; return r; } }
impl Q { fn cc(self): i64 { return self.c; } }
impl Q { fn cc2(self: Q): i64 { return self.c; } }
impl Q { fn useq(self, o: Q): i64 { return o.c; } }
fn Q_add(a: Q, b: Q): i64 { return a.a * 10 + b.c; }
fn S1_add(a: S1, b: S1): i64 { return a.u * 10 + b.u; }
'
PQ='var p: Pt; p.x = 3; p.y = 4; var q: Q; q.a = 1; q.b = 2; q.c = 7;'
TS='include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
'
P62='a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31, a32, a33, a34, a35, a36, a37, a38, a39, a40, a41, a42, a43, a44, a45, a46, a47, a48, a49, a50, a51, a52, a53, a54, a55, a56, a57, a58, a59, a60, a61'
A62='0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61'

echo "=== the two filed repros (roadmap, found at the 6.7.1 open) ==="
refuse "R1 bq(p), a Pt into b: Q" "cannot pass 'p' $MA 'bq'" \
    'struct Pt { x; y; }
struct Q { a; b; c; }
fn bq(b: Q) { return b.c; }
fn main() {
    var p: Pt;
    p.x = 3; p.y = 4;
    var r = bq(p);
    return r;
}
var rr = main();
syscall(60, rr);
'
refuse "R2 bs(mk1(p)), a Box<Pt> into b: Box" "cannot pass 'mk1' $MA 'bs'" \
    'struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn mk1<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn bs(b: Box) { return b.n; }
fn main() {
    var p: Pt;
    p.x = 3; p.y = 4;
    return bs(mk1(p));
}
var rr = main();
syscall(60, rr);
'

echo "=== names: locals, globals, captures, calls, method results (address-passed parameters) ==="
refuse "R3 a pointer-mode local" "cannot pass 'p' $MA 'bq'" \
    "include \"lib/alloc.cyr\"
${T}fn go(): i64 { var p: Pt = alloc(16); p.x = 3; p.y = 4; return bq(p); } syscall(60, go());"
refuse "R4a a \`u: *Pt\` local into b: *Q" "cannot pass 'u' $MA 'bqp'" \
    "${T}fn go(): i64 { ${PQ} var u: *Pt = &p; return bqp(u); } syscall(60, go());"
refuse "R4b a \`u: *Pt\` local into b: Q" "cannot pass 'u' $MA 'bq'" \
    "${T}fn go(): i64 { ${PQ} var u: *Pt = &p; return bq(u); } syscall(60, go());"
refuse "R4c a named Pt into b: *Q (implicit &)" "cannot pass 'p' $MA 'bqp'" \
    "${T}fn go(): i64 { ${PQ} return bqp(p); } syscall(60, go());"
refuse "R5 a global, in a fn" "cannot pass 'G' $MA 'bq'" \
    "${T}var G = Pt { 3, 4 }; fn go(): i64 { return bq(G); } syscall(60, go());"
refuse "R6 a global, at top level" "cannot pass 'P0' $MA 'bq'" \
    "${T}var P0 = Pt { 3, 4 }; var r0 = bq(P0); syscall(60, r0);"
refuse "R7 a closure capture" "cannot pass 'p' $MA 'bq'" \
    "include \"lib/fnptr.cyr\"
${T}fn go(): i64 { ${PQ} var f = || bq(p); return fncall0(f); } syscall(60, go());"
refuse "R8 a free call returning Pt" "cannot pass 'mkp' $MA 'bq'" \
    "${T}fn go(): i64 { return bq(mkp()); } syscall(60, go());"
refuse "R9 a method result (Pt_dup)" "cannot pass 'Pt_dup' $MA 'bq'" \
    "${T}fn go(): i64 { ${PQ} return bq(p.dup()); } syscall(60, go());"
refuse "R10 a method's ARGUMENT, p.takeq(r)" "cannot pass 'r' $MA 'Pt_takeq'" \
    "${T}fn go(): i64 { ${PQ} var r: Pt; return p.takeq(r); } syscall(60, go());"
refuse "R11 Q_cc(p), an untyped impl self" "cannot pass 'p' $MA 'Q_cc'" \
    "${T}fn go(): i64 { ${PQ} return Q_cc(p); } syscall(60, go());"
refuse "R12 Q_cc2(p), self: Q" "cannot pass 'p' $MA 'Q_cc2'" \
    "${T}fn go(): i64 { ${PQ} return Q_cc2(p); } syscall(60, go());"
refuse "R13a a tail call, by value (8 B)" "cannot pass 't' $MA 'bs1'" \
    "${T}fn f(t: T1): i64 { return bs1(t); } fn go(): i64 { var t: T1; t.w = 9; return f(t); } syscall(60, go());"
refuse "R13b a tail call, \`*Pt\` into b: *Q" "cannot pass 'u' $MA 'bqp'" \
    "${T}fn f(u: *Pt): i64 { return bqp(u); } fn go(): i64 { ${PQ} return f(&p); } syscall(60, go());"
refuse "R14 a forwarded by-value parameter" "cannot pass 'p' $MA 'bq'" \
    "${T}fn f(p: Pt): i64 { var r = bq(p); return r; } fn go(): i64 { ${PQ} return f(p); } syscall(60, go());"
refuse "R15 a callee defined AFTER the call (pass 1)" "cannot pass 'p' $MA 'later'" \
    "${T}fn go(): i64 { ${PQ} return later(p); } fn later(b: Q): i64 { return b.c; } syscall(60, go());"

echo "=== generics: an instance against its base, and the reverse ==="
refuse "R16 tt(p, q), T bound by p" "cannot pass 'q' $MA 'tt\$Pt'" \
    "${T}fn go(): i64 { ${PQ} return tt(p, q); } syscall(60, go());"
refuse "R17 a trait-bounded bb(p, q)" "cannot pass 'q' $MA 'bb\$Pt'" \
    "${T}trait Sh { fn sh(self): i64; }
impl Sh for Pt { fn sh(self): i64 { return self.y; } }
impl Sh for Q { fn sh(self): i64 { return self.c; } }
fn bb<T: Sh>(x: T, y: T): i64 { return y.sh(); }
fn go(): i64 { ${PQ} return bb(p, q); } syscall(60, go());"
refuse "R18 gx<Pt>(a Box<Q>)" "cannot pass 'bq2' $MA 'gx\$Pt'" \
    "${T}fn go(): i64 { ${PQ} var bq2: Box<Q> = mk1(q); return gx<Pt>(bq2); } syscall(60, go());"
# `gx(b)` does not infer T through `b: Box<T>`, so the BASE gx (T = i64, `b: Box`) is called with
# a Box<Pt>: it read b.n at the base's offset — 4 (b.v.y) where 8 is right. Refused like R19.
refuse "R18b gx(b), T not inferred: a Box<Pt> into the base" "cannot pass 'b' $MA 'gx'" \
    "${T}fn go(): i64 { ${PQ} var b: Box<Pt> = mk1(p); return gx(b); } syscall(60, go());"
refuse "R19 a Box<Pt> local into b: Box" "cannot pass 'b' $MA 'bs'" \
    "${T}fn go(): i64 { ${PQ} var b: Box<Pt> = mk1(p); return bs(b); } syscall(60, go());"
refuse "R20 a Box local into b: Box<Pt>" "cannot pass 'b' $MA 'bi'" \
    "${T}fn go(): i64 { var b: Box; b.v = 1; b.n = 8; return bi(b); } syscall(60, go());"

echo "=== a by-value struct of 8 B or less (no address bit: never reached the old arms) ==="
refuse "R21 bs1(t), a T1 local" "cannot pass 't' $MA 'bs1'" \
    "${T}fn go(): i64 { var t: T1; t.w = 9; return bs1(t); } syscall(60, go());"
refuse "R22 bs1(mkt1())" "cannot pass 'mkt1' $MA 'bs1'" \
    "${T}fn go(): i64 { return bs1(mkt1()); } syscall(60, go());"
refuse "R23 bs1(p.t1()), an 8 B method result" "cannot pass 'Pt_t1' $MA 'bs1'" \
    "${T}fn go(): i64 { ${PQ} return bs1(p.t1()); } syscall(60, go());"
refuse "R24 bs1(p.v2()), a 16 B method result" "cannot pass 'Pt_v2' $MA 'bs1'" \
    "${T}fn go(): i64 { ${PQ} return bs1(p.v2()); } syscall(60, go());"
refuse "R24b bs1(p.mq()), a 24 B method result" "cannot pass 'Pt_mq' $MA 'bs1'" \
    "${T}fn go(): i64 { ${PQ} return bs1(p.mq()); } syscall(60, go());"
refuse "R25 bs1(h.t), an 8 B field" "cannot pass 't' $MA 'bs1'" \
    "${T}fn go(): i64 { var h: H; h.t.w = 9; return bs1(h.t); } syscall(60, go());"
refuse "R26 bs1p(t), a T1 into b: *S1" "cannot pass 't' $MA 'bs1p'" \
    "${T}fn go(): i64 { var t: T1; t.w = 9; return bs1p(t); } syscall(60, go());"
refuse "R26b bs1(q), a Q into b: S1" "cannot pass 'q' $MA 'bs1'" \
    "${T}fn go(): i64 { ${PQ} return bs1(q); } syscall(60, go());"
refuse "R26c a T1 global, at top level" "cannot pass 'GT' $MA 'bs1'" \
    "${T}var GT = T1 { 9 }; var rr = bs1(GT); syscall(60, rr);"

echo "=== an operator's operands (parameters 0 and 1 of the operator fn) and a method's self ==="
refuse "R27 q + p with Q_add(a: Q, b: Q)" "cannot pass 'p' $MA 'Q_add'" \
    "${T}fn go(): i64 { ${PQ} return q + p; } syscall(60, go());"
refuse "R28 q + mkp()" "cannot pass 'mkp' $MA 'Q_add'" \
    "${T}fn go(): i64 { ${PQ} return q + mkp(); } syscall(60, go());"
refuse "R28b q + p.dup()" "cannot pass 'Pt_dup' $MA 'Q_add'" \
    "${T}fn go(): i64 { ${PQ} return q + p.dup(); } syscall(60, go());"
refuse "R29 q + (p)" "cannot pass 'p' $MA 'Q_add'" \
    "${T}fn go(): i64 { ${PQ} return q + (p); } syscall(60, go());"
refuse "R30 s + t with S1_add (8 B)" "cannot pass 't' $MA 'S1_add'" \
    "${T}fn go(): i64 { var s: S1; s.u = 1; var t: T1; t.w = 9; return s + t; } syscall(60, go());"
refuse "R31 the LEFT operand: Pt_add(a: Q, b: Pt)" "cannot pass 'p' $MA 'Pt_add'" \
    "${T}fn Pt_add(a: Q, b: Pt): i64 { return a.c; } fn go(): i64 { ${PQ} return p + p; } syscall(60, go());"
refuse "R32 the receiver: p.weird() with self: Q" "cannot pass 'p' $MA 'Pt_weird'" \
    "${T}impl Pt { fn weird(self: Q): i64 { return self.c; } } fn go(): i64 { ${PQ} return p.weird(); } syscall(60, go());"

echo "=== a Str handle, and a struct past the per-fn masks' width ==="
refuse "R33a a Str local into b: Q" "cannot pass 's' $MA 'bq'" \
    "${TS}${T}fn go(): i64 { var s = str_from(\"abc\"); return bq(s); } syscall(60, go());"
refuse "R33b a Pt into s: Str" "cannot pass 'p' $MA 'sl'" \
    "${TS}${T}fn sl(s: Str): i64 { return str_len(s); } fn go(): i64 { ${PQ} return sl(p); } syscall(60, go());"
refuse "R34a an address-passed struct at ordinal 62" "cannot pass 'p' $MA 'take62'" \
    "${T}fn take62(${P62}, b: Q): i64 { return b.c; } fn go(): i64 { ${PQ} return take62(${A62}, p); } syscall(60, go());"
refuse "R34b a by-value 8 B struct at ordinal 65" "cannot pass 't' $MA 'take65'" \
    "${T}fn take65(${P62}, b0, b1, b2, b: S1): i64 { return b.u; } fn go(): i64 { var t: T1; t.w = 9; return take65(${A62}, 0, 0, 0, t); } syscall(60, go());"

echo "=== the same shapes with the declared type (no false refusal) ==="
accept "A1 names, global, capture, field, call, method" \
    "include \"lib/alloc.cyr\"
${T}var GQ = Q { 1, 2, 3 };
fn f(b: Q): i64 { return bq(b); }
fn go(): i64 { ${PQ} var qp: Q = alloc(24); qp.c = 4; var u: *Q = &q; var h: H; h.q.c = 5;
  var g = || bq(q);
  return bq(q) + bq(qp) + bqp(u) + bqp(q) + bq(GQ) + fncall0(g) + bq(h.q) + bq(mkq()) + bq(p.mq()) + p.takeq(q) + Q_cc(q) + Q_cc2(q) + q.useq(q) + f(q); }
syscall(60, go());" \
    88 \
    "${T}fn go(): i64 { return 7 + 4 + 7 + 7 + 3 + 7 + 5 + 7 + 6 + 7 + 7 + 7 + 7 + 7; } syscall(60, go());"
accept "A2 generics: instance, explicit, bound, base" \
    "${T}fn go(): i64 { ${PQ} var r: Pt; r.x = 5; r.y = 6; var b: Box<Pt> = mk1(p); var c: Box; c.n = 9;
  return tt(p, r) + bi(b) + bi(mk1(p)) + gx<Pt>(b) + gx<Pt>(mk1(p)) + bs(c); }
syscall(60, go());" \
    47 \
    "${T}fn go(): i64 { return 6 + 8 + 8 + 8 + 8 + 9; } syscall(60, go());"
accept "A3 by value, 8 B: local, call, method, field, *S1" \
    "${T}fn f(s: S1): i64 { return bs1(s); }
fn go(): i64 { ${PQ} var s: S1; s.u = 2; var h: H; h.s.u = 4;
  return bs1(s) + bs1(mks1()) + bs1(p.s1()) + bs1(h.s) + bs1p(s) + f(s); }
syscall(60, go());" \
    18 \
    "${T}fn go(): i64 { return 2 + 5 + 3 + 4 + 2 + 2; } syscall(60, go());"
accept "A4 operators and a chain" \
    "${T}fn Q_mul(a: Q, k): i64 { return a.c * k; }
impl V2 { fn s1(self): S1 { var r: S1; r.u = self.a + self.b; return r; } }
fn go(): i64 { ${PQ} var r: Q; r.a = 2; r.b = 0; r.c = 6; var s: S1; s.u = 1; var s2: S1; s2.u = 3;
  return q + r + (q * 2) + (s + s2) + (s + mks1()) + bs1(p.v2().s1()); }
syscall(60, go());" \
    65 \
    "${T}fn go(): i64 { return 16 + 14 + 13 + 15 + 7; } syscall(60, go());"
accept "A5 the untyped boundary: &q, an untyped name, fncall" \
    "include \"lib/fnptr.cyr\"
${T}fn go(): i64 { ${PQ} var u = &q; return bq(u) + bqp(&q) + fncall1(&bq, &q); }
syscall(60, go());" \
    21 \
    "${T}fn go(): i64 { return 7 * 3; } syscall(60, go());"
compiles "A6 &p into b: *Q (an address expression)" \
    "${T}fn go(): i64 { ${PQ} return bqp(&p); } syscall(60, go());"
accept "A7 Str handles: a local, a call, an untyped name" \
    "${TS}${T}fn sl(s: Str): i64 { return str_len(s); }
fn go(): i64 { var s = str_from(\"abcd\"); var a: Q = alloc(24); a = str_from(\"xy\"); var u = a;
  return sl(s) + sl(str_from(\"abc\")) + sl(u); }
syscall(60, go());" \
    9 \
    "${T}fn go(): i64 { return 4 + 3 + 2; } syscall(60, go());"
accept "A8 the declared types past the masks' width" \
    "${T}fn take62(${P62}, b: Q): i64 { return b.c; } fn take65(${P62}, b0, b1, b2, b: S1): i64 { return b.u; }
fn go(): i64 { ${PQ} var s: S1; s.u = 5; return take62(${A62}, q) + take65(${A62}, 0, 0, 0, s); }
syscall(60, go());" \
    12 \
    "${T}fn go(): i64 { return 7 + 5; } syscall(60, go());"
accept "A9 a redefined fn: the call checks the LAST definition" \
    "${T}fn rf(p: S1): i64 { return p.u; }
fn go(): i64 { var t: T1; t.w = 9; return rf(t); }
fn rf(p: T1): i64 { return p.w + 1; }
syscall(60, go());" \
    10 \
    "${T}fn go(): i64 { return 9 + 1; } syscall(60, go());"

echo "  $pass passed, $fail failed ($nrefuse refusal rows, $naccept acceptance rows)"
[ "$fail" -eq 0 ]
