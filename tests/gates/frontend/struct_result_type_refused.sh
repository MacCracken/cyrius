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
#       word: `p = mkq()` (24 B), `p = mkr()` (16 B), `z = mkod2()` (3 B), generic `s = mk(r.n)`
#       (the scalar field infers T = i64, so the call reaches Box<i64>, not Box<Pt>). The
#       declarations `var z: Odd = mkod2()` and `var s: Box<Pt> = mk(r.n)` were not refused by
#       name either — only the retptr / rax:rdx receives compared the sid. Root cause:
#       `_try_struct_call_assign` (src/frontend/parse.cyr) exited at `cls == 0`, `n <= 1` and
#       the sid test with `return 0` = the scalar store.
#       At TOP LEVEL the same mismatch compiled clean at 9-16 B too (`var GZ: Pt = mkr()`,
#       `= GQ.mr()`: no frame, so no receive compared the sid; the binary SIGSEGV'd reading GZ.x),
#       and the LEADING declaration block — replayed by EMIT_GVAR_INITS, not PARSE_VAR — checked
#       nothing at any size. Fixed in `_scv_call_check` (9-16 B at top level),
#       `_sc_global_mismatch` (-3 and -1) and `_gvi_ann` / `_gvi_expr` (the leading block).
#       (6.6.11's rows read `mk(r.v)`, the inline Pt field, which inferred i64 then; since 6.7.17 a struct-typed field
#       binds its struct — the user's D2, 2026-10-22 — so `mk(r.v)` reaches Box<Pt> and is accepted: AGa / DGa, its
#       value 7. The tree before D2 (3e8756f2a) -> RED AGa DGa, refused "a different struct type".)
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
#     (historical: since 6.7.16's D99 the store through `p` IS a stub line, `_gs_dsr_stmt` — MDP4 below)
# 6.7.16 — D1 AT A GENERIC CALLEE (TG13-TG22, TA7-TA10, TGX TG13 / TG17 on aarch64 / cx / PE): its result is read at the
# binding its call, method or operator makes (`_gs_gcall`, `_gs_mret`, `_gs_opg` — the operator's since D85 (a) calls
# that instance). (Each mutant: a scratch copy of the tree with the one change, its cycc built from it, this gate run
# from the copy; 2026-10-21.)
#   MTG8 the tree before (6bc8e2206)                    -> RED 16: TG13-TG22 (compiled, no diagnostic), TGX TG13 / TG17
#                                                         on aarch64 / cx / PE
#   MTG9 `_gs_gcall` answering `_tok_init_sid`'s        -> RED 8: TG13 TG14 TG19 TG20 TG22, TGX TG13 x3
#   MTG10 `_gs_mret` answering `_gs_ret_sid`'s          -> RED 2: TG15 TG16
#   MTG11 `_gs_opg` answering the base's GFRS           -> RED 6: TG17 TG18 TG21, TGX TG17 x3
#   MTG12 `_gs_mtp` without `_cam_open` (parameter k read at position k) -> RED 2: TG15 TG16
# 6.7.16 (D99, the user's decision, 2026-10-20; issues/archived/2026-10-20-dereference-store-of-struct-result-keeps-first-word.md) —
# A STRUCT RESULT OVER 8 B STORED THROUGH A POINTER TO A SCALAR is refused, "cannot assign '*p: i64' from 'mkp', which
# returns the struct 'Q' - store it through a '*Q' or bind a field" (`_dsr_sres`, src/frontend/parse.cyr), and in a
# generic a store through a name reading T is a stub line (`_gs_dsr_stmt`): DP0 the filed repro verbatim (its one error,
# at 6:44), DP1-DP21 (DP18b), DPK1-DPK4; TA6 / TA6n / TA6b / TA6c re-pinned (they compiled: the review's R1 had taken the
# line out of D1's), TA11 a carrier's `*T` field, TA12 `*(p + 0)`, TA13 the base parse judges no T-typed store (a chain
# the scan reads no struct from); DPX DP0 / TA6 / DP9 / DP13 on aarch64 / cx / PE. (Each mutant: a scratch copy of the
# tree with the one change, its cycc built from it, this gate run from the copy; 2026-10-21.)
#   MDP1 the tree before (94a79ff72)                    -> RED 42: TA6 TA6n TA6b TA6c TA11 TA12, DP0-DP21 (24 rows,
#                                                         compiled), DPX x12
#   MDP2 `_dsr_sres` answering 0                        -> RED 33: DP0-DP21, DPX DP0 / DP9 / DP13 x3
#   MDP3 `_dsr_tdep` answering 0 (no T skip in a base)  -> RED 1: TA13 (refused at the generic's definition)
#   MDP4 `_gs_dsr_stmt` answering 0                     -> RED 9: TA6 TA6n TA6b TA6c TA11 TA12, DPX TA6 x3
#   MDP5 `_gs_dsr_dep` reading no annotation's T        -> RED 1: TA11 (the carrier `w: Wt<T>`)
#   MDP6 `_dsr_amp` answering 0                         -> RED 2: DP20 DP20b
#   MDP7 `_dsr_call` answering -1 (records only)        -> RED 25: every free-call row (DP0-DP12 DP17-DP21), DPX x6
# 6.7.16 (the s16 review) — D99'S SUBSCRIPT STORE `p[i] = mkp();` (`_dsr_esub`, `_esub_assign`) and its stub line
# (`_gs_sub_sres`): DS1-DS11, DSK1-DSK3, TA15 / TA15n / TA15b / TA15c, DSX DS1 / DS3 / TA15 on aarch64 / cx / PE.
# (2026-10-21, measured as above:)
#   MDS7 the tree before (75e50e3cf)                    -> RED 23: DS1-DS11 TA15 TA15n TA15b, DSX x3 x3
#   MDS8 `_dsr_esub` answering 0                        -> RED 17: DS1-DS11, DSX DS1 / DS3 x3
#   MDS9 `_gs_sub_sres` answering 0                     -> RED 6: TA15 TA15n TA15b, DSX TA15 x3
# 6.7.16 (met beside D99) — THE STUB SCAN READS EVERY STRUCT RESULT THE PARSE TYPES: an operator chain `a + c + a`
# (`_gs_top_op`: the operator applied last, its left side's struct `_gs_sres`), a receiver in parentheses `(a + c).mk()`
# (`_gs_recv_wrap`), a generic call or method as a receiver (`_gs_rcall_g`, `_gs_mret`), a local from a generic call
# (`_gs_recv_gvar`) — each generic compiled at i64 and kept the first word. TG23-TG25c, TA14 / TA14b. (2026-10-21, as above:)
#   MDS1 the tree before (b86a3cb01)                    -> RED 8: TG23 TG23b TG23c TG24 TG24b TG25 TG25b TG25c
#   MDS2 `_gs_top_op` taking one operator only          -> RED 3: TG23 TG23b TG23c
#   MDS3 `_gs_recv_wrap` answering 0                    -> RED 2: TG24 TG24b
#   MDS4 `_gs_rcall_g` answering 0                      -> RED 2: TG25b TG25c
#   MDS5 `_gs_recv_gvar` answering 0                    -> RED 1: TG25c
#   MDS6 `_gs_recv_call` without its generic method arm -> RED 1: TG25
#   (MDP3 re-measured: GREEN — TA13's `gdo` is a stub now, its base not parsed; `_dsr_tdep` is the base parse's guard
#   for a T-typed store the scan would read no struct from, and no row reaches it)
# 6.7.17 (D13, the user's decision, 2026-10-22; issues/2026-10-21-struct-and-pointer-shapes-beyond-d97-d99-take-a-word.md
# row B1) — THE SAME STORE THROUGH AN UNTYPED POINTER is refused in D99's words without the type, "cannot assign '*p'
# from 'mkp', which returns the struct 'Q' - store it through a '*Q' or bind a field" (`_dsr_untyped`, parse.cyr): UP0
# the filed repro verbatim (exit 77 through 6.7.16: Q's first word), UP1-UP13 (`alloc`, `*(p + 8)`, an untyped global,
# top level, a method, an operator, wrapped, `fncall0(&mkp)`, 24 B, a for step, an untyped parameter, a capture, a
# generic), UPK1-UPK5 (a field of the result, 8 B, a `Str`, `*(&q)`, a word); UPX UP0 / UP5 on aarch64 / cx / PE.
# (A scratch copy of the tree with the one change, its cycc built from it, this gate run from the copy; 2026-10-22:)
#   MUP1 `_dsr_untyped` answering 0 (the tree before)   -> RED 20: UP0-UP13 (compiled), UPX x6
# 6.7.17 (D16, the user's decision, 2026-10-22; the same issue, row B4) — INTO A SCALAR OR POINTER FIELD AND AN ARRAY'S
# ELEMENT: "cannot assign 'w.n: i64' from 'mkp', which returns the struct 'Q' - store it through a '*Q' or bind a field"
# (`_dsr_fld` from `_fst_on`, `_dsr_earr` from `_dsr_esub`, `_dsr_lit` from EMIT_STRUCT_FIELD_W, `_dsr_slf` from
# `_slice_fld_store`; the stub scan's `_gs_fst_sres` / `_gs_lit_sres` for a T-typed field or generic literal): FE0-FE0c
# the filed repros verbatim (77; the globals' two lines, 154), FE1-FE17c, FE18-FE19 generics, FEK1-FEK7; FEX FE1 / FE15b
# / FE17 / FE18 on aarch64 / cx / PE. FEK5 was refused at the generic's definition before ("field 'v' is not a struct":
# the base parsed `b.v.b` of an untyped `Box<T>` literal); the literal's stub line leaves it to the instance. (2026-10-22:)
#   MFE1 the tree before (D13's commit)                 -> RED 43: FE0-FE19 (each compiled), FEK5, FEX x12
#   MFE2 `_dsr_fld` answering 0                         -> RED 21: FE0 FE0c FE1-FE14 FE19, FEX FE1 x3
#   MFE3 `_dsr_earr` answering 0                        -> RED 9: FE0b FE0c (its second line) FE15-FE15c, FEX FE15b x3
#   MFE4 `_dsr_lit` answering 0                         -> RED 6: FE17-FE17c, FEX FE17 x3
#   MFE5 `_dsr_slf` answering 0                         -> RED 1: FE16
#   MFE6 `_gs_fst_sres` answering 0                     -> RED 5: FE18 FE18b (compiled: the base kept the word), FEX FE18 x3
#   MFE7 `_gs_lit_sres` answering 0                     -> RED 2: FE18c (compiled), FEK5 (refused at the definition)
# 6.7.17 (D15, the user's decision, 2026-10-22; the same issue, row B3) — A COMPOUND ASSIGNMENT `OP=` WITH A STRUCT RESULT
# OVER 8 B ON ITS RIGHT is refused with its `=` form's words (`_cop_sres` from `_asg_compound_op`, every OP= site; the
# field, slice and element sites name their destination through `_cop_dst`): CO0 the filed repro verbatim (116 through
# 6.7.16; its two lines), CO1-CO19, CO8w no float warning beside the refusal, COK1-COK3; COX CO5 / CO7 on aarch64 / cx /
# PE. (2026-10-22, as above:)
#   MCO1 `_cop_sres` answering 0 (the tree before)      -> RED 28: CO0 (both lines) CO1-CO19 CO8w (compiled), COX x6
#   MCO2 `_fld_compound` without its `_cop_dst = 1`     -> RED 8: CO7 CO8 CO8w CO9 CO19, COX CO7 x3
#   MCO3 `_esub_assign` without its `_cop_dst`          -> RED 2: CO10 CO11 (an array's element; `p[0]` judged by its word)
#   MCO4 `_slice_fld_store` without its `_cop_dst = 2`  -> RED 1: CO14
#   MCO5 the float arm warning beside a refusal         -> RED 1: CO8w
#   (the review, 2026-10-22: CO20-CO24 the same stores through a generic's T at a scalar instance, a stub as their `=`
#   forms are; COK4 / COK5; COX CO21 on aarch64 / cx / PE)
#   (each a scratch copy of src / lib / tests / programs — the AS0 rows read docs/, so they are red in every copy)
#   MCO6 the tree before it (the integration head)      -> RED 9: CO20-CO24 (compiled, the first word added: 78), CO24b
#                                                          (the i32 instance's own "cannot assign 'y: T'"), COX CO21 x3
#   MCO7 `_gs_cop_de` answering eq (no compound pair)   -> RED 6: CO21-CO23, COX CO21 x3
#   MCO8 `_gs_cop_asg` answering 0                      -> RED 3: CO20 CO24 CO24b
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
refuse "AG  s = mk(r.n)  (generic)" "$MA" "$G"'fn main(): i64 { var r: RB; r.v.x = 2; r.v.y = 7; r.n = 1; var s: Box<Pt>; s.n = 0; s = mk(r.n); return s.n; }'"$E"
refuse "D3m var z: Odd = y.same()" "$MD" "$T"'fn main(): i64 { var y: Od2; var z: Odd = y.same(); return 0; }'"$E"
refuse "D3o var z: Odd = y + y" "$MD" "$T"'fn main(): i64 { var y: Od2; var z: Odd = y + y; return 0; }'"$E"
refuse "D8m var z: P8 = y.mq()" "$MD" "$T"'fn main(): i64 { var y: Q8; var z: P8 = y.mq(); return 0; }'"$E"
refuse "D3c var z: Odd = mkod2()" "$MD" "$T"'fn main(): i64 { var z: Odd = mkod2(); return 0; }'"$E"
refuse "D8c var z: P8 = mkq8()" "$MD" "$T"'fn main(): i64 { var z: P8 = mkq8(); return 0; }'"$E"
refuse "D16 var p: Pt = mkr()" "$MD" "$T"'fn main(): i64 { var p: Pt = mkr(); return p.x; }'"$E"
refuse "D24 var p: Pt = mkq()" "$MD" "$T"'fn main(): i64 { var p: Pt = mkq(); return p.x; }'"$E"
refuse "DG  var s: Box<Pt> = mk(r.n)" "$MD" "$G"'fn main(): i64 { var r: RB; r.v.x = 2; r.v.y = 7; r.n = 1; var s: Box<Pt> = mk(r.n); return s.n; }'"$E"
# 6.7.17 (D2): the inline Pt field binds Pt, so mk(r.v) reaches Box<Pt> — the same struct, accepted.
accept "AGa s = mk(r.v)  (D2, 6.7.17)" "$G"'fn main(): i64 { var r: RB; r.v.x = 2; r.v.y = 7; r.n = 1; var s: Box<Pt>; s.n = 0; s = mk(r.v); return s.v.y * 10 + s.n; }'"$E" 75 "$G"'fn main(): i64 { var s: Box<Pt>; s.v.x = 2; s.v.y = 7; s.n = 5; return s.v.y * 10 + s.n; }'"$E"
accept "DGa var s: Box<Pt> = mk(r.v)  (D2)" "$G"'fn main(): i64 { var r: RB; r.v.x = 2; r.v.y = 7; r.n = 1; var s: Box<Pt> = mk(r.v); return s.v.y * 10 + s.n; }'"$E" 75 "$G"'fn main(): i64 { var s: Box<Pt>; s.v.x = 2; s.v.y = 7; s.n = 5; return s.v.y * 10 + s.n; }'"$E"
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

