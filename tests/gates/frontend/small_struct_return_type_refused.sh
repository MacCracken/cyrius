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
# 6.7.15 (D58, measured 2026-10-18; R37 R38 on the four compilers, R38b-R38e; a one-edit scratch copy of the tree, its
# 2-stage mutant, the gate run from it):
#   `_ret_slot_refuse` advising "— return q" for every    -> RED 12: R37 R38 x4, R38b-R38e (the 6.7.14 words)
#   struct again
#   real tree                                           -> GREEN (47 refusal rows — floor 47 — and 27 acceptance rows)
# 6.7.15 (D18, measured 2026-10-18; R40-R46 on the four compilers, R47-R58, A15; the same scratch-tree mutants):
#   the lane before it (the D58 commit)                 -> RED 37: R40-R44 x4 (compiled, no diagnostic: the slot's
#                                                          address as c.v), R45 R46 x4 (the classes' own refusals),
#                                                          R47-R55
#   `_ret_slot_amp` without `_ret_amp_bare`             -> RED 31: R40-R42 R44-R52 R55 (R43, a `Str` handle, is the
#                                                          slot arm's)
#   `_ret_slot_amp` without the inline `Str` / tuple    -> RED 2: R53 (compiled), R54 (the retptr class's words)
#   kind-3 arm (0, as before)
#   `_ret_gen_base` answering 0 (the base refused)      -> RED 2: A15 (a generic used only at <S8> refused at its
#                                                          base), R56 (the base's error, then the instance's)
#   real tree                                           -> GREEN (66 refusal rows — floor 66 — and 28 acceptance rows)
#
# 6.7.16 — R11b-R11e: a dereference named as written, from its `*` (`*gu(pu)`, `*w.pu`; it was `*pu`), on the four
# compilers. Mutation (2026-10-19, a scratch tree with the src before the fix, the gate run from it):
#   the fix reverted                                    -> RED 16: R11b-R11e on each of the four legs
#   real tree                                           -> GREEN (70 refusal rows — floor 70 — and 28 acceptance rows)
# 6.7.16 — P1-P15, PC1-PC9: a 9-16 B fn's `return E;` reports E's own error alone, the class's refusal printed after E's
# parse (`_pair_ret_late`); every `^error` line compared, on the four compilers (`errs4`). Mutation (2026-10-20, a scratch
# copy of the tree, its 2-stage mutant, the gate run from it):
#   the tree before it (parse_fn.cyr at 8535eb44)       -> RED 68: P1-P15 (the refusal, then E's error: 2 lines), PC5
#                                                          PC7 (the same in their mk2 / mk) — each on the four legs
#   `_pair_ret_late` standing down on the file-wide     -> RED 8: PC3 PC7 (the refusal lost after an earlier
#   `_had_error` instead of the statement's `_err_n`       statement's error)
#   PARSE_RETURN not keeping a pending refusal across   -> RED 16: P13 P14 PC4 PC5 (the outer refusal printed by the
#   a return inside the value                              inner return, in its fn's context: "struct `struct`"; and
#                                                          P13 P14 then E's error)
#   `_pair_ret_late` not putting the cursor on E        -> RED 29: PC1-PC7 (the refusal at the `;`, "got `this
#                                                          expression`"), R1b
#   real tree                                           -> GREEN (94 refusal rows — floor 94 — and 28 acceptance rows)
# 6.7.16 — SX1-SX5, SXC1 SXC2 at 16 and 24 B: the method / operator arm (`_return_struct_expr`) refuses only a value whose
# parse reported nothing. Mutation (2026-10-20, as above):
#   its refusal not yielding to the value's error       -> RED 40: SX1-SX5 at 16 and 24 B (the error, then the
#   (the tree before it)                                   refusal: 2 lines), on the four legs
#   real tree                                           -> GREEN (108 refusal rows — floor 108 — and 28 acceptance rows)
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
refuse "R10 return u.dup(); (a method of another struct)" "$MS — got \`U8\.dup\` (a \`U8\`)" "$T"'fn f(): S8 { var u: U8; return u.dup(); }'"$E"
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
# 6.7.16 (issues/2026-10-18-struct-value-dereference-refusals-name-operand-last-name.md): a dereference is named as the
# source spells it — `*` and its operand's tokens; it was `*` and the operand's LAST name (`*pu` for `*gu(pu)` and
# `*w.pu`, `*GU` for `*gu(&GU)`). R11 `return *pu;` reads the same either way. Over 8 B (the pointer arm): struct_arg_type_refused.sh DS5 DS6.
DG='fn gu(p: *U8): *U8 { return p; }
struct WP { k; pu: *U8; }
'
refuse4 "R11b return *gu(pu); (the filed line)" "$MS — got \`\*gu(pu)\` (a \`U8\`)" "$T$DG"'fn f(): S8 { var u: U8; u.u = 13; var pu: *U8 = &u; return *gu(pu); }'"$E"
refuse4 "R11c return *w.pu; (a *U8 field)" "$MS — got \`\*w\.pu\` (a \`U8\`)" "$T$DG"'fn f(): S8 { var u: U8; u.u = 13; var w: WP; w.pu = &u; return *w.pu; }'"$E"
refuse4 "R11d return (*(pu));" "$MS — got \`\*(pu)\` (a \`U8\`)" "$T$DG"'fn f(): S8 { var u: U8; u.u = 13; var pu: *U8 = &u; return (*(pu)); }'"$E"
refuse4 "R11e return *gu(&GU); (a call on a global)" "$MS — got \`\*gu(&GU)\` (a \`U8\`)" "$T$DG"'fn f(): S8 { return *gu(&GU); }'"$E"
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
# ANOTHER struct's `*U` / handle (6.7.15, the user's D58, 2026-10-18): still refused, the advice reworded — the
# message said "— return pu", and `return pu;` is itself refused (R12: "got `pu` (a `*U8`)"); it now names what pu is.
# The full line is checked (`$` after the type): no "— return" tail.
refuse4 "R37 return &pu; (pu: *U8, another struct) from : S8" "$MS — \`&pu\` $SLOT pu's slot, not a struct, and pu is a \`\*U8\`\$" "$T"'fn f(): S8 { var u: U8; var pu: *U8 = &u; return &pu; }'"$E"
refuse4 "R38 return &GUH; (a handle global of U8) from : S8" "$MS — \`&GUH\` $SLOT GUH's slot, not a struct, and GUH is a \`U8\`\$" "$T"'fn f(): S8 { return &GUH; }'"$E"
refuse "R38b return &pu; (pu: *U16, a parameter) from : S16" "$MS — \`&pu\` $SLOT pu's slot, not a struct, and pu is a \`\*U16\`\$" 'struct S16 { v; w; }
struct U16 { a; b; }
fn h(pu: *U16): S16 { return &pu; }
fn main(): i64 { var u: U16; var c: S16 = h(&u); return c.v; }
syscall(60, main());
'
refuse "R38c return &q; (a handle of U24) from : S24" "$MS — \`&q\` $SLOT q's slot, not a struct, and q is a \`U24\`\$" 'include "lib/alloc.cyr"
struct S24 { v; w; x; }
struct U24 { a; b; c; }
fn h(): S24 { var q: U24 = alloc(24); return &q; }
fn main(): i64 { alloc_init(); var c: S24 = h(); return c.v; }
syscall(60, main());
'
refuse "R38d return &self; (an untyped self of U8) from : S8" "$MS — \`&self\` $SLOT self's slot, not a struct, and self is a \`\*U8\`\$" "$T"'impl U8 { fn cv(self): S8 { return &self; } }
fn f(): S8 { var u: U8; return u.cv(); }'"$E"
refuse "R38e return &ps; (ps: *Str) from : S8" "$MS — \`&ps\` $SLOT ps's slot, not a struct, and ps is a \`\*Str\`\$" 'include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
struct S8 { v; }
fn h(): S8 { var t = str_from("ab"); var ps: *Str = t; return &ps; }
fn main(): i64 { alloc_init(); var c: S8 = h(); return c.v; }
syscall(60, main());
'
echo "=== return &n (6.7.15, the user's decision D18, 2026-10-18): &n of a name holding no struct is its slot ==="
# `&n` of an integer, a `*i64` / `*V`, a `**S`, a `Str` handle, an array, a vector — a local, a parameter, a global — is
# the address of n's slot, no struct: refused by name at every size, ONE error at the `&`, with no "— return n" advice
# (the line ends at "not a struct"). Through 6.7.14 the 8 B form compiled with no diagnostic and the caller read the
# slot's address as c.v (a different byte each run: the filed table's 48 / 0, 248 / 56, 0 / 16, 96 / 144, 128 / 192),
# and over 8 B the classes refused it naming nothing ("... two registers ... got `this expression`", "return must be a
# bare local identifier ..."). An inline `Str` / tuple is the address of that aggregate: refused as `&u` of another
# struct (kind 3). docs/development/issues/archived/2026-10-17-return-address-of-scalar-or-non-struct-pointer-slot-in-struct-fn.md
NS="not a struct\$"
refuse4 "R40 the filed repro verbatim (&n, an integer, 8 B)" "$MS — \`&n\` $SLOT n's slot, $NS" 'include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct S { v; }
fn h(): S { var n = 5; return &n; }
fn main(): i64 { alloc_init(); var c = h(); return c.v; }
syscall(60, main());
'
NT='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/simd.cyr"
struct S { v; }
struct S16 { v; w; }
struct S24 { v; w; x; }
struct S3 { a: i8; b: i8; c: i8; }
var GN = 5;
'
NE='
fn main(): i64 { alloc_init(); var c: S = h(); return c.v; }
syscall(60, main());
'
refuse4 "R41 return &pi; (pi: *i64) from : S (8 B)" "$MS — \`&pi\` $SLOT pi's slot, $NS" "$NT"'fn h(): S { var n = 5; var pi: *i64 = &n; return &pi; }'"$NE"
refuse4 "R42 return &pp; (pp: **S) from : S (8 B)" "$MS — \`&pp\` $SLOT pp's slot, $NS" "$NT"'fn h(): S { var s: S; var p: *S = &s; var pp: **S = &p; return &pp; }'"$NE"
refuse4 "R43 return &t; (a Str handle) from : S (8 B)" "$MS — \`&t\` $SLOT t's slot, not a struct, and t is a \`Str\`\$" "$NT"'fn h(): S { var t = str_from("ab"); return &t; }'"$NE"
refuse4 "R44 return &pv; (pv: *f64v2) from : S (8 B)" "$MS — \`&pv\` $SLOT pv's slot, $NS" "$NT"'fn h(): S { var a: f64v2 = f64v2_make(1, 2); var pv: *f64v2 = &a; return &pv; }'"$NE"
refuse4 "R45 return &n; (an integer) from : S16" "$MS — \`&n\` $SLOT n's slot, $NS" "$NT"'fn h(): S16 { var n = 5; return &n; }
fn main(): i64 { var c: S16 = h(); return c.v; }
syscall(60, main());
'
refuse4 "R46 return &n; (an integer) from : S24" "$MS — \`&n\` $SLOT n's slot, $NS" "$NT"'fn h(): S24 { var n = 5; return &n; }
fn main(): i64 { var c: S24 = h(); return c.v; }
syscall(60, main());
'
refuse "R47 return &pn; (an untyped parameter) from : S" "$MS — \`&pn\` $SLOT pn's slot, $NS" "$NT"'fn h2(pn): S { return &pn; }
fn h(): S { return h2(5); }'"$NE"
refuse "R48 return &GN; (an integer global) from : S" "$MS — \`&GN\` $SLOT GN's slot, $NS" "$NT"'fn h(): S { return &GN; }'"$NE"
refuse "R49 return &buf; (an array) from : S" "$MS — \`&buf\` $SLOT buf's slot, $NS" "$NT"'fn h(): S { var buf[8]; return &buf; }'"$NE"
refuse "R50 return ((&n)); (wrapped) from : S16" "$MS — \`&n\` $SLOT n's slot, $NS" "$NT"'fn h(): S16 { var n = 5; return ((&n)); }
fn main(): i64 { var c: S16 = h(); return c.v; }
syscall(60, main());
'
refuse "R51 return &a; (an inline f64v2) from : S" "$MS — \`&a\` $SLOT a's slot, $NS" "$NT"'fn h(): S { var a: f64v2 = f64v2_make(1, 2); return &a; }'"$NE"
refuse "R52 return &f; (an f64) from : S3" "$MS — \`&f\` $SLOT f's slot, $NS" "$NT"'fn h(): S3 { var f: f64 = 1.5; return &f; }
fn main(): i64 { var c: S3 = h(); return c.a; }
syscall(60, main());
'
refuse "R53 return &t; (an inline Str) from : S: another struct" "$MS — got \`&t\` (a \`\*Str\`)" "$NT"'fn h(): S { var t: Str; t.data = 0; t.len = 0; return &t; }'"$NE"
refuse "R54 return &tu; (a tuple) from : S24: another aggregate" "$MS — got \`&tu\` (a \`\*(i64, i64)\`)" "$NT"'fn h(): S24 { var tu = (1, 2); return &tu; }
fn main(): i64 { var c: S24 = h(); return c.v; }
syscall(60, main());
'
refuse "R55 return &n; (n: T) in a generic, instances i32 / i16 / i64" "$MS — \`&n\` $SLOT n's slot, $NS" "$NT"'fn hg<T>(x: T): S { var n: T = x; return &n; }
fn h(): S { var c: S = hg<i32>(4); var d: S = hg<i16>(5); return hg(3); }'"$NE"
refuse "R56 return &n; (n: T) at <U8>: another struct" "$MS — got \`&n\` (a \`\*U8\`)" "$NT"'struct U8 { u; }
fn hg<T>(x: T): S { var n: T = x; return &n; }
fn h(): S { var u: U8; return hg<U8>(u); }'"$NE"
# What stays: a const's and an enum constant's `&` keep the factor's own refusal (one error).
refuse "R57 return &N; (a const) keeps its own refusal" "cannot take the address of const 'N'" "$NT"'const N = 3;
fn h(): S { return &N; }'"$NE"
refuse "R58 return &RED; (an enum constant) keeps its own refusal" "cannot take the address of enum constant 'RED'" "$NT"'enum Color { RED, GREEN }
fn h(): S { return &RED; }'"$NE"
# A generic's base is its i64 reading: `var n: T = x; return &n;` used only at `<S>` is D4 (a)'s struct, not refused.
accept "A15 return &n; (n: T) used only at <S8> is the struct" "$T"'fn hg<T>(x: T): S8 { var n: T = x; return &n; }
fn f(): S8 { var s: S8; s.v = 26; return hg<S8>(s); }'"$E" 26 "$T"'fn f(): S8 { var u: S8; u.v = 26; return u; }'"$E"
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

