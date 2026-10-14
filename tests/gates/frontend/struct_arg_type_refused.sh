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
#   `gx(b)`, b: Box<Pt>, `fn gx<T>(b: Box<T>)`          -> 4 where 8 is right (T was not inferred
#                                                          through Box<T>: the BASE gx ran; refused
#                                                          here 6.7.3 - 6.7.7, inferred since 6.7.8: R18b)
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
#   base 6.7.3 build/cycc                              -> RED, all 41 refusal rows (compiled clean)
#   `_sarg_type_err` always returns 0                  -> RED, all 41 refusal rows
#   the local arm's `_sarg_type_err` dropped           -> RED R1 R3 R4c R10 R11 R12 R14 R15 R16 R17 R18 R18b R19 R20 R26 R33a R34a (re-measured 2026-10-08;
#                                                         R18b is an acceptance row since 6.7.8)
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
#   real tree                                          -> GREEN (41 refusal rows, 12 acceptance rows — R4a R4b R13b accept a typed pointer since the user's decision of 2026-10-08)
#
# 6.7.8 — T IS INFERRED THROUGH A GENERIC STRUCT PARAMETER (`_gs_carrier`, parse_fn.cyr):
# R18b `gx(b)` flips from a refusal to an acceptance (exit 8, control `gx<Pt>(b)`). What stays: an
# `x: T` parameter binds T before the struct carrier does (R18c — the literal's i64, so the
# Box<Pt> is still refused against the base) and a nested `Box<Pair<T>>` binds nothing (R18d). The
# `*Box<T>` carrier's pointer forms are tests/tcyr/crossos/generic_struct_inference.tcyr G8. The
# filed repro is R18f, verbatim. Mutations (scratch tree, measured):
#   `_gs_carrier` records nothing                      -> RED R18b R18f
#   the struct carrier asked before an `x: T` one      -> RED R18c (compiles)
#   real tree                                          -> GREEN (42 refusal rows, 15 acceptance rows)
#
# 6.7.9 — A POINTER INTO A BY-VALUE `b: Box<T>` BINDS T FROM ITS POINTEE (`_gsc_arg`, the user's
# decision 2(b)). 6.7.8 bound nothing for it: the i64 base ran, reading `b.n` at Box<i64>'s offset
# (b.v.y: 4 for 8), silently — R18e pinned that at 4. Now `gx(bp)`, `gx(&b)`, a `*Box<Pt>`
# parameter and a `*Box<Pt>`-returning call call `gx$Pt`, as `gx<Pt>(..)` does: R18e flips to 8,
# R18g (the other three, 888 - 800), R18h the filed repro verbatim (248; 128 before). Every other
# pointer form (a field chain, a `*Box<Pt>` global, `&G`, `&b` of a by-value parameter, a `: T`
# return, `Box<i32>`, a stub base, the pair scans) is generic_struct_inference.tcyr G10.
#   the fix reverted (the 6.7.9 tree before it)        -> RED R18e (4) R18g (156) R18h (128)
#   real tree                                          -> GREEN (42 refusal rows, 17 acceptance rows)
#
# 6.7.10 (B7-1b) — A POINTER INTO A BY-VALUE STRUCT PARAMETER OF 8 B OR LESS PASSES THE STRUCT IT POINTS
# AT (the user's decision 7, 2026-10-12), as over 8 B, where that parameter is address-passed: the
# accepted `&p` / `*T` argument was pushed AS the struct's one word, so the callee read the pointer's
# bits (issues/archived/2026-10-11-typed-pointer-into-small-byvalue-struct-param.md, exit 0 where 111 is right).
# B1 is that repro verbatim, B2-B4 the forms it names (a `*S1` local, `&s`, a `*S1` parameter, a call
# returning one, a generic instance, another struct's `*T1`); B5 pins the boundary (an untyped value is
# the word). The type check is unchanged — no new refusal. Every other form, consumer, size and target:
# tests/tcyr/crossos/small_struct_pointer_arg.tcyr, run by tests/gates/codegen/small_struct_handle_line.sh
# R3 / R4 / PP (its mutation ledger MB1..MB9).
#   the B7-1g compiler (f72166c0)                     -> RED B1 (0) B2 B3 B4 (the pointers' bits)
#   real tree                                          -> GREEN (42 refusal rows, 22 acceptance rows)
#
# 6.7.11 — PARENTHESES WRAPPING A WHOLE ARGUMENT INTO A BY-VALUE STRUCT OF 8 B OR LESS ARE TRANSPARENT
# to the type check (`_expr_struct_sid` / `_ess_wrap`, the user's decision 2026-10-13: refuse by name):
# `bs1((t))` compiled and exited 7 (T1's word read as an S1) through 6.7.10, where `bs1(t)` and every
# wrapped spelling over 8 B were refused (issues/2026-10-08-paren-arg-small-byval-struct-skips-type-check.md).
# W1 is the filed repro verbatim; W2-W9 the wrapped name / call / field / global / tail / method-argument
# spellings; W10 the declared type wrapped (no false refusal); W11 an expression in parentheses stays a
# value; W12 / W13 a tuple literal is not a wrap of its first element. Mutations (each a one-change
# copy of the fixed src built by the fixed compiler; measured):
#   the fix reverted (A2's compiler)                   -> RED W1-W9 (each compiled, exit 7 / 9)
#   `_fpk_want` armed at the wrap, not inside it       -> RED W5 W6
#   the wrapped-name arm dropped                       -> RED W1 W2 W7 W8 W9
#   the wrapped-call arm dropped                       -> RED W3 W4
#   `_ess_call` without the innermost-`)` span check   -> RED W12 (a second error naming 'mkt1')
#   the wrapped name also taken before a `,`           -> RED W13 (a second error naming 't')
#   real tree                                          -> GREEN (53 refusal rows, 24 acceptance rows)
#
# 6.7.11 — A WHOLE DEREFERENCE OF ANOTHER STRUCT'S POINTER INTO A BY-VALUE STRUCT OF 8 B OR LESS IS REFUSED
# BY NAME (`_ess_deref`, the user's decision 2026-10-13: refuse by name; `*p` is a struct value at every
# size, 6.7.10 decision 6): `take8(*pu)` with `pu: *U8` into `s: S8` compiled and exited 7 through 6.7.10,
# where `take8(u)`, the 16 B `take(*pu)` and `var l: S8 = *pu;` were refused
# (issues/2026-10-13-dereference-of-other-struct-into-small-byvalue-param-decision.md). D1 is the filed
# repro verbatim; D2-D9 wrapped, a `: *T` call (named by its last name, as `_dro_check` names it over 8 B),
# a `*T` field, pointer arithmetic, a tail call, `*self` and a `Str` parameter (139 before); D9 a generic
# carrier of the SAME instance binds T through the dereference (the review fix below); D10 the same struct
# (no false refusal); D11 the pointer itself and an untyped `*x`; D12 an operator on the dereference is not
# one. Mutations:
#   the fix reverted (the paren commit's compiler)     -> RED D1-D8 D3b (each compiled)
#   no unwrap (`_ie_unparen`)                          -> RED D2
#   the operand's last name not scanned                -> RED D3 D4 D5 (named 'gt' / 'hp' / a stray token)
#   no whole-dereference test (`_gz_split`)            -> RED D12 (`*tp + 1` refused as `tp`)
#   real tree                                          -> GREEN (63 refusal rows, 27 acceptance rows)
#
# 6.7.11 (the lane's review) — THE TWO SPELLINGS ABOVE BIND A GENERIC CARRIER'S T AS THEIR PLAIN ONES DO
# (`_gsc_wrap` / `_gsc_deref`, out of `_gsc_arg`): the struct-carrier inference read neither a whole-argument
# wrap nor `* E`, so `gw((w))`, `gw((mkw(6)))` and `gw(*wp)` with `fn gw<T>(w: W1<T>)`, `w: W1<i32>` reached
# the BASE (`w: W1`) — refused "a different struct type" by the two bites above (through 6.7.10 at 8 B or less
# they compiled and read W1<i32> with the base's layout: `w.v = -6` tested >= 0), and over 8 B `gx((b))` /
# `gx(*bp)` were refused so since 6.7.6 / 6.7.10 — where `gw(w)`, `gw(mkw(6))` and `gw(wp)` call `gw$i32`.
# D9 (flipped from a refusal) and G1-G2 accept with the instance's layout (a negative i32 tested < 0); G3 / G4
# a wrapped / dereferenced struct of ANOTHER type stays refused; G5 a tuple literal binds nothing (the
# refusal names the base). The pair scans' half (`_tok_gen_sc_sid`: a `?` above a wrapper typed through
# either spelling) is tests/tcyr/crossos/generic_struct_inference.tcyr G11 (MG12 there: rc 139).
# Mutations (each a one-change copy of the fixed src built by the fixed compiler; measured 2026-10-14):
#   `_gsc_arg` without its `(` arm (`_gsc_wrap`)       -> RED D9 G1 G2 (refused: a different struct type)
#   `_gsc_arg` without its `*` arm (`_gsc_deref`)      -> RED D9 G2 (refused: a different struct type)
#   `_pwrap_in` without its tuple test                 -> RED G5 (the refusal names 'gx$Pt')
#   `_gsc_deref` without its `_gz_split` test          -> no row: an operator on a generic instance's value
#                                                          dispatches `W1$i32_add`, which no source defines, so
#                                                          `gw(*wp + 1)` is refused either way; the test keeps
#                                                          `*wp + 1` from being read as `*(wp + 1)`
#   real tree                                          -> GREEN (65 refusal rows, 30 acceptance rows)
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
# A typed POINTER converts freely, as `&p` and the receive path do (the user's decision, 2026-10-08).
compiles "R4a a \`u: *Pt\` local into b: *Q (a typed pointer: accepted)" \
    "${T}fn go(): i64 { ${PQ} var u: *Pt = &p; return bqp(u); } syscall(60, go());"