# 6.7.16 (issues/archived/2026-10-19-pointer-struct-source-refusal-names-call-argument.md): the PU*b / PU*c rows name the `*U`
# value as written — `gu8()`, `w.pu` (they named `gu8`, `pu`, the chain's last name); PU*a / PU*e keep the name.
echo "6.7.11 — a *U of another struct returned from a struct fn is refused by name, at every size:"
MU="takes a value of that struct, or a pointer to one — got"
refuse "PU3a 3 B: return GU3;" "$MU \`GU3\` (a \`\\*U3\`)" "$(printf 'struct S3 { a: i8; b: i8; c: i8; }\nstruct U3 { x: i8; y: i8; z: i8; }\nstruct W3 { pu: *U3; }\nvar GU3: *U3 = 0;\nfn gu3(): *U3 { return GU3; }\nfn f(): S3 { return GU3; }\nfn main(): i64 { var r: S3 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU3b 3 B: return gu3();" "$MU \`gu3()\` (a \`\\*U3\`)" "$(printf 'struct S3 { a: i8; b: i8; c: i8; }\nstruct U3 { x: i8; y: i8; z: i8; }\nstruct W3 { pu: *U3; }\nvar GU3: *U3 = 0;\nfn gu3(): *U3 { return GU3; }\nfn f(): S3 { return gu3(); }\nfn main(): i64 { var r: S3 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU3c 3 B: var w: W3; return w.pu;" "$MU \`w.pu\` (a \`\\*U3\`)" "$(printf 'struct S3 { a: i8; b: i8; c: i8; }\nstruct U3 { x: i8; y: i8; z: i8; }\nstruct W3 { pu: *U3; }\nvar GU3: *U3 = 0;\nfn gu3(): *U3 { return GU3; }\nfn f(): S3 { var w: W3; return w.pu; }\nfn main(): i64 { var r: S3 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU3d 3 B: return *GU3;" "$MU \`\\*GU3\` (a \`U3\`)" "$(printf 'struct S3 { a: i8; b: i8; c: i8; }\nstruct U3 { x: i8; y: i8; z: i8; }\nstruct W3 { pu: *U3; }\nvar GU3: *U3 = 0;\nfn gu3(): *U3 { return GU3; }\nfn f(): S3 { return *GU3; }\nfn main(): i64 { var r: S3 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU3e 3 B: var pu: *U3 = GU3; return (pu);" "$MU \`pu\` (a \`\\*U3\`)" "$(printf 'struct S3 { a: i8; b: i8; c: i8; }\nstruct U3 { x: i8; y: i8; z: i8; }\nstruct W3 { pu: *U3; }\nvar GU3: *U3 = 0;\nfn gu3(): *U3 { return GU3; }\nfn f(): S3 { var pu: *U3 = GU3; return (pu); }\nfn main(): i64 { var r: S3 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU8a 8 B: return GU8;" "$MU \`GU8\` (a \`\\*U8\`)" "$(printf 'struct S8 { v; }\nstruct U8 { u; }\nstruct W8 { pu: *U8; }\nvar GU8: *U8 = 0;\nfn gu8(): *U8 { return GU8; }\nfn f(): S8 { return GU8; }\nfn main(): i64 { var r: S8 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU8b 8 B: return gu8();" "$MU \`gu8()\` (a \`\\*U8\`)" "$(printf 'struct S8 { v; }\nstruct U8 { u; }\nstruct W8 { pu: *U8; }\nvar GU8: *U8 = 0;\nfn gu8(): *U8 { return GU8; }\nfn f(): S8 { return gu8(); }\nfn main(): i64 { var r: S8 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU8c 8 B: var w: W8; return w.pu;" "$MU \`w.pu\` (a \`\\*U8\`)" "$(printf 'struct S8 { v; }\nstruct U8 { u; }\nstruct W8 { pu: *U8; }\nvar GU8: *U8 = 0;\nfn gu8(): *U8 { return GU8; }\nfn f(): S8 { var w: W8; return w.pu; }\nfn main(): i64 { var r: S8 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU8d 8 B: return *GU8;" "$MU \`\\*GU8\` (a \`U8\`)" "$(printf 'struct S8 { v; }\nstruct U8 { u; }\nstruct W8 { pu: *U8; }\nvar GU8: *U8 = 0;\nfn gu8(): *U8 { return GU8; }\nfn f(): S8 { return *GU8; }\nfn main(): i64 { var r: S8 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU8e 8 B: var pu: *U8 = GU8; return (pu);" "$MU \`pu\` (a \`\\*U8\`)" "$(printf 'struct S8 { v; }\nstruct U8 { u; }\nstruct W8 { pu: *U8; }\nvar GU8: *U8 = 0;\nfn gu8(): *U8 { return GU8; }\nfn f(): S8 { var pu: *U8 = GU8; return (pu); }\nfn main(): i64 { var r: S8 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU16a 16 B: return GU16;" "$MU \`GU16\` (a \`\\*U16\`)" "$(printf 'struct S16 { v; w; }\nstruct U16 { u; t; }\nstruct W16 { pu: *U16; }\nvar GU16: *U16 = 0;\nfn gu16(): *U16 { return GU16; }\nfn f(): S16 { return GU16; }\nfn main(): i64 { var r: S16 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU16b 16 B: return gu16();" "$MU \`gu16()\` (a \`\\*U16\`)" "$(printf 'struct S16 { v; w; }\nstruct U16 { u; t; }\nstruct W16 { pu: *U16; }\nvar GU16: *U16 = 0;\nfn gu16(): *U16 { return GU16; }\nfn f(): S16 { return gu16(); }\nfn main(): i64 { var r: S16 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU16c 16 B: var w: W16; return w.pu;" "$MU \`w.pu\` (a \`\\*U16\`)" "$(printf 'struct S16 { v; w; }\nstruct U16 { u; t; }\nstruct W16 { pu: *U16; }\nvar GU16: *U16 = 0;\nfn gu16(): *U16 { return GU16; }\nfn f(): S16 { var w: W16; return w.pu; }\nfn main(): i64 { var r: S16 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU16d 16 B: return *GU16;" "$MU \`\\*GU16\` (a \`U16\`)" "$(printf 'struct S16 { v; w; }\nstruct U16 { u; t; }\nstruct W16 { pu: *U16; }\nvar GU16: *U16 = 0;\nfn gu16(): *U16 { return GU16; }\nfn f(): S16 { return *GU16; }\nfn main(): i64 { var r: S16 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU16e 16 B: var pu: *U16 = GU16; return (pu);" "$MU \`pu\` (a \`\\*U16\`)" "$(printf 'struct S16 { v; w; }\nstruct U16 { u; t; }\nstruct W16 { pu: *U16; }\nvar GU16: *U16 = 0;\nfn gu16(): *U16 { return GU16; }\nfn f(): S16 { var pu: *U16 = GU16; return (pu); }\nfn main(): i64 { var r: S16 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU24a 24 B: return GU24;" "$MU \`GU24\` (a \`\\*U24\`)" "$(printf 'struct S24 { v; w; x; }\nstruct U24 { u; t; s; }\nstruct W24 { pu: *U24; }\nvar GU24: *U24 = 0;\nfn gu24(): *U24 { return GU24; }\nfn f(): S24 { return GU24; }\nfn main(): i64 { var r: S24 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU24b 24 B: return gu24();" "$MU \`gu24()\` (a \`\\*U24\`)" "$(printf 'struct S24 { v; w; x; }\nstruct U24 { u; t; s; }\nstruct W24 { pu: *U24; }\nvar GU24: *U24 = 0;\nfn gu24(): *U24 { return GU24; }\nfn f(): S24 { return gu24(); }\nfn main(): i64 { var r: S24 = f(); return 0; }\nsyscall(60, main());\n')" one
refuse "PU24c 24 B: var w: W24; return w.pu;" "$MU \`w.pu\` (a \`\\*U24\`)" "$(printf 'struct S24 { v; w; x; }\nstruct U24 { u; t; s; }\nstruct W24 { pu: *U24; }\nvar GU24: *U24 = 0;\nfn gu24(): *U24 { return GU24; }\nfn f(): S24 { var w: W24; return w.pu; }\nfn main(): i64 { var r: S24 = f(); return 0; }\nsyscall(60, main());\n')" one
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
# (issues/archived/2026-10-18-global-pointer-to-unknown-type-reads-first-struct.md; rows: type_name_refused.sh axis 7).
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

# SH1-SH12 (6.7.16, issues/archived/2026-10-18-refused-annotation-stand-down-silences-a-shadowing-block-variable.md) — THE STAND-DOWN
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

# UC (6.7.16, issues/archived/2026-10-18-untyped-closure-capture-field-use-says-undefined-variable.md) — `.field`, a field store and
# `.m()` ON AN UNTYPED CLOSURE CAPTURE take the `sid == 0` arms an untyped local takes. PARSE_FIELD_LOAD's and
# PARSE_FIELD_STORE's capture rung (`_CL_CAP_FIELD_IDX`) answered for a struct capture only, so an untyped one fell to
# the globals and "undefined variable 'x'" — at the right column, naming the wrong fault; after a refused annotation it
# was a second error (the stand-down looked up no capture). Now the rung (`_cl_cap_fld_any`, parse_decl.cyr) hands any
# capture on as its capture-band index with sid 0: "no struct type in scope for 'x'" in the field / store / method
# wording, a captured vector's "SIMD vector has no named fields", and the refused-annotation stand-down, which resolves
# the capture to its declaring fn's slot through any nesting (`_cl_cap_origin`, parse_expr.cyr: the closure context
# keeps its host fn, `_cl_host_fn`, and the enclosing context, `_cl_ctx_up`). The same arm calls a bounded scalar T's
# member on a captured receiver (`|| v.show()` at T = i64 was "undefined variable 'v'": tests/tcyr/crossos/
# trait_bounds.tcyr K1-K9). `--syntax-only` stays silent (UC12).
# UCG (6.7.16, the user's D96, 2026-10-20; issues/2026-10-20-closure-untyped-capture-named-like-struct-global-reads-
# global-field.md) — A CAPTURE NAMED LIKE A STRUCT GLOBAL shadows the global for `.field`, a field store and `.m()`, as
# the local does outside the closure. The rung answered -1 when a global of the name existed (a `FINDVAR >= 0` test),
# so `var x = 5; |k| x.a + k` beside `var x = Q { 7, 8 };` exited 7 — the GLOBAL's field — while `x` alone in the same
# closure read the capture (5). Now refused as UC0 is: UCG0 (the filed repro verbatim), UCG1 (a store and a method),
# UCG2 (an `i64` capture), UCG3 (an untyped `&q` capture), UCG4 (a nested closure's capture of a capture), on every leg
# (`uc_rows`), and silent under --syntax-only (UC12). Controls (x86_64): a struct-typed capture reads its own copy (UCG5),
# a closure capturing no `x` reads the global (UCG6), a plain `x` the capture (UCG7).
# Every UC row but the UC3 / UC4 controls runs on x86_64 and again from the aarch64, cx and PE compilers (CPX, `uc_rows`).
# (Mutants: a scratch copy of the tree with the one change, its build/cycc; CPX's cross compilers come from it too.
# Re-measured 2026-10-20 after the review's CPX extension:)
#   the tree before (4b6958340)                         -> RED 48: UC0-UC2 UC5-UC11 UC13 UC14 ("undefined variable"),
#                                                          x4 legs (x86_64, CPX aarch64 / cx / PE)
#   `_cl_cap_fld_any` = `_CL_CAP_FIELD_IDX` (the rung)   -> RED 48: the same
#   `_ann_refd_said` without its capture arm             -> RED 24: UC2 UC7-UC11 (a second, no-struct error) x4 legs
#   `_cl_cap_origin` not following `_cl_ctx_up`          -> RED 8: UC8 UC10 (a capture of a capture) x4 legs
#   the tree before D96 (4ae0873f3: the `FINDVAR >= 0` exit) -> RED 20: UCG0-UCG4 (compiled: the global's field) x4 legs
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
UCG='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
var x = Q { 7, 8 };
fn main(): i64 { var x = 5; var f = |k| { return x.a + k; }; return fncall1(f, 0); }
syscall(60, main());
'
UCGH='include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn m(self): i64 { return self.b; } }
var x = Q { 7, 8 };
'
refuse_at "UC0 |k| x.a + k  (the filed repro)" "3:54: $SN 'x'$SA" "$UCA"
refuse_at "UC1 x.a = k; x.m()  (store, method)" "3:47: $SN 'x'$SS|3:62: $SN 'x'$SM" "$UCB"
refuse_at "UC2 var x: Foo = 5; |k| x.a  (refused)" "3:25: unknown type 'Foo' for variable 'x'" "$UCC"
refuse_at "UC3 control: outside the closure" "3:39: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x = 5; return x.a; }
syscall(60, main());
'
accept "UCG5 control: a struct capture, a struct global" "$UCGH"'fn main(): i64 { var x: Q = Q { 1, 2 }; var f = |k| { return x.a * 10 + x.m() + k; }; return fncall1(f, 0); }
syscall(60, main());
' 12 'syscall(60, 12);'
accept "UCG6 control: no x captured: the global" "$UCGH"'fn main(): i64 { var y = 5; var f = |k| { return x.a * 10 + x.m() + k + y; }; return fncall1(f, 0); }
syscall(60, main());
' 83 'syscall(60, 83);'
accept "UCG7 control: a plain x is the capture" "$UCGH"'fn main(): i64 { var x = 5; var f = |k| { return x + k; }; return fncall1(f, 1); }
syscall(60, main());
' 6 'syscall(60, 6);'
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
# UC5-UC11, UC13, UC14 and UC12 run as one function: on x86_64 here, and again from every cross compiler (CPX,
# `cross_rows` below) — the brief's acceptance is each UC row on x86_64 / aarch64 / cx / PE. $1 = the label prefix.
uc_rows() {
    refuse_at "${1}UC5 a captured f64v2's .a" "3:57: SIMD vector has no named fields" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var v: f64v2; var f = |k| { return v.a + k; }; return fncall1(f, 0); }
syscall(60, main());
'
    refuse_at "${1}UC6 a nested closure's capture of a capture" "3:68: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x = 5; var f = |k| { var g = |j| { return x.a + j; }; return fncall1(g, k); }; return fncall1(f, 0); }
syscall(60, main());
'
    refuse_at "${1}UC7 refused: store, method, field" "3:25: unknown type 'Foo' for variable 'x'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x: Foo = 5; var f = |k| { x.a = k; return x.m() + x.b; }; return fncall1(f, 0); }
syscall(60, main());
'
    refuse_at "${1}UC8 refused, read by a nested closure" "3:25: unknown type 'Foo' for variable 'x'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x: Foo = 5; var f = |k| { var g = |j| { return x.a + j; }; return fncall1(g, k); }; return fncall1(f, 0); }
syscall(60, main());
'
    refuse_at "${1}UC9 refused in a closure, nested read" "3:39: unknown type 'Foo' for variable 'x'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var f = |k| { var x: Foo = 5; var g = |j| { return x.a + j; }; return fncall1(g, k); }; return fncall1(f, 0); }
syscall(60, main());
'
    refuse_at "${1}UC10 refused, two closures deep" "3:25: unknown type 'Foo' for variable 'x'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x: Foo = 5; var f = |k| { var g = |j| { var h = || x.a; return fncall0(h) + j; }; return fncall1(g, k); }; return fncall1(f, 0); }
syscall(60, main());
'
    refuse_at "${1}UC11 a refused parameter, captured" "3:10: unknown type 'Foo' for parameter 'q'" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn h(q: *Foo): i64 { var f = |k| { return q.a + k; }; return fncall1(f, 0); }
fn main(): i64 { return 0; }
syscall(60, main());
'
    refuse_at "${1}UC13 the shadow of a refused x, captured" "3:25: unknown type 'Foo' for variable 'x'|3:84: $SN 'x'$SA" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var x: Foo = 5; if (1 == 1) { var x = 7; var f = |k| { return x.a + k; }; return fncall1(f, 0); } return 0; }
syscall(60, main());
'
    refuse_at "${1}UC14 y.m<i64>(1) on a capture" "3:58: $SN 'y'$SM" 'include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 { var y = 5; var f = |k| { return y.m<i64>(1) + k; }; return fncall1(f, 0); }
syscall(60, main());
'
    refuse_at "${1}UCG0 D96: the filed repro (a struct global x)" "5:54: $SN 'x'$SA" "$UCG"
    refuse_at "${1}UCG1 D96: a store and a method" "5:47: $SN 'x'$SS|5:62: $SN 'x'$SM" "$UCGH"'fn main(): i64 { var x = 5; var f = |k| { x.a = k; return x.m(); }; return fncall1(f, 0); }
syscall(60, main());
'
    refuse_at "${1}UCG2 D96: an i64 capture" "5:59: $SN 'x'$SA" "$UCGH"'fn main(): i64 { var x: i64 = 5; var f = |k| { return x.b + k; }; return fncall1(f, 0); }
syscall(60, main());
'
    refuse_at "${1}UCG3 D96: an untyped &q capture" "5:75: $SN 'x'$SA" "$UCGH"'fn main(): i64 { var q = Q { 3, 4 }; var x = &q; var f = |k| { return x.b + k; }; return fncall1(f, 0); }
syscall(60, main());
'
    refuse_at "${1}UCG4 D96: a nested closure's capture" "5:68: $SN 'x'$SA" "$UCGH"'fn main(): i64 { var x = 5; var f = |k| { var g = |j| { return x.a + j; }; return fncall1(g, k); }; return fncall1(f, 0); }