# 6.7.16 — THE VALUE'S OWN ERROR FIRST (issues/2026-10-18-pair-class-return-refusal-beside-the-values-own-error.md): a 9-16 B
# struct fn's `return E;` whose E reports an error of its own printed the class's refusal ("... two registers ... got `zz`")
# AND E's error, the refusal first (it was printed before E was parsed). It is printed after E's parse now, unless the
# statement reported an error since (`_pair_ret_late`, the statement's `_err_n`): one error, E's own, as the 8 B class
# gives. Every `^error` line is compared, in order, on the four compilers.
errs4() {  # $1 label  $2 source  $3... the exact `^error` lines, in order; no binary — x86_64, aarch64, cx and PE
    nrefuse=$((nrefuse+1))
    e4l=$1; printf '%s' "$2" > "$D/e4.cyr"; shift 2
    printf '%s\n' "$@" > "$D/e4.want"
    for l4 in x86_64 aarch64 cx pe; do
        rc=0
        case $l4 in
            x86_64)  "$CC" < "$D/e4.cyr" > "$D/e4.bin" 2>"$D/e4.err" || rc=$? ;;
            aarch64) "$D/cc_a64" < "$D/e4.cyr" > "$D/e4.bin" 2>"$D/e4.err" || rc=$? ;;
            cx)      "$D/cc_cx" < "$D/e4.cyr" > "$D/e4.bin" 2>"$D/e4.err" || rc=$? ;;
            pe)      CYRIUS_TARGET_WIN=1 "$CC" < "$D/e4.cyr" > "$D/e4.bin" 2>"$D/e4.err" || rc=$? ;;
        esac
        grep '^error' "$D/e4.err" > "$D/e4.got" 2>/dev/null || true
        if [ -s "$D/e4.bin" ]; then
            printf '  FAIL: %-50s emitted a binary (rc=%s)\n' "$e4l ($l4)" "$rc"; fail=$((fail+1))
        elif cmp -s "$D/e4.want" "$D/e4.got"; then
            printf '  ok(errors): %-46s %s line(s)\n' "$e4l ($l4)" "$(wc -l < "$D/e4.got" | tr -d ' ')"; pass=$((pass+1))
        else
            printf '  FAIL: %-50s %s error line(s), want %s: %s\n' "$e4l ($l4)" "$(wc -l < "$D/e4.got" | tr -d ' ')" \
                "$(wc -l < "$D/e4.want" | tr -d ' ')" "$(head -2 "$D/e4.got" | tr '\n' '|')"; fail=$((fail+1))
        fi
    done
}
PQ='struct Q { v; w; }
'
PM='
fn main(): i64 { var s: Q; var r: Q = mk(&s); return r.v; }
syscall(60, main());
'
PR='a fn returning the 9-16 byte struct `Q` is returned in two registers, so `return` takes a local of that struct or a call returning it — got'
UZ="undefined variable 'zz' (missing include or enum?)"
errs4 "P1 the filed repro verbatim (pr2): return zz;" 'struct Q { v; w; }
fn mk(q: *Q): Q { return zz; }
fn main(): i64 { var s: Q; var r: Q = mk(&s); return r.v; }
syscall(60, main());
' "error:<source>:2:28: $UZ"
errs4 "P2 return &(q);" "$PQ"'fn mk(q: *Q): Q { return &(q); }'"$PM" "error:<source>:2:27: expected identifier, got '('"
errs4 "P3 return 5 + ;" "$PQ"'fn mk(q: *Q): Q { return 5 + ; }'"$PM" "error:<source>:2:30: unexpected ';'"
errs4 "P4 return (zz);" "$PQ"'fn mk(q: *Q): Q { return (zz); }'"$PM" "error:<source>:2:29: $UZ"
errs4 "P5 return *zz;" "$PQ"'fn mk(q: *Q): Q { return *zz; }'"$PM" "error:<source>:2:29: $UZ"
errs4 "P6 return q.zz; (no such field)" "$PQ"'fn mk(q: *Q): Q { return q.zz; }'"$PM" "error:<source>:2:30: unknown field 'zz' on struct 'Q'"
errs4 "P7 return zz.v;" "$PQ"'fn mk(q: *Q): Q { return zz.v; }'"$PM" "error:<source>:2:30: undefined variable 'zz'"
errs4 "P8 return &zz;" "$PQ"'fn mk(q: *Q): Q { return &zz; }'"$PM" "error:<source>:2:29: undefined variable 'zz'"
errs4 "P9 return q.v + zz;" "$PQ"'fn mk(q: *Q): Q { return q.v + zz; }'"$PM" "error:<source>:2:34: $UZ"
errs4 "P10 return (5 + );" "$PQ"'fn mk(q: *Q): Q { return (5 + ); }'"$PM" "error:<source>:2:31: unexpected ')'"
errs4 "P11 a generic's return zz; at three types: once" "$PQ"'fn mk<T>(q: T): Q { return zz; }
fn main(): i64 { var s: Q; var r: Q = mk(&s); var r2: Q = mk(5); var r3: Q = mk<i32>(5); return r.v; }
syscall(60, main());
' "error:<source>:2:30: $UZ"
errs4 "P12 an error in a closure body inside the value" 'include "lib/fnptr.cyr"
'"$PQ"'fn mk(q: *Q): Q { return fncall1(|x| { return x + zz; }, 5); }'"$PM" "error:<source>:3:53: $UZ"
errs4 "P13 a closure's return, then the value's own error" "$PQ"'fn ap(f, x) { return x; }
fn mk(q: *Q): Q { return ap(|x| { return x; }, zz); }'"$PM" "error:<source>:3:50: $UZ"
errs4 "P14 an #inline replay's return, then the value's own error" "$PQ"'#inline
fn one(x): i64 { return x + 1; }
fn ap(a, b) { return a; }
fn mk(q: *Q): Q { return ap(one(5), zz); }'"$PM" "error:<source>:5:39: $UZ"
errs4 "P15 an earlier statement in error: one error per statement" "$PQ"'fn mk(q: *Q): Q { var a = yy; return zz; }'"$PM" \
    "error:<source>:2:29: undefined variable 'yy' (missing include or enum?)" "error:<source>:2:40: $UZ"
