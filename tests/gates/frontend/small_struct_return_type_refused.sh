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
#                                                          (6.7.14, re-measured 2026-10-16: GREEN — the replay runs
#                                                          with no struct class, `_inl_replay_body`; RR1-RR13 pin it)
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
# 6.7.14 (measured 2026-10-16; RR1-RR13 and the RR builds; a one-edit scratch copy of the tree, its 2-stage mutant):
#   `_inl_replay_body` without its mask (the caller's  -> RED 21: RR1-RR6 RR11-RR13 (refused by the CALLER's class,
#   struct class leaks into the replay, as before)        no binary) and the 12 RR builds on aarch64 / cx / PE;
#                                                          RR7-RR10 green (an 8 B or i64 caller, the uncalled generic);
#                                                          small_struct_handle_line.sh R12 RED on every leg (the
#                                                          values file does not build)
#   real tree                                           -> GREEN (27 refusal rows, 26 acceptance rows — floor 26 —
#                                                          and 12 builds)
# 6.7.14 (D19 (a), measured 2026-10-17; R24-R39, A14; CYCC=the mutant, a one-edit copy of parse_fn.cyr built by the
# fixed compiler — the aarch64 / cx legs build from the tree's src and stay fixed):
#   the lane before it (0d225f0c)                       -> RED 25: R24-R32 x86_64 / PE (8 B: compiled, the slot's
#                                                          address the struct's word; 16 / 24 B: the classes' own
#                                                          refusals), R33-R39
#   `_ret_ptr_src` without its `_ret_slot_amp` arm      -> RED 15: R25 R26 R28 R29 R31 R32 x86_64 / PE, R34-R36
#   `_ret_small_ptr` without it                         -> RED 10: R24 R27 R30 x86_64 / PE, R33 R37 R38 R39
#   `_ret_slot_amp` taking no `*T` (`_hl_cp` 1)          -> RED 16: R27-R32 x86_64 / PE, R34-R37
#   `_ret_slot_amp` without its inline test             -> RED 9: R17-R22 (this wording), A11-A13 (refused)
#   (`_hl_amp_sid`)
#   `_ret_slot_refuse` without `_tn_once`               -> RED 1: R39 (once per generic instance)
#   real tree                                           -> GREEN (43 refusal rows — floor 43 — and 27 acceptance rows)
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
# docs/development/issues/archived/2026-10-14-return-address-of-struct-local-decision.md
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
echo "=== return &q (6.7.14, the user's decision D19 (a), 2026-10-16): a handle's / *T's / untyped self's &q is its slot ==="
# `&q` of a handle, a `*T` or an untyped `self` is the address of q's own slot (the handle line), no pointer to a struct:
# refused by name at every size, ONE error at the `&`. Through 6.7.13 the 8 B form returned the slot's address as the
# struct's word (a dead frame's address read as c.v) and the 16 / 24 B forms were refused in other words ("... two
# registers ... got `this expression`", "return must be a bare local identifier ..."). Each of the handle / `*S` local /
# untyped `self` rows on the four compilers. docs/development/issues/archived/2026-10-15-return-address-of-handle-or-pointer-in-struct-fn.md
SLOT='is the address of'
refuse4 "R24 the filed repro verbatim (a handle, 8 B)" "$MS — \`&q\` $SLOT q's slot, not a struct — return q" 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct S8 { v; }
fn h(): S8 { var q: S8 = alloc(8); q.v = 3; return &q; }
fn main(): i64 { alloc_init(); var c: S8 = h(); return c.v == 3; }
syscall(60, main());
'
HQ='include "lib/alloc.cyr"
struct S16 { v; w; }
struct S24 { v; w; x; }
'
refuse4 "R25 return &q; (a handle) from : S16" "$MS — \`&q\` $SLOT q's slot, not a struct — return q" "$HQ"'fn h(): S16 { var q: S16 = alloc(16); q.v = 3; return &q; }
fn main(): i64 { alloc_init(); var c: S16 = h(); return c.v; }
syscall(60, main());
'
refuse4 "R26 return &q; (a handle) from : S24" "$MS — \`&q\` $SLOT q's slot, not a struct — return q" "$HQ"'fn h(): S24 { var q: S24 = alloc(24); q.v = 3; return &q; }
fn main(): i64 { alloc_init(); var c: S24 = h(); return c.v; }
syscall(60, main());
'
refuse4 "R27 return &p; (p: *S8, a local) from : S8" "$MS — \`&p\` $SLOT p's slot, not a struct — return p" "$T"'fn f(): S8 { var s: S8; s.v = 3; var p: *S8 = &s; return &p; }'"$E"
refuse4 "R28 return &p; (p: *S16, a local) from : S16" "$MS — \`&p\` $SLOT p's slot, not a struct — return p" "$HQ"'fn h(): S16 { var s: S16; s.v = 3; var p: *S16 = &s; return &p; }
fn main(): i64 { var c: S16 = h(); return c.v; }
syscall(60, main());
'
refuse4 "R29 return &p; (p: *S24, a local) from : S24" "$MS — \`&p\` $SLOT p's slot, not a struct — return p" "$HQ"'fn h(): S24 { var s: S24; s.v = 3; var p: *S24 = &s; return &p; }
fn main(): i64 { var c: S24 = h(); return c.v; }
syscall(60, main());
'
refuse4 "R30 return &self; (an untyped self) from : S8" "$MS — \`&self\` $SLOT self's slot, not a struct — return self" 'struct S8 { v; }
impl S8 { fn cp(self): S8 { return &self; } }
fn main(): i64 { var s: S8; s.v = 3; var c: S8 = s.cp(); return c.v; }
syscall(60, main());
'
refuse4 "R31 return &self; (an untyped self) from : S16" "$MS — \`&self\` $SLOT self's slot, not a struct — return self" 'struct S16 { v; w; }
impl S16 { fn cp(self): S16 { return &self; } }
fn main(): i64 { var s: S16; s.v = 3; var c: S16 = s.cp(); return c.v; }
syscall(60, main());
'
refuse4 "R32 return &self; (an untyped self) from : S24" "$MS — \`&self\` $SLOT self's slot, not a struct — return self" 'struct S24 { v; w; x; }
impl S24 { fn cp(self): S24 { return &self; } }
fn main(): i64 { var s: S24; s.v = 3; var c: S24 = s.cp(); return c.v; }
syscall(60, main());
'
# ... wrapped, a `*S` parameter, a `*S` global, a typed `self: *S`, a `*U` of another struct, a handle global (x86_64).
refuse "R33 return (&q); (a handle, wrapped) from : S8" "$MS — \`&q\` $SLOT q's slot, not a struct — return q" "$T"'fn f(): S8 { var q: S8 = alloc(8); q.v = 3; return (&q); }'"$E"
refuse "R34 return &p; (p: *S16, a parameter) from : S16" "$MS — \`&p\` $SLOT p's slot, not a struct — return p" "$HQ"'fn h2(p: *S16): S16 { return &p; }
fn main(): i64 { var s: S16; s.v = 3; var c: S16 = h2(&s); return c.v; }
syscall(60, main());
'
refuse "R35 return &GP; (GP: *S24, a global) from : S24" "$MS — \`&GP\` $SLOT GP's slot, not a struct — return GP" "$HQ"'var GS: S24 = S24 { 3, 4, 5 };
var GP: *S24 = &GS;
fn h(): S24 { return &GP; }
fn main(): i64 { var c: S24 = h(); return c.v; }
syscall(60, main());
'
refuse "R36 return &self; (self: *S16, typed) from : S16" "$MS — \`&self\` $SLOT self's slot, not a struct — return self" 'struct S16 { v; w; }
impl S16 { fn cp(self: *S16): S16 { return &self; } }
fn main(): i64 { var s: S16; s.v = 3; var c: S16 = s.cp(); return c.v; }
syscall(60, main());
'
refuse "R37 return &pu; (pu: *U8, another struct) from : S8" "$MS — \`&pu\` $SLOT pu's slot, not a struct — return pu" "$T"'fn f(): S8 { var u: U8; var pu: *U8 = &u; return &pu; }'"$E"
refuse "R38 return &GUH; (a handle global of U8) from : S8" "$MS — \`&GUH\` $SLOT GUH's slot, not a struct — return GUH" "$T"'fn f(): S8 { return &GUH; }'"$E"
# A generic fn's base and its three instances parse the same `return &q;`: reported once.
refuse "R39 return &q; in a generic fn, three instances" "$MS — \`&q\` $SLOT q's slot, not a struct — return q" 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct S8 { v; }
fn h<T>(x: T): S8 { var q: S8 = alloc(8); q.v = x; return &q; }
fn main(): i64 { alloc_init(); var c: S8 = h(3); var d: S8 = h<i32>(4); var e: S8 = h<i16>(5); return c.v; }
syscall(60, main());
'
accept "A14 return q; (q a handle: the advice) is the struct" "$T"'fn f(): S8 { var q: S8 = alloc(8); q.v = 24; return q; }'"$E" 24 \
    "$T"'fn f(): S8 { var u: S8; u.v = 24; return u; }'"$E"