syscall(60, main());
'
    # UC12: --syntax-only (cyrius lint) — silent, rc 0, as for an untyped local.
    for so in UCA UCB UCC UCG; do
        eval "src=\$$so"
        printf '%s' "$src" > "$D/so.cyr"
        rc=0; "$CC" --syntax-only < "$D/so.cyr" > /dev/null 2> "$D/so.err" || rc=$?
        nrefuse=$((nrefuse+1))
        if [ "$rc" -eq 0 ] && ! grep -q '^error\|^warning' "$D/so.err"; then
            printf '  ok(silent): %sUC12 --syntax-only %s\n' "$1" "$so"; pass=$((pass+1))
        else
            printf '  FAIL: %sUC12 --syntax-only %s rc=%s: %s\n' "$1" "$so" "$rc" "$(head -1 "$D/so.err")"; fail=$((fail+1))
        fi
    done
}
uc_rows ""

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

# CP (6.7.16, issues/archived/2026-10-18-closure-parameter-keeps-an-earlier-fns-slot-type.md) — A CLOSURE'S PARAMETER IS UNTYPED
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

# CPX (6.7.16) — the closure rows (CP0 CP1, every UC row but the UC3 / UC4 controls: UC0-UC2, `uc_rows`' UC5-UC11 UC13
# UC14, the UCG rows (D96) and UC12's --syntax-only) from every cross compiler built from this tree (the frontend is
# shared; this pins it).
# The cross compilers are built from the tree's src/, so a mutant is a tree mutant.
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
struct G1<U> { v: U; }
struct B1 { a; }
struct E1 { a; }
fn mkg1<U>(v: U): G1<U> { var g: G1<U>; g.v = v; return g; }
fn B1_add<U>(l: B1, r: U): G1<U> { var g: G1<U>; g.v = r; return g; }
fn E1_add<U>(l: E1, r: U): U { return r; }
impl B1 {
    fn mkg<U>(self, v: U): G1<U> { var g: G1<U>; g.v = v; return g; }
    fn idm<U>(self, v: U): U { return v; }
}
fn pk2<A, C>(a: A, c: C): G1<A> { var g: G1<A>; g.v = a; return g; }
struct G2<A, C> { a: A; }
fn pk3<A, C>(a: A, c: C): G2<A, C> { var g: G2<A, C>; g.a = a; return g; }
fn gc3<T>(x: T): i64 { var q: Q; var y: T = pk3(q, 5); return 9; }
fn gc<T>(x: T): i64 { var q: Q; q.a = 1; var y: T = mkg1(q); return 9; }
fn gcx<T>(x: T): i64 { var q: Q; var y: T = mkg1<Q>(q); return 9; }
fn gcm<T>(x: T): i64 { var b: B1; var q: Q; var y: T = b.mkg(q); return 9; }
fn gct<T>(x: T): i64 { var b: B1; var q: Q; var y: T = b.idm(q); return 9; }
fn gco<T>(x: T): i64 { var b: B1; var q: Q; var y: T = b + q; return 9; }
fn gce<T>(x: T): i64 { var e: E1; var q: Q; var y: T = e + q; return 9; }
fn gca<T>(x: T): i64 { var q: Q; var y: T = x; y = mkg1(q); return 9; }
fn gc2<T>(x: T): i64 { var q: Q; var y: T = pk2(q, 5); return 9; }
fn gck<T>(x: T): i64 { return gco(x); }
fn gk1<T>(x: T): i64 { var y: T = mkg1(x); return 9; }
fn gk2<T>(x: T): i64 { var b: B1; var y: T = b + x; return 9; }
fn gk3<T>(x: T): i64 { var q: Q8; q.a = 21; var y: T = mkg1(q); return y; }
fn gk4<T>(x: T): i64 { var q: Q; q.a = 3; q.b = 44; var y: T = mkg1(q); return y.v.b; }
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
# TA6-TA6c (6.7.16, the user's D99, 2026-10-20): a store THROUGH a `*T` / `**T` is a stub line too — at a scalar T it lands
# in a scalar, refused in a plain fn (the DP rows) — so `gd(5)` / `gd<i32>(5)` / `gdd(5)` are refused, the note naming
# the pointer (they compiled and kept Q's first word, 41ca7d41c through 94a79ff72); TA6d at T = Q copies.
refuse "TA6 *p = mkp(); (p: *T) at i64: a stub (D99)" "generic 'gd' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gd(5); }'"$TE" one
if grep -q "^  note: <source>:[0-9]*:[0-9]*: 'gd' stores a struct result over 8 bytes through 'p', a pointer to its type parameter\$" "$D/r.err"; then
    printf '  ok(refused): %-28s\n' "TA6n the note names p"; pass=$((pass+1))
else printf '  FAIL: %-34s %s\n' "TA6n the note" "$(grep '^  note' "$D/r.err" | head -1)"; fail=$((fail+1)); fi
refuse "TA6b *p = mkp(); at gd<i32>(5)" "generic 'gd' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gd<i32>(5); }'"$TE" one
refuse "TA6c **pp = mkp(); (pp: **T) at i64" "generic 'gdd' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gdd(5); }'"$TE" one
accept "TA6d *p = mkp(); at T = Q copies through p" "$TH"'fn main(): i64 { var q: Q; q.a = 7; q.b = 8; return gdq(q); }'"$TE" 44 'syscall(60, 44);'
refuse "TA12 *(p + 0) = mkp(); (p: *T) at i64" "generic 'gda' has no i64 (or other scalar) instance" "$TH"'fn gda<T>(x: T): i64 { var p: *T = &x; *(p + 0) = mkp(); return 9; }
fn main(): i64 { return gda(5); }'"$TE" one
accept "TA12b ... at T = Q copies (its base parse judges nothing)" "$TH"'fn gda<T>(x: T): i64 { var p: *T = &x; *(p + 0) = mkp(); return x.b - 400; }
fn main(): i64 { var q: Q; return gda(q); }'"$TE" 44 'syscall(60, 44);'
accept "TA13 *p = a + a + a; (p: *T) at T = Q copies: the base judges no T-typed store" "$TH"'fn gdo<T>(p: *T): i64 { var a: Q; a.a = 0; a.b = 0; *p = a + a + a; return 9; }
fn main(): i64 { var q: Q; q.a = 5; q.b = 6; gdo(&q); return q.b; }'"$TE" 1 'syscall(60, 1);'
# TG23-TG25 / TA14 (met beside D99): the stub scan's struct-result reader took one operator only (`_gs_top_op`), a
# receiver in parentheses as none (`_gs_recv_wrap`) and a generic call or method receiver as its base (`_gs_recv_call`),
# so each of these generics compiled at i64 and kept the result's first word, where the plain fn refuses the line.
refuse "TG23 var y: T = a + c + a; (an operator chain)" "generic 'gch' has no i64 (or other scalar) instance" "$TH"'fn gch<T>(x: T): i64 { var a: Q; var c: Q; var y: T = a + c + a; return 9; }
fn main(): i64 { return gch(5); }'"$TE" one
refuse "TG23b y = a + c + a; (a chain, y: T)" "generic 'gch2' has no i64 (or other scalar) instance" "$TH"'fn gch2<T>(x: T): i64 { var a: Q; var c: Q; var y: T = x; y = a + c + a; return 9; }
fn main(): i64 { return gch2(5); }'"$TE" one
refuse "TG23c *p = a + c + a; (p: *T)" "generic 'gch3' has no i64 (or other scalar) instance" "$TH"'fn gch3<T>(p: *T): i64 { var a: Q; var c: Q; *p = a + c + a; return 9; }
fn main(): i64 { var x = 5; return gch3(&x); }'"$TE" one
refuse "TG24 var y: T = (a + c).mk(); (a wrapped receiver)" "generic 'gcw' has no i64 (or other scalar) instance" "$TH"'fn gcw<T>(x: T): i64 { var a: Q; var c: Q; var y: T = (a + c).mk(); return 9; }
fn main(): i64 { return gcw(5); }'"$TE" one
refuse "TG24b *p = (a + c).mk(); (p: *T)" "generic 'gcw2' has no i64 (or other scalar) instance" "$TH"'fn gcw2<T>(p: *T): i64 { var a: Q; var c: Q; *p = (a + c).mk(); return 9; }
fn main(): i64 { var x = 5; return gcw2(&x); }'"$TE" one
refuse "TG25 *p = b.idm(a).mk(); (a generic method receiver)" "generic 'gcg' has no i64 (or other scalar) instance" "$TH"'fn gcg<T>(p: *T): i64 { var a: Q; var b: B1; *p = b.idm(a).mk(); return 9; }
fn main(): i64 { var x = 5; return gcg(&x); }'"$TE" one
refuse "TG25b var y: T = mkg1(a).v.mk(); (a generic call receiver)" "generic 'gcf' has no i64 (or other scalar) instance" "$TH"'fn gcf<T>(x: T): i64 { var a: Q; var y: T = mkg1(a).v.mk(); return 9; }
fn main(): i64 { return gcf(5); }'"$TE" one
refuse "TG25c var g = mkg1(a); var y: T = g.v.mk(); (a local from a generic call)" "generic 'gcl' has no i64 (or other scalar) instance" "$TH"'fn gcl<T>(x: T): i64 { var a: Q; var g = mkg1(a); var y: T = g.v.mk(); return 9; }
fn main(): i64 { return gcl(5); }'"$TE" one
accept "TA14 var y: T = a + c + a; at T = Q copies" "$TH"'fn gch4<T>(x: T): i64 { var a: Q; a.a = 0; var c: Q; c.a = 0; var y: T = a + c + a; return y.b; }
fn main(): i64 { var q: Q; return gch4(q); }'"$TE" 1 'syscall(60, 1);'
accept "TA14b *p = (a + c).mk(); at T = Q copies through p" "$TH"'fn gcw3<T>(p: *T): i64 { var a: Q; var c: Q; *p = (a + c).mk(); return 9; }
fn main(): i64 { var q: Q; q.b = 6; gcw3(&q); return q.b; }'"$TE" 2 'syscall(60, 2);'
refuse "TA11 *w.p = mkp(); (a carrier's *T field) at i64" "generic 'gdw' has no i64 (or other scalar) instance" "$TH"'struct Wt<U> { p: *U; }
fn gdw<T>(w: Wt<T>): i64 { *w.p = mkp(); return 9; }
fn main(): i64 { var k = 5; var w: Wt<i64>; w.p = &k; return gdw(w); }'"$TE" one
accept "TA11b ... at Wt<Q> copies through w.p" "$TH"'struct Wt<U> { p: *U; }
fn gdw<T>(w: Wt<T>): i64 { *w.p = mkp(); return 9; }
fn main(): i64 { var q: Q; var w: Wt<Q>; w.p = &q; gdw(w); return q.b - 400; }'"$TE" 44 'syscall(60, 44);'
# 6.7.16 — D1 AT A GENERIC CALLEE: its result is read at the binding its call makes (`_gs_gcall`, `_gs_mret`, `_gs_opg`),
# a generic operator fn's at its dispatch's (D85 (a)). Each compiled and kept the 16 B `G1<Q>`'s (or Q's) first word.
refuse "TG13 var y: T = mkg1(q); (G1<Q>)" "generic 'gc' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gc(5); }'"$TE" one
refuse "TG14 var y: T = mkg1<Q>(q);" "generic 'gcx' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gcx(5); }'"$TE" one
refuse "TG15 var y: T = b.mkg(q); (a method)" "generic 'gcm' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gcm(5); }'"$TE" one
refuse "TG16 var y: T = b.idm(q); (a : U method)" "generic 'gct' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gct(5); }'"$TE" one
refuse "TG17 var y: T = b + q; (B1_add<Q>)" "generic 'gco' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gco(5); }'"$TE" one
refuse "TG18 var y: T = e + q; (a : U operator)" "generic 'gce' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gce(5); }'"$TE" one
refuse "TG19 y = mkg1(q); (y: T)" "generic 'gca' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gca(5); }'"$TE" one
refuse "TG20 var y: T = pk2(q, 5); (one name of two)" "generic 'gc2' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gc2(5); }'"$TE" one
refuse "TG21 gck(5): a generic forwarding its T to gco" "generic 'gck' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gck(5); }'"$TE" one
refuse "TG22 var y: T = pk3(q, 5); (G2<Q, i64>)" "generic 'gc3' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gc3(5); }'"$TE" one
accept "TA7 var y: T = mkg1(x); (x: T) at i64: not a stub" "$TH"'fn main(): i64 { return gk1(5); }'"$TE" 9 'syscall(60, 9);'
accept "TA8 var y: T = b + x; (x: T) at i64: not a stub" "$TH"'fn main(): i64 { return gk2(5); }'"$TE" 9 'syscall(60, 9);'
accept "TA9 an 8 B G1<Q8> into y: T at i64 keeps its word" "$TH"'fn main(): i64 { return gk3(5); }'"$TE" 21 'syscall(60, 21);'
accept "TA10 var y: T = mkg1(q); at T = G1<Q> copies" "$TH"'fn main(): i64 { var q: Q; q.a = 1; q.b = 2; return gk4(mkg1(q)); }'"$TE" 44 'syscall(60, 44);'