# Unchanged: a value that parses keeps the class's refusal — after an earlier statement's error too, beside a closure's
# or an #inline replay's own return, at a generic's every instance once — and the 8 B / 24 B classes their own error.
errs4 "PC1 control: return 5; keeps the refusal" "$PQ"'fn mk(q: *Q): Q { return 5; }'"$PM" "error:<source>:2:26: $PR \`5\`"
errs4 "PC2 control: return t; (a scalar local) keeps it" "$PQ"'fn mk(q: *Q): Q { var t = 3; return t; }'"$PM" \
    "error:<source>:2:37: $PR \`t\`"
errs4 "PC3 control: an earlier statement in error, then return 5;" "$PQ"'fn mk(q: *Q): Q { var a = yy; return 5; }'"$PM" \
    "error:<source>:2:29: undefined variable 'yy' (missing include or enum?)" "error:<source>:2:38: $PR \`5\`"
errs4 "PC4 control: a closure's own return inside the value" "$PQ"'fn ap(f, x) { return x; }
fn mk(q: *Q): Q { return ap(|x| { return x; }, 5); }'"$PM" "error:<source>:3:26: $PR \`ap\`"
errs4 "PC5 control: an #inline replay's return inside the value" "$PQ"'#inline
fn one(x): i64 { return x + 1; }
fn mk(q: *Q): Q { return one(5); }
fn mk2(q: *Q): Q { return one(zz); }'"$PM" "error:<source>:4:26: $PR \`one\`" "error:<source>:5:33: $UZ"
errs4 "PC6 control: a generic's return 5; at three types: once" "$PQ"'fn mk<T>(q: T): Q { return 5; }
fn main(): i64 { var s: Q; var r: Q = mk(&s); var r2: Q = mk(5); var r3: Q = mk<i32>(5); return r.v; }
syscall(60, main());
' "error:<source>:2:28: $PR \`5\`"
errs4 "PC7 control: three statements, three errors" "$PQ"'fn mk(q: *Q): Q { if (q.v == 1) { return zz; } return 5; }
fn mk2(q: *Q): Q { return 6 + ; }'"$PM" "error:<source>:2:44: $UZ" "error:<source>:2:55: $PR \`5\`" \
    "error:<source>:3:31: unexpected ';'"