compiles "R4b a \`u: *Pt\` local into b: Q (a typed pointer: accepted)" \
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
compiles "R13b a tail call, \`*Pt\` into b: *Q (a typed pointer: accepted)" \
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
# `gx(b)` did not infer T through `b: Box<T>`, so the BASE gx (T = i64, `b: Box`) was called with
# a Box<Pt> and read b.n at the base's offset — 4 (b.v.y) where 8 is right; refused here 6.7.3 -
# 6.7.7. Since 6.7.8 T is inferred through the struct carrier: `gx$Pt`, as `gx<Pt>(b)`.
accept "R18b gx(b), T inferred through Box<T> (6.7.8)" \
    "${T}fn go(): i64 { ${PQ} var b: Box<Pt> = mk1(p); return gx(b); } syscall(60, go());" \
    8 \
    "${T}fn go(): i64 { ${PQ} var b: Box<Pt> = mk1(p); return gx<Pt>(b); } syscall(60, go());"
# An `x: T` parameter binds T before a struct carrier does (6.7.8: what compiled keeps its meaning):
# the literal binds i64, the base takes `b: Box`, and the Box<Pt> is refused as before.
refuse "R18c g4(b, 7): an x: T parameter binds T first" "cannot pass 'b' $MA 'g4'" \
    "${T}fn g4<T>(b: Box<T>, x: T): i64 { return b.n; } fn go(): i64 { ${PQ} var b: Box<Pt> = mk1(p); return g4(b, 7); } syscall(60, go());"