accept "A11 return &u; (u: S8) is the struct" "$T"'fn f(): S8 { var u: S8; u.v = 21; return &u; }'"$E" 21 \
    "$T"'fn f(): S8 { var u: S8; u.v = 21; return u; }'"$E"
accept "A12 return (&u); (u: S3) is the struct" "$T"'fn f(): S3 { var u: S3; u.c = 22; return (&u); }'"$E3" 22 \
    "$T"'fn f(): S3 { var u: S3; u.c = 22; return u; }'"$E3"
accept "A13 return &p; (p: S8, a by-value parameter)" "$T"'fn f2(p: S8): S8 { return &p; }
fn f(): S8 { var u: S8; u.v = 23; return f2(u); }'"$E" 23 "$T"'fn f(): S8 { var u: S8; u.v = 23; return u; }'"$E"

echo "=== a replayed body's return inside a struct-returning fn (6.7.14): the callee's, never the caller's class ==="
# A small generic (or `#inline`) fn is REPLAYED at its call, re-parsed inside the caller; its `return` met the
# CALLER's struct-return class — `return GPA;` in `fn gpg<T>(): *T`, replayed in a `: P2` fn, was refused as
# "a fn returning the 9-16 byte struct `P2` ... got `GPA`", and in a `: P3` fn "struct-return: identifier is
# not a local"; a one-call body (`return gsel(sizeof(T));`) the same. The 8 B class was already exempt
# (`_ret_small_cls`'s GIDEP test, A10). issues/archived/2026-10-14-generic-instance-return-takes-enclosing-fns-struct-return-class.md
GR='struct P2 { x; y; }
struct P3 { x; y; z; }
struct B8 { v; }
var GS16 = B8 { 5 };
var GPA = 0;
fn gpg<T>(): *T { return GPA; }
'
GRE2='
fn main(): i64 { GPA = &GS16; var c: P2 = r(); return c.x; }
syscall(60, main());
'
GRE3='
fn main(): i64 { GPA = &GS16; var c: P3 = r(); return c.x; }
syscall(60, main());
'
GRE1='
fn main(): i64 { GPA = &GS16; var c: B8 = r(); return c.v; }
syscall(60, main());
'
GRC2="$GR"'fn r(): P2 { var q: *B8 = &GS16; var t: P2; t.x = q.v; return t; }'"$GRE2"
GRC3="$GR"'fn r(): P3 { var q: *B8 = &GS16; var t: P3; t.x = q.v; return t; }'"$GRE3"
GRC1="$GR"'fn r(): B8 { var q: *B8 = &GS16; var t: B8; t.v = q.v; return t; }'"$GRE1"
# The filed repro, verbatim.
GRR='struct P2 { x; y; }
struct P3 { x; y; z; }
struct B8 { v; }
var GS16 = B8 { 5 };
var GPA = 0;
fn gpg<T>(): *T { return GPA; }
fn r(): P2 { var q: *B8 = gpg<B8>(); var t: P2; t.x = q.v; return t; }
fn main(): i64 { GPA = &GS16; var c: P2 = r(); return c.x; }
syscall(60, main());
'
accept "RR1 the filed repro: gpg<B8>() in a : P2 fn (16 B)" "$GRR
" 5 "$GRC2"
accept "RR2 gpg<P2>() (T the enclosing struct) in a : P2 fn" "$GR"'fn r(): P2 { var q: *B8 = gpg<P2>(); var t: P2; t.x = q.v; return t; }'"$GRE2" 5 "$GRC2"
accept "RR3 gpg<i32>() (T a scalar) in a : P2 fn" "$GR"'fn r(): P2 { var q: *B8 = gpg<i32>(); var t: P2; t.x = q.v; return t; }'"$GRE2" 5 "$GRC2"
accept "RR4 gpg<B8>() in a : P3 fn (24 B, retptr)" "$GR"'fn r(): P3 { var q: *B8 = gpg<B8>(); var t: P3; t.x = q.v; return t; }'"$GRE3" 5 "$GRC3"
accept "RR5 gpg<P2>() in a : P3 fn" "$GR"'fn r(): P3 { var q: *B8 = gpg<P2>(); var t: P3; t.x = q.v; return t; }'"$GRE3" 5 "$GRC3"
accept "RR6 gpg<i32>() in a : P3 fn" "$GR"'fn r(): P3 { var q: *B8 = gpg<i32>(); var t: P3; t.x = q.v; return t; }'"$GRE3" 5 "$GRC3"
accept "RR7 control: gpg<B8>() in a : B8 fn (8 B)" "$GR"'fn r(): B8 { var q: *B8 = gpg<B8>(); var t: B8; t.v = q.v; return t; }'"$GRE1" 5 "$GRC1"
accept "RR8 control: gpg<i32>() in a : B8 fn" "$GR"'fn r(): B8 { var q: *B8 = gpg<i32>(); var t: B8; t.v = q.v; return t; }'"$GRE1" 5 "$GRC1"
accept "RR9 control: gpg<P2>() in an i64 fn" "$GR"'fn r(): i64 { var q: *B8 = gpg<P2>(); return q.v; }
fn main(): i64 { GPA = &GS16; return r(); }
syscall(60, main());
' 5 "$GR"'fn main(): i64 { GPA = &GS16; return GS16.v; }
syscall(60, main());
'
accept "RR10 control: the generic left uncalled beside a : P2 fn" "$GR"'fn r(): P2 { var t: P2; t.x = 5; return t; }'"$GRE2" 5 "$GRC2"
GS='struct P2 { x; y; }
struct P3 { x; y; z; }
struct B8 { v; }
fn gsel(n): i64 { return n; }
fn gz<T>(): i64 { return gsel(sizeof(T)); }
'
accept "RR11 a one-call body: return gsel(sizeof(T)); in a : P2 fn" "$GS"'fn r(): P2 { var t: P2; t.x = gz<B8>(); return t; }
fn main(): i64 { var c: P2 = r(); return c.x; }
syscall(60, main());
' 8 "$GS"'fn r(): P2 { var t: P2; t.x = 8; return t; }
fn main(): i64 { var c: P2 = r(); return c.x; }
syscall(60, main());
'
accept "RR12 ... in a : P3 fn" "$GS"'fn r(): P3 { var t: P3; t.x = gz<P3>(); return t; }
fn main(): i64 { var c: P3 = r(); return c.x; }
syscall(60, main());
' 24 "$GS"'fn r(): P3 { var t: P3; t.x = 24; return t; }
fn main(): i64 { var c: P3 = r(); return c.x; }
syscall(60, main());
'
# The replay is shared: a non-generic `#inline` fn's `return` was judged by the caller's class too.
accept "RR13 an #inline fn's return GPA; in a : P2 fn" 'struct P2 { x; y; }
struct B8 { v; }
var GS16 = B8 { 5 };
var GPA = 0;
#inline
fn gp(): *B8 { return GPA; }
fn r(): P2 { var q: *B8 = gp(); var t: P2; t.x = q.v; return t; }
fn main(): i64 { GPA = &GS16; var c: P2 = r(); return c.x; }
syscall(60, main());
' 5 "$GRC2"
# The filed repro and RR4 / RR11 / RR12 compile on the aarch64, cx and PE compilers too (the runtime legs:
# tests/tcyr/crossos/generic_ptr_struct_source.tcyr, small_struct_handle_line.sh R12).
builds4() {  # $1 label  $2 source — compiles, a binary written, on the aarch64, cx and PE compilers
    printf '%s' "$2" > "$D/b4.cyr"
    for l4 in aarch64 cx pe; do
        rc=0
        case $l4 in
            aarch64) "$D/cc_a64" < "$D/b4.cyr" > "$D/b4.bin" 2>"$D/b4.err" || rc=$? ;;
            cx)      "$D/cc_cx" < "$D/b4.cyr" > "$D/b4.bin" 2>"$D/b4.err" || rc=$? ;;
            pe)      CYRIUS_TARGET_WIN=1 "$CC" < "$D/b4.cyr" > "$D/b4.bin" 2>"$D/b4.err" || rc=$? ;;
        esac
        if [ "$rc" -eq 0 ] && [ -s "$D/b4.bin" ]; then printf '  ok(builds): %-46s\n' "$1 ($l4)"; pass=$((pass+1))
        else printf '  FAIL: %-50s rc=%s: %s\n' "$1 ($l4)" "$rc" "$(grep '^error' "$D/b4.err" | head -1)"; fail=$((fail+1)); fi
    done
}
builds4 "RR1 the filed repro" "$GRR
"
builds4 "RR4 gpg<B8>() in a : P3 fn" "$GR"'fn r(): P3 { var q: *B8 = gpg<B8>(); var t: P3; t.x = q.v; return t; }'"$GRE3"
builds4 "RR11 gsel body in a : P2 fn" "$GS"'fn r(): P2 { var t: P2; t.x = gz<B8>(); return t; }
fn main(): i64 { var c: P2 = r(); return c.x; }
syscall(60, main());
'
builds4 "RR12 gsel body in a : P3 fn" "$GS"'fn r(): P3 { var t: P3; t.x = gz<P3>(); return t; }
fn main(): i64 { var c: P3 = r(); return c.x; }
syscall(60, main());
'

echo "small_struct_return_type_refused: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$nrefuse" -ge 43 ] || { echo "FAIL: only $nrefuse refusal rows ran (floor 43) — rows were lost"; exit 1; }
[ "$naccept" -ge 27 ] || { echo "FAIL: only $naccept acceptance rows ran (floor 27) — rows were lost"; exit 1; }
[ "$fail" -eq 0 ] || exit 1
exit 0