errs4 "PC8 control: the 8 B class's return zz;" 'struct Q { v; }
fn mk(q: *Q): Q { return zz; }'"$PM" "error:<source>:2:28: $UZ"
errs4 "PC9 control: the 24 B class's return zz;" 'struct Q { v; w; x; }
fn mk(q: *Q): Q { return zz; }'"$PM" "error:<source>:2:26: struct-return: identifier is not a local"

# ... and the method / operator arm both struct classes share (`_return_struct_expr`): its refusal ("struct-return fn:
# return must be a bare local identifier ...") followed a value that had reported its own error — `return zz + 1;`,
# `return q.e(zz);` at 16 and at 24 B were that error AND the refusal. The error alone now; a value that parses keeps it.
SX='impl Q { fn e(self, n): i64 { return n; } }
fn mk2(n): i64 { return n; }
'
SR='struct-return fn: return must be a bare local identifier, or a call to a fn returning the same struct'
for sxz in 16 24; do
    if [ "$sxz" = 16 ]; then SQ="$PQ$SX"; else SQ='struct Q { v; w; x; }
'"$SX"; fi
    errs4 "SX1 return zz + 1; ($sxz B)" "$SQ"'fn mk(q: *Q): Q { return zz + 1; }'"$PM" "error:<source>:4:29: $UZ"
    errs4 "SX2 return zz - q; ($sxz B)" "$SQ"'fn mk(q: *Q): Q { return zz - q; }'"$PM" "error:<source>:4:29: $UZ"
    errs4 "SX3 return (zz) + 1; ($sxz B)" "$SQ"'fn mk(q: *Q): Q { return (zz) + 1; }'"$PM" "error:<source>:4:29: $UZ"
    errs4 "SX4 return q.e(zz); ($sxz B, a scalar method)" "$SQ"'fn mk(q: *Q): Q { return q.e(zz); }'"$PM" "error:<source>:4:32: $UZ"
    errs4 "SX5 return mk2(zz) + 1; ($sxz B)" "$SQ"'fn mk(q: *Q): Q { return mk2(zz) + 1; }'"$PM" "error:<source>:4:32: $UZ"
    errs4 "SXC1 control: return q.e(1); keeps the refusal ($sxz B)" "$SQ"'fn mk(q: *Q): Q { return q.e(1); }'"$PM" \
        "error:<source>:4:32: $SR"
    errs4 "SXC2 control: return mk2(1) + 1; keeps it ($sxz B)" "$SQ"'fn mk(q: *Q): Q { return mk2(1) + 1; }'"$PM" \
        "error:<source>:4:36: $SR"