# T nested a level deeper binds nothing — the base, refused (write `gn<Pt>(b)`).
refuse "R18d gn(b), T nested in Box<Pair<T>>" "cannot pass 'b' $MA 'gn'" \
    "${T}struct Pair<U> { a: U; b: U; } fn gn<T>(b: Box<Pair<T>>): i64 { return b.n; } fn go(): i64 { var b: Box<Pair<Pt>>; b.n = 8; return gn(b); } syscall(60, go());"
# A POINTER passed to a by-value `b: Box<T>` binds T from what it points at (6.7.9, the user's
# decision 2(b)): the parameter is address-passed, so `gx$Pt` receives the same address the base
# did — and reads it with Box<Pt>'s layout. 6.6.10 - 6.7.8 bound nothing: the i64 base read `b.n`
# at Box<i64>'s offset, b.v.y (4 for 8), silently.
accept "R18e a *Box<Pt> local into b: Box<T> binds Pt (6.7.9; was 4)" \
    "${T}fn go(): i64 { ${PQ} var b: Box<Pt> = mk1(p); var bp: *Box<Pt> = &b; return gx(bp); } syscall(60, go());" \
    8 \
    "${T}fn go(): i64 { ${PQ} var b: Box<Pt> = mk1(p); var bp: *Box<Pt> = &b; return gx<Pt>(bp); } syscall(60, go());"