echo "=== 6.7.16 (D99): a struct result over 8 B stored through a pointer to a scalar is refused, as its siblings ==="
# issues/archived/2026-10-20-dereference-store-of-struct-result-keeps-first-word.md — `*p = mkp();` (p: *i64) stored Q's first
# word (the filed repro exited 77), silently, where `y = mkp();` (D27) and `p = mkp();` (D32) are refused. DP0 the
# filed repro verbatim; DP1-DP19 every operand the compiler types as a pointer to no struct (a `*u8` / `*f64` / `*bool`
# local, a parameter, a global, a field, a `: *i64` call, `p + n`, `**pp`, `*pp` of a `**i64` or of a `**Pt`, a capture)
# and every struct result (a method, an operator, a known `&f`, wrapped, 24 B, a for step); DP20 `*(&x)` is x (D27 /
# D33's words); DP21 a fixed `*i64` in a generic is refused at its definition; DPK1-DPK4 an 8 B result, a `Str`, a
# field of the result, a `*Q` of the result's own struct keep their store. The generic twin is the stub rule (TA6-TA6c
# re-pinned; TA11 a carrier's `*T` field).
DQ='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
struct Q { a; b; }
struct Q3 { a; b; c; }
struct S8 { v; }
struct Pt { x; y; }
struct W { pi: *i64; n; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn mk3(): Q3 { var q: Q3; q.a = 333; q.b = 1; q.c = 2; return q; }
fn mk8(): S8 { var s: S8; s.v = 9; return s; }
fn mks(): Str { return str_from("abc"); }
impl Q { fn dup(self): Q { return mkp(); } }
fn Q_add(l: Q, r: Q): Q { return mkp(); }
var GX = 5;
var GP: *i64 = &GX;
fn gpi(): *i64 { return GP; }
'
DM="cannot assign '\*p: i64' from 'mkp', which returns the struct 'Q' - store it through a '\*Q' or bind a field"
DP0S='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct S8 { v; }
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn g(x: i64): i64 { var p: *i64 = &x; *p = mkp(); return x; }
fn main(): i64 { return g(5); }
syscall(60, main());
'
refuse_at "DP0 the filed repro verbatim (its one error, at the call)" "6:44: $(printf '%s' "$DM" | tr -d '\\')" "$DP0S"
refuse "DP1 *p through a *u8" "cannot assign '\*p: u8' from 'mkp'" "$DQ"'fn main(): i64 { var x: u8 = 5; var p: *u8 = &x; *p = mkp(); return x; }'"$TE" one
refuse "DP2 *p through a *f64" "cannot assign '\*p: f64' from 'mkp'" "$DQ"'fn main(): i64 { var x: f64 = 1.5; var p: *f64 = &x; *p = mkp(); return 0; }'"$TE" one
refuse "DP3 *p through a *bool" "cannot assign '\*p: bool' from 'mkp'" "$DQ"'fn main(): i64 { var x: bool = false; var p: *bool = &x; *p = mkp(); return 0; }'"$TE" one
refuse "DP4 a *i64 parameter" "$DM" "$DQ"'fn f(p: *i64): i64 { *p = mkp(); return 0; }
fn main(): i64 { var x = 5; return f(&x); }'"$TE" one
refuse "DP5 *GP, a *i64 global" "cannot assign '\*GP: i64' from 'mkp'" "$DQ"'fn main(): i64 { *GP = mkp(); return GX; }'"$TE" one
refuse "DP6 *w.pi, a *i64 field" "cannot assign '\*w\.pi: i64' from 'mkp'" "$DQ"'fn main(): i64 { var x = 5; var w: W; w.pi = &x; *w.pi = mkp(); return x; }'"$TE" one
refuse "DP7 *gpi(), a : *i64 call" "cannot assign '\*gpi(): i64' from 'mkp'" "$DQ"'fn main(): i64 { *gpi() = mkp(); return GX; }'"$TE" one
refuse "DP8 *(p + 0)" "cannot assign '\*(p + 0): i64' from 'mkp'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; *(p + 0) = mkp(); return x; }'"$TE" one
refuse "DP9 **pp of a **i64" "cannot assign '\*\*pp: i64' from 'mkp'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; var pp: **i64 = &p; **pp = mkp(); return x; }'"$TE" one
refuse "DP10 *pp of a **i64 (a *i64 slot, D32's)" "cannot assign '\*pp: \*i64' from 'mkp'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; var pp: **i64 = &p; *pp = mkp(); return x; }'"$TE" one
refuse "DP11 *pp of a **Pt (another struct's slot)" "cannot assign '\*pp: \*Pt' from 'mkp'" "$DQ"'fn main(): i64 { var t: Pt; var p: *Pt = &t; var pp: **Pt = &p; *pp = mkp(); return 0; }'"$TE" one
refuse "DP12 a closure's captured *i64" "$DM" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; var f = || { *p = mkp(); return 0; }; fncall0(f); return x; }'"$TE" one
refuse "DP13 a method's result" "cannot assign '\*p: i64' from 'Q\.dup'" "$DQ"'fn main(): i64 { var q: Q; var x = 5; var p: *i64 = &x; *p = q.dup(); return x; }'"$TE" one
refuse "DP14 an operator's result" "cannot assign '\*p: i64' from 'Q_add'" "$DQ"'fn main(): i64 { var q: Q; var x = 5; var p: *i64 = &x; *p = q + q; return x; }'"$TE" one
refuse "DP15 fncall0(&mkp)" "$DM" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; *p = fncall0(&mkp); return x; }'"$TE" one
refuse "DP16 callptr(&mkp)" "$DM" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; *p = callptr(&mkp); return x; }'"$TE" one
refuse "DP17 ((mkp())), wrapped" "$DM" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; *p = ((mkp())); return x; }'"$TE" one
refuse "DP18 mk3(), 24 B" "cannot assign '\*p: i64' from 'mk3', which returns the struct 'Q3' - store it through a '\*Q3'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; *p = mk3(); return x; }'"$TE" one
refuse "DP18b an operator chain a + a + a" "cannot assign '\*p: i64' from 'Q_add'" "$DQ"'fn main(): i64 { var a: Q; var x = 5; var p: *i64 = &x; *p = a + a + a; return x; }'"$TE" one
refuse "DP19 a for step" "$DM" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; for (var i = 0; i < 1; *p = mkp()) { i = i + 1; } return x; }'"$TE" one
refuse "DP20 *(&x) is x: D27 / D33's words" "cannot assign 'x: i64' from 'mkp', which returns the struct 'Q' - declare 'x: Q' or bind a field" "$DQ"'fn main(): i64 { var x: i64 = 5; *(&x) = mkp(); return x; }'"$TE" one
refuse "DP20b *(&u) of an untyped u" "cannot assign 'u' from 'mkp', which returns the struct 'Q' - declare 'u: Q' or bind a field" "$DQ"'fn main(): i64 { var u = 5; *(&u) = mkp(); return u; }'"$TE" one
refuse "DP21 a fixed *i64 in a generic, uncalled" "cannot assign '\*pk: i64' from 'mkp'" "$DQ"'fn g6<T>(x: T): i64 { var k = 5; var pk: *i64 = &k; *pk = mkp(); return k; }
fn main(): i64 { return 0; }'"$TE" one
accept "DPK1 an 8 B result keeps its word" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; *p = mk8(); return x; }'"$TE" 9 'syscall(60, 9);'
accept "DPK2 a Str result keeps its handle" "$DQ"'fn main(): i64 { alloc_init(); var x = 0; var p: *i64 = &x; *p = mks(); var s: Str = x; return s.len(); }'"$TE" 3 'syscall(60, 3);'
accept "DPK3 a field of the result" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; *p = mkp().a; return x - 300; }'"$TE" 33 'syscall(60, 33);'
accept "DPK4 *pq of a *Q copies (6.7.11)" "$DQ"'fn main(): i64 { var q: Q; var pq: *Q = &q; *pq = mkp(); return q.b - 400; }'"$TE" 44 'syscall(60, 44);'
# DS (the s16 review, D99 carried to a subscript store): `p[i] = mkp();` through a typed pointer to a scalar is refused as
# `*(p + i) = mkp();` is, named as spelled ('p[0]: i64'): a `*i64` local, a `*i64` field, a `: *i64` call, a `*i64` global,
# a `*f64` / `*u8` with a method's and an operator's result, wrapped, `fncall0(&mkp)`, a for step, after the first
# top-level statement (each compiled and kept Q's first word: 77); DSK1 `pp[0][0]` is the subscript's own one error;
# DSK2 / DSK3 a field of the result, an 8 B result keep their word; TA15 / TA15b / TA15n the generic's `p[0] = mkp();`
# (p: *T) is a stub line (`_gs_sub_sres`), TA15c a scalar store through `p[0]` in a generic is no stub.
refuse "DS1 p[0] through a *i64" "cannot assign 'p\[0\]: i64' from 'mkp', which returns the struct 'Q'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; p[0] = mkp(); return x; }'"$TE" one
refuse "DS2 w.pi[0], a *i64 field" "cannot assign 'w\.pi\[0\]: i64' from 'mkp'" "$DQ"'fn main(): i64 { var x = 5; var w: W; w.pi = &x; w.pi[0] = mkp(); return x; }'"$TE" one
refuse "DS3 gpi()[0], a : *i64 call" "cannot assign 'gpi()\[0\]: i64' from 'mkp'" "$DQ"'fn main(): i64 { gpi()[0] = mkp(); return GX; }'"$TE" one
refuse "DS4 GP[0], a *i64 global" "cannot assign 'GP\[0\]: i64' from 'mkp'" "$DQ"'fn main(): i64 { GP[0] = mkp(); return GX; }'"$TE" one
refuse "DS5 p[0] through a *f64, a method's result" "cannot assign 'p\[0\]: f64' from 'Q\.dup'" "$DQ"'fn main(): i64 { var q: Q; var x: f64 = 1.5; var p: *f64 = &x; p[0] = q.dup(); return 0; }'"$TE" one
refuse "DS6 p[1] through a *u8, an operator's result" "cannot assign 'p\[1\]: u8' from 'Q_add'" "$DQ"'fn main(): i64 { var q: Q; var b: u8[2]; var p: *u8 = &b; p[1] = q + q; return 0; }'"$TE" one
refuse "DS7 ((mkp())), wrapped" "cannot assign 'p\[0\]: i64' from 'mkp'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; p[0] = ((mkp())); return x; }'"$TE" one
refuse "DS8 fncall0(&mkp)" "cannot assign 'p\[0\]: i64' from 'mkp'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; p[0] = fncall0(&mkp); return x; }'"$TE" one
refuse "DS9 a for step" "cannot assign 'p\[0\]: i64' from 'mkp'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; for (var i = 0; i < 1; p[0] = mkp()) { i = i + 1; } return x; }'"$TE" one
refuse "DS10 mk3(), 24 B" "cannot assign 'p\[0\]: i64' from 'mk3', which returns the struct 'Q3'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; p[0] = mk3(); return x; }'"$TE" one
refuse "DS11 after the first top-level statement" "cannot assign 'GP\[0\]: i64' from 'mkp'" "$DQ"'syscall(1, 1, "", 0);
GP[0] = mkp();
fn main(): i64 { return GX; }'"$TE" one
refuse "DSK1 pp[0][0] of a **i64: the subscript's own one error" "cannot subscript 'pp'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; var pp: **i64 = &p; pp[0][0] = mkp(); return x; }'"$TE" one
accept "DSK2 p[0] = mkp().a, a field of the result" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; p[0] = mkp().a; return x - 300; }'"$TE" 33 'syscall(60, 33);'
accept "DSK3 p[0] = mk8(), an 8 B result keeps its word" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; p[0] = mk8(); return x; }'"$TE" 9 'syscall(60, 9);'
refuse "TA15 p[0] = mkp(); (p: *T) at i64: a stub (D99)" "generic 'gds' has no i64 (or other scalar) instance" "$TH"'fn gds<T>(x: T): i64 { var p: *T = &x; p[0] = mkp(); return 9; }
fn main(): i64 { return gds(5); }'"$TE" one
if grep -q "^  note: <source>:[0-9]*:[0-9]*: 'gds' stores a struct result over 8 bytes through 'p', a pointer to its type parameter\$" "$D/r.err"; then
    printf '  ok(refused): %-28s\n' "TA15n the note names p"; pass=$((pass+1))
else printf '  FAIL: %-34s %s\n' "TA15n the note" "$(grep '^  note' "$D/r.err" | head -1)"; fail=$((fail+1)); fi
refuse "TA15b ... at gds<i32>(5)" "generic 'gds' has no i64 (or other scalar) instance" "$TH"'fn gds<T>(x: T): i64 { var p: *T = &x; p[0] = mkp(); return 9; }
fn main(): i64 { return gds<i32>(5); }'"$TE" one
accept "TA15c p[0] = 7; (p: *T) at i64 is no stub" "$TH"'fn gdk<T>(x: T): i64 { var p: *T = &x; p[0] = 7; return x + 7; }
fn main(): i64 { return gdk(5); }'"$TE" 14 'syscall(60, 14);'

echo "=== 6.7.17 (D13): a struct result over 8 B stored through an UNTYPED pointer is refused, in D99's words without the type ==="
# issues/2026-10-21-struct-and-pointer-shapes-beyond-d97-d99-take-a-word.md row B1 — `*p = mkp();` with `var p = &x;`
# stored Q's first word (77), silently. UP0 the filed repro verbatim; UP1-UP13 every untyped operand and struct result;
# UPK1-UPK5 a field of the result, an 8 B result, a `Str`, a `*Q` of its own struct, `*(&q)` keep their store.
UPM="cannot assign '\*p' from 'mkp', which returns the struct 'Q' - store it through a '\*Q' or bind a field"
UP0S='struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn main(): i64 { var x = 0; var p = &x; *p = mkp(); return x; }
syscall(60, main());
'
refuse_at "UP0 the filed repro B1 verbatim (its one error, at the call)" "3:46: $(printf '%s' "$UPM" | tr -d '\\')" "$UP0S"
refuse "UP1 p = alloc(16)" "$UPM" "$DQ"'fn main(): i64 { var p = alloc(16); *p = mkp(); return load64(p); }'"$TE" one
refuse "UP2 *(p + 8) of an untyped p" "cannot assign '\*(p + 8)' from 'mkp'" "$DQ"'fn main(): i64 { var p = alloc(16); *(p + 8) = mkp(); return 0; }'"$TE" one
refuse "UP3 an untyped global" "cannot assign '\*GU' from 'mkp'" "$DQ"'var GU = 0;
fn main(): i64 { GU = &GX; *GU = mkp(); return GX; }'"$TE" one
refuse "UP4 after the first top-level statement" "cannot assign '\*GU' from 'mkp'" "$DQ"'var GU = &GX;
syscall(1, 1, "", 0);
*GU = mkp();
fn main(): i64 { return GX; }'"$TE" one
refuse "UP5 a method's result" "cannot assign '\*p' from 'Q\.dup'" "$DQ"'fn main(): i64 { var q: Q; var x = 5; var p = &x; *p = q.dup(); return x; }'"$TE" one
refuse "UP6 an operator's result" "cannot assign '\*p' from 'Q_add'" "$DQ"'fn main(): i64 { var q: Q; var x = 5; var p = &x; *p = q + q; return x; }'"$TE" one
refuse "UP7 ((mkp())), wrapped" "$UPM" "$DQ"'fn main(): i64 { var x = 5; var p = &x; *p = ((mkp())); return x; }'"$TE" one
refuse "UP8 fncall0(&mkp)" "$UPM" "$DQ"'fn main(): i64 { var x = 5; var p = &x; *p = fncall0(&mkp); return x; }'"$TE" one
refuse "UP9 mk3(), 24 B" "cannot assign '\*p' from 'mk3', which returns the struct 'Q3' - store it through a '\*Q3'" "$DQ"'fn main(): i64 { var x = 5; var p = &x; *p = mk3(); return x; }'"$TE" one
refuse "UP10 a for step" "$UPM" "$DQ"'fn main(): i64 { var x = 5; var p = &x; for (var i = 0; i < 1; *p = mkp()) { i = i + 1; } return x; }'"$TE" one
refuse "UP11 an untyped parameter" "$UPM" "$DQ"'fn f(p): i64 { *p = mkp(); return 0; }
fn main(): i64 { var x = 5; return f(&x); }'"$TE" one
refuse "UP12 a closure's captured untyped pointer" "$UPM" "$DQ"'fn main(): i64 { var x = 5; var p = &x; var f = || { *p = mkp(); return 0; }; fncall0(f); return x; }'"$TE" one
refuse "UP13 an untyped pointer in a generic" "$UPM" "$DQ"'fn gu<T>(p, v: T): i64 { *p = mkp(); return 0; }
fn main(): i64 { var x = 5; return gu(&x, 1); }'"$TE" one
accept "UPK1 *p = mkp().a, a field of the result" "$DQ"'fn main(): i64 { var x = 5; var p = &x; *p = mkp().a; return x - 300; }'"$TE" 33 'syscall(60, 33);'
accept "UPK2 an 8 B result keeps its word" "$DQ"'fn main(): i64 { var x = 5; var p = &x; *p = mk8(); return x; }'"$TE" 9 'syscall(60, 9);'
accept "UPK3 a Str result keeps its handle" "$DQ"'fn main(): i64 { alloc_init(); var x = 0; var p = &x; *p = mks(); var s: Str = x; return s.len(); }'"$TE" 3 'syscall(60, 3);'
accept "UPK4 *(&q) of a Q is q = mkp()" "$DQ"'fn main(): i64 { var q: Q; *(&q) = mkp(); return q.b - 400; }'"$TE" 44 'syscall(60, 44);'
accept "UPK5 an untyped store of a word keeps it" "$DQ"'fn main(): i64 { var x = 5; var p = &x; *p = 7; return x; }'"$TE" 7 'syscall(60, 7);'

