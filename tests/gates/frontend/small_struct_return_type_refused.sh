#!/bin/sh
# Gate: the value a fn returning a struct of 8 B or less returns is checked by its struct (6.7.11).
#
# THE DEFECT (measured on the 6.7.11 struct lane's tree before the fix, 3fc1dbbb, x86_64 Linux; every
# refusal row below compiled clean there, no diagnostic):
#   `fn f(): S8 { var u: U8; u.u = 3; return u; }`        -> exit 3: U8's word read as the S8 (R1, the filed repro)
#   `return (u);`, a by-value `p: U8`, a global `GU`,     -> 7 / 4 / 5 / 6: the same, each spelling
#     `return mk();` (taken as a tail call)
#   a handle of another struct (B7-1)                     -> 9: its struct's bytes, by design in 6.7.10
#   `var p: *U8 = &u; return p;`, `q: *U8`               -> the ADDRESS (208 / 240 measured, varying by build)
#   `var p: *S8 = &u; return p;` (the fn's OWN struct)   -> the ADDRESS (192 filed; 240 here): A1's repro
# while the 9-16 B class refused every one of them by name (`_refuse_pair_return`) and the > 16 B class
# did ("identifier type != fn ret_sid"), and a `q: *S8` PARAMETER copied (6.6.17). The class's only
# `return IDENT;` arm (`_ret_small_ptrp`) took a `*T` parameter or a handle and never compared the type;
# every other shape reached the scalar tail (`_bx_pcmpe_ret`), a plain PCMPE.
# docs/development/issues/archived/2026-10-12-small-struct-return-takes-another-structs-value.md
#
# THE RULE (the user's decision, 2026-10-13, (a)): every other-struct shape is refused by name — a local,
# a by-value parameter, a global, a parenthesised name, a call (the tail-called `return mk();` included),
# a field, a method or operator result, a dereference of a `*U`, a `*U` local or parameter, and a handle of
# another struct (local or global):
#   a fn returning the struct `S8` takes a value of that struct, or a pointer to one — got `u` (a `U8`)
# A `*S8` LOCAL of the fn's own struct is the struct it points at, as a `*S8` parameter is (decision 6:
# struct copies are size-independent). An untyped value stays the struct's word (out of scope).
# `_ret_small_val` / `_ret_expr_sid` / `_ret_small_ptr` / `_tc_small_sret_divert` (src/frontend/parse_fn.cyr),
# `_ret_small_gh` (parse_decl.cyr). The runtime half is tests/tcyr/crossos/struct_ptrmode_return_copy.tcyr
# (the `*T` local rows, every leg: tests/gates/codegen/small_struct_handle_line.sh R13).
#
# Refusal rows are checked on the MESSAGE, that it is the ONE `^error`, and that no binary was written.
# Acceptance rows are checked against the exit code AND a field-by-field CONTROL.
#
# MUTATION LEDGER (6.7.11, each mutant a one-change copy of the fixed src built by the fixed compiler;
# measured 2026-10-14):
#   the tree before it (3fc1dbbb)                       -> RED 20: R1-R16 (each compiled, no diagnostic), A1 A2
#                                                          A9 A10 (the `*T` local's address: 80 / 32 / 252 / 0)
#   `_ret_small_val` without its value refusal          -> RED 12: R1-R11 R15
#   `_ret_small_ptr` answering 0                        -> RED 8: R12-R14 R16 (the address), A1 A2 A9 A10
#   `_tc_small_sret_divert` answering 0                 -> RED 1: R5 (`return mk();` kept its `jmp`)
#   `_ret_small_ptrp` with the 6.7.10 handle exemption  -> RED 1: R7 (another struct's handle copied)
#   `_ret_small_gh` without its type test               -> RED 1: R8 (another struct's handle global copied)
#   `_ret_expr_sid` without the `;` wrap (k 0)          -> RED 2: R2 R6
#   `_bx_pcmpe_ret` a plain PCMPE again                 -> RED 20: as the tree before it
#   `_ret_small_cls` without its GIDEP test              -> RED 1: A10 (the replayed `gu<i64>()` body's `return GU;`
#                                                          refused as the S8 fn's: a false refusal)
#   `_ret_small_val` without its dyn test               -> no row here: tests/gates/frontend/dyn_checked.sh V4y RED
#                                                          (`return pass(o);` of a dyn from a `: S1` fn: 2 error lines,
#                                                          the dyn's own refusal and this one)
#   real tree                                           -> GREEN (17 refusal rows, 10 acceptance rows)
# 6.7.13 (D4 (a), measured 2026-10-15; R17-R23, A11-A13):
#   the tree before it (431793cf)                       -> RED 9: R17-R20 compiled, no diagnostic (u's address as the
#                                                          S8 / S3); R21 R22 refused in other words ("... two registers
#                                                          ... got `this expression`", "return must be a bare local
#                                                          identifier ..."); A11-A13 the address's low byte (192 / 71 / 16)
#   `_ret_small_ptr` typing by `_hl_psid` again         -> RED 7: R17-R20, A11-A13
#   `_ret_ptr_src` typing by `_hl_psid` again           -> RED 2: R21 R22 (the old refusals)
#   `_ret_sid_refuse` without kind 3 (`&u` read `u`, `U8`) -> RED 6: R17-R22 (the message names `u` (a `U8`))
#   real tree                                           -> GREEN (24 refusal rows, 13 acceptance rows)
# 6.7.13 (the review fix, measured 2026-10-16; R23b-R23d, each on the x86_64, aarch64, cx and PE compilers):
#   `_ret_addr_field` answering -1 (the lane before it) -> RED 12: R23b R23d x4 (the pair class's "two registers"
#                                                          first, D3's second: 2 errors), R23c x4 ("return must be a
#                                                          bare local identifier ..." alone)
#   real tree                                           -> GREEN (27 refusal rows — floor 27 — and 13 acceptance rows)
#
# Exit 77 = could not run (the SKIP protocol): no compiler, or no scratch directory.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: compiler $CC missing"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "SKIP: mktemp -d failed"; exit 77; }
trap 'rm -rf "$D"' EXIT