accept "R18g &b, a *Box<Pt> parameter and a *Box<Pt>-returning call (6.7.9; was 444)" \
    "${T}fn pid(bp: *Box<Pt>): *Box<Pt> { return bp; } fn vp(bp: *Box<Pt>): i64 { return gx(bp); }
fn go(): i64 { ${PQ} var b: Box<Pt> = mk1(p); return gx(&b) * 100 + vp(&b) * 10 + gx(pid(&b)); } syscall(60, go() - 800);" \
    88 \
    "${T}fn pid(bp: *Box<Pt>): *Box<Pt> { return bp; } fn vp(bp: *Box<Pt>): i64 { return gx<Pt>(bp); }
fn go(): i64 { ${PQ} var b: Box<Pt> = mk1(p); return gx<Pt>(&b) * 100 + vp(&b) * 10 + gx<Pt>(pid(&b)); } syscall(60, go() - 800);"
# The filed repro, verbatim (issues/archived/2026-10-08-generic-inference-through-generic-struct-param.md).
RP="docs/development/issues/repros/2026-10-08-generic-inference-through-generic-struct-param.cyr"
accept "R18f the filed repro, verbatim" "$(cat "$RP")" 8 "$(sed 's/gx(b)/gx<Pt>(b)/' "$RP")"
# The 6.7.9 filed repro, verbatim (issues/2026-10-10-pointer-into-byvalue-generic-carrier-runs-base.md):
# `gx(&b)`, a `*Box<Pt>` local and a `*Box<Pt>` parameter — 128 before (each read 4).
RP2="docs/development/issues/repros/2026-10-10-pointer-into-byvalue-generic-carrier-runs-base.cyr"
accept "R18h the 6.7.9 filed repro, verbatim (was 128)" "$(cat "$RP2")" 248 "$(sed 's/ gx(/ gx<Pt>(/g' "$RP2")"
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

echo "=== 6.7.10 (B7-1b): a pointer into a by-value struct of 8 B or less passes the struct it points at ==="
# The filed repro, verbatim (docs/development/issues/archived/2026-10-11-typed-pointer-into-small-byvalue-struct-param.md):
# exit 0 through 6.7.9 — each callee read the pointer's bits as its struct. The control passes the structs.
RPB='include "lib/syscalls.cyr"
struct S1 { u; }
struct S4 { a: i32; }
fn bs1(b: S1): i64 { return b.u; }
fn bs4(b: S4): i64 { return b.a; }
fn go(): i64 {
    var s: S1; s.u = 5;
    var t: S4; t.a = 6;
    var sp: *S1 = &s;
    var tp: *S4 = &t;
    var r = 0;
    if (bs1(sp) == 5) { r = r + 1; }      # a `*S1` local into `b: S1` (8 B, passed by value)
    if (bs4(tp) == 6) { r = r + 10; }     # a `*S4` local into `b: S4` (4 B)
    if (bs1(&s) == 5) { r = r + 100; }    # `&s` into `b: S1`
    return r;
}
syscall(60, go());
'
accept "B1 the filed repro, verbatim (was 0)" "$RPB" 111 \
    "$(printf '%s' "$RPB" | sed 's/bs1(sp)/bs1(s)/; s/bs4(tp)/bs4(t)/; s/bs1(&s)/bs1(s)/')"