echo "=== 6.7.17 (D16): a struct result over 8 B stored into a scalar FIELD or an array ELEMENT is refused, as its siblings ==="
# issues/2026-10-21-struct-and-pointer-shapes-beyond-d97-d99-take-a-word.md row B4 — `w.n = mkp();` and `buf[0] = mkp();`
# kept Q's first word (77; the globals' 154), silently. FE0-FE0c the filed repros verbatim; FE1-FE17 every field store
# (through a `*W`, a chain, a capture, a for step, top level, narrow / float / `*i64` / `*Pt` fields, a method, an
# operator, 24 B, wrapped, `fncall0`), every array element (an index variable, `u8[N]`, a global at top level), a
# slice's `.len`, a struct literal's element (positional, named, a global's); FE18-FE19 generics (a `Box<T>` field and
# literal at a scalar T are stub lines; a plain field is refused at the definition); FEK1-FEK7 what keeps its store.
FQ='include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
struct Q { a; b; }
struct Q3 { a; b; c; }
struct S8 { v; }
struct Pt { x; y; }
struct W { n; pi: *i64; }
struct WF { c: u8; d: i32; f: f64; pp: *Pt; q: Q; }
struct V { w: W; }
struct Box<T> { v: T; n; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn mk3(): Q3 { var q: Q3; q.a = 333; q.b = 1; q.c = 2; return q; }
fn mk8(): S8 { var s: S8; s.v = 9; return s; }
fn mks(): Str { return str_from("abc"); }
impl Q { fn dup(self): Q { return mkp(); } }
fn Q_add(l: Q, r: Q): Q { return mkp(); }
var GW = W { 1, 0 };
var GB: i64[2];
'
FTE='
fn main(): i64 { return g(); }
syscall(60, main());
'
FM="cannot assign 'w\.n: i64' from 'mkp', which returns the struct 'Q' - store it through a '\*Q' or bind a field"
refuse "FE0 the filed repro B4 verbatim: w.n = mkp();" "$FM" 'struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
struct W { n; pi: *i64; }
fn g(): i64 { var w = W { 1, 0 }; w.n = mkp(); return w.n; }
syscall(60, g());
' one
refuse "FE0b the filed repro: buf[0] = mkp();" "cannot assign 'buf\[0\]: i64' from 'mkp'" 'struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn g(): i64 { var buf: i64[2]; buf[0] = mkp(); return buf[0]; }
syscall(60, g());
' one
refuse "FE0c the filed repro: GW.n = mkp(); GB[1] = mkp(); (its two lines)" "cannot assign 'GW\.n: i64' from 'mkp'" "$FQ"'fn g(): i64 { GW.n = mkp(); GB[1] = mkp(); return GW.n + GB[1]; }'"$FTE" 2
if grep -q "cannot assign 'GB\[1\]: i64' from 'mkp'" "$D/r.err"; then printf '  ok(refused): %-40s\n' "FE0c its second line, GB[1]"; pass=$((pass+1))
else printf '  FAIL: %-46s %s\n' "FE0c its second line, GB[1]" "$(grep '^error' "$D/r.err" | sed -n 2p)"; fail=$((fail+1)); fi
refuse "FE1 pw.n through a *W" "cannot assign 'pw\.n: i64' from 'mkp'" "$FQ"'fn g(): i64 { var w = W { 1, 0 }; var pw: *W = &w; pw.n = mkp(); return w.n; }'"$FTE" one
refuse "FE2 a chain v.w.n" "cannot assign 'v\.w\.n: i64' from 'mkp'" "$FQ"'fn g(): i64 { var v: V; v.w.n = mkp(); return v.w.n; }'"$FTE" one
refuse "FE3 a closure's captured struct" "$FM" "$FQ"'fn g(): i64 { var w = W { 1, 0 }; var f = || { w.n = mkp(); return 0; }; fncall0(f); return w.n; }'"$FTE" one
refuse "FE4 a for step" "$FM" "$FQ"'fn g(): i64 { var w = W { 1, 0 }; for (var i = 0; i < 1; w.n = mkp()) { i = 1; } return w.n; }'"$FTE" one
refuse "FE5 after the first top-level statement" "cannot assign 'GW\.n: i64' from 'mkp'" "$FQ"'syscall(1, 1, "", 0);
GW.n = mkp();
fn g(): i64 { return GW.n; }'"$FTE" one
refuse "FE6 a u8 field" "cannot assign 'w\.c: u8' from 'mkp'" "$FQ"'fn g(): i64 { var w: WF; w.c = mkp(); return w.c; }'"$FTE" one
refuse "FE6b an i32 field" "cannot assign 'w\.d: i32' from 'mkp'" "$FQ"'fn g(): i64 { var w: WF; w.d = mkp(); return w.d; }'"$FTE" one
refuse "FE7 an f64 field" "cannot assign 'w\.f: f64' from 'mkp'" "$FQ"'fn g(): i64 { var w: WF; w.f = mkp(); return 0; }'"$FTE" one
refuse "FE8 a *i64 field" "cannot assign 'w\.pi: \*i64' from 'mkp'" "$FQ"'fn g(): i64 { var w = W { 1, 0 }; w.pi = mkp(); return 0; }'"$FTE" one
refuse "FE9 a *Pt field (another struct)" "cannot assign 'w\.pp: \*Pt' from 'mkp'" "$FQ"'fn g(): i64 { var w: WF; w.pp = mkp(); return 0; }'"$FTE" one
refuse "FE10 a method's result" "cannot assign 'w\.n: i64' from 'Q\.dup'" "$FQ"'fn g(): i64 { var q: Q; var w = W { 1, 0 }; w.n = q.dup(); return w.n; }'"$FTE" one
refuse "FE11 an operator's result" "cannot assign 'w\.n: i64' from 'Q_add'" "$FQ"'fn g(): i64 { var q: Q; var w = W { 1, 0 }; w.n = q + q; return w.n; }'"$FTE" one
refuse "FE12 mk3(), 24 B" "cannot assign 'w\.n: i64' from 'mk3', which returns the struct 'Q3'" "$FQ"'fn g(): i64 { var w = W { 1, 0 }; w.n = mk3(); return w.n; }'"$FTE" one
refuse "FE13 ((mkp())), wrapped" "$FM" "$FQ"'fn g(): i64 { var w = W { 1, 0 }; w.n = ((mkp())); return w.n; }'"$FTE" one
refuse "FE14 fncall0(&mkp)" "$FM" "$FQ"'fn g(): i64 { var w = W { 1, 0 }; w.n = fncall0(&mkp); return w.n; }'"$FTE" one
refuse "FE15 an element at an index variable" "cannot assign 'buf\[i\]: i64' from 'mkp'" "$FQ"'fn g(): i64 { var buf: i64[2]; var i = 1; buf[i] = mkp(); return buf[1]; }'"$FTE" one
refuse "FE15b a u8 array's element" "cannot assign 'b\[1\]: u8' from 'mkp'" "$FQ"'fn g(): i64 { var b: u8[4]; b[1] = mkp(); return b[1]; }'"$FTE" one
refuse "FE15c a global array at top level" "cannot assign 'GB\[0\]: i64' from 'mkp'" "$FQ"'syscall(1, 1, "", 0);
GB[0] = mkp();
fn g(): i64 { return GB[0]; }'"$FTE" one
refuse "FE16 a slice's .len" "cannot assign 's\.len: i64' from 'mkp'" "$FQ"'fn g(): i64 { var a: i64[2]; var s: [i64] = slice_of(&a, 2); s.len = mkp(); return 0; }
fn slice_of(p, n): i64 { return p; }'"$FTE" one
refuse "FE17 a struct literal's element" "cannot assign 'n: i64' from 'mkp'" "$FQ"'fn g(): i64 { var w = W { mkp(), 0 }; return w.n; }'"$FTE" one
refuse "FE17b ... a named element" "cannot assign 'n: i64' from 'mkp'" "$FQ"'fn g(): i64 { var w = W { n: mkp(), pi: 0 }; return w.n; }'"$FTE" one
refuse "FE17c ... a global's, in the declaration zone" "cannot assign 'n: i64' from 'mkp'" "$FQ"'var GW2 = W { mkp(), 0 };
fn g(): i64 { return GW2.n; }'"$FTE" one
refuse "FE18 b.v = mkp(); (b: Box<T>) at i64: a stub" "generic 'gf' has no i64 (or other scalar) instance" "$FQ"'fn gf<T>(x: T): i64 { var b: Box<T>; b.v = mkp(); return 7; }
fn g(): i64 { return gf(5); }'"$FTE" one
refuse "FE18b p.v through a *Box<T>: a stub" "generic 'gp' has no i64 (or other scalar) instance" "$FQ"'fn gp<T>(p: *Box<T>): i64 { p.v = mkp(); return 7; }
fn g(): i64 { var b: Box<i64>; return gp(&b); }'"$FTE" one
refuse "FE18c Box<T> { mkp(), 1 } at i64: a stub" "generic 'gl' has no i64 (or other scalar) instance" "$FQ"'fn gl<T>(x: T): i64 { var b = Box<T> { mkp(), 1 }; return 7; }
fn g(): i64 { return gl(5); }'"$FTE" one
refuse "FE19 a plain field in a generic: at its definition" "$FM" "$FQ"'fn gw<T>(x: T): i64 { var w = W { 1, 0 }; w.n = mkp(); return 7; }
fn g(): i64 { return 7; }'"$FTE" one
accept "FEK1 w.n = mkp().a, a field of the result" "$FQ"'fn g(): i64 { var w = W { 1, 0 }; w.n = mkp().a; return w.n - 300; }'"$FTE" 33 'syscall(60, 33);'
accept "FEK2 an 8 B result keeps its word" "$FQ"'fn g(): i64 { var w = W { 1, 0 }; w.n = mk8(); return w.n; }'"$FTE" 9 'syscall(60, 9);'
accept "FEK3 a Q field copies" "$FQ"'fn g(): i64 { var w: WF; w.q = mkp(); return w.q.b - 400; }'"$FTE" 44 'syscall(60, 44);'
accept "FEK4 b.v = mkp(); at T = Q copies" "$FQ"'fn gf<T>(x: T): i64 { var b: Box<T>; b.v = mkp(); return b.v.b - 400; }
fn g(): i64 { var q: Q; return gf(q); }'"$FTE" 44 'syscall(60, 44);'
accept "FEK5 Box<T> { mkp(), 1 } at T = Q copies (an untyped var)" "$FQ"'fn gl<T>(x: T): i64 { var b = Box<T> { mkp(), 1 }; return b.v.b - 400; }
fn g(): i64 { var q: Q; return gl(q); }'"$FTE" 44 'syscall(60, 44);'
accept "FEK6 buf[0] = mkp().b, a field of the result" "$FQ"'fn g(): i64 { var buf: i64[2]; buf[0] = mkp().b; return buf[0] - 400; }'"$FTE" 44 'syscall(60, 44);'
accept "FEK7 a Str result into an i64 field keeps its handle" "$FQ"'fn g(): i64 { alloc_init(); var w = W { 1, 0 }; w.n = mks(); var s: Str = w.n; return s.len(); }'"$FTE" 3 'syscall(60, 3);'

echo "=== 6.7.17 (D15): a compound assignment with a struct result over 8 B on its right is refused, in its = form's words ==="
# issues/2026-10-21-struct-and-pointer-shapes-beyond-d97-d99-take-a-word.md row B3 — `*p += mk3();` and `y += mk3();` added
# Q's first word (the filed repro exited 116), silently. CO0 the filed repro verbatim (its two lines, each its `=` form's
# words); CO1-CO19 every OP= destination (a typed / untyped / parameter / global name, top level, `*p` typed and untyped,
# `*(&x)`, a field, an f64 field, a captured struct's field, an array's and a `*i64`'s element, a global array, a
# `*i64` name, a slice's `.len`, a for step) and result (a method, an operator, `fncall0`); COK1-COK3 a field of the
# result, 8 B, a wrapped result's field.
CO0S='struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn mk3(): Q { var q: Q; q.a = 3; q.b = 4; return q; }
fn main(): i64 { var x = 10; var p: *i64 = &x; *p += mk3(); var y = 100; y += mk3(); return x + y; }
syscall(60, main());
'
refuse "CO0 the filed repro B3 verbatim (its two lines)" "cannot assign '\*p: i64' from 'mk3', which returns the struct 'Q' - store it through a '\*Q' or bind a field" "$CO0S" 2
if grep -q "cannot assign 'y' from 'mk3', which returns the struct 'Q' - declare 'y: Q' or bind a field" "$D/r.err"; then printf '  ok(refused): %-40s\n' "CO0 its second line, y (D33's words)"; pass=$((pass+1))
else printf '  FAIL: %-46s %s\n' "CO0 its second line, y" "$(grep '^error' "$D/r.err" | sed -n 2p)"; fail=$((fail+1)); fi
CQ="$FQ"'var GY = 5;
'
refuse "CO1 y -= mk3(); a typed i64" "cannot assign 'y: i64' from 'mk3', which returns the struct 'Q3' - declare 'y: Q3' or bind a field" "$CQ"'fn g(): i64 { var y: i64 = 100; y -= mk3(); return y; }'"$FTE" one
refuse "CO2 an i64 parameter" "cannot assign 'y: i64' from 'mkp'" "$CQ"'fn f(y: i64): i64 { y += mkp(); return y; }
fn g(): i64 { return f(1); }'"$FTE" one
refuse "CO3 an untyped global" "cannot assign 'GY' from 'mkp'" "$CQ"'fn g(): i64 { GY *= mkp(); return GY; }'"$FTE" one
refuse "CO4 after the first top-level statement" "cannot assign 'GY' from 'mkp'" "$CQ"'syscall(1, 1, "", 0);
GY += mkp();
fn g(): i64 { return GY; }'"$FTE" one
refuse "CO5 *p += through an untyped p" "cannot assign '\*p' from 'mkp'" "$CQ"'fn g(): i64 { var x = 10; var p = &x; *p += mkp(); return x; }'"$FTE" one
refuse "CO6 *(&x) += is x += (D27's words)" "cannot assign 'x: i64' from 'mkp'" "$CQ"'fn g(): i64 { var x: i64 = 1; *(&x) += mkp(); return x; }'"$FTE" one
refuse "CO7 a field" "cannot assign 'w\.n: i64' from 'mkp'" "$CQ"'fn g(): i64 { var w = W { 1, 0 }; w.n += mkp(); return w.n; }'"$FTE" one
refuse "CO8 an f64 field (no float warning beside it)" "cannot assign 'w\.f: f64' from 'mkp'" "$CQ"'fn g(): i64 { var w: WF; w.f += mkp(); return 0; }'"$FTE" one
if grep -q '^warning' "$D/r.err"; then printf '  FAIL: %-46s %s\n' "CO8w no warning" "$(grep '^warning' "$D/r.err" | head -1)"; fail=$((fail+1))
else printf '  ok(refused): %-40s\n' "CO8w no warning beside it"; pass=$((pass+1)); fi
refuse "CO9 a closure's captured struct's field" "cannot assign 'w\.n: i64' from 'mkp'" "$CQ"'fn g(): i64 { var w = W { 1, 0 }; var f = || { w.n += mkp(); return 0; }; fncall0(f); return 0; }'"$FTE" one
refuse "CO10 an array's element" "cannot assign 'b\[0\]: i64' from 'mkp'" "$CQ"'fn g(): i64 { var b: i64[2]; b[0] = 1; b[0] += mkp(); return b[0]; }'"$FTE" one
refuse "CO11 a global array's element" "cannot assign 'GB\[1\]: i64' from 'mkp'" "$CQ"'fn g(): i64 { GB[1] |= mkp(); return GB[1]; }'"$FTE" one
refuse "CO12 a *i64's element p[0]" "cannot assign 'p\[0\]: i64' from 'mkp'" "$CQ"'fn g(): i64 { var x = 1; var p: *i64 = &x; p[0] += mkp(); return x; }'"$FTE" one
refuse "CO13 a *i64 name p += (D32's words)" "cannot assign 'p: \*i64' from 'mkp', which returns the struct 'Q' - declare 'p: Q' and take" "$CQ"'fn g(): i64 { var x = 1; var p: *i64 = &x; p += mkp(); return 0; }'"$FTE" one
refuse "CO14 a slice's .len" "cannot assign 's\.len: i64' from 'mkp'" "$CQ"'fn g(): i64 { var a: i64[2]; var s: [i64] = sl(&a, 2); s.len += mkp(); return 0; }
fn sl(p, n): i64 { return p; }'"$FTE" one
refuse "CO15 a for step" "cannot assign 'y' from 'mkp'" "$CQ"'fn g(): i64 { var y = 1; for (var i = 0; i < 1; y += mkp()) { i = 1; } return y; }'"$FTE" one
refuse "CO16 a method's result" "cannot assign 'y' from 'Q\.dup'" "$CQ"'fn g(): i64 { var q: Q; var y = 1; y += q.dup(); return y; }'"$FTE" one
refuse "CO17 an operator's result" "cannot assign 'y' from 'Q_add'" "$CQ"'fn g(): i64 { var q: Q; var y = 1; y += q + q; return y; }'"$FTE" one
refuse "CO18 fncall0(&mkp)" "cannot assign 'y' from 'mkp'" "$CQ"'fn g(): i64 { var y = 1; y += fncall0(&mkp); return y; }'"$FTE" one
refuse "CO19 a field's for step" "cannot assign 'w\.n: i64' from 'mkp'" "$CQ"'fn g(): i64 { var w = W { 1, 0 }; for (var i = 0; i < 1; w.n += mkp()) { i = 1; } return w.n; }'"$FTE" one
accept "COK1 y += mkp().a, a field of the result" "$CQ"'fn g(): i64 { var y = 1; y += mkp().a; return y - 300; }'"$FTE" 34 'syscall(60, 34);'
accept "COK2 an 8 B result keeps its word" "$CQ"'fn g(): i64 { var y = 1; y += mk8(); return y; }'"$FTE" 10 'syscall(60, 10);'
accept "COK3 y += (mkp()).b, a wrapped result's field" "$CQ"'fn g(): i64 { var y = 1; y += (mkp()).b; return y - 400; }'"$FTE" 45 'syscall(60, 45);'
# 6.7.17 (D15, its review) — THROUGH A GENERIC'S T: at a scalar instance `y += R` (y: T), `*p += R` / `p[0] -= R`
# (p: *T), `b.v |= R` (b: *Box<T>) and a for step combined Q's first word (78), silently (CO24b: `gc<i32>` was refused
# in the instance's words, "cannot assign 'y: T'", where `y = R` is a stub): the base parse leaves a T-typed store to
# the D1 stub scan (`_dsr_tdep`), which read only the `=` forms. Now it reads `OP=` as its `=` form (`_gs_cop_de`,
# `_gs_cop_asg`): no scalar instance, the call refused naming the line. COK4 / COK5: 8 B and a field of the result
# keep their word.
CGM="generic 'gc' has no i64 (or other scalar) instance"
refuse "CO20 y += mkp(); (y: T) at i64: a stub" "$CGM" "$CQ"'fn gc<T>(x: T): i64 { var y: T = x; y += mkp(); return 7; }
fn g(): i64 { return gc(1); }'"$FTE" one
refuse "CO21 *p += mkp(); (p: *T) at i64: a stub" "$CGM" "$CQ"'fn gc<T>(p: *T): i64 { *p += mkp(); return 7; }
fn g(): i64 { var z = 1; return gc(&z); }'"$FTE" one
refuse "CO22 p[0] -= mkp(); (p: *T) at i64: a stub" "$CGM" "$CQ"'fn gc<T>(p: *T): i64 { p[0] -= mkp(); return 7; }
fn g(): i64 { var z = 1; return gc(&z); }'"$FTE" one
refuse "CO23 b.v |= mkp(); (b: *Box<T>) at i64: a stub" "$CGM" "$CQ"'fn gc<T>(b: *Box<T>): i64 { b.v |= mkp(); return 7; }
fn g(): i64 { var b: Box<i64>; b.v = 1; return gc(&b); }'"$FTE" one
refuse "CO24 a for step y += mkp(); (y: T) at i64: a stub" "$CGM" "$CQ"'fn gc<T>(x: T): i64 { var y: T = x; for (var i = 0; i < 1; y += mkp()) { i = 1; } return 7; }
fn g(): i64 { return gc(1); }'"$FTE" one
refuse "CO24b gc<i32>(1): the stub's words, as y = mkp() has" "$CGM" "$CQ"'fn gc<T>(x: T): i64 { var y: T = x; y += mkp(); return 7; }
fn g(): i64 { return gc<i32>(1); }'"$FTE" one
accept "COK4 *p += mk8(); (p: *T), 8 B keeps its word" "$CQ"'fn gc<T>(p: *T): i64 { *p += mk8(); return 0; }
fn g(): i64 { var z = 1; gc(&z); return z; }'"$FTE" 10 'syscall(60, 10);'
accept "COK5 y += mkp().a; (y: T), a field of the result" "$CQ"'fn gc<T>(x: T): i64 { var y: T = x; y += mkp().a; return y - 300; }
fn g(): i64 { return gc(1); }'"$FTE" 34 'syscall(60, 34);'

# TV (6.7.16, the user's D102, 2026-10-20; issues/archived/2026-10-20-generic-untyped-local-from-type-parameter-value-refused.md)
# — AN UNTYPED `var y = x;` HOLDING A VALUE OF T TAKES T'S TYPE IN EACH INSTANCE. The stub scan saw no T-typed name in y,
# so the i64 base parsed `y.b` at the definition: the filed repro (TV0) was rc 1, "no struct type in scope for 'y'",
# though valid at T = Q, and `y = mkp();` on it had 6.7.15's D33 words. y is now a T-typed name (`_gs_uvar` /
# `_gs_vkind`, parse_fn_def.cyr) — from x, wrapped, another untyped var, a generic call's `: U` / `: G<..U..>` result bound
# to such a value, a carrier `b: Box<T>` by value — so its struct uses make the generic a stub, refused at a scalar call
# with the stub's note (TV1-TV5), compiled when never called (TV6), and a bounded `y.show()` is a bounded site
# (`_bnr_uvar`; tests/tcyr/crossos/generic_struct_only_lines.tcyr V1-V15 run the struct instances on every backend). A
# `*T` source and `x + 1` stay untyped, as the instance types them (TV7, TV8). A bounded `y.show()` / `z.show()` (z =
# `id(x)`) calls the bound's impl at i64 (TV9) and at Pt (TV9p); with no `impl Show for i64` the bound's refusal (TV9n).
# TVX: TV1 / TV2 on aarch64 / cx / PE.
# (a scratch copy of the tree with the one change, its 2-stage cycc, this gate run from it with CYCC=:)
#   MTV1 the tree before D102 (7fd3db958)                -> RED 17: TV0 TV6 TV9 (refused at the definition), TV1-TV5
#                                                         TV1n TV2n TV5n ("no struct type", D33's words), TVX TV1 TV2 x3
#   MTV2 `_gs_uvar` adding nothing                      -> RED 10: TV0 TV1 TV1n TV3 TV4 TV5 TV5n, TVX TV1 x3
#   MTV3 `_gs_dst_tp` without its untyped-var arm       -> RED 5: TV2 TV2n (D33's words), TVX TV2 x3
#   MTV4 `_bnr_uvar` recording nothing                  -> RED 1: TV9 (refused as a stub at i64)
#   MTV5 `_gs_vcall` answering 0 (no generic call)      -> RED 2: TV3, TV9 (`z = id(x)`: refused at the definition)
echo "=== an untyped var y = x; holding a value of T takes T's type in each instance (6.7.16, the user's D102) ==="
TV0='include "lib/syscalls.cyr"
struct Q { a; b; }
fn g<T>(x: T): i64 { var y = x; return y.b; }
fn main(): i64 { var q = Q { 3, 4 }; return g(q); }
syscall(60, main());
'
accept "TV0 the filed repro verbatim: 4" "$TV0" 4 'syscall(60, 4);'
TVH='include "lib/syscalls.cyr"
struct Q { a; b; }
struct Box<T> { v: T; n; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn id<T>(v: T): T { return v; }
fn vb<T>(x: T): i64 { return x.b; }
'
TV1="$TVH"'fn g<T>(x: T): i64 { var y = x; return y.b; }
fn main(): i64 { return g(5); }
syscall(60, main());
'
TV2="$TVH"'fn g<T>(x: T): i64 { var y = x; y = mkp(); return 9; }
fn main(): i64 { return g(5); }
syscall(60, main());
'
# $1 label  $2 the note's text (after "note: <source>:")
tv_note() {
    if grep -qF "  note: <source>:$2" "$D/r.err"; then printf '  ok(refused): %-28s\n' "$1"; pass=$((pass+1))
    else printf '  FAIL: %-34s %s\n' "$1" "$(grep '^  note' "$D/r.err" | head -1)"; fail=$((fail+1)); fi
}
refuse "TV1 g(5): y.b, y = x's" "$TGM" "$TV1" one
tv_note "TV1n the note names 7:40" "7:40: 'g' takes a field of a value typed by its type parameter"
refuse "TV2 g(5): y = mkp(), y = x's (D1)" "$TGM" "$TV2" one
tv_note "TV2n the note names 7:33" "7:33: 'g' stores a struct result over 8 bytes in 'y', typed by its type parameter"
refuse "TV3 g(5): var y = id(x); y.b" "$TGM" "$TVH"'fn g<T>(x: T): i64 { var y = id(x); return y.b; }
fn main(): i64 { return g(5); }
syscall(60, main());
' one
refuse "TV4 g(bx), Box<i64>: var y = b; y.v.b" "$TGM" "$TVH"'fn g<T>(b: Box<T>): i64 { var y = b; return y.v.b; }
fn main(): i64 { var bx: Box<i64>; bx.v = 1; return g(bx); }
syscall(60, main());
' one
refuse "TV5 g(5): y forwarded to a stub" "$TGM" "$TVH"'fn g<T>(x: T): i64 { var y = x; return vb(y); }
fn main(): i64 { return g(5); }
syscall(60, main());
' one
tv_note "TV5n the forward's note" "7:40: 'g' forwards its type parameter to 'vb'"
accept "TV6 never called: compiles" "$TVH"'fn g<T>(x: T): i64 { var y = x; y = mkp(); return y.b; }
fn main(): i64 { return 0; }
syscall(60, main());
' 0 'syscall(60, 0);'
refuse_at "TV7 var y = p; (p: *T): untyped" "7:44: $SN 'y'$SA" "$TVH"'fn g<T>(p: *T): i64 { var y = p; return y.b; }
fn main(): i64 { return 0; }
syscall(60, main());
'
refuse_at "TV8 var y = x + 1;: untyped" "7:47: $SN 'y'$SA" "$TVH"'fn g<T>(x: T): i64 { var y = x + 1; return y.b; }
fn main(): i64 { return 0; }
syscall(60, main());
'
TV9H='include "lib/syscalls.cyr"
struct Pt { x; y; }
trait Show { fn show(self): i64; }
impl Show for Pt { fn show(self): i64 { return self.x * 10 + self.y; } }
fn id<T>(v: T): T { return v; }
fn g<T: Show>(x: T): i64 { var y = x; var z = id(x); return y.show() + z.show(); }
'
accept "TV9 bounded y.show() at i64: impl Show for i64" "$TV9H"'impl Show for i64 { fn show(self): i64 { return self + 100; } }
fn main(): i64 { return g(5); }
syscall(60, main());
' 210 'syscall(60, 210);'
accept "TV9p bounded y.show() at Pt" "$TV9H"'fn main(): i64 { var p = Pt { 3, 4 }; return g(p); }
syscall(60, main());
' 68 'syscall(60, 68);'
refuse "TV9n bounded, no impl Show for i64: the bound's" "does not implement trait 'Show'" "$TV9H"'fn main(): i64 { return g(5); }
syscall(60, main());
' one
# TV10-TV10s (the f16b review of D102, 2026-10-21): neither a chain of untyped copies nor a nest of generic calls is cut
# short — y takes T's type at any length, as each instance types it. `_gs_vkind` had one 8-level budget for both, so a
# 10-copy chain (TV10), a chain of 9 mixing copies and `id(..)` (TV10b) and `id(..)` 9 deep (TV10c) stayed untyped:
# "no struct type in scope for 'y10'" at the definition at T = Q (tests/tcyr/crossos/generic_struct_only_lines.tcyr
# V16-V18 run them), and at 5 instead of the stub's refusal. A declaration whose own initializer holds the use is no T
# value, and the walk ends there (TV10s: `var z = z;`, the same two errors as the tree before D102).
#   MTV6 the lane head before the fix (0ae54834c)           -> RED 11: TV10 TV10n TV10b TV10bn TV10c, TVX TV10 TV10b x3
#   MTV7 `_gs_vkind` without the `e > u` guard              -> TV10s never ends (the walk re-reads `var z = z;`)
TV10="$TVH"'fn g<T>(x: T): i64 { var y1 = x; var y2 = y1; var y3 = y2; var y4 = y3; var y5 = y4; var y6 = y5; var y7 = y6; var y8 = y7; var y9 = y8; var y10 = y9; return y10.b; }
fn main(): i64 { return g(5); }
syscall(60, main());
'
TV10b="$TVH"'fn g<T>(x: T): i64 { var a = x; var b = id(a); var c = b; var d = id(c); var e = d; var f = id(e); var h = f; var i = id(h); var j = i; return j.b; }
fn main(): i64 { return g(5); }
syscall(60, main());
'
refuse "TV10 g(5): a 10-copy chain's y10.b" "$TGM" "$TV10" one
tv_note "TV10n the note names 7:159" "7:159: 'g' takes a field of a value typed by its type parameter"
refuse "TV10b g(5): copies and id() mixed, 9" "$TGM" "$TV10b" one
tv_note "TV10bn the note names 7:144" "7:144: 'g' takes a field of a value typed by its type parameter"
refuse "TV10c g(5): id(..) nested 9 deep" "$TGM" "$TVH"'fn g<T>(x: T): i64 { var y = id(id(id(id(id(id(id(id(id(x))))))))); return y.b; }
fn main(): i64 { return g(5); }
syscall(60, main());
' one
refuse_at "TV10s var z = z; ends: the two errors" "7:31: undefined variable 'z' (missing include or enum?)|7:43: $SN 'z'$SA" "$TVH"'fn g<T>(x: T): i64 { var z = z; return z.b; }
fn main(): i64 { return 0; }
syscall(60, main());
'
# TV11-TV11l (the f16b review of D102, 2026-10-21): a name a closure parameter, a for-in variable or a destructure's
# later name rebinds is not the T value. `_tok_name_decl` reads only `var NAME` and the fn's own parameters, so D102's
# readers reached g's `x: T` past `|x|`, `for x in` and `var q, x = two();` (and `idp(p)` past `|p|`, `first(b)` past
# `|b|`): y counted as T-typed, so a never-called g compiled (TV11, the review's repro verbatim, and TV11c-TV11f; each
# refused at the definition before D102), `g(5)` named a field of a T value in its note (TV11b), and a bounded
# `y.show()` called the bound's impl on the word — SIGSEGV at T = Pt (TV11g-TV11i). Each is again the no-struct line at
# the definition (`_gs_rebound`, parse_fn_def.cyr); the same name read after the closure, after the loop, or after a
# block holding the destructure is the T value (TV11j-TV11l; generic_struct_only_lines.tcyr V19-V21 on every backend).
#   MTV8 the tree before this fix (d458f47dc)               -> RED 9: TV11 TV11b-TV11i (TV11g-TV11i: rc 0, exit 139)
#   MTV9 `_gs_rebound` without its for-in / destructure arms -> RED 4: TV11e TV11f TV11h TV11i
TVR='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
struct Box<T> { v: T; n; }
fn idp<T>(p: *T): T { var r: T = *p; return r; }
fn first<T>(b: Box<T>): T { var r: T = b.v; return r; }
fn two(): (i64, i64) { return (1, 2); }
'
TVM='fn main(): i64 { return 0; }
syscall(60, main());
'
refuse_at "TV11 |x| { var y = x; y.b }: the repro" "4:57: $SN 'y'$SA" 'include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
fn g<T>(x: T): i64 { var f = |x| { var y = x; return y.b; }; return fncall1(f, 5); }
fn main(): i64 { return 0; }'
refuse_at "TV11b g(5): the no-struct line, no stub" "4:57: $SN 'y'$SA" 'include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
fn g<T>(x: T): i64 { var f = |x| { var y = x; return y.b; }; return fncall1(f, 5); }
fn main(): i64 { return g(5); }
syscall(60, main());
'
refuse_at "TV11c |p| { var y = idp(p); }" "8:63: $SN 'y'$SA" "$TVR"'fn g<T>(p: *T): i64 { var f = |p| { var y = idp(p); return y.b; }; return fncall1(f, 5); }
'"$TVM"
refuse_at "TV11d |b| { var y = first(b); }" "8:69: $SN 'y'$SA" "$TVR"'fn g<T>(b: Box<T>): i64 { var f = |b| { var y = first(b); return y.b; }; return fncall1(f, 5); }
'"$TVM"
refuse_at "TV11e for x in 0..3 { var y = x; }" "8:71: $SN 'y'$SA" "$TVR"'fn g<T>(x: T): i64 { var s = 0; for x in 0..3 { var y = x; s = s + y.b; } return s; }
'"$TVM"
refuse_at "TV11f var q, x = two(); var y = x;" "8:62: $SN 'y'$SA" "$TVR"'fn g<T>(x: T): i64 { var q, x = two(); var y = x; return y.b + q; }
'"$TVM"
TVB='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Pt { x; y; }
trait Show { fn show(self): i64; }
impl Show for Pt { fn show(self): i64 { return self.x * 10 + self.y; } }
impl Show for i64 { fn show(self): i64 { return self + 100; } }
fn two(): (i64, i64) { return (1, 2); }
'
TVBM='fn main(): i64 { var p = Pt { 2, 4 }; return g(p); }
syscall(60, main());
'
refuse_at "TV11g bounded |x| y.show() at Pt" "8:66: $SN 'y'$SM" "$TVB"'fn g<T: Show>(x: T): i64 { var f = |x| { var y = x; return y.show(); }; return fncall1(f, 5); }
'"$TVBM"
refuse_at "TV11h bounded for x in: y.show() at Pt" "8:80: $SN 'y'$SM" "$TVB"'fn g<T: Show>(x: T): i64 { var s = 0; for x in 0..2 { var y = x; s = s + y.show(); } return s; }
'"$TVBM"
refuse_at "TV11i bounded var q, x: y.show() at Pt" "8:70: $SN 'y'$SM" "$TVB"'fn g<T: Show>(x: T): i64 { var q, x = two(); var y = x; return y.show() + q; }
'"$TVBM"
TVQM='fn main(): i64 { var q = Q { 3, 4 }; return g(q); }
syscall(60, main());
'
accept "TV11j |x| closed before var y = x;: x's" "$TVR"'fn g<T>(x: T): i64 { var f = |x| { return x + 1; }; var y = x; return y.b + fncall1(f, 1); }
'"$TVQM" 6 'syscall(60, 6);'
accept "TV11k for x in, then var y = x;: x's" "$TVR"'fn g<T>(x: T): i64 { var s = 0; for x in 0..3 { s = s + x; } var y = x; return y.b + s; }
'"$TVQM" 7 'syscall(60, 7);'
accept "TV11l var q, x in a closed block: x's" "$TVR"'fn g<T>(x: T): i64 { var r = 0; if (r == 0) { var q, x = two(); r = q + x; } var y = x; return y.b + r; }
'"$TVQM" 7 'syscall(60, 7);'

# RB (6.7.17, the user's D1, 2026-10-22; issues/2026-10-21-generic-tparam-name-rebound-by-closure-param-forin-destructure-
# read-as-t-sigsegv.md) — A NAME A CLOSURE PARAMETER, A FOR-IN VARIABLE OR A DESTRUCTURE'S LATER NAME REBINDS IS ITS OWN,
# UNTYPED, AS A PLAIN FN READS IT — g's own `x: T` too, not only D102's `var y = x;` (TV11). The scans' name tables
# (`_gsn`, `_gcr`, `_bnr_tab`) and `_tok_name_decl`'s readers had no scope for them, so in `fn g<T: Show>(x: T)` a
# closure's `|x| { return x.show(); }`, `for x in 0..2 { .. x.show() .. }` and `var q, x = two(); x.show()` were bounded
# sites of g's x: rc 0, SIGSEGV at T = Pt (RB0-RB2, the filed repros), `g(7)` exit 105 (RB3); and `x.b`, `x = mkp();`,
# `return &n;`, `p[0] = mkp();`, a forward into a stub, a carrier's `b.v.b` / `gx(b)` on the rebound name made the generic
# a stub — compiled never called (RB4-RB14; RB16 / RB16b a rebound struct receiver `|p| p.pick(t)` / `p.mk()` read as
# g's `p: P`), refused at a scalar call with a note blaming T. Each is now the plain fn's
# refusal at the definition (`_gsn_live`, `_gcr_live`, `_gs_rebound_at`, parse_fn_def.cyr). The rebinding's own reach
# is the parser's: a range's end bound reads the loop variable (RB15-RB15c), a destructure's right-hand side the enclosing
# name (RBK6, which the new readers had refused), a range's start bound the enclosing one (RBK7). Controls RBK1-RBK5:
# g's own x after a rebinding closes, a captured T value in a closure, a carrier after `|b|` (RBK8: a captured `p`) — unchanged
# (tests/tcyr/crossos/generic_struct_only_lines.tcyr V22-V28 run them on every backend). RBX: RB0 RB1 RB2 RB4 on
# aarch64 / cx / PE. (trait_bounds_checked.sh RB: a bounded site on a rebound receiver is no site.)
# (a scratch copy of the tree with the one change, its 2-stage cycc, this gate run from it with CYCC=:)
#   MRB1 the tree before (e65604d5d)                         -> RED 32: RB0-RB3 (rc 0, exit 139 / 105), RB4 RB4b RB5
#                                                             RB6-RB14 RB15b RB15c RB16 RB16b (compiled, or the stub's words; RB15
#                                                             was refused: `..x` read as a field name), RBX x3 (12)
#   MRB2 `_bnd_sites` without its rebound test               -> RED 13: RB0-RB3, RBX RB0 RB1 RB2 x3 (rc 0)
#   MRB3 `_gsn_live` = `_gsn_has` (the T-name table by name)  -> RED 13: RB3 RB4 RB4b RB5 RB6 RB8 RB13 RB14 RB15b RB15c,
#                                                             RBX RB4 x3
#   MRB4 `_gs_mvar_holds` reading its right-hand side        -> RED 2: RBK6 RBK6n
#   MRB5 `_gs_forin_holds` without its end-bound arm          -> RED 2: RB15b RB15c
#   MRB6 `_bnd_fsite` without its rebound test               -> GREEN here (its refusal is the base parse's either way);
#                                                             RED in trait_bounds_checked.sh RB4 (the contract's words)
#   MRB7 `_gs_recv_sid` without its rebound test             -> RED 2: RB16 RB16b (compiled: the stub)
echo "=== a name a closure's parameter, a for-in variable or a destructure rebinds is untyped (6.7.17, the user's D1) ==="
RB0='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Pt { x; y; }
trait Show { fn show(self): i64; }
impl Show for Pt { fn show(self): i64 { return self.x * 10 + self.y; } }
impl Show for i64 { fn show(self): i64 { return self + 100; } }
fn g<T: Show>(x: T): i64 { var f = |x| { return x.show(); }; return fncall1(f, 5); }
fn main(): i64 { var p = Pt { 2, 4 }; return g(p); }
syscall(60, main());
'
RBI='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Pt { x; y; }
trait Show { fn show(self): i64; }
impl Show for Pt { fn show(self): i64 { return self.x * 10 + self.y; } }
impl Show for i64 { fn show(self): i64 { return self + 100; } }
'
RBPM='fn main(): i64 { var p = Pt { 2, 4 }; return g(p); }
syscall(60, main());
'
RB1="$RBI"'fn g<T: Show>(x: T): i64 { var s = 0; for x in 0..2 { s = s + x.show(); } return s; }
'"$RBPM"
RB2="$RBI"'fn two(): (i64, i64) { return (1, 2); }
fn g<T: Show>(x: T): i64 { var q, x = two(); return x.show() + q; }
'"$RBPM"
RB4='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
fn g<T>(x: T): i64 { var f = |x| { return x.b; }; return fncall1(f, 5); }
fn main(): i64 { return 0; }
syscall(60, main());
'
refuse_at "RB0 the filed repro: |x| x.show() at Pt" "7:55: $SN 'x'$SM" "$RB0"
refuse_at "RB1 the filed for x in: x.show() at Pt" "7:69: $SN 'x'$SM" "$RB1"
refuse_at "RB2 the filed var q, x: x.show() at Pt" "8:59: $SN 'x'$SM" "$RB2"
refuse_at "RB3 g(7): exit 105 before" "7:55: $SN 'x'$SM" "$RBI"'fn g<T: Show>(x: T): i64 { var f = |x| { return x.show(); }; return fncall1(f, 5); }
fn main(): i64 { return g(7); }
syscall(60, main());
'
refuse_at "RB4 the review's |x| x.b, never called" "4:46: $SN 'x'$SA" "$RB4"
refuse_at "RB4b ... g(5): no stub, no T note" "4:46: $SN 'x'$SA" 'include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
fn g<T>(x: T): i64 { var f = |x| { return x.b; }; return fncall1(f, 5); }
fn main(): i64 { return g(5); }
syscall(60, main());
'
refuse_at "RB5 for x in 0..3 { x.b }, never called" "4:60: $SN 'x'$SA" 'include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
fn g<T>(x: T): i64 { var s = 0; for x in 0..3 { s = s + x.b; } return s; }
fn main(): i64 { return 0; }
syscall(60, main());
'
RBH='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct S8 { a; }
trait Show { fn show(self): i64; }
impl Show for Pt { fn show(self): i64 { return self.x * 10 + self.y; } }
impl Show for i64 { fn show(self): i64 { return self + 100; } }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn vb<T>(x: T): i64 { return x.b; }
fn gx<T>(b: Box<T>): i64 { return b.v.b; }
fn two(): (i64, i64) { return (1, 2); }
fn pr(a: i64): (i64, i64) { return (a, a + 1); }
'
RBM='fn main(): i64 { return 0; }
syscall(60, main());
'
RBVB="generic 'vb' has no i64 (or other scalar) instance: it uses its type parameter as a struct (a '.field' on a T-typed value, \`&x\` of one returned as a struct, or a struct result over 8 bytes stored in one — directly or in a generic it forwards T to) — pass a struct argument, or name a struct type argument"
RBGX="$(printf '%s' "$RBVB" | sed "s/'vb'/'gx'/")"
RBUM="cannot assign 'y' from 'mkp', which returns the struct 'Q' - declare 'y: Q' or bind a field"
refuse_at "RB6 var q, x = two(); x.b" "15:51: $SN 'x'$SA" "$RBH"'fn g<T>(x: T): i64 { var q, x = two(); return x.b + q; }
'"$RBM"
refuse_at "RB7 |b| b.v.b (a carrier)" "15:51: $SN 'b'$SA" "$RBH"'fn g<T>(b: Box<T>): i64 { var f = |b| { return b.v.b; }; return fncall1(f, 5); }
'"$RBM"
refuse_at "RB8 |x| vb(x) (a forward)" "15:46: $RBVB" "$RBH"'fn g<T>(x: T): i64 { var f = |x| { return vb(x); }; return fncall1(f, 5); }
'"$RBM"
refuse_at "RB9 |b| gx(b) (a carrier forward)" "15:51: $RBGX" "$RBH"'fn g<T>(b: Box<T>): i64 { var f = |b| { return gx(b); }; return fncall1(f, 5); }
'"$RBM"
refuse_at "RB10 |y| { y = mkp(); } (D33)" "15:40: $RBUM" "$RBH"'fn g<T>(y: T): i64 { var f = |y| { y = mkp(); return 0; }; return fncall1(f, 5); }
'"$RBM"
refuse_at "RB11 for n in: return &n; (D18)" "15:44: a fn returning the struct \`S8\` takes a value of that struct, or a pointer to one — \`&n\` is the address of n's slot, not a struct" "$RBH"'fn g<T>(n: T): S8 { for n in 0..2 { return &n; } var r: S8; return r; }
'"$RBM"
refuse_at "RB12 |p| { p[0] = mkp(); }" "15:38: cannot subscript 'p': it is not a typed array, a *T or a slice local - declare \`var a: T[N]\` or \`p: *T\` (T an integer, f64, f32 or bool), or load / store at an explicit byte offset" "$RBH"'fn g<T>(p: *T): i64 { var f = |p| { p[0] = mkp(); return 0; }; return fncall1(f, 5); }
'"$RBM"
refuse_at "RB13 for x in: vb(x)" "15:48: $RBVB" "$RBH"'fn g<T>(x: T): i64 { for x in 0..2 { return vb(x); } return 0; }
'"$RBM"
refuse_at "RB14 var q, x = two(); vb(x)" "15:50: $RBVB" "$RBH"'fn g<T>(x: T): i64 { var q, x = two(); return vb(x) + q; }
'"$RBM"
refuse_at "RB15 for x in 0..x.b: the loop's x" "15:49: $SN 'x'$SA" "$RBH"'fn g<T>(x: T): i64 { var s = 0; for x in 0..x.b { s = s + 1; } return s; }
'"$RBM"
refuse_at "RB15b for x in 0..(x.b): the loop's x" "15:49: $SN 'x'$SA" "$RBH"'fn g<T>(x: T): i64 { var s = 0; for x in 0..(x.b) { s = s + 1; } return s; }
'"$RBM"
refuse_at "RB15c for x in 0..vb(x): the loop's x" "15:48: $RBVB" "$RBH"'fn g<T>(x: T): i64 { var s = 0; for x in 0..vb(x) { s = s + 1; } return s; }
'"$RBM"
RBP='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Q { a; b; }
struct P { k; }
impl P { fn pick<U>(self, u: U): i64 { return u.b; } }
impl P { fn mk(self): Q { var q: Q; q.a = 1; q.b = 2; return q; } }
'
refuse_at "RB16 |p| p.pick(t): p the closure's" "7:55: $SN 'p'$SM" "$RBP"'fn g<T>(p: P, t: T): i64 { var f = |p| { return p.pick(t); }; return fncall1(f, 5); }
'"$RBM"
refuse_at "RB16b |p| { var y: T = p.mk(); }" "7:57: $SN 'p'$SM" "$RBP"'fn g<T>(p: P, t: T): i64 { var f = |p| { var y: T = p.mk(); return 0; }; return fncall1(f, 5); }
'"$RBM"
accept "RBK8 |k| p.pick(t) + k: g's p, captured" "$RBP"'fn g<T>(p: P, t: T): i64 { var f = |k| { return p.pick(t) + k; }; return fncall1(f, 1); }
fn main(): i64 { var p = P { 1 }; var q = Q { 3, 4 }; return g(p, q); }
syscall(60, main());
' 5 'syscall(60, 5);'
RBQM='fn main(): i64 { var q = Q { 3, 4 }; return g(q); }
syscall(60, main());
'
accept "RBK1 x.show() after |x| and for x in close" "$RBH"'fn g<T: Show>(x: T): i64 { var f = |x| { return x + 1; }; var s = 0; for x in 0..2 { s = s + x; } return x.show() + fncall1(f, 1) + s; }
'"$RBPM" 27 'syscall(60, 27);'
accept "RBK2 x.show() after a block's var q, x" "$RBH"'fn g<T: Show>(x: T): i64 { var r = 0; if (r == 0) { var q, x = two(); r = q + x; } return x.show() + r; }
'"$RBPM" 27 'syscall(60, 27);'
accept "RBK3 a captured x: |k| x.show() + k" "$RBH"'fn g<T: Show>(x: T): i64 { var f = |k| { return x.show() + k; }; return fncall1(f, 5); }
'"$RBPM" 29 'syscall(60, 29);'
accept "RBK4 x.b after |x| closes" "$RBH"'fn g<T>(x: T): i64 { var f = |x| { return x + 1; }; return x.b + fncall1(f, 1); }
'"$RBQM" 6 'syscall(60, 6);'
accept "RBK5 b.v.b after |b| closes" "$RBH"'fn g<T>(b: Box<T>): i64 { var f = |b| { return b + 1; }; return b.v.b + fncall1(f, 1); }
fn main(): i64 { var b: Box<Q>; b.v.a = 1; b.v.b = 9; return g(b); }
syscall(60, main());
' 11 'syscall(60, 11);'
RBK6="$RBH"'fn g<T>(x: T): i64 { var q, x = pr(x.b); return q + x; }
'
accept "RBK6 var q, x = pr(x.b);: the RHS's x" "$RBK6$RBQM" 9 'syscall(60, 9);'
refuse "RBK6n ... g(5): the stub's" "$TGM" "$RBK6"'fn main(): i64 { return g(5); }
syscall(60, main());
' one
accept "RBK7 for x in x.a..5: the start's x" "$RBH"'fn g<T>(x: T): i64 { var s = 0; for x in x.a..5 { s = s + 1; } return s; }
'"$RBQM" 2 'syscall(60, 2);'

# RBN (6.7.17, the user's D1, the integrator's ruling at the genr finish pass): NEVER CALLED, IN A SKIPPED BASE TOO.
# A generic whose i64 base is not parsed — bounded with no `impl` of its bound for i64, or a stub (`var k = x.y;`
# elsewhere) — was judged only in its instances, so its rebound `x.show()` / `x.y` (a closure's `|x|`, a `for x in`,
# a destructure's later name) compiled when never called; D1 refuses them at the definition, called or not, as the
# same body with `impl Show for i64` (a parsed base) does. RBN rows: never called x {closure, for-in, destructure} x
# {method, field} x {an i64 impl, none, a stub base}: each exactly the parsed base's line (`_rbs_begin` / `_rbs_tok`,
# parse_fn_def.cyr). RBNC: called at Pt with no i64 impl, still exactly one line (the instance's report at the same
# token is the same report). RBNK: g's own x past the rebindings, a destructure's right-hand side and a range's start
# in a skipped base still compile and run. RBNX: RBN on aarch64 / cx / PE.
# (each a scratch copy of the tree with the one change, its 2-stage cycc, this gate run from it; MRBN1 the compiler
# alone, run from the real tree with CYCC=, so its aarch64 / cx legs cross-build the fixed src)
#   MRBN1 the compiler before the fix (l6717-integ 761023ca2) -> RED 15: the 12 none / stub rows and RBNS (compiled,
#                                                               rc 0), RBNX [pe] x2; the i64 rows, RBNC, RBNK green
#   MRBN2 `_rbs_tok` reporting nothing                        -> RED 19: the 12 none / stub rows, RBNS, RBNX x6
#   MRBN3 `_rbs_use` without its statement arm (no store)     -> RED 1: RBNS (the '.field' access words)
RBNB='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Pt { x; y; }
trait Show { fn show(self): i64; }
impl Show for Pt { fn show(self): i64 { return self.x * 10 + self.y; } }
impl Pt { fn other(self): i64 { return 77; } }
fn two(): (i64, i64) { return (1, 2); }
'
RBNI='impl Show for i64 { fn show(self): i64 { return self + 100; } }
'
RBNO='# no impl Show for i64
'
RBNM='fn main(): i64 { return 0; }
syscall(60, main());
'
rbn_g() {  # $1 form (cl fi ds)  $2 use  $3 "stub" for the stub base -> the generic's line
    if [ "${3:-}" = stub ]; then
        case $1 in
            cl) printf 'fn g<T>(x: T): i64 { var k = x.y; var f = |x| { return %s; }; return fncall1(f, 5) + k; }\n' "$2" ;;
            fi) printf 'fn g<T>(x: T): i64 { var k = x.y; var s = 0; for x in 0..2 { s = s + %s; } return s + k; }\n' "$2" ;;
            ds) printf 'fn g<T>(x: T): i64 { var k = x.y; var q, x = two(); return %s + q + k; }\n' "$2" ;;
        esac
    else
        case $1 in
            cl) printf 'fn g<T: Show>(x: T): i64 { var f = |x| { return %s; }; return fncall1(f, 5); }\n' "$2" ;;
            fi) printf 'fn g<T: Show>(x: T): i64 { var s = 0; for x in 0..2 { s = s + %s; } return s; }\n' "$2" ;;
            ds) printf 'fn g<T: Show>(x: T): i64 { var q, x = two(); return %s + q; }\n' "$2" ;;
        esac
    fi
}
rbn_rows() {  # $1 form  $2 / $3 the method / field line:col with a parsed or bound-bad base  $4 / $5 the stub's
    refuse_at "RBN i64 $1 x.show()" "$2: $SN 'x'$SM" "$RBNB$RBNI$(rbn_g $1 'x.show()')
$RBNM"
    refuse_at "RBN i64 $1 x.y" "$3: $SN 'x'$SA" "$RBNB$RBNI$(rbn_g $1 'x.y')
$RBNM"
    refuse_at "RBN none $1 x.show()" "$2: $SN 'x'$SM" "$RBNB$RBNO$(rbn_g $1 'x.show()')
$RBNM"
    refuse_at "RBN none $1 x.y" "$3: $SN 'x'$SA" "$RBNB$RBNO$(rbn_g $1 'x.y')
$RBNM"
    refuse_at "RBN stub $1 x.other()" "$4: $SN 'x'$SM" "$RBNB$RBNO$(rbn_g $1 'x.other()' stub)
$RBNM"
    refuse_at "RBN stub $1 x.y" "$5: $SN 'x'$SA" "$RBNB$RBNO$(rbn_g $1 'x.y' stub)
$RBNM"
}
rbn_rows cl 9:55 9:52 9:63 9:59
rbn_rows fi 9:69 9:66 9:77 9:73
rbn_rows ds 9:59 9:57 9:67 9:64
refuse_at "RBNS none: a statement |x| { x.y = 3; }" "9:46: $SN 'x'$SS" "$RBNB$RBNO"'fn g<T: Show>(x: T): i64 { var f = |x| { x.y = 3; return 0; }; return fncall1(f, 5); }
'"$RBNM"
RBNP='fn main(): i64 { var p = Pt { 2, 4 }; return g(p); }
syscall(60, main());
'
refuse_at "RBNC none, called at Pt: one line" "9:55: $SN 'x'$SM" "$RBNB$RBNO$(rbn_g cl 'x.show()')
$RBNP"
accept "RBNK1 none: g's own x past |x| and for x in" "$RBNB$RBNO"'fn g<T: Show>(x: T): i64 { var f = |x| { return x + 1; }; var s = 0; for x in 0..2 { s = s + x; } return x.show() + fncall1(f, 1) + s; }
'"$RBNP" 27 'syscall(60, 27);'
accept "RBNK2 stub: var q, x = pr2(x.y); the RHS's x" "$RBNB$RBNO"'fn pr2(v): (i64, i64) { return (v, 1); }
fn g<T>(x: T): i64 { var q, x = pr2(x.y); return q + x; }
'"$RBNP" 5 'syscall(60, 5);'
accept "RBNK3 none: for x in x.y..9, the start's x" "$RBNB$RBNO"'fn g<T: Show>(x: T): i64 { var s = 0; for x in x.y..9 { s = s + 1; } return s; }
'"$RBNP" 5 'syscall(60, 5);'
accept "RBNK4 none, never called: g's own x past the rebindings" "$RBNB$RBNO"'fn g<T: Show>(x: T): i64 { var f = |x| { return x + 1; }; var q, z = two(); return x.show() + fncall1(f, 1) + q + z; }
'"$RBNM" 0 'syscall(60, 0);'