done

# 6.7.16 (the receives review) — AND THE VECTOR CLASS'S 6.6.6 RULE (`_ret_vec_rule`): its refusal ("a vector-returning fn
# carries its result in a fixed register pair ... got `zz`") was printed before the value was parsed, so a vector fn's
# `return zz;`, `return &(q);`, `return 5 + ;`, `return zz + 1;`, `return (zz);`, `return q.zz;` were the refusal AND the
# value's own error. It is pending until the value is parsed now (`_pair_ret_late`, kind 2), as the 9-16 B class's is: the
# value's own error alone; a value that parses keeps the refusal (VEC1-VEC7: a literal, a scalar local, after an earlier
# statement's error, beside a closure's own return, at a generic's every instance once, three statements three errors).
# f64v2 and f64v4, on the four compilers. VE8 / VEC5 (6.7.16, met with them): an `#inline` callee's `return` replayed
# inside a vector fn is the callee's (`_inl_replay_body` masks the caller's vector class, as 6.7.14 masked its struct
# class) — it was judged by the vector rule at the callee's line ("2:25: ... got `x`", and a valid fn storing
# `one(40)` into its own vector local was refused: crossos/simd_value_return_binding.tcyr group K). Mutations (2026-10-20,
# measured):
#   `_inl_replay_body` without the vector mask (the tree before) -> RED 16: VE8 and VEC5 at both widths on the four legs
#       ("2:25: ... got `x`" first)
#   `_ret_vec_rule` refusing before the value's parse (the tree before) -> RED 96: VE1-VE10, VEC5, VEC7 at both widths
#       on the four legs (the refusal, then the value's error)
VR='a vector-returning fn carries its result in a fixed register pair, so `return` takes a local of that vector type or a call to a fn declared to return the same one — got'
for vt in f64v2 f64v4; do
    VM='