# The rows the filing asks for: a `*S1` local, `&s`, a `*S1` parameter, a call returning one, a
# generic instance — each the struct it points at (the control copies through the receive path).
accept "B2 a *S1 local, &s, a *S1 parameter, a *S1-returning call (was 0)" \
    "${T}fn sid(u: *S1): *S1 { return u; } fn vp(u: *S1): i64 { var r = bs1(u); return r; }
fn go(): i64 { var s: S1; s.u = 5; var sp: *S1 = &s; return bs1(sp) * 1000 + bs1(&s) * 100 + vp(&s) * 10 + bs1(sid(&s)); } syscall(60, go() - 5400);" \
    155 \
    "${T}fn go(): i64 { var s: S1; s.u = 5; var sp: *S1 = &s; var c: S1 = sp; return bs1(c) * 1000 + bs1(c) * 100 + bs1(c) * 10 + bs1(c); } syscall(60, go() - 5400);"
accept "B3 a generic instance: gw(wp), gw<i32>(wp) into w: W1<T> (was 0)" \
    "struct W1<T> { v: T; } fn gw<T>(w: W1<T>): i64 { return w.v; }
fn go(): i64 { var w: W1<i32>; w.v = 6; var wp: *W1<i32> = &w; return gw(wp) * 10 + gw<i32>(wp); } syscall(60, go());" \
    66 \
    "struct W1<T> { v: T; } fn gw<T>(w: W1<T>): i64 { return w.v; }
fn go(): i64 { var w: W1<i32>; w.v = 6; return gw(w) * 10 + gw<i32>(w); } syscall(60, go());"
# A typed pointer of ANOTHER struct converts, as over 8 B (6.7.3, the user's decision of 2026-10-08):
# its bytes are read with the parameter's layout.
accept "B4 a *T1 into b: S1 is read as an S1, as over 8 B" \
    "${T}fn go(): i64 { var t: T1; t.w = 9; var tp: *T1 = &t; return bs1(tp) * 10 + bs1(&t); } syscall(60, go());" \
    99 \
    "${T}fn go(): i64 { var s: S1; s.u = 9; return bs1(s) * 10 + bs1(s); } syscall(60, go());"
# An UNTYPED value is still the struct's word — only a typed pointer or `&x` is copied through.
accept "B5 the untyped boundary: an untyped local holding &s is its word" \
    "${T}fn go(): i64 { var s: S1; s.u = 5; var u = &s; if (bs1(u) == u) { return 7; } return 1; } syscall(60, go());" \
    7 \
    "${T}fn go(): i64 { var s: S1; s.u = 5; var u = &s; var c: S1; c.u = u; if (bs1(c) == u) { return 7; } return 1; } syscall(60, go());"

echo "=== 6.7.11: parentheses wrapping a whole argument into a by-value struct of 8 B or less ==="
# The filed repro, verbatim (issues/2026-10-08-paren-arg-small-byval-struct-skips-type-check.md): it
# compiled and exited 7 (T1's word read as an S1) through 6.7.10, where `bs1(t)` was refused.
refuse "W1 the filed repro, verbatim: bs1((t))" "cannot pass 't' $MA 'bs1'" \
    'struct S1 { v; }
struct T1 { w; }
fn bs1(p: S1): i64 { return p.v; }
fn main(): i64 { var t: T1 = T1 { 7 }; return bs1((t)); }
syscall(60, main());
'
refuse "W2 bs1(((t)))" "cannot pass 't' $MA 'bs1'" \
    "${T}fn go(): i64 { var t: T1; t.w = 9; return bs1(((t))); } syscall(60, go());"
refuse "W3 bs1((mkt1()))" "cannot pass 'mkt1' $MA 'bs1'" \
    "${T}fn go(): i64 { return bs1((mkt1())); } syscall(60, go());"
refuse "W4 bs1(((mkt1())))" "cannot pass 'mkt1' $MA 'bs1'" \
    "${T}fn go(): i64 { return bs1(((mkt1()))); } syscall(60, go());"
refuse "W5 bs1((h.t)), an 8 B field" "cannot pass 't' $MA 'bs1'" \
    "${T}fn go(): i64 { var h: H; h.t.w = 9; return bs1((h.t)); } syscall(60, go());"