# WR (6.7.17, met reviewing the genr lane): a whole argument's wrap carries what it wraps in the stub scan too, as the
# parser binds it (the guide: parentheses around the WHOLE argument carry what they wrap). `vb((x))`, `gxw((b))`,
# `var r = idp((&x)); r.b` and `var r = first((b)); r.a` forwarded / typed nothing (`_gs_arg_named`, `_gs_carries`,
# `_gs_cb_pp`, `_gs_cb_carr` read the argument's first token), so the generic kept its i64 base and was refused at the
# definition, called or not — naming the callee ("generic 'vb' has no i64 ... instance") or "no struct type in scope for
# 'r'" — where the unwrapped spelling made it a stub. Now the struct call runs (WRa-WRd; generic_struct_only_lines.tcyr
# V29-V33 on every backend) and the scalar call is refused with the stub's words (WR1-WR4, WR1n the forward's note).
#   MWR1 the tree before the fix (l6717-integ 45c7ff467)    -> RED 9: WR1-WR4 (the callee's words / "no struct type"),
#                                                             WR1n (the callee's note), WRa-WRd (refused at the definition)
echo "=== a wrapped whole argument forwards / types T in the stub scan, as the parser binds it (6.7.17) ==="
WRH='include "lib/syscalls.cyr"
struct Q { a; b; }
struct Box<T> { v: T; n; }
fn vb<T>(x: T): i64 { return x.b; }
fn gxw<T>(b: Box<T>): i64 { return b.v.b + b.n; }
fn idp<T>(p: *T): T { var r: T = *p; return r; }
fn first<T>(b: Box<T>): T { var r: T = b.v; return r; }
'
WR1G='fn g<T>(x: T): i64 { return vb((x)); }
'
WR2G='fn g<T>(b: Box<T>): i64 { return gxw((b)); }
'
WR3G='fn g<T>(x: T): i64 { var r = idp((&x)); return r.b; }
'
WR4G='fn g<T>(b: Box<T>): i64 { var r = first((b)); return r.a; }
'
WRS='fn main(): i64 { return g(5); }
syscall(60, main());
'
WRB='fn main(): i64 { var bx: Box<i64>; bx.v = 1; bx.n = 2; return g(bx); }
syscall(60, main());
'
WRQ='fn main(): i64 { var q = Q { 3, 4 }; return g(q); }
syscall(60, main());
'
WRQB='fn main(): i64 { var bx: Box<Q>; bx.v.a = 3; bx.v.b = 4; bx.n = 6; return g(bx); }
syscall(60, main());
'
refuse "WR1 vb((x)) at g(5): the stub's" "$TGM" "$WRH$WR1G$WRS" one
tv_note "WR1n the forward's note" "8:29: 'g' forwards its type parameter to 'vb'"
refuse "WR2 gxw((b)) at Box<i64>" "$TGM" "$WRH$WR2G$WRB" one
refuse "WR3 var r = idp((&x)); r.b at g(5)" "$TGM" "$WRH$WR3G$WRS" one
refuse "WR4 var r = first((b)); r.a at Box<i64>" "$TGM" "$WRH$WR4G$WRB" one
accept "WRa vb((x)) at Q" "$WRH$WR1G$WRQ" 4 'syscall(60, 4);'
accept "WRb gxw((b)) at Box<Q>" "$WRH$WR2G$WRQB" 10 'syscall(60, 10);'
accept "WRc var r = idp((&x)); r.b at Q" "$WRH$WR3G$WRQ" 4 'syscall(60, 4);'
accept "WRd var r = first((b)); r.a at Box<Q>" "$WRH$WR4G$WRQB" 3 'syscall(60, 3);'