MS='takes a value of that struct, or a pointer to one'
pass=0; fail=0; nrefuse=0; naccept=0

refuse() {  # $1 label  $2 expected message  $3 source — the message must be the ONE error
    nrefuse=$((nrefuse+1))
    _refuse_leg x86_64 "$@"
}
_refuse_leg() {  # $1 leg (x86_64 / aarch64 / cx / pe), then refuse's arguments
    leg=$1; shift
    printf '%s' "$3" > "$D/r.cyr"
    rc=0
    case $leg in
        x86_64)  "$CC" < "$D/r.cyr" > "$D/r.bin" 2>"$D/r.err" || rc=$? ;;
        aarch64) "$D/cc_a64" < "$D/r.cyr" > "$D/r.bin" 2>"$D/r.err" || rc=$? ;;
        cx)      "$D/cc_cx" < "$D/r.cyr" > "$D/r.bin" 2>"$D/r.err" || rc=$? ;;
        pe)      CYRIUS_TARGET_WIN=1 "$CC" < "$D/r.cyr" > "$D/r.bin" 2>"$D/r.err" || rc=$? ;;
    esac
    nerr=$(grep -c '^error' "$D/r.err" 2>/dev/null || true)
    if grep -q "$2" "$D/r.err" 2>/dev/null; then
        if [ -s "$D/r.bin" ]; then
            printf '  FAIL: %-50s reported but still emitted a binary\n' "$1"; fail=$((fail+1))
        elif [ "$nerr" != 1 ]; then
            printf '  FAIL: %-50s refused, then %s more error(s): %s\n' "$1" "$((nerr-1))" \
                "$(grep '^error' "$D/r.err" | sed -n 2p)"
            fail=$((fail+1))
        else
            printf '  ok(refused): %-44s\n' "$1"; pass=$((pass+1))
        fi
    else
        printf '  FAIL: %-50s not refused (rc=%s, first line: %s)\n' \
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
        printf '  FAIL: %-50s CONTROL gave %s, want %s — the expectation is wrong\n' "$1" "$ctl" "$3"
        fail=$((fail+1)); return
    fi
    if [ "$got" = "$3" ]; then
        printf '  ok(accepted): %-43s exit=%s (control %s)\n' "$1" "$got" "$ctl"; pass=$((pass+1))
    else
        printf '  FAIL: %-50s exit=%s, want %s (control %s): %s\n' "$1" "$got" "$3" "$ctl" \
            "$(grep '^error' "$D/a.err" 2>/dev/null | head -1)"
        fail=$((fail+1))
    fi
}

# S8 / U8 two 8 B structs; S3 / U3 two 3 B ones; G reads the S8 f() returns.
T='include "lib/alloc.cyr"
struct S8 { v; }
struct U8 { u; }
struct S3 { a: i8; b: i8; c: i8; }
struct U3 { x: i8; y: i8; z: i8; }
struct W { u: U8; k; }
var GU = U8 { 0 };
var GUH: U8 = 0;
var GPU: *U8 = 0;
fn mk(): U8 { var r: U8; r.u = 6; return r; }
fn mk8(n): S8 { var r: S8; r.v = n; return r; }
impl U8 { fn dup(self): U8 { var r: U8; r.u = 15; return r; } }
'
E='
fn g(): i64 { var s: S8 = f(); return s.v; }
alloc_init();
syscall(60, g());
'
E3='
fn g(): i64 { var s: S3 = f(); return s.c; }
syscall(60, g());
'