fn main(): i64 { var s: '"$vt"'; var r: '"$vt"' = mk(&s); return load64(&r); }
syscall(60, main());
'
    errs4 "VE1 return zz; ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { return zz; }'"$VM" "error:<source>:1:36: $UZ"
    errs4 "VE2 return &(q); ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { return &(q); }'"$VM" "error:<source>:1:35: expected identifier, got '('"
    errs4 "VE3 return 5 + ; ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { return 5 + ; }'"$VM" "error:<source>:1:38: unexpected ';'"
    errs4 "VE4 return zz + 1; ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { return zz + 1; }'"$VM" "error:<source>:1:37: $UZ"
    errs4 "VE5 return (zz); ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { return (zz); }'"$VM" "error:<source>:1:37: $UZ"
    errs4 "VE6 return q.zz; ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { return q.zz; }'"$VM" \
        "error:<source>:1:38: no struct type in scope for 'q'; a '.field' access needs its struct declaration (missing include?)"
    errs4 "VE7 a closure's return, then the value's own error ($vt)" 'fn ap(f, x) { return x; }
fn mk(q: *'"$vt"'): '"$vt"' { return ap(|x| { return x; }, zz); }'"$VM" "error:<source>:2:58: $UZ"
    errs4 "VE9 an earlier statement in error: one error per statement ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { var a = yy; return zz; }'"$VM" \
        "error:<source>:1:37: undefined variable 'yy' (missing include or enum?)" "error:<source>:1:48: $UZ"
    errs4 "VE10 a generic's return zz; at three types: once ($vt)" 'fn mk<T>(q: T): '"$vt"' { return zz; }