refuse "W6 bs1(((h.t)))" "cannot pass 't' $MA 'bs1'" \
    "${T}fn go(): i64 { var h: H; h.t.w = 9; return bs1(((h.t))); } syscall(60, go());"
refuse "W7 a T1 global, wrapped, at top level" "cannot pass 'GT' $MA 'bs1'" \
    "${T}var GT = T1 { 9 }; var rr = bs1((GT)); syscall(60, rr);"
refuse "W8 a tail call, wrapped" "cannot pass 't' $MA 'bs1'" \
    "${T}fn f(t: T1): i64 { return bs1((t)); } fn go(): i64 { var t: T1; t.w = 9; return f(t); } syscall(60, go());"
refuse "W9 a method's argument, wrapped" "cannot pass 't' $MA 'Pt_sk'" \
    "${T}impl Pt { fn sk(self, b: S1): i64 { return b.u; } } fn go(): i64 { ${PQ} var t: T1; t.w = 9; return p.sk((t)); } syscall(60, go());"
accept "W10 the declared type, wrapped: a local, a call, a field, a method result" \
    "${T}fn go(): i64 { ${PQ} var s: S1; s.u = 2; var h: H; h.s.u = 4;
  return bs1((s)) + bs1(((s))) + bs1((mks1())) + bs1(((mks1()))) + bs1((h.s)) + bs1((p.s1())); }
syscall(60, go());" \
    21 \
    "${T}fn go(): i64 { return 2 + 2 + 5 + 5 + 4 + 3; } syscall(60, go());"
# Not a wrap of the whole argument: an expression, as without the parentheses (an untyped word).
accept "W11 (t.w), (mkt1().w), (x) + 1: values, not wrapped struct sources" \
    "${T}fn go(): i64 { var t: T1; t.w = 9; var x = 1; return bs1((t.w)) + bs1((mkt1().w)) + bs1((x) + 1); }
syscall(60, go());" \
    20 \
    "${T}fn go(): i64 { return 9 + 9 + 2; } syscall(60, go());"
# A tuple literal is not a wrap of its first element: the literal's own refusal, once, nothing more.
refuse "W12 bs1((mkt1(), 3)): the tuple literal's refusal only" "a tuple \`( .. )\` is a value only" \
    "${T}fn go(): i64 { return bs1((mkt1(), 3)); } syscall(60, go());"
refuse "W13 bs1((t, 3)): the tuple literal's refusal only" "a tuple \`( .. )\` is a value only" \
    "${T}fn go(): i64 { var t: T1; t.w = 9; return bs1((t, 3)); } syscall(60, go());"

echo "=== 6.7.11: a whole dereference of another struct's pointer into a by-value struct of 8 B or less ==="
GW='struct W1<T> { v: T; }
fn gw<T>(w: W1<T>): i64 { if (w.v < 0) { return 1; } return 2; }
fn mkw(a): W1<i32> { var r: W1<i32>; r.v = a; return r; }
'
# The filed repro, verbatim (issues/2026-10-13-dereference-of-other-struct-into-small-byvalue-param-decision.md):
# it compiled and exited 7 (U8's `u` read as an S8) through 6.7.10, where `take8(u)`, the 16 B `take(*pu)`
# and `var l: S8 = *pu;` were refused by name.
refuse "D1 the filed repro, verbatim: take8(*pu)" "cannot pass 'pu' $MA 'take8'" \
    'struct S8 { v; }
struct U8 { u; }
fn take8(s: S8): i64 { return s.v; }
fn main(): i64 { var u: U8; u.u = 7; var pu: *U8 = &u; return take8(*pu); }
syscall(60, main());
'
DH='struct HP { pt: *T1; ps: *S1; }
fn gt(t: *T1): *T1 { return t; }
fn gs(s: *S1): *S1 { return s; }
'
refuse "D2 bs1((*tp))" "cannot pass 'tp' $MA 'bs1'" \
    "${T}${DH}fn go(): i64 { var t: T1; t.w = 9; var tp: *T1 = &t; return bs1((*tp)); } syscall(60, go());"