echo "=== the filed repros, verbatim ==="
refuse "R1 r8.cyr: return u; (u: U8) from : S8" "$MS — got \`u\` (a \`U8\`)" 'struct S8 { v; }
struct U8 { u; }
fn f(): S8 { var u: U8; u.u = 3; return u; }
fn g(): i64 { var s: S8 = f(); return s.v; }
syscall(60, g());
'
# The 9-16 B twin keeps its own class's refusal (unchanged).
refuse "R1b r16.cyr: the 9-16 B twin (unchanged)" "is returned in two registers, so .return. takes a local of that struct or a call returning it — got .k." 'struct H { a; b; }
struct K { c; d; }
fn f(): H { var k: K; k.c = 3; k.d = 4; return k; }
fn g(): i64 { var s: H = f(); return s.a; }
syscall(60, g());
'
accept "A1 rp.cyr: return p; (p: *S8 a local) is its struct" 'struct S8 { v; }
fn f(): S8 { var u: S8; u.v = 8; var p: *S8 = &u; return p; }
fn g(): i64 { var s: S8 = f(); return s.v; }
syscall(60, g());
' 8 'struct S8 { v; }
fn g(): i64 { var s: S8; s.v = 8; return s.v; }
syscall(60, g());
'

echo "=== another struct's value, every spelling (8 B) ==="
refuse "R2 return (u);" "$MS — got \`u\` (a \`U8\`)" "$T"'fn f(): S8 { var u: U8; u.u = 7; return (u); }'"$E"
refuse "R3 return p; (p: U8, a by-value parameter)" "$MS — got \`p\` (a \`U8\`)" "$T"'fn f2(p: U8): S8 { return p; }
fn f(): S8 { var u: U8; u.u = 4; return f2(u); }'"$E"
refuse "R4 return GU; (a value global)" "$MS — got \`GU\` (a \`U8\`)" "$T"'fn f(): S8 { GU.u = 5; return GU; }'"$E"
refuse "R5 return mk(); (tail-call shaped)" "$MS — got \`mk\` (a \`U8\`)" "$T"'fn f(): S8 { return mk(); }'"$E"
refuse "R6 return (mk());" "$MS — got \`mk\` (a \`U8\`)" "$T"'fn f(): S8 { return (mk()); }'"$E"
refuse "R7 a handle of another struct (B7-1)" "$MS — got \`u\` (a \`U8\`)" "$T"'fn f(): S8 { var u: U8 = alloc(8); u.u = 9; return u; }'"$E"
refuse "R8 a handle GLOBAL of another struct" "$MS — got \`GUH\` (a \`U8\`)" "$T"'fn f(): S8 { GUH = alloc(8); GUH.u = 11; return GUH; }'"$E"
refuse "R9 return w.u; (a field of another struct)" "$MS — got \`u\` (a \`U8\`)" "$T"'fn f(): S8 { var w: W; w.u.u = 2; return w.u; }'"$E"
refuse "R10 return u.dup(); (a method of another struct)" "$MS — got \`U8_dup\` (a \`U8\`)" "$T"'fn f(): S8 { var u: U8; return u.dup(); }'"$E"
refuse "R11 return *pu; (a dereference of a *U8)" "$MS — got \`\\*pu\` (a \`U8\`)" "$T"'fn f(): S8 { var u: U8; u.u = 13; var pu: *U8 = &u; return *pu; }'"$E"

echo "=== a pointer to another struct (8 B) ==="
refuse "R12 var p: *U8 = &u; return p;" "$MS — got \`p\` (a \`\\*U8\`)" "$T"'fn f(): S8 { var u: U8; u.u = 1; var p: *U8 = &u; return p; }'"$E"
refuse "R13 fn f(q: *U8): S8 { return q; }" "$MS — got \`q\` (a \`\\*U8\`)" "$T"'fn f2(q: *U8): S8 { return q; }
fn f(): S8 { var u: U8; u.u = 1; return f2(&u); }'"$E"
refuse "R14 return ((p)); (p: *U8)" "$MS — got \`p\` (a \`\\*U8\`)" "$T"'fn f(): S8 { var u: U8; var p: *U8 = &u; return ((p)); }'"$E"