fn main(): i64 { var s: '"$vt"'; var r: '"$vt"' = mk(&s); var r2: '"$vt"' = mk(5); var r3: '"$vt"' = mk<i32>(5); return load64(&r); }
syscall(60, main());
' "error:<source>:1:34: $UZ"
    errs4 "VEC1 control: return 5; keeps the refusal ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { return 5; }'"$VM" "error:<source>:1:34: $VR \`5\`"
    errs4 "VEC2 control: return t; (a scalar local) keeps it ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { var t = 3; return t; }'"$VM" \
        "error:<source>:1:45: $VR \`t\`"
    errs4 "VEC3 control: an earlier statement in error, then return 5; ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { var a = yy; return 5; }'"$VM" \
        "error:<source>:1:37: undefined variable 'yy' (missing include or enum?)" "error:<source>:1:46: $VR \`5\`"
    errs4 "VEC4 control: a closure's own return inside the value ($vt)" 'fn ap(f, x) { return x; }
fn mk(q: *'"$vt"'): '"$vt"' { return ap(|x| { return x; }, 5); }'"$VM" "error:<source>:2:34: $VR \`ap\`"
    errs4 "VEC6 control: a generic's return 5; at three types: once ($vt)" 'fn mk<T>(q: T): '"$vt"' { return 5; }
fn main(): i64 { var s: '"$vt"'; var r: '"$vt"' = mk(&s); var r2: '"$vt"' = mk(5); var r3: '"$vt"' = mk<i32>(5); return load64(&r); }
syscall(60, main());
' "error:<source>:1:32: $VR \`5\`"
    errs4 "VE8 an #inline replay's return, then the value's own error ($vt)" '#inline
fn one(x): i64 { return x + 1; }
fn ap(a, b) { return a; }
fn mk(q: *'"$vt"'): '"$vt"' { return ap(one(5), zz); }'"$VM" "error:<source>:4:47: $UZ"
    errs4 "VEC5 control: an #inline replay's return inside the value is the callee's ($vt)" '#inline
fn one(x): i64 { return x + 1; }
fn mk(q: *'"$vt"'): '"$vt"' { return one(5); }
fn mk2(q: *'"$vt"'): '"$vt"' { return one(zz); }'"$VM" "error:<source>:3:34: $VR \`one\`" "error:<source>:4:41: $UZ"
    errs4 "VEC7 control: three statements, three errors ($vt)" 'fn mk(q: *'"$vt"'): '"$vt"' { if (load64(q) == 1) { return zz; } return 5; }
fn mk2(q: *'"$vt"'): '"$vt"' { return 6 + ; }'"$VM" "error:<source>:1:58: $UZ" "error:<source>:1:69: $VR \`5\`" \
        "error:<source>:2:39: unexpected ';'"
done

# 6.7.16 (met with the vector rule's rows) — AND A TUPLE LITERAL'S: the multi-value arm printed "a fn returning the
# struct `Q` returns that struct — `(a, b)` is a tuple" (6.7.11) / the vector rule (6.6.6) before the literal was parsed,
# so `return (zz, 1);` was that AND "undefined variable 'zz'" at 8, 16 and 24 B and in a vector fn. Pending until the
# arm has parsed the literal now (`_ret_tup_defer`, `_pair_ret_late` kind 3): the element's error alone (TU1-TU5); a
# literal of four or more values gives the class's refusal once, where it was that and "multi-value return needs 2 or 3
# types" (TU6 / TU7); a literal that parses keeps the refusal, and a scalar fn keeps the arity error (TUC1-TUC4). Mutation
# (2026-10-20, measured):
#   the arm refusing before the literal's parse, the arity error unguarded (the tree before) -> RED 28: TU1-TU7 on the
#       four legs
TT='a fn returning the struct `Q` returns that struct — '
TM='
fn main(): i64 { return 0; }
syscall(60, main());
'
errs4 "TU1 return (zz, 1); (16 B)" 'struct Q { v; w; }
fn mk(q: *Q): Q { return (zz, 1); }'"$TM" "error:<source>:2:29: $UZ"
errs4 "TU2 return (zz, 1); (8 B)" 'struct Q { v; }
fn mk(q: *Q): Q { return (zz, 1); }'"$TM" "error:<source>:2:29: $UZ"
errs4 "TU3 return (zz, 1); (24 B)" 'struct Q { v; w; x; }
fn mk(q: *Q): Q { return (zz, 1); }'"$TM" "error:<source>:2:29: $UZ"
errs4 "TU4 return (1, 5 + ); (f64v2)" 'fn mk(q: *f64v2): f64v2 { return (1, 5 + ); }'"$TM" "error:<source>:1:42: unexpected ')'"
errs4 "TU5 return (zz, 1, 2); (f64v4)" 'fn mk(q: *f64v4): f64v4 { return (zz, 1, 2); }'"$TM" "error:<source>:1:37: $UZ"
errs4 "TU6 return (1, 2, 3, 4); (16 B): the class's refusal once" 'struct Q { v; w; }
fn mk(q: *Q): Q { return (1, 2, 3, 4); }'"$TM" "error:<source>:2:26: $TT\`(a, b, c)\` is a tuple, another type"
errs4 "TU7 return (1, 2, 3, 4); (f64v2): the class's refusal once" 'fn mk(q: *f64v2): f64v2 { return (1, 2, 3, 4); }'"$TM" \
    "error:<source>:1:34: $VR \`(...)\`"
errs4 "TUC1 control: return (1, 2); keeps the refusal (16 B)" 'struct Q { v; w; }
fn mk(q: *Q): Q { return (1, 2); }'"$TM" "error:<source>:2:26: $TT\`(a, b)\` is a tuple, another type"
errs4 "TUC2 control: return (1, 2); keeps the refusal (f64v2)" 'fn mk(q: *f64v2): f64v2 { return (1, 2); }'"$TM" \
    "error:<source>:1:34: $VR \`(...)\`"
errs4 "TUC3 control: a scalar fn's return (1, 2, 3, 4); keeps the arity error" 'fn mk(q): i64 { return (1, 2, 3, 4); }'"$TM" \
    "error:<source>:1:24: multi-value return needs 2 or 3 types"
errs4 "TUC4 control: an earlier statement in error, then return (1, 2);" 'struct Q { v; w; }
fn mk(q: *Q): Q { var a = yy; return (1, 2); }'"$TM" "error:<source>:2:29: undefined variable 'yy' (missing include or enum?)" \
    "error:<source>:2:38: $TT\`(a, b)\` is a tuple, another type"

echo "small_struct_return_type_refused: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
[ "$nrefuse" -ge 153 ] || { echo "FAIL: only $nrefuse refusal rows ran (floor 153) — rows were lost"; exit 1; }
[ "$naccept" -ge 28 ] || { echo "FAIL: only $naccept acceptance rows ran (floor 28) — rows were lost"; exit 1; }
[ "$fail" -eq 0 ] || exit 1
exit 0