# CF (6.7.17, the genr review, beside the user's D2): inside a generic a struct carrier's T field `b.v` (`b: Box<T>`,
# `v: T`), whole in an argument, is a value of T as a T-typed name is (`_gs_cfv`, parse_fn_def.cyr). Since D2 the
# instance binds it (`rdb(b.v)` at `Box<Q>` calls `rdb$Q`), but the stub scan read only a name: `rdb(b.v)` and
# `var r = idt(b.v); r.b` kept the i64 base, refused at the definition naming rdb / "no struct type in scope for 'r'",
# called or not, where `var y: T = b.v; rdb(y)` was a stub. Now the struct call runs (CFa, CFb; the tcyr's F17 rows on
# every backend), the scalar call is refused with the stub's words (CF1, CF1n, CF2), and a bounded `r.show()` on such
# an `r` is a bounded site at every T (CF3, `impl Show for i64`).
#   MCF1 the tree before the fix (97918d988)                  -> RED 6: CF1 CF2 (rdb's words / "no struct type"), CF1n,
#                                                               CFa CFb CF3 (refused at the definition)
echo "=== a carrier's T field, whole in an argument, is a value of T in the stub scan (6.7.17, beside D2) ==="
CFH='include "lib/syscalls.cyr"
struct Q { a; b; }
struct Box<T> { v: T; n; }
fn rdb<T>(x: T): i64 { return x.b; }
fn idt<T>(x: T): T { return x; }
'
CF1G='fn g<T>(b: Box<T>): i64 { return rdb(b.v); }
'
CF2G='fn g<T>(b: Box<T>): i64 { var r = idt(b.v); return r.b; }
'
CFS='fn main(): i64 { var bi: Box<i64>; bi.v = 4; bi.n = 0; return g(bi); }
syscall(60, main());
'
CFQ='fn main(): i64 { var bq: Box<Q>; bq.v.a = 3; bq.v.b = 4; bq.n = 0; return g(bq); }
syscall(60, main());
'
refuse "CF1 rdb(b.v) at Box<i64>: the stub's" "$TGM" "$CFH$CF1G$CFS" one
tv_note "CF1n the forward's note" "6:34: 'g' forwards its type parameter to 'rdb'"
refuse "CF2 var r = idt(b.v); r.b at Box<i64>" "$TGM" "$CFH$CF2G$CFS" one
accept "CFa rdb(b.v) at Box<Q>" "$CFH$CF1G$CFQ" 4 'syscall(60, 4);'
accept "CFb var r = idt(b.v); r.b at Box<Q>" "$CFH$CF2G$CFQ" 4 'syscall(60, 4);'
accept "CF3 bounded r.show() on idt(b.v) at Box<i64>" "$CFH"'trait Show { fn show(self): i64; }
impl Show for i64 { fn show(self): i64 { return self + 100; } }
fn g<T: Show>(b: Box<T>): i64 { var r = idt(b.v); return r.show(); }
'"$CFS" 104 'syscall(60, 104);'