refuse "D3 bs1(*gt(&t)), a : *T1 call" "cannot pass 't' $MA 'bs1'" \
    "${T}${DH}fn go(): i64 { var t: T1; t.w = 9; return bs1(*gt(&t)); } syscall(60, go());"
refuse "D3b bs1(*gtg()), a : *T1 call with no argument" "cannot pass 'gtg' $MA 'bs1'" \
    "${T}${DH}var GTP: *T1 = 0; fn gtg(): *T1 { return GTP; } fn go(): i64 { var t: T1; t.w = 9; GTP = &t; return bs1(*gtg()); } syscall(60, go());"
refuse "D4 bs1(*hp.pt), a *T1 field" "cannot pass 'pt' $MA 'bs1'" \
    "${T}${DH}fn go(): i64 { var t: T1; t.w = 9; var hp: HP; hp.pt = &t; return bs1(*hp.pt); } syscall(60, go());"
refuse "D5 bs1(*(tp + 0)), pointer arithmetic" "cannot pass 'tp' $MA 'bs1'" \
    "${T}${DH}fn go(): i64 { var t: T1; t.w = 9; var tp: *T1 = &t; return bs1(*(tp + 0)); } syscall(60, go());"
refuse "D6 a tail call, bs1(*tp) with tp: *T1 a parameter" "cannot pass 'tp' $MA 'bs1'" \
    "${T}${DH}fn f(tp: *T1): i64 { return bs1(*tp); } fn go(): i64 { var t: T1; t.w = 9; return f(&t); } syscall(60, go());"
refuse "D7 bs1(*self) in an impl of T1" "cannot pass 'self' $MA 'bs1'" \
    "${T}${DH}impl T1 { fn tk(self): i64 { return bs1(*self); } } fn go(): i64 { var t: T1; t.w = 9; return t.tk(); } syscall(60, go());"
# Into a `Str` handle parameter (any size of the pointee): it SIGSEGV'd (139) through 6.7.10, as `sl(p)` did before 6.7.3.
refuse "D8 sl(*tp) into s: Str" "cannot pass 'tp' $MA 'sl'" \
    "${TS}${T}${DH}fn sl(s: Str): i64 { return str_len(s); } fn go(): i64 { var t: T1; t.w = 9; var tp: *T1 = &t; return sl(*tp); } syscall(60, go());"
# A generic carrier of the same instance: `*wp` binds T as `wp` does (the lane's review), so `gw$i32` reads
# the i32 -6 as negative — the base read W1<i32>'s word with W1<i64>'s layout (>= 0: 2, through 6.7.10).
accept "D9 gw(*wp) / gw((*wp)) bind T = i32 through the dereference, as gw(wp) does" \
    "${GW}fn go(): i64 { var w: W1<i32>; w.v = 0 - 6; var wp: *W1<i32> = &w; return gw(*wp) * 10 + gw((*wp)); } syscall(60, go());" \
    11 \
    "${GW}fn go(): i64 { var w: W1<i32>; w.v = 0 - 6; var wp: *W1<i32> = &w; return gw(wp) * 10 + gw(w); } syscall(60, go());"
accept "D10 the same struct: *sp, (*sp), *gs(&s), *hp.ps, *self, gw<i32>(*wp)" \
    "${T}${DH}struct W1<T> { v: T; } fn gw<T>(w: W1<T>): i64 { return w.v; }
impl S1 { fn tk(self): i64 { return bs1(*self); } }
fn go(): i64 { var s: S1; s.u = 2; var sp: *S1 = &s; var hp: HP; hp.ps = &s; var w: W1<i32>; w.v = 6; var wp: *W1<i32> = &w;
  return bs1(*sp) + bs1((*sp)) + bs1(*gs(&s)) + bs1(*hp.ps) + s.tk() + gw<i32>(*wp); }
syscall(60, go());" \
    16 \
    "${T}fn go(): i64 { return 2 + 2 + 2 + 2 + 2 + 6; } syscall(60, go());"