echo "=== an odd-sized struct (3 B) ==="
refuse "R15 return u; (u: U3) from : S3" "$MS — got \`u\` (a \`U3\`)" "$T"'fn f(): S3 { var u: U3; u.z = 3; return u; }'"$E3"
refuse "R16 var p: *U3 = &u; return p; from : S3" "$MS — got \`p\` (a \`\\*U3\`)" "$T"'fn f(): S3 { var u: U3; var p: *U3 = &u; return p; }'"$E3"

echo "=== the same struct, and untyped values (no false refusal) ==="
accept "A2 return ((p)); (p: *S8 a local)" "$T"'fn f(): S8 { var u: S8; u.v = 16; var p: *S8 = &u; return ((p)); }'"$E" 16 \
    "$T"'fn f(): S8 { var u: S8; u.v = 16; return u; }'"$E"
accept "A3 control: fn f(q: *S8): S8 { return q; }" "$T"'fn f2(q: *S8): S8 { return q; }
fn f(): S8 { var u: S8; u.v = 12; return f2(&u); }'"$E" 12 "$T"'fn f(): S8 { var u: S8; u.v = 12; return u; }'"$E"
accept "A4 control: return u; (u: S8)" "$T"'fn f(): S8 { var u: S8; u.v = 10; return u; }'"$E" 10 \
    "$T"'fn f(): S8 { var u: S8; u.v = 10; var c = u.v; u.v = c; return u; }'"$E"
accept "A5 return mk8(8); (the same struct: a tail call)" "$T"'fn f(): S8 { return mk8(8); }'"$E" 8 \
    "$T"'fn f(): S8 { var u: S8; u.v = 8; return u; }'"$E"
accept "A6 a handle of the same struct" "$T"'fn f(): S8 { var u: S8 = alloc(8); u.v = 17; return u; }'"$E" 17 \
    "$T"'fn f(): S8 { var u: S8; u.v = 17; return u; }'"$E"
accept "A7 return x; (x untyped: the struct's word)" "$T"'fn f(): S8 { var x = 14; return x; }'"$E" 14 \
    "$T"'fn f(): S8 { var u: S8; u.v = 14; return u; }'"$E"
accept "A8 return *p; (p: *S8)" "$T"'fn f(): S8 { var u: S8; u.v = 18; var p: *S8 = &u; return *p; }'"$E" 18 \
    "$T"'fn f(): S8 { var u: S8; u.v = 18; return u; }'"$E"
accept "A9 a 3 B *S3 local" "$T"'fn f(): S3 { var u: S3; u.c = 19; var p: *S3 = &u; return p; }'"$E3" 19 \
    "$T"'fn f(): S3 { var u: S3; u.c = 19; return u; }'"$E3"
# A generic's straight-line body is REPLAYED inline at its call: its `return` is the callee's, never judged by
# the enclosing S8 fn's class — `gq<i64>()` hands back its `*S8` (not the struct), `gu<i64>()` its U8.
accept "A10 generic inline bodies inside a : S8 fn" "$T"'var GS8 = S8 { 41 };
var GPT: *S8 = 0;
fn gq<T>(): *S8 { return GPT; }
fn gu<T>(): U8 { return GU; }
fn f(): S8 { GPT = &GS8; GU.u = 7; var p: *S8 = gq<i64>(); p.v = p.v + 1; var u: U8 = gu<i64>(); p.v = p.v + u.u; return p; }'"$E" 49 \
    "$T"'fn f(): S8 { var u: S8; u.v = 49; return u; }'"$E"

