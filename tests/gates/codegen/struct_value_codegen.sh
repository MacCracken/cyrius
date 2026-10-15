#!/bin/sh
# tests/gates/codegen/struct_value_codegen.sh — 6.7.6 (Break 1, lane E)
#
# STRUCT VALUES AND STRUCT FIELDS AS OPERANDS — crashes and silent wrong values on valid code. The
# runtime half is tests/tcyr/crossos/struct_value_codegen.tcyr, which this gate builds and runs on
# x86_64 (default pipeline, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and (6.7.11)
# PE (wine), compilers built from this tree (rows A); the release gate runs it on the four real hosts.
#
#   F  x86: `if (h.m)` / `while (h.m)` on an i8 / i16 / i32 field branched on the flags of the
#      statement before it (EFIELD_LOAD_W's narrow load never cleared `_flags_reflect_rax`).
#      F2+ (6.7.6 follow-up, FE): the same skip after a narrow typed LOCAL (EFLLOAD_W's narrow arms),
#      mulh64 (EMULH) and — found by the audit — `~`, `&x`, `&g`, `&f`, a string literal, f64_floor
#      and every PE syscall reroute (tcyr F15-F21). EFLLOAD_W and EMULH clear the tracker, and
#      ECONDCMP skips its `test` only when the setter was the LAST emit (`_flags_cp`)
#   I  a name intrinsic's result (`mulh64`, `fncallN`, `callptr`) kept its LAST argument's struct
#      type, so `fncall1(&f, n) + 1` with `n: Num` dispatched `Num_add` (100 where 8 is right).
#      I3 (FE): ... but an `&f` callee returning `: f64` with an f64 last argument keeps the f64 type
#      that leak gave it (`_icall_result`): `fncall1(&dbl, d) + 1.0` is an f64 add, as in 6.7.5
#   P  a PARENTHESISED argument to an address-passed parameter (`rd3((a))`, `rd1((s))`,
#      `rd1((mk1(4)))`) pushed its value: SIGSEGV. Parentheses wrapping the whole argument are
#      transparent (`_sarg_paren`); its refusals (another struct, no frame at top level) are the
#      unparenthesised argument's, reported once
#   Q  a PARENTHESISED struct source into a struct-typed field (`o.i = (z.k)`: 72 where 78 is
#      right; a for step too), a struct variable (`w = (j)`: one word) or a declaration
#      (`var q: K = (z.k)`: SIGSEGV), in a fn and at top level: transparent at every destination
#      (`_fsc_paren`, `_asg_paren`, `_scv_peel` + `_sc_pwrap` + `_fnc_agg`, `_sci_pname`,
#      `_gci_src`); a source of another struct is refused once, by name, as unwrapped
#   Q10 / O7 (6.7.6 follow-up, FE): a closure body declaring a `var` inside the wrap / the operand ran
#      PARSE_VAR's arm inside the outer one, which zeroed `_scv_pk` / `_scv_term` and cleared
#      `_sc_fcw`: Q10 refused ("expected ';', got ')'"), O7 SIGSEGV. `_scv_arm` saves them and
#      `_scv_disarm` restores them (`_scv_vec`); tcyr Q28-Q30 and O12-O14
#   O  a struct result over 8 B as the RIGHT operand of an address-passed operator parameter
#      (`s - mk3(4)`, `p + p.dup()`, by-value or `*S`, bare or wrapped) pushed its first word:
#      SIGSEGV. The operand asks for the result's temp (`_op_big_arm` / `_op_big_take`); at top
#      level, where there is no frame, it is refused by name
#   S  a `: Str` field as a source (`bq(h.name)` with `fn bq(b: Q)`, `var q: Q = h.name;`) compiled
#      and read Q's fields out of the Str's header and past it. It is a Str handle (`_fls_note`):
#      into a struct of another type — an argument at either width, a declaration in a fn or at
#      top level, an assignment, a field, an operator operand, wrapped or not — refused by name;
#      into a Str, an untyped slot or a handle (6.6.16's rebind) unchanged
#   L  (6.7.6 follow-up, lane E2) a struct-returning call, method or operator result as the LEFT
#      operand never dispatched: only a name typed the left operand, so `p.dup() + p` integer-added
#      first words (2 where 6), `a + b + a` with a struct-returning `+` SIGSEGV'd and `mk3(4) - s +
#      10` dispatched an undefined `P3_add` from `s`'s leftover type. The result is stamped where it
#      ends (`_lsc_note`; a free call in `_call_scale_fix` via `_lsc_free`) and a left operand that is
#      it — wrapped or not, nothing emitted since — dispatches from its own struct (`_op_lst`) and
#      passes its value or its temp's address (`_op_lhs_call_sv`); a missing operator fn, a
#      parameter of another struct and a top-level operand that needs a frame are refused by name.
#      As an argument (`lvsz(mklv(1) + a)`) it takes the operator path's temp. A `Str` stays a handle.
#      As a declaration's initialiser or a struct fn's return value the receive took the call ALONE
#      (`var r = mk3(4) - s;`, `return mk(1) + a;`: expected ';', got '-'): it now takes only a call
#      that ends the statement (`_call_ends_at`), and `_ret_expr_head` sends `f(..) OP` to the
#      operator receive (rows L12-L15)
#   K  (6.7.11, issues/archived/2026-10-08-struct-operator-results.md #2) an INTEGER operator's result kept its right
#      operand's struct type and slot, so the next `+ - * /` dispatched on it: `n - s + 10` called `P3_add(&s,
#      10)` and discarded `n - s` (the filed repro: SIGSEGV), for every integer arm (`+ - * / % << >> >>>`,
#      `& | ^`, a comparison, `&&` / `||`, `+| +? -| -? *| *?`, `~`). Each clears a struct expression type
#      (`_int_st`, `_int_res`). K1 the filed repro, verbatim (8); K2 / K3 the same with no `P3_add` compile
#      (refused 'undefined function' through 6.7.10); the values file's K rows (every arm, 24 B and 8 B, the
#      dispatching twins, an f64 right operand's type kept) run on A1-A7 — A7 (new) is the values file on PE
#      (wine)
#   U  (6.7.11, issues/archived/2026-10-08-struct-operator-results.md #3; the user's decision (a), 2026-10-13) `-s` on a
#      struct is integer negation of its word with no struct type (`_neg_int` -> `_int_res`; the declaration
#      zone's typer `_gz_unary` agrees): `-s + t` dispatched `S_add` — over 8 B from s's slot, the minus
#      dropped (the filed repro: 6), at 8 B on the negated word (13) — where `-w.s + t` added (252). U1 the
#      repro, verbatim (252); U2 / U3 `var X: S8 = -G + H;` in the zone and after it (252); the values file's
#      U rows (every size against the field form, the right operand, `-(s + t)`, f64, u128) on A1-A7
#      L16 / L17 (6.7.11): a leading call's struct types an untyped declaration only when the call ENDS it
#      (`_var_rhs_csid`): `var r = mk3(4) - s; r.x` (the filed repro, verbatim) and `var r = mk2(1) == p; return
#      r;` in a fn returning Pt took the call's struct (SIGSEGV each); refused by name now
#   R  (lane E2) parentheses around a struct fn's WHOLE return value: `return (j);`, `return
#      (mk3(v));`, `return (a + b);` were refused ("return must be a bare local identifier ..." for
#      the retptr class, "... got `(...)`" for rax:rdx); `_ret_peel` steps inside them for both
#      classes (`_ret_struct_big` / `_ret_struct_pair`, out of PARSE_RETURN), `_ret_end` closes them,
#      a passed-through pair call keeps its wrap (`_ret_unpeel`); `return (a) + b;` is an operator
#      receive (`_ret_expr_head`). The top-level operand refusal says "(a struct over 8 bytes)" for
#      a by-value or untyped operator parameter, "(a `*` parameter)" only for a `*S` one
#   MP (6.7.11, issues/archived/2026-10-10-field-of-method-pointer-result-refused.md; the user's decision (a), 2026-10-13)
#      a METHOD's `*T` result takes `.field`, `.m(..)` and a deeper chain (`h.get().b`), in a fn and at top
#      level, as a free call's `*T` result has since 6.6.17; it was refused "it does not return a struct".
#      `_method_chain` parks the pointer (`_mchain_ptr`, `_ptr_park`); `h.get().b = 5` stays refused
#   PE (6.7.11, issues/archived/2026-10-10-paren-wrapped-struct-call-as-nested-literal-element-refused.md; the user's decision
#      (a), 2026-10-13) a free struct call in parentheses as a nested-struct literal element (`H { 7, (mkq(4,
#      9)), 8 }`) was a scalar for the nested struct's first leaf: "unexpected '}'" at 16 / 24 B and 8 B with two
#      leaves. It is the element the unwrapped call is (`_spi_pcall`), its refusals the unwrapped call's
#   N  (lane E2) lib/fnptr.cyr's x86_64 SysV fncall8 (Linux, macOS, agnos arms) stored argument 7 at
#      [rsp] — the C order — while a cyrius callee reads its LAST argument there: an address-taken
#      `&fncall8` swapped 7 and 8 (12345687). Every target is tests/tcyr/crossos/fncall_stack_args.tcyr
#      (the release gate's hosts) and cx_backend_parity.tcyr's &fncall8 row, cx-only until now
#   FP (6.7.11, the call-arguments lane) a struct result through `fncallN(&f, ..)` / `callptr(&f, ..)`
#      had no struct-result ABI: over 16 B no hidden result pointer (the callee wrote through its first
#      argument: SIGSEGV x86 / aarch64, a guest error on cx, a write fault at 0x5 on PE), 9-16 B no pair
#      receive, and 8 B — right through 6.7.9 — a handle since 6.7.10's handle line (the result was an
#      untyped word). A known callee now takes the struct-call hooks (`_icall_sret` / `_sc_x8` /
#      `_icall_result`'s `_sc_post`), so the declaration, assignment, argument, field store and `return`
#      see a struct value; a callee in a variable stays a word, its struct-typed receive a handle (the
#      user's decision, 2026-10-13: FP6). The runtime half is tests/tcyr/crossos/fncall_struct_result.tcyr,
#      run as B1-B7 on x86_64 / IR=1 / IR=3 / DCE / aarch64 (qemu) / cx (cxvm) / PE (wine, a private
#      prefix), each requiring "N passed, 0 failed (N total)" with N derived from the file (one row per
#      `assert_eq(`, floor 48). PE has code of its own (`_icall_sret` runs after its callee push, and the
#      result pointer is counted into ECALLPTR_PE's argc), so FPw1 / FPw2 run FP1 / FP2 there too
#   EV (6.7.11, the call-arguments lane) under CYRIUS_IR=3, LASE kept a just-stored local's rax image
#      across EFLADDR's `lea rax, [rbp+d]`, which recorded no IR node, and dropped the reload after it:
#      `o.with2(x)` / `bs(h, x)` / `var b: B = mk(x)` right after `var x = 5;` passed the aggregate's
#      ADDRESS as x (an ASLR-dependent exit). EFLADDR records IR_RAW_EMIT, as ELOAD_LOCAL_ADDR does. EV1-EV4
#      are the filed repros verbatim, built under CYRIUS_IR=3; tcyr E1-E5 run them on every leg (A3 is the
#      one that was wrong)
#
# MUTATION LEDGER (scratch copies of the tree, each rebuilt with the one change and the gate run
# from that copy as CYCC=<mutant>; 2026-10-08):
#   M-F x86 EFIELD_LOAD_W without `_flags_reflect_rax = 0`  -> RED F1 (exit 1) and A1-A4 (tcyr F1-F4
#       F6 F8); A5 A6 green (aarch64 / cx never set the tracker)
#   M-I1 `_lower_mulh64` without `_icall_untyped`            -> RED I2 (100) and A1-A6 (tcyr I1 I7)
#   M-I2 `_PINDIRECT_CALL_IN` without `_icall_untyped`       -> RED I1 (100) and A1-A6 (tcyr I2-I7)
#   M-P1 `_try_push_struct_addr_arg` without the `_sarg_paren` arm -> RED P1 P2 (139), P3 P5 (BUILT)
#       and A1-A6 (native SIGSEGV; cx tcyr P1 P2 read the value as an address)
#   M-P2 `_pwrap_k` without its consecutive-close test       -> RED A1-A6 (tcyr P16: `((a) + (b))`
#       read as two wraps; native SIGSEGV)
#   M-P3 `_pwrap_k` reading the token after the INNERMOST `)` (E-3 as first committed) -> RED P6
#       and A1-A6 (the values file does not build: "expected ')'" at tcyr P17's `+`)
#   M-Q1 `_fsc_src` without the `_fsc_paren` arm             -> RED Q1, Q6 (BUILT), A1-A6 (tcyr Q1-Q7)
#   M-Q2 `_try_aggregate_copy_assign` without its wrap arm   -> RED Q2, Q5 (BUILT), A1-A6 (tcyr Q9 Q10
#       Q14 Q27)
#   M-Q3 `_try_struct_call_assign` without its wrap arm      -> RED Q7 (BUILT), A1-A6 (tcyr Q11; Q24
#       off cx)
#   M-Q4 `_pcmpe_struct_assign` without its wrap arm         -> RED A1-A5 (the values file does not
#       build: a 9-16 B method result in a wrap reached `_sc_whole` as "no frame" -4, and was
#       refused as at top level), A6 (tcyr Q8)
#   M-Q5 `_sc_whole` without `_sc_pwrap`                     -> RED Q8 (BUILT), A1-A6 (tcyr Q19 Q20;
#       native SIGSEGV after)
#   M-Q6 `_scv_arm` without `_scv_peel`                      -> RED Q2 (139), Q8 Q9 (BUILT), A1-A6
#       (tcyr Q17; native SIGSEGV after)
#   M-Q7 `_fnc_agg` never taking `_sc_fcw`                   -> RED Q8 (BUILT), A1-A5 (native SIGSEGV
#       at tcyr Q18); A6 green (cx binds the temp's address, measured)
#   M-Q8 `_fla_take` without `_fla_inparen`                  -> RED Q2 (139), Q9 (BUILT), A1-A6 (tcyr Q17)
#   M-Q9 `_try_struct_copy_init` refusing a wrapped name     -> RED Q4 (BUILT), A1-A6 (tcyr Q16 Q21)
#   M-Q10 `_gci_src` without the wrap                         -> RED Q3 (139), A1-A6 (tcyr Q27)
#   M-O1 `_op_rhs` without `_op_big_arm`                     -> RED O1-O3 (139), O4 O5 (BUILT), A1-A6
#       (native SIGSEGV; cx tcyr O1-O3 read the first word as an address)
#   M-O2 `_op_big_arm` not setting `_sc_fcw` (free calls)    -> RED O1 O3 (139), A1-A6 (tcyr O1 O2)
#   M-O3 `_op_big_arm` not setting `_sc_want` (9-16 B methods) -> RED O2 O3 (139), A1-A5 (native
#       SIGSEGV at tcyr O8); A6 green (cx has no 16-byte pair return)
#   M-O4 `_op_big_take` without the top-level pair-call refusal -> RED O5 (BUILT)
#   M-S1 `_fls_note` recording nothing                       -> RED S1-S8 (each BUILT)
#   M-S2 `_fls_asg_check` without the handle exemption        -> RED S9 (the rebind refused)
#   M-S3 `_push_struct_expr_arg` without its `_fls` check     -> RED S1 S8 (BUILT)
#   M-S4 `_sc_var_receive` without its `_fls` check           -> RED S2 (BUILT)
#   M-S5 `_fsc_expr` without its `_fls` check                 -> RED S4 (BUILT)
#   M-S6 `_op_arg_check` without its `_fls` arm               -> RED S5 (BUILT)
#   M-S7 `_sarg_byval_small` without its `_fls` arm           -> RED S6 (BUILT)
#   M-S8 `_sc_global_mismatch` without its `_fls` check       -> RED S7 (BUILT)
#   M-S9 `_pcmpe_struct_assign` without `_fls_asg_check`      -> RED S3 (BUILT)
#   (lane E2, 2026-10-08, the same procedure)
#   M-L1 `_op_lst` never matching the stamp                  -> RED L1-L4 (2 / undefined P3_add / 251 /
#       139), L5-L9 (BUILT), A1-A6 (native SIGSEGV; cx tcyr L1 L6 L7)
#   M-L2 `_sc_post` without `_lsc_note` (method / operator)  -> RED L1 L4 L6, A1-A6 (tcyr L6 L7; L9 L20 a64)
#   M-L3 `_sc_post_small` without `_lsc_note` (<= 8 B)        -> RED A1-A6 (tcyr L11 L13)
#   M-L4 `_call_scale_fix` without `_lsc_free` (free calls)  -> RED L2 L3, L5 L7-L9 (BUILT), A1-A6
#   M-L5 `_lsc_span` without the wrap (`_lsc_beg != beg`)    -> RED A1-A6 (tcyr L9 L22; native SIGSEGV)
#   M-L6 `_op_lhs_call_sv` without the rax:rdx store          -> RED L1 L3 (139), A1-A5 (cx: no pairs)
#   M-L7 `_op_lhs_call_sv` without the top-level refusal      -> RED L6 L7 (BUILT)
#   M-L8 `_try_push_struct_addr_arg` value-pushing a call that is only the left operand -> RED A1-A6
#       (tcyr L8: native SIGSEGV)
#   M-L9 `_fnc_agg` not recording its temp (`_fnc_lo`)        -> RED L2, L9 (BUILT), A1-A6 (tcyr L1)
#   M-L10 `_lsc_note` stamping a `Str`                        -> RED L11 (an undefined Str_add)
#   M-L11 `_op_lhs_sv` ignoring `_lsc_hit`                    -> RED L1-L4, L6-L8 (BUILT), A1-A6
#   M-D1 PARSE_VAR's receive without `_call_ends_at`          -> RED L12 (expected ';'), A1-A6 (no build)
#   M-D2 `_return_struct_call` without `_call_ends_at`        -> RED L14 (expected ';'), A1-A6 (no build)
#   M-D3 `_ret_expr_head` without its call-head arm           -> RED A1-A6 (tcyr L33 refused); L13
#       green — a rax:rdx `+` result passes through the call-return path
#   M-D4 `_refuse_toplevel_pair_init` without `_call_ends_at` -> RED L15 (2 error lines)
#   M-D5 (6.7.9) `_sc_global_pair` without its `_scv_err` test -> RED L15 (2 error lines: the zone now refuses
#       a whole 9-16 B operator result, once — struct_result_type_refused.sh rows Z)
#   M-R1 `_ret_peel` never peeling                           -> RED R1-R5, A1-A6 (no build)
#   M-R2 `_ret_end` without `_pw_close`                       -> RED R1-R3 (expected ';'), A1-A6 (no build)
#   M-R3 `_ret_struct_pair` without `_ret_unpeel`             -> RED R4 (2 error lines), A1-A5 (no build;
#       cx has no pairs)
#   M-R4 `_return_struct_call` ending at `;` inside a wrap    -> RED R2, A1-A6 (no build)
#   M-R5 `_ret_expr_head` without its `(` arm                 -> RED A1-A6 (tcyr R5 refused)
#   M-R6 `_op_star_param` never 1                             -> RED R7
#   M-R7 `_op_star_param` always 1 (the old wording)          -> RED R6
#   M-N1a lib/fnptr.cyr's Linux x86 fncall8 arm back to the C order -> RED N1 (87); the same mutant
#       turns cx_backend_parity.sh RED (M-N1b: T native 57 passed, 1 failed)
#   (FE, 2026-10-08, the same procedure)
#   M-F2 ECONDCMP without its `GCP(S) != _flags_cp` test         -> RED F5 F6, A1-A4 (tcyr F15-F20; F21
#       on PE under wine: 12 red with the pre-fix compiler); A5 A6 green (the tracker is x86's only)
#   M-F3 M-F2 + EFLLOAD_W without its clear                      -> RED F2 F3 F5 F6, A1-A4 (tcyr F9-F12)
#   M-F4 M-F2 + EMULH without its clear                          -> RED F4 F5 F6, A1-A4 (tcyr F14)
#   M-V1 `_scv_restore` resetting as before (pk 0, term 5, fcw / fla -1) -> RED Q10 (expected ';'),
#       O7 (139), A1-A6 (the values file does not build: tcyr Q28)
#   M-V2 `_scv_restore` not restoring `_sc_fcw`                  -> RED Q10 O7 (139), A1-A5 (SIGSEGV at
#       tcyr Q28), A6 (tcyr Q28 O12-O14 wrong values)
#   M-V3 `_scv_restore` not restoring `_scv_pk`                  -> RED Q10 (expected ';'), A1-A6 (no build)
#   M-I3 `_icall_result` never typing f64                         -> RED I3 (exit 2), A1-A6 (tcyr I8-I11 I14)
#   M-I4 `_icall_result` ignoring the last argument's type        -> RED A1-A6 (tcyr I13)
#   M-I5 `_icall_result` ignoring the callee (`cfi` / `: f64`)    -> RED A1-A6 (tcyr I12)
#   M-I6 `_lfa_load` not recording `_lfa_end` (no static callee)   -> RED I3, A1-A6 (tcyr I8-I11 I14)
#   (6.7.11, the call-arguments lane, the same procedure)
#   M-FP1 `_icall_sret` never reserving (-1)                     -> RED FP1 FP3 (139), FP4 FP5 (refused), FP8 FP9 (BUILT),
#       B1-B6 (the values file refused)
#   M-FP2 `_icall_result` without its `_sc_post` arm              -> RED FP2 FP3 (139), FP4 (98), FP5 FP7 (refused), FP9
#       (BUILT), B1-B6 (refused)
#   M-FP3 `_PINDIRECT_CALL_IN` without `_sc_x8`                   -> RED B5 only (aarch64: 139) — X8 is aarch64's alone
#   M-FP4 `_PINDIRECT_CALL_IN` not counting the result pointer    -> RED FP1 FP4 FP5 (139), B1-B4 (139), B6 (cx: 1); B5
#       green (aarch64 pushes no result pointer)
#   M-FP5 `_icall_ret` never 1 (`return fncall1(&f, ..)`)         -> RED FP5 (refused), B1-B6 (refused)
#   M-FP6 `_try_push_struct_addr_arg` without its `_icall_sid_at` arm -> RED FP4 (139), B1-B5 (139), B6 (cx: 1)
#   M-FP7 `_gz_unary` without its `_gz_icall` arm (the zone)      -> RED FP7, B1-B6 ("the declaration zone misread ..")
#   M-FP8 `_icall_sret` called BEFORE the `if (_TARGET_PE == 1)` callee push (PE-only: elsewhere that
#       block emits nothing) -> RED FPw1 (exit 5: the result pointer popped as the callee) and B7 (exit 5)
#       only; FPw2 green (8 B pushes no result pointer), every other row and leg green (2026-10-14)
#   M-FPF one `assert_eq(` row deleted from fncall_struct_result.tcyr -> RED "only 47 rows (floor 48)";
#       B1-B7 then read "47 passed" (each requires the derived N exactly)
#   M-EV1 x86 EFLADDR without its `_IR_REC0(S, IR_RAW_EMIT)` (= the A3 compiler) -> RED EV1-EV4 (exit 30 +
#       the low byte of the address / 1), A3 (tcyr E1-E5); A1 A2 A4-A6 and B1-B6 green (only IR=3 applies LASE)
#   (6.7.11, the struct lane, issues/archived/2026-10-08-struct-operator-results.md, the same procedure, 2026-10-14)
#   M-V1 `_var_rhs_csid` without its `_call_ends_at` test (= the tree before it) -> RED L16 L17 (BUILT); the
#       values files green (an untyped value and a mistyped one read alike: only `.f` / a pair return differ)
#   the tree before #2 (39f62ebb)                          -> RED K1 (139), K2 K3 (undefined P3_add), A1-A7
#       (K1-K23: 1, the dispatch)
#   M-K1 `_INT_F64_MIX` without `_int_st` (`+ - * /`)        -> RED K1 K2, A1-A7 (K1 K2 K20; `* /` are also
#       cleared by the term tail)
#   M-K2 PARSE_TERM's tail SPSC only (`% << >> >>>`)          -> RED A1-A7 (K5-K8)
#   M-K3 `_pexpr_bit_ps` SPSC only (`& | ^`)                  -> RED A1-A7 (K9-K11)
#   M-K4 `_PLOGIC_ATOM`'s compare tail SPSC only               -> RED K3, A1-A7 (K12 K13 K22)
#   M-K5 `_PLOGIC_AND` / PCMPE's `||` SPSC only                -> RED A1-A7 (K14 K15)
#   M-K6 EMIT_OVF_CALL without `_int_st` (`+| +? -| -?`)       -> RED A1-A7 (K17 K18)
#   M-K7 `_bnot_int` SPSC only (`~`)                           -> RED A1-A7 (K16 K23)
#   the tree before #3 (0d1c660c)                          -> RED U1 (6) U2 U3 (13), A1-A7 (U1-U8 U11 U12)
#   M-U1 `_neg_int` SPSC only (no `_int_res`)                  -> RED U1 (6), U2 (the zone's typer now disagrees:
#       "the declaration zone misread .."), U3 (13), A1-A7 (U1-U8 U11 U12)
#   M-U2 `_gz_unary` keeping `-g`'s struct (kind 4)            -> RED U2 ("the declaration zone misread ..")
#   M-R1 `_refuse_struct_tuple_return` answering 0             -> RED R8-R11 (BUILT); R12-R15 green
#   M-R3 `_refuse_struct_tuple_return` without its GIDEP guard  -> RED R27 R28 (refused: the inline replay judged by
#       the caller's class); R8-R15 green
#   M-R2 `_pair_ret_call_ok` without its `_call_ends_at` test   -> RED R16-R22 (BUILT); R23-R26 green
#   M-MP1 `_method_chain` without its `_mchain_ptr` arm (= the tree before) -> RED MP1 MP2 (refused 'it does not
#       return a struct'), MP3 (refused, but as 'it does not return a struct'), A1-A7 (the values file does not build:
#       tcyr MP1-MP16); MP4 MP5 green
#   M-PE1 `_spi_src` without its `_spi_pcall` arm (= the tree before) -> RED PE1 (unexpected '}'), PE2 (refused, but
#       as unexpected '}'), PE3 (2 error lines), PE4 (BUILT: 65), PE5 (unexpected '}'), PE6, A1-A7 (the values file
#       does not build: tcyr Q31-Q41)
#   (6.7.12, the fixfirst lane, issues/2026-10-13-pe-discarded-vector-call-result-no-hidden-pointer.md, the same
#   procedure, 2026-10-15)
#   M-VD1 `_pe_vret` answering 0 (no Win64 vector temp anywhere) -> RED 4: VDw1-VDw3 (exit 5), C7 (exit 5); C1-C6
#       green (SysV / AAPCS64 / cx return a vector in registers)
#   M-VD2 `_sc_pre` / `_sc_post` without the arm (methods, operators, `&f` calls) -> RED 3: VDw2 VDw3 (exit 5), C7
#       (exit 5); VDw1 green
#   M-VD3 `_fnc_agg` without the arm (by-name calls)              -> RED 2: VDw1 (exit 5), C7 (exit 5)
#   M-VDF one `assert_eq(` row deleted from vector_call_result_discarded.tcyr -> RED 1: "only 14 rows (floor 15)"
#
#   C  (6.7.12) tests/tcyr/crossos/vector_call_result_discarded.tcyr — a vector-returning call whose result goes
#      nowhere (the three filed repros, an argument, a method with `self` intact, an operator fn returning a
#      vector, at top level) — on x86_64 / IR=1 / IR=3 / DCE / aarch64 / cx / PE: "N passed, 0 failed (N total)".
#      On Win64 no hidden result pointer was passed, so the callee wrote through its first argument (exit 5;
#      `s.mv(..)` overwrote self). VDw1-VDw3: the filed repros verbatim on PE (exit 3)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=struct_value_codegen
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper (6.7.11: the PE legs B7 / FPw).
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
cd "$ROOT"
ulimit -c 0 2>/dev/null
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() {   # <name> <message fragment> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$rc" -eq 124 ]; then bad "$3: the compiler did not finish (timeout)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}
refused_file() {   # <name> <message fragment> <what> <file>: a filed repro, verbatim
    cp "$4" "$T/$1.cyr"
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}
exits_file() {   # <name> <want> <what> <file>: a filed repro, verbatim
    cp "$4" "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
exits() {   # <name> <want> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
exits_ir3() {   # <name> <want> <what> <source>: built under CYRIUS_IR=3
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; CYRIUS_IR=3 timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
# tcyr <what> <compiler> <runner> [ENV=V]: build the values file, run it, require "0 failed" — with TN
# set, exactly "TN passed, 0 failed (TN total)" (the B rows: a gutted or truncated file is RED).
TC=tests/tcyr/crossos/struct_value_codegen.tcyr
TN=""
_tc_ok() {
    if [ -n "$TN" ]; then tr -d '\r' < "$1" | grep -qx "$TN passed, 0 failed ($TN total)"
    else grep -q ' 0 failed' "$1"; fi
}
tcyr() {
    n=$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_')
    rc=0
    if [ -n "${4:-}" ]; then env "$4" "$2" < "$TC" > "$T/tc_$n" 2> "$T/tc_$n.err" || rc=$?
    else "$2" < "$TC" > "$T/tc_$n" 2> "$T/tc_$n.err" || rc=$?; fi
    if [ "$rc" -ne 0 ] || [ ! -s "$T/tc_$n" ]; then bad "$1: the values file did not build (rc $rc): $(grep '^error' "$T/tc_$n.err" | head -1)"; return; fi
    chmod +x "$T/tc_$n"
    got=0
    if [ -n "$3" ]; then timeout 120 $3 "$T/tc_$n" > "$T/tc_$n.out" 2>&1 || got=$?
    else timeout 60 "$T/tc_$n" > "$T/tc_$n.out" 2>&1 || got=$?; fi
    if [ "$got" -eq 0 ] && _tc_ok "$T/tc_$n.out"; then ok "$1: $(tr -d '\r' < "$T/tc_$n.out" | grep ' 0 failed')"
    elif [ -n "$TN" ]; then bad "$1: exit $got, want '$TN passed, 0 failed ($TN total)': $(tr -d '\r' < "$T/tc_$n.out" | grep -E 'FAIL|failed' | head -4 | tr '\n' '|')"
    else bad "$1: exit $got: $(grep -E 'FAIL|failed' "$T/tc_$n.out" | head -4 | tr '\n' '|')"; fi
}
# The PE legs (6.7.11): a cyrius PE run under wine in the private prefix; the exit code passes through.
_wine() {
    (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$1")
}
exits_pe() {   # <name> <want> <what> <source>: built with CYRIUS_TARGET_WIN=1, run under wine
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.exe" 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$T/$1.exe" ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    got=0; _wine "$T/$1.exe" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
E='\nsyscall(60, main());\n'

exits f01 0 "F1: if (h.m) on a zero i8 field after x = x + 1 (the filed repro: 1 on x86)" "struct H { n; m: i8; k: i32; }\nfn main(): i64 { var h = H { 1, 0, 3 }; var x = 5; x = x + 1; if (h.m) { return 1; } return 0; }$E"
exits f02 0 "F2: if (b) on a zero u8 LOCAL after x = x + 1 (the filed repro: 1 on x86)" "fn main(): i64 { var b: u8 = 0; var x = 5; x = x + 1; if (b) { return 1; } return 0; }$E"
exits f03 1 "F3: if (b) on a nonzero i8 local after y = y - 3 left ZF set (0 on x86)" "fn g(y): i64 { var b: i8 = 0 - 1; y = y - 3; if (b) { return 1; } return 0; }\nfn main(): i64 { return g(3); }$E"
exits f04 0 "F4: if (mulh64(x, y + 1)) with mulh64(5, 7) == 0 (the filed repro: 1)" "fn g(x, y): i64 { if (mulh64(x, y + 1)) { return 1; } return 0; }\nfn main(): i64 { return g(5, 6); }$E"
exits f05 0 "F5: if (~(a + b)) with a + b == -1 (1 on x86)" "fn g(a, b): i64 { if (~(a + b)) { return 1; } return 0; }\nfn main(): i64 { return g(0 - 2, 1); }$E"
exits f06 1 "F6: if (&z) after y = y - 3 (0 on x86)" "fn g(y): i64 { var z = 0; y = y - 3; if (&z) { return 1; } return 0; }\nfn main(): i64 { return g(3); }$E"
NUM='struct Num { a; b; }\nfn Num_add(x: Num, y) { return 100; }\nfn id1(x) { return 7; }\n'
exits i01 8 "I1: fncall1(&id1, n) + 1 (the filed repro: 100)" "include \"lib/fnptr.cyr\"\n${NUM}fn main() { var n: Num = Num { 1, 2 }; return fncall1(&id1, n) + 1; }$E"
exits i02 1 "I2: mulh64(3, n) + 1 (the filed repro: 100)" "${NUM}fn main() { var n: Num = Num { 1, 2 }; return mulh64(3, n) + 1; }$E"
exits i03 1 "I3: fncall1(&dbl, d) + 1.0, dbl: f64 and d: f64, is an f64 add (6.7.5: 7.0; E-2: integer add)" "include \"lib/fnptr.cyr\"\nfn dbl(x: f64): f64 { return x * 2.0; }\nfn main(): i64 { var d: f64 = 3.0; var r = fncall1(&dbl, d) + 1.0; var t: f64 = 7.0; if (r == t) { return 1; } return 2; }$E"
P3S='struct P3 { x; y; z; }\nfn rd3(p: *P3) { return p.z; }\nfn mk3(v): P3 { var t: P3 = P3 { v, v, v }; return t; }\n'
S1S='struct S1 { v; }\nfn rd1(p: *S1) { return p.v; }\nfn mk1(v): S1 { var t: S1; t.v = v; return t; }\n'
exits p01 3 "P1: rd3((a)) (the filed repro: SIGSEGV)" "${P3S}fn main() { var a: P3 = P3 { 1, 2, 3 }; return rd3((a)); }$E"
exits p02 45 "P2: rd1((s)) + rd1((mk1(4))) * 10 (the filed repros: SIGSEGV)" "${S1S}fn main() { var s: S1; s.v = 5; return rd1((s)) + rd1((mk1(4))) * 10; }$E"
refused p03 "cannot pass 'a' to a parameter of a different struct type in a call to 'rd3'" "P3: rd3((a)) with a: Q3" "${P3S}struct Q3 { x; y; z; }\nfn main() { var a: Q3 = Q3 { 1, 2, 3 }; return rd3((a)); }$E"
refused p04 "'mk3' returns a struct by value, and a struct result needs storage in a fn's frame" "P4: rd3((mk3(4))) at top level" "${P3S}var r = rd3((mk3(4)));\nsyscall(60, r);\n"
refused p05 "'mk1' returns a struct by value, and a struct result needs storage in a fn's frame" "P5: rd1((mk1(4))) at top level" "${S1S}var r = rd1((mk1(4)));\nsyscall(60, r);\n"
KQ='struct K { a; b; c; }\nstruct Q { a; b; c; }\nstruct O { n; i: K; }\nstruct Z { m; k: K; }\nfn mkq(v): Q { var t: Q = Q { v, v, v }; return t; }\n'
exits q01 0 "Q1: o.i = (z.k); o.i = (j); and a for step (the filed repro: 72 where 78)" "${KQ}fn main(): i64 { var z = Z { 1, 20, 25, 30 }; var j = K { 21, 26, 31 }; var o = O { 0, 0, 0, 0 }; o.i = (z.k); var r = o.i.a + o.i.b + o.i.c; o.i = (j); r = r + o.i.a + o.i.b + o.i.c; var i = 0; o.i = j; for (i = 0; i < 1; o.i = (z.k)) { i = i + 1; } return r + o.i.a + o.i.b + o.i.c - 228; }$E"
exits q02 0 "Q2: var q: K = (z.k); (SIGSEGV) and w = (j); (one word)" "${KQ}fn main(): i64 { var z = Z { 1, 20, 25, 30 }; var j = K { 21, 26, 31 }; var q: K = (z.k); var w = K { 0, 0, 0 }; w = (j); return q.a + q.b + q.c + w.a + w.b + w.c - 153; }$E"
exits q03 6 "Q3: var G: K = (A); at top level (SIGSEGV)" "${KQ}var A = K { 1, 2, 3 };\nvar G: K = (A);\nsyscall(60, G.a + G.b + G.c);\n"
refused q04 "cannot copy 'q' into a variable of a different struct/vector type: 'v'" "Q4: var v: K = (q) with q: Q" "${KQ}fn main(): i64 { var q = Q { 1, 2, 3 }; var v: K = (q); return v.a; }$E"
refused q05 "cannot copy 'q' into a variable of a different struct/vector type: 'v'" "Q5: v = (q) with q: Q" "${KQ}fn main(): i64 { var q = Q { 1, 2, 3 }; var v = K { 0, 0, 0 }; v = (q); return v.a; }$E"
refused q06 "cannot copy 'q' into a struct field of a different struct type: 'i'" "Q6: o.i = (q) with q: Q" "${KQ}fn main(): i64 { var q = Q { 1, 2, 3 }; var o = O { 0, 0, 0, 0 }; o.i = (q); return o.n; }$E"
refused q07 "cannot copy 'mkq' into a variable of a different struct/vector type: 'v'" "Q7: v = (mkq(5))" "${KQ}fn main(): i64 { var v = K { 0, 0, 0 }; v = (mkq(5)); return v.a; }$E"
refused q08 "fn return struct-id differs from declared var type" "Q8: var v: K = (mkq(5))" "${KQ}fn main(): i64 { var v: K = (mkq(5)); return v.a; }$E"
refused q09 "cannot copy 'k' into a variable of a different struct/vector type: 'v'" "Q9: var v: K = (z.k) with z.k: Q" "struct K { a; b; c; }\nstruct Q { a; b; c; }\nstruct Z { m; k: Q; }\nfn main(): i64 { var z = Z { 1, 2, 3, 4 }; var v: K = (z.k); return v.a; }$E"
exits q10 0 "Q10: var q: K = (mkk(fncall1(|x| { var y = x * x; return y; }, 2))); (the filed repro: expected ';')" "include \"lib/fnptr.cyr\"\nstruct K { a; b; c; }\nfn mkk(v): K { var t: K = K { v, v + 1, v + 2 }; return t; }\nfn main(): i64 { var q: K = (mkk(fncall1(|x| { var y = x * x; return y; }, 2))); return q.a * 100 + q.b * 10 + q.c - 456; }$E"
exits o07 5 "O7: s - mkv(fncall1(|x| { var y = x; return y; }, 4)) (the filed repro: SIGSEGV)" "include \"lib/fnptr.cyr\"\nstruct V3 { x; y; z; }\nfn V3_sub(a: *V3, b: *V3): i64 { return a.z - b.z; }\nfn mkv(v): V3 { var t: V3 = V3 { v, v, v }; return t; }\nfn main(): i64 { var s: V3 = V3 { 9, 9, 9 }; return s - mkv(fncall1(|x| { var y = x; return y; }, 4)); }$E"
exits o01 5 "O1: s - mk3(4) into *P3 operands (the filed repro: SIGSEGV)" "${P3S}fn P3_sub(a: *P3, b: *P3) { return a.z - b.z; }\nfn main() { var s: P3 = P3 { 9, 9, 9 }; return s - mk3(4); }$E"
PT2='struct Pt { x; y; }\nfn Pt_add(a: Pt, b: Pt) { return a.x + b.x + a.y + b.y; }\nimpl Pt { fn dup(self): Pt { var t: Pt = Pt { self.x, self.y }; return t; } }\nfn mk2(v): Pt { var t: Pt = Pt { v, v }; return t; }\n'
exits o02 6 "O2: p + p.dup() (the filed repro: SIGSEGV)" "${PT2}fn main() { var p: Pt = Pt { 1, 2 }; return p + p.dup(); }$E"
exits o03 15 "O3: p + (p.dup()) + p + mk2(3) wrapped and a rax:rdx free call" "${PT2}fn main() { var p: Pt = Pt { 1, 2 }; var a = p + (p.dup()); return a + (p + mk2(3)); }$E"
TLO="the right operand of 'Pt_add' is passed by address"
refused o04 "$TLO" "O4: G + G.dup() at top level (no frame)" "${PT2}var G: Pt = Pt { 1, 2 };\nvar r = G + G.dup();\nsyscall(60, r);\n"
refused o05 "$TLO" "O5: G + mk2(3) at top level (no frame)" "${PT2}var G: Pt = Pt { 1, 2 };\nvar r = G + mk2(3);\nsyscall(60, r);\n"
refused o06 "cannot pass 'mkq' to a parameter of a different struct type in a call to 'P3_sub'" "O6: s - mkq(4) with mkq: Q3" "${P3S}struct Q3 { x; y; z; }\nfn P3_sub(a: *P3, b: *P3) { return a.z - b.z; }\nfn mkq(v): Q3 { var t: Q3 = Q3 { v, v, v }; return t; }\nfn main() { var s: P3 = P3 { 9, 9, 9 }; return s - mkq(4); }$E"
HSQ='include "lib/str.cyr"\nstruct H { name: Str; k; }\nstruct Q { a; b; c; }\nstruct S1 { v; }\nstruct O { n; q: Q; }\n'
HMK='alloc_init(); var h: H; h.name = str_from("abc"); h.k = 7;'
SPC="to a parameter of a different struct type in a call to"
SCP="into a variable of a different struct/vector type"
refused s01 "cannot pass 'name' $SPC 'bq'" "S1: bq(h.name), fn bq(b: Q) (the filed repro: built)" "${HSQ}fn bq(b: Q): i64 { return b.c; }\nfn main(): i64 { $HMK return bq(h.name); }$E"
refused s02 "cannot copy 'name' $SCP: 'q'" "S2: var q: Q = h.name; (the filed repro: built)" "${HSQ}fn main(): i64 { $HMK var q: Q = h.name; return q.c; }$E"
refused s03 "cannot copy 'name' $SCP: 'q'" "S3: q = h.name; into an inline Q" "${HSQ}fn main(): i64 { $HMK var q = Q { 1, 2, 3 }; q = h.name; return q.c; }$E"
refused s04 "cannot copy 'name' into a struct field of a different struct type: 'q'" "S4: o.q = h.name;" "${HSQ}fn main(): i64 { $HMK var o = O { 0, 1, 2, 3 }; o.q = h.name; return o.n; }$E"
refused s05 "cannot pass 'name' $SPC 'Q_add'" "S5: q + h.name, fn Q_add(a: Q, b: Q)" "${HSQ}fn Q_add(a: Q, b: Q): i64 { return a.c + b.c; }\nfn main(): i64 { $HMK var q = Q { 1, 2, 3 }; return q + h.name; }$E"
refused s06 "cannot pass 'name' $SPC 'b1'" "S6: b1(h.name), an 8-byte by-value parameter" "${HSQ}fn b1(b: S1): i64 { return b.v; }\nfn main(): i64 { $HMK return b1(h.name); }$E"
refused s07 "cannot copy 'name' (a Str field) into a global of a different struct type" "S7: var GQ: Q = GH.name; at top level" "${HSQ}var GH: H = H { 0, 7 };\nvar GQ: Q = GH.name;\nsyscall(60, GQ.c);\n"
refused s08 "cannot pass 'name' $SPC 'bq'" "S8: bq((h.name)), fn bq(b: *Q)" "${HSQ}fn bq(b: *Q): i64 { return b.c; }\nfn main(): i64 { $HMK return bq((h.name)); }$E"
exits s09 0 "S9: a handle Q rebinds to h.name (6.6.16 C2), untouched" "${HSQ}fn main(): i64 { $HMK var q: Q = alloc(24); q = h.name; return 0; }$E"
exits s10 12 "S10: u = h.name; o.s = h.name; into Str destinations" "${HSQ}struct OS { n; s: Str; }\nfn main(): i64 { $HMK var u: Str = str_from(\"x\"); u = h.name; var o: OS; o.n = 0; o.s = h.name; var w: Str = (h.name); return str_len(u) * 4 + str_len(o.s) - str_len(w); }$E"
exits p06 21 "P6: sz(((a)) + (b)): a double wrap that is only the left operand" "${P3S}fn P3_add(a: *P3, b: *P3): P3 { var t: P3 = P3 { a.x + b.x, a.y + b.y, a.z + b.z }; return t; }\nfn sz(p: P3) { return p.x + p.y + p.z; }\nfn main() { var a: P3 = P3 { 1, 2, 3 }; var b: P3 = P3 { 4, 5, 6 }; return sz(((a)) + (b)) + rd3(((b))) - 6; }$E"

# L (6.7.6 E2) — a struct-returning call / method / operator result as the LEFT operand dispatches.
LPT='struct Pt { x; y; }\nfn Pt_add(a: Pt, b: Pt) { return a.x + b.x + a.y + b.y; }\nimpl Pt { fn dup(self): Pt { var t: Pt = Pt { self.x, self.y }; return t; } }\nfn mk2(v): Pt { var t: Pt = Pt { v, v }; return t; }\n'
LW='struct LW { v; }\nfn LW_sub(a: *LW, b: *LW): i64 { return a.v * 10 - b.v; }\nfn mklw(v): LW { var t: LW; t.v = v; return t; }\n'
exits l01 6 "L1: p.dup() + p (the filed repro: 2, first words integer-added)" "${LPT}fn main() { var p: Pt = Pt { 1, 2 }; return p.dup() + p; }$E"
exits l02 5 "L2: mk3(4) - s + 10 (the filed repro: an undefined P3_add from s's leftover type)" "${P3S}fn P3_sub(a: *P3, b: *P3) { return a.z - b.z; }\nfn main() { var s: P3 = P3 { 9, 9, 9 }; return mk3(4) - s + 10; }$E"
exits l03 10 "L3: mk2(4) - s, a by-value rax:rdx operand (-5: first words)" "struct Pt { x; y; }\nfn Pt_sub(a: Pt, b: Pt) { return a.x - b.x + a.y - b.y + 20; }\nfn mk2(v): Pt { var t: Pt = Pt { v, v }; return t; }\nfn main() { var s: Pt = Pt { 9, 9 }; return mk2(4) - s; }$E"
exits l04 72 "L4: a + b + a, a struct-returning + (SIGSEGV)" "struct V3 { x; y; z; }\nfn V3_add(a: V3, b: V3): V3 { var t: V3 = V3 { a.x + b.x, a.y + b.y, a.z + b.z }; return t; }\nfn main() { var a: V3 = V3 { 1, 2, 3 }; var b: V3 = V3 { 10, 20, 30 }; var c: V3 = a + b + a; return c.x + c.y + c.z; }$E"
refused l05 "undefined function 'LW_add'" "L5: mklw(3) + 4 with no LW_add (an integer add of the struct's bytes)" "${LW}fn main() { return mklw(3) + 4; }$E"
refused l06 "the left operand of 'Pt_add' is passed by address" "L6: G.dup() + G at top level (no frame)" "${LPT}var G: Pt = Pt { 1, 2 };\nvar r = G.dup() + G;\nsyscall(60, r);\n"
refused l07 "the left operand of 'Pt_add' is passed by address" "L7: mk2(3) + G at top level (no frame)" "${LPT}var G: Pt = Pt { 1, 2 };\nvar r = mk2(3) + G;\nsyscall(60, r);\n"
refused l08 "the left operand of 'LW_sub' is passed by address" "L8: mklw(5) - G into *LW at top level" "${LW}var G: LW = LW { 3 };\nvar r = mklw(5) - G;\nsyscall(60, r);\n"
refused l09 "cannot pass 'mkq' to a parameter of a different struct type in a call to 'Q3_sub'" "L9: mkq(4) - s, fn Q3_sub(a: P3, b: Q3)" "${P3S}struct Q3 { x; y; z; }\nfn Q3_sub(a: P3, b: Q3) { return 1; }\nfn mkq(v): Q3 { var t: Q3 = Q3 { v, v, v }; return t; }\nfn main() { var s: Q3 = Q3 { 9, 9, 9 }; return mkq(4) - s; }$E"
refused l10 "'mk3' returns a struct by value, and a struct result needs storage" "L10: mk3(4) - G at top level, refused once (by the call)" "${P3S}fn P3_sub(a: *P3, b: *P3) { return a.z - b.z; }\nvar G: P3 = P3 { 9, 9, 9 };\nvar r = mk3(4) - G;\nsyscall(60, r);\n"
exits l11 8 "L11: a Str-returning call stays a handle: gs() + 8 - gs() is pointer arithmetic" "include \"lib/str.cyr\"\nvar GS: Str = 0;\nfn gs(): Str { return GS; }\nfn main() { alloc_init(); GS = str_from(\"abc\"); return gs() + 8 - gs(); }$E"
exits l12 5 "L12: var r = mk3(4) - s; in a fn (the filed repro: expected ';', got '-')" "${P3S}fn P3_sub(a: *P3, b: *P3) { return a.z - b.z; }\nfn main() { var s: P3 = P3 { 9, 9, 9 }; var r = mk3(4) - s; return r + 10; }$E"
exits l13 5 "L13: return mk2(1) + a; from a fn returning Pt (expected ';')" "struct Pt { x; y; }\nfn Pt_add(a: Pt, b: Pt): Pt { var t: Pt = Pt { a.x + b.x, a.y + b.y }; return t; }\nfn mk2(v): Pt { var t: Pt = Pt { v, v }; return t; }\nfn rp(a: Pt): Pt { return mk2(1) + a; }\nfn main(): i64 { var p: Pt = Pt { 1, 2 }; var q: Pt = rp(p); return q.x + q.y; }$E"
refused l14 "struct-return fn: return must be a bare local identifier" "L14: return mk3(1) + a; whose + returns an integer" "${P3S}fn P3_add(a: P3, b: P3): i64 { return a.x + b.x; }\nfn rp(a: P3): P3 { return mk3(1) + a; }\nfn main(): i64 { var p: P3 = P3 { 1, 2, 3 }; var q: P3 = rp(p); return q.x; }$E"
refused l15 "the left operand of 'Pt_add' is passed by address" "L15: var G: Pt = mk2(3) + H; at top level, refused once" "struct Pt { x; y; }\nfn Pt_add(a: Pt, b: Pt): Pt { var t: Pt = Pt { a.x + b.x, a.y + b.y }; return t; }\nfn mk2(v): Pt { var t: Pt = Pt { v, v }; return t; }\nvar H: Pt = Pt { 1, 2 };\nvar G: Pt = mk2(3) + H;\nsyscall(60, G.x);\n"
# L16 / L17 (6.7.11) — a leading call's struct types an untyped declaration only when the call ends it
# (`_var_rhs_csid`): after an integer-returning operator or a comparison the binding is untyped.
ROPR=docs/development/issues/repros/2026-10-08-struct-operator-results
refused_file l16 "no struct type in scope for 'r'" "L16: var r = mk3(4) - s; r.x (the filed repro, verbatim: SIGSEGV)" "$ROPR-1-untyped-var-typed-from-leading-call.cyr"
refused l17 'got `r`' "L17: var r = mk2(1) == p; return r; from a fn returning Pt (SIGSEGV: a 16 B return from an 8 B slot)" "struct Pt { x; y; }\nfn mk2(v): Pt { var t: Pt = Pt { v, v }; return t; }\nfn g(p: Pt): Pt { var r = mk2(1) == p; return r; }\nfn main(): i64 { var p: Pt = Pt { 1, 1 }; var q: Pt = g(p); return q.x; }$E"
# K (6.7.11) — an integer operator's result is an integer: the next `+ - * /` never dispatches on the struct
# its right operand left (the values file's K rows: every integer arm, 24 B and 8 B, the twins).
exits_file k01 8 "K1: n - s + 10 (the filed repro, verbatim: SIGSEGV in P3_add(&s, 10))" "$ROPR-2-integer-op-keeps-right-struct-type.cyr"
exits k02 8 "K2: n - s + 10 with no P3_add compiles (refused 'undefined function P3_add' through 6.7.10)" "struct P3 { x; y; z; }\nfn main(): i64 { var s: P3 = P3 { 5, 6, 7 }; var n = 3; return n - s + 10; }$E"
exits k03 11 "K3: (n < s) + 10 and (~s) + 10 with no P3_add compile" "struct P3 { x; y; z; }\nfn main(): i64 { var s: P3 = P3 { 5, 6, 7 }; var n = 3; return (n < s) + 10 + (~s) + 6; }$E"
# U (6.7.11, the user's decision (a), 2026-10-13) — `-s` on a struct is integer negation of its word, with no
# struct type: `-s + t` is an integer add at every size, as `-w.s + t` is (the values file's U rows).
exits_file u01 252 "U1: -s + t (the filed repro, verbatim: 6, the minus dropped)" "$ROPR-3-unary-minus-on-struct-dropped.cyr"
US8='struct S8 { v; }\nfn S8_add(a: S8, b: S8): S8 { var r: S8; r.v = a.v * 100 + b.v; return r; }\nvar G = S8 { 5 };\nvar H = S8 { 1 };\n'
exits u02 252 "U2: var X: S8 = -G + H; in the declaration zone (13: the dispatch; the zone's typer agrees)" "${US8}var X: S8 = -G + H;\nsyscall(60, load64(&X));\n"
exits u03 252 "U3: ... after the first statement (13)" "${US8}var k = 0;\nk = 1;\nvar X: S8 = -G + H;\nsyscall(60, load64(&X));\n"
# R (6.7.6 E2) — parentheses around a struct fn's whole return value; the top-level operand wording.
exits r01 6 "R1: return (j); from a fn returning a 24-byte P3 (the filed repro: refused)" "struct P3 { x; y; z; }\nfn cp(j: P3): P3 { return (j); }\nfn main(): i64 { var j = P3 { 1, 2, 3 }; var q: P3 = cp(j); return q.x + q.y + q.z; }$E"
exits r02 6 "R2: return (mk3(v)); (the filed repro: refused)" "struct P3 { x; y; z; }\nfn mk3(v): P3 { var t: P3 = P3 { v, v, v }; return t; }\nfn cp(v): P3 { return (mk3(v)); }\nfn main(): i64 { var q: P3 = cp(2); return q.x + q.y + q.z; }$E"
exits r03 3 "R3: return (j); from a fn returning a 16-byte Pt (refused: got (...))" "struct Pt { x; y; }\nfn cp(j: Pt): Pt { return (j); }\nfn main(): i64 { var j = Pt { 1, 2 }; var q: Pt = cp(j); return q.x + q.y; }$E"
refused r04 'got `5`' "R4: return (5); from a Pt fn, refused once naming 5" "struct Pt { x; y; }\nfn f(): Pt { return (5); }\nfn main(): i64 { var q: Pt = f(); return q.x; }$E"
refused r05 'struct-return: identifier type != fn ret_sid' "R5: return (q); with q: Q from a P3 fn, refused as return q; is" "struct Q { x; y; z; }\nstruct P3 { x; y; z; }\nfn f(q: Q): P3 { return (q); }\nfn main(): i64 { var a: Q = Q { 1, 2, 3 }; var r: P3 = f(a); return r.x; }$E"
refused r06 "the left operand of 'Pt_add' is passed by address (a struct over 8 bytes)" "R6: a by-value 16-byte operand at top level is not called a * parameter" "${LPT}var G: Pt = Pt { 1, 2 };\nvar r = G.dup() + G;\nsyscall(60, r);\n"
refused r07 'the left operand of '"'"'LW_sub'"'"' is passed by address (a `*` parameter)' "R7: a *LW operand at top level keeps its wording" "${LW}var G: LW = LW { 3 };\nvar r = mklw(5) - G;\nsyscall(60, r);\n"
# R8-R15 (6.7.11, issues/archived/2026-10-08-struct-operator-results.md #4; the user's decision (a), 2026-10-13) a tuple
# literal `return (a, b[, c]);` in a fn declared to return a named struct took the multi-value path: over 16 B
# the result pointer was never written (the filed repro: 0), at 8 B or less the second value was dropped (1),
# at 9-16 B it worked by ABI coincidence (12). Refused by name in every class, once; a fn declared `: (T1, T2)`,
# an undeclared one and `return ((a, b));`'s own refusal are unchanged.
RTUP='returns that struct — `(a, b)` is a tuple, another type'
refused_file r08 "a fn returning the struct \`P3\` $RTUP" "R8: return (a, b); from a fn returning a 24 B P3 (the filed repro, verbatim: 0)" "$ROPR-4-tuple-return-in-struct-fn.cyr"
refused r09 "a fn returning the struct \`S8\` $RTUP" "R9: ... from an 8 B S8 (1: b dropped)" "struct S8 { v; }\nfn f(a, b): S8 { return (a, b); }\nfn main(): i64 { var q: S8 = f(1, 2); return q.v; }$E"
refused r10 "a fn returning the struct \`Pt\` $RTUP" "R10: ... from a 16 B Pt (12: rax:rdx by coincidence)" "struct Pt { x; y; }\nfn f(a, b): Pt { return (a, b); }\nfn main(): i64 { var q: Pt = f(1, 2); return q.x * 10 + q.y; }$E"
refused r11 'a fn returning the struct `P3` returns that struct — `(a, b, c)` is a tuple, another type' "R11: return (a, b, 7); from a 24 B P3 (0)" "struct P3 { x; y; z; }\nfn f(a, b): P3 { return (a, b, 7); }\nfn main(): i64 { var q: P3 = f(1, 2); return q.x * 100 + q.y * 10 + q.z; }$E"
exits r12 12 "R12: fn f(): (i64, i64) { return (1, 2); } still builds" "fn f(): (i64, i64) { return (1, 2); }\nfn main(): i64 { var a, b = f(); return a * 10 + b; }$E"
exits r13 12 "R13: an undeclared fn's return (a, b); still builds" "fn f(a, b) { return (a, b); }\nfn main(): i64 { var a, b = f(1, 2); return a * 10 + b; }$E"
refused r14 'a multi-value return is written `return (a, b);` - drop the extra parentheses' "R14: return ((a, b)); from a Pt fn keeps its own refusal" "struct Pt { x; y; }\nfn f(a, b): Pt { return ((a, b)); }\nfn main(): i64 { var q: Pt = f(1, 2); return q.x; }$E"
refused r15 'struct-return fn: return must be a bare local identifier' "R15: return ((a, b)); from a P3 fn keeps its own refusal" "struct P3 { x; y; z; }\nfn f(a, b): P3 { return ((a, b)); }\nfn main(): i64 { var q: P3 = f(1, 2); return q.x; }$E"
# R27 / R28 — the refusal judges the fn the `return` belongs to: an `#inline` or generic callee's `return (a, b);`
# replayed inside a fn returning P3 (GIDEP) is the callee's, and builds.
exits r27 127 "R27: an #inline fn's return (a, b); replayed in a P3 fn still builds" "struct P3 { x; y; z; }\n#inline\nfn two(a, b) { return (a, b); }\nfn f(a, b): P3 { var c, d = two(a, b); var r: P3 = P3 { c, d, 7 }; return r; }\nfn main(): i64 { var q: P3 = f(1, 2); return q.x * 100 + q.y * 10 + q.z; }$E"
exits r28 127 "R28: a generic fn's return (a, b); replayed in a P3 fn still builds" "struct P3 { x; y; z; }\nfn two<T>(a: T, b: T) { return (a, b); }\nfn f(a, b): P3 { var c, d = two(a, b); var r: P3 = P3 { c, d, 7 }; return r; }\nfn main(): i64 { var q: P3 = f(1, 2); return q.x * 100 + q.y * 10 + q.z; }$E"
# R16-R26 (6.7.11, issues/archived/2026-10-08-struct-operator-results.md #5; the user's decision (a), 2026-10-13) in a fn
# returning a 9-16 B struct, `return mk2(1) OP x;` with an operator that does not dispatch passed the pair-call
# check (`_pair_ret_call_ok` asked only that a same-struct call START the value): rax the operator's result, rdx
# mk2's stale second word (the filed repro: 41). The call must END the value (`_call_ends_at`): refused by name,
# once ('got `mk2`'), as `return mk2(1).x;` is. `return mk2(1);` (the tail call), its wrap and a dispatching
# `mk2(1) + p` are unchanged.
RPR='a fn returning the 9-16 byte struct `Pt` is returned in two registers, so `return` takes a local of that struct or a call returning it — got `mk2`'
RPH='struct Pt { x; y; }\nfn mk2(v): Pt { var t: Pt = Pt { v, v + 40 }; return t; }\n'
RPM="fn main(): i64 { var p: Pt = Pt { 1, 2 }; var q: Pt = g(p); return q.x * 100 + q.y; }$E"
refused_file r16 "$RPR" "R16: return mk2(1) == p; from a Pt fn (the filed repro, verbatim: 41, q.y = mk2's y)" "$ROPR-5-pair-return-leading-call-operator.cyr"
refused r17 "$RPR" "R17: return mk2(1) < 3; (141)" "${RPH}fn g(p: Pt): Pt { return mk2(1) < 3; }\n${RPM}"
refused r18 "$RPR" "R18: return mk2(1) & 3; (141)" "${RPH}fn g(p: Pt): Pt { return mk2(1) & 3; }\n${RPM}"
refused r19 "$RPR" "R19: return mk2(1) << 3; (73)" "${RPH}fn g(p: Pt): Pt { return mk2(1) << 3; }\n${RPM}"
refused r20 "$RPR" "R20: return mk2(1) && 3; (141)" "${RPH}fn g(p: Pt): Pt { return mk2(1) && 3; }\n${RPM}"
refused r21 "$RPR" "R21: return mk2(1) % 3; (101: the idiv remainder in rdx)" "${RPH}fn g(p: Pt): Pt { return mk2(1) % 3; }\n${RPM}"
refused r22 "$RPR" "R22: return (mk2(1) == p); inside a wrap (141)" "${RPH}fn g(p: Pt): Pt { return (mk2(1) == p); }\n${RPM}"
exits r23 141 "R23: return mk2(1); (the tail call) still builds" "${RPH}fn g(p: Pt): Pt { return mk2(1); }\n${RPM}"
exits r24 141 "R24: return (mk2(1)); still builds" "${RPH}fn g(p: Pt): Pt { return (mk2(1)); }\n${RPM}"
exits r25 243 "R25: return mk2(1) + p; (a dispatch) still builds" "${RPH}fn Pt_add(a: Pt, b: Pt): Pt { var r: Pt = Pt { a.x + b.x, a.y + b.y }; return r; }\nfn g(p: Pt): Pt { return mk2(1) + p; }\n${RPM}"
exits r26 141 "R26: var k = p.x; return mk2(k); (a tail call after a statement) still builds" "${RPH}fn g(p: Pt): Pt { var k = p.x; return mk2(k); }\n${RPM}"
# MP (6.7.11, issues/archived/2026-10-10-field-of-method-pointer-result-refused.md; the user's decision (a), 2026-10-13) a
# METHOD's `*T` result takes `.field` / `.m(..)` / a deeper chain, as a free call's has since 6.6.17 — it was "cannot
# take a field of the result of 'H_get': it does not return a struct" (`_mchain_ptr`; the values file's MP rows, in
# a fn, at top level, through a dyn and a generic method, on A1-A7). The store through it stays refused, now as the
# free call's is (the 6.7.12 store issue); a method returning no struct and no `*T` keeps its refusal.
MPH='struct P { a; b; }\nstruct H { p: *P; }\n'
exits_file mp1 44 "MP1: var y = h.get().b; (the filed repro, verbatim: refused)" docs/development/issues/repros/2026-10-10-field-of-method-pointer-result-refused.cyr
exits mp2 43 "MP2: a method defined below its use (pass 1's record)" "${MPH}fn main(): i64 { var p = P { 3, 4 }; var h = H { &p }; return h.get().b * 10 + h.get().a; }\nimpl H { fn get(self): *P { return self.p; } }$E"
refused mp3 'cannot assign to a field of a call result: the result is a temporary' "MP3: h.get().b = 5; stays refused, as get2(&h).b = 5; is (6.7.12)" "${MPH}impl H { fn get(self): *P { return self.p; } }\nfn main(): i64 { var p = P { 3, 4 }; var h = H { &p }; h.get().b = 5; return p.b; }$E"
refused mp4 "cannot take a field of the result of 'H_gi': it does not return a struct" "MP4: a method returning *i64 keeps the refusal" "${MPH}impl H { fn gi(self): *i64 { return 0; } }\nfn main(): i64 { var p = P { 3, 4 }; var h = H { &p }; return h.gi().b; }$E"
refused mp5 "cannot take a field of the result of 'H_n': it does not return a struct" "MP5: a method returning i64 keeps the refusal" "${MPH}impl H { fn n(self): i64 { return 1; } }\nfn main(): i64 { var p = P { 3, 4 }; var h = H { &p }; return h.n().b; }$E"
# PE (6.7.11, issues/archived/2026-10-10-paren-wrapped-struct-call-as-nested-literal-element-refused.md; the user's decision
# (a), 2026-10-13) a free struct call in parentheses as a nested-struct literal element is the element the
# unwrapped call is (`_spi_pcall`): it was parsed as a scalar for the first leaf, so 16 B, 24 B and 8 B with two
# leaves were "unexpected '}'". The values file's Q31-Q41 run it on A1-A7; here the repro, the top-level refusals
# (by name, once, as the unwrapped call's) and another struct refused by name — as the unwrapped call is; at 8 B
# with one leaf it compiled, the word carried into the leaf unchecked.
PEH='struct Q { a; b; }\nstruct H { x; q: Q; z; }\nfn mkq(a, b): Q { var q = Q { a, b }; return q; }\n'
PEM="'mkq' returns a struct by value, and a struct result needs storage in a fn's frame"
exits_file pe1 64 "PE1: H { 7, (mkq(4, 9)), 8 } (the filed repro, verbatim: unexpected '}')" docs/development/issues/repros/2026-10-10-paren-wrapped-struct-call-as-nested-literal-element-refused.cyr
refused pe2 "$PEM" "PE2: at top level, 16 B: refused by name once (unexpected '}')" "${PEH}var G = H { 7, (mkq(4, 9)), 8 };\nsyscall(60, G.x);\n"
refused pe3 "$PEM" "PE3: at top level, 24 B: refused once (+ unexpected '}')" "struct Q { a; b; c; }\nstruct H { x; q: Q; z; }\nfn mkq(a, b): Q { var q = Q { a, b, 1 }; return q; }\nvar G = H { 7, ((mkq(4, 9))), 8 };\nsyscall(60, G.x);\n"
refused pe4 "cannot copy 'mko' into a struct field of a different struct type: 'q'" "PE4: (mko(5)) of another 8 B struct, refused as mko(5) is (compiled: 65)" "struct Q { a; }\nstruct O { a; }\nstruct H { x; q: Q; z; }\nfn mko(a): O { var o = O { a }; return o; }\nfn main(): i64 { var h = H { 7, (mko(5)), 8 }; return h.x + h.q.a * 10 + h.z; }$E"
refused pe5 "cannot copy 'mko' into a struct field of a different struct type: 'q'" "PE5: (mko(4, 9)) of another 16 B struct, refused by name (unexpected '}')" "${PEH}struct O { a; b; }\nfn mko(a, b): O { var q = O { a, b }; return q; }\nfn main(): i64 { var h = H { 7, (mko(4, 9)), 8 }; return h.x; }$E"
exits pe6 64 "PE6: H { 7, (mkq(4, 9)), 8 } at top level of an 8 B two-u32 Q (unexpected '}')" "struct Q { a: u32; b: u32; }\nstruct H { x; q: Q; z; }\nfn mkq(a, b): Q { var q = Q { a, b }; return q; }\nvar G = H { 7, (mkq(4, 9)), 8 };\nsyscall(60, G.x + G.q.a * 10 + G.q.b + G.z);\n"
# N (6.7.6 E2) — lib/fnptr.cyr's address-taken fncall8 passes a cyrius callee args 7 / 8 in cyrius's order.
exits n01 78 "N1: callptr(&fncall8, &s8, 1..8) % 100 (x86 SysV: 87, args 7 and 8 swapped)" "include \"lib/alloc.cyr\"\ninclude \"lib/fnptr.cyr\"\nfn s8(a, b, c, d, e, f, g, h) { return a * 10000000 + b * 1000000 + c * 100000 + d * 10000 + e * 1000 + f * 100 + g * 10 + h; }\nfn main() { return callptr(&fncall8, &s8, 1, 2, 3, 4, 5, 6, 7, 8) % 100; }$E"

# FP (6.7.11) — a struct result through fncallN / callptr with a known callee.
FPH='include "lib/fnptr.cyr"\nstruct P1 { a; }\nstruct P2 { a; b; }\nstruct P3 { a; b; c; }\nfn mk1(a): P1 { var r: P1 = P1 { a + 3 }; return r; }\nfn mk2(a): P2 { var r: P2 = P2 { a, a + 1 }; return r; }\nfn mk3(a): P3 { var r: P3 = P3 { a, a + 1, a + 2 }; return r; }\n'
exits fp1 18 "FP1: var p: P3 = fncall1(&mk3, 5); (the filed repro, verbatim: SIGSEGV)" "include \"lib/fnptr.cyr\"\nstruct P3 { a; b; c; }\nfn mk3(a): P3 { var r: P3 = P3 { a, a + 1, a + 2 }; return r; }\nfn main() {\n    var p: P3 = fncall1(&mk3, 5);\n    return p.a + p.b + p.c;\n}\nvar r = main();\nsyscall(60, r);\n"
exits fp2 8 "FP2: var p: P1 = fncall1(&mk1, 5); (8 B: right through 6.7.9, a handle reading address 8 in 6.7.10)" "${FPH}fn main() { var p: P1 = fncall1(&mk1, 5); return p.a; }$E"
exits fp3 11 "FP3: var p: P2 = callptr(&mk2, 5); (16 B: the first word as an address)" "${FPH}fn main() { var p: P2 = callptr(&mk2, 5); return p.a + p.b; }$E"
exits fp4 36 "FP4: p = callptr(&mk3, 5); and sz(fncall1(&mk3, 5)) (24 B: SIGSEGV)" "${FPH}fn sz(q: P3): i64 { return q.a + q.b + q.c; }\nfn main() { var p: P3 = P3 { 0, 0, 0 }; p = callptr(&mk3, 5); return p.a + p.b + p.c + sz(fncall1(&mk3, 5)); }$E"
exits fp5 29 "FP5: return fncall1(&mk3, a); / return callptr(&mk2, a); (refused through 6.7.10)" "${FPH}fn r3(a): P3 { return fncall1(&mk3, a); }\nfn r2(a): P2 { return callptr(&mk2, a); }\nfn main() { var p: P3 = r3(5); var q: P2 = r2(5); return p.a + p.b + p.c + q.a + q.b; }$E"
exits fp6 26 "FP6: var p: P3 = callptr(fp, 5) through a variable is a handle (decided): fn gp(a): *P3" "${FPH}var G: P3 = P3 { 0, 0, 0 };\nfn gp(a): *P3 { G.a = a; G.b = a + 1; G.c = a + 10; return &G; }\nfn main() { var fp = &gp; var p: P3 = callptr(fp, 5); p.a = p.a + 0; return G.a + G.b + G.c; }$E"
exits fp7 61 "FP7: var a, b = fncall1(&mk2, 5) keeps its two words; var g: P1 = fncall1(&mk1, 2) in the zone" "${FPH}var g: P1 = fncall1(&mk1, 2);\nfn main() { var a, b = fncall1(&mk2, 5); return a + b + g.a * 10; }$E"
refused fp8 "'mk3' returns a struct by value, and a struct result needs storage in a fn's frame" "FP8: var g: P3 = fncall1(&mk3, 5); at top level, refused by name" "${FPH}var g: P3 = fncall1(&mk3, 5);\nsyscall(60, g.a);\n"
refused fp9 "fn return struct-id differs from declared var type" "FP9: var q: Q3 = fncall1(&mk3, 5); (another struct: SIGSEGV)" "${FPH}struct Q3 { a; b; c; }\nfn main() { var q: Q3 = fncall1(&mk3, 5); return q.a; }$E"

# EV (6.7.11) — the filed repros verbatim, under CYRIUS_IR=3: a just-stored local after an EFLADDR `lea`.
exits_ir3 ev1 35 "EV1: o.with2(x) after var x = 5; under CYRIUS_IR=3 (the filed repro: 30 + the low byte of &o)" "struct S8 { v; }\nimpl S8 { fn with2(self: *S8, n): i64 { return self.v * 10 + n; } }\nfn a2(): i64 { var o: S8; o.v = 3; var x = 5; return o.with2(x); }\nsyscall(60, a2());\n"
exits_ir3 ev2 0 "EV2: o.same(x), the identity probe, under CYRIUS_IR=3 (the filed repro: 1, n == self)" "struct S8 { v; }\nimpl S8 { fn same(self: *S8, n): i64 { if (n == self) { return 1; } return 0; } }\nfn a2(): i64 { var o: S8; o.v = 3; var x = 5; return o.same(x); }\nsyscall(60, a2());\n"
exits_ir3 ev3 35 "EV3: bs(h, x), a 16 B by-value struct, under CYRIUS_IR=3 (the filed repro: varies)" "struct H { a; b; }\nfn bs(h: H, n): i64 { return h.a * 10 + n; }\nfn g(): i64 { var h: H; h.a = 3; h.b = 0; var x = 5; return bs(h, x); }\nsyscall(60, g());\n"
exits_ir3 ev4 5 "EV4: var b: B = mk(x), a 24 B result, under CYRIUS_IR=3 (the filed repro: varies)" "struct B { a; b; c; }\nfn mk(n): B { var k: B; k.a = n; k.b = 0; k.c = 0; return k; }\nfn g(): i64 { var x = 5; var b: B = mk(x); return b.a; }\nsyscall(60, g());\n"

tcyr "A1: the values file (x86_64)" "$CC" ""
tcyr "A2: ... under CYRIUS_IR=1" "$CC" "" CYRIUS_IR=1
tcyr "A3: ... under CYRIUS_IR=3" "$CC" "" CYRIUS_IR=3
tcyr "A4: ... under CYRIUS_DCE=1" "$CC" "" CYRIUS_DCE=1
TCA=tests/tcyr/crossos/struct_value_codegen.tcyr
TCB=tests/tcyr/crossos/fncall_struct_result.tcyr   # 6.7.11: rows B
TCC=tests/tcyr/crossos/vector_call_result_discarded.tcyr   # 6.7.12: rows C
# One B row per `assert_eq(` call (the file defines none); the floor keeps a gutted file from passing.
NB=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TCB")
FLOORB=48
if [ "$NB" -lt "$FLOORB" ]; then bad "B: only $NB rows in $TCB (floor $FLOORB) — rows were lost"; fi
NC=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TCC")
FLOORC=15
if [ "$NC" -lt "$FLOORC" ]; then bad "C: only $NC rows in $TCC (floor $FLOORC) — rows were lost"; fi
TC=$TCB; TN=$NB
tcyr "B1: fncall_struct_result.tcyr (x86_64)" "$CC" ""
tcyr "B2: ... under CYRIUS_IR=1" "$CC" "" CYRIUS_IR=1
tcyr "B3: ... under CYRIUS_IR=3" "$CC" "" CYRIUS_IR=3
tcyr "B4: ... under CYRIUS_DCE=1" "$CC" "" CYRIUS_DCE=1
TC=$TCC; TN=$NC
tcyr "C1: vector_call_result_discarded.tcyr (x86_64)" "$CC" ""
tcyr "C2: ... under CYRIUS_IR=1" "$CC" "" CYRIUS_IR=1
tcyr "C3: ... under CYRIUS_IR=3" "$CC" "" CYRIUS_IR=3
tcyr "C4: ... under CYRIUS_DCE=1" "$CC" "" CYRIUS_DCE=1
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        TC=$TCA; TN=""
        tcyr "A5: aarch64 (qemu)" "$T/cc_a64" qemu-aarch64
        TC=$TCB; TN=$NB
        tcyr "B5: fncall_struct_result.tcyr, aarch64 (qemu): X8" "$T/cc_a64" qemu-aarch64
        TC=$TCC; TN=$NC
        tcyr "C5: vector_call_result_discarded.tcyr, aarch64 (qemu)" "$T/cc_a64" qemu-aarch64
    else bad "A5 / B5: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 legs A5 / B5 (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    printf '#!/bin/sh\nexec "%s" < "$1"\n' "$T/cxvm" > "$T/cxrun"; chmod +x "$T/cxrun"
    TC=$TCA; TN=""
    tcyr "A6: cx (cxvm)" "$T/cc_cx" "$T/cxrun"
    TC=$TCB; TN=$NB
    tcyr "B6: fncall_struct_result.tcyr, cx (cxvm)" "$T/cc_cx" "$T/cxrun"
    TC=$TCC; TN=$NC
    tcyr "C6: vector_call_result_discarded.tcyr, cx (cxvm)" "$T/cc_cx" "$T/cxrun"
else bad "A6 / B6: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
# 6.7.11 — PE (wine): the result pointer rides after PE's stack-pushed callee and is counted into
# ECALLPTR_PE's argc, code no other leg runs. The filed repro and the 8 B row, then the values file.
if command -v wine > /dev/null 2>&1; then
    exits_pe fpw1 18 "FPw1: FP1 (the filed repro, verbatim) on PE (wine)" "include \"lib/fnptr.cyr\"\nstruct P3 { a; b; c; }\nfn mk3(a): P3 { var r: P3 = P3 { a, a + 1, a + 2 }; return r; }\nfn main() {\n    var p: P3 = fncall1(&mk3, 5);\n    return p.a + p.b + p.c;\n}\nvar r = main();\nsyscall(60, r);\n"
    exits_pe fpw2 8 "FPw2: FP2 (8 B: var p: P1 = fncall1(&mk1, 5);) on PE (wine)" "${FPH}fn main() { var p: P1 = fncall1(&mk1, 5); return p.a; }$E"
    printf '#!/bin/sh\ncp "$1" "$1.exe" || exit 1\ncd "%s" && WINEPREFIX="%s" HOME="%s" XDG_CACHE_HOME="%s/.cache" WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d" exec wine "$1.exe"\n' \
        "$T" "$WP" "$WHM" "$WHM" > "$T/winrun"; chmod +x "$T/winrun"
    TC=$TCB; TN=$NB
    tcyr "B7: fncall_struct_result.tcyr, PE (wine)" "$CC" "$T/winrun" CYRIUS_TARGET_WIN=1
    TC=$TCA; TN=""
    tcyr "A7: the values file, PE (wine) (6.7.11: the K rows)" "$CC" "$T/winrun" CYRIUS_TARGET_WIN=1
    # 6.7.12 — the filed repros of the Win64 discarded vector result, verbatim (exit 5 before), then rows C.
    exits_pe vdw1 3 "VDw1: mkv(41, 7); as a statement (the filed repro 1, verbatim) on PE (wine)" "fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }\nfn run(): i64 {\n    mkv(41, 7);\n    return 3;\n}\nsyscall(60, run());\n"
    exits_pe vdw2 3 "VDw2: callptr(&mkv, 41, 7); (the filed repro 2, verbatim) on PE (wine)" "include \"lib/fnptr.cyr\"\nfn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }\nfn run(): i64 {\n    callptr(&mkv, 41, 7);\n    return 3;\n}\nsyscall(60, run());\n"
    exits_pe vdw3 3 "VDw3: var x = callptr(&mkv, 41, 7); (the filed repro 3, verbatim) on PE (wine)" "include \"lib/fnptr.cyr\"\nfn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }\nfn run(): i64 {\n    var x = callptr(&mkv, 41, 7);\n    return 3;\n}\nsyscall(60, run());\n"
    TC=$TCC; TN=$NC
    tcyr "C7: vector_call_result_discarded.tcyr, PE (wine)" "$CC" "$T/winrun" CYRIUS_TARGET_WIN=1
else echo "  SKIP: PE legs FPw1 / FPw2 / B7 / A7 / VDw1-VDw3 / C7 (wine not installed)"; skips=$((skips + 1)); fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — struct values and narrow fields as operands, struct results as left operands (L), struct results through fncallN / callptr (FP), a local after an EFLADDR under IR=3 (EV): values on x86_64 / IR / DCE / aarch64 / cx (A, B) and PE (B7, $NB rows); a discarded vector result (C, $NC rows, PE's VDw)"