# The pointer itself still converts (the user's decision, 2026-10-08); an untyped `*x` is the word it reads.
accept "D11 bs1(tp) with tp: *T1 converts; bs1(*x) with x untyped is its word" \
    "${T}fn go(): i64 { var t: T1; t.w = 9; var tp: *T1 = &t; var x = &t; return bs1(tp) * 10 + bs1(*x); } syscall(60, go());" \
    99 \
    "${T}fn go(): i64 { var s: S1; s.u = 9; return bs1(s) * 10 + bs1(s); } syscall(60, go());"
# Not one whole dereference: an operator on it is its operator fn's result (6.7.10, decision 11), an i64 here.
accept "D12 bs1(*tp + 1) with T1_add returning i64: a value" \
    "${T}fn T1_add(a: T1, b): i64 { return a.w + b; } fn go(): i64 { var t: T1; t.w = 9; var tp: *T1 = &t; return bs1(*tp + 1); } syscall(60, go());" \
    10 \
    "${T}fn go(): i64 { var s: S1; s.u = 10; return bs1(s); } syscall(60, go());"

echo "=== 6.7.11 (review): a wrapped or dereferenced argument binds a generic carrier's T ==="
# `gw((w))` and `gw((mkw(-6)))` call `gw$i32`, as `gw(w)` / `gw(mkw(-6))` do: the i32 -6 tests negative.
accept "G1 gw((w)), gw(((w))), gw((mkw(-6))), gw((GW)) bind T = i32" \
    "${GW}var GW: W1<i32> = W1<i32> { 0 };
fn go(): i64 { GW.v = 0 - 6; var w: W1<i32>; w.v = 0 - 6; return gw((w)) + gw(((w))) * 10 + gw((mkw(0 - 6))) * 100 + gw((GW)) * 1000 - 1000; } syscall(60, go());" \
    111 \
    "${GW}var GW: W1<i32> = W1<i32> { 0 };
fn go(): i64 { GW.v = 0 - 6; var w: W1<i32>; w.v = 0 - 6; return gw(w) + gw(w) * 10 + gw(mkw(0 - 6)) * 100 + gw(GW) * 1000 - 1000; } syscall(60, go());"
GB='var GB: Box<Pt> = Box<Pt> { 0, 0, 0 };
fn gpb(): *Box<Pt> { return &GB; }
fn gxp<T>(b: *Box<T>): i64 { return b.n; }
'
# Over 8 B (an address-passed carrier): refused through the base since 6.7.6 (wrapped) / 6.7.10 (`*bp`).
accept "G2 gx((b)), gx(*bp), gx((*bp)), gx(*gpb()), gxp((b)) bind T = Pt" \
    "${T}${GB}fn go(): i64 { GB.n = 8; var b: Box<Pt>; b.n = 8; var bp: *Box<Pt> = &b; return gx((b)) + gx(*bp) + gx((*bp)) + gx(*gpb()) + gxp((b)); } syscall(60, go());" \
    40 \
    "${T}${GB}fn go(): i64 { GB.n = 8; var b: Box<Pt>; b.n = 8; var bp: *Box<Pt> = &b; return gx(b) + gx(bp) + gx(&b) + gx(gpb()) + gxp(&b); } syscall(60, go());"
# Another struct, wrapped or dereferenced, binds nothing: the base meets it and refuses it by name.
refuse "G3 gw((t)) with t: T1" "cannot pass 't' $MA 'gw'" \
    "${T}${GW}fn go(): i64 { var t: T1; t.w = 7; return gw((t)); } syscall(60, go());"
refuse "G4 gw(*tp) with tp: *T1" "cannot pass 'tp' $MA 'gw'" \
    "${T}${GW}fn go(): i64 { var t: T1; t.w = 7; var tp: *T1 = &t; return gw(*tp); } syscall(60, go());"
# A tuple literal is not a wrap of its first element: no T from `b`, the literal's refusal names the base.
refuse "G5 gx((b, 3)): the tuple literal's refusal, naming the base" "this parameter of 'gx' is not a tuple" \
    "${T}fn go(): i64 { var b: Box<Pt>; b.n = 8; return gx((b, 3)); } syscall(60, go());"

echo "  $pass passed, $fail failed ($nrefuse refusal rows, $naccept acceptance rows)"
[ "$fail" -eq 0 ]