cross_rows() {  # $1 the leg's name
    refuse_at "CPX [$1] CP0" "4:42: $NSF" "$CPA"
    refuse_at "CPX [$1] CP1" "5:36: $UM" "$CPB"
    refuse_at "CPX [$1] UC0" "3:54: $SN 'x'$SA" "$UCA"
    refuse_at "CPX [$1] UC1" "3:47: $SN 'x'$SS|3:62: $SN 'x'$SM" "$UCB"
    refuse_at "CPX [$1] UC2" "3:25: unknown type 'Foo' for variable 'x'" "$UCC"
    uc_rows "CPX [$1] "
    refuse "TGX [$1] TG0" "$TGM" "$TG0" one
    refuse "TVX [$1] TV1" "$TGM" "$TV1" one
    refuse "TVX [$1] TV2" "$TGM" "$TV2" one
    refuse "TVX [$1] TV10" "$TGM" "$TV10" one
    refuse "TVX [$1] TV10b" "$TGM" "$TV10b" one
    refuse_at "RBX [$1] RB0" "7:55: $SN 'x'$SM" "$RB0"
    refuse_at "RBX [$1] RB1" "7:69: $SN 'x'$SM" "$RB1"
    refuse_at "RBX [$1] RB2" "8:59: $SN 'x'$SM" "$RB2"
    refuse_at "RBX [$1] RB4" "4:46: $SN 'x'$SA" "$RB4"
    refuse_at "RBNX [$1] none cl x.show()" "9:55: $SN 'x'$SM" "$RBNB$RBNO$(rbn_g cl 'x.show()')
$RBNM"
    refuse_at "RBNX [$1] stub fi x.y" "9:73: $SN 'x'$SA" "$RBNB$RBNO$(rbn_g fi 'x.y' stub)
$RBNM"
    refuse "TGX [$1] TG13" "generic 'gc' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gc(5); }'"$TE" one
    refuse "TGX [$1] TG17" "generic 'gco' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gco(5); }'"$TE" one
    refuse_at "DPX [$1] DP0" "6:44: $(printf '%s' "$DM" | tr -d '\\')" "$DP0S"
    refuse "DPX [$1] TA6" "generic 'gd' has no i64 (or other scalar) instance" "$TH"'fn main(): i64 { return gd(5); }'"$TE" one
    refuse "DPX [$1] DP9" "cannot assign '\*\*pp: i64' from 'mkp'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; var pp: **i64 = &p; **pp = mkp(); return x; }'"$TE" one
    refuse "DPX [$1] DP13" "cannot assign '\*p: i64' from 'Q\.dup'" "$DQ"'fn main(): i64 { var q: Q; var x = 5; var p: *i64 = &x; *p = q.dup(); return x; }'"$TE" one
    refuse "DSX [$1] DS1" "cannot assign 'p\[0\]: i64' from 'mkp'" "$DQ"'fn main(): i64 { var x = 5; var p: *i64 = &x; p[0] = mkp(); return x; }'"$TE" one
    refuse "DSX [$1] DS3" "cannot assign 'gpi()\[0\]: i64' from 'mkp'" "$DQ"'fn main(): i64 { gpi()[0] = mkp(); return GX; }'"$TE" one
    refuse "DSX [$1] TA15" "generic 'gds' has no i64 (or other scalar) instance" "$TH"'fn gds<T>(x: T): i64 { var p: *T = &x; p[0] = mkp(); return 9; }
fn main(): i64 { return gds(5); }'"$TE" one
    refuse_at "UPX [$1] UP0" "3:46: $(printf '%s' "$UPM" | tr -d '\\')" "$UP0S"
    refuse "UPX [$1] UP5" "cannot assign '\*p' from 'Q\.dup'" "$DQ"'fn main(): i64 { var q: Q; var x = 5; var p = &x; *p = q.dup(); return x; }'"$TE" one
    refuse "COX [$1] CO5" "cannot assign '\*p' from 'mkp'" "$CQ"'fn g(): i64 { var x = 10; var p = &x; *p += mkp(); return x; }'"$FTE" one
    refuse "COX [$1] CO7" "cannot assign 'w\.n: i64' from 'mkp'" "$CQ"'fn g(): i64 { var w = W { 1, 0 }; w.n += mkp(); return w.n; }'"$FTE" one
    refuse "COX [$1] CO21" "$CGM" "$CQ"'fn gc<T>(p: *T): i64 { *p += mkp(); return 7; }
fn g(): i64 { var z = 1; return gc(&z); }'"$FTE" one
    refuse "FEX [$1] FE1" "cannot assign 'pw\.n: i64' from 'mkp'" "$FQ"'fn g(): i64 { var w = W { 1, 0 }; var pw: *W = &w; pw.n = mkp(); return w.n; }'"$FTE" one
    refuse "FEX [$1] FE15b" "cannot assign 'b\[1\]: u8' from 'mkp'" "$FQ"'fn g(): i64 { var b: u8[4]; b[1] = mkp(); return b[1]; }'"$FTE" one
    refuse "FEX [$1] FE17" "cannot assign 'n: i64' from 'mkp'" "$FQ"'fn g(): i64 { var w = W { mkp(), 0 }; return w.n; }'"$FTE" one
    refuse "FEX [$1] FE18" "generic 'gf' has no i64 (or other scalar) instance" "$FQ"'fn gf<T>(x: T): i64 { var b: Box<T>; b.v = mkp(); return 7; }
fn g(): i64 { return gf(5); }'"$FTE" one
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
# FLOOR (the wave-4 integration, 2026-10-21: 6.7.16's D102 review 367 (f16b) and the generic-callee / D99 rows 401 (s16:
# + DS, TA15, DSX), each over the genbind review's 300 — 300 + 67 + 101; 345 at D102, 327 at D96; 6.7.17's D13 + 25, D16 + 48, D15 + 29 (+ 11 at its review); D1 (genr) + 44; the genr review's WR + 8, CF + 5; the genr finish's RBN + 30): a lost row block —
# a source variable emptied, a leg's loop dropped — is RED, not a shorter green.
if [ $((nrefuse + naccept)) -lt 668 ]; then
    echo "FAIL: struct_result_type_refused ran $((nrefuse + naccept)) rows, under its floor of 668"; exit 1
fi
[ "$fail" -eq 0 ] || exit 1
exit 0
