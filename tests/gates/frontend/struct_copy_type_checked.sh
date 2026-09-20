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
[ "$nrefuse" -ge 9 ]  || { echo "FAIL: only $nrefuse refusal rows ran (floor 9)"; fail=$((fail+1)); }
[ "$naccept" -ge 7 ]  || { echo "FAIL: only $naccept acceptance rows ran (floor 7)"; fail=$((fail+1)); }
# And the message this gate greps for must still be the one the compiler emits, spelled in
# exactly one place in src/ — a reworded diagnostic with an unchanged gate greps for nothing
# and every refusal row would report "not refused", which is loud; this says why.
n=$(grep -c "$MSG" src/common/util.cyr || true)
[ "$n" -ge 1 ] || { echo "FAIL: src/common/util.cyr no longer spells '$MSG' — reworded?"; fail=$((fail+1)); }

echo "struct_copy_type_checked: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$fail" -eq 0 ]