echo "=== return &x (6.7.13, the user's decision D4 (a), 2026-10-15): &s of the fn's own struct is the struct ==="
# `return &s;` is `return s;` (tests/tcyr/crossos/struct_return_address_of.tcyr, every leg: small_struct_handle_line.sh
# R13a); `&u` of ANOTHER struct is refused by name at every size, as `return u;` is — through 6.7.12 the 8 B form
# returned u's ADDRESS as the S8 (no diagnostic) and the 16 / 24 B forms were refused in other words.
# docs/development/issues/2026-10-14-return-address-of-struct-local-decision.md
refuse "R17 return &u; (u: U8) from : S8" "$MS — got \`&u\` (a \`\\*U8\`)" "$T"'fn f(): S8 { var u: U8; u.u = 3; return &u; }'"$E"
refuse "R18 return (&GU); (a value global of U8)" "$MS — got \`&GU\` (a \`\\*U8\`)" "$T"'fn f(): S8 { return (&GU); }'"$E"
refuse "R19 return &p; (p: U8, a by-value parameter)" "$MS — got \`&p\` (a \`\\*U8\`)" "$T"'fn f2(p: U8): S8 { return &p; }
fn f(): S8 { var u: U8; u.u = 4; return f2(u); }'"$E"
refuse "R20 return &u; (u: U3) from : S3" "$MS — got \`&u\` (a \`\\*U3\`)" "$T"'fn f(): S3 { var u: U3; u.z = 3; return &u; }'"$E3"
refuse "R21 return &k; (k: K) from : H (16 B)" "$MS — got \`&k\` (a \`\\*K\`)" 'struct H { a; b; }
struct K { c; d; }
fn f(): H { var k: K; k.c = 3; k.d = 4; return &k; }
fn g(): i64 { var s: H = f(); return s.a; }
syscall(60, g());
'
refuse "R22 return (&k); (k: K, a by-value parameter) from : H (24 B)" "$MS — got \`&k\` (a \`\\*K\`)" 'struct H { a; b; c; }
struct K { d; e; f; }
fn f2(k: K): H { return (&k); }
fn f(): H { var k: K; return f2(k); }
fn g(): i64 { var s: H = f(); return s.a; }
syscall(60, g());
'
# `&w.u` is no expression at all (6.7.13 D3 (b)): its own refusal, once — the return check adds nothing.
refuse "R23 return &w.u; (the address of a field)" "the address of a field is not taken" "$T"'fn f(): S8 { var w: W; return &w.u; }'"$E"
# ... at 16 and 24 B too (the review fix, `_ret_addr_field`): the pair class raised its "two registers ... got
# `this expression`" before D3's refusal (two errors) and the retptr class its "return must be a bare local
# identifier ..." alone. Each row on the four compilers (aarch64 and cx cross-built from this tree's src).
"$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2>/dev/null && [ -s "$D/cc_a64" ] && chmod +x "$D/cc_a64" \
    || { echo "FAIL: src/main_aarch64.cyr did not build"; exit 1; }
"$CC" < src/main_cx.cyr > "$D/cc_cx" 2>/dev/null && [ -s "$D/cc_cx" ] && chmod +x "$D/cc_cx" \
    || { echo "FAIL: src/main_cx.cyr did not build"; exit 1; }
refuse4() {  # refuse on the x86_64, aarch64, cx and PE compilers
    nrefuse=$((nrefuse+1))
    for l4 in x86_64 aarch64 cx pe; do _refuse_leg "$l4" "$1 ($l4)" "$2" "$3"; done
}
FW='struct S16 { v; w; }
struct S24 { v; w; x; }
struct W16 { n; s: S16; }
struct W24 { n; s: S24; }
'
refuse4 "R23b return &w.s; from : S16 (16 B)" "the address of a field is not taken" "$FW"'fn f(): S16 { var w: W16; w.s.v = 3; return &w.s; }
fn g(): i64 { var s: S16 = f(); return s.v; }
syscall(60, g());
'
refuse4 "R23c return &w.s; from : S24 (24 B)" "the address of a field is not taken" "$FW"'fn f(): S24 { var w: W24; w.s.v = 3; return &w.s; }
fn g(): i64 { var s: S24 = f(); return s.v; }
syscall(60, g());
'
refuse4 "R23d return (&w.s); from : S16 (16 B)" "the address of a field is not taken" "$FW"'fn f(): S16 { var w: W16; w.s.v = 3; return (&w.s); }
fn g(): i64 { var s: S16 = f(); return s.v; }
syscall(60, g());
'
accept "A11 return &u; (u: S8) is the struct" "$T"'fn f(): S8 { var u: S8; u.v = 21; return &u; }'"$E" 21 \
    "$T"'fn f(): S8 { var u: S8; u.v = 21; return u; }'"$E"
accept "A12 return (&u); (u: S3) is the struct" "$T"'fn f(): S3 { var u: S3; u.c = 22; return (&u); }'"$E3" 22 \
    "$T"'fn f(): S3 { var u: S3; u.c = 22; return u; }'"$E3"
accept "A13 return &p; (p: S8, a by-value parameter)" "$T"'fn f2(p: S8): S8 { return &p; }
fn f(): S8 { var u: S8; u.v = 23; return f2(u); }'"$E" 23 "$T"'fn f(): S8 { var u: S8; u.v = 23; return u; }'"$E"

echo "small_struct_return_type_refused: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$nrefuse" -ge 27 ] || { echo "FAIL: only $nrefuse refusal rows ran (floor 27) — rows were lost"; exit 1; }
[ "$naccept" -ge 13 ] || { echo "FAIL: only $naccept acceptance rows ran (floor 13) — rows were lost"; exit 1; }
[ "$fail" -eq 0 ] || exit 1
exit 0
