#!/bin/sh
# Gate: copying between two DIFFERENT struct (or vector) types is refused (6.6.6).
#
# THE DEFECT (measured at 6.6.5 and at this lane's parent, x86_64 Linux, NO diagnostic):
#
#     struct P3{x;y;z;} struct Q3{a;b;c;}
#     var p: P3 = mk3(1,2,3);  var q: Q3 = mkq(7,8,9);
#     p = q;        syscall(60, p.z);      -> exit 3, and p.x had silently become 7
#     var p: P3 = q;                       -> p.x read 139 (q's ADDRESS, stored into a
#                                             slot the compiler marks struct-typed)
#
# ROOT CAUSE. Both copy paths — `_try_aggregate_copy_assign` (src/frontend/parse.cyr) and
# `_try_struct_copy_init` (src/frontend/parse_decl.cyr) — answered a type mismatch with
# `return 0`, which falls through to the generic 8-byte store. Neither reported anything.
# The LITERAL form (`var p: P3 = Q3{..}`) has been a hard error since 6.6.5; these two were
# the same rule with nothing behind it. Fixed by `_AGG_ASSIGN_TYPE_ERR` (src/common/util.cyr),
# called from all three bail sites (local source, global source, assignment).
#
# ⚠ A SOURCE WITH NO AGGREGATE TYPE STILL FALLS THROUGH. That is the deliberate pointer-bind
# path ("the C semantics of `P *b = a`", CHANGELOG [6.6.5]) and row A4 pins it, so a future
# tightening cannot quietly take it out. Row A7 pins that a SCALAR source keeps its existing
# warning rather than becoming an error — a different rule, deliberately untouched here.
#
# EXPECTED VALUES. Refusal rows are checked on the MESSAGE, not just on a non-zero exit, so a
# row cannot pass on an unrelated syntax error. Acceptance rows are checked twice: against the
# literal exit code written next to them, and against a CONTROL program that performs the same
# copy FIELD BY FIELD (a different construct, compiled by the same compiler) — so a row cannot
# pass by both sides sharing one defect.
#
# MUTATION LEDGER (6.6.6 — each mutant is a scratch tree from `git archive HEAD` with the one
# call site reverted, rebuilt with build/cycc; ledger measured on the fixed tree):
#   m1 all three call sites reverted to a bare `return 0`  -> RED, 9 of 9 refusal rows
#   m2 assignment site only (parse.cyr)                    -> RED rows R1 R3 R5 R7 R9
#   m3 declaration local-source site only (parse_decl.cyr) -> RED rows R2 R6 R8
#   m4 declaration global-source site only                 -> RED row R4
#   real tree                                              -> GREEN (9 refusals, 7 acceptances)
#
# 6.7.11 — A TYPED `*S` GLOBAL AS THE DESTINATION OF A STRUCT VALUE (the user's decision (a), 2026-10-13;
# issues/archived/2026-10-13-struct-value-into-pointer-global-destination-decision.md): `GP = l` copies `l` into `*GP`, as
# through a `*S` local or parameter, so a struct of ANOTHER type into it is refused by name, as into the local:
# R10-R15 (a local, 1-slot, a top-level global, a call, `*pu`, an operator result), R16 (a call over 8 B at top
# level: no frame for its result, as into a value global); A8 the filed repro verbatim (11 = 1 + 2 + 8; 13 when
# `GP = l` made GP the word 5), A9 `GP = &x` still rebinds. Mutation ledger (2026-10-14, a scratch tree copy with
# the one change, its compiler built by the fixed one, this gate run with CYCC=that compiler):
#   the tree before it (299e6e60)                          -> RED 8: R10-R16 not refused (each stored a word), A8 13
#   M5a `_agc_ptr_global` answering 0                      -> RED 8 (the same rows)
#   M5b `_agc_ptr_global` without the `_agc_src` test      -> GREEN, and struct_value_into_ptr_global.tcyr 138/138:
#                                                             an EQUIVALENT mutant — a `*S` global SOURCE then copies
#                                                             through `_try_aggregate_copy_assign` instead of
#                                                             `_hl_psrc_copy`, the same bytes copied (the corpus
#                                                             differential's one change, struct_pointer_source_copy
#                                                             .tcyr's binary, 60/60 either way); the test keeps every
#                                                             source's code byte-identical
#
# 6.7.11 — `*p = v` THROUGH A `*S` COPIES THE STRUCT (the user's decision (a), 2026-10-13; issues/2026-10-11-deref-
# store-through-struct-pointer-decision.md), so a struct of ANOTHER type is refused by name, as into `G`: R17-R25 (a
# local, a global, a call, `*pu`, an operator, a method, a field, a `*U` local; R24 at top level; R25 1-slot); and
# `*p OP= v` is refused as `l += a` is: C1-C4 (`*p += 1`, `*p += a`, top level `*GP -= 1`, a for step). A10 / A11
# the filed repros verbatim (90 = the whole 16 B struct, 42 through 6.7.10; 77 = nothing stored for a zero-size
# struct, 0 through 6.7.10). Mutation ledger (2026-10-14, the same method):
#   the tree before it (ac419c94)                          -> RED 15: R17-R25 and C1-C4 not refused, A10 42, A11 0
#   M9a `_dst_struct` answering 0                          -> RED 15 (the same rows)
#   M9b `_dst_struct` without the compound refusal         -> RED 4: C1-C4
#
# 6.7.13 — A DEREFERENCE OF AN ADDRESS-OF IS THE STRUCT IT NAMES (issues/2026-10-14-dereference-of-address-of-struct-
# faults.md): `*(&l) = q` of another struct is refused by name (R26), `*(&l) = v` / `*&G = v` copy the whole struct
# (A12; through 6.7.12 one word, l.z stale), and `*(&s) OP= v` keeps 6.7.5's first-word op (A13 — not this fix's).
# Mutations (2026-10-15, the same method): `_hl_dpsid` answering `_hl_psid` -> RED R26 A12; `_hl_dstep` ignoring the
# `&x` arm's step -> RED R26 A12; `_dst_struct` refusing `*(&s) OP= v` too -> RED A13.
#
# 6.7.14 — `**pp` THROUGH A `**S` IS THE STRUCT VALUE `*p` IS (issues/2026-10-16-struct-double-pointer-dereference-is-
# no-struct-value.md; 6.7.13's D9 (a) with 6.7.11's decision (a)): `var t: Q3 = **pp;` (R27) and `**pp = q` (R28) of
# another struct are refused by name, as `var t: Q3 = *p;` / `*p = q` are; `**pp += 1` (C5) and a top-level `**GPP -= 1`
# (C6) are refused as `*p OP= v` is; `**pp = u` copies the whole struct (A14: 56; through 6.7.13 one word, 54 — and
# R27 / R28 / C5 / C6 compiled: a handle bound to the first field, one word stored, the first field added to).
# Mutation (2026-10-17, the gate run as CYCC=<the lane's compiler before the fix>): RED 5 — R27 R28 C5 C6 not refused,
# A14 exit 54.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-$ROOT/build/cycc}
[ -x "$CC" ] || { echo "FAIL: compiler $CC missing"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$D"' EXIT

MSG="a different struct/vector type"
pass=0; fail=0; nrefuse=0; naccept=0

refuse() {  # $1 label  $2 source
    printf '%s' "$2" > "$D/r.cyr"
    rc=0
    cat "$D/r.cyr" | "$CC" > "$D/r.bin" 2>"$D/r.err" || rc=$?
    nrefuse=$((nrefuse+1))
    if grep -q "$MSG" "$D/r.err" 2>/dev/null; then
        if [ -s "$D/r.bin" ]; then
            printf '  FAIL: %-38s reported but still emitted a binary\n' "$1"; fail=$((fail+1))
        else
            printf '  ok(refused): %-31s\n' "$1"; pass=$((pass+1))
        fi
    else
        printf '  FAIL: %-38s not refused (rc=%s, first line: %s)\n' \
            "$1" "$rc" "$(head -1 "$D/r.err" 2>/dev/null || echo '(no output)')"
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
        printf '  FAIL: %-38s CONTROL gave %s, want %s — the expectation is wrong\n' "$1" "$ctl" "$3"
        fail=$((fail+1)); return
    fi
    if [ "$got" = "$3" ]; then
        printf '  ok(accepted): %-30s exit=%s (control %s)\n' "$1" "$got" "$ctl"; pass=$((pass+1))
    else
        printf '  FAIL: %-38s exit=%s, want %s (control %s)\n' "$1" "$got" "$3" "$ctl"
        fail=$((fail+1))
    fi
}

P3Q3='struct P3{x;y;z;} struct Q3{a;b;c;}
'
MK='fn mk3(x,y,z): P3 { var p: P3; p.x=x; p.y=y; p.z=z; return p; }
fn mkq(a,b,c): Q3 { var q: Q3; q.a=a; q.b=b; q.c=c; return q; }
'

echo "refusals — the copy is between two different types:"
refuse "R1 p = q  (locals, 3 slots)" "$P3Q3$MK"'fn main(): i64 { var p: P3 = P3{1,2,3}; var q: Q3 = Q3{7,8,9}; p = q; return p.z; }
var r = main(); syscall(60, r);
'
refuse "R2 var p: P3 = q  (local src)" "$P3Q3"'fn main(): i64 { var q: Q3 = Q3{7,8,9}; var p: P3 = q; return p.x; }
var r = main(); syscall(60, r);
'
refuse "R3 A = B  (two globals)" "$P3Q3"'var A = P3{1,2,3};
var B = Q3{7,8,9};
A = B;
syscall(60, A.z);
'
refuse "R4 var p: P3 = B  (global src)" "$P3Q3"'var B = Q3{7,8,9};
fn main(): i64 { var p: P3 = B; return p.x; }
var r = main(); syscall(60, r);
'
refuse "R5 p = q  (1-slot structs)" 'struct S1{x;} struct T1{a;}
fn main(): i64 { var p: S1 = S1{1}; var q: T1 = T1{7}; p = q; return p.x; }
var r = main(); syscall(60, r);
'
refuse "R6 var p: S1 = q  (1-slot)" 'struct S1{x;} struct T1{a;}
fn main(): i64 { var q: T1 = T1{7}; var p: S1 = q; return p.x; }
var r = main(); syscall(60, r);
'
refuse "R7 f64v4 = f64v2" 'fn main(): i64 { var a: f64v2; var b: f64v4; store64(&a, 41); b = a; return load64(&b); }
var r = main(); syscall(60, r);
'
refuse "R8 var b: f64v4 = a (f64v2)" 'fn main(): i64 { var a: f64v2; store64(&a, 41); var b: f64v4 = a; return load64(&b); }
var r = main(); syscall(60, r);
'
refuse "R9 struct = vector" 'struct P3{x;y;z;}
fn main(): i64 { var p: P3 = P3{1,2,3}; var v: f64v2; p = v; return p.x; }
var r = main(); syscall(60, r);
'

# 6.7.11: into a typed `*S` GLOBAL, which copies into its pointee (see the header).
PS='struct P3{x;y;z;} struct Q3{a;b;c;}
var GT = P3{0,0,0};
var GP: *P3 = &GT;
'
refuse "R10 GP = q  (a *P3 global, local src)" "$PS"'fn main(): i64 { var q: Q3 = Q3{7,8,9}; GP = q; return GT.z; }
var r = main(); syscall(60, r);
'
refuse "R11 GP = q  (1-slot structs)" 'struct S1{x;} struct T1{a;}
var GT = S1{0};
var GP: *S1 = &GT;
fn main(): i64 { var q: T1 = T1{7}; GP = q; return GT.x; }
var r = main(); syscall(60, r);
'
refuse "R12 GP = B  (top level, a global src)" "$PS"'var B = Q3{7,8,9};
GP = B;
syscall(60, GT.z);
'
refuse "R13 GP = mkq()  (a call result)" "$PS$MK"'fn main(): i64 { GP = mkq(7,8,9); return GT.z; }
var r = main(); syscall(60, r);
'
refuse "R14 GP = *pu  (a dereference)" "$PS"'fn main(): i64 { var q: Q3 = Q3{7,8,9}; var pu: *Q3 = &q; GP = *pu; return GT.z; }
var r = main(); syscall(60, r);
'
refuse "R15 GP = a + b  (an operator result)" "$PS"'fn Q3_add(l: Q3, r: Q3): Q3 { var t: Q3; t.a = l.a + r.a; t.b = l.b + r.b; t.c = l.c + r.c; return t; }
fn main(): i64 { var a: Q3 = Q3{7,8,9}; var b: Q3 = Q3{0,0,0}; GP = a + b; return GT.z; }
var r = main(); syscall(60, r);
'
# R16 — a 16 B call (rax:rdx) at TOP LEVEL into a `*S` global: no frame for its result, refused as into a value
# global (through 6.7.10 it compiled and made `GP` the result's first word, 7).
printf '%s' 'struct P2{x;y;}
fn mk2(x,y): P2 { var p: P2; p.x=x; p.y=y; return p; }
var GT2 = P2{0,0};
var GP2: *P2 = &GT2;
var e = 0;
GP2 = mk2(7,8);
syscall(60, GT2.y);
' > "$D/r16.cyr"
nrefuse=$((nrefuse+1))
if cat "$D/r16.cyr" | "$CC" > "$D/r16.bin" 2>"$D/r16.err"; then
    printf '  FAIL: %-38s compiled\n' "R16 GP = mk2() at top level"; fail=$((fail+1))
elif grep -q "needs storage in a fn's frame" "$D/r16.err" && [ ! -s "$D/r16.bin" ]; then
    printf '  ok(refused): %-31s\n' "R16 GP = mk2() at top level"; pass=$((pass+1))
else
    printf '  FAIL: %-38s %s\n' "R16 GP = mk2() at top level" "$(head -1 "$D/r16.err")"; fail=$((fail+1))
fi

# 6.7.11: through a `*S`, `*p = v` copies the struct (see the header).
refuse "R17 *p = u  (a local)" "$P3Q3"'var GT = P3{0,0,0};
fn main(): i64 { var u: Q3 = Q3{7,8,9}; var p: *P3 = &GT; *p = u; return GT.z; }
var r = main(); syscall(60, r);
'
refuse "R18 *p = GU  (a global)" "$P3Q3"'var GT = P3{0,0,0};
var GU = Q3{7,8,9};
fn main(): i64 { var p: *P3 = &GT; *p = GU; return GT.z; }
var r = main(); syscall(60, r);
'
refuse "R19 *p = mkq()  (a call)" "$P3Q3$MK"'var GT = P3{0,0,0};
fn main(): i64 { var p: *P3 = &GT; *p = mkq(7,8,9); return GT.z; }
var r = main(); syscall(60, r);
'
refuse "R20 *p = *pu  (a dereference)" "$P3Q3"'var GT = P3{0,0,0};
fn main(): i64 { var u: Q3 = Q3{7,8,9}; var pu: *Q3 = &u; var p: *P3 = &GT; *p = *pu; return GT.z; }
var r = main(); syscall(60, r);
'
refuse "R21 *p = a + b  (an operator)" "$P3Q3"'fn Q3_add(l: Q3, r: Q3): Q3 { var t: Q3; t.a = l.a + r.a; t.b = l.b + r.b; t.c = l.c + r.c; return t; }
var GT = P3{0,0,0};
fn main(): i64 { var a: Q3 = Q3{7,8,9}; var b: Q3 = Q3{0,0,0}; var p: *P3 = &GT; *p = a + b; return GT.z; }
var r = main(); syscall(60, r);
'
refuse "R22 *p = w.u  (a field)" "$P3Q3"'struct WQ { k; u: Q3; }
var GT = P3{0,0,0};
fn main(): i64 { var w: WQ = WQ{0,7,8,9}; var p: *P3 = &GT; *p = w.u; return GT.z; }
var r = main(); syscall(60, r);
'
refuse "R23 *p = pu  (a *U local)" "$P3Q3"'var GT = P3{0,0,0};
fn main(): i64 { var u: Q3 = Q3{7,8,9}; var pu: *Q3 = &u; var p: *P3 = &GT; *p = pu; return GT.z; }
var r = main(); syscall(60, r);
'
refuse "R24 *GP = GU  (top level)" "$P3Q3"'var GT = P3{0,0,0};
var GP: *P3 = &GT;
var GU = Q3{7,8,9};
var e = 0;
*GP = GU;
syscall(60, GT.z);
'
refuse "R25 *p = q  (1-slot structs)" 'struct S1{x;} struct T1{a;}
var GT = S1{0};
fn main(): i64 { var q: T1 = T1{7}; var p: *S1 = &GT; *p = q; return GT.x; }
var r = main(); syscall(60, r);
'
# R26 (6.7.13, issues/archived/2026-10-14-dereference-of-address-of-struct-faults.md) — `*(&l) = q`: a dereference of an
# address-of is the struct `l` names, so a struct of another type is refused by name as `l = q` is (through 6.7.12
# it stored q's address into l's first field).
refuse "R26 *(&l) = q  (another struct)" "$P3Q3"'fn main(): i64 { var q: Q3 = Q3{7,8,9}; var l: P3 = P3{0,0,0}; *(&l) = q; return l.x; }
var r = main(); syscall(60, r);
'
# R27 / R28 (6.7.14) — `**pp` of a `**P3` is a P3 value: another struct is refused by name, into a declaration and
# through `**pp = q`.
refuse "R27 var t: Q3 = **pp  (a **P3)" "$P3Q3"'fn main(): i64 { var s: P3 = P3{1,2,3}; var p: *P3 = &s; var pp: **P3 = &p; var t: Q3 = **pp; return t.a; }
var r = main(); syscall(60, r);
'
refuse "R28 **pp = q  (another struct)" "$P3Q3"'fn main(): i64 { var s: P3 = P3{1,2,3}; var p: *P3 = &s; var pp: **P3 = &p; var q: Q3 = Q3{7,8,9}; **pp = q; return s.x; }
var r = main(); syscall(60, r);
'
# C1-C4 — `*p OP= v` through a `*S`: refused by name, as `l += a` on a struct value is.
CMSG="compound assignment to the struct"
crefuse() {  # $1 label  $2 source
    printf '%s' "$2" > "$D/c.cyr"
    nrefuse=$((nrefuse+1))
    cat "$D/c.cyr" | "$CC" > "$D/c.bin" 2>"$D/c.err" || true
    if grep -q "$CMSG" "$D/c.err" 2>/dev/null && [ ! -s "$D/c.bin" ]; then
        printf '  ok(refused): %-31s\n' "$1"; pass=$((pass+1))
    else
        printf '  FAIL: %-38s not refused (first line: %s)\n' "$1" "$(head -1 "$D/c.err" 2>/dev/null)"; fail=$((fail+1))
    fi
}
crefuse "C1 *p += 1" "$P3Q3"'var GT = P3{0,0,0};
fn main(): i64 { var p: *P3 = &GT; *p += 1; return GT.x; }
var r = main(); syscall(60, r);
'
crefuse "C2 *p += a  (a struct)" "$P3Q3"'var GT = P3{0,0,0};
fn main(): i64 { var a: P3 = P3{1,2,3}; var p: *P3 = &GT; *p += a; return GT.x; }
var r = main(); syscall(60, r);
'
crefuse "C3 *GP -= 1  (top level)" "$P3Q3"'var GT = P3{5,0,0};
var GP: *P3 = &GT;
var e = 0;
*GP -= 1;
syscall(60, GT.x);
'
crefuse "C4 *p += 1  (a for step)" "$P3Q3"'var GT = P3{0,0,0};
fn main(): i64 { var p: *P3 = &GT; for (var i = 0; i < 1; *p += 1) { i = 1; } return GT.x; }
var r = main(); syscall(60, r);
'
# C5 / C6 (6.7.14) — `**pp OP= v` through a `**S`, as `*p OP= v` through a `*S` (6.7.11): in a fn and at top level.
crefuse "C5 **pp += 1  (a **P3)" "$P3Q3"'fn main(): i64 { var s: P3 = P3{1,2,3}; var p: *P3 = &s; var pp: **P3 = &p; **pp += 1; return s.x; }
var r = main(); syscall(60, r);
'
crefuse "C6 **GPP -= 1  (top level)" "$P3Q3"'var GT = P3{5,0,0};
var GP: *P3 = &GT;
var GPP: **P3 = &GP;
**GPP -= 1;
syscall(60, GT.x);
'

echo "acceptances — these must stay legal, with the right VALUE:"
accept "A1 p = q  (same struct type)" 'struct P3{x;y;z;}
fn main(): i64 { var p: P3 = P3{1,2,3}; var q: P3 = P3{7,8,9}; p = q; return p.z; }
var r = main(); syscall(60, r);
' 9 'struct P3{x;y;z;}
fn main(): i64 { var p: P3 = P3{1,2,3}; var q: P3 = P3{7,8,9}; p.x = q.x; p.y = q.y; p.z = q.z; return p.z; }
var r = main(); syscall(60, r);
'
accept "A2 var p: P3 = q (same type)" 'struct P3{x;y;z;}
fn main(): i64 { var q: P3 = P3{7,8,9}; var p: P3 = q; return p.z; }
var r = main(); syscall(60, r);
' 9 'struct P3{x;y;z;}
fn main(): i64 { var q: P3 = P3{7,8,9}; var p: P3; p.x = q.x; p.y = q.y; p.z = q.z; return p.z; }
var r = main(); syscall(60, r);
'
accept "A3 A = B  (same-type globals)" 'struct P3{x;y;z;}
var A = P3{1,2,3};
var B = P3{7,8,9};
A = B;
syscall(60, A.z);
' 9 'struct P3{x;y;z;}
var A = P3{1,2,3};
var B = P3{7,8,9};
A.x = B.x;
A.y = B.y;
A.z = B.z;
syscall(60, A.z);
'
accept "A4 pointer-mode src still binds" 'struct P3{x;y;z;}
fn mk3(x,y,z): P3 { var p: P3; p.x=x; p.y=y; p.z=z; return p; }
fn main(): i64 { var q: P3 = mk3(7,8,9); var p: P3 = q; return p.z; }
var r = main(); syscall(60, r);
' 9 'struct P3{x;y;z;}
fn mk3(x,y,z): P3 { var p: P3; p.x=x; p.y=y; p.z=z; return p; }
fn main(): i64 { var q: P3 = mk3(7,8,9); return q.z; }
var r = main(); syscall(60, r);
'
accept "A5 f64v2 = f64v2" 'fn main(): i64 { var a: f64v2; var b: f64v2; store64(&a, 41); b = a; return load64(&b); }
var r = main(); syscall(60, r);
' 41 'fn main(): i64 { var a: f64v2; store64(&a, 41); return load64(&a); }
var r = main(); syscall(60, r);
'
accept "A6 by-value struct param copy" 'struct P3{x;y;z;}
fn take(p: P3): i64 { var q: P3 = P3{0,0,0}; q = p; return q.z; }
fn main(): i64 { var a: P3 = P3{1,2,3}; return take(a); }
var r = main(); syscall(60, r);
' 3 'struct P3{x;y;z;}
fn take(p: P3): i64 { return p.z; }
fn main(): i64 { var a: P3 = P3{1,2,3}; return take(a); }
var r = main(); syscall(60, r);
'
# A8 — the filed repro, verbatim (issues/archived/2026-10-13-struct-value-into-pointer-global-destination-decision.md):
# 11 = 1 (the local copies) + 2 (`GP = l` copied into GS) + 8 (the parameter copies); 13 through 6.7.10.
accept "A8 GP = l copies into *GP (filed)" 'struct S { a; b; }
var GS = S { 0, 0 };
var GP: *S = 0;
fn viap(q: *S, l: S): i64 { q = l; return 0; }
fn main(): i64 {
    GP = &GS;
    var t: S; t.a = 0; t.b = 0;
    var lp: *S = &t;
    var l: S; l.a = 5; l.b = 8;
    lp = l;
    var r = (t.a == 5 && t.b == 8);
    GP = l;
    r = r + (GS.a == 5) * 2 + (GP == 5) * 4;
    var u: S; u.a = 0; u.b = 0; viap(&u, l); return r + (u.a == 5 && u.b == 8) * 8;
}
syscall(60, main());
' 11 'struct S { a; b; }
var GS = S { 0, 0 };
var GP: *S = 0;
fn main(): i64 {
    GP = &GS;
    var l: S; l.a = 5; l.b = 8;
    GP.a = l.a; GP.b = l.b;
    return 1 + (GS.a == 5) * 2 + (GP == 5) * 4 + 8;
}
syscall(60, main());
'
accept "A9 GP = &x still rebinds" "$PS"'fn main(): i64 { var x: P3 = P3{7,8,9}; GP = &x; return GP.z + GT.z; }
var r = main(); syscall(60, r);
' 9 "$PS"'fn main(): i64 { var x: P3 = P3{7,8,9}; var q = &x; return load64(q + 16) + GT.z; }
var r = main(); syscall(60, r);
'
# A10 / A11 — issues/archived/2026-10-11-deref-store-through-struct-pointer-decision.md's repros, verbatim: 90 (the whole
# 16 B struct; 42 through 6.7.10, only x copied) and 77 (a zero-size struct stores nothing; 0 through 6.7.10).
accept "A10 *p = l copies 16 B (filed)" 'struct P2 { x; y; }
var G: P2 = P2 { 1, 2 };
fn run(): i64 { var l: P2 = P2 { 40, 50 }; var p: *P2 = &G; *p = l; return 0; }
var rr = run();
syscall(60, G.x + G.y);   # actual 42 (only x copied) · 90 for a whole-struct copy · 3 if nothing is stored
' 90 'struct P2 { x; y; }
var G: P2 = P2 { 1, 2 };
fn run(): i64 { var l: P2 = P2 { 40, 50 }; var p: *P2 = &G; p.x = l.x; p.y = l.y; return 0; }
var rr = run();
syscall(60, G.x + G.y);
'
accept "A11 *p = l, zero-size (filed)" 'struct E { }
var G: E = E { };
var N1: i8 = 77;
fn run(): i64 { var l: E; var p: *E = &G; *p = l; return 0; }
var rr = run();
syscall(60, N1);          # actual 0 · 77 if nothing (or the zero bytes of E) is stored
' 77 'struct E { }
var G: E = E { };
var N1: i8 = 77;
fn run(): i64 { var l: E; var p: *E = &G; return 0; }
var rr = run();
syscall(60, N1);
'
# A12 / A13 (6.7.13) — `*(&l) = v` / `*&G = v` copy the struct `l` / `G` names (through 6.7.12 one word: l.z
# stale); `*(&s) OP= v` is not this fix's — it keeps 6.7.5's word op on the first word (the `OP=` of a
# dereference of an address-of is not refused like `*p OP= v` through a `*S`; field_compound_values.tcyr Q4).
accept "A12 *(&l) = v, *&G = v copy the struct" "$P3Q3"'var G: P3 = P3{0,0,0};
fn main(): i64 { var v: P3 = P3{1,2,3}; var l: P3 = P3{0,0,0}; *(&l) = v; *&G = v; v.z = 0; return l.z * 10 + G.z; }
var r = main(); syscall(60, r);
' 33 "$P3Q3"'var G: P3 = P3{0,0,0};
fn main(): i64 { var v: P3 = P3{1,2,3}; var l: P3 = P3{0,0,0}; l.z = v.z; G.z = v.z; return l.z * 10 + G.z; }
var r = main(); syscall(60, r);
'
accept "A13 *(&s) += 10 keeps the first-word op" "$P3Q3"'fn main(): i64 { var s: P3 = P3{3,4,5}; *(&s) += 10; return s.x * 10 + s.y; }
var r = main(); syscall(60, r);
' 134 "$P3Q3"'fn main(): i64 { var s: P3 = P3{3,4,5}; s.x = s.x + 10; return s.x * 10 + s.y; }
var r = main(); syscall(60, r);
'
# A14 (6.7.14) — `**pp = u` through a `**P2` copies the whole struct (56; through 6.7.13 one word: 54).
accept "A14 **pp = u copies the struct" 'struct P2 { x; y; }
fn main(): i64 { var s = P2 { 3, 4 }; var p: *P2 = &s; var pp: **P2 = &p; var u = P2 { 5, 6 }; **pp = u; return s.x * 10 + s.y; }
var r = main(); syscall(60, r);
' 56 'struct P2 { x; y; }
fn main(): i64 { var s = P2 { 3, 4 }; var p: *P2 = &s; var u = P2 { 5, 6 }; p.x = u.x; p.y = u.y; return s.x * 10 + s.y; }
var r = main(); syscall(60, r);
'
# A7 — a SCALAR source is a different rule (a warning, since before 6.6.6) and must not have
# been swept into the new error. Checked directly rather than through accept(): the point is
# the absence of the refusal, and the value it stores is the pre-existing behaviour.
printf '%s' 'struct P3{x;y;z;}
fn main(): i64 { var p: P3 = P3{1,2,3}; var s = 5; p = s; return p.x; }
var r = main(); syscall(60, r);
' > "$D/a7.cyr"
a7=$(_run "$D/a7.cyr")
naccept=$((naccept+1))
if grep -q "$MSG" "$D/a.err" 2>/dev/null; then
    printf '  FAIL: %-38s a scalar source was swept into the new error\n' "A7 scalar src still only warns"
    fail=$((fail+1))
elif [ "$a7" = "5" ]; then
    printf '  ok(accepted): %-30s exit=5, warning only\n' "A7 scalar src still only warns"; pass=$((pass+1))
else
    printf '  FAIL: %-38s exit=%s, want 5\n' "A7 scalar src still only warns" "$a7"; fail=$((fail+1))
fi

# Anti-vacuous: a rewritten row list must move these, and a `refuse`/`accept` helper that
# silently stopped running would leave them at 0.
[ "$nrefuse" -ge 34 ] || { echo "FAIL: only $nrefuse refusal rows ran (floor 34)"; fail=$((fail+1)); }
[ "$naccept" -ge 14 ] || { echo "FAIL: only $naccept acceptance rows ran (floor 14)"; fail=$((fail+1)); }
# And the message this gate greps for must still be the one the compiler emits, spelled in
# exactly one place in src/ — a reworded diagnostic with an unchanged gate greps for nothing
# and every refusal row would report "not refused", which is loud; this says why.
n=$(grep -c "$MSG" src/common/util.cyr || true)
[ "$n" -ge 1 ] || { echo "FAIL: src/common/util.cyr no longer spells '$MSG' — reworded?"; fail=$((fail+1)); }

echo "struct_copy_type_checked: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$fail" -eq 0 ]
