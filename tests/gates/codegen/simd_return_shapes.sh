#!/bin/sh
# Gate: a vector-returning fn `return`s only what the vector return ABI can carry (6.6.6).
#
# THE DEFECT (measured at 6.6.5 and at this lane's parent, x86_64 Linux, NO diagnostic, exit 0):
#
#     fn bad(): f64v2 { return 5; }        -> compiled clean, the caller read 0
#     fn bad(): f64v2 { var s = 5; return s; }                    -> same
#     fn bad(): f64v2 { return; }                                 -> same
#     fn bad(x: f64v2, y: f64v2): f64v2 { return x + y; }         -> returned Y UNCHANGED
#     fn bad(): f64v2 { var v: f64v2 = mkv(41,7); return load64(&v); }  -> lo right, hi stale
#     fn sc(): i64 { return 5; }  fn bad(): f64v2 { return sc(); }      -> garbage
#     fn mk4(): f64v4 { ... }     fn bad(): f64v2 { return mk4(); }     -> 32 B into a 16 B return
#     fn bad(): f64v2 { return (41, 7); }                         -> caller read 0 (X10-X12)
#
# TWO MORE SHAPES THE 6.6.6 RULE REFUSES, whose pre-6.6.6 behaviour is NOT uniformly wrong and
# so is written down here rather than in the defect list (both measured at the lane parent):
#   X13  `return callptr(fp, 41, 7);`  -> high lane 7 on x86_64 and 7 under qemu-aarch64, 5
#        under wine-PE (all three built from the 701fb02f tree, which predates the refusal).
#        Right on two targets, wrong on the third. `callptr` is a BUILTIN token, not an IDENT
#        naming a declared fn, so there is no declared return type for the exact-type test or
#        for the PE arm's `GFRS(callee) == _cur_fn_ret_scalar` to key on — exactly the asymmetry
#        noted below. Refused.
#   X14  `return G;` for a correctly-typed vector GLOBAL -> read a STALE REGISTER, not G, on
#        x86_64. With `var G: f64v2 = mkv(41,7); var H: f64v2 = mkv(3,4);` ahead of it the
#        caller got 3 — H's low lane, the last thing left in XMM0 — not G's 41. (`load64(&G)`
#        reads 0 at the parent too: the top-level initializer of a vector global never stores,
#        a separate pre-existing defect reported by bite 21's review, not fixed here.) The two
#        `return IDENT;` branches resolve the name with FINDLOCAL, so a global never matched
#        and fell straight through to the scalar path. Refused. 6.7.16 (the receives review): by the
#        vector global's own read refusal alone ("vector global 'G' is read and written through its
#        address"), the value's own error — the 6.6.6 refusal waits for the value to parse
#        (`_pair_ret_late`) and printed both through 6.7.15 (`r_msg`).
#
# ROOT CAUSE. PARSE_RETURN's `_is_simd128` / `_is_simd256` branches handle exactly
# `return IDENT;` for a local of the matching class and fall through to the scalar PCMPE path
# for everything else, so rax held whatever the expression left there and rdx was never written.
# The v6.4.31 `_TARGET_PE` arm covers only `return <simd_call>(..)`. This is the same shape as
# bite 16c's 9-16 byte struct pair, one type class over.
#
# ⚠ THREE SITES, AND ONLY ONE OF THEM IS THE PARSE_RETURN REFUSAL. Two earlier arms of
# PARSE_RETURN handle a `return` themselves and `return 0` out of the function, so the refusal
# ~330 lines down never sees them:
#   * the TAIL-CALL path takes `return f(args);` and a `jmp` hands the callee's return
#     convention straight back to OUR caller — rows X6 and X7. Mutant m3.
#   * the MULTI-RETURN path takes `return (a, b);` and hands the values back in the ret2/ret3
#     INT convention (rax:rdx[:r3]), which is not the vector ABI on any target — rows X10-X12,
#     added by bite 21's review, which found the first refusal shipped with this hole open.
#     Mutant m4. The PAIR class is untouched (rax:rdx IS its ABI) and so is the scalar
#     multi-return: rows A7 (pair, host + win64) and A8/A9 (scalar, all four legs) are exactly
#     those, and they must stay GREEN under m4 as well as on the real tree.
#
# ⚠ THE CALL FORM IS TESTED ON THE EXACT DECLARED TYPE while `return IDENT;` accepts any local
# of the same CLASS. Deliberate: the IDENT branches byte-copy 16/32 bytes (right whatever the
# lane type), but the PE arm keys on `GFRS(callee) == _cur_fn_ret_scalar`, so a same-class call
# of a different declared type would miss that arm and land on the generic path on Windows.
#
# LEGS: host x86_64 (refusals + acceptances), the tree's own cx compiler under cxvm, aarch64
# under qemu-aarch64 and Win64 PE under wine when installed. qemu and wine are EMULATION, NOT
# hardware — the ecb/ach/cass/pi legs of the release gate are what verify the real thing.
# Refusal is a compile-time property, so every compiler is asked; only acceptances need a runner.
#
# EXPECTED VALUES. Refusals are checked on the MESSAGE, not just a non-zero exit, so a row
# cannot pass on an unrelated syntax error. Acceptances check BOTH lanes of the vector, by two
# separate programs, so a path that carries only the low half (exactly what the defect did)
# fails — and the values are re-derived per leg by the same program built by that leg's compiler.
#
# MUTATION LEDGER (6.6.6 — each mutant is a scratch tree from `git archive HEAD` with the named
# hunk of src/frontend/parse_fn.cyr reverted, rebuilt with build/cycc, run as CYCC=<mutant>):
#   m1 all three sites reverted             -> RED, all 14 refusal rows (host)
#   m2 PARSE_RETURN refusal only reverted   -> RED, 11 rows: X1-X9 plus X13 and X14, which that
#                                              one refusal is the only site for; X10-X12 (the
#                                              tuple rows) stay green
#   m3 tail-call guard only reverted        -> RED, rows X6 and X7 only — the two CALL-form
#                                              rows, which the tail path takes before the
#                                              vector branch can see them
#   m4 multi-return guard only reverted     -> RED, rows X10, X11 and X12 only — the tuple
#                                              rows, which the multi-return arm takes before
#                                              the vector branch can see them. A7/A8/A9 stay
#                                              GREEN under m4, which is what proves the guard
#                                              is keyed on the vector classes and not on the
#                                              tuple syntax.
#   real tree                               -> GREEN (90 rows: 56 refusals, 34 acceptances —
#                                              14 refusal rows x 4 legs, 9 acceptance rows x 4
#                                              minus A7's two skipped legs, see a_legs —
#                                              across host + cx + qemu-aarch64 + wine-PE)
# Mutants were measured on a host-only copy of this file; the other legs share the frontend.
#
# ⛔ 6.7.11 (the call-arguments lane) — THE RECEIVE SIDE: a value-form vector LOCAL (`var v: T = <src>;`,
# `v = <src>;`). It got its 16 / 32 bytes only from `f(..)` by name: `callptr(&f, ..)`, `fncallN(&f,
# ..)` and `(f(..))` were stored as one word (wrong lanes on x86_64 / aarch64 / cx; on PE no hidden
# result pointer, so the callee wrote through its first argument), and so was every source that is no
# vector — a callee held in a variable (`callptr(fp, ..)`: 181 / 180 / 45 where 48 is right, a page
# fault at 0x29 on PE), `5`, `load64(..)`, `&w`. The receive now takes every source that IS the vector
# — a local of its type, a by-name call declared to return it, inside parentheses too, and
# `fncallN(&f, ..)` / `callptr(&f, ..)` with `f` declared to return it — and refuses every other one by
# name, at the declaration and the assignment (the user's decision, 2026-10-13: the 6.6.6 return
# rule's sources, at the receive). Rows V (accepted, each lane read back through a value-form
# parameter; f64v2 / f32v4 / i32v4 / f64v4, declaration and assignment, and the guide's out-pointer
# workaround) and Y (refused once, by name, no artifact — Y1 is the filed repro verbatim) on all four
# legs; tests/tcyr/crossos/simd_indirect_receive.tcyr is the same table for the release gate's hosts.
# 6.7.13 (issues/archived/2026-10-14-parenthesised-fn-pointer-callee-loses-struct-result.md): V10 — the callee in parentheses,
# `callptr((&mk2), 4, 1)`, is the known callee (`_icall_fti`): it was refused as a callee in a variable is.
# MUTATION LEDGER (6.7.11 — a scratch copy of the tree, the one change, rebuilt, run as CYCC=<mutant>):
#   MV1 `_vrcv_decl` never declaring                       -> RED V1 V3 V5 V7 on all four legs (refused: the declaration
#                                                          fell to the scalar path)
#   MV2 `_vrcv_asg` always deferring (-1)                  -> RED Y5-Y8 Y11 (not refused) and V2 V4 V6 V8 (1; PE 5)
#                                                          on all four legs
#   MV3 `_var_rhs_post` without `_vrcv_decl_err`           -> RED Y1-Y4 Y9 Y10 (not refused) on all four legs
#   MV4 `_icall_sret` without its `_icall_vbeg` arm (PE)   -> RED win64 V1-V8 only (5: the callee wrote through its
#                                                          first argument) — the hidden pointer is PE's alone
#   MV5 `_vrcv_emit` without the register-pair store       -> RED V1-V8 on host / cx / aarch64 (1); win64 green (no pair)
# 6.7.12 (issues/archived/2026-10-14-6711-rows-not-run-on-hardware.md item 4): A7 runs on ecb / ach / cass / pi in
# tests/tcyr/crossos/struct_return_shape_controls.tcyr (6.7.13: its producer says `return p;`, as here).
#
# ⛔ 6.7.13 (the vectors lane, issues/archived/2026-10-14-explicit-instance-vector-result-not-received.md) — AN
# EXPLICIT-INSTANCE GENERIC CALL `mkg<i64>(41, 7)` IS A BY-NAME CALL DECLARED TO RETURN ITS VECTOR. Every receive tested `IDENT (`: the
# assignment `v = mkg<i64>(41, 7);` was refused (".. got `mkg`"), the declaration `var v: f64v2 = mkg<i64>(..)` lost its
# annotation (PARSE_VAR's struct lookahead reset it: `_gen_decl_check` answered 0 for a vector), so the local was one
# word — `lanes(v)` refused "value-form SIMD arg must be a 16-byte vector" (PE: exit 5), `load64(&v + 8)` read garbage
# silently (x86_64 / IR=3 / aarch64 0, cx 154, PE 195; 161 is right) — and `return mkg<i64>(a, b)` from a `: f64v2` fn
# was refused. One recogniser (`_vcall_fi`: `_gcall_open` + `_gen_resolve_call`) now serves the receives, the
# declared-type check, the return rule, PE's own call (`_vcall_enter`) and D27's `*V` argument (`_svc_rs`); a vector
# annotation is never reset. Rows E (accepted; x86_64 / IR=3 / cx / aarch64 / PE) and Z (refused once, by name):
#   E1 the filed repro verbatim (161)   E2 the declaration with lanes(v)   E3 the declaration read through load64(&v)
#   (the silent one)   E4 `return mkg<i64>(a, b)`   E5 the inferred `mkg(41, 7)` (the control, always 161)   E6 the
#   unannotated `var v = mkg<i64>(..)` (inferred, as `var v = mkv(..)` is)   E7 `rd(mkg<i64>(42, 7))` into `*f64v2`
#   (42: D27's call result; row 7 of 2026-10-15-vector-value-into-other-pointer-or-byvalue-struct-and-unreceived-call-
#   sources.md)   E8 a real instance `mkg<i32>` and a struct type argument `mkp<Pt>`, declaration and assignment
#   E9 wrapped `(mkg<i64>(..))`, declaration and assignment
#   Z1 `var v: f64v4 = mkg<i64>(..)` (an f64v2 call) "vector return type does not match the declared type" (compiled
#   before: the annotation dropped)   Z2 `w = mkg<i64>(..)` into an f64v4 ".. the assigned variable"
#   Z3 `x = mkg<i64>(..)` into a scalar local, as `x = mkv(..)` is (compiled before: exit 0)   Z4 `var x: i64 =
#   mkg<i64>(..)` (compiled before)
#   Z5 `var v: f64v2 = idg<i64>(5)`, a scalar-returning generic: the vector local's own refusal (compiled before: the
#   annotation reset)   Z6 `return mkg<i64>(a, b)` from a `: f64v4` fn (the return rule's)
# MUTATION LEDGER (6.7.13 — a scratch copy of the tree, the one change, rebuilt, run as CYCC=<mutant>; measured):
#   ME1 `_vcall_fi` taking `IDENT (` only (`o != ti + 1` -> -1) -> RED 56: E1-E4 E6-E9 on all five legs (refused, or
#       the one-word local: E6 0 / cx 154 / PE 195, E7 139 / cx 0 / PE 5), Z1-Z4 on all four (another refusal, or
#       compiled); E5 (the inferred `IDENT (`) and Z5 Z6 green
#   ME2 `_gen_decl_check` without its vector guard          -> RED 4: Z5 on all four legs (compiled); the E rows green
#       (the receive takes them before the reset)
#   ME3 `_vrcv_decl` deferring an explicit instance (no `_vrcv_g` arm) -> RED 20: E2 E3 E6 E8 on all five legs (0;
#       cx 154 / 88, PE 195 / 244: the scalar init); E1 (`_try_vector_call_assign` takes the assignment) and E9 (a
#       wrap) green
#   ME4 `_vcall_enter` stepping two tokens (`IDENT (` only) -> RED 8: win64 E1-E4 E6-E9 ("undefined variable 'i64'":
#       the type argument parsed as the first argument) — PE's own call alone
#
# ⛔ 6.7.13 (the vectors lane, D29 A — the user's decision, 2026-10-15; issues/2026-10-13-vector-call-results-the-receives-
# do-not-take.md) — THREE CALLS DECLARED TO RETURN THE VECTOR THAT THE RECEIVES AND THE RETURN STILL REFUSED: a method
# `var v: f64v2 = s.mv();` ("a value-form vector local is initialised only from .. got `s`" on all five legs; before 6.7.11
# it read wrong lanes: 1 / 1 / cx 155 / PE 41), an unannotated `var v = callptr(&mkv, 41, 7);` (one word: `lanes(v)` refused
# "value-form SIMD arg must be a 16-byte vector" on x86_64 / IR=3 / aarch64 / cx, PE exit 5 — lane 0 taken as the vector's
# address) and `return callptr(&mkv, a, b);` from a `: f64v2` fn (refused ".. got `this expression`"). Each is taken now:
# the method by the receive (`_vmc_fi`; on PE its hidden result pointer is the local's address, `_sc_vbeg`), the untyped
# declaration as the callee's vector (`_vrcv_ity`), the return by the rule (`_ret_vicall`; PE `_ret_vicall_pe`). Rows C
# (accepted, 161 on x86_64 / IR=3 / cx / aarch64 / PE): C1-C3 the three filed repros verbatim, C4 the method assignment
# with `s` intact afterwards (PE: the pointer goes before `self`), C5 `return fncall2(&mkv, a, b)` in a tail position.
# Rows Q (refused once): Q1 `var v: f64v4 = s.mv()` (an f64v2 method) "vector return type does not match the declared
# type", Q2 `w = s.mv()` into an f64v4 ".. the assigned variable", Q3 an unannotated `var v = callptr(fp, ..)` through a
# variable stays a word (D32): `lanes(v)` refused "value-form SIMD arg must be a 16-byte vector", Q4 `return callptr(&mk4,
# ..)` (an f64v4 callee) from a `: f64v2` fn — the return rule's refusal.
# MUTATION LEDGER (6.7.13 D29 — a scratch copy of the tree, the one change, rebuilt, run as CYCC=<mutant>; measured):
#   MC1 `_vrcv_src` without the method arm      -> RED 10: C1 C4 on all five legs (refused 'got `s`'); Q1 Q2 green (the
#       method's own mismatch refusal stands)
#   MC2 `_vrcv_decl` without the untyped inference -> RED 5: C2 on all five legs (refused; PE 5)
#   MC3 `_simd_ret_call_ok` without `_ret_vicall` -> RED 10: C3 C5 on all five legs (refused)
#   MC4 `_sc_pre` without its `_sc_vbeg` arm      -> RED 2: win64 C1 C4 = 0 (the method wrote a temp; the local never set)
#   MC5 `_ret_vicall_pe` answering 0             -> RED 2: win64 C3 C5 = 0 (the generic path passes no hidden pointer)
# 6.7.14 (issues/archived/2026-10-16-indirect-call-of-another-vector-into-vector-local-generic-words.md) — `callptr(&f, ..)` /
# `fncallN(&f, ..)` with `f` declared to return ANOTHER vector, into a vector local, is refused in the by-name call's
# words, as Q1 / Q2's method is (`_vrcv_ibad`): it was the receive's generic refusal ("a value-form vector local is
# initialised only from .. (by name, a method, or fncallN / callptr with the callee written `&f`) .. - got `callptr`"),
# whose own list names the shape written. Rows Q, once, on all four legs: Q5 the filed repro verbatim, Q6 its `v = ..`
# twin, Q7 / Q8 `fncall1(&mk4, ..)` declared / assigned, Q9 / Q10 wrapped (`(callptr(&mk4, 41))`, `((fncall1((&mk4),
# 41)))`), Q11 / Q12 the same 16-byte class of another type (an f64v2 callee into `f32v4`) and a 16-byte callee into an
# f64v4 — "vector return type does not match the declared type" / ".. the assigned variable".
#   M-Q1 `_vrcv_ibad` answering 0 (measured)     -> RED 32: Q5-Q12 on all four legs (the generic line, `got `callptr``)
# 6.7.14 (issues/archived/2026-10-16-vector-local-assignment-from-undefined-call-warns-typed-pointer.md) — THE ASSIGNMENT'S
# TYPED-POINTER WARNING SKIPS A VALUE-FORM VECTOR LOCAL (its SLTYPE a descriptor, <= -2048, never `0 - sid`): `v =
# f64v2_splat(1.0);` (the fn undefined) warned "assigning non-pointer to typed pointer" ahead of the undefined-function
# lines, and `v = mk4(41)` of another vector beside its refusal. H9 (the filed repro verbatim) and every undef H row now
# assert no such warning, Q13 the by-name mismatch, and every Q row; TP is the control: `p = 5;` into a `*Pt` local and
# `q = 7;` into a `*i64` one still warn (twice), on all four legs.
#   M-T1 the parse.cyr guard reverted (measured) -> RED 8: H9 Q13 on all four legs; TP green
# 6.7.15 (issues/archived/2026-10-17-wrapped-by-name-or-method-call-of-another-vector-into-vector-local-generic-words.md) — a
# by-name call (an explicit instance too) or a method (a field chain's too) of ANOTHER vector INSIDE PARENTHESES, into a
# vector local, is refused in the by-name call's words, as unwrapped: one mismatch check for every spelling (`_vrcv_bad`
# over `_vcall_vt`, which folds 6.7.13's `_vrcv_mbad` and 6.7.14's `_vrcv_ibad`). It was the receive's generic line,
# "got `(...)`", on all four legs. Rows Q14-Q17 the filed repro's four sources one at a time, Q18 a for step's double
# wrap, Q19 a double-wrapped `mkg<i64>(..)`, Q20 a wrapped chained method; QF the filed repro verbatim (its four lines,
# in order). Mutations (2026-10-18, measured):
#   M-W1 `_vcall_vt` answering 0 for a wrapped by-name call / method -> RED 32: Q14-Q20 QF on all four legs; Q9 Q10
#       (wrapped `callptr` / `fncallN`) green
#   M-W2 `_vrcv_bad` never refusing                      -> RED 82: Q1 Q2 Q5-Q12 Q14-Q20 QF on all four legs, CRK3 CRK4
#       on all five (the generic line)
# Q3 runs on win64 too since D30 (simd_pointer_param.sh's VZ4: a word into Win64's value-form parameter is refused);
# M-VC3 there (`_sarg_pe_vword` answering 0) -> RED win64 Q3 here; 6.7.14: M-PV1 / M-PV2 there (`_sarg_pe_vform`, which
# folds it) -> RED win64 Q3 here.
#
# ⛔ 6.7.13 (D34 A, the user's decision, 2026-10-15; issues/archived/2026-10-13-vector-dereference-into-vector-local-decision.md) —
# `var v: V = *p;` / `v = *p;` WITH `p: *V` COPY THE VECTOR THROUGH THE POINTER, as `var q: T = *p;` copies a struct
# (6.7.10 decision 6): `_vrcv_src` kind 4 (`_vrcv_dsrc`: a whole `* E`, any wrap), `_vrcv_demit` (E parsed, its step
# word's vector read: `ty`'s copied through a hidden temp; another vector refused by name; an untyped word keeps the
# receive refusal). Refused since 6.7.11 ("got `*p`"); through 6.7.10 one word, the high lanes stale (x86_64 210, aarch64
# 74, cx 98, PE 146). Rows P (accepted, 161 on x86_64 / IR=3 / cx / aarch64 / PE): P1 the filed repro verbatim, P2 its
# `v = *p;` twin, P3 `(*p)` declared and assigned from a `p: *f64v2` parameter, P4 an f64v4 (lanes 0 and 3), P5 `**pp` of
# a `**f64v2` in a for step. Rows K (refused once, on host / cx / aarch64 / PE): K1 `var v: f64v2 = *q;` with `q: *i32v4`
# (the same size) and K2 `v = *q;` with `q: *f64v4` — "cannot copy 'q' into a variable of a different struct/vector
# type: 'v'", the words a local of another type meets; K3 / K4 an untyped `*x` (declared, assigned) — the receive
# refusal, as before.
#   M-D1 `_vrcv_dsrc` answering 0 (2026-10-16, measured)    -> RED 33: P1-P5 on all five legs (refused, the 6.7.11
#       words), K1 K2 on all four (the receive refusal, not the copy's words)
#   M-D2 `_vrcv_demit` without the vector-type test          -> RED 8: K1 K2 on all four legs (compiled)
#
# ⛔ 6.7.13 (issues/archived/2026-10-14-vector-local-refusal-hint-every-source.md) — THE RECEIVE'S REFUSAL NAMES WHAT IT REFUSES. Since
# 6.7.11 every refusal ended "; through a fn pointer held in a variable, give the target an out-pointer" (`= 5`,
# `= load64(&w)`, `= &w`), and a call to a fn that does not exist (`var v: f64v2 = f64v2_splat(1.0);`, no include) was
# reported as a refused source ahead of the undefined-function warnings. The hint now follows a whole fncallN / callptr
# call whose callee is not written `&f` (`_vrcv_fptr`), a call naming no fn is the undefined-function path's alone
# (`_vrcv_nofn`), and the accepted list names `*p` (D34). Rows H on all four legs, one `error` line each, no artifact:
#   H1 the filed c8 verbatim (`= 5`), H2 `= load64(&w)`, H3 `= &w`, H6 `v = load64(&w)`, H8 `callptr(&sc, ..)` (the
#   callee written `&f`, a word), H10 an untyped `*x` — refused without the hint; H4 `callptr(fp, 41, 7)`, H7 `v =
#   fncall2(fp, 41, 7)`, H11 `(callptr(fp, 41, 7))` — refused with it; every one names its source and the dereference
#   in the list; H5 the filed d7 verbatim and H9 its `v = ..` twin — the undefined-function warning and the
#   refusing-to-emit line, no receive line.
# MUTATION LEDGER (6.7.13, measured — a scratch copy of the tree, the one change, rebuilt, run as CYCC=<mutant>):
#   the lane's previous compiler (the hint everywhere, the old list) -> RED 44: H1-H11 on all four legs
#   M-H1 `_vrcv_fptr` answering 1                  -> RED 20: H1 H2 H3 H6 H8 on all four legs (the hint printed);
#       H10 green (the dereference's refusal passes no hint)
#   M-H2 `_vrcv_nofn` answering 0                  -> RED 8: H5 H9 on all four legs (the receive line, two errors)
#   M-H3 `_vrcv_fptr` without its `&f` test         -> RED 4: H8 on all four legs
#   M-H4 `_vrcv_nofn` taking FINDFN < 0 only        -> RED 4: H5 on all four legs (the declaration asks after the
#       parse, which registered the name: only the definition stamp `GFDS` tells it from a declared fn)
# 6.7.14 (issues/archived/2026-10-16-other-vector-refusals-report-undefined-call-as-refused-source.md) — A CALL NAMING NO FN IS THE
# UNDEFINED-FUNCTION PATH'S AT THE OTHER VECTOR DESTINATIONS TOO, inside parentheses as well (`_vrcv_nofnw`): the wrapped
# local source `var v: f64v2 = (f64v2_splat(1.0));` printed "got `(...)`" and `return f64v2_splat(1.0);` from a vector fn
# "got `f64v2_splat`" (the 6.6.6 rule), each ahead of the undefined-function warnings, on all four legs. Rows H (undef):
#   H12 the filed wrapped local verbatim, H13 its `v = (..)` twin, H14 `return f64v2_splat(1.0);` from a vector fn the
#   program calls (the tail arm diverts it to the rule), H15 `return (f64v2_splat(1.0));` — the undefined-function lines
#   alone; H16 the filed return repro verbatim (its fn never called: x86_64 / aarch64 / PE build it with the warning
#   alone, as the unwrapped local, cx refuses an unresolved call) — no vector-return line, the warning, on every leg.
#   (The value-form argument's half: simd_pointer_param.sh, rows VU.)
#   M-U1 `_vrcv_nofnw` answering 0 (measured)       -> RED 24: H5 H12-H16 on all four legs (the refusal's line came
#       back; H5 too: the declaration asks `_vrcv_nofnw` now)
#   M-U2 `_ret_vec_rule` without its `_vrcv_nofnw` test (measured) -> RED 12: H14-H16 on all four legs
#
# ⛔ 6.7.14 (D43, the user's decision, 2026-10-16; issues/archived/2026-10-15-ret2-in-vector-returning-fn-compiles.md) — `ret2(a, b)`
# AS A STATEMENT IN A VECTOR-RETURNING FN IS REFUSED by the 6.6.6 rule's text, as `return (a, b);` (X10) and
# `return ret2(..);` there are: it loaded rax:rdx where the caller reads the vector registers (Win64: the result
# pointer), so the caller's vector held their leftovers — 0 on x86_64 / aarch64 / PE, 41 on cx, where {41, 7} is
# right. `_ret2_in_vector` (beside D22's `_ret2_in_struct`), at the ret2, once, in sync, named "got `ret2`". Rows T
# (refused once, the message naming `ret2`, no artifact; every leg): T1 the filed repro verbatim (f64v2), T2 f64v4,
# T3 f32v4, T4 i32v4, T5 a generic's two instances (once), T6 a ret2 on one path only, T7 a `return ret2(..);` (the
# return's own refusal, once: "got `this expression`"). Rows U (run, 83, every leg): U1 a closure's own ret2 inside a
# vector fn, U2 an #inline fn's ret2 replayed there — each that fn's, as D22's carve-out.
#   M-R1 the tree before (b773a56a)                   -> RED 24: T1-T6 on all four legs (built)
#   M-R2 `_ret2_in_vector` without its GIDEP guard     -> RED 4: U2 on all four legs (refused)
#   M-R3 `_ret2_in_vector` without its `return` test    -> RED 4: T7 on all four legs (two error lines)
#   M-R4 `_ret2_in_vector` without its `_tn_once`       -> RED 4: T5 on all four legs (two error lines)
#
# 6.7.14 (D35 A / D36 A, the user's decisions, 2026-10-16; issues/2026-10-16-vector-dereference-return-and-untyped-
# destinations.md) — `return *p;` from a `: V` fn with `p: *V` copies the vector through the pointer (`_ret_vderef`:
# refused "got `this expression`" on every leg before), and an untyped `var v = *p;` declares a V local copied through
# it (`_dvi_arm` / `_dvi_park` / `_dvi_take`: one word before — x86_64 114, IR=3 226, aarch64 26, cx 98, PE 146 where
# 161 is right). Rows D (run, 161, on host / host IR=3 / cx / aarch64 / win64): D1 / D2 the filed repros verbatim,
# D3-D6 the return wrapped, `**pp`, `*gp(p)`, `*h.pv`, `*&w`, f64v4, f32v4, D7 / D8 the untyped declaration wrapped,
# through `**pp`, `*gp(p)`, `*h.pv`, f64v4, f32v4, a copy, D9 it is the vector (a value-form argument), D10 a `*i64`'s
# `*pi` stays a word. Rows DK (refused once, the 6.6.6 words, no artifact, four legs): a `*f32v4` / `*f64v4` into an
# f64v2 fn's return, a `*i64`'s, wrapped. Mutations (2026-10-17, a scratch copy, its 2-stage mutant; measured):
#   M-D1 `_simd_ret_call_ok` without its `* E` arm      -> RED 40: D1 D3-D6 on all five legs (refused), DK1-DK4 on
#       four (two error lines)
#   M-D2 `_dvi_park` never parking                     -> RED 20: D2 D7 D8 D9 on all five legs (one word)
#   M-D3 `_ret_vderef` without its type check          -> RED 16: DK1-DK4 on all four legs (compiled)
#
# 6.7.14 (D37 A / D38 A / D39 A, the user's decisions, 2026-10-16; issues/2026-10-16-vector-method-result-untyped-scalar-
# and-return-destinations.md) — a method declared `: V` is the vector where a by-name call declared `: V` is: an untyped
# `var v = s.mv();` is a V local (`_vrcv_ity` -> `_vmc_whole`; one word before: x86_64 / IR=3 / aarch64 1, cx 155, PE
# 195), `var x: i64 = s.mv();` / `x = s.mv();` are refused in the by-name call's words (`_vrcv_mscal`, `_vasg_mscal`;
# they stored 0 / 41), and `return s.mv();` from a `: V` fn is taken (`_ret_vmc`; Win64 `_ret_vmc_pe` through the
# method arm's hidden-pointer hook; refused "got `s`" before). Rows M (run, 161, host / host IR=3 / cx / aarch64 /
# win64): M1 / M2 the filed repros 1 and 3 verbatim, M3 untyped f32v4 / f64v4 / generic / `*Mv` receiver (self intact),
# M4 the return from f64v2 / f32v4 / f64v4 fns, a generic method's, a local receiver's, M5 a scalar method unchanged.
# Rows MK (refused once, four legs): MK1 the filed repro 2 verbatim, MK2 `x = s.m2(1)`, MK3 a for step, MK4 a struct
# annotation, MK5 `: f64`, MK6 / MK7 a method of another vector returned ("got `s`"). Mutations (2026-10-17, measured):
#   M-M1 `_vrcv_ity` without its method arm            -> RED 10: M1 M3 on all five legs (one word / refused as a word)
#   M-M2 `_vrcv_mscal` never refusing                  -> RED 12: MK1 MK4 MK5 on four legs (compiled)
#   M-M3 `_vasg_mscal` never refusing                  -> RED 8: MK2 MK3 on four legs (compiled)
#   M-M4 `_simd_ret_call_ok` without `_ret_vmc`        -> RED 10: M2 M4 on all five legs (refused)
#   M-M5 `_ret_vmc_pe` never taking it (Win64)         -> RED 2: M2 M4 win64 (0 / 1: the scalar path's word)
#
# 6.7.15 (issues/archived/2026-10-17-chained-receiver-vector-method-binds-a-word-annotated-refused.md) — a method declared `: V` on a
# FIELD-CHAIN receiver (`w.s.mv()`, `pw.s.mv()`, `h.w.s.mv()`, `n.ps.mv()`) is the vector where a single name's is: one
# recogniser (`_vmc_open` -> `_mch_open`, parse_decl.cyr) serves the receives, D37's untyped declaration, D38's scalar
# refusals, the value-form and `*V` arguments (`_svc_rs`) and D39's return. Before: the untyped declaration bound one word
# (x86_64 104, IR=3 40, aarch64 144, cx 98, PE 195 — garbage, per build), the annotated declaration, the assignment, the
# value-form argument and the return were refused "got `w`", `rd(w.s.mv())` into a `*f64v2` pushed lane 0 as the address
# (139; cx 201, PE 5), `var x: i64 = w.s.mv();` / `x = w.s.mv();` stored a word (0; cx / PE 41). Rows CR (run, 161, host /
# host IR=3 / cx / aarch64 / win64) and CRK (refused once, the same five legs). Mutations (2026-10-18, measured):
#   M-CR1 `_vmc_open` without its chain arm            -> RED 60: CR1-CR7 and CRK1-CRK5 on all five legs; CRK6 green (the
#       return rule names `w` either way)
#   M-CR2 `_svc_rs` naming token ti + 2                 -> RED 5: CRK5 on all five legs ("cannot pass 's'")
# 6.7.16 (issues/archived/2026-10-18-vector-method-on-dereference-or-call-head-receiver-binds-a-word.md) — and on EVERY OTHER
# RECEIVER the method arm takes: a parenthesised head (`(*ps).mv()`, `((*ps)).mv()`, `(*pw).s.mv()`, `(s).mv()`,
# `(ps).mv()`, `(w.s).mv()`, `(gw(&w)).s.mv()`, `(mks(3)).mv()`, `(*q.ps).mv()`, `(ps + 0).mv()`), a call's result
# (`gw(&w).s.mv()`, `gs(&s).mv()`, `mks(3).mv()`, `gwg<W>(&w).s.mv()`, `callptr(&gw, &w).s.mv()`, `fncall1(&gs, ps).mv()`)
# and a method's result mid-chain (`o.gp(&w).s.mv()`, `o.me(&s).mv()`): `_mch_open`'s head (`_mch_head`: a name, a call,
# `( E )`) and steps (`_mch_walk`: fields and methods), `_vrcv_src` taking a `(` that wraps no whole source as no wrap,
# and the argument paths' `_vmc_phead`. Before (the filing, re-measured at 41ca7d41c): `var v = (*ps).mv();` bound one
# word of stack garbage (x86_64 96, IR=3 112, aarch64 168, cx 106, PE 195 where 161 is right; rows 2 / 3 likewise),
# `var x: i64 = (*ps).mv();` stored a word (0; cx / PE 41), `var v: f64v2 = (*ps).mv();` was refused "got `(...)`".
# Rows CR8-CR17 (run, 161; CR8-CR11 the filed rows 1-3 and 5 verbatim) and CRK7-CRK16 (refused once; CRK7 the filed row
# 4 verbatim) on host / host IR=3 / cx / aarch64 / win64. Mutations (2026-10-20, measured):
#   M-CR3 `_mch_head` reading a name head only            -> RED 90: CR8-CR17 and CRK7-CRK11 CRK13-CRK15 on all five
#       legs; CRK12 (a name head) and CRK16 (the return rule names `(...)` either way) green
#   M-CR4 `_vmc_open` without the chain's last method     -> RED 10: CR16 and CRK12 (`o.gp(&w).s.mv()`) on five legs
#   M-CR5 `_vrcv_src` reading a leading `(` as a wrap     -> RED 35: CR8 CR9 CR11 CR12 CR13 CR15 CR17 on five legs
#   M-CR6 `_vmc_phead` answering -1                       -> RED 25: CR12 CR13 CR15 CR17 (a value-form / `*f64v2`
#       argument) and CRK11 on five legs
# 6.7.15 (issues/archived/2026-10-17-by-name-vector-call-into-f64-declaration-stores-a-word.md) — a by-name call declared `: V` into
# a declaration annotated with a type of no integer width (`: f64`, `: f32`, `: bool`, `: cstring`, an enum, `: Vec`,
# `: Result`, `: Option`) is refused "vector return type does not match the declared type", as the method is since
# 6.7.14's D38: PARSE_VAR inferred the callee's vector whenever the annotation had no width, so `x` was a two-slot
# vector local labelled f64 (the filed repro exit 3, `load64(&x + 8)` 7, on all five legs). It infers only when there
# is no annotation. Rows NK (refused once, host / host IR=3 / cx / aarch64 / win64), N1 the control (161). Mutation
# (2026-10-18, measured):
#   M-N1 the inference on any width-0 annotation (the tree before) -> RED 45: NK1-NK6 and NK12-NK14 on all five legs;
#       NK7-NK11 (the method) and N1 green (re-measured with NK12-NK14 at the review fix)
# 6.7.15 (D28 A / D29 A, the user's decisions, 2026-10-18; issues/2026-10-17-wrapped-vector-call-into-untyped-or-scalar-
# declaration-binds-a-word.md) — parentheses around a WHOLE vector call are transparent at an untyped declaration and at
# an integer destination, and a method (an indirect `callptr(&f, ..)` too) that STARTS an integer initialiser is refused,
# as the by-name call is: `_vrcv_ity`, `_vrcv_mscal` and `_vasg_mscal` read `_vcall_vt` (every spelling, wrapped or not;
# the declaration with `start` 1). Before: `var x = (mk2(41, 7));` bound one word (x86_64 / IR=3 / aarch64 0, cx 154, PE
# 195), `var x = (s.m2());` 1 / cx 155 / PE 195, `var x: i64 = (mk2(..));` / `= (s.m2());` / `x = (mk2(1, 2));` / `x =
# (s.m2());` stored a word (0; cx / PE 41 or 1), `var x: i64 = s.m2() + 1;` 1 (cx / PE 42). Rows WR (run, 161) and WRK
# (refused once) on host / host IR=3 / cx / aarch64 / win64. Mutations (2026-10-18, measured):
#   M-WR1 `_vrcv_ity` without the wrap (the tree before)    -> RED 30: WR1-WR6 on all five legs (one word, or "value-form
#       SIMD arg must be a 16-byte vector")
#   M-WR2 `_vrcv_mscal` asking a whole call (`start` 0)    -> RED 20: WRK3 WRK7 WRK9 WRK11 on all five legs (compiled)
#   M-WR3 `_vasg_mscal` asking a whole method (the tree before) -> RED 15: WRK4-WRK6 on all five legs (compiled)
#   M-WR4 `_vrcv_mscal` asking a whole method (the tree before) -> RED 40: WRK1-WRK3 WRK7-WRK11 on all five legs
# 6.7.16 (D25 A / D26 A, the user's decisions, 2026-10-19; issues/2026-10-18-vector-call-starting-assignment-or-wrapped-
# start-stores-a-word.md) — a method or `callptr(&f, ..)` that STARTS an assignment's right-hand side is refused as the
# by-name call is (`_vasg_vt` reads `_vcall_vt` with `start` 1, as the declaration's `_vrcv_mscal` does), and parentheses
# change nothing for a call that starts an integer source: `(mk2(41, 7)) + 1` (`_vcv_wpeel`), `(mk2(41, 7) + 1)` (a call
# starting a whole wrap's inside). Before (re-measured at 41ca7d41c + the method-head bite): `x = s.m2() + 1;`, `x =
# callptr(&mk2, 41, 7) + 1;`, `var x: i64 = (mk2(41, 7)) + 1;`, `x = (mk2(41, 7)) + 1;`, `var x: i64 = (s.m2()) + 1;`
# stored the result's word plus 1 (x86_64 / IR=3 / aarch64 1, cx / PE 42). Rows WRK12-WRK16 (the filed rows 1-5
# verbatim), WRK17-WRK21 (f64v4 twins), WRK22 (a for step), WRK23 / WRK24 (a global in a fn, at top level), WRK25 /
# WRK26 (a top-level `: i64` in the declaration zone, after the first statement), WRK27 (a call starting a whole wrap),
# WRK28-WRK31 (a double wrap, a parenthesised head, a chain, `(callptr(&f))`), refused once; WR7 the controls (`var w =
# (mk2(41, 7));` 161, `x = load64(&w) + 1;` 42). Five legs. Mutations (2026-10-20, measured):
#   M-WR5 `_vasg_vt` asking a whole call (`start` 0, the tree before) -> RED 65: WRK12 WRK13 WRK15 WRK17 WRK18 WRK20
#       WRK22-WRK24 WRK28-WRK31 on five legs
#   M-WR6 `_vcv_wpeel` peeling nothing                  -> RED 65: WRK14-WRK16 WRK19-WRK22 WRK25 WRK26 WRK28-WRK31 on five
#   M-WR7 `start` 1 taking only an unwrapped start (the tree before) -> RED 5: WRK27 on five legs
# 6.7.16 (the receives review) — and behind leading parentheses that close AFTER an operator: `_vcv_wpeel` peeled only
# parentheses whose innermost `)` closed right after the call, so `var x: i64 = (mk2(41, 7) + 1) * 2;` and `x = (mk2(41,
# 7) + 1) * 2;` stored the result's word (x86_64 / IR=3 / aarch64 2, cx 84), `var x: i64 = (s.m2() * 2) + 1;` 1 (cx 83),
# and the untyped / top-level `var w = (mk2(41, 7) + 1) * 2;` compiled the same way. Now a call at any depth of leading
# parentheses starts the source. Rows WRK32-WRK41 (a declaration, an assignment, a method, a parenthesised head, the
# zone, after the first statement, an f64v4 twin, a global in a fn, `callptr(&f)`, a top-level assignment) and OP22-OP25
# (untyped, in a fn and at top level), refused once on five legs. Mutation (2026-10-20, measured):
#   M-WR8 `_vcv_wpeel` back to the innermost-`)` peel (the tree before) -> RED 70: WRK32-WRK41 OP22-OP25 on five legs

# 6.7.15 (issues/archived/2026-10-17-vector-call-or-method-assigned-to-scalar-global-stores-a-word.md) — a vector call assigned to a
# GLOBAL that is no vector (by name, an explicit instance, a method incl. a chain's, `fncallN(&f, ..)` / `callptr(&f, ..)`,
# wrapped or not; a by-name call starting the source, as the local's arm reads it), and `fncallN(&f, ..)` /
# `callptr(&f, ..)` into a scalar local or declaration, is refused "vector return type does not match the assigned
# variable / the declared type", as `x = mkv(..);` into a local is (`_vasg_mscal`: `_vasg_gnv`, `_vasg_vt`). Before: one
# word stored (x86_64 / IR=3 / aarch64 0, cx / PE 41; row 4 0 / cx / PE 82). A vector global keeps its own refusal
# (`_vecg_refuse`, GV1). Rows GA / GV (refused once), GAF (the filed row 4 verbatim, two lines), GC (the control, 161) on
# host / host IR=3 / cx / aarch64 / win64. Mutations (2026-10-18, measured):
#   M-GA1 `_vasg_mscal` judging no global           -> RED 60: GA1-GA3 GA6-GA14 on all five legs (compiled)
#   M-GA2 `_try_vector_call_assign`'s old order (a local's `IDENT (` that is no vector call left) -> RED 9: GA4 on five
#       legs, GAF on four (`x = fncall2(&mkv, ..)` compiled)
#   M-GA3 `_vasg_vt` without the by-name start      -> RED 5: GA11 on all five legs
#   M-GA4 `_vasg_gnv` judging a vector global too   -> RED 5: GV1 on all five legs (the mismatch's words, not the vector
#       global's)
# 6.7.16 (issues/archived/2026-10-18-top-level-assignment-of-vector-call-to-scalar-global-stores-a-word.md) — and ASSIGNED AT TOP
# LEVEL to a global that is no vector: `G = mkv(41, 7);` / `G = s.mv();` after the first statement (or as it, or in a
# top-level for step) compiled with no diagnostic and stored one word (x86_64 / IR=3 / aarch64 0, cx / PE 41), where
# the same assignment in a fn is refused (rows GA) — `_try_vector_call_assign` returned before any check outside a fn.
# Now `_vasg_gtop` (the global arm of `_vasg_mscal`, no local table at top level) refuses it with the in-fn words; a
# vector global keeps its own refusal (GTV1). Rows GT (refused once) and GC2 (the top-level scalar control: an
# assignment, a for step, a method, 161) on host / host IR=3 / cx / aarch64 / win64. Mutation (2026-10-20, measured):
#   M-GT1 `_try_vector_call_assign` returning 0 outside a fn (the tree before) -> RED 45: GT1-GT9 on all five legs
#       (compiled); GTV1 and GC2 green
# 6.7.15 (D26 A / D27 A, the user's decisions, 2026-10-18; issues/2026-10-17-top-level-untyped-vector-call-or-method-
# result-binds-a-word.md) — a call declared to return a vector into a TOP-LEVEL declaration is refused: untyped (whole,
# any spelling, any wrap) "'mkv' returns a vector by value, and a vector result needs storage in a fn's frame - call it
# inside a fn" (the words of a top-level vector call into a `*V` parameter), annotated with no vector "vector return type
# does not match the declared type", as the line is in a fn; a vector annotation keeps the vector global's own refusal.
# PARSE_VAR's global arm (`_vin_decl` -> `_vin_top`) after the first statement, the replay (`_bx_gvi_expr` ->
# `_vin_zone`) in the declaration zone, one judgment (`_vtop_ref` over `_vcall_vt`). Before: one word (x86_64 / IR=3 /
# aarch64 0, cx 154, PE 195 in the zone / 154 after the first statement; `: i64` 0 / cx / PE 41). Rows TL (refused once)
# on host / host IR=3 / cx / aarch64 / win64; the controls in tests/tcyr/crossos/vector_global_storage.tcyr. Mutations
# (2026-10-18, measured):
#   M-TL1 `_vin_decl` without the top-level arm      -> RED 30: TL4-TL6 TL8 TL14 TL16 (after the first statement) on five
#   M-TL2 the replay without `_vin_zone`             -> RED 50: TL1-TL3 TL7 TL9-TL13 TL15 (the zone) on five legs
#   M-TL3 `_vtop_ref` asking a whole call when annotated -> RED 5: TL12 on five legs
#   M-TL4 no vector-global guard (zone, late)         -> RED 10: TLV1 TLV2 on five legs (a second error)
# 6.7.16 (D24 A, the user's decision, 2026-10-19; issues/2026-10-18-operator-after-vector-call-into-vector-local-
# dropped.md) — an operator after a vector call: every by-name receive takes the call only when it is the WHOLE source
# (`_vrcv_src`, PARSE_VAR's inline 16- / 32-byte receives through `_vrcv_wcall`, the assignment's `_vrcv_other` and the
# declaration's `_vrcv_decl_err` through `_vrcv_vcall`), so a vector destination meets the value-form refusal, and an
# untyped declaration whose initialiser a vector call of any spelling STARTS but is not takes that call's vector
# (`_vin_ustart`) and is refused the same way; at top level the untyped declaration's start is refused as its whole
# call is (`_vtop_ref`, 6.7.15's D26 words). Before (re-measured on this lane): `var w = mk2(41, 7) + 1;`, `var w:
# f64v2 = ..`, `w = ..` gave 161 on x86_64 / IR=3 / aarch64 (the `+ 1` dropped), 165 on cx (added to a lane), and on
# Windows "expected ';', got '+'"; `var w = s.m2() + 1;` bound one word (11; cx 165, PE 205); top-level `var w = mkv(41,
# 7) + 1;` stored the result's word plus 1 (1; cx / PE 42). Rows OP (refused once; OP1-OP6 the filed rows verbatim) and
# OPC1 (the whole call at every destination, width and spelling: 161) on host / host IR=3 / cx / aarch64 / win64.
# Mutations (2026-10-20, measured):
#   M-OP1 `_vrcv_src` taking a by-name call that only starts the source (the tree before) -> RED 15: OP3 OP9 OP14 on five
#       legs (the assignment's by-name arm, an explicit instance's declaration)
#   M-OP2 `_vrcv_wcall` reading `IDENT (` only (the tree before) -> RED 30: OP1 OP2 OP7 OP8 OP10 OP19 on five legs
#   M-OP3 `_vrcv_vcall` exempting any by-name call (the tree before) -> RED 45: OP1-OP3 OP7-OP10 OP14 OP19 on five legs
#   M-OP4 `_vin_decl` without `_vin_ustart`            -> RED 25: OP4 OP12 OP13 OP15 OP16 on five legs
#   M-OP5 `_vtop_ref` asking a whole call when untyped (the tree before) -> RED 15: OP6 OP17 OP18 on five legs
# 6.7.16 (met fixing D24) — and as a vector fn's RETURN value: `_simd_ret_call_ok` took a by-name call that only STARTS
# the value (`return mk2(41, 7) + 1;`), so x86_64 / IR=3 / aarch64 returned the call's vector (161, the `+ 1` dropped),
# cx added it to a lane (165) and Windows' own-call arm stopped at the operator ("expected ';', got '+'"); `return
# mk4(41) * 2;` gave 1 (PE "got '*'"). Now the 6.6.6 rule's refusal, "got `mk2`", once on every target (the whole value:
# `_simd_ret_call_ok`, PARSE_RETURN's Win64 arm through `_ret_vwcall`). Rows RV (refused once) and RVC1 (the whole
# calls, 161) on five legs. Mutations (2026-10-20, measured):
#   M-RV1 `_simd_ret_call_ok` taking a call that starts the value (the tree before) -> RED 15: RV1-RV3 on five legs
#   M-RV2 `_ret_vwcall` reading the call's `(` only (the tree before) -> RED 3: RV1-RV3 on win64 (a second error)
# 6.7.16 (D101 A, the user's decision, 2026-10-20; issues/2026-10-20-whole-vector-call-returned-as-scalar-or-passed-to-
# integer-parameter.md) — a whole vector call returned from a fn that returns no vector (PARSE_RETURN's `_vsc_ret`: the
# whole value, or a call starting it with an operator after it; a closure's expression body, `_vop_clb`), passed to a
# parameter that takes a word (`_bx_pcmpe_arg`'s `_vsc_arg`), or to a builtin's or an indirect call's argument
# (PARSE_FACTOR's `_vop_rchk` -> `_vsl_bopen`) is refused "a vector value cannot be returned as i64 / passed to an
# integer parameter - 'mk2' returns a vector, ..". Before (re-measured on this lane): `return mk2(41, 7);` from `: i64`
# gave x86_64 / IR=3 / aarch64 0, cx 41, PE exit 5 (a page fault: no hidden result pointer); `return s.m2();`,
# `takei(mk2(41, 7))`, `take(mk2(41, 7))`, `syscall(60, mk2(..))`, `|k| mk2(k, 7)` 0 / cx / PE 41; `return mk2(41, 7) +
# 1;` 1 / cx / PE 42. Rows VA (refused once; VA1-VA5 the filed rows verbatim), VAS (the refusal made in sync: the next
# statement keeps its own error) and VAC1 (the vector's own destinations, 161) on host / host IR=3 / cx / aarch64 /
# win64. Mutations (2026-10-21, measured):
#   M-VA0 the tree before                              -> RED 171: VA1-VA29 VAS1-VAS5 on five legs, and the message self-check
#   M-VA1 `_vsc_ret` judging nothing                   -> RED 70: VA1 VA2 VA5-VA14 VA25 VA28 on five legs
#   M-VA2 `_vsc_arg` judging nothing                   -> RED 45: VA3 VA4 VA15-VA19 VA27 VA29 on five legs
#   M-VA3 `_vop_whole` without the builtin / indirect argument (`_vsl_bopen`) -> RED 25: VA20-VA23 VA26 on five legs
#   M-VA4 the closure body never marked (`_vop_clb`)   -> RED 5: VA24 on five legs
#   M-VA5 `_vsc_ret` asking a whole call (`start` 0)   -> RED 15: VA5 VA13 VA14 on five legs
#   M-VA6 `_vsc_err` not marked in sync (`_refuse_in_sync`) -> RED 5: VAS1 on five legs (the declaration's resync skipped
#       the next statement, `x = zz9;` unreported)
# 6.7.16 (D100 A, the user's decision, 2026-10-20; issues/2026-10-20-vector-call-as-later-operand-or-compound-right-side-
# uses-first-word.md) — a vector call as an OPERAND anywhere (`_vop_opnd`: a binary operator beside it, a unary one or a
# compound `op =` before it), refused in the words of what receives it (`_vop_ctx`: a declaration "vector return type
# does not match the declared type", an assignment ".. the assigned variable", a `return` or a closure's expression body
# D101's, anything else the declaration's), and as the whole of a word slot (`_vsl_slot`: a store into a field, an
# element, through a pointer to no vector; a condition, an index, a range bound, a literal's field, `match`'s subject).
# A value-form vector destination's source keeps its own refusal (`_vop_vd`), a call a top-level declaration refused
# keeps that one (`_vop_done`); every refusal is made in sync (`_vrcv_tyerr`). Before (re-measured on this lane):
# `var x: i64 = 1 + mk2(41, 7);`, `x = 1 + mk2(..)`, `var w = 1 + mk2(..)`, `take(mk2(41, 7) + 1)` x86_64 / IR=3 /
# aarch64 1, cx / PE 42; `x += mk2(41, 7)`, `x += s.m2()`, `p.a = mk2(..)`, `*q = mk2(..)` 0 / 41; the filed row 6 0 /
# 82; `rd(mk2(41, 7) + 1)` and `var q = *mk2(41, 7);` 139 / 139 / 139, cx 0 / 1, PE 5; `if (mk2(41, 7))` took the
# branch on cx / PE only. Rows VO (refused once; VO1-VO7 the filed rows verbatim), VOS (VOF the filed row 6's two
# statements, each refused; the next statement's error kept) and VOC1 (161) on host / host IR=3 / cx / aarch64 / win64.
# Mutations (2026-10-21, measured):
#   M-VO0 the tree before                              -> RED 260: VO1-VO47 VOF VOS1-VOS5 on five legs (VO48 the parse's
#       one error before too)
#   M-VO1 `_vop_opnd` reading no operand               -> RED 155: VO1-VO5 VO7-VO14 VO18-VO31 VOF VOS1 VOS2 VOS5 on five
#       legs (VO15-VO17, a compound store through a field, a `*T`, an element, are the slot's store, same words)
#   M-VO2 `_vsl_slot` reading no slot                  -> RED 90: VO32-VO47 VOS3 VOS4 on five legs
#   M-VO3 `_vop_ctx` answering "anything else" always  -> RED 115: VO2 VO4 VO5 VO9-VO11 VO13 VO15-VO20 VO23 VO26 VO27
#       VO30 VOF VOS2, and RV1-RV4 (a vector fn's own `return`: the 6.6.6 rule's words) on five legs
#   M-VO4 the refusal not marked in sync (then a wrapper, `_vop_tyerr`; `_vrcv_tyerr` marks itself since the WS bite
#       below, M-WS1) -> RED 20: VOF VOS1-VOS3 on five legs
#   M-VO5 no `_vop_vd` exemption                       -> RED 85: OP1-OP5 OP7-OP15 OP19 OP22 OP23 on five legs (a second
#       error in front of the value-form refusal)
#   M-VO6 no `_vop_done` exemption                     -> RED 25: OP6 OP17 OP18 OP24 OP25 on five legs (two errors)
#   M-VO7 `_vsl_dst` exempting an untyped pointer      -> RED 5: VO36 on five legs
#   M-VO8 the `|` before a closure's body an operator  -> RED 5: VO48 on five legs (a second error before the parse's)
#   M-VO9 `_vop_ctx` past a closure's body start       -> RED 5: VO20 on five legs (the declaration's words)
# The s16 review (2026-10-21, measured): a whole call as a tuple literal's element (`_vsl_tup`; rows VO49-VO60, VOC2 the
# controls) — the tree before RED 60: VO49-VO60 on five legs (x86_64 / aarch64 0, cx 41: one word stored);
#   M-VO10 `_vsl_tup` reading no tuple literal         -> RED 60: VO49-VO60 on five legs
#   M-VO11 a tuple element always the declaration's words -> RED 10: VO51 VO60 on five legs
# and a whole call stored into a field or an element of a call's result (`_vsl_cstore`; rows VO61-VO67, VOC3 the
# controls) — the tree before RED 35: VO61-VO67 on five legs;
#   M-VO12 `_vsl_cstore` reading no call               -> RED 35: VO61-VO67 on five legs
#   M-VO13 `_vsl_cstore` by name only (no `callptr`)   -> RED 5: VO62 on five legs
# 6.7.17 (met landing D24) — a vector call as an OPERAND in a multi-value `return (..)`'s element (`_vop_mret`; rows
# VO68-VO73, VOC4 the controls): in a declared multi-value fn it compiled (`_vsc_rskip` stands down there) and handed back
# the word — `return (mk2(41, 7) + 1, 3);` x86_64 / IR=3 / aarch64 4, cx / PE 45; VO69 4 / 86, VO70 (a method's) 1 / 42,
# VO73 3 / 218 — and in an undeclared one PARSE_RETURN's `_vsc_ret` said D101's "returned as i64" (VO71, VO72), where the
# whole call there (VO54) and the guide say "does not match the declared type". Mutations (2026-10-22, measured):
#   M-VO14 `_vop_mret` answering 0                     -> RED 30: VO68-VO73 on five legs (VO71 VO72 D101's words)
#   M-VO15 `_vsc_ret` judging a `return (a, b);`       -> RED 10: VO71 VO72 on five legs (D101's words)
# 6.7.17 (met landing D24) — a refused compound assignment is its whole right side's one error (`_cop_rti`, set by
# `_asg_wide_refused`, `_asg_struct_refused`, `_dst_cop_err`, `_dvec_cop_err`; `_vop_rchk` leaves a vector value that is
# all of the right side alone): `w += mk2(1, 1);` on a vector, a struct, an array, through a `*f64v2` / `*Pt` / `**Pt`,
# `*(&w)`, printed the compound's refusal and then D100's "vector return type does not match the assigned variable" — two
# errors for one mistake (VCO2 / VCO3 the call's alone, the compound's refusal not said, before D23). Rows VCO1-VCO6
# (refused once), VCO7 / VCO8 (an operand inside the right side keeps its own: two errors) on five legs. Mutations
# (2026-10-22, measured, host):
#   M-VCO1 `_vop_rchk` without the exemption (the tree before) -> RED VCO1-VCO6 (two errors)
#   M-VCO2 the exemption taking a call an operator follows    -> RED VCO8 (one error)
# 6.7.17 (D23 A, the user's decision, 2026-10-22; issues/2026-10-21-vector-value-in-a-word-position-beyond-d100-d101.md
# row 1) — a store through a pointer to a vector copies the whole vector (`_dst_vec` / `_dvec_rcv`, parse.cyr), as `w = u`
# does: the store wrote one word — `*pv = u;` 42 on every leg, `*pv = mk2(4, 7);` and `*(&w) = mk2(4, 7);` x86_64 /
# IR=3 / aarch64 2, cx / PE 42, where 47 is right; VS5's spellings 149, VS6 (top level) 42 — and `*pv OP= v` added to lane
# 0 silently; `*pv = 5`, another vector, a callee held in a variable (PE: exit 5) compiled. Rows VS (run: 47, VS5 161)
# and VSK (refused once) on host / host IR=3 / cx / aarch64 / win64. Mutations (2026-10-22, measured, host):
#   M-VS1 `_dst_vec` answering 0 (the tree before)     -> RED VS1-VS3 VS5 VS6 (42 / 2 / 2 / 149 / 42) VSK1-VSK11
#   M-VS2 `_dvec_rcv` without the name arm             -> RED VS1 VS5 (refused "got `u`") VSK2
#   M-VS3 the call's temporary not copied through      -> RED VS2 VS3 (12) VS5 (113)
#   M-VS4 `_dvec_cop_err` saying nothing               -> RED VSK5-VSK7 (compiled)
#   M-VS5 the operand's step word only (no `&w` arm)   -> RED VS3 (2) VS5 (130) VSK7
# 6.7.17 (D24 A, the user's decision, 2026-10-22; the same issue's row 2) — a vector value that is no call (a local, a
# by-value parameter, a closure's capture, a dereference of a pointer to a vector: `_vval_at`) in a word slot is refused
# where D100 / D101 refuse the call, naming it ("'w' is a vector"): `_vop_val` feeds `_vop_rchk` and `_vsc_arg`;
# `_vsc_rval` a `return`, `_vin_vval` / `_vin_zval` an annotated declaration, `_vasg_vval` an assignment, and a tuple
# literal's element keeps its own words (`_tup_elem_bad`). Before (host, re-measured on this lane): 67 of rows VL1-VL70
# compiled and read lane 0 (the filed rows 4 / 4 / 4 / 5 / 4; `*w` 139; a closure's value 8), VL37 / VL69 / VL70 were
# refused in their own words as now. Rows VL (refused once), VLS (in sync: the next statement's error kept), VLC (the
# vector's own uses, 161) on host / host IR=3 / cx / aarch64 / win64. Mutations (2026-10-22, measured, host):
#   M-VL1 `_vop_val` reading calls only                -> RED 45: the operand, slot, argument and closure rows
#   M-VL2 `_vsc_rval` answering 0                      -> RED VL2 VL16 VL51 VL56 VL65
#   M-VL3 `_vin_vval` answering 0                      -> RED VL3 VL42-VL49 VL62
#   M-VL4 `_vasg_vval` answering 0                     -> RED VL17 VL55 VL60 VL63
#   M-VL5 `_tup_elem_bad` without the value arm        -> RED VL38 VL39 (compiled)
#   M-VL6 `_vnm_lty` without the capture arm           -> RED VL14-VL16 VL59
#   M-VL7 `_vin_zval` answering 0                      -> RED VL61
#   M-VL8 `_vop_whole` judging a name's tuple element  -> RED VL37-VL39 (D100's words first)
#   M-VL9 `_vop_tyerr` not in sync                     -> RED VLS1 VLS2 (the next statement's error lost)
# 6.7.17 (met landing D23) — a refusal that keeps away from its source's own error (a vector receive's "got ..", a value-
# form argument's `*E`, `_scv_err`) read that error as `_had_error` going 0 -> 1, which is sticky: after any earlier error
# in the file the source's own error did not count, and the refusal followed it — `var y = zz8; .. w = zz9;` printed
# "undefined variable 'zz9'" and then ".. assigned only from .. - got `zz9`", the zone's `var G: *i64 = zz9;` added
# "assigning non-pointer to typed pointer". A report since the snapshot (`_own_err`, util.cyr: `_err_n` moved, or
# `_had_error` 0 -> 1) is the source's own now. Rows VER1-VER7 (exactly the two errors), VER8 / VER9 (a genuine refusal
# after an earlier error kept) on five legs. Mutations (2026-10-22, measured, host):
#   M-VER1 `_own_err` reading `_had_error` only (the tree before) -> RED VER1-VER7 (a third line)
#   M-VER2 `_vrcv_other`'s test as before             -> RED VER1 VER4 VER5
#   M-VER3 `_scv_disarm`'s test as before             -> RED VER2 VER3
#   M-VER4 `_sar_dsrc`'s test as before               -> RED VER6
#   M-VER5 `_gvi_scalar`'s test as before             -> RED VER7
# 6.7.16 (met landing D100) — the vector receives' refusals are made in sync (`_refuse_in_sync`): the by-name call's
# mismatch into a local (`_try_vector_call_assign`), `_vrcv_tyerr` (the starting call, a method, `&f`, a global, another
# vector; D100's operands and slots), `_vrcv_mscal` (a method starting a declaration) and `_vin_decl` (`var x: i64 =
# mk2(..)`). Each latched the panic mid-statement, the statement parsed on to its own `;`, and PARSE_STMT's resync then
# skipped the NEXT statement: `x = mk2(1, 2); x = zz9;` reported no `zz9`, and a `for` header's init (`for (a = mk2(1,
# 2); a < 3; a = a + 1)`) lost its condition — "expected ';', got '='" second. Rows WS (two errors: the refusal, the next
# statement's) and WF (a `for` init, one error) on host / host IR=3 / cx / aarch64 / win64. Mutations (2026-10-21,
# measured):
#   M-WS0 the tree before                              -> RED 50: WS1-WS6 WF1-WF4 on five legs
#   M-WS1 `_vrcv_tyerr` not marked                     -> RED 35: WS4 WS6 WF4, VOF VOS1-VOS3 (D100's) on five legs
#   M-WS2 `_try_vector_call_assign`'s mismatch not marked -> RED 20: WS1 WS3 WF1 WF3 on five legs
#   M-WS3 `_vin_decl` not marked                       -> RED 10: WS2 WF2 on five legs
#   M-WS4 `_vrcv_mscal` not marked                     -> RED 5: WS5 on five legs
# 6.7.16 (met landing D100) — a refused statement prints no float-type warning (`_FLT_TYPE_WARN` says nothing while the
# panic latch its error holds is up): D100's `var x: f64 = 1.0 + mk2(41, 7);` printed the refusal and then "f64
# arithmetic with a non-f64 right operand" about the refused operand (f32, a comparison, an int-left `+` the same). Rows
# FW (one error, no warning; FW5 the next statement's own warning kept) on host / host IR=3 / cx / aarch64 / win64.
# Mutation (2026-10-21, measured): M-FW0 the tree before -> RED 25: FW1-FW5 on five legs (FW5 two warnings).
# The s16 review (2026-10-21, measured): a statement that reported an error that does not latch prints no float-type
# warning either (`_FLT_TYPE_WARN` asks `_err_n` against `_flt_en`, set by PARSE_STMT and each zone replay entry; a tuple's
# refusal, `_dyn_ebeg`, now counted) — rows FW6-FW13. The tree before -> RED 40: FW6-FW13 on five legs (a warning after
# the error); M-FW1 the count not asked -> RED 40 (the same rows); M-FW2 `_dyn_ebeg` not counting -> RED 10: FW6 FW11 on
# five legs; M-FW3 no zone entry reset -> RED 5: FW9 on five legs (C's own warning lost).

set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-$ROOT/build/cycc}
[ -x "$CC" ] || { echo "FAIL: compiler $CC missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: mktemp"; exit 1; }
# A PRIVATE wine prefix under $W, never the user's ~/.wine: its one wineserver is shared by
# every concurrent check.sh on the box. The EXIT kill is scoped to THIS prefix and also removes
# its server socket dir (/tmp/.wine-<uid>/server-<dev>-<ino>). The bare `wineserver -k` this trap
# ran before 6.6.16 killed the DEFAULT prefix's server on any exit before the export below.
# CHANGELOG [6.6.16]
# 6.6.17: wine's own HOME and XDG_CACHE_HOME are under $W too — a fresh prefix writes
# $HOME/.cache (mesa shader caches) — and `wineserver -k` leaves the server dir behind, so
# _wine_down removes it. CHANGELOG [6.6.17]
WP="$W/wine"
WHM="$W/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$W"' EXIT

MSG="a vector-returning fn carries its result"
pass=0; fail=0; nrefuse=0; naccept=0

bad() { echo "  FAIL: $*"; fail=$((fail+1)); }
good() { echo "  ok: $*"; pass=$((pass+1)); }

MKV='fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
'
MK4='fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, a + 1); return v; }
'

# ---- the row tables -------------------------------------------------------------------------
# One fn per table, `case` on the row id — the sources embed quotes and braces, so a here-doc
# list or an eval'd array would be the fragile spelling.
r_src() {  # $1 row id -> source on stdout
    case "$1" in
    X1) printf '%s' "$MKV"'fn bad(): f64v2 { return 5; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X2) printf '%s' "$MKV"'fn bad(): f64v2 { var s = 5; return s; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X3) printf '%s' "$MKV"'fn bad(): f64v2 { return; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X4) printf '%s' "$MKV"'fn bad(x: f64v2, y: f64v2): f64v2 { return x + y; }
fn main(): i64 { var a: f64v2 = mkv(10,11); var b: f64v2 = mkv(20,21); var c: f64v2 = bad(a,b); return load64(&c); }
var r = main(); syscall(60, r);
' ;;
    X5) printf '%s' "$MKV"'fn bad(): f64v2 { var v: f64v2 = mkv(41,7); return load64(&v); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X6) printf '%s' "$MKV"'fn sc(): i64 { return 5; }
fn bad(): f64v2 { return sc(); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X7) printf '%s' "$MKV$MK4"'fn bad(): f64v2 { return mk4(77); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X8) printf '%s' 'fn bad(): f64v4 { return 5; }
fn main(): i64 { var v: f64v4 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X9) printf '%s' 'fn bad(): f64v2 { var v: f64v4; store64(&v, 41); return v; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X10) printf '%s' 'fn bad(): f64v2 { return (41, 7); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X11) printf '%s' 'fn bad(): i64v2 { return (41, 7); }
fn main(): i64 { var v: i64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X12) printf '%s' 'fn bad(): f64v4 { return (41, 7, 9); }
fn main(): i64 { var v: f64v4 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X13) printf '%s' "$MKV"'fn bad(): f64v2 { var fp = &mkv; return callptr(fp, 41, 7); }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    X14) printf '%s' "$MKV"'var G: f64v2 = mkv(41, 7);
fn bad(): f64v2 { return G; }
fn main(): i64 { var v: f64v2 = bad(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    esac
}
REFUSE_ROWS="X1 X2 X3 X4 X5 X6 X7 X8 X9 X10 X11 X12 X13 X14"

a_src() {  # $1 row id -> source on stdout
    case "$1" in
    A1) printf '%s' "$MKV"'fn good(): f64v2 { var v: f64v2 = mkv(41, 7); return v; }
fn main(): i64 { var v: f64v2 = good(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    A2) printf '%s' "$MKV"'fn good(): f64v2 { var v: f64v2 = mkv(41, 7); return v; }
fn main(): i64 { var v: f64v2 = good(); return load64(&v + 8); }
var r = main(); syscall(60, r);
' ;;
    A3) printf '%s' "$MKV"'fn good(): f64v2 { return mkv(41, 7); }
fn main(): i64 { var v: f64v2 = good(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    A4) printf '%s' "$MKV"'fn good(): f64v2 { return mkv(41, 7); }
fn main(): i64 { var v: f64v2 = good(); return load64(&v + 8); }
var r = main(); syscall(60, r);
' ;;
    A5) printf '%s' "$MK4"'fn good(): f64v4 { var v: f64v4 = mk4(41); return v; }
fn main(): i64 { var v: f64v4 = good(); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    A6) printf '%s' 'fn sc(): i64 { return 33; }
fn main(): i64 { return sc(); }
var r = main(); syscall(60, r);
' ;;
    # A7-A9: the tuple return is refused for the VECTOR classes ONLY. These three are the
    # shapes X10-X12 sit next to and must not take with them — the rax:rdx pair struct, whose
    # ABI the ret2 convention IS, and the scalar arity-2/arity-3 multi-return. Each packs its
    # values into distinct decimal digits so a row cannot pass with the operands swapped or
    # with one register left unwritten. 6.7.11: a fn returning a named struct refuses the tuple
    # literal itself (the user's decision, issues/archived/2026-10-08-struct-operator-results.md #4), so
    # A7's pair struct said `ret2(41, 7)`, the same multi-value arm; A8 / A9 keep the tuple spelling. 6.7.13:
    # `ret2` in a fn declared to return a named struct is refused too (D22 A, the user's decision, 2026-10-15), so
    # A7 returns its struct as the struct: `return p;`, the 9-16 B pair's own path.
    A7) printf '%s' 'struct P2 { a; b; }
fn good(): P2 { var p: P2 = P2 { 41, 7 }; return p; }
fn main(): i64 { var p: P2 = good(); return p.a + p.b; }
var r = main(); syscall(60, r);
' ;;
    A8) printf '%s' 'fn two(): i64 { return (5, 6); }
fn main(): i64 { var a, b = two(); return a * 10 + b; }
var r = main(); syscall(60, r);
' ;;
    A9) printf '%s' 'fn three(): i64 { return (1, 2, 3); }
fn main(): i64 { var a, b, c = three(); return a * 100 + b * 10 + c; }
var r = main(); syscall(60, r);
' ;;
    esac
}
ACCEPT_ROWS="A1 A2 A3 A4 A5 A6 A7 A8 A9"

# ---- 6.7.11: the receive (rows V accepted, Y refused) ----------------------------------------
MSGV="a value-form vector local is"
VH='include "lib/fnptr.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkf(a, b, c, d): f32v4 { var v: f32v4; store32(&v, a); store32(&v + 4, b); store32(&v + 8, c); store32(&v + 12, d); return v; }
fn mki(a, b, c, d): i32v4 { var v: i32v4; store32(&v, a); store32(&v + 4, b); store32(&v + 8, c); store32(&v + 12, d); return v; }
fn mkd(a, b, c, d): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, b); store64(&v + 16, c); store64(&v + 24, d); return v; }
fn l2(x: f64v2): i64 { return load64(&x) * 100 + load64(&x + 8); }
fn lf(x: f32v4): i64 { return load32(&x) * 1000000 + load32(&x + 4) * 10000 + load32(&x + 8) * 100 + load32(&x + 12); }
fn li(x: i32v4): i64 { return load32(&x) * 1000000 + load32(&x + 4) * 10000 + load32(&x + 8) * 100 + load32(&x + 12); }
fn ld(x: f64v4): i64 { return load64(&x) * 1000000 + load64(&x + 8) * 10000 + load64(&x + 16) * 100 + load64(&x + 24); }
'
VE='var r = main(); syscall(60, r);
'
v_src() {  # $1 row id -> source on stdout; each returns 42 when every lane is right, else the shape that is not
    case "$1" in
    V1) printf '%s' "$VH"'fn main(): i64 { var a: f64v2 = callptr(&mk2, 41, 7); var b: f64v2 = fncall2(&mk2, 12, 34); var c: f64v2 = (mk2(56, 78));
  if (l2(a) != 4107) { return 1; } if (l2(b) != 1234) { return 2; } if (l2(c) != 5678) { return 3; } return 42; }
'"$VE" ;;
    V2) printf '%s' "$VH"'fn main(): i64 { var a: f64v2 = mk2(0, 0); a = callptr(&mk2, 41, 7); if (l2(a) != 4107) { return 1; }
  a = fncall2(&mk2, 12, 34); if (l2(a) != 1234) { return 2; } a = (mk2(56, 78)); if (l2(a) != 5678) { return 3; } return 42; }
'"$VE" ;;
    V3) printf '%s' "$VH"'fn main(): i64 { var a: f32v4 = callptr(&mkf, 1, 2, 3, 4); var b: f32v4 = fncall4(&mkf, 5, 6, 7, 8); var c: f32v4 = (mkf(9, 10, 11, 12));
  if (lf(a) != 1020304) { return 1; } if (lf(b) != 5060708) { return 2; } if (lf(c) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V4) printf '%s' "$VH"'fn main(): i64 { var a: f32v4 = mkf(0, 0, 0, 0); a = callptr(&mkf, 1, 2, 3, 4); if (lf(a) != 1020304) { return 1; }
  a = fncall4(&mkf, 5, 6, 7, 8); if (lf(a) != 5060708) { return 2; } a = (mkf(9, 10, 11, 12)); if (lf(a) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V5) printf '%s' "$VH"'fn main(): i64 { var a: i32v4 = callptr(&mki, 1, 2, 3, 4); var b: i32v4 = fncall4(&mki, 5, 6, 7, 8); var c: i32v4 = (mki(9, 10, 11, 12));
  if (li(a) != 1020304) { return 1; } if (li(b) != 5060708) { return 2; } if (li(c) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V6) printf '%s' "$VH"'fn main(): i64 { var a: i32v4 = mki(0, 0, 0, 0); a = callptr(&mki, 1, 2, 3, 4); if (li(a) != 1020304) { return 1; }
  a = fncall4(&mki, 5, 6, 7, 8); if (li(a) != 5060708) { return 2; } a = (mki(9, 10, 11, 12)); if (li(a) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V7) printf '%s' "$VH"'fn main(): i64 { var a: f64v4 = callptr(&mkd, 1, 2, 3, 4); var b: f64v4 = fncall4(&mkd, 5, 6, 7, 8); var c: f64v4 = (mkd(9, 10, 11, 12));
  if (ld(a) != 1020304) { return 1; } if (ld(b) != 5060708) { return 2; } if (ld(c) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V8) printf '%s' "$VH"'fn main(): i64 { var a: f64v4 = mkd(0, 0, 0, 0); a = callptr(&mkd, 1, 2, 3, 4); if (ld(a) != 1020304) { return 1; }
  a = fncall4(&mkd, 5, 6, 7, 8); if (ld(a) != 5060708) { return 2; } a = (mkd(9, 10, 11, 12)); if (ld(a) != 9101112) { return 3; } return 42; }
'"$VE" ;;
    V10) printf '%s' "$VH"'fn main(): i64 { var a: f64v2 = callptr((&mk2), 4, 1); if (load64(&a) + load64(&a + 8) != 5) { return 1; }
  var b: f64v4 = fncall4(((&mkd)), 1, 2, 3, 4); if (ld(b) != 1020304) { return 2; }
  a = fncall2((&mk2), 56, 78); if (l2(a) != 5678) { return 3; } var c: f32v4 = (callptr((&mkf), 9, 10, 11, 12)); if (lf(c) != 9101112) { return 4; } return 42; }
'"$VE" ;;
    V9) printf '%s' "$VH"'fn mko(out, a, b): i64 { store64(out, a); store64(out + 8, b); return 0; }
fn main(): i64 { var fp = &mko; var v: f64v2 = mk2(0, 0); var ig = callptr(fp, &v, 41, 7); var u: f64v2 = mk2(41, 7);
  if (l2(v) != 4107) { return 1; } if (l2(u) != 4107) { return 2; } return 42; }
'"$VE" ;;
    esac
}
V_ROWS="V1 V2 V3 V4 V5 V6 V7 V8 V9 V10"
y_src() {  # $1 row id -> source on stdout
    case "$1" in
    Y1) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 {
    var fp = &mkv;
    var v: f64v2 = callptr(fp, 41, 7);
    return load64(&v) + load64(&v + 8);
}
syscall(60, run());
' ;;
    Y2) printf '%s' "$VH"'fn main(): i64 { var v: f64v2 = 5; return l2(v); }
'"$VE" ;;
    Y3) printf '%s' "$VH"'fn main(): i64 { var w = 3; var v: f64v2 = load64(&w); return l2(v); }
'"$VE" ;;
    Y4) printf '%s' "$VH"'fn main(): i64 { var w = 3; var v: f64v2 = &w; return l2(v); }
'"$VE" ;;
    Y5) printf '%s' "$VH"'fn main(): i64 { var fp = &mk2; var v: f64v2 = mk2(0, 0); v = callptr(fp, 41, 7); return l2(v); }
'"$VE" ;;
    Y6) printf '%s' "$VH"'fn main(): i64 { var v: f64v2 = mk2(0, 0); v = 5; return l2(v); }
'"$VE" ;;
    Y7) printf '%s' "$VH"'fn main(): i64 { var w = 3; var v: f64v2 = mk2(0, 0); v = load64(&w); return l2(v); }
'"$VE" ;;
    Y8) printf '%s' "$VH"'fn main(): i64 { var w = 3; var v: f64v2 = mk2(0, 0); v = &w; return l2(v); }
'"$VE" ;;
    Y9) printf '%s' "$VH"'fn main(): i64 { var fp = &mkd; var v: f64v4 = callptr(fp, 1, 2, 3, 4); return ld(v); }
'"$VE" ;;
    Y10) printf '%s' "$VH"'fn main(): i64 { var fp = &mkf; var v: f32v4 = fncall4(fp, 1, 2, 3, 4); return lf(v); }
'"$VE" ;;
    Y11) printf '%s' "$VH"'fn main(): i64 { var v: i32v4 = mki(1, 2, 3, 4); var i = 0; for (i = 0; i < 1; v = 5) { i = i + 1; } return li(v); }
'"$VE" ;;
    esac
}
Y_ROWS="Y1 Y2 Y3 Y4 Y5 Y6 Y7 Y8 Y9 Y10 Y11"
# ---- 6.7.13: the explicit instance (rows E accepted, Z refused) --------------------------------
EH='include "lib/fnptr.cyr"
struct Pt { x; y; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkp<T>(p: T, a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn idg<T>(a: T): T { return a; }
fn rd(p: *f64v2): i64 { return load64(p); }
'
e_src() {  # $1 row id -> source on stdout
    case "$1" in
    E1) printf '%s' 'fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 { var v: f64v2; v = mkg<i64>(41, 7); return lanes(v); }
syscall(60, run());
' ;;
    E2) printf '%s' "$EH"'fn run(): i64 { var v: f64v2 = mkg<i64>(41, 7); return lanes(v); }
syscall(60, run());
' ;;
    E3) printf '%s' "$EH"'fn run(): i64 { var v: f64v2 = mkg<i64>(41, 7); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run());
' ;;
    E4) printf '%s' "$EH"'fn mk2(a, b): f64v2 { return mkg<i64>(a, b); }
fn run(): i64 { var v: f64v2 = mk2(41, 7); return lanes(v); }
syscall(60, run());
' ;;
    E5) printf '%s' "$EH"'fn run(): i64 { var v: f64v2 = mkg(41, 7); return lanes(v); }
syscall(60, run());
' ;;
    E6) printf '%s' "$EH"'fn run(): i64 { var v = mkg<i64>(41, 7); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run());
' ;;
    E7) printf '%s' "$EH"'fn run(): i64 { return rd(mkg<i64>(42, 7)); }
syscall(60, run());
' ;;
    E8) printf '%s' "$EH"'fn run(): i64 { var p: Pt; var v: f64v2 = mkg<i32>(41, 7); var w: f64v2; w = mkp<Pt>(p, 1, 2);
  var q: f64v2 = mkp<Pt>(p, 3, 4); v = mkg<i32>(lanes(v) - 120, 7); return lanes(v) + lanes(w) + lanes(q) - 46; }
syscall(60, run());
' ;;
    E9) printf '%s' "$EH"'fn run(): i64 { var v: f64v2 = (mkg<i64>(41, 7)); var w: f64v2; w = (mkg<i64>(1, 2));
  return lanes(v) + lanes(w) - 12; }
syscall(60, run());
' ;;
    esac
}
E_ROWS="E1 E2 E3 E4 E5 E6 E7 E8 E9"
e_want() { case "$1" in E7) echo 42;; *) echo 161;; esac; }
z_src() {  # $1 row id -> source on stdout
    case "$1" in
    Z1) printf '%s' "$EH"'fn run(): i64 { var v: f64v4 = mkg<i64>(41, 7); return 1; }
syscall(60, run());
' ;;
    Z2) printf '%s' "$EH"'fn run(): i64 { var w: f64v4; w = mkg<i64>(1, 2); return 1; }
syscall(60, run());
' ;;
    Z3) printf '%s' "$EH"'fn run(): i64 { var x = 0; x = mkg<i64>(1, 2); return x; }
syscall(60, run());
' ;;
    Z4) printf '%s' "$EH"'fn run(): i64 { var x: i64 = mkg<i64>(1, 2); return x; }
syscall(60, run());
' ;;
    Z5) printf '%s' "$EH"'fn run(): i64 { var v: f64v2 = idg<i64>(5); return 1; }
syscall(60, run());
' ;;
    Z6) printf '%s' "$EH"'fn r4(a, b): f64v4 { return mkg<i64>(a, b); }
syscall(60, 1);
' ;;
    esac
}
Z_ROWS="Z1 Z2 Z3 Z4 Z5 Z6"
z_msg() {
    case "$1" in
    Z1|Z4) echo "vector return type does not match the declared type";;
    Z2|Z3) echo "vector return type does not match the assigned variable";;
    Z5) echo "$MSGV";;
    Z6) echo "$MSG";;
    esac
}
# ---- 6.7.13 (D29): a method, an untyped indirect call and an indirect return (rows C accepted, Q refused) ----------
CH='include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, a); store64(&v + 16, a); store64(&v + 24, a); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(40 + self.k, 7); } }
'
c_src() {  # $1 row id -> source on stdout; each exits 161 when right
    case "$1" in
    C1) printf '%s' 'include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn run(): i64 {
    var s: S = S { 1 };
    var v: f64v2 = s.mv();
    return lanes(v);
}
syscall(60, run() % 256);
' ;;
    C2) printf '%s' 'include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 {
    var v = callptr(&mkv, 41, 7);
    return lanes(v);
}
syscall(60, run() % 256);
' ;;
    C3) printf '%s' 'include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn fwd(a, b): f64v2 { return callptr(&mkv, a, b); }
fn run(): i64 { var v: f64v2 = fwd(41, 7); return lanes(v); }
syscall(60, run() % 256);
' ;;
    C4) printf '%s' "$CH"'fn run(): i64 { var s: S = S { 1 }; var v: f64v2 = mkv(0, 0); v = s.mv(); if (s.k != 1) { return 1; } return lanes(v); }
syscall(60, run() % 256);
' ;;
    C5) printf '%s' "$CH"'fn fwd(a, b): f64v2 { return fncall2(&mkv, a, b); }
fn run(): i64 { var v: f64v2 = fwd(41, 7); return lanes(v); }
syscall(60, run() % 256);
' ;;
    esac
}
C_ROWS="C1 C2 C3 C4 C5"
# 6.7.15 (issues/archived/2026-10-17-wrapped-by-name-or-method-call-of-another-vector-into-vector-local-generic-words.md): the
# filed repro's own definitions — an f64v4 by name and an f64v4 method, wrapped into f64v2 locals (Q14-Q20, QF).
QW='fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); return v; }
struct S { k; }
impl S { fn mv(self): f64v4 { var v: f64v4; return v; } }
'
q_src() {  # $1 row id -> source on stdout
    case "$1" in
    Q1) printf '%s' "$CH"'fn run(): i64 { var s: S = S { 1 }; var v: f64v4 = s.mv(); return 1; }
syscall(60, run());
' ;;
    Q2) printf '%s' "$CH"'fn run(): i64 { var s: S = S { 1 }; var w: f64v4 = mk4(0); w = s.mv(); return 1; }
syscall(60, run());
' ;;
    Q3) printf '%s' "$CH"'fn run(): i64 { var fp = &mkv; var v = callptr(fp, 41, 7); return lanes(v); }
syscall(60, run() % 256);
' ;;
    Q4) printf '%s' "$CH"'fn fwd(a): f64v2 { return callptr(&mk4, a); }
syscall(60, 1);
' ;;
    Q5) printf '%s' 'include "lib/fnptr.cyr"
fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 { var v: f64v2 = callptr(&mk4, 41); return lanes(v); }
syscall(60, run());
' ;;
    Q6) printf '%s' "$CH"'fn run(): i64 { var v: f64v2 = mkv(1, 2); v = callptr(&mk4, 41); return lanes(v); }
syscall(60, run());
' ;;
    Q7) printf '%s' "$CH"'fn run(): i64 { var v: f64v2 = fncall1(&mk4, 41); return lanes(v); }
syscall(60, run());
' ;;
    Q8) printf '%s' "$CH"'fn run(): i64 { var v: f64v2 = mkv(1, 2); v = fncall1(&mk4, 41); return lanes(v); }
syscall(60, run());
' ;;
    Q9) printf '%s' "$CH"'fn run(): i64 { var v: f64v2 = (callptr(&mk4, 41)); return lanes(v); }
syscall(60, run());
' ;;
    Q10) printf '%s' "$CH"'fn run(): i64 { var v: f64v2 = mkv(1, 2); v = ((fncall1((&mk4), 41))); return lanes(v); }
syscall(60, run());
' ;;
    Q11) printf '%s' "$CH"'fn run(): i64 { var w: f32v4 = callptr(&mkv, 1, 2); return 1; }
syscall(60, run());
' ;;
    Q12) printf '%s' "$CH"'fn run(): i64 { var u: f64v4 = mk4(1); u = fncall2(&mkv, 1, 2); return 1; }
syscall(60, run());
' ;;
    Q13) printf '%s' "$CH"'fn run(): i64 { var v: f64v2 = mkv(1, 2); v = mk4(41); return lanes(v); }
syscall(60, run());
' ;;
    Q14) printf '%s' "$QW"'fn run(): i64 { var s: S = S { 1 }; var v: f64v2 = (mk4(41)); return 1; }
syscall(60, run());
' ;;
    Q15) printf '%s' "$QW"'fn run(): i64 { var s: S = S { 1 }; var w: f64v2 = (s.mv()); return 1; }
syscall(60, run());
' ;;
    Q16) printf '%s' "$QW"'fn run(): i64 { var s: S = S { 1 }; var v: f64v2; v = (mk4(41)); return 1; }
syscall(60, run());
' ;;
    Q17) printf '%s' "$QW"'fn run(): i64 { var s: S = S { 1 }; var w: f64v2; w = (s.mv()); return 1; }
syscall(60, run());
' ;;
    Q18) printf '%s' "$QW"'fn run(): i64 { var v: f64v2; var i = 0; for (i = 0; i < 1; v = ((mk4(i)))) { i = i + 1; } return 1; }
syscall(60, run());
' ;;
    Q19) printf '%s' "$QW"'fn mkg<U>(a: U): f64v4 { var v: f64v4; store64(&v, a); return v; }
fn run(): i64 { var v: f64v2 = ((mkg<i64>(41))); return 1; }
syscall(60, run());
' ;;
    Q20) printf '%s' "$QW"'struct T { s: S; }
fn run(): i64 { var t: T; var w: f64v2; w = (t.s.mv()); return 1; }
syscall(60, run());
' ;;
    esac
}
Q_ROWS="Q1 Q2 Q3 Q4 Q5 Q6 Q7 Q8 Q9 Q10 Q11 Q12 Q13 Q14 Q15 Q16 Q17 Q18 Q19 Q20"
q_msg() {
    case "$1" in
    Q1) echo "vector return type does not match the declared type";;
    Q2) echo "vector return type does not match the assigned variable";;
    Q3) echo "value-form SIMD arg must be a 16-byte vector";;
    Q4) echo "$MSG";;
    Q5|Q7|Q9|Q11|Q14|Q15|Q19) echo "vector return type does not match the declared type";;
    Q6|Q8|Q10|Q12|Q13|Q16|Q17|Q18|Q20) echo "vector return type does not match the assigned variable";;
    esac
}
# ---- 6.7.13 (D34 A): `*p` of a `*V` into a value-form vector local (rows P accepted, 161; K refused once) ----------------
PH='fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
'
p_src() {  # $1 row id -> source on stdout; each exits 161 when right
    case "$1" in
    P1) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 {
    var w: f64v2 = mkv(41, 7);
    var p: *f64v2 = &w;
    var v: f64v2 = *p;
    return lanes(v);
}
syscall(60, run() % 256);
' ;;
    P2) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 {
    var w: f64v2 = mkv(41, 7);
    var p: *f64v2 = &w;
    var v: f64v2 = mkv(1, 2);
    v = *p;
    return lanes(v);
}
syscall(60, run() % 256);
' ;;
    P3) printf '%s' "$PH"'fn dp(p: *f64v2): i64 { var v: f64v2 = (*p); var u: f64v2 = mkv(0, 0); u = (*p); return lanes(v) * 1000 + lanes(u); }
fn run(): i64 { var w: f64v2 = mkv(41, 7); if (dp(&w) != 417417) { return 1; } return 161; }
syscall(60, run() % 256);
' ;;
    P4) printf '%s' "$PH"'fn run(): i64 { var w: f64v4; store64(&w, 1); store64(&w + 24, 161); var p: *f64v4 = &w; var v: f64v4 = *p;
  return load64(&v + 24) + load64(&v) - 1; }
syscall(60, run() % 256);
' ;;
    P5) printf '%s' "$PH"'fn run(): i64 { var w: f64v2 = mkv(41, 7); var p: *f64v2 = &w; var pp: **f64v2 = &p; var v: f64v2 = mkv(0, 0);
  var i = 0; for (i = 0; i < 1; v = **pp) { i = i + 1; } return lanes(v); }
syscall(60, run() % 256);
' ;;
    esac
}
P_ROWS="P1 P2 P3 P4 P5"
k_src() {  # $1 row id -> source on stdout
    case "$1" in
    K1) printf '%s' "$PH"'fn run(): i64 { var w: i32v4; var q: *i32v4 = &w; var v: f64v2 = *q; return lanes(v); }
syscall(60, run());
' ;;
    K2) printf '%s' "$PH"'fn run(): i64 { var w: f64v4; var q: *f64v4 = &w; var v: f64v2 = mkv(0, 0); v = *q; return lanes(v); }
syscall(60, run());
' ;;
    K3) printf '%s' "$PH"'fn run(): i64 { var w: f64v2 = mkv(41, 7); var x = &w; var v: f64v2 = *x; return lanes(v); }
syscall(60, run());
' ;;
    K4) printf '%s' "$PH"'fn run(): i64 { var w: f64v2 = mkv(41, 7); var x = &w; var v: f64v2 = mkv(0, 0); v = *x; return lanes(v); }
syscall(60, run());
' ;;
    esac
}
K_ROWS="K1 K2 K3 K4"
k_msg() {
    case "$1" in
    K1|K2) echo "cannot copy 'q' into a variable of a different struct/vector type: 'v'";;
    K3) echo "a value-form vector local is initialised only from";;
    K4) echo "a value-form vector local is assigned only from";;
    esac
}
# ---- 6.7.14 (D35 A / D36 A): `return *p;` and an untyped `var v = *p;` with `p: *V` (rows D run, 161; rows DK refused once) --
# D1 / D2 the filed repros verbatim; D3-D6 the return through `(*p)`, `((*p))`, `**pp`, `*gp(p)`, `*h.pv`, `*&w`, f64v4,
# f32v4; D7 / D8 the untyped declaration wrapped, through `**pp`, `*gp(p)`, `*h.pv`, of f64v4 / f32v4, and a copy;
# D9 it meets the vector rules (a value-form argument, its lanes by address); D10 a `*i64`'s `*pi` stays a word.
# 6.7.15 (D21 A, the user's decision, 2026-10-18; issues/2026-10-17-dereference-of-address-of-typed-pointer-local-
# loses-its-pointee.md) — `*(&p)` of a typed pointer is p, its type kept: D11 `return **(&p);` (wrapped, f64v4), D12
# `lanes(**(&p))`, D13 the annotated, untyped and wrapped declarations (the untyped one a copy), D14 `*(&p)` / `**(&p)`
# into a `*f64v2` parameter pass p, `***(&pp)` of a `**f64v2`, D15 `(*(&ps)).y`, `**(&pb)` of a `*u8` one byte, `*(&pb
# + 0)` unchanged, `*(&pi) + 1` steps an i64; DV the filed repro verbatim compiles (its `rd` steps `p + 8` by the
# f64v2, so its own value is no row). They were refused ("got `this
# expression`", "got `*...`", "initialised only from .."), or bound one word (x86_64 178 / IR=3 82 / aarch64 42 / cx 98
# / PE 146 for the untyped `**(&p)`, 161 right). Mutations (2026-10-18, the gate run with each compiler):
#   the tree before it (3033ec7ab)                      -> RED 30: D11-D15 and DV on host / IR=3 / cx / aarch64 / win64
#                                                          (each refused, "got `this expression`" / "got `*...`" / ..)
#   `_deref_read` without `_amp_pw` (the token readers kept) -> RED 30: D11-D14 and DV refused, D15 exit 2 (`**(&pb)`
#                                                          a word), on every leg
#   `_hl_dref_psid` / `_hl_pw` without the `& NAME` arm  -> RED 5: D15 (`(*(&ps)).y` refused) on every leg
DH='include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn l4(x: f64v4): i64 { return load64(&x) * 1000 + load64(&x + 8) * 100 + load64(&x + 16) * 10 + load64(&x + 24); }
fn lf(x: f32v4): i64 { return load32(&x) * 1000 + load32(&x + 4) * 100 + load32(&x + 8) * 10 + load32(&x + 12); }
struct HV { pv: *f64v2; }
fn gp(p: *f64v2): *f64v2 { return p; }
'
d_src() {  # $1 row id -> source on stdout; each exits 161 when right
    case "$1" in
    D1) printf '%s' 'include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn dr(p: *f64v2): f64v2 { return *p; }
fn run(): i64 { var w: f64v2 = mkv(41, 7); var v: f64v2 = dr(&w); return lanes(v); }
syscall(60, run() % 256);
' ;;
    D2) printf '%s' 'include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 { var w: f64v2 = mkv(41, 7); var p: *f64v2 = &w; var v = *p; return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
' ;;
    D3) printf '%s' "$DH"'fn r1(p: *f64v2): f64v2 { return (*p); }
fn r2(p: *f64v2): f64v2 { return ((*p)); }
fn run(): i64 { var w: f64v2 = mkv(41, 7); var a: f64v2 = r1(&w); var b: f64v2 = r2(&w);
  if (lanes(a) != 417) { return 1; } if (lanes(b) != 417) { return 2; } return 161; }
syscall(60, run() % 256);
' ;;
    D4) printf '%s' "$DH"'fn r1(pp: **f64v2): f64v2 { return **pp; }
fn r2(p: *f64v2): f64v2 { return *gp(p); }
fn r3(h: *HV): f64v2 { return *h.pv; }
fn r4(): f64v2 { var w: f64v2 = mkv(4, 5); return *&w; }
fn run(): i64 { var w: f64v2 = mkv(41, 7); var p: *f64v2 = &w; var h: HV; h.pv = &w;
  var a: f64v2 = r1(&p); var b: f64v2 = r2(p); var c: f64v2 = r3(&h); var d: f64v2 = r4();
  if (lanes(a) != 417) { return 1; } if (lanes(b) != 417) { return 2; } if (lanes(c) != 417) { return 3; }
  if (lanes(d) != 45) { return 4; } return 161; }
syscall(60, run() % 256);
' ;;
    D5) printf '%s' "$DH"'fn r4(p: *f64v4): f64v4 { return *p; }
fn run(): i64 { var w: f64v4; store64(&w, 1); store64(&w + 8, 2); store64(&w + 16, 3); store64(&w + 24, 4);
  var v: f64v4 = r4(&w); if (l4(v) != 1234) { return 1; } return 161; }
syscall(60, run() % 256);
' ;;
    D6) printf '%s' "$DH"'fn rf(p: *f32v4): f32v4 { return *p; }
fn run(): i64 { var w: f32v4; store32(&w, 5); store32(&w + 4, 6); store32(&w + 8, 7); store32(&w + 12, 8);
  var v: f32v4 = rf(&w); if (lf(v) != 5678) { return 1; } return 161; }
syscall(60, run() % 256);
' ;;
    D7) printf '%s' "$DH"'fn run(): i64 { var w: f64v2 = mkv(41, 7); var p: *f64v2 = &w; var pp: **f64v2 = &p; var h: HV; h.pv = &w;
  var a = (*p); var b = **pp; var c = *gp(p); var d = *h.pv; var e = ((*p));
  if (lanes(a) != 417) { return 1; } if (lanes(b) != 417) { return 2; } if (lanes(c) != 417) { return 3; }
  if (lanes(d) != 417) { return 4; } if (lanes(e) != 417) { return 5; }
  store64(&a, 9); if (load64(&w) != 41) { return 6; } return 161; }
syscall(60, run() % 256);
' ;;
    D8) printf '%s' "$DH"'fn run(): i64 { var w: f64v4; store64(&w, 1); store64(&w + 8, 2); store64(&w + 16, 3); store64(&w + 24, 4);
  var f: f32v4; store32(&f, 5); store32(&f + 4, 6); store32(&f + 8, 7); store32(&f + 12, 8);
  var p4: *f64v4 = &w; var pf: *f32v4 = &f; var a = *p4; var b = *pf;
  if (l4(a) != 1234) { return 1; } if (lf(b) != 5678) { return 2; } return 161; }
syscall(60, run() % 256);
' ;;
    D9) printf '%s' "$DH"'fn run(): i64 { var w: f64v2 = mkv(41, 7); var p: *f64v2 = &w; var v = *p;
  if (load64(&v + 8) != 7) { return 1; } return lanes(v) - 256; }
syscall(60, run() % 256);
' ;;
    D10) printf '%s' "$DH"'fn run(): i64 { var x = 150; var pi: *i64 = &x; var u = *pi; var t = (*pi); return u + t - 139; }
syscall(60, run() % 256);
' ;;
    D11) printf '%s' "$DH"'fn dr(p: *f64v2): f64v2 { return **(&p); }
fn dr2(p: *f64v2): f64v2 { return ((**((&p)))); }
fn d4(p: *f64v4): f64v4 { return **(&p); }
fn run(): i64 { var w: f64v2 = mkv(41, 7); var a: f64v2 = dr(&w); var b: f64v2 = dr2(&w);
  var x: f64v4; store64(&x, 1); store64(&x + 8, 2); store64(&x + 16, 3); store64(&x + 24, 4); var c: f64v4 = d4(&x);
  if (lanes(a) != 417) { return 1; } if (lanes(b) != 417) { return 2; } if (l4(c) != 1234) { return 3; } return 161; }
syscall(60, run() % 256);
' ;;
    D12) printf '%s' "$DH"'fn run(): i64 { var w: f64v2 = mkv(41, 7); var p: *f64v2 = &w; var h: HV; h.pv = p;
  if (lanes(**(&p)) != 417) { return 1; } if (lanes((**(&p))) != 417) { return 2; }
  return lanes(**(&p)) - 256; }
syscall(60, run() % 256);
' ;;
    D13) printf '%s' "$DH"'fn run(): i64 { var w: f64v2 = mkv(41, 7); var p: *f64v2 = &w;
  var v: f64v2 = **(&p); var u = **(&p); var t = (**(&p));
  if (lanes(v) != 417) { return 1; } if (lanes(u) != 417) { return 2; } if (lanes(t) != 417) { return 3; }
  store64(&u, 9); if (load64(&w) != 41) { return 4; } return 161; }
syscall(60, run() % 256);
' ;;
    D14) printf '%s' "$DH"'fn rp2(p: *f64v2): i64 { var a: i64 = p; return load64(a) * 10 + load64(a + 8); }
fn run(): i64 { var w: f64v2 = mkv(41, 7); var p: *f64v2 = &w; var pp: **f64v2 = &p;
  if (rp2(*(&p)) != 417) { return 1; } if (rp2(**(&p)) != 417) { return 2; } if (lanes(***(&pp)) != 417) { return 3; }
  return 161; }
syscall(60, run() % 256);
' ;;
    D15) printf '%s' "$DH"'struct Ps { x; y; }
fn run(): i64 { var s: Ps; s.x = 3; s.y = 44; var ps: *Ps = &s; var b: u8[8]; store64(&b, 0x0102030405060708);
  var pb: *u8 = &b; var x = 5; var pi: *i64 = &x;
  if ((*(&ps)).y != 44) { return 1; } if (**(&pb) != 8) { return 2; } if (*(&pb + 0) != load64(&pb)) { return 3; }
  if (*(&pi) + 1 != pi + 1) { return 4; } return 161; }
syscall(60, run() % 256);
' ;;
    esac
}
D_ROWS="D1 D2 D3 D4 D5 D6 D7 D8 D9 D10 D11 D12 D13 D14 D15"
# DV: the D21 filed repro, verbatim, compiles with no error on every leg (`dv_compile`; its `rd` reads `p + 8` stepped by
# the f64v2, past w, so its exit value is no row).
dv_compile() {  # $1 leg label  $2 compiler  [$3 VAR=value]
    cat > "$W/dv.cyr" <<'DVEOF'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn rd(p: *f64v2): i64 { return load64(p) * 10 + load64(p + 8); }
fn dr(p: *f64v2): f64v2 { return **(&p); }
fn run(): i64 {
    var w: f64v2 = mkv(41, 7);
    var p: *f64v2 = &w;
    var a = rd(*(&p));
    var b = lanes(**(&p));
    return a + b;
}
syscall(60, run() % 256);
DVEOF
    rc=0
    if [ -n "${3:-}" ]; then env "$3" "$2" < "$W/dv.cyr" > "$W/dv.out" 2>"$W/dv.err" || rc=$?
    else "$2" < "$W/dv.cyr" > "$W/dv.out" 2>"$W/dv.err" || rc=$?; fi
    naccept=$((naccept+1))
    if [ "$rc" != 0 ] || [ ! -s "$W/dv.out" ] || grep -q '^error' "$W/dv.err"; then
        bad "$1 DV: the filed repro does not compile (rc=$rc: $(grep -m1 '^error' "$W/dv.err" 2>/dev/null))"
    else good "$1 DV: the filed repro compiles"; fi
}
dk_src() {  # $1 row id -> source on stdout
    case "$1" in
    DK1) printf '%s' "$DH"'fn bad(q: *f32v4): f64v2 { return *q; }
fn run(): i64 { var w: f32v4; var v: f64v2 = bad(&w); return lanes(v); }
syscall(60, run());
' ;;
    DK2) printf '%s' "$DH"'fn bad(q: *f64v4): f64v2 { return *q; }
fn run(): i64 { var w: f64v4; var v: f64v2 = bad(&w); return lanes(v); }
syscall(60, run());
' ;;
    DK3) printf '%s' "$DH"'fn bad(pi: *i64): f64v2 { return *pi; }
fn run(): i64 { var x = 5; var v: f64v2 = bad(&x); return lanes(v); }
syscall(60, run());
' ;;
    DK4) printf '%s' "$DH"'fn bad(q: *f32v4): f64v2 { return (*q); }
fn run(): i64 { var w: f32v4; var v: f64v2 = bad(&w); return lanes(v); }
syscall(60, run());
' ;;
    esac
}
DK_ROWS="DK1 DK2 DK3 DK4"
dk_got() { case "$1" in DK4) echo '(...)';; *) echo 'this expression';; esac; }
# ---- 6.7.14 (D37 A / D38 A / D39 A): a method declared `: V` at the destinations 6.7.13's D29 did not name (rows M run,
# 161; rows MK refused once) --------------------------------------------------------------------------------------------
# M1 / M2 the filed repros 1 and 3 verbatim; M3 the untyped declaration of f32v4 / f64v4 / a generic method / a `*Mv`
# receiver's (the receiver untouched by Win64's hidden result pointer); M4 `return s.m(..)` from f64v2 / f32v4 / f64v4
# fns, a generic method's, a local receiver's; M5 a scalar method into `: i64`, assigned and untyped, unchanged.
MH='fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkf(a, b, c, d): f32v4 { var v: f32v4; store32(&v, a); store32(&v + 4, b); store32(&v + 8, c); store32(&v + 12, d); return v; }
fn mkd(a, b, c, d): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, b); store64(&v + 16, c); store64(&v + 24, d); return v; }
fn l2(x: f64v2): i64 { return load64(&x) * 100 + load64(&x + 8); }
fn lf(x: f32v4): i64 { return load32(&x) * 1000 + load32(&x + 4) * 100 + load32(&x + 8) * 10 + load32(&x + 12); }
fn ld(x: f64v4): i64 { return load64(&x) * 1000 + load64(&x + 8) * 100 + load64(&x + 16) * 10 + load64(&x + 24); }
struct Mv { k; j; }
impl Mv {
    fn m2(self, a): f64v2 { return mk2(a + self.k, 7); }
    fn mf(self): f32v4 { return mkf(5, 6, 7, self.k); }
    fn md(self, a, b, c, d, e): f64v4 { return mkd(a, b, c, self.k); }
    fn mg<T>(self, a: T): f64v2 { return mk2(a, self.j); }
    fn m4(self): f64v4 { return mkd(1, 2, 3, 4); }
    fn sc(self): i64 { return self.k + 100; }
}
'
m_src() {  # $1 row id -> source on stdout; each exits 161 when right
    case "$1" in
    M1) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn run(): i64 { var s: S = S { 1 }; var v = s.mv(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
' ;;
    M2) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn fwd(s: *S): f64v2 { return s.mv(); }
fn run(): i64 { var s: S = S { 1 }; var v: f64v2 = fwd(&s); return lanes(v); }
syscall(60, run() % 256);
' ;;
    M3) printf '%s' "$MH"'fn run(): i64 { var s: Mv = Mv { 1, 2 }; var p: *Mv = &s;
  var a = s.m2(40); var b = s.mf(); var c = s.md(1, 2, 3, 4, 5); var d = s.mg(30); var e = p.m2(50);
  if (l2(a) != 4107) { return 1; } if (lf(b) != 5671) { return 2; } if (ld(c) != 1231) { return 3; }
  if (l2(d) != 3002) { return 4; } if (l2(e) != 5107) { return 5; } if (s.k * 10 + s.j != 12) { return 6; }
  store64(&a + 8, 9); if (l2(a) != 4109) { return 7; } return 161; }
syscall(60, run() % 256);
' ;;
    M4) printf '%s' "$MH"'fn f2(s: *Mv, a): f64v2 { return s.m2(a); }
fn ff(s: *Mv): f32v4 { return s.mf(); }
fn fd(s: *Mv): f64v4 { return s.md(1, 2, 3, 4, 5); }
fn fg(s: *Mv): f64v2 { return s.mg(30); }
fn fl(): f64v2 { var s: Mv = Mv { 3, 4 }; return s.m2(10); }
fn run(): i64 { var s: Mv = Mv { 1, 2 };
  var a: f64v2 = f2(&s, 20); var b: f32v4 = ff(&s); var c: f64v4 = fd(&s); var d: f64v2 = fg(&s); var e: f64v2 = fl();
  if (l2(a) != 2107) { return 1; } if (lf(b) != 5671) { return 2; } if (ld(c) != 1231) { return 3; }
  if (l2(d) != 3002) { return 4; } if (l2(e) != 1307) { return 5; } if (s.k * 10 + s.j != 12) { return 6; } return 161; }
syscall(60, run() % 256);
' ;;
    M5) printf '%s' "$MH"'fn run(): i64 { var s: Mv = Mv { 30, 2 }; var x: i64 = s.sc(); var y = s.sc(); y = s.sc() + 1; return x + y - 100; }
syscall(60, run() % 256);
' ;;
    esac
}
M_ROWS="M1 M2 M3 M4 M5"
mk_src() {  # $1 row id -> source on stdout
    case "$1" in
    MK1) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn run(): i64 { var s: S = S { 1 }; var x: i64 = s.mv(); return x; }
syscall(60, run() % 256);
' ;;
    MK2) printf '%s' "$MH"'fn run(): i64 { var s: Mv = Mv { 1, 2 }; var x = 0; x = s.m2(1); return x; }
syscall(60, run());
' ;;
    MK3) printf '%s' "$MH"'fn run(): i64 { var s: Mv = Mv { 1, 2 }; var x = 0; var i = 0; for (i = 0; i < 1; x = s.m2(1)) { i = i + 1; } return x; }
syscall(60, run());
' ;;
    MK4) printf '%s' "$MH"'struct Pt { x; y; }
fn run(): i64 { var s: Mv = Mv { 1, 2 }; var x: Pt = s.m2(1); return x.y; }
syscall(60, run());
' ;;
    MK5) printf '%s' "$MH"'fn run(): i64 { var s: Mv = Mv { 1, 2 }; var x: f64 = s.mf(); return 1; }
syscall(60, run());
' ;;
    MK6) printf '%s' "$MH"'fn bad(s: *Mv): f64v2 { return s.m4(); }
fn run(): i64 { var s: Mv = Mv { 1, 2 }; var v: f64v2 = bad(&s); return l2(v); }
syscall(60, run());
' ;;
    MK7) printf '%s' "$MH"'fn bad(s: *Mv): f32v4 { return s.m2(1); }
fn run(): i64 { var s: Mv = Mv { 1, 2 }; var v: f32v4 = bad(&s); return lf(v); }
syscall(60, run());
' ;;
    esac
}
MK_ROWS="MK1 MK2 MK3 MK4 MK5 MK6 MK7"
mk_msg() {
    case "$1" in
    MK1|MK4|MK5) echo "vector return type does not match the declared type";;
    MK2|MK3) echo "vector return type does not match the assigned variable";;
    MK6|MK7) echo "$MSG in a fixed register pair, so \`return\` takes a local of that vector type or a call to a fn declared to return the same one — got \`s\`";;
    esac
}
# ---- 6.7.15 (issues/archived/2026-10-17-by-name-vector-call-into-f64-declaration-stores-a-word.md): a by-name call declared `: V`
# into a declaration annotated with a type of no integer width (rows NK refused once; row N1 the control, 161) ----------
# NK1 the filed repro verbatim (`var x: f64 = mkv(41, 7);`), NK2-NK5 `: f32` / `: bool` / `: cstring` / an enum, NK6
# an explicit instance into `: f64`, NK7-NK11 the method into the same five (refused since 6.7.14's D38, the parity
# row), NK12-NK14 `: Vec` / `: Result` / `: Option` (newly refused too: the base compiled them, exit 3); N1 `var x:
# f64v2 = mkv(..)` and the untyped `var y = mkv(..)` stay the vector.
NH='fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
enum E { EA, EB }
'
nk_src() {  # $1 row id -> source on stdout
    case "$1" in
    NK1) printf '%s' 'include "lib/syscalls.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn main(): i64 { var x: f64 = mkv(41, 7); return 3; }
syscall(60, main());
' ;;
    NK2) printf '%s' "$NH"'fn run(): i64 { var x: f32 = mkv(41, 7); return 3; }
syscall(60, run());
' ;;
    NK3) printf '%s' "$NH"'fn run(): i64 { var x: bool = mkv(41, 7); return 3; }
syscall(60, run());
' ;;
    NK4) printf '%s' "$NH"'fn run(): i64 { var x: cstring = mkv(41, 7); return 3; }
syscall(60, run());
' ;;
    NK5) printf '%s' "$NH"'fn run(): i64 { var x: E = mkv(41, 7); return 3; }
syscall(60, run());
' ;;
    NK6) printf '%s' "$NH"'fn run(): i64 { var x: f64 = mkg<i64>(41, 7); return 3; }
syscall(60, run());
' ;;
    NK7) printf '%s' "$NH"'fn run(): i64 { var s: S = S { 1 }; var x: f64 = s.mv(); return 3; }
syscall(60, run());
' ;;
    NK8) printf '%s' "$NH"'fn run(): i64 { var s: S = S { 1 }; var x: f32 = s.mv(); return 3; }
syscall(60, run());
' ;;
    NK9) printf '%s' "$NH"'fn run(): i64 { var s: S = S { 1 }; var x: bool = s.mv(); return 3; }
syscall(60, run());
' ;;
    NK10) printf '%s' "$NH"'fn run(): i64 { var s: S = S { 1 }; var x: cstring = s.mv(); return 3; }
syscall(60, run());
' ;;
    NK11) printf '%s' "$NH"'fn run(): i64 { var s: S = S { 1 }; var x: E = s.mv(); return 3; }
syscall(60, run());
' ;;
    NK12) printf '%s' "$NH"'fn run(): i64 { var x: Vec = mkv(41, 7); return 3; }
syscall(60, run());
' ;;
    NK13) printf '%s' "$NH"'fn run(): i64 { var x: Result = mkv(41, 7); return 3; }
syscall(60, run());
' ;;
    NK14) printf '%s' "$NH"'fn run(): i64 { var x: Option = mkv(41, 7); return 3; }
syscall(60, run());
' ;;
    esac
}
NK_ROWS="NK1 NK2 NK3 NK4 NK5 NK6 NK7 NK8 NK9 NK10 NK11 NK12 NK13 NK14"
nk_msg() { echo "vector return type does not match the declared type"; }
n_src() {  # $1 row id -> source on stdout; exits 161 when right
    case "$1" in
    N1) printf '%s' "$NH"'fn run(): i64 { var x: f64v2 = mkv(41, 7); var y = mkv(41, 7); if (lanes(y) != 417) { return 1; } return lanes(x); }
syscall(60, run() % 256);
' ;;
    esac
}
N_ROWS="N1"
# ---- 6.7.15 (issues/archived/2026-10-17-chained-receiver-vector-method-binds-a-word-annotated-refused.md): a method declared `: V`
# on a FIELD-CHAIN receiver (rows CR run, 161; rows CRK refused once) -----------------------------------------------------
# CR1 the filed repro verbatim (the untyped declaration); CR2-CR5 `w.s.mv()`, `pw.s.mv()` (a pointer head), `h.w.s.mv()`
# (two hops) and a generic method (`w.s.mg(40)`, `w.s.mg<i64>(40)`), each at the untyped and annotated declarations, the
# assignment, a value-form argument, a `*f64v2` argument and the return, the receiver intact afterwards; CR6 a `*S` field
# hop, a global head, `self.s.mv()` in an impl, f32v4 / f64v4 methods; CR7 a closure's captured head.
CRH='fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkf(a, b, c, d): f32v4 { var v: f32v4; store32(&v, a); store32(&v + 4, b); store32(&v + 8, c); store32(&v + 12, d); return v; }
fn mkd(a, b, c, d): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, b); store64(&v + 16, c); store64(&v + 24, d); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn lanes4(x: f64v4): i64 { return load64(&x) * 1000 + load64(&x + 8) * 100 + load64(&x + 16) * 10 + load64(&x + 24); }
fn lf(x: f32v4): i64 { return load32(&x) * 1000 + load32(&x + 4) * 100 + load32(&x + 8) * 10 + load32(&x + 12); }
fn rd(p: *f64v2): i64 { var v: f64v2 = *p; return load64(&v) * 10 + load64(&v + 8); }
struct S { k; }
struct W { s: S; j; }
struct H { w: W; i; }
struct N { ps: *S; q; }
impl S {
    fn mv(self): f64v2 { return mkv(40 + self.k, 7); }
    fn mg<T>(self, a: T): f64v2 { return mkv(a + self.k, 7); }
    fn mf(self): f32v4 { return mkf(5, 6, 7, self.k); }
    fn md(self): f64v4 { return mkd(1, 2, 3, self.k); }
}
'
# 6.7.16 (issues/archived/2026-10-18-vector-method-on-dereference-or-call-head-receiver-binds-a-word.md): CPF the filing's header;
# CRP the heads CR12-CR17 and CRK8-CRK16 add to CRH.
CPF='fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
struct W { s: S; j; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn gw(p: *W): *W { return p; }
'
CRP='struct O { k; }
struct Q { ps: *S; }
impl O { fn gp(self, p: *W): *W { return p; } fn me(self, s: *S): *S { return s; } fn gpx<T>(self, p: *T): *T { return p; } }
fn gw(p: *W): *W { return p; }
fn gs(p: *S): *S { return p; }
fn mks(k): S { var s: S = S { k }; return s; }
fn gwg<T>(p: *T): *T { return p; }
'
cr_src() {  # $1 row id -> source on stdout; each exits 161 when right

    case "$1" in
    CR1) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
struct W { s: S; j; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
fn run(): i64 { var w: W; w.s.k = 1; var v = w.s.mv(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
' ;;
    CR2) printf '%s' "$CRH"'fn ret(w: *W): f64v2 { return w.s.mv(); }
fn run(): i64 { var w: W; w.s.k = 1; w.j = 5;
  var a = w.s.mv(); if (load64(&a + 8) != 7) { return 1; } if (lanes(a) != 417) { return 2; }
  var b: f64v2 = w.s.mv(); if (lanes(b) != 417) { return 3; }
  var c: f64v2 = mkv(0, 0); c = w.s.mv(); if (lanes(c) != 417) { return 4; }
  if (lanes(w.s.mv()) != 417) { return 5; } if (rd(w.s.mv()) != 417) { return 6; }
  var d: f64v2 = ret(&w); if (lanes(d) != 417) { return 7; } if (w.s.k * 10 + w.j != 15) { return 8; } return 161; }
syscall(60, run() % 256);
' ;;
    CR3) printf '%s' "$CRH"'fn ret(pw: *W): f64v2 { return pw.s.mv(); }
fn run(): i64 { var w: W; w.s.k = 2; w.j = 5; var pw: *W = &w;
  var a = pw.s.mv(); if (load64(&a + 8) != 7) { return 1; } if (lanes(a) != 427) { return 2; }
  var b: f64v2 = pw.s.mv(); if (lanes(b) != 427) { return 3; }
  var c: f64v2 = mkv(0, 0); c = pw.s.mv(); if (lanes(c) != 427) { return 4; }
  if (lanes(pw.s.mv()) != 427) { return 5; } if (rd(pw.s.mv()) != 427) { return 6; }
  var d: f64v2 = ret(pw); if (lanes(d) != 427) { return 7; } if (w.s.k * 10 + w.j != 25) { return 8; } return 161; }
syscall(60, run() % 256);
' ;;
    CR4) printf '%s' "$CRH"'fn ret(h: *H): f64v2 { return h.w.s.mv(); }
fn run(): i64 { var h: H; h.w.s.k = 3; h.w.j = 5; h.i = 6;
  var a = h.w.s.mv(); if (load64(&a + 8) != 7) { return 1; } if (lanes(a) != 437) { return 2; }
  var b: f64v2 = h.w.s.mv(); if (lanes(b) != 437) { return 3; }
  var c: f64v2 = mkv(0, 0); c = h.w.s.mv(); if (lanes(c) != 437) { return 4; }
  if (lanes(h.w.s.mv()) != 437) { return 5; } if (rd(h.w.s.mv()) != 437) { return 6; }
  var d: f64v2 = ret(&h); if (lanes(d) != 437) { return 7; } if (h.w.s.k * 100 + h.w.j * 10 + h.i != 356) { return 8; } return 161; }
syscall(60, run() % 256);
' ;;
    CR5) printf '%s' "$CRH"'fn ret(w: *W, a): f64v2 { return w.s.mg(a); }
fn retx(w: *W, a): f64v2 { return w.s.mg<i64>(a); }
fn run(): i64 { var w: W; w.s.k = 1; w.j = 5;
  var a = w.s.mg(40); if (load64(&a + 8) != 7) { return 1; } if (lanes(a) != 417) { return 2; }
  var b: f64v2 = w.s.mg<i64>(50); if (lanes(b) != 517) { return 3; }
  var c: f64v2 = mkv(0, 0); c = w.s.mg<i64>(60); if (lanes(c) != 617) { return 4; }
  if (lanes(w.s.mg(20)) != 217) { return 5; } if (rd(w.s.mg<i64>(30)) != 317) { return 6; }
  var d: f64v2 = ret(&w, 10); if (lanes(d) != 117) { return 7; }
  var e: f64v2 = retx(&w, 0); if (lanes(e) != 17) { return 8; } if (w.s.k * 10 + w.j != 15) { return 9; } return 161; }
syscall(60, run() % 256);
' ;;
    CR6) printf '%s' "$CRH"'var G: W = W { 0, 0 };
impl W { fn wm(self): f64v2 { return self.s.mv(); } fn wu(self): i64 { var v = self.s.mv(); return lanes(v); } }
fn run(): i64 { var s: S = S { 4 }; var n: N; n.ps = &s;
  var a = n.ps.mv(); if (lanes(a) != 447) { return 1; } a = n.ps.mv(); if (lanes(n.ps.mv()) != 447) { return 2; }
  G.s.k = 5; var g = G.s.mv(); var g2: f64v2 = G.s.mv(); if (lanes(g) + lanes(g2) != 914) { return 3; }
  var w: W; w.s.k = 6; var m: f64v2 = w.wm(); if (lanes(m) + w.wu() != 934) { return 4; }
  var f = w.s.mf(); if (lf(f) != 5676) { return 5; }
  var d: f64v4 = w.s.md(); if (lanes4(d) != 1236) { return 6; } d = mkd(0, 0, 0, 0); d = w.s.md(); if (lanes4(w.s.md()) != 1236) { return 7; }
  if (lanes4(d) != 1236) { return 8; } if (s.k * 10 + w.s.k != 46) { return 9; } return 161; }
syscall(60, run() % 256);
' ;;
    CR7) printf '%s' 'include "lib/alloc.cyr"
include "lib/fnptr.cyr"
'"$CRH"'fn run(): i64 { alloc_init(); var w: W; w.s.k = 1; var pw: *W = &w;
  var f = |k| lanes(w.s.mv()) + k; var g = |k| lanes(pw.s.mv()) + k;
  return fncall1(f, 0) + fncall1(g, 0) - 417 - 417 + 161; }
syscall(60, run() % 256);
' ;;
    CR8) printf '%s' "$CPF"'fn run(): i64 { var s: S = S { 1 }; var ps: *S = &s; var v = (*ps).mv(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
' ;;
    CR9) printf '%s' "$CPF"'fn run(): i64 { var w: W; w.s.k = 1; var pw: *W = &w; var v = (*pw).s.mv(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
' ;;
    CR10) printf '%s' "$CPF"'fn run(): i64 { var w: W; w.s.k = 1; var v = gw(&w).s.mv(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
' ;;
    CR11) printf '%s' "$CPF"'fn run(): i64 { var s: S = S { 1 }; var ps: *S = &s; var v: f64v2 = (*ps).mv(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, run() % 256);
' ;;
    CR12) printf '%s' "$CRH$CRP"'fn ret(ps: *S): f64v2 { return (*ps).mv(); }
fn run(): i64 { var s: S = S { 1 }; var ps: *S = &s;
  var a = (*ps).mv(); if (load64(&a + 8) != 7) { return 1; } if (lanes(a) != 417) { return 2; }
  var b: f64v2 = ((*ps)).mv(); if (lanes(b) != 417) { return 3; }
  var c: f64v2 = mkv(0, 0); c = (*(ps)).mv(); if (lanes(c) != 417) { return 4; }
  if (lanes((*ps).mv()) != 417) { return 5; } if (rd((*ps).mv()) != 417) { return 6; }
  var d: f64v2 = ret(ps); if (lanes(d) != 417) { return 7; } if (s.k != 1) { return 8; } return 161; }
syscall(60, run() % 256);
' ;;
    CR13) printf '%s' "$CRH$CRP"'fn ret(pw: *W): f64v2 { return (*pw).s.mv(); }
fn run(): i64 { var w: W; w.s.k = 2; w.j = 5; var pw: *W = &w;
  var a = (*pw).s.mv(); if (load64(&a + 8) != 7) { return 1; } if (lanes(a) != 427) { return 2; }
  var b: f64v2 = (*pw).s.mv(); if (lanes(b) != 427) { return 3; }
  var c: f64v2 = mkv(0, 0); c = (*pw).s.mv(); if (lanes(c) != 427) { return 4; }
  if (lanes((*pw).s.mv()) != 427) { return 5; } if (rd((*pw).s.mv()) != 427) { return 6; }
  var d: f64v2 = ret(pw); if (lanes(d) != 427) { return 7; } if (w.s.k * 10 + w.j != 25) { return 8; } return 161; }
syscall(60, run() % 256);
' ;;
    CR14) printf '%s' "$CRH$CRP"'fn ret(w: *W): f64v2 { return gw(w).s.mv(); }
fn run(): i64 { var w: W; w.s.k = 3; w.j = 5;
  var a = gw(&w).s.mv(); if (load64(&a + 8) != 7) { return 1; } if (lanes(a) != 437) { return 2; }
  var b: f64v2 = gw(&w).s.mv(); if (lanes(b) != 437) { return 3; }
  var c: f64v2 = mkv(0, 0); c = gw(&w).s.mv(); if (lanes(c) != 437) { return 4; }
  if (lanes(gw(&w).s.mv()) != 437) { return 5; } if (rd(gw(&w).s.mv()) != 437) { return 6; }
  var d: f64v2 = ret(&w); if (lanes(d) != 437) { return 7; } if (w.s.k * 10 + w.j != 35) { return 8; } return 161; }
syscall(60, run() % 256);
' ;;
    CR15) printf '%s' "$CRH$CRP"'fn run(): i64 { var s: S = S { 1 }; var ps: *S = &s; var w: W; w.s.k = 2; w.j = 5; var pw: *W = &w; var o: O = O { 0 }; var q: Q; q.ps = &s;
  var a = (s).mv(); if (lanes(a) != 417) { return 1; }
  var b = (ps).mv(); if (lanes(b) != 417) { return 2; }
  var c = (pw).s.mv(); if (lanes(c) != 427) { return 3; }
  var d = (w.s).mv(); if (lanes(d) != 427) { return 4; }
  var e = (gw(&w)).s.mv(); if (lanes(e) != 427) { return 5; }
  var f = (mks(3)).mv(); if (lanes(f) != 437) { return 6; }
  var g: f64v2 = (*q.ps).mv(); if (lanes(g) != 417) { return 7; }
  var h: f64v2 = (ps + 0).mv(); if (lanes(h) != 417) { return 8; }
  var i: f64v2 = (*o.me(&s)).mv(); if (lanes(i) != 417) { return 9; }
  if (lanes((o.me(ps)).mv()) != 417) { return 10; } if (s.k * 10 + w.s.k != 12) { return 11; } return 161; }
syscall(60, run() % 256);
' ;;
    CR16) printf '%s' 'include "lib/fnptr.cyr"
'"$CRH$CRP"'fn run(): i64 { var s: S = S { 1 }; var ps: *S = &s; var w: W; w.s.k = 2; w.j = 5; var pw: *W = &w; var o: O = O { 0 };
  var a = gs(&s).mv(); if (lanes(a) != 417) { return 1; }
  var b = mks(3).mv(); if (lanes(b) != 437) { return 2; }
  var c: f64v2 = gwg<W>(&w).s.mv(); if (lanes(c) != 427) { return 3; }
  var d = gwg(pw).s.mv(); if (lanes(d) != 427) { return 4; }
  var e = callptr(&gw, &w).s.mv(); if (lanes(e) != 427) { return 5; }
  var f: f64v2 = mkv(0, 0); f = fncall1(&gs, ps).mv(); if (lanes(f) != 417) { return 6; }
  var g = o.gp(&w).s.mv(); if (lanes(g) != 427) { return 7; }
  var h: f64v2 = o.me(&s).mv(); if (lanes(h) != 417) { return 8; }
  if (rd(o.gpx<W>(pw).s.mv()) != 427) { return 9; } if (lanes(gw(pw).s.mv()) != 427) { return 10; }
  if (s.k * 10 + w.s.k != 12) { return 11; } return 161; }
syscall(60, run() % 256);
' ;;
    CR17) printf '%s' 'include "lib/alloc.cyr"
include "lib/fnptr.cyr"
'"$CRH$CRP"'fn run(): i64 { alloc_init(); var s: S = S { 4 }; var ps: *S = &s; var w: W; w.s.k = 4; var pw: *W = &w;
  var a = (*ps).mg(40); if (lanes(a) != 447) { return 1; }
  var b: f64v2 = (*ps).mg<i64>(50); if (lanes(b) != 547) { return 2; }
  var c = gw(&w).s.mg(60); if (lanes(c) != 647) { return 3; }
  var f = (*ps).mf(); if (lf(f) != 5674) { return 4; }
  var d: f64v4 = gw(pw).s.md(); if (lanes4(d) != 1234) { return 5; } d = mkd(0, 0, 0, 0); d = ((*ps)).md(); if (lanes4(d) != 1234) { return 6; }
  var u = |k| lanes((*ps).mv()) + k; var v = |k| { var x = gw(pw).s.mv(); return lanes(x) + k; };
  if (fncall1(u, 0) + fncall1(v, 0) != 894) { return 7; } return 161; }
syscall(60, run() % 256);
' ;;
    esac
}
CR_ROWS="CR1 CR2 CR3 CR4 CR5 CR6 CR7 CR8 CR9 CR10 CR11 CR12 CR13 CR14 CR15 CR16 CR17"
crk_src() {  # $1 row id -> source on stdout
    case "$1" in
    CRK1) printf '%s' "$CRH"'fn run(): i64 { var w: W; w.s.k = 1; var x: i64 = w.s.mv(); return x; }
syscall(60, run());
' ;;
    CRK2) printf '%s' "$CRH"'fn run(): i64 { var w: W; w.s.k = 1; var x = 0; x = w.s.mv(); return x; }
syscall(60, run());
' ;;
    CRK3) printf '%s' "$CRH"'fn run(): i64 { var w: W; w.s.k = 1; var v: f64v4 = w.s.mv(); return 1; }
syscall(60, run());
' ;;
    CRK4) printf '%s' "$CRH"'fn run(): i64 { var h: H; h.w.s.k = 1; var u: f64v4 = mkd(1, 2, 3, 4); u = h.w.s.mv(); return 1; }
syscall(60, run());
' ;;
    CRK5) printf '%s' "$CRH"'fn run(): i64 { var w: W; w.s.k = 1; var pw: *W = &w; return lanes4(pw.s.mv()); }
syscall(60, run());
' ;;
    CRK6) printf '%s' "$CRH"'fn bad(w: *W): f64v4 { return w.s.mv(); }
fn run(): i64 { var w: W; var v: f64v4 = bad(&w); return lanes4(v); }
syscall(60, run());
' ;;
    CRK7) printf '%s' "$CPF"'fn run(): i64 { var s: S = S { 1 }; var ps: *S = &s; var x: i64 = (*ps).mv(); return x; }
syscall(60, run() % 256);
' ;;
    CRK8) printf '%s' "$CRH$CRP"'fn run(): i64 { var w: W; w.s.k = 1; var x = 0; x = gw(&w).s.mv(); return x; }
syscall(60, run());
' ;;
    CRK9) printf '%s' "$CRH$CRP"'fn run(): i64 { var s: S = S { 1 }; var ps: *S = &s; var u: f64v4 = (*ps).mv(); return 1; }
syscall(60, run());
' ;;
    CRK10) printf '%s' "$CRH$CRP"'fn run(): i64 { var w: W; var pw: *W = &w; var u: f64v4 = mkd(1, 2, 3, 4); u = (*pw).s.mv(); return 1; }
syscall(60, run());
' ;;
    CRK11) printf '%s' "$CRH$CRP"'fn run(): i64 { var s: S = S { 1 }; var ps: *S = &s; return lanes4((*ps).mv()); }
syscall(60, run());
' ;;
    CRK12) printf '%s' "$CRH$CRP"'fn run(): i64 { var o: O = O { 0 }; var w: W; var x = 0; x = o.gp(&w).s.mv(); return x; }
syscall(60, run());
' ;;
    CRK13) printf '%s' "$CRH$CRP"'fn run(): i64 { var x: f64 = mks(1).mv(); return 1; }
syscall(60, run());
' ;;
    CRK14) printf '%s' "$CRH$CRP"'fn run(): i64 { var s: S = S { 1 }; var x: i64 = ((s)).mv(); return x; }
syscall(60, run());
' ;;
    CRK15) printf '%s' "$CRH$CRP"'fn rd4(p: *f64v4): i64 { var v: f64v4 = *p; return load64(&v); }
fn run(): i64 { var w: W; w.s.k = 1; return rd4(gw(&w).s.mv()); }
syscall(60, run());
' ;;
    CRK16) printf '%s' "$CRH$CRP"'fn bad(ps: *S): f64v4 { return (*ps).mv(); }
fn run(): i64 { var s: S = S { 1 }; var v: f64v4 = bad(&s); return lanes4(v); }
syscall(60, run());
' ;;
    esac
}
CRK_ROWS="CRK1 CRK2 CRK3 CRK4 CRK5 CRK6 CRK7 CRK8 CRK9 CRK10 CRK11 CRK12 CRK13 CRK14 CRK15 CRK16"
crk_msg() {
    case "$1" in
    CRK1|CRK3|CRK7|CRK9|CRK13|CRK14) echo "vector return type does not match the declared type";;
    CRK2|CRK4|CRK8|CRK10|CRK12) echo "vector return type does not match the assigned variable";;
    CRK5|CRK11) echo "cannot pass 'mv' to a parameter of a different vector type in a call to 'lanes4'";;
    CRK15) echo "cannot pass 'mv' to a parameter of a different vector type in a call to 'rd4'";;
    CRK6) echo "$MSG in a fixed register pair, so \`return\` takes a local of that vector type or a call to a fn declared to return the same one — got \`w\`";;
    CRK16) echo "$MSG in a fixed register pair, so \`return\` takes a local of that vector type or a call to a fn declared to return the same one — got \`(...)\`";;
    esac
}
# ---- 6.7.15 (D28 A / D29 A, the user's decisions, 2026-10-18; issues/2026-10-17-wrapped-vector-call-into-untyped-or-
# scalar-declaration-binds-a-word.md): parentheses around a whole vector call are transparent at an untyped declaration
# (rows WR run, 161) and at an integer destination, and a method starting an integer initialiser is refused (rows WRK
# refused once) ----------------------------------------------------------------------------------------------------------
# WR1 / WR2 the filed rows 4 and 5 verbatim (by name, a method); WR3 a double wrap and an explicit instance; WR4 a field
# chain and a generic method (inferred and explicit); WR5 `(fncall2(&mk2, ..))` / `(callptr(&mk2, ..))`; WR6 f64v4 and
# f32v4. WRK1-WRK3 the filed rows 1-3 verbatim; WRK4 / WRK5 the filed assignments; WRK6 a for step; WRK7 a chain's
# method starting `: i64`; WRK8 a wrapped generic method into `: u8`; WRK9 `callptr(&mk2, ..) + 1` into `: i64`; WRK10 a
# double-wrapped explicit instance into `: f64`; WRK11 an explicit-instance method starting `: i64`.
WF='fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct Mv { k; }
impl Mv { fn m2(self): f64v2 { return mk2(41, 7); } }
'
WH='include "lib/fnptr.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkd(a, b, c, d): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, b); store64(&v + 16, c); store64(&v + 24, d); return v; }
fn mkf(a, b, c, d): f32v4 { var v: f32v4; store32(&v, a); store32(&v + 4, b); store32(&v + 8, c); store32(&v + 12, d); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
struct Mv { k; }
struct W { s: Mv; j; }
impl Mv {
    fn m2(self): f64v2 { return mk2(40 + self.k, 7); }
    fn gm<T>(self, a: T): f64v2 { return mk2(a + self.k, 7); }
}
'
# 6.7.16 (D25 / D26): an f64v4 method and call for the WRK17-WRK21 twins.
W4='include "lib/fnptr.cyr"
fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, 7); store64(&v + 16, 8); store64(&v + 24, 9); return v; }
struct M4 { k; }
impl M4 { fn m4(self): f64v4 { return mk4(41); } }
'
wr_src() {  # $1 row id -> source on stdout; each exits 161 when right

    case "$1" in
    WR1) printf '%s' "$WF"'fn r(): i64 { var x = (mk2(41, 7)); return load64(&x) * 10 + load64(&x + 8); }
syscall(60, r() % 256);
' ;;
    WR2) printf '%s' "$WF"'fn r(): i64 { var s: Mv = Mv { 1 }; var x = (s.m2()); return load64(&x) * 10 + load64(&x + 8); }
syscall(60, r() % 256);
' ;;
    WR3) printf '%s' "$WH"'fn r(): i64 { var x = ((mk2(41, 7))); var y = (mkg<i64>(41, 7)); if (lanes(y) != 417) { return 1; } return lanes(x); }
syscall(60, r() % 256);
' ;;
    WR4) printf '%s' "$WH"'fn r(): i64 { var w: W; w.s.k = 1; w.j = 5; var x = (w.s.m2()); var s: Mv = Mv { 1 }; var g = (s.gm(40)); var h = ((s.gm<i64>(40)));
    if (lanes(g) != 417) { return 2; } if (lanes(h) != 417) { return 3; } if (w.s.k * 10 + w.j != 15) { return 4; } return lanes(x); }
syscall(60, r() % 256);
' ;;
    WR5) printf '%s' "$WH"'fn r(): i64 { var x = (fncall2(&mk2, 41, 7)); var y = (callptr((&mk2), 41, 7)); if (lanes(y) != 417) { return 1; } return lanes(x); }
syscall(60, r() % 256);
' ;;
    WR6) printf '%s' "$WH"'fn r(): i64 { var d = (mkd(1, 2, 3, 4)); var f = ((mkf(5, 6, 7, 8)));
    if (load64(&d) * 1000 + load64(&d + 8) * 100 + load64(&d + 16) * 10 + load64(&d + 24) != 1234) { return 1; }
    if (load32(&f) * 1000 + load32(&f + 4) * 100 + load32(&f + 8) * 10 + load32(&f + 12) != 5678) { return 2; } return 161; }
syscall(60, r());
' ;;
    WR7) printf '%s' "$WF"'fn r(): i64 { var w = (mk2(41, 7)); var x = 0; x = load64(&w) + 1; if (x != 42) { return 1; } return load64(&w) * 10 + load64(&w + 8); }
syscall(60, r() % 256);
' ;;
    esac
}
WR_ROWS="WR1 WR2 WR3 WR4 WR5 WR6 WR7"
wrk_src() {  # $1 row id -> source on stdout
    case "$1" in
    WRK1) printf '%s' "$WF"'fn r(): i64 { var x: i64 = (mk2(41, 7)); return x; }
syscall(60, r() % 256);
' ;;
    WRK2) printf '%s' "$WF"'fn r(): i64 { var s: Mv = Mv { 1 }; var x: i64 = (s.m2()); return x; }
syscall(60, r() % 256);
' ;;
    WRK3) printf '%s' "$WF"'fn r(): i64 { var s: Mv = Mv { 1 }; var x: i64 = s.m2() + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK4) printf '%s' "$WF"'fn r(): i64 { var x = 0; x = (mk2(1, 2)); return x; }
syscall(60, r() % 256);
' ;;
    WRK5) printf '%s' "$WF"'fn r(): i64 { var s: Mv = Mv { 1 }; var x = 0; x = (s.m2()); return x; }
syscall(60, r() % 256);
' ;;
    WRK6) printf '%s' "$WH"'fn r(): i64 { var x = 0; for (var i = 0; i < 1; x = (mk2(i, 1))) { i = i + 1; } return x; }
syscall(60, r() % 256);
' ;;
    WRK7) printf '%s' "$WH"'fn r(): i64 { var w: W; w.s.k = 1; var x: i64 = w.s.m2() + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK8) printf '%s' "$WH"'fn r(): i64 { var s: Mv = Mv { 1 }; var x: u8 = (s.gm(40)); return x; }
syscall(60, r() % 256);
' ;;
    WRK9) printf '%s' "$WH"'fn r(): i64 { var x: i64 = callptr(&mk2, 41, 7) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK10) printf '%s' "$WH"'fn r(): i64 { var x: f64 = ((mkg<i64>(41, 7))); return 3; }
syscall(60, r() % 256);
' ;;
    WRK11) printf '%s' "$WH"'fn r(): i64 { var s: Mv = Mv { 1 }; var x: i64 = s.gm<i64>(40) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK12) printf '%s' "$WF"'fn r(): i64 { var s: Mv = Mv { 1 }; var x = 0; x = s.m2() + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK13) printf '%s' "$WF"'fn r(): i64 { var x = 0; x = callptr(&mk2, 41, 7) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK14) printf '%s' "$WF"'fn r(): i64 { var x: i64 = (mk2(41, 7)) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK15) printf '%s' "$WF"'fn r(): i64 { var x = 0; x = (mk2(41, 7)) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK16) printf '%s' "$WF"'fn r(): i64 { var s: Mv = Mv { 1 }; var x: i64 = (s.m2()) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK17) printf '%s' "$W4"'fn r(): i64 { var s: M4 = M4 { 1 }; var x = 0; x = s.m4() + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK18) printf '%s' "$W4"'fn r(): i64 { var x = 0; x = callptr(&mk4, 41) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK19) printf '%s' "$W4"'fn r(): i64 { var x: i64 = (mk4(41)) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK20) printf '%s' "$W4"'fn r(): i64 { var x = 0; x = ((mk4(41))) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK21) printf '%s' "$W4"'fn r(): i64 { var s: M4 = M4 { 1 }; var x: i64 = (s.m4()) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK22) printf '%s' "$WF"'fn r(): i64 { var x = 0; for (var i = 0; i < 1; x = (mk2(i, 1)) + 1) { i = i + 1; } return x; }
syscall(60, r() % 256);
' ;;
    WRK23) printf '%s' "$WF"'var G = 0;
fn r(): i64 { var s: Mv = Mv { 1 }; G = s.m2() + 1; return G; }
syscall(60, r() % 256);
' ;;
    WRK24) printf '%s' "$WF"'var G = 0;
syscall(1, 1, "", 0);
var s: Mv = Mv { 1 };
G = s.m2() + 1;
syscall(60, G % 256);
' ;;
    WRK25) printf '%s' "$WF"'var X: i64 = (mk2(41, 7)) + 1;
syscall(60, X % 256);
' ;;
    WRK26) printf '%s' "$WF"'syscall(1, 1, "", 0);
var X: i64 = (mk2(41, 7)) + 1;
syscall(60, X % 256);
' ;;
    WRK27) printf '%s' "$WF"'fn r(): i64 { var x: i64 = (mk2(41, 7) + 1); return x; }
syscall(60, r() % 256);
' ;;
    WRK28) printf '%s' "$WF"'fn r(): i64 { var s: Mv = Mv { 1 }; var x = 0; x = ((s.m2())) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK29) printf '%s' "$WF"'fn r(): i64 { var s: Mv = Mv { 1 }; var ps: *Mv = &s; var x = 0; x = ((*ps).m2()) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK30) printf '%s' "$WH"'fn r(): i64 { var w: W; var x = 0; x = (w.s.m2()) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK31) printf '%s' "$WH"'fn r(): i64 { var x = 0; x = (callptr(&mk2, 41, 7)) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK32) printf '%s' "$WF"'fn r(): i64 { var x: i64 = (mk2(41, 7) + 1) * 2; return x; }
syscall(60, r() % 256);
' ;;
    WRK33) printf '%s' "$WF"'fn r(): i64 { var x = 0; x = (mk2(41, 7) + 1) * 2; return x; }
syscall(60, r() % 256);
' ;;
    WRK34) printf '%s' "$WF"'fn r(): i64 { var s: Mv = Mv { 1 }; var x: i64 = (s.m2() * 2) + 1; return x; }
syscall(60, r() % 256);
' ;;
    WRK35) printf '%s' "$WF"'fn r(): i64 { var s: Mv = Mv { 1 }; var ps: *Mv = &s; var x: i64 = ((*ps).m2() + 1) * 2; return x; }
syscall(60, r() % 256);
' ;;
    WRK36) printf '%s' "$WF"'var X: i64 = (mk2(41, 7) + 1) * 2;
syscall(60, X % 256);
' ;;
    WRK37) printf '%s' "$WF"'syscall(1, 1, "", 0);
var X: i64 = ((mk2(41, 7) + 1) * 2) + 3;
syscall(60, X % 256);
' ;;
    WRK38) printf '%s' "$W4"'fn r(): i64 { var x = 0; x = ((mk4(41) + 1) * 2) + 3; return x; }
syscall(60, r() % 256);
' ;;
    WRK39) printf '%s' "$WF"'var G = 0;
fn r(): i64 { var s: Mv = Mv { 1 }; G = (s.m2() + 1) * 2; return G; }
syscall(60, r() % 256);
' ;;
    WRK40) printf '%s' "$WH"'fn r(): i64 { var x = 0; x = (callptr(&mk2, 41, 7) + 1) * 2; return x; }
syscall(60, r() % 256);
' ;;
    WRK41) printf '%s' "$WF"'var G = 0;
syscall(1, 1, "", 0);
G = (mk2(41, 7) + 1) * 2;
syscall(60, G % 256);
' ;;
    esac
}
WRK_ROWS="WRK1 WRK2 WRK3 WRK4 WRK5 WRK6 WRK7 WRK8 WRK9 WRK10 WRK11 WRK12 WRK13 WRK14 WRK15 WRK16 WRK17 WRK18 WRK19 WRK20 WRK21 WRK22 WRK23 WRK24 WRK25 WRK26 WRK27 WRK28 WRK29 WRK30 WRK31 WRK32 WRK33 WRK34 WRK35 WRK36 WRK37 WRK38 WRK39 WRK40 WRK41"
wrk_msg() {
    case "$1" in
    WRK4|WRK5|WRK6|WRK12|WRK13|WRK15|WRK17|WRK18|WRK20|WRK22|WRK23|WRK24|WRK28|WRK29|WRK30|WRK31|WRK33|WRK38|WRK39|WRK40|WRK41) echo "vector return type does not match the assigned variable";;
    *) echo "vector return type does not match the declared type";;
    esac
}
# ---- 6.7.15 (issues/archived/2026-10-17-vector-call-or-method-assigned-to-scalar-global-stores-a-word.md): a vector call assigned to
# a GLOBAL that is no vector, and `fncallN(&f, ..)` / `callptr(&f, ..)` into a scalar local, refused as `x = mkv(..);` into a
# local is (rows GA refused once; GAF the filed row 4 verbatim, its two lines; GV a vector global keeps its own refusal;
# GC the control, 161) -----------------------------------------------------------------------------------------------------
# GA1-GA3 the filed rows 1-3 verbatim (by name, a method, `fncall2(&mkv, ..)`); GA4 / GA5 row 4's two statements alone;
# GA6 a closure assigning the global; GA7 an explicit instance; GA8 a field chain's method; GA9 / GA10 wrapped by name /
# `callptr((&mkv), ..)`; GA11 a by-name call starting the source, as the local's arm reads it; GA12 a struct global;
# GA13 an f64 global from a method; GA14 a for step.
GAH='fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
var G = 0;
'
GAX='include "lib/fnptr.cyr"
include "lib/alloc.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn sc(a): i64 { return a + 1; }
struct S { k; }
struct W { s: S; j; }
struct P1 { a; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } fn ks(self): i64 { return self.k; } }
var G = 0;
var VG: f64v2 = 0;
var GS: P1 = P1 { 0 };
var GF: f64 = 0.0;
'
ga_src() {  # $1 row id -> source on stdout
    case "$1" in
    GA1) printf '%s' "$GAH"'fn run(): i64 { G = mkv(41, 7); return G; }
syscall(60, run() % 256);
' ;;
    GA2) printf '%s' "$GAH"'fn run(): i64 { var s: S = S { 1 }; G = s.mv(); return G; }
syscall(60, run() % 256);
' ;;
    GA3) printf '%s' 'include "lib/fnptr.cyr"
'"$GAH"'fn run(): i64 { G = fncall2(&mkv, 41, 7); return G; }
syscall(60, run() % 256);
' ;;
    GA4) printf '%s' 'include "lib/fnptr.cyr"
'"$GAH"'fn run(): i64 { var x = 0; x = fncall2(&mkv, 41, 7); return x; }
syscall(60, run() % 256);
' ;;
    GA5) printf '%s' "$GAH"'fn run(): i64 { var y: i64 = callptr(&mkv, 41, 7); return y; }
syscall(60, run() % 256);
' ;;
    GA6) printf '%s' "$GAX"'fn run(): i64 { alloc_init(); var f = |k| { G = mkv(41, k); return 0; }; fncall1(f, 7); return G; }
syscall(60, run() % 256);
' ;;
    GA7) printf '%s' "$GAX"'fn run(): i64 { G = mkg<i64>(41, 7); return G; }
syscall(60, run() % 256);
' ;;
    GA8) printf '%s' "$GAX"'fn run(): i64 { var w: W; w.s.k = 1; G = w.s.mv(); return G; }
syscall(60, run() % 256);
' ;;
    GA9) printf '%s' "$GAX"'fn run(): i64 { G = (mkv(41, 7)); return G; }
syscall(60, run() % 256);
' ;;
    GA10) printf '%s' "$GAX"'fn run(): i64 { G = ((callptr((&mkv), 41, 7))); return G; }
syscall(60, run() % 256);
' ;;
    GA11) printf '%s' "$GAX"'fn run(): i64 { G = mkv(41, 7) + 1; return G; }
syscall(60, run() % 256);
' ;;
    GA12) printf '%s' "$GAX"'fn run(): i64 { GS = mkv(41, 7); return 1; }
syscall(60, run() % 256);
' ;;
    GA13) printf '%s' "$GAX"'fn run(): i64 { var s: S = S { 1 }; GF = s.mv(); return 1; }
syscall(60, run() % 256);
' ;;
    GA14) printf '%s' "$GAX"'fn run(): i64 { for (var i = 0; i < 1; G = mkv(i, 1)) { i = i + 1; } return G; }
syscall(60, run() % 256);
' ;;
    GV1) printf '%s' "$GAX"'fn run(): i64 { VG = mkv(41, 7); return 1; }
syscall(60, run() % 256);
' ;;
    esac
}
GA_ROWS="GA1 GA2 GA3 GA4 GA5 GA6 GA7 GA8 GA9 GA10 GA11 GA12 GA13 GA14 GV1"
ga_msg() {
    case "$1" in
    GA5) echo "vector return type does not match the declared type";;
    GV1) echo "vector global 'VG' is read and written through its address";;
    *) echo "vector return type does not match the assigned variable";;
    esac
}
gc_src() {  # $1 row id -> source on stdout; exits 161 when right
    case "$1" in
    GC1) printf '%s' "$GAX"'fn run(): i64 { var s: S = S { 7 }; G = sc(100); G = G + s.ks(); var v = mkv(41, 7); G = G + lanes(v) - 364; return G; }
syscall(60, run() % 256);
' ;;
    GC2) printf '%s' "$GAX"'var s7: S = S { 7 };
syscall(0 - 1, 0);
G = sc(99);
var i = 0;
for (i = 0; i < 1; G = sc(G)) { i = 1; }
G = G + s7.ks();
G = (G + 53);
syscall(60, G % 256);
' ;;
    esac
}
GC_ROWS="GC1 GC2"
# GAF: the filed row 4 verbatim — both statements refused, in order, at their calls.
gaf_src() { printf '%s' 'include "lib/fnptr.cyr"
'"$GAH"'fn run(): i64 { var x = 0; x = fncall2(&mkv, 41, 7); var y: i64 = callptr(&mkv, 41, 7); return x + y; }
syscall(60, run() % 256);
'; }
refuse_gaf_all() {  # $1 leg label  $2 compiler
    gaf_src > "$W/gaf.cyr"
    rc=0
    "$2" < "$W/gaf.cyr" > "$W/gaf.out" 2>"$W/gaf.err" || rc=$?
    nrefuse=$((nrefuse+1))
    got=$(grep '^error' "$W/gaf.err" | sed 's/^error:<source>://' | tr '\n' '|')
    want="6:32: vector return type does not match the assigned variable|6:65: vector return type does not match the declared type|"
    if [ "$got" != "$want" ]; then bad "$1 GAF: '$got' (rc=$rc), want '$want'"
    elif [ -s "$W/gaf.out" ]; then bad "$1 GAF: reported but still emitted an artifact"
    else good "$1 GAF refused: both statements, the mismatch's words"; fi
}
# ---- 6.7.16 (issues/archived/2026-10-18-top-level-assignment-of-vector-call-to-scalar-global-stores-a-word.md): a call declared to
# return a vector ASSIGNED at top level to a global that is no vector, refused as the same assignment in a fn is (rows
# GT refused once; GTV the vector-global control keeps its own refusal; GC2 the scalar control, 161) -------------------
# GT1 / GT2 the filed rows 1 / 2 verbatim (by name after a first statement, a method); GT3 `fncall2(&mkv, ..)`; GT4
# wrapped `(mkv(..))`; GT5 the program's first statement; GT6 a top-level for step; GT7 `callptr(&mkv, ..)`; GT8 an
# explicit instance; GT9 a by-name call starting the source.
gt_src() {  # $1 row id -> source on stdout
    case "$1" in
    GT1) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
var G = 0;
syscall(0 - 1, 0);
G = mkv(41, 7);
syscall(60, G % 256);
' ;;
    GT2) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
var G = 0;
var s: S = S { 1 };
syscall(0 - 1, 0);
G = s.mv();
syscall(60, G % 256);
' ;;
    GT3) printf '%s' "$GAX"'syscall(0 - 1, 0);
G = fncall2(&mkv, 41, 7);
syscall(60, G % 256);
' ;;
    GT4) printf '%s' "$GAX"'syscall(0 - 1, 0);
G = (mkv(41, 7));
syscall(60, G % 256);
' ;;
    GT5) printf '%s' "$GAX"'G = mkv(41, 7);
syscall(60, G % 256);
' ;;
    GT6) printf '%s' "$GAX"'var i = 0;
for (i = 0; i < 1; G = mkv(41, 7)) { i = 1; }
syscall(60, G % 256);
' ;;
    GT7) printf '%s' "$GAX"'syscall(0 - 1, 0);
G = callptr(&mkv, 41, 7);
syscall(60, G % 256);
' ;;
    GT8) printf '%s' "$GAX"'syscall(0 - 1, 0);
G = mkg<i64>(41, 7);
syscall(60, G % 256);
' ;;
    GT9) printf '%s' "$GAX"'syscall(0 - 1, 0);
GF = mkv(41, 7) + 1;
syscall(60, 0);
' ;;
    GTV1) printf '%s' "$GAX"'syscall(0 - 1, 0);
VG = mkv(41, 7);
syscall(60, 0);
' ;;
    esac
}
GT_ROWS="GT1 GT2 GT3 GT4 GT5 GT6 GT7 GT8 GT9 GTV1"
gt_msg() {
    case "$1" in
    GTV1) echo "vector global 'VG' is read and written through its address";;
    *) echo "vector return type does not match the assigned variable";;
    esac
}
# ---- 6.7.15 (D26 A / D27 A, the user's decisions, 2026-10-18; issues/2026-10-17-top-level-untyped-vector-call-or-method-
# result-binds-a-word.md): a call declared to return a vector into a TOP-LEVEL declaration (rows TL refused once) ---------
# TL1-TL3 the filed rows verbatim in the declaration zone (by name, a method, `: i64`), TL4-TL6 the same after the first
# statement; TL7 / TL8 `callptr(&mkv, ..)` in both zones; TL9 wrapped; TL10 an explicit instance; TL11 a field chain's
# method through a `*W` global; TL12 a method starting a `: i64` initialiser; TL13 `fncall2(&mkv, ..)` into `: u8`; TL14
# a wrapped call into `: f64` after the first statement; TL15 a callee declared below the zone global; TL16 a struct
# annotation after the first statement; TLV1 / TLV2 a vector annotation keeps the vector global's own refusal, once.
TLH='fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
var s: S = S { 1 };
'
TLX='include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct S { k; }
struct W { s: S; j; }
struct P1 { a; }
impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
var s: S = S { 1 };
var pw: *W = 0;
'
TLR='syscall(60, (load64(&w) * 10 + load64(&w + 8)) % 256);
'
tl_src() {  # $1 row id -> source on stdout
    case "$1" in
    TL1) printf '%s' "$TLH"'var w = mkv(41, 7);
'"$TLR" ;;
    TL2) printf '%s' "$TLH"'var v = s.mv();
syscall(60, (load64(&v) * 10 + load64(&v + 8)) % 256);
' ;;
    TL3) printf '%s' "$TLH"'var x: i64 = mkv(41, 7); syscall(60, x % 256);
' ;;
    TL4) printf '%s' "$TLH"'var q = 0; q = 1;
var w = mkv(41, 7);
'"$TLR" ;;
    TL5) printf '%s' "$TLH"'var q = 0; q = 1;
var v = s.mv();
syscall(60, (load64(&v) * 10 + load64(&v + 8)) % 256);
' ;;
    TL6) printf '%s' "$TLH"'var q = 0; q = 1;
var x: i64 = mkv(41, 7); syscall(60, x % 256);
' ;;
    TL7) printf '%s' "$TLX"'var w = callptr(&mkv, 41, 7);
'"$TLR" ;;
    TL8) printf '%s' "$TLX"'var q = 0; q = 1;
var w = callptr(&mkv, 41, 7);
'"$TLR" ;;
    TL9) printf '%s' "$TLX"'var w = ((mkv(41, 7)));
'"$TLR" ;;
    TL10) printf '%s' "$TLX"'var w = mkg<i64>(41, 7);
'"$TLR" ;;
    TL11) printf '%s' "$TLX"'var w = pw.s.mv();
'"$TLR" ;;
    TL12) printf '%s' "$TLX"'var x: i64 = s.mv() + 1; syscall(60, x % 256);
' ;;
    TL13) printf '%s' "$TLX"'var x: u8 = fncall2(&mkv, 41, 7); syscall(60, x % 256);
' ;;
    TL14) printf '%s' "$TLX"'var q = 0; q = 1;
var x: f64 = (mkv(41, 7)); syscall(60, 0);
' ;;
    TL15) printf '%s' 'var w = mkv(41, 7);
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
'"$TLR" ;;
    TL16) printf '%s' "$TLX"'var q = 0; q = 1;
var t: P1 = mkv(41, 7); syscall(60, 0);
' ;;
    TLV1) printf '%s' "$TLX"'var w: f64v4 = s.mv();
syscall(60, 0);
' ;;
    TLV2) printf '%s' "$TLX"'var q = 0; q = 1;
var w: f64v2 = (mkv(41, 7));
syscall(60, 0);
' ;;
    esac
}
TL_ROWS="TL1 TL2 TL3 TL4 TL5 TL6 TL7 TL8 TL9 TL10 TL11 TL12 TL13 TL14 TL15 TL16 TLV1 TLV2"
tl_msg() {
    case "$1" in
    TL2|TL5|TL11) echo "'mv' returns a vector by value, and a vector result needs storage in a fn's frame - call it inside a fn";;
    TL10) echo "'mkg' returns a vector by value, and a vector result needs storage in a fn's frame - call it inside a fn";;
    TLV1|TLV2) echo "vector global 'w' takes no initializer but 0";;
    TL1|TL4|TL7|TL8|TL9|TL15) echo "'mkv' returns a vector by value, and a vector result needs storage in a fn's frame - call it inside a fn";;
    *) echo "vector return type does not match the declared type";;
    esac
}
# ---- 6.7.16 (D24 A, the user's decision, 2026-10-19; issues/2026-10-18-operator-after-vector-call-into-vector-local-
# dropped.md): an operator after a vector call into a VECTOR LOCAL, or into an untyped declaration, is refused by name
# (rows OP refused once; OPC the whole-call controls, 161) ---------------------------------------------------------------
# OP1-OP6 the filed rows 1-6 verbatim (1 / 4 / 6 per the decision); OP7-OP10 f64v4 / f32v4 twins; OP11 `w = (mk2(..)) +
# 1;`; OP12 `var w = (s.m2()) + 1;`; OP13-OP16 `callptr(&f, ..)`, an explicit instance, a chain's method, a parenthesised
# head; OP17 / OP18 top level after the first statement (by name, a method); OP19 another operator; OP20 / OP21 a call of
# another vector starting it (the mismatch's words, as before).
OPF='fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct Mv { k; }
impl Mv { fn m2(self): f64v2 { return mk2(41, 7); } }
'
OPH='include "lib/fnptr.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, 7); store64(&v + 16, 8); store64(&v + 24, 9); return v; }
fn mkf(a, b, c, d): f32v4 { var v: f32v4; store32(&v, a); store32(&v + 4, b); store32(&v + 8, c); store32(&v + 12, d); return v; }
struct Mv { k; }
struct W { s: Mv; j; }
impl Mv { fn m2(self): f64v2 { return mk2(41, 7); } fn m4(self): f64v4 { return mk4(41); } }
'
op_src() {  # $1 row id -> source on stdout
    case "$1" in
    OP1) printf '%s' "$OPF"'fn r(): i64 { var w = mk2(41, 7) + 1; return load64(&w) * 10 + load64(&w + 8); }
syscall(60, r() % 256);
' ;;
    OP2) printf '%s' "$OPF"'fn r(): i64 { var w: f64v2 = mk2(41, 7) + 1; return load64(&w) * 10 + load64(&w + 8); }
syscall(60, r() % 256);
' ;;
    OP3) printf '%s' "$OPF"'fn r(): i64 { var w: f64v2; w = mk2(41, 7) + 1; return load64(&w) * 10 + load64(&w + 8); }
syscall(60, r() % 256);
' ;;
    OP4) printf '%s' "$OPF"'fn r(): i64 { var s: Mv = Mv { 1 }; var w = s.m2() + 1; return load64(&w) * 10 + load64(&w + 8); }
syscall(60, r() % 256);
' ;;
    OP5) printf '%s' "$OPF"'fn r(): i64 { var s: Mv = Mv { 1 }; var w: f64v2 = s.m2() + 1; return load64(&w) * 10 + load64(&w + 8); }
syscall(60, r() % 256);
' ;;
    OP6) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
var w = mkv(41, 7) + 1;
syscall(60, w % 256);
' ;;
    OP7) printf '%s' "$OPH"'fn r(): i64 { var w = mk4(41) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP8) printf '%s' "$OPH"'fn r(): i64 { var w: f64v4 = mk4(41) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP9) printf '%s' "$OPH"'fn r(): i64 { var w: f64v4 = mk4(1); w = mk4(41) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP10) printf '%s' "$OPH"'fn r(): i64 { var f = mkf(1, 2, 3, 4) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP11) printf '%s' "$OPF"'fn r(): i64 { var w: f64v2 = mk2(1, 2); w = (mk2(41, 7)) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP12) printf '%s' "$OPF"'fn r(): i64 { var s: Mv = Mv { 1 }; var w = (s.m2()) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP13) printf '%s' "$OPH"'fn r(): i64 { var w = callptr(&mk2, 41, 7) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP14) printf '%s' "$OPH"'fn r(): i64 { var w = mkg<i64>(41, 7) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP15) printf '%s' "$OPH"'fn r(): i64 { var x: W; var w = x.s.m2() + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP16) printf '%s' "$OPH"'fn r(): i64 { var s: Mv = Mv { 1 }; var ps: *Mv = &s; var w = (*ps).m2() + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP17) printf '%s' "$OPH"'syscall(1, 1, "", 0);
var w = mk2(41, 7) + 1;
syscall(60, 0);
' ;;
    OP18) printf '%s' "$OPH"'var GS: Mv = Mv { 1 };
var w = GS.m2() + 1;
syscall(60, 0);
' ;;
    OP19) printf '%s' "$OPH"'fn r(): i64 { var w = mk2(41, 7) * 2; return 1; }
syscall(60, r() % 256);
' ;;
    OP20) printf '%s' "$OPH"'fn r(): i64 { var w: f64v2 = mk4(41) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP21) printf '%s' "$OPH"'fn r(): i64 { var w: f64v2 = mk2(1, 2); w = mk4(41) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP22) printf '%s' "$OPF"'fn r(): i64 { var w = (mk2(41, 7) + 1) * 2; return 1; }
syscall(60, r() % 256);
' ;;
    OP23) printf '%s' "$OPF"'fn r(): i64 { var s: Mv = Mv { 1 }; var w = ((s.m2() * 2)) + 1; return 1; }
syscall(60, r() % 256);
' ;;
    OP24) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
var w = (mkv(41, 7) + 1) * 2;
syscall(60, w % 256);
' ;;
    OP25) printf '%s' "$OPH"'syscall(1, 1, "", 0);
var w = (mk2(41, 7) + 1) * 2;
syscall(60, 0);
' ;;
    esac
}
OP_ROWS="OP1 OP2 OP3 OP4 OP5 OP6 OP7 OP8 OP9 OP10 OP11 OP12 OP13 OP14 OP15 OP16 OP17 OP18 OP19 OP20 OP21 OP22 OP23 OP24 OP25"
op_msg() {
    case "$1" in
    OP1|OP2|OP19) echo "$MSGV initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`mk2\`";;
    OP3) echo "$MSGV assigned only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`mk2\`";;
    OP4|OP5) echo "$MSGV initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`s\`";;
    OP6|OP24) echo "'mkv' returns a vector by value, and a vector result needs storage in a fn's frame - call it inside a fn";;
    OP7|OP8) echo "$MSGV initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`mk4\`";;
    OP9) echo "$MSGV assigned only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`mk4\`";;
    OP10) echo "$MSGV initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`mkf\`";;
    OP11) echo "$MSGV assigned only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`(...)\`";;
    OP12|OP16|OP22|OP23) echo "$MSGV initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`(...)\`";;
    OP13) echo "$MSGV initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`callptr\`";;
    OP14) echo "$MSGV initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`mkg\`";;
    OP15) echo "$MSGV initialised only from a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`x\`";;
    OP17|OP25) echo "'mk2' returns a vector by value, and a vector result needs storage in a fn's frame - call it inside a fn";;
    OP18) echo "'m2' returns a vector by value, and a vector result needs storage in a fn's frame - call it inside a fn";;
    OP20) echo "vector return type does not match the declared type";;
    OP21) echo "vector return type does not match the assigned variable";;
    esac
}
# The controls: the whole call at every destination, every width and spelling (161).
opc_src() {  # $1 row id -> source on stdout; exits 161 when right
    case "$1" in
    OPC1) printf '%s' "$OPH"'fn r(): i64 { var s: Mv = Mv { 1 };
  var a = mk2(41, 7); var b: f64v2 = mk2(41, 7); var c: f64v2 = mk2(0, 0); c = mk2(41, 7);
  if (load64(&a) * 10 + load64(&a + 8) != 417) { return 1; } if (load64(&b) * 10 + load64(&b + 8) != 417) { return 2; }
  if (load64(&c) * 10 + load64(&c + 8) != 417) { return 3; }
  var d = mk4(4); var e: f64v4 = mk4(1); e = mk4(4); if (load64(&d) + load64(&d + 24) + load64(&e + 16) != 21) { return 4; }
  var f = mkf(1, 2, 3, 4); if (load32(&f) * 1000 + load32(&f + 4) * 100 + load32(&f + 8) * 10 + load32(&f + 12) != 1234) { return 5; }
  var g = s.m2(); var h = (mk2(41, 7)); var i = callptr(&mk2, 41, 7); var j = mkg<i64>(41, 7);
  if (load64(&g + 8) + load64(&h + 8) + load64(&i + 8) + load64(&j + 8) != 28) { return 6; } return 161; }
syscall(60, r() % 256);
' ;;
    esac
}
OPC_ROWS="OPC1"
# ---- 6.7.16 (met fixing D24): an operator after a by-name vector call as a vector fn's RETURN value (rows RV refused once;
# RVC1 the whole calls, 161) -----------------------------------------------------------------------------------------------
# RV1 `return mk2(41, 7) + 1;`, RV2 an explicit instance, RV3 an f64v4 fn's `return mk4(41) * 2;`, RV4 the wrapped
# `return (mk2(41, 7)) + 1;` (refused before too: the same words).
rv_src() {  # $1 row id -> source on stdout
    case "$1" in
    RV1) printf '%s' "$OPH"'fn f(): f64v2 { return mk2(41, 7) + 1; }
fn r(): i64 { var v: f64v2 = f(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, r() % 256);
' ;;
    RV2) printf '%s' "$OPH"'fn f(): f64v2 { return mkg<i64>(41, 7) + 1; }
fn r(): i64 { var v: f64v2 = f(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, r() % 256);
' ;;
    RV3) printf '%s' "$OPH"'fn f(): f64v4 { return mk4(41) * 2; }
fn r(): i64 { var v: f64v4 = f(); return load64(&v); }
syscall(60, r() % 256);
' ;;
    RV4) printf '%s' "$OPH"'fn f(): f64v2 { return (mk2(41, 7)) + 1; }
fn r(): i64 { var v: f64v2 = f(); return load64(&v) * 10 + load64(&v + 8); }
syscall(60, r() % 256);
' ;;
    esac
}
RV_ROWS="RV1 RV2 RV3 RV4"
rv_msg() {
    case "$1" in
    RV1) echo "$MSG in a fixed register pair, so \`return\` takes a local of that vector type or a call to a fn declared to return the same one — got \`mk2\`";;
    RV2) echo "$MSG in a fixed register pair, so \`return\` takes a local of that vector type or a call to a fn declared to return the same one — got \`mkg\`";;
    RV3) echo "$MSG in a fixed register pair, so \`return\` takes a local of that vector type or a call to a fn declared to return the same one — got \`mk4\`";;
    RV4) echo "$MSG in a fixed register pair, so \`return\` takes a local of that vector type or a call to a fn declared to return the same one — got \`(...)\`";;
    esac
}
rvc_src() {  # $1 row id -> source on stdout; exits 161 when right
    case "$1" in
    RVC1) printf '%s' "$OPH"'fn f(a): f64v2 { return mk2(a, 7); }
fn g(): f64v2 { return mkg<i64>(41, 7); }
fn h(): f64v4 { return mk4(4); }
fn r(): i64 { var v: f64v2 = f(41); var w: f64v2 = g(); var x: f64v4 = h();
  if (load64(&v) * 10 + load64(&v + 8) != 417) { return 1; } if (load64(&w) * 10 + load64(&w + 8) != 417) { return 2; }
  if (load64(&x) * 10 + load64(&x + 24) != 49) { return 3; } return 161; }
syscall(60, r() % 256);
' ;;
    esac
}
RVC_ROWS="RVC1"
# ---- 6.7.16 (the receives review): a WHOLE vector call followed by a stray token is still the whole call (rows SX, one
# error each — the parse's own). The receives and the vector return told a call that only STARTS the source (D24) by the
# token after its `)`, and read anything but the terminator as an operator, so the value-form / 6.6.6 refusal ("... got
# `mk2`") came in front of the parse's "expected ';', got number 5" — two errors, the first naming the wrong mistake
# (by name since D24; the method and `&f` spellings since 6.7.13). Only a binary operator, `.`, `[` or a postfix `?`
# makes the call a start (`_vcall_more`). SX1-SX8 by name (an untyped, annotated and assigned receive, `,` after it, a
# return, a stray `)`), SX9 / SX14 / SX4 / SX5 / SX16 a method (return, assignment, untyped, annotated, wrapped start),
# SX10 / SX11 `callptr(&f)`, SX12 / SX13 / SX17 f64v4, SX15 an explicit instance, SX18 f32v4. Before: two errors on every
# SX row (this lane's D24 tests); at 41ca7d41c on SX5, SX9-SX11, SX14 (6.7.13's method / `&f` arms). Mutation (2026-10-20,
# measured):
#   M-SX1 `_vcall_more` reading every token but the terminator as an operator (the tree before) -> RED 90: SX1-SX18 on
#       five legs, two errors each
sx_src() {  # $1 row id -> source on stdout
    case "$1" in
    SX1) printf '%s' "$OPF"'fn r(): i64 { var w = mk2(41, 7) 5; return 1; }
syscall(60, r() % 256);
' ;;
    SX2) printf '%s' "$OPF"'fn r(): i64 { var w: f64v2 = mk2(41, 7), x = 1; return 1; }
syscall(60, r() % 256);
' ;;
    SX3) printf '%s' "$OPF"'fn r(): i64 { var w: f64v2; w = mk2(41, 7) 5; return 1; }
syscall(60, r() % 256);
' ;;
    SX4) printf '%s' "$OPF"'fn r(): i64 { var s: Mv = Mv { 1 }; var w = s.m2() 5; return 1; }
syscall(60, r() % 256);
' ;;
    SX5) printf '%s' "$OPF"'fn r(): i64 { var s: Mv = Mv { 1 }; var w: f64v2 = s.m2(), x = 1; return 1; }
syscall(60, r() % 256);
' ;;
    SX6) printf '%s' "$OPF"'fn f(): f64v2 { return mk2(41, 7) 5; }
fn r(): i64 { var v: f64v2 = f(); return load64(&v); }
syscall(60, r() % 256);
' ;;
    SX7) printf '%s' "$OPF"'fn f(): f64v2 { return mk2(41, 7), 1; }
fn r(): i64 { var v: f64v2 = f(); return load64(&v); }
syscall(60, r() % 256);
' ;;
    SX8) printf '%s' "$OPF"'fn r(): i64 { var w = mk2(41, 7)); return 1; }
syscall(60, r() % 256);
' ;;
    SX9) printf '%s' "$OPF"'fn f(s: Mv): f64v2 { return s.m2() 5; }
fn r(): i64 { return 1; }
syscall(60, r() % 256);
' ;;
    SX10) printf '%s' "$OPH"'fn f(): f64v2 { return callptr(&mk2, 41, 7) 5; }
fn r(): i64 { return 1; }
syscall(60, r() % 256);
' ;;
    SX11) printf '%s' "$OPH"'fn r(): i64 { var w: f64v2 = callptr(&mk2, 41, 7) 5; return 1; }
syscall(60, r() % 256);
' ;;
    SX12) printf '%s' "$OPH"'fn r(): i64 { var w: f64v4 = mk4(41) 5; return 1; }
syscall(60, r() % 256);
' ;;
    SX13) printf '%s' "$OPH"'fn f(): f64v4 { return mk4(41) 5; }
fn r(): i64 { return 1; }
syscall(60, r() % 256);
' ;;
    SX14) printf '%s' "$OPH"'fn r(): i64 { var s: Mv = Mv { 1 }; var w: f64v2; w = s.m2() 5; return 1; }
syscall(60, r() % 256);
' ;;
    SX15) printf '%s' "$OPH"'fn r(): i64 { var w = mkg<i64>(41, 7) 5; return 1; }
syscall(60, r() % 256);
' ;;
    SX16) printf '%s' "$OPF"'fn r(): i64 { var s: Mv = Mv { 1 }; var w = (s.m2()) 5; return 1; }
syscall(60, r() % 256);
' ;;
    SX17) printf '%s' "$OPH"'fn r(): i64 { var w = mk4(41), x = 1; return 1; }
syscall(60, r() % 256);
' ;;
    SX18) printf '%s' "$OPH"'fn r(): i64 { var w: f32v4 = mkf(1, 2, 3, 4) 5; return 1; }
syscall(60, r() % 256);
' ;;
    esac
}
SX_ROWS="SX1 SX2 SX3 SX4 SX5 SX6 SX7 SX8 SX9 SX10 SX11 SX12 SX13 SX14 SX15 SX16 SX17 SX18"
sx_msg() {
    case "$1" in
    SX1) echo "4:34: expected ';', got number 5";;
    SX2) echo "4:40: expected ';', got ','";;
    SX3) echo "4:44: expected ';', got number 5";;
    SX4) echo "4:52: expected ';', got number 5";;
    SX5) echo "4:58: expected ';', got ','";;
    SX6) echo "4:35: expected ';', got number 5";;
    SX7) echo "4:34: expected ';', got ','";;
    SX8) echo "4:33: expected ';', got ')'";;
    SX9) echo "4:36: expected ';', got number 5";;
    SX10) echo "9:45: expected ';', got number 5";;
    SX11) echo "9:51: expected ';', got number 5";;
    SX12) echo "9:38: expected ';', got number 5";;
    SX13) echo "9:32: expected ';', got number 5";;
    SX14) echo "9:62: expected ';', got number 5";;
    SX15) echo "9:39: expected ';', got number 5";;
    SX16) echo "4:54: expected ';', got number 5";;
    SX17) echo "9:30: expected ';', got ','";;
    SX18) echo "9:46: expected ';', got number 5";;
    esac
}


# ---- 6.7.16 (D101 A, the user's decision, 2026-10-20; issues/2026-10-20-whole-vector-call-returned-as-scalar-or-passed-to-
# integer-parameter.md): a whole vector call returned from a fn that returns no vector, or passed where a word goes, is
# refused by name (rows VA refused once; VAC1 the vector's own destinations, 161) ----------------------------------------
# VA1-VA5 the filed rows verbatim (VA5 `return mk2(41, 7) + 1;`); VA6-VA12 the return's spellings and types (a wrap, `&f`
# through callptr, an explicit instance, a chain's method, `: f64` / f64v4, an untyped fn, `: *i64`, a multiplied
# method, a wrapped start); VA13-VA18 the parameter's kinds and call paths (`f64`, a method's, a named argument, the 7th
# (stack) argument, a callee below its call, an #inline callee); VA19-VA22 a builtin's or an indirect call's argument;
# VA23 / VA24 a closure's value (an expression body, a block's `return`); VA25 / VA26 at top level; VA27 a generic's
# body at two instances (once); VA28 f32v4.
VAH="$OPH"'fn take(t): i64 { return t; }
fn takei(n: i64): i64 { return n; }
fn takef(x: f64): i64 { return 3; }
fn take7(a, b, c, d, e, f, g): i64 { return g; }
impl W { fn ti(self, n: i64): i64 { return n; } }
'
va_src() {  # $1 row id -> source on stdout
    case "$1" in
    VA1) printf '%s' "$OPF"'fn r(): i64 { return mk2(41, 7); }
syscall(60, r() % 256);
' ;;
    VA2) printf '%s' "$OPF"'fn r(): i64 { var s: Mv = Mv { 1 }; return s.m2(); }
syscall(60, r() % 256);
' ;;
    VA3) printf '%s' "$OPF"'fn takei(x: i64): i64 { return x; }
fn r(): i64 { return takei(mk2(41, 7)); }
syscall(60, r() % 256);
' ;;
    VA4) printf '%s' "$OPF"'fn take(x): i64 { return x; }
fn r(): i64 { return take(mk2(41, 7)); }
syscall(60, r() % 256);
' ;;
    VA5) printf '%s' "$OPF"'fn r(): i64 { return mk2(41, 7) + 1; }
syscall(60, r() % 256);
' ;;
    VA6) printf '%s' "$VAH"'fn r(): i64 { return ((mk2(41, 7))); }
syscall(60, r() % 256);
' ;;
    VA7) printf '%s' "$VAH"'fn r(): i64 { return callptr(&mk2, 41, 7); }
syscall(60, r() % 256);
' ;;
    VA8) printf '%s' "$VAH"'fn r(): i64 { return mkg<i64>(41, 7); }
syscall(60, r() % 256);
' ;;
    VA9) printf '%s' "$VAH"'fn r(): i64 { var x: W; return x.s.m2(); }
syscall(60, r() % 256);
' ;;
    VA10) printf '%s' "$VAH"'fn r(): f64 { return mk4(41); }
syscall(60, 0);
' ;;
    VA11) printf '%s' "$VAH"'fn r() { return mk2(41, 7); }
syscall(60, r() % 256);
' ;;
    VA12) printf '%s' "$VAH"'fn r(): *i64 { return fncall2(&mk2, 41, 7); }
syscall(60, 0);
' ;;
    VA13) printf '%s' "$VAH"'fn r(): i64 { var s: Mv = Mv { 1 }; return s.m2() * 2; }
syscall(60, r() % 256);
' ;;
    VA14) printf '%s' "$VAH"'fn r(): i64 { return (mk2(41, 7) + 1) * 2; }
syscall(60, r() % 256);
' ;;
    VA15) printf '%s' "$VAH"'fn r(): i64 { return takef(mk2(41, 7)); }
syscall(60, r() % 256);
' ;;
    VA16) printf '%s' "$VAH"'fn r(): i64 { var w: W; return w.ti(n: mk2(41, 7)); }
syscall(60, r() % 256);
' ;;
    VA17) printf '%s' "$VAH"'fn r(): i64 { return take7(1, 2, 3, 4, 5, 6, (mk2(41, 7))); }
syscall(60, r() % 256);
' ;;
    VA18) printf '%s' "$VAH"'fn r(): i64 { var s: Mv = Mv { 1 }; return later(s.m2()); }
fn later(n): i64 { return n; }
syscall(60, r() % 256);
' ;;
    VA19) printf '%s' "$VAH"'#inline
fn il(n): i64 { return n; }
fn r(): i64 { return il(mkg<i64>(41, 7)); }
syscall(60, r() % 256);
' ;;
    VA20) printf '%s' "$VAH"'fn r(): i64 { syscall(60, mk2(41, 7)); return 0; }
syscall(60, r() % 256);
' ;;
    VA21) printf '%s' "$VAH"'fn r(): i64 { var x = 0; store64(&x, (mk2(41, 7))); return x; }
syscall(60, r() % 256);
' ;;
    VA22) printf '%s' "$VAH"'fn r(): i64 { var f = |k| k; return fncall1(f, mk4(41)); }
syscall(60, r() % 256);
' ;;
    VA23) printf '%s' "$VAH"'fn r(): i64 { return callptr(&takei, callptr(&mk2, 41, 7)); }
syscall(60, r() % 256);
' ;;
    VA24) printf '%s' "$VAH"'fn r(): i64 { var f = |k| mk2(k, 7); return fncall1(f, 41); }
syscall(60, r() % 256);
' ;;
    VA25) printf '%s' "$VAH"'fn r(): i64 { var f = |k| { return (mk2(k, 7)); }; return fncall1(f, 41); }
syscall(60, r() % 256);
' ;;
    VA26) printf '%s' "$VAH"'syscall(60, mk2(41, 7));
' ;;
    VA27) printf '%s' "$VAH"'var X = take(mk2(41, 7));
syscall(60, X % 256);
' ;;
    VA28) printf '%s' "$VAH"'fn g<T>(x: T): i64 { return mk2(41, 7); }
fn r(): i64 { return g(1) + g<i32>(2); }
syscall(60, r() % 256);
' ;;
    VA29) printf '%s' "$VAH"'fn r(): i64 { return take(mkf(1, 2, 3, 4)); }
syscall(60, r() % 256);
' ;;
    esac
}
VA_ROWS="VA1 VA2 VA3 VA4 VA5 VA6 VA7 VA8 VA9 VA10 VA11 VA12 VA13 VA14 VA15 VA16 VA17 VA18 VA19 VA20 VA21 VA22 VA23 VA24 VA25 VA26 VA27 VA28 VA29"
VAM="a vector value cannot be"
va_msg() {
    case "$1" in
    VA1|VA5|VA6|VA7|VA8|VA11|VA14|VA24|VA25|VA28) echo "$VAM returned as i64 - '$(va_nm "$1")' returns a vector";;
    VA2|VA9|VA13) echo "$VAM returned as i64 - 'm2' returns a vector";;
    VA10) echo "$VAM returned as f64 - 'mk4' returns a vector";;
    VA12) echo "$VAM returned as *i64 - 'mk2' returns a vector";;
    VA3) echo "$VAM passed to an integer parameter - 'mk2' returns a vector, passed to parameter 'x' of 'takei'";;
    VA4) echo "$VAM passed to an integer parameter - 'mk2' returns a vector, passed to parameter 'x' of 'take'";;
    VA15) echo "$VAM passed to an f64 parameter - 'mk2' returns a vector, passed to parameter 'x' of 'takef'";;
    VA16) echo "$VAM passed to an integer parameter - 'mk2' returns a vector, passed to parameter 'n' of 'W.ti'";;
    VA17) echo "$VAM passed to an integer parameter - 'mk2' returns a vector, passed to parameter 'g' of 'take7'";;
    VA18) echo "$VAM passed to an integer parameter - 'm2' returns a vector, passed to parameter 'n' of 'later'";;
    VA19) echo "$VAM passed to an integer parameter - 'mkg' returns a vector, passed to parameter 'n' of 'il'";;
    VA20|VA26) echo "$VAM passed to an integer parameter - 'mk2' returns a vector, passed to 'syscall'";;
    VA21) echo "$VAM passed to an integer parameter - 'mk2' returns a vector, passed to 'store64'";;
    VA22) echo "$VAM passed to an integer parameter - 'mk4' returns a vector, passed to 'fncall1'";;
    VA23) echo "$VAM passed to an integer parameter - 'mk2' returns a vector, passed to 'callptr'";;
    VA27) echo "$VAM passed to an integer parameter - 'mk2' returns a vector, passed to parameter 't' of 'take'";;
    VA29) echo "$VAM passed to an integer parameter - 'mkf' returns a vector, passed to parameter 't' of 'take'";;
    esac
}
va_nm() { case "$1" in VA8) echo mkg;; *) echo mk2;; esac; }
# VAS: the refusal is made in sync — the statement parses on to its own end and the NEXT statement keeps its own error
# (two errors: the refusal, then "undefined variable 'zz9'"): after a declaration's argument (VAS1), a builtin's
# argument (VAS2), a `return` (VAS3), a closure's value (VAS4), at top level (VAS5).
vas_src() {  # $1 row id -> source on stdout
    case "$1" in
    VAS1) printf '%s' "$VAH"'fn r(): i64 { var x = take(mk2(41, 7)); x = zz9; return x; }
syscall(60, r() % 256);
' ;;
    VAS2) printf '%s' "$VAH"'fn r(): i64 { syscall(60, mk2(41, 7)); var y = zz9; return y; }
syscall(60, r() % 256);
' ;;
    VAS3) printf '%s' "$VAH"'fn r(): i64 { var c = 1; if (c == 1) { return mk2(41, 7); } return zz9; }
syscall(60, r() % 256);
' ;;
    VAS4) printf '%s' "$VAH"'fn r(): i64 { var f = |k| mk2(k, 7); var y = zz9; return y; }
syscall(60, r() % 256);
' ;;
    VAS5) printf '%s' "$VAH"'syscall(60, mk2(41, 7));
var Y = zz9;
syscall(60, Y);
' ;;
    esac
}
VAS_ROWS="VAS1 VAS2 VAS3 VAS4 VAS5"
vas_msg() {  # the two errors, one per line
    case "$1" in
    VAS1) echo "$VAM passed to an integer parameter - 'mk2' returns a vector, passed to parameter 't' of 'take'";;
    VAS2|VAS5) echo "$VAM passed to an integer parameter - 'mk2' returns a vector, passed to 'syscall'";;
    VAS3|VAS4) echo "$VAM returned as i64 - 'mk2' returns a vector";;
    esac
    echo "undefined variable 'zz9'"
}
# The controls: the vector's own destinations — a vector fn's return, a value-form and a `*V` parameter, a discarded
# call, a parameter its callee ignores, a closure's value-form argument, a bool's own refusal stays out (161).
vac_src() {  # $1 row id -> source on stdout; exits 161 when right
    case "$1" in
    VAC1) printf '%s' "$VAH"'fn f(a): f64v2 { return mk2(a, 7); }
fn g(s: Mv): f64v2 { return s.m2(); }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn rd(p: *f64v2): i64 { return load64(p); }
fn takev(x: f64v2): i64 { return 3; }
fn r(): i64 { var s: Mv = Mv { 1 };
  mk2(1, 2); s.m2(); callptr(&mk2, 1, 2);
  if (lanes(mk2(41, 7)) != 417) { return 1; } if (rd(mk2(41, 7)) != 41) { return 2; } if (lanes(s.m2()) != 417) { return 3; }
  if (takev(mk2(1, 2)) != 3) { return 4; } var v: f64v2 = f(41); var w: f64v2 = g(s); if (lanes(v) + lanes(w) != 834) { return 5; }
  var h = |k| lanes(mk2(k, 7)); if (fncall1(h, 41) != 417) { return 6; } return 161; }
syscall(60, r() % 256);
' ;;
    esac
}
VAC_ROWS="VAC1"


# ---- 6.7.16 (D100 A, the user's decision, 2026-10-20; issues/2026-10-20-vector-call-as-later-operand-or-compound-right-
# side-uses-first-word.md): a vector call as an operand anywhere, or as the whole of a word slot, is refused by name (rows
# VO refused once; VOF the filed repro's two-statement row, refused once per statement; VOS the next statement's error
# kept; VOC1 the controls, 161) -----------------------------------------------------------------------------------------
# VO1-VO7 the filed rows verbatim (the issue's repro file, `r`'s body per row; VO6's two statements are VOF); VO8 `rd(mk2(41,
# 7) + 1)` into a `*f64v2` (139 / cx 221 / PE 5 before); VO9-VO12 unary operators (`-` `!` `~` `*`); VO13 / VO14 a
# `return`'s and a condition's later operand; VO15-VO18 a compound right side through a field, a `*T`, an element, `-=`;
# VO19 a wrapped later operand; VO20 a closure's expression body; VO21-VO24 at top level (the zone, after the first
# statement, a compound assignment, a builtin's argument expression); VO25-VO28 an explicit instance, a chain's method,
# f64v4, f32v4; VO29 into an `f64`; VO30 inside a term; VO31 `&&`; VO32-VO36 a whole call stored into a field, through a
# `*i64`, an element, `*(&x)`, an untyped pointer; VO37-VO46 a whole call as a condition (`if`, `while`, a `for`'s,
# `elif`, `switch`), an index, a range bound, a struct literal's field (positional, named), `match`'s subject; VO47 a
# top-level field store; VO48 a closure's expression body followed by a stray token (the parse's one error, as SX);
# VO49-VO60 (the s16 review) a whole call as a tuple literal's element — an untyped and an annotated declaration's, an
# assignment's, a tuple argument's, the second element, a multi-value fn's and a method's `return`, a method's call as a
# middle element, a wrapped explicit instance, the declaration zone, after the first statement (`callptr(&mk2, ..)`), a
# tuple field's store (f64v4); VO61-VO67 (the s16 review) a whole call stored into a field or an element of a CALL's
# result — `gp().b`, `callptr(&gp).b`, `gi()[0]`, an explicit instance's `gpg<i64>(1).b`, an inferred generic's (f64v4),
# `fncall0(&gp).b` from a method, after the first statement; VO68-VO73 (6.7.17) a call as an operand in a multi-value
# `return`'s element — a declared fn's first element, a three-value fn's wrapped `* 2`, a method's `1 + s.m2()`, an
# undeclared fn's (D101's words before), wrapped through `callptr`, an explicit instance under unary `-`.
VOH="$OPH"'fn take(t): i64 { return t; }
fn rd(p: *f64v2): i64 { return load64(p); }
struct Pt { a; b; }
'
VOG="$VOH"'var GP: Pt = Pt { 1, 2 };
var GX: i64[2];
fn gp(): *Pt { return &GP; }
fn gi(): *i64 { return &GX; }
fn gpg<T>(x: T): *Pt { return &GP; }
'
vo_src() {  # $1 row id -> source on stdout
    case "$1" in
    VO1|VO2|VO3|VO4|VO5|VO7) printf '%s' 'include "lib/fnptr.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct Mv { k; }
impl Mv { fn m2(self): f64v2 { return mk2(41, 7); } }
'"$(vo_filed "$1")"'
syscall(60, r() % 256);
' ;;
    VO8) printf '%s' "$VOH"'fn r(): i64 { return rd(mk2(41, 7) + 1); }
syscall(60, r() % 256);
' ;;
    VO9) printf '%s' "$VOH"'fn r(): i64 { var x = 0; x = -mk2(41, 7); return x; }
syscall(60, r() % 256);
' ;;
    VO10) printf '%s' "$VOH"'fn r(): i64 { var x = 0; x = !mk2(41, 7); return x; }
syscall(60, r() % 256);
' ;;
    VO11) printf '%s' "$VOH"'fn r(): i64 { return ~mk2(41, 7); }
syscall(60, r() % 256);
' ;;
    VO12) printf '%s' "$VOH"'fn r(): i64 { var q = *mk2(41, 7); return q; }
syscall(60, r() % 256);
' ;;
    VO13) printf '%s' "$VOH"'fn r(): i64 { return 1 + mk2(41, 7); }
syscall(60, r() % 256);
' ;;
    VO14) printf '%s' "$VOH"'fn r(): i64 { if (1 + mk2(41, 7) > 0) { return 1; } return 2; }
syscall(60, r() % 256);
' ;;
    VO15) printf '%s' "$VOH"'fn r(): i64 { var p: Pt = Pt { 1, 2 }; p.a += mk2(41, 7); return p.a; }
syscall(60, r() % 256);
' ;;
    VO16) printf '%s' "$VOH"'fn r(): i64 { var x = 1; var p: *i64 = &x; *p += mk2(41, 7); return x; }
syscall(60, r() % 256);
' ;;
    VO17) printf '%s' "$VOH"'fn r(): i64 { var a: i64[4]; a[0] = 1; a[0] += mk2(41, 7); return a[0]; }
syscall(60, r() % 256);
' ;;
    VO18) printf '%s' "$VOH"'fn r(): i64 { var x = 50; x -= mk2(41, 7); return x; }
syscall(60, r() % 256);
' ;;
    VO19) printf '%s' "$VOH"'fn r(): i64 { var x = 0; x = 2 * ((mk2(41, 7))); return x; }
syscall(60, r() % 256);
' ;;
    VO20) printf '%s' "$VOH"'fn r(): i64 { var f = |k| k + mk2(k, 7); return fncall1(f, 41); }
syscall(60, r() % 256);
' ;;
    VO21) printf '%s' "$VOH"'var X = 1 + mk2(41, 7);
syscall(60, X % 256);
' ;;
    VO22) printf '%s' "$VOH"'syscall(1, 1, "", 0);
var X = 1 + mk2(41, 7);
syscall(60, X % 256);
' ;;
    VO23) printf '%s' "$VOH"'var X = 0;
syscall(1, 1, "", 0);
X += mk2(41, 7);
syscall(60, X % 256);
' ;;
    VO24) printf '%s' "$VOH"'syscall(60, mk2(41, 7) % 256);
' ;;
    VO25) printf '%s' "$VOH"'fn r(): i64 { var x: i64 = 1 + mkg<i64>(41, 7); return x; }
syscall(60, r() % 256);
' ;;
    VO26) printf '%s' "$VOH"'fn r(): i64 { var w: W; var x = 0; x = 1 + w.s.m2(); return x; }
syscall(60, r() % 256);
' ;;
    VO27) printf '%s' "$VOH"'fn r(): i64 { var x = 0; x += mk4(41); return x; }
syscall(60, r() % 256);
' ;;
    VO28) printf '%s' "$VOH"'fn r(): i64 { var x = 1 + mkf(1, 2, 3, 4); return x; }
syscall(60, r() % 256);
' ;;
    VO29) printf '%s' "$VOH"'fn r(): i64 { var x: f64 = 1.0 + mk2(41, 7); return 1; }
syscall(60, r() % 256);
' ;;
    VO30) printf '%s' "$VOH"'fn r(): i64 { var x = 0; x = 1 + mk2(41, 7) * 2; return x; }
syscall(60, r() % 256);
' ;;
    VO31) printf '%s' "$VOH"'fn r(): i64 { if (1 && callptr(&mk2, 41, 7)) { return 1; } return 2; }
syscall(60, r() % 256);
' ;;
    VO32) printf '%s' "$VOH"'fn r(): i64 { var p: Pt = Pt { 1, 2 }; p.a = mk2(41, 7); return p.a; }
syscall(60, r() % 256);
' ;;
    VO33) printf '%s' "$VOH"'fn r(): i64 { var x = 1; var p: *i64 = &x; *p = mk2(41, 7); return x; }
syscall(60, r() % 256);
' ;;
    VO34) printf '%s' "$VOH"'fn r(): i64 { var a: i64[4]; a[1] = mk2(41, 7); return a[1]; }
syscall(60, r() % 256);
' ;;
    VO35) printf '%s' "$VOH"'fn r(): i64 { var x = 1; *(&x) = mk2(41, 7); return x; }
syscall(60, r() % 256);
' ;;
    VO36) printf '%s' "$VOH"'fn r(): i64 { var x = 1; var q = &x; *q = (mk2(41, 7)); return x; }
syscall(60, r() % 256);
' ;;
    VO37) printf '%s' "$VOH"'fn r(): i64 { if (mk2(41, 7)) { return 1; } return 2; }
syscall(60, r() % 256);
' ;;
    VO38) printf '%s' "$VOH"'fn r(): i64 { var s: Mv = Mv { 1 }; var n = 0; while (s.m2()) { n = n + 1; break; } return n; }
syscall(60, r() % 256);
' ;;
    VO39) printf '%s' "$VOH"'fn r(): i64 { var n = 0; for (var i = 0; mk2(1, 0); i = i + 1) { n = n + 1; break; } return n; }
syscall(60, r() % 256);
' ;;
    VO40) printf '%s' "$VOH"'fn r(): i64 { var c = 0; if (c == 1) { return 1; } elif (mk2(41, 7)) { return 2; } return 3; }
syscall(60, r() % 256);
' ;;
    VO41) printf '%s' "$VOH"'fn r(): i64 { switch (mk2(41, 7)) { case 41: return 1; default: return 2; } return 3; }
syscall(60, r() % 256);
' ;;
    VO42) printf '%s' "$VOH"'fn r(): i64 { var a: i64[4]; return a[mk2(0, 7)]; }
syscall(60, r() % 256);
' ;;
    VO43) printf '%s' "$VOH"'fn r(): i64 { var n = 0; for i in 0..mk2(3, 7) { n = n + 1; } return n; }
syscall(60, r() % 256);
' ;;
    VO44) printf '%s' "$VOH"'fn r(): i64 { var p: Pt = Pt { mk2(41, 7), 1 }; return p.a; }
syscall(60, r() % 256);
' ;;
    VO45) printf '%s' "$VOH"'fn r(): i64 { var p: Pt = Pt { a: 1, b: mkg<i64>(41, 7) }; return p.b; }
syscall(60, r() % 256);
' ;;
    VO46) printf '%s' "$VOH"'fn r(): i64 { match mk2(41, 7) { 41 => { return 1; } _ => { return 2; } } return 3; }
syscall(60, r() % 256);
' ;;
    VO47) printf '%s' "$VOH"'var GP: Pt = Pt { 1, 2 };
syscall(1, 1, "", 0);
GP.a = mk2(41, 7);
syscall(60, GP.a % 256);
' ;;
    VO48) printf '%s' "$VOH"'fn r(): i64 { var f = |k| mk2(k, 7) 5; return 1; }
syscall(60, r() % 256);
' ;;
    VO49) printf '%s' "$VOH"'fn r(): i64 { var t = (mk2(41, 7), 3); return t.0; }
syscall(60, r() % 256);
' ;;
    VO50) printf '%s' "$VOH"'fn r(): i64 { var t: (i64, i64) = (mk2(41, 7), 3); return t.0; }
syscall(60, r() % 256);
' ;;
    VO51) printf '%s' "$VOH"'fn r(): i64 { var t: (i64, i64) = (1, 2); t = (mk2(41, 7), 3); return t.0; }
syscall(60, r() % 256);
' ;;
    VO52) printf '%s' "$VOH"'fn tk(t: (i64, i64)): i64 { return t.0; }
fn r(): i64 { return tk((mk2(41, 7), 3)); }
syscall(60, r() % 256);
' ;;
    VO53) printf '%s' "$VOH"'fn r(): i64 { var t = (3, mk2(41, 7)); return t.1; }
syscall(60, r() % 256);
' ;;
    VO54) printf '%s' "$VOH"'fn two(): (i64, i64) { return (mk2(41, 7), 3); }
fn r(): i64 { var a, b = two(); return a; }
syscall(60, r() % 256);
' ;;
    VO55) printf '%s' "$VOH"'impl Pt { fn tw(self): (i64, i64) { return (3, mk2(41, 7)); } }
fn r(): i64 { var p = Pt { 1, 2 }; var a, b = p.tw(); return b; }
syscall(60, r() % 256);
' ;;
    VO56) printf '%s' "$VOH"'fn r(): i64 { var s: Mv = Mv { 1 }; var t = (1, s.m2(), 3); return t.1; }
syscall(60, r() % 256);
' ;;
    VO57) printf '%s' "$VOH"'fn r(): i64 { var t = ((mkg<i64>(41, 7)), 3); return t.0; }
syscall(60, r() % 256);
' ;;
    VO58) printf '%s' "$VOH"'var GT = (mk2(41, 7), 3);
syscall(60, GT.0 % 256);
' ;;
    VO59) printf '%s' "$VOH"'syscall(1, 1, "", 0);
var GT: (i64, i64) = (3, callptr(&mk2, 41, 7));
syscall(60, GT.1 % 256);
' ;;
    VO60) printf '%s' "$VOH"'struct St { t: (i64, i64); }
fn r(): i64 { var s: St; s.t = (mk4(41), 3); return s.t.0; }
syscall(60, r() % 256);
' ;;
    VO61) printf '%s' "$VOG"'fn r(): i64 { gp().b = mk2(41, 7); return GP.b; }
syscall(60, r() % 256);
' ;;
    VO62) printf '%s' "$VOG"'fn r(): i64 { callptr(&gp).b = mk2(41, 7); return GP.b; }
syscall(60, r() % 256);
' ;;
    VO63) printf '%s' "$VOG"'fn r(): i64 { gi()[0] = mk2(41, 7); return GX[0]; }
syscall(60, r() % 256);
' ;;
    VO64) printf '%s' "$VOG"'fn r(): i64 { gpg<i64>(1).b = mk2(41, 7); return GP.b; }
syscall(60, r() % 256);
' ;;
    VO65) printf '%s' "$VOG"'fn r(): i64 { gpg(1).a = mk4(41); return GP.a; }
syscall(60, r() % 256);
' ;;
    VO66) printf '%s' "$VOG"'fn r(): i64 { var s: Mv = Mv { 1 }; fncall0(&gp).b = s.m2(); return GP.b; }
syscall(60, r() % 256);
' ;;
    VO67) printf '%s' "$VOG"'syscall(1, 1, "", 0);
gp().b = mk2(41, 7);
syscall(60, GP.b % 256);
' ;;
    VO68) printf '%s' "$VOH"'fn two(): (i64, i64) { return (mk2(41, 7) + 1, 3); }
fn r(): i64 { var a, b = two(); return a + b; }
syscall(60, r() % 256);
' ;;
    VO69) printf '%s' "$VOH"'fn two(): (i64, i64, i64) { return (1, ((mk2(41, 7))) * 2, 3); }
fn r(): i64 { var a, b, c = two(); return a + b + c; }
syscall(60, r() % 256);
' ;;
    VO70) printf '%s' "$VOH"'impl Pt { fn tw(self): (i64, i64) { var s: Mv = Mv { 1 }; return (3, 1 + s.m2()); } }
fn r(): i64 { var p = Pt { 1, 2 }; var a, b = p.tw(); return b; }
syscall(60, r() % 256);
' ;;
    VO71) printf '%s' "$VOH"'fn two() { return (mk2(41, 7) + 1, 3); }
fn r(): i64 { var a, b = two(); return a + b; }
syscall(60, r() % 256);
' ;;
    VO72) printf '%s' "$VOH"'fn two() { return ((callptr(&mk2, 41, 7) + 1), 3); }
fn r(): i64 { var a, b = two(); return a + b; }
syscall(60, r() % 256);
' ;;
    VO73) printf '%s' "$VOH"'fn two(): (i64, i64) { return (3, -mkg<i64>(41, 7)); }
fn r(): i64 { var a, b = two(); return a + b; }
syscall(60, r() % 256);
' ;;
    esac
}
vo_filed() {  # the issue's `r` per row
    case "$1" in
    VO1) printf '%s' 'fn r(): i64 { var x: i64 = 1 + mk2(41, 7); return x; }' ;;
    VO2) printf '%s' 'fn r(): i64 { var x = 0; x = 1 + mk2(41, 7); return x; }' ;;
    VO3) printf '%s' 'fn r(): i64 { var w = 1 + mk2(41, 7); return w; }' ;;
    VO4) printf '%s' 'fn r(): i64 { var x = 0; x += mk2(41, 7); return x; }' ;;
    VO5) printf '%s' 'fn r(): i64 { var s: Mv = Mv { 1 }; var x = 0; x += s.m2(); return x; }' ;;
    VO6) printf '%s' 'fn r(): i64 { var x = 0; x += callptr(&mk2, 41, 7); x += (mk2(41, 7)); return x; }' ;;
    VO7) printf '%s' 'fn take(t): i64 { return t; }
fn r(): i64 { return take(mk2(41, 7) + 1); }' ;;
    esac
}
VO_ROWS="VO1 VO2 VO3 VO4 VO5 VO7 VO8 VO9 VO10 VO11 VO12 VO13 VO14 VO15 VO16 VO17 VO18 VO19 VO20 VO21 VO22 VO23 VO24 VO25 VO26 VO27 VO28 VO29 VO30 VO31 VO32 VO33 VO34 VO35 VO36 VO37 VO38 VO39 VO40 VO41 VO42 VO43 VO44 VO45 VO46 VO47 VO48 VO49 VO50 VO51 VO52 VO53 VO54 VO55 VO56 VO57 VO58 VO59 VO60 VO61 VO62 VO63 VO64 VO65 VO66 VO67 VO68 VO69 VO70 VO71 VO72 VO73"
VOD="vector return type does not match the declared type"
VOA="vector return type does not match the assigned variable"
vo_msg() {
    case "$1" in
    VO2|VO4|VO5|VO9|VO10|VO15|VO16|VO17|VO18|VO19|VO23|VO26|VO27|VO30|VO32|VO33|VO34|VO35|VO36|VO47|VO51|VO60|VO61|VO62|VO63|VO64|VO65|VO66|VO67) echo "$VOA";;
    VO11|VO13|VO20) echo "a vector value cannot be returned as i64 - 'mk2' returns a vector";;
    VO48) echo "12:37: expected ';', got number 5";;
    *) echo "$VOD";;
    esac
}
# VOF: the filed table's row 6 verbatim — two statements, each refused at its own call (two errors); VOS: the refusal is
# made in sync — the NEXT statement keeps its own error (two errors: the refusal, then "undefined variable 'zz9'"): after a
# declaration's later operand (VOS1), a compound assignment (VOS2), a field store (VOS3), a condition (VOS4), at top
# level (VOS5).
vos_src() {  # $1 row id -> source on stdout
    case "$1" in
    VOF) printf '%s' 'include "lib/fnptr.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct Mv { k; }
impl Mv { fn m2(self): f64v2 { return mk2(41, 7); } }
'"$(vo_filed VO6)"'
syscall(60, r() % 256);
' ;;
    VOS1) printf '%s' "$VOH"'fn r(): i64 { var x: i64 = 1 + mk2(41, 7); x = zz9; return x; }
syscall(60, r() % 256);
' ;;
    VOS2) printf '%s' "$VOH"'fn r(): i64 { var x = 0; x += mk2(41, 7); x = zz9; return x; }
syscall(60, r() % 256);
' ;;
    VOS3) printf '%s' "$VOH"'fn r(): i64 { var p: Pt = Pt { 1, 2 }; p.a = mk2(41, 7); p.b = zz9; return p.b; }
syscall(60, r() % 256);
' ;;
    VOS4) printf '%s' "$VOH"'fn r(): i64 { if (mk2(41, 7)) { return 1; } return zz9; }
syscall(60, r() % 256);
' ;;
    VOS5) printf '%s' "$VOH"'var X = 1 + mk2(41, 7);
var Y = zz9;
syscall(60, X + Y);
' ;;
    esac
}
VOS_ROWS="VOF VOS1 VOS2 VOS3 VOS4 VOS5"
vos_msg() {  # the two errors, one per line
    case "$1" in
    VOF) echo "5:31: $VOA"; echo "5:59: $VOA"; return 0;;
    VOS2|VOS3) echo "$VOA";;
    *) echo "$VOD";;
    esac
    echo "undefined variable 'zz9'"
}
# The controls: a vector call where a vector goes, and the bound vector's lanes in every operator and slot (161); VOC2 a
# vector call inside a tuple literal element's argument, a multi-value fn's element from a vector parameter (161); VOC3
# a call result's field and element from a vector's lane (161); VOC4 (6.7.17) a multi-value `return`'s element an
# operator over a vector's lane, declared and undeclared (161).
voc_src() {  # $1 row id -> source on stdout; exits 161 when right
    case "$1" in
    VOC1) printf '%s' "$VOH"'fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn r(): i64 { var s: Mv = Mv { 1 }; var p: Pt = Pt { 1, 2 }; var a: i64[4]; a[0] = 0;
  mk2(1, 2); s.m2(); var w = mk2(41, 7); var v: f64v2 = s.m2(); var x = 0;
  x = 1 + load64(&w); x += load64(&v + 8); p.a = load64(&w); a[0] += load64(&v + 8); a[1] = lanes(mk2(41, 7)) - lanes(s.m2());
  if (x != 49 || p.a != 41 || a[0] != 7 || a[1] != 0) { return 1; }
  if (lanes(mk2(4, 1)) + rd(mk2(41, 7)) != 82) { return 2; }
  var f = |k| lanes(mk2(k, 7)) + 1; if (fncall1(f, 41) != 418) { return 3; } return 161; }
syscall(60, r() % 256);
' ;;
    VOC2) printf '%s' "$VOH"'fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn two(w: f64v2): (i64, i64) { return (lanes(w), load64(&w + 8)); }
fn r(): i64 { var t = (lanes(mk2(4, 1)), 3); var a, b = two(mk2(41, 7)); var u: (i64, i64) = (1, 2); u = (lanes(mk2(1, 6)), b);
  if (t.0 != 41 || t.1 != 3 || a != 417 || b != 7 || u.0 != 16 || u.1 != 7) { return 1; } return 161; }
syscall(60, r() % 256);
' ;;
    VOC4) printf '%s' "$VOH"'fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn two(): (i64, i64) { var w = mk2(41, 7); return (lanes(mk2(1, 6)) + 1, load64(&w) + 2); }
fn tw3() { return ((lanes(mk2(4, 1)) + 1), 3); }
fn r(): i64 { var a, b = two(); var c, d = tw3(); if (a != 17 || b != 43 || c != 42 || d != 3) { return 1; } return 161; }
syscall(60, r() % 256);
' ;;
    VOC3) printf '%s' "$VOG"'fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn r(): i64 { var w = mk2(41, 7); gp().b = load64(&w); gi()[1] = lanes(mk2(1, 6)); callptr(&gp).a = load64(&w + 8);
  if (GP.b != 41 || GX[1] != 16 || GP.a != 7) { return 1; } return 161; }
syscall(60, r() % 256);
' ;;
    esac
}
VOC_ROWS="VOC1 VOC2 VOC3 VOC4"

# ---- 6.7.17 (met landing D24): a refused compound assignment is its whole right side's one error (rows VCO refused once;
# VCO7 / VCO8 an operand inside the right side keeps its own, two errors) ----------------------------------------------
# VCO1-VCO6 `op = mk2(..)` on a vector local, through a `*f64v2`, `*(&w)` wrapped, a struct local, through a `*Pt`, `**qq`
# of a `**Pt`, an array.
VCOH='fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
struct Pt { a; b; }
'
vco_src() {  # $1 row id -> source on stdout
    case "$1" in
    VCO1) printf '%s' "$VCOH"'fn r(): i64 { var w: f64v2 = mk2(1, 2); w += mk2(1, 1); return 0; }
syscall(60, r());
' ;;
    VCO2) printf '%s' "$VCOH"'fn r(): i64 { var w: f64v2 = mk2(1, 2); var pv: *f64v2 = &w; *pv += mk2(1, 1); return 0; }
syscall(60, r());
' ;;
    VCO3) printf '%s' "$VCOH"'fn r(): i64 { var w: f64v2 = mk2(1, 2); *(&w) -= (mk2(1, 1)); return 0; }
syscall(60, r());
' ;;
    VCO4) printf '%s' "$VCOH"'fn r(): i64 { var p: Pt; p += mk2(1, 1); return 0; }
syscall(60, r());
' ;;
    VCO5) printf '%s' "$VCOH"'fn r(): i64 { var p: Pt; var q: *Pt = &p; var qq: **Pt = &q; **qq *= mk2(1, 1); return 0; }
syscall(60, r());
' ;;
    VCO6) printf '%s' "$VCOH"'fn r(): i64 { var a: i64[4]; a += mk2(1, 1); return 0; }
syscall(60, r());
' ;;
    VCO7) printf '%s' "$VCOH"'fn r(): i64 { var w: f64v2 = mk2(1, 2); w += 1 + mk2(1, 1); return 0; }
syscall(60, r());
' ;;
    VCO8) printf '%s' "$VCOH"'fn r(): i64 { var p: Pt; var q: *Pt = &p; *q += mk2(1, 1) * 2; return 0; }
syscall(60, r());
' ;;
    esac
}
VCO_ROWS="VCO1 VCO2 VCO3 VCO4 VCO5 VCO6"
VCO2_ROWS="VCO7 VCO8"
vco_msg() {
    case "$1" in
    VCO1|VCO3) echo "compound assignment to vector 'w' is refused";;
    VCO2) echo "compound assignment to the vector 'pv' points at is refused";;
    VCO4) echo "compound assignment to struct 'p' is refused";;
    VCO5) echo "compound assignment to the struct '*qq' points at is refused";;
    VCO6) echo "compound assignment to array 'a' is refused";;
    VCO7) echo "compound assignment to vector 'w' is refused"; echo "vector return type does not match the assigned variable";;
    VCO8) echo "compound assignment to the struct 'q' points at is refused"; echo "vector return type does not match the assigned variable";;
    esac
}

# ---- 6.7.17 (met landing D23): a refusal that keeps away from its source's own error does so after an earlier error in
# the file too (rows VER: exactly the two errors, the earlier one and the source's own, no third line and no warning) ---
# VER1 an assignment's source (`_vrcv_other`), VER2 / VER3 a declaration's, wrapped (`_scv_err`), VER4 a store through a
# `*f64v2` (D23's receive), VER5 the earlier error in another fn, VER6 a value-form argument's `*E` (`_sar_dsrc`), VER7
# the declaration zone's typed-pointer warning (`_gvi_scalar`); VER8 / VER9 the controls: a genuine refusal after an
# earlier error is still said.
VERH='fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
'
ver_src() {  # $1 row id -> source on stdout
    case "$1" in
    VER1) printf '%s' "$VERH"'fn r(): i64 { var y = zz8; var w: f64v2 = mk2(1, 2); w = zz9; return 0; }
syscall(60, r());
' ;;
    VER2) printf '%s' "$VERH"'fn r(): i64 { var y = zz8; var w: f64v2 = zz9; return 0; }
syscall(60, r());
' ;;
    VER3) printf '%s' "$VERH"'fn r(): i64 { var y = zz8; var w: f64v2 = ((zz9)); return 0; }
syscall(60, r());
' ;;
    VER4) printf '%s' "$VERH"'fn r(): i64 { var y = zz8; var w: f64v2 = mk2(1, 2); var pv: *f64v2 = &w; *pv = zz9; return 0; }
syscall(60, r());
' ;;
    VER5) printf '%s' "$VERH"'fn q(): i64 { return zz8; }
fn r(): i64 { var w: f64v2 = mk2(1, 2); w = zz9; return 0; }
syscall(60, r());
' ;;
    VER6) printf '%s' "$VERH"'fn r(): i64 { var y = zz8; return lanes(*zz9); }
syscall(60, r());
' ;;
    VER7) printf '%s' 'var Y = zz8;
var G: *i64 = zz9;
syscall(60, 0);
' ;;
    VER8) printf '%s' "$VERH"'fn r(): i64 { var y = zz8; var w: f64v2 = mk2(1, 2); w = 5; return 0; }
syscall(60, r());
' ;;
    VER9) printf '%s' "$VERH"'fn r(): i64 { var y = zz8; var x = 0; return lanes(*x); }
syscall(60, r());
' ;;
    esac
}
VER_ROWS="VER1 VER2 VER3 VER4 VER5 VER6 VER7 VER8 VER9"
ver_msg() {  # the two lines, one per line
    case "$1" in
    VER5) echo "undefined variable 'zz8'"; echo "undefined variable 'zz9'";;
    VER8) echo "undefined variable 'zz8'"; echo "a value-form vector local is assigned only from";;
    VER9) echo "undefined variable 'zz8'"; echo "a value-form vector argument to 'lanes'";;
    *) echo "undefined variable 'zz8'"; echo "undefined variable 'zz9'";;
    esac
}
# ... each refused with exactly `ver_msg`'s two lines as its whole error / warning list, no artifact.
refuse_ver_all() {  # $1 leg label  $2 compiler
    for row in $VER_ROWS; do
        ver_src "$row" > "$W/ve.cyr"
        rc=0
        "$2" < "$W/ve.cyr" > "$W/ve.out" 2>"$W/ve.err" || rc=$?
        nrefuse=$((nrefuse+1))
        m1=$(ver_msg "$row" | sed -n 1p)
        m2=$(ver_msg "$row" | sed -n 2p)
        nl=$(grep -cE '^(error|warning)' "$W/ve.err" 2>/dev/null || true)
        if [ "$nl" != 2 ]; then bad "$1 $row: $nl error / warning lines (want 2; rc=$rc: $(grep -E '^(error|warning)' "$W/ve.err" | tr '\n' ' ' | cut -c1-300))"
        elif ! grep -E '^(error|warning)' "$W/ve.err" | sed -n 1p | grep -qF -- "$m1"; then bad "$1 $row: first line not '$m1'"
        elif ! grep -E '^(error|warning)' "$W/ve.err" | sed -n 2p | grep -qF -- "$m2"; then bad "$1 $row: second line not '$m2'"
        elif [ -s "$W/ve.out" ]; then bad "$1 $row: reported but still emitted an artifact"
        else good "$1 $row: the two errors alone"; fi
    done
}

# ---- 6.7.17 (D24 A, the user's decision, 2026-10-22; issues/2026-10-21-vector-value-in-a-word-position-beyond-d100-
# d101.md row 2): a vector value that is no call — a local, a by-value parameter, a capture, a dereference of a pointer to
# a vector — is refused in every word slot D100 / D101 refuse the call in, naming it (rows VL refused once; VLS the next
# statement's error kept; VLC the vector's own uses, 161) ---------------------------------------------------------------
# VL1-VL5 the filed row 2 verbatim; VL6-VL13 a parameter's kinds (i64, f64, cstring, a method's named one, wrapped) and a
# builtin's / an indirect call's argument; VL14-VL16 a closure's value; VL17-VL23 an assignment, a compound right side,
# unary `-` `!` `~` `*`, a binary operand; VL24-VL27 a store into a field, an element, through a `*i64`, `*(&x)`;
# VL28-VL36 a condition (`while`, `elif`, a `for`'s, `switch`, `match`), an index, a range bound, a struct literal's
# field (positional, named); VL37-VL39 a tuple literal's element (its own words: wrapped and `*pv` too, which compiled);
# VL40 / VL41 a comparison's and `&&`'s operand; VL42-VL48 a declaration annotated `f64`, `u8`, `*i64`, `*f64v2`,
# `cstring`, `u128`, wrapped; VL49-VL54 a dereference of a pointer to a vector (`*pv`, `*(&w)`, `**ppv`); VL55 into a
# `*i64` local; VL56 / VL57 a by-value vector parameter; VL58 a generic's parameter; VL59 a closure's capture; VL60 a
# `for` step; VL61-VL65 top level (the declaration zone, after the first statement, an assignment, a builtin's
# argument, `*(&GW)` of a vector global); VL66-VL68 f64v4, i32v4, f32v4; VL69 / VL70 a bool's own words kept.
VLF='fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn rd(p): i64 { return load64(p) * 10 + load64(p + 8); }
fn take(t): i64 { return t; }
'
VLH='include "lib/fnptr.cyr"
include "lib/alloc.cyr"
'"$VLF"'fn takei(n: i64): i64 { return n; }
fn takef(x: f64): i64 { return 3; }
fn takec(c: cstring): i64 { return 3; }
fn g<T>(x: T): i64 { return 1; }
struct Pt { a; b; }
impl Pt { fn ti(self, n: i64): i64 { return n; } }
'
vl_src() {  # $1 row id -> source on stdout
    case "$1" in
    VL1) printf '%s' "$VLF"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return take(w); }
syscall(60, r());
' ;;
    VL2) printf '%s' "$VLF"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return w; }
syscall(60, r());
' ;;
    VL3) printf '%s' "$VLF"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x: i64 = w; return x; }
syscall(60, r());
' ;;
    VL4) printf '%s' "$VLF"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return 1 + w; }
syscall(60, r());
' ;;
    VL5) printf '%s' "$VLF"'fn r(): i64 { var w: f64v2 = mk2(4, 7); if (w) { return 4; } return 9; }
syscall(60, r());
' ;;
    VL6) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return takei(w); }
syscall(60, r() % 256);
' ;;
    VL7) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return takef(w); }
syscall(60, r() % 256);
' ;;
    VL8) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return takec(w); }
syscall(60, r() % 256);
' ;;
    VL9) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var p: Pt; return p.ti(n: w); }
syscall(60, r() % 256);
' ;;
    VL10) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return take(((w))); }
syscall(60, r() % 256);
' ;;
    VL11) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); syscall(60, w); return 0; }
syscall(60, r() % 256);
' ;;
    VL12) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x = 0; store64(&x, w); return x; }
syscall(60, r() % 256);
' ;;
    VL13) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var f = |k| k; return fncall1(f, w); }
syscall(60, r() % 256);
' ;;
    VL14) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var f = |k| w; return fncall1(f, 1); }
syscall(60, r() % 256);
' ;;
    VL15) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var f = |k| k + w; return fncall1(f, 1); }
syscall(60, r() % 256);
' ;;
    VL16) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var f = |k| { return w; }; return fncall1(f, 1); }
syscall(60, r() % 256);
' ;;
    VL17) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x = 0; x = w; return x; }
syscall(60, r() % 256);
' ;;
    VL18) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x = 0; x += w; return x; }
syscall(60, r() % 256);
' ;;
    VL19) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x = -w; return x; }
syscall(60, r() % 256);
' ;;
    VL20) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x = 0; x = !w; return x; }
syscall(60, r() % 256);
' ;;
    VL21) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return ~w; }
syscall(60, r() % 256);
' ;;
    VL22) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x = *w; return x; }
syscall(60, r() % 256);
' ;;
    VL23) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return w * 2; }
syscall(60, r() % 256);
' ;;
    VL24) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var p: Pt; p.a = w; return p.a; }
syscall(60, r() % 256);
' ;;
    VL25) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var a: i64[4]; a[0] = w; return a[0]; }
syscall(60, r() % 256);
' ;;
    VL26) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x = 1; var p: *i64 = &x; *p = w; return x; }
syscall(60, r() % 256);
' ;;
    VL27) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x = 1; *(&x) = w; return x; }
syscall(60, r() % 256);
' ;;
    VL28) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); while (w) { break; } return 0; }
syscall(60, r() % 256);
' ;;
    VL29) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var c = 0; if (c == 1) { return 1; } elif (w) { return 2; } return 3; }
syscall(60, r() % 256);
' ;;
    VL30) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); for (var i = 0; w; i = i + 1) { break; } return 0; }
syscall(60, r() % 256);
' ;;
    VL31) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); switch (w) { default: return 2; } return 3; }
syscall(60, r() % 256);
' ;;
    VL32) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); match w { _ => { return 2; } } return 3; }
syscall(60, r() % 256);
' ;;
    VL33) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var a: i64[4]; return a[w]; }
syscall(60, r() % 256);
' ;;
    VL34) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var n = 0; for i in 0..w { n = n + 1; } return n; }
syscall(60, r() % 256);
' ;;
    VL35) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var p: Pt = Pt { w, 1 }; return p.a; }
syscall(60, r() % 256);
' ;;
    VL36) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var p: Pt = Pt { a: 1, b: w }; return p.b; }
syscall(60, r() % 256);
' ;;
    VL37) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var t = (w, 3); return 0; }
syscall(60, r() % 256);
' ;;
    VL38) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var t: (i64, i64) = (1, 2); t = (3, (w)); return 0; }
syscall(60, r() % 256);
' ;;
    VL39) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var pv: *f64v2 = &w; var t = (*pv, 3); return 0; }
syscall(60, r() % 256);
' ;;
    VL40) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); if (w == 1) { return 1; } return 2; }
syscall(60, r() % 256);
' ;;
    VL41) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); if (1 && w) { return 1; } return 2; }
syscall(60, r() % 256);
' ;;
    VL42) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x: f64 = w; return 0; }
syscall(60, r() % 256);
' ;;
    VL43) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x: u8 = w; return x; }
syscall(60, r() % 256);
' ;;
    VL44) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x: *i64 = w; return 0; }
syscall(60, r() % 256);
' ;;
    VL45) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x: *f64v2 = w; return 0; }
syscall(60, r() % 256);
' ;;
    VL46) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x: cstring = w; return 0; }
syscall(60, r() % 256);
' ;;
    VL47) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x: u128 = w; return 0; }
syscall(60, r() % 256);
' ;;
    VL48) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x: i64 = (w); return x; }
syscall(60, r() % 256);
' ;;
    VL49) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var pv: *f64v2 = &w; var x: i64 = *pv; return x; }
syscall(60, r() % 256);
' ;;
    VL50) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var pv: *f64v2 = &w; return take(*pv); }
syscall(60, r() % 256);
' ;;
    VL51) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var pv: *f64v2 = &w; return *pv; }
syscall(60, r() % 256);
' ;;
    VL52) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var pv: *f64v2 = &w; return 1 + *pv; }
syscall(60, r() % 256);
' ;;
    VL53) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return take(*(&w)); }
syscall(60, r() % 256);
' ;;
    VL54) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var pv: *f64v2 = &w; var ppv: **f64v2 = &pv; return take(**ppv); }
syscall(60, r() % 256);
' ;;
    VL55) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var p: *i64 = 0; p = w; return 0; }
syscall(60, r() % 256);
' ;;
    VL56) printf '%s' "$VLH"'fn r(x: f64v2): i64 { return x; }
fn s(): i64 { return r(mk2(4, 7)); }
syscall(60, s() % 256);
' ;;
    VL57) printf '%s' "$VLH"'fn r(x: f64v2): i64 { return take(x); }
fn s(): i64 { return r(mk2(4, 7)); }
syscall(60, s() % 256);
' ;;
    VL58) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); return g(w); }
syscall(60, r() % 256);
' ;;
    VL59) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var f = |k| take(w); return fncall1(f, 1); }
syscall(60, r() % 256);
' ;;
    VL60) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x = 0; for (x = 0; x < 3; x = w) { } return x; }
syscall(60, r() % 256);
' ;;
    VL61) printf '%s' "$VLH"'var GW: f64v2 = 0;
var GP: *f64v2 = &GW;
var X: i64 = *GP;
syscall(60, X % 256);
' ;;
    VL62) printf '%s' "$VLH"'var GW: f64v2 = 0;
var GP: *f64v2 = &GW;
syscall(1, 1, "", 0);
var X: i64 = *GP;
syscall(60, X % 256);
' ;;
    VL63) printf '%s' "$VLH"'var GW: f64v2 = 0;
var GP: *f64v2 = &GW;
var G = 0;
syscall(1, 1, "", 0);
G = *GP;
syscall(60, G % 256);
' ;;
    VL64) printf '%s' "$VLH"'var GW: f64v2 = 0;
var GP: *f64v2 = &GW;
syscall(60, *GP);
' ;;
    VL65) printf '%s' "$VLH"'var GW: f64v2 = 0;
fn r(): i64 { return *(&GW); }
syscall(60, r() % 256);
' ;;
    VL66) printf '%s' "$VLH"'fn r(): i64 { var w: f64v4; return take(w); }
syscall(60, r() % 256);
' ;;
    VL67) printf '%s' "$VLH"'fn r(): i64 { var w: i32v4; var x = 0; x = 1 + w; return x; }
syscall(60, r() % 256);
' ;;
    VL68) printf '%s' "$VLH"'fn r(): i64 { var w: f32v4; if (w) { return 1; } return 0; }
syscall(60, r() % 256);
' ;;
    VL69) printf '%s' "$VLH"'fn r(): bool { var w: f64v2 = mk2(4, 7); return w; }
syscall(60, 0);
' ;;
    VL70) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var b: bool = false; b = w; return 0; }
syscall(60, r() % 256);
' ;;
    esac
}
VL_ROWS="VL1 VL2 VL3 VL4 VL5 VL6 VL7 VL8 VL9 VL10 VL11 VL12 VL13 VL14 VL15 VL16 VL17 VL18 VL19 VL20 VL21 VL22 VL23 VL24 VL25 VL26 VL27 VL28 VL29 VL30 VL31 VL32 VL33 VL34 VL35 VL36 VL37 VL38 VL39 VL40 VL41 VL42 VL43 VL44 VL45 VL46 VL47 VL48 VL49 VL50 VL51 VL52 VL53 VL54 VL55 VL56 VL57 VL58 VL59 VL60 VL61 VL62 VL63 VL64 VL65 VL66 VL67 VL68 VL69 VL70"
VLM="a vector value cannot be"
VLD="vector type does not match the declared type"
VLA="vector type does not match the assigned variable"
vl_msg() {
    case "$1" in
    VL1) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to parameter 't' of 'take'";;
    VL2) echo "$VLM returned as i64 - 'w' is a vector";;
    VL3) echo "$VLD - 'w' is a vector";;
    VL4) echo "$VLM returned as i64 - 'w' is a vector";;
    VL5) echo "$VLD - 'w' is a vector";;
    VL6) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to parameter 'n' of 'takei'";;
    VL7) echo "$VLM passed to an f64 parameter - 'w' is a vector, passed to parameter 'x' of 'takef'";;
    VL8) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to parameter 'c' of 'takec'";;
    VL9) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to parameter 'n' of 'Pt.ti'";;
    VL10) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to parameter 't' of 'take'";;
    VL11) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to 'syscall'";;
    VL12) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to 'store64'";;
    VL13) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to 'fncall1'";;
    VL14) echo "$VLM returned as i64 - 'w' is a vector";;
    VL15) echo "$VLM returned as i64 - 'w' is a vector";;
    VL16) echo "$VLM returned as i64 - 'w' is a vector";;
    VL17) echo "$VLA - 'w' is a vector";;
    VL18) echo "$VLA - 'w' is a vector";;
    VL19) echo "$VLD - 'w' is a vector";;
    VL20) echo "$VLA - 'w' is a vector";;
    VL21) echo "$VLM returned as i64 - 'w' is a vector";;
    VL22) echo "$VLD - 'w' is a vector";;
    VL23) echo "$VLM returned as i64 - 'w' is a vector";;
    VL24) echo "$VLA - 'w' is a vector";;
    VL25) echo "$VLA - 'w' is a vector";;
    VL26) echo "$VLA - 'w' is a vector";;
    VL27) echo "$VLA - 'w' is a vector";;
    VL28) echo "$VLD - 'w' is a vector";;
    VL29) echo "$VLD - 'w' is a vector";;
    VL30) echo "$VLD - 'w' is a vector";;
    VL31) echo "$VLD - 'w' is a vector";;
    VL32) echo "$VLD - 'w' is a vector";;
    VL33) echo "$VLD - 'w' is a vector";;
    VL34) echo "$VLD - 'w' is a vector";;
    VL35) echo "$VLD - 'w' is a vector";;
    VL36) echo "$VLD - 'w' is a vector";;
    VL37) echo "a tuple element is i64, f64 or bool, not a vector";;
    VL38) echo "a tuple element is i64, f64 or bool, not a vector";;
    VL39) echo "a tuple element is i64, f64 or bool, not a vector";;
    VL40) echo "$VLD - 'w' is a vector";;
    VL41) echo "$VLD - 'w' is a vector";;
    VL42) echo "$VLD - 'w' is a vector";;
    VL43) echo "$VLD - 'w' is a vector";;
    VL44) echo "$VLD - 'w' is a vector";;
    VL45) echo "$VLD - 'w' is a vector";;
    VL46) echo "$VLD - 'w' is a vector";;
    VL47) echo "$VLD - 'w' is a vector";;
    VL48) echo "$VLD - 'w' is a vector";;
    VL49) echo "$VLD - '*pv' is a vector";;
    VL50) echo "$VLM passed to an integer parameter - '*pv' is a vector, passed to parameter 't' of 'take'";;
    VL51) echo "$VLM returned as i64 - '*pv' is a vector";;
    VL52) echo "$VLM returned as i64 - '*pv' is a vector";;
    VL53) echo "$VLM passed to an integer parameter - '*(&w)' is a vector, passed to parameter 't' of 'take'";;
    VL54) echo "$VLM passed to an integer parameter - '**ppv' is a vector, passed to parameter 't' of 'take'";;
    VL55) echo "$VLA - 'w' is a vector";;
    VL56) echo "$VLM returned as i64 - 'x' is a vector";;
    VL57) echo "$VLM passed to an integer parameter - 'x' is a vector, passed to parameter 't' of 'take'";;
    VL58) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to parameter 'x' of 'g'";;
    VL59) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to parameter 't' of 'take'";;
    VL60) echo "$VLA - 'w' is a vector";;
    VL61) echo "$VLD - '*GP' is a vector";;
    VL62) echo "$VLD - '*GP' is a vector";;
    VL63) echo "$VLA - '*GP' is a vector";;
    VL64) echo "$VLM passed to an integer parameter - '*GP' is a vector, passed to 'syscall'";;
    VL65) echo "$VLM returned as i64 - '*(&GW)' is a vector";;
    VL66) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to parameter 't' of 'take'";;
    VL67) echo "$VLA - 'w' is a vector";;
    VL68) echo "$VLD - 'w' is a vector";;
    VL69) echo "cannot return a value that is not a bool from bool fn 'r'";;
    VL70) echo "cannot assign a value that is not a bool to bool 'b'";;
    esac
}
# VLS: the refusal is made in sync — the next statement keeps its own error (two errors): after a declaration, an
# assignment, an argument, a condition, a `return` in a branch.
vls_src() {  # $1 row id -> source on stdout
    case "$1" in
    VLS1) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x: i64 = w; x = zz9; return x; }
syscall(60, r() % 256);
' ;;
    VLS2) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var x = 0; x = w; x = zz9; return x; }
syscall(60, r() % 256);
' ;;
    VLS3) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); take(w); var y = zz9; return y; }
syscall(60, r() % 256);
' ;;
    VLS4) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); if (w) { return 1; } return zz9; }
syscall(60, r() % 256);
' ;;
    VLS5) printf '%s' "$VLH"'fn r(): i64 { var w: f64v2 = mk2(4, 7); var c = 1; if (c == 1) { return w; } return zz9; }
syscall(60, r() % 256);
' ;;
    esac
}
VLS_ROWS="VLS1 VLS2 VLS3 VLS4 VLS5"
vls_msg() {  # the two errors, one per line
    case "$1" in
    VLS1|VLS4) echo "$VLD - 'w' is a vector";;
    VLS2) echo "$VLA - 'w' is a vector";;
    VLS3) echo "$VLM passed to an integer parameter - 'w' is a vector, passed to parameter 't' of 'take'";;
    VLS5) echo "$VLM returned as i64 - 'w' is a vector";;
    esac
    echo "undefined variable 'zz9'"
}
# VLC: the vector's own uses keep compiling and computing (161): a value-form and a `*V` parameter, a vector declaration
# and assignment, a vector fn's value-form parameter returned, `*pv` into a value-form and a `*V` parameter, D36's
# untyped `var v = *pv;`, `var q: f64v2 = *pv;`, `return *p;` from a vector fn, `&w + 8`, `load64(&w)` in a condition,
# a vector's pointer as a multi-value element, a closure's capture into a value-form parameter, lib/simd.cyr's value
# form.
vlc_src() {  # $1 row id -> source on stdout; exits 161 when right
    case "$1" in
    VLC1) printf '%s' 'include "lib/fnptr.cyr"
include "lib/alloc.cyr"
include "lib/simd.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn rd(p): i64 { return load64(p) * 10 + load64(p + 8); }
fn rv(p: *f64v2): i64 { return rd(p); }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn pass(x: f64v2): f64v2 { return x; }
fn via(x: f64v2): i64 { return lanes(x) + rv(x); }
fn back(p: *f64v2): f64v2 { return *p; }
fn two(p: *f64v2): (i64, i64) { return (load64(p), 2); }
fn r(): i64 {
    var w: f64v2 = mk2(4, 7);
    var bad = 0;
    if (lanes(w) != 47) { bad = bad | 1; }
    if (rv(w) != 47) { bad = bad | 2; }
    var u: f64v2 = w; if (rd(&u) != 47) { bad = bad | 4; }
    var z: f64v2 = mk2(0, 0); z = w; if (rd(&z) != 47) { bad = bad | 8; }
    var y: f64v2 = pass(w); if (rd(&y) != 47) { bad = bad | 16; }
    if (via(w) != 94) { bad = bad | 32; }
    var pv: *f64v2 = &w;
    if (lanes(*pv) + rv(*pv) != 94) { bad = bad | 64; }
    var v = *pv; if (rd(&v) != 47) { bad = bad | 128; }
    var q: f64v2 = *pv; if (rd(&q) != 47) { bad = bad | 256; }
    var b: f64v2 = back(&w); if (rd(&b) != 47) { bad = bad | 512; }
    if (load64(&w + 8) != 7) { bad = bad | 1024; }
    var a, c = two(&w); if (a + c != 6) { bad = bad | 2048; }
    var f = |k| lanes(w) + k; if (fncall1(f, 1) != 48) { bad = bad | 4096; }
    var s: f64v2 = f64v2_add(w, u); if (load64(&s) == 0) { bad = bad | 8192; }
    if (bad != 0) { return bad % 251 + 1; }
    return 161;
}
alloc_init();
syscall(60, r() % 256);
' ;;
    esac
}
VLC_ROWS="VLC1"

# ---- 6.7.17 (D23 A, the user's decision, 2026-10-22; issues/2026-10-21-vector-value-in-a-word-position-beyond-d100-
# d101.md row 1): a store through a pointer to a vector copies the whole vector, as `w = u` does (rows VS run, VSK refused
# once) ----------------------------------------------------------------------------------------------------------------
# VS1-VS3 the filed row 1's three bodies verbatim, VS4 its control (each 47 — 4 * 10 + 7 — on every leg); VS5 every
# spelling at once (161): a local, a by-name call, `*(&w)`, a method, `callptr(&f, ..)`, `fncallN(&f, ..)`, an explicit
# instance, a wrapped call, `*q` of a `*V`, `**ppv`, `*gp(pv)`, `*h.pv` (a field, a wrapped source), a by-value vector
# parameter into a `p: *f64v2` parameter, f64v4, f32v4, `*(pa + 1)`, `*&w = *pq`, a closure's captures, a vector
# global through `*(&GW)` and through a `*V` local; VS6 at top level (`*GP = *GQ`).
VSH='fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn rd(p): i64 { return load64(p) * 10 + load64(p + 8); }
fn take(t): i64 { return t; }
'
vs_src() {  # $1 row id -> source on stdout
    case "$1" in
    VS1) printf '%s' "$VSH"'fn r(): i64 { var w: f64v2 = mk2(1, 2); var u: f64v2 = mk2(4, 7); var pv: *f64v2 = &w; *pv = u; return rd(&w); }
syscall(60, r());
' ;;
    VS2) printf '%s' "$VSH"'fn r(): i64 { var w: f64v2 = mk2(1, 2); var pv: *f64v2 = &w; *pv = mk2(4, 7); return rd(&w); }
syscall(60, r());
' ;;
    VS3) printf '%s' "$VSH"'fn r(): i64 { var w: f64v2 = mk2(1, 2); *(&w) = mk2(4, 7); return rd(&w); }
syscall(60, r());
' ;;
    VS4) printf '%s' "$VSH"'fn r(): i64 { var w: f64v2 = mk2(1, 2); var u: f64v2 = mk2(4, 7); w = u; return rd(&w); }
syscall(60, r());
' ;;
    VS5) printf '%s' 'include "lib/fnptr.cyr"
include "lib/alloc.cyr"
fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mkg<T>(a: T, b: T): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn mk4(a, b, c, d): f64v4 { var v: f64v4; store64(&v, a); store64(&v + 8, b); store64(&v + 16, c); store64(&v + 24, d); return v; }
fn mkf(a, b, c, d): f32v4 { var v: f32v4; store32(&v, a); store32(&v + 4, b); store32(&v + 8, c); store32(&v + 12, d); return v; }
fn rd(p): i64 { return load64(p) * 10 + load64(p + 8); }
fn rd4(p): i64 { return ((load64(p) * 10 + load64(p + 8)) * 10 + load64(p + 16)) * 10 + load64(p + 24); }
fn rdf(p): i64 { return ((load32(p) * 10 + load32(p + 4)) * 10 + load32(p + 8)) * 10 + load32(p + 12); }
struct Mv { k; }
impl Mv { fn m2(self): f64v2 { return mk2(4, 7); } }
struct H { pv: *f64v2; n; }
var GW: f64v2 = 0;
fn gp(p: *f64v2): *f64v2 { return p; }
fn st(p: *f64v2, u: f64v2): i64 { *p = u; return 0; }
fn r(): i64 {
    var bad = 0;
    var w: f64v2 = mk2(1, 2); var pv: *f64v2 = &w; var u: f64v2 = mk2(4, 7);
    *pv = u; if (rd(&w) != 47) { bad = bad | 1; }
    w = mk2(1, 2); *pv = mk2(4, 7); if (rd(&w) != 47) { bad = bad | 2; }
    w = mk2(1, 2); *(&w) = mk2(4, 7); if (rd(&w) != 47) { bad = bad | 4; }
    w = mk2(1, 2); var s: Mv = Mv { 1 }; *pv = s.m2(); if (rd(&w) != 47) { bad = bad | 8; }
    w = mk2(1, 2); *pv = callptr(&mk2, 4, 7); if (rd(&w) != 47) { bad = bad | 16; }
    w = mk2(1, 2); *pv = fncall2(&mk2, 4, 7); if (rd(&w) != 47) { bad = bad | 32; }
    w = mk2(1, 2); *pv = mkg<i64>(4, 7); if (rd(&w) != 47) { bad = bad | 64; }
    w = mk2(1, 2); *pv = ((mk2(4, 7))); if (rd(&w) != 47) { bad = bad | 128; }
    w = mk2(1, 2); var q: f64v2 = mk2(4, 7); var pq: *f64v2 = &q; *pv = *pq; if (rd(&w) != 47) { bad = bad | 256; }
    w = mk2(1, 2); var ppv: **f64v2 = &pv; **ppv = u; if (rd(&w) != 47) { bad = bad | 512; }
    w = mk2(1, 2); *gp(pv) = u; if (rd(&w) != 47) { bad = bad | 1024; }
    w = mk2(1, 2); var h: H; h.pv = pv; *h.pv = (u); if (rd(&w) != 47) { bad = bad | 2048; }
    w = mk2(1, 2); st(pv, u); if (rd(&w) != 47) { bad = bad | 4096; }
    var a4: f64v4 = mk4(1, 1, 1, 1); var p4: *f64v4 = &a4; *p4 = mk4(4, 7, 2, 9); if (rd4(&a4) != 4729) { bad = bad | 8192; }
    var af: f32v4 = mkf(1, 1, 1, 1); var pf: *f32v4 = &af; var bf: f32v4 = mkf(3, 1, 4, 1); *pf = bf; if (rdf(&af) != 3141) { bad = bad | 16384; }
    var wa: f64v2[2]; var pa: *f64v2 = &wa; *(pa + 1) = u; if (rd(&wa + 16) != 47) { bad = bad | 32768; }
    w = mk2(1, 2); *&w = *pq; if (rd(&w) != 47) { bad = bad | 65536; }
    w = mk2(1, 2); var f = |k| { *pv = u; return k; }; fncall1(f, 1); if (rd(&w) != 47) { bad = bad | 131072; }
    *(&GW) = u; if (rd(&GW) != 47) { bad = bad | 262144; }
    var gpv: *f64v2 = &GW; store64(&GW, 0); *gpv = mk2(4, 7); if (rd(&GW) != 47) { bad = bad | 524288; }
    if (bad != 0) { return bad % 251 + 1; }
    return 161;
}
alloc_init();
syscall(60, r() % 256);
' ;;
    VS6) printf '%s' 'fn rd(p): i64 { return load64(p) * 10 + load64(p + 8); }
var GW: f64v2 = 0;
var GX: f64v2 = 0;
var GP: *f64v2 = &GW;
var GQ: *f64v2 = &GX;
store64(&GX, 4); store64(&GX + 8, 7);
store64(&GW, 1); store64(&GW + 8, 2);
*GP = *GQ;
syscall(60, rd(&GW));
' ;;
    esac
}
VS_ROWS="VS1 VS2 VS3 VS4 VS5 VS6"
vs_want() { case "$1" in VS5) echo 161;; *) echo 47;; esac; }
# VSK: refused once, in the words `w = <src>` meets — a word (`5`, `load64(..)`), another vector (a local, a call, a `*q`),
# a call that only starts the value, a callee held in a variable — and the compound `*pv OP= v` as `w OP= v` (`*(&w)`: w's
# own words); VSK9 a vector call at top level (no frame).
VSKH="$VSH"'fn mk4(a): f64v4 { var v: f64v4; store64(&v, a); return v; }
'
vsk_src() {  # $1 row id -> source on stdout
    case "$1" in
    VSK1) printf '%s' "$VSKH"'fn r(): i64 { var w: f64v2; var pv: *f64v2 = &w; *pv = 5; return 0; }
syscall(60, r());
' ;;
    VSK2) printf '%s' "$VSKH"'fn r(): i64 { var w: f64v2; var pv: *f64v2 = &w; var u4: f64v4; *pv = u4; return 0; }
syscall(60, r());
' ;;
    VSK3) printf '%s' "$VSKH"'fn r(): i64 { var w: f64v2; var pv: *f64v2 = &w; *pv = mk4(1); return 0; }
syscall(60, r());
' ;;
    VSK4) printf '%s' "$VSKH"'fn r(): i64 { var w: f64v2; var pv: *f64v2 = &w; *pv = mk2(1, 2) + 1; return 0; }
syscall(60, r());
' ;;
    VSK5) printf '%s' "$VSKH"'fn r(): i64 { var w: f64v2; var pv: *f64v2 = &w; var u: f64v2; *pv += u; return 0; }
syscall(60, r());
' ;;
    VSK6) printf '%s' "$VSKH"'fn r(): i64 { var w: f64v2; var pv: *f64v2 = &w; var ppv: **f64v2 = &pv; **ppv -= 1; return 0; }
syscall(60, r());
' ;;
    VSK7) printf '%s' "$VSKH"'fn r(): i64 { var w: f64v2; *(&w) += 1; return 0; }
syscall(60, r());
' ;;
    VSK8) printf '%s' "$VSKH"'fn r(): i64 { var w: f64v2; var pv: *f64v2 = &w; var u4: f64v4; var p4: *f64v4 = &u4; *pv = *p4; return 0; }
syscall(60, r());
' ;;
    VSK9) printf '%s' "$VSKH"'var GW: f64v2 = 0;
var GP: *f64v2 = &GW;
*GP = mk2(1, 2);
syscall(60, 0);
' ;;
    VSK10) printf '%s' 'include "lib/fnptr.cyr"
'"$VSKH"'fn r(): i64 { var w: f64v2; var pv: *f64v2 = &w; var fp = &mk2; *pv = callptr(fp, 1, 2); return 0; }
syscall(60, r());
' ;;
    VSK11) printf '%s' "$VSKH"'fn r(): i64 { var w: f64v2; var pv: *f64v2 = &w; *pv = load64(&w); return 0; }
syscall(60, r());
' ;;
    esac
}
VSK_ROWS="VSK1 VSK2 VSK3 VSK4 VSK5 VSK6 VSK7 VSK8 VSK9 VSK10 VSK11"
VSR="a value-form vector local is assigned only from"
vsk_msg() {
    case "$1" in
    VSK1) echo "$VSR a local of its type, a call declared to return it (by name, a method, or fncallN / callptr with the callee written \`&f\`) or a dereference of a pointer to its type (\`*p\`) - got \`5\`";;
    VSK2) echo "cannot copy 'u4' into a variable of a different struct/vector type: 'pv'";;
    VSK3) echo "vector return type does not match the assigned variable";;
    VSK4) echo "$VSR"; ;;
    VSK5) echo "compound assignment to the vector 'pv' points at is refused - a vector value is not an integer or a float";;
    VSK6) echo "compound assignment to the vector '*ppv' points at is refused";;
    VSK7) echo "compound assignment to vector 'w' is refused - a vector value is not an integer or a float";;
    VSK8) echo "cannot copy 'p4' into a variable of a different struct/vector type: 'pv'";;
    VSK9) echo "'mk2' returns a vector by value, and a vector result needs storage in a fn's frame - call it inside a fn";;
    VSK10) echo "got \`callptr\`; through a fn pointer held in a variable, give the target an out-pointer";;
    VSK11) echo "- got \`load64\`";;
    esac
}
# 6.7.17: a table's rows built by the leg's compiler (`$7` an env assignment, or none) and run, each exiting `$6 <row>`.
accept_want_all() {  # $1 leg label  $2 compiler  $3 runner fn name  $4 source fn  $5 rows  $6 want fn  [$7 VAR=value]
    for row in $5; do
        "$4" "$row" > "$W/dw.cyr"
        rc=0
        if [ -n "${7:-}" ]; then env "$7" "$2" < "$W/dw.cyr" > "$W/dw.out" 2>"$W/dw.err" || rc=$?
        else "$2" < "$W/dw.cyr" > "$W/dw.out" 2>"$W/dw.err" || rc=$?; fi
        naccept=$((naccept+1))
        if ! [ -s "$W/dw.out" ]; then bad "$1 $row: produced no artifact (rc=$rc: $(grep -m1 '^error' "$W/dw.err" 2>/dev/null))"; continue; fi
        if grep -q '^error' "$W/dw.err"; then bad "$1 $row: an error line: $(grep -m1 '^error' "$W/dw.err")"; continue; fi
        chmod +x "$W/dw.out"
        got=0
        ( ulimit -c 0; "$3" "$W/dw.out" ) >/dev/null 2>&1 || got=$?
        want=$("$6" "$row")
        if [ "$got" = "$want" ]; then good "$1 $row = $got"; else bad "$1 $row = $got, want $want"; fi
    done
}


# ---- 6.7.16 (met landing D100): the vector receives' refusals are made in sync — the statement parses on to its own end,
# so the NEXT statement keeps its own error (rows WS: two errors, the refusal then "undefined variable 'zz9'") and a
# `for` header's init is one error (rows WF; the condition was read as consumed: "expected ';', got '='" second) ---------
# WS1 `x = mk2(..)` (a by-name call into a local), WS2 `var x: i64 = mk2(..)`, WS3 `x = mk2(..) + 1` (a call starting
# it), WS4 `x = s.m2()`, WS5 `var x: i64 = s.m2() + 1`, WS6 a top-level global assignment, WS7 a top-level annotated
# declaration after the first statement, WS8 a vector of another type into a vector local (WS7 / WS8 kept the next error
# before too: their paths resync on their own); WF1-WF4 the `for` init's assignment, annotated declaration, starting
# call, method.
WSH="$OPH"'struct Pt { a; b; }
'
ws_src() {  # $1 row id -> source on stdout
    case "$1" in
    WS1) printf '%s' "$WSH"'fn r(): i64 { var x = 0; x = mk2(1, 2); x = zz9; return x; }
syscall(60, r() % 256);
' ;;
    WS2) printf '%s' "$WSH"'fn r(): i64 { var x: i64 = mk2(1, 2); x = zz9; return x; }
syscall(60, r() % 256);
' ;;
    WS3) printf '%s' "$WSH"'fn r(): i64 { var x = 0; x = mk2(1, 2) + 1; x = zz9; return x; }
syscall(60, r() % 256);
' ;;
    WS4) printf '%s' "$WSH"'fn r(): i64 { var s: Mv = Mv { 1 }; var x = 0; x = s.m2(); x = zz9; return x; }
syscall(60, r() % 256);
' ;;
    WS5) printf '%s' "$WSH"'fn r(): i64 { var s: Mv = Mv { 1 }; var x: i64 = s.m2() + 1; x = zz9; return x; }
syscall(60, r() % 256);
' ;;
    WS6) printf '%s' "$WSH"'var G = 0;
syscall(1, 1, "", 0);
G = mk2(1, 2);
G = zz9;
syscall(60, G);
' ;;
    WS7) printf '%s' "$WSH"'syscall(1, 1, "", 0);
var X: i64 = mk2(1, 2) + 1;
var Y = zz9;
syscall(60, X + Y);
' ;;
    WS8) printf '%s' "$WSH"'fn r(): i64 { var w: f64v4 = mk4(1); w = mk2(1, 2); var y = zz9; return y; }
syscall(60, r() % 256);
' ;;
    esac
}
WS_ROWS="WS1 WS2 WS3 WS4 WS5 WS6 WS7 WS8"
ws_msg() {  # the two errors, one per line
    case "$1" in
    WS2|WS5|WS7) echo "vector return type does not match the declared type";;
    *) echo "vector return type does not match the assigned variable";;
    esac
    echo "undefined variable 'zz9'"
}
wf_src() {  # $1 row id -> source on stdout
    case "$1" in
    WF1) printf '%s' "$WSH"'fn r(): i64 { var a = 0; for (a = mk2(1, 2); a < 3; a = a + 1) { } return a; }
syscall(60, r() % 256);
' ;;
    WF2) printf '%s' "$WSH"'fn r(): i64 { var a = 0; for (var b: i64 = mk2(1, 2); a < 3; a = a + 1) { } return a; }
syscall(60, r() % 256);
' ;;
    WF3) printf '%s' "$WSH"'fn r(): i64 { var a = 0; for (a = mk2(1, 2) + 1; a < 3; a = a + 1) { } return a; }
syscall(60, r() % 256);
' ;;
    WF4) printf '%s' "$WSH"'fn r(): i64 { var s: Mv = Mv { 1 }; var a = 0; for (a = s.m2(); a < 3; a = a + 1) { } return a; }
syscall(60, r() % 256);
' ;;
    esac
}
WF_ROWS="WF1 WF2 WF3 WF4"
wf_msg() { case "$1" in WF2) echo "vector return type does not match the declared type";; *) echo "vector return type does not match the assigned variable";; esac; }


# ---- 6.7.16 (met landing D100): a refused statement prints no float-type warning — the panic latch its error holds is
# the statement's (`_FLT_TYPE_WARN`): `var x: f64 = 1.0 + mk2(41, 7);` printed D100's refusal and then "f64 arithmetic with
# a non-f64 right operand" about the same operand (rows FW: one error, no warning; FW1 f64, FW2 f32, FW3 a comparison,
# FW4 an int-left `+` with an f64 right; FW5 the next statement's own warning still printed) ---------------------------
# FW6-FW13 (the s16 review): an error that does not latch — a tuple used as a value (FW6, FW11 f32), an undefined name
# (FW7, FW10 a comparison, FW13 a generic's body at two instances) — stands the warning down too (`_err_n` since the
# statement began, `_flt_en`); the next statement's own warning prints (FW8, FW9 the declaration zone's next entry,
# FW12 after the first statement, FW13).
FWH='fn mk2(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
'
fw_src() {  # $1 row id -> source on stdout
    case "$1" in
    FW1) printf '%s' "$FWH"'fn r(): i64 { var x: f64 = 1.0 + mk2(41, 7); return 1; }
syscall(60, r() % 256);
' ;;
    FW2) printf '%s' "$FWH"'fn r(): i64 { var y: f32 = 1.0; var x: f32 = y * mk2(41, 7); return 1; }
syscall(60, r() % 256);
' ;;
    FW3) printf '%s' "$FWH"'fn r(): i64 { var y: f64 = 1.5; if (y < mk2(41, 7)) { return 1; } return 2; }
syscall(60, r() % 256);
' ;;
    FW4) printf '%s' "$FWH"'fn r(): i64 { var y: f64 = 1.5; var x = 0; x = 1 + mk2(41, 7) + y; return 1; }
syscall(60, r() % 256);
' ;;
    FW5) printf '%s' "$FWH"'fn r(): i64 { var y: f64 = 1.5; var x: f64 = y - mk2(41, 7); var z: f64 = y + 1; return 1; }
syscall(60, r() % 256);
' ;;
    FW6) printf '%s' "$FWH"'fn r(): i64 { var t = (1, 2); var f: f64 = 1.0 + t; return 1; }
syscall(60, r() % 256);
' ;;
    FW7) printf '%s' "$FWH"'fn r(): i64 { var f: f64 = 1.0 + undefined_q; return 1; }
syscall(60, r() % 256);
' ;;
    FW8) printf '%s' "$FWH"'fn r(): i64 { var f: f64 = 1.0 + undefined_q; var g = 1; var h: f64 = 1.0 + g; return 1; }
syscall(60, r() % 256);
' ;;
    FW9) printf '%s' "$FWH"'var A: f64 = 1.0 + undefined_q;
var B = 1;
var C: f64 = 1.0 + B;
syscall(60, 1);
' ;;
    FW10) printf '%s' "$FWH"'fn r(): i64 { var y: f64 = 1.5; if (y < undefined_q) { return 1; } return 2; }
syscall(60, r() % 256);
' ;;
    FW11) printf '%s' "$FWH"'fn r(): i64 { var t = (1, 2); var y: f32 = 1.0; var x: f32 = y * t; return 1; }
syscall(60, r() % 256);
' ;;
    FW12) printf '%s' "$FWH"'syscall(1, 1, "", 0);
var A: f64 = 1.0 + undefined_q;
var B = 1;
var C: f64 = 1.0 + B;
syscall(60, 1);
' ;;
    FW13) printf '%s' "$FWH"'fn g<T>(x: T): i64 { var f: f64 = 1.0 + undefined_q; var h: f64 = 1.0 + x; return 1; }
fn r(): i64 { return g(1) + g(2); }
syscall(60, r() % 256);
' ;;
    esac
}
FW_ROWS="FW1 FW2 FW3 FW4 FW5 FW6 FW7 FW8 FW9 FW10 FW11 FW12 FW13"
fw_msg() {
    case "$1" in
    FW4) echo "vector return type does not match the assigned variable";;
    FW6|FW11) echo "tuple 't' used as a value";;
    FW7|FW8|FW9|FW10|FW12|FW13) echo "undefined variable 'undefined_q'";;
    *) echo "vector return type does not match the declared type";;
    esac
}
fw_warn() {
    case "$1" in
    FW5) echo "2:80: f64 arithmetic with a non-f64 right operand";;
    FW8) echo "2:78: f64 arithmetic with a non-f64 right operand";;
    FW9) echo "4:21: f64 arithmetic with a non-f64 right operand";;
    FW12) echo "5:21: f64 arithmetic with a non-f64 right operand";;
    FW13) echo "2:74: f64 arithmetic with a non-f64 right operand";;
    *) echo "";;
    esac
}
refuse_fw_all() {  # $1 leg label  $2 compiler  [$3 VAR=value]: one error (`fw_msg`), and only `fw_warn`'s warning (or none)
    for row in $FW_ROWS; do
        fw_src "$row" > "$W/fw.cyr"
        rc=0
        if [ -n "${3:-}" ]; then env "$3" "$2" < "$W/fw.cyr" > "$W/fw.out" 2>"$W/fw.err" || rc=$?
        else "$2" < "$W/fw.cyr" > "$W/fw.out" 2>"$W/fw.err" || rc=$?; fi
        nrefuse=$((nrefuse+1))
        ne=$(grep -c '^error' "$W/fw.err" 2>/dev/null || true)
        nw=$(grep -c '^warning' "$W/fw.err" 2>/dev/null || true)
        ww=$(fw_warn "$row")
        if [ "$ne" != 1 ] || ! grep '^error' "$W/fw.err" | grep -qF -- "$(fw_msg "$row")"; then bad "$1 $row: $ne error lines, want 1 '$(fw_msg "$row")' (rc=$rc)"
        elif [ -z "$ww" ] && [ "$nw" != 0 ]; then bad "$1 $row: $nw warning lines after the refusal: $(grep '^warning' "$W/fw.err" | tr '\n' ' ')"
        elif [ -n "$ww" ] && { [ "$nw" != 1 ] || ! grep '^warning' "$W/fw.err" | grep -qF -- "$ww"; }; then bad "$1 $row: want the one warning '$ww', got $nw: $(grep '^warning' "$W/fw.err" | tr '\n' ' ')"
        elif [ -s "$W/fw.out" ]; then bad "$1 $row: reported but still emitted an artifact"
        else good "$1 $row refused once, no warning of its own"; fi
    done
}


# ---- 6.7.16 (met landing the review's D100 fixes): a refused annotation is its declaration's one error — the
# annotation parses on as a plain i64 (`_tn_refuse`), and the vector refusals compared the call with that i64: `var x: zz =
# mk2(41, 7);` printed "unknown type 'zz' for variable 'x'" and then "vector return type does not match the declared type"
# (`_vin_decl`, `_vrcv_mscal`, `_vrcv_tyerr`, `_vtop_ref` now ask `_vrcv_annbad`). Rows VN (one error, the annotation's):
# VN1 a by-name call, VN2 a later operand (D100), VN3 wrapped, VN4 a method, VN5 a method starting it into `Q<i64>`, VN6
# `callptr(&mk2, ..)`, VN7 a `for` init, VN8 the declaration zone, VN9 after the first statement, VN10 a tuple element's
# refusal (`(f64v2, i64)`) before a later operand; rows VNS (two errors: another declaration's own mismatch is kept) on
# host / host IR=3 / cx / aarch64 / win64. Mutations (2026-10-21, measured; per-site on host):
#   M-VN0 the tree before                              -> RED 55: VN1-VN10 VNS1 on five legs
#   M-VN1 `_vin_decl` not asking                       -> RED 3: VN1 VN7 VNS1
#   M-VN2 `_vrcv_tyerr` not asking                     -> RED 4: VN2 VN5 VN9 VN10
#   M-VN3 `_vrcv_mscal` not asking                     -> RED 7: VN1 VN3-VN7 VNS1
#   M-VN4 `_vtop_ref` not asking                       -> RED 2: VN8 VN9
#   M-VN5 `_vrcv_dbeg` stopping at a grouping `(`      -> RED 1: VN10
vn_src() {  # $1 row id -> source on stdout
    case "$1" in
    VN1) printf '%s' "$OPH"'fn r(): i64 { var x: zz = mk2(41, 7); return 1; }
syscall(60, r() % 256);
' ;;
    VN2) printf '%s' "$OPH"'fn r(): i64 { var x: zz = 1 + mk2(41, 7); return 1; }
syscall(60, r() % 256);
' ;;
    VN3) printf '%s' "$OPH"'fn r(): i64 { var x: zz = (mk2(41, 7)); return 1; }
syscall(60, r() % 256);
' ;;
    VN4) printf '%s' "$OPH"'fn r(): i64 { var s: Mv = Mv { 1 }; var x: zz = s.m2(); return 1; }
syscall(60, r() % 256);
' ;;
    VN5) printf '%s' "$OPH"'fn r(): i64 { var s: Mv = Mv { 1 }; var x: Q<i64> = s.m2() + 1; return 1; }
syscall(60, r() % 256);
' ;;
    VN6) printf '%s' "$OPH"'fn r(): i64 { var x: zz = callptr(&mk2, 41, 7); return 1; }
syscall(60, r() % 256);
' ;;
    VN7) printf '%s' "$OPH"'fn r(): i64 { for (var i: zz = mk2(41, 7); i < 3; i = i + 1) { } return 1; }
syscall(60, r() % 256);
' ;;
    VN8) printf '%s' "$OPH"'var X: zz = mk2(41, 7);
syscall(60, 1);
' ;;
    VN9) printf '%s' "$OPH"'syscall(1, 1, "", 0);
var X: zz = mk2(41, 7) + 1;
syscall(60, 1);
' ;;
    VN10) printf '%s' "$OPH"'fn r(): i64 { var t: (f64v2, i64) = (1 + mk2(41, 7), 3); return 1; }
syscall(60, r() % 256);
' ;;
    esac
}
VN_ROWS="VN1 VN2 VN3 VN4 VN5 VN6 VN7 VN8 VN9 VN10"
vn_msg() {
    case "$1" in
    VN5) echo "unknown type 'Q' for variable 'x'";;
    VN7) echo "unknown type 'zz' for variable 'i'";;
    VN8|VN9) echo "unknown type 'zz' for variable 'X'";;
    VN10) echo "a tuple element is i64, f64 or bool, not 'f64v2'";;
    *) echo "unknown type 'zz' for variable 'x'";;
    esac
}
vns_src() {  # $1 row id -> source on stdout
    case "$1" in
    VNS1) printf '%s' "$OPH"'fn r(): i64 { var x: zz = mk2(41, 7); var y: i64 = mk2(1, 2); return 1; }
syscall(60, r() % 256);
' ;;
    VNS2) printf '%s' "$OPH"'fn r(): i64 { var t: (zz, i64) = (3, 4); var x: i64 = 1 + mk2(1, 2); return 1; }
syscall(60, r() % 256);
' ;;
    esac
}
VNS_ROWS="VNS1 VNS2"
vns_msg() {  # the two errors, one per line
    case "$1" in
    VNS1) echo "unknown type 'zz' for variable 'x'";;
    VNS2) echo "unknown type 'zz' as a tuple element";;
    esac
    echo "vector return type does not match the declared type"
}


# ---- 6.7.16 (met landing the review's D100 fixes): an inline literal global after the first statement holds its index
# while its elements are parsed (`_glit_hold`) — on PE an element's vector call made a hidden global temporary for its
# result (6.7.12) at the index the literal had registered without counting, overwrote the slot, and the literal's count
# bump cut the temporary off: the refusal was followed by "undefined variable 'GP'" at the next use (through 6.7.15 that
# wrong error alone). Rows VG (one error: the refusal) — VG1 a struct literal's whole-call field, VG2 an operand in an
# annotated literal, VG3 a tuple literal's operand, VG4 a named field's method call — and VGS1 / VGS2 (the name is
# still not visible inside its own literal: "undefined variable") on host / host IR=3 / cx / aarch64 / win64.
# Mutations (2026-10-21, measured): M-VG0 the tree before -> RED 4: VG1-VG4 on win64 (the other legs make no temporary);
# M-VG1 the held slot not marked dead -> RED 10: VGS1 VGS2 on five legs (the literal read its own uninitialised slot).
vg_src() {  # $1 row id -> source on stdout
    case "$1" in
    VG1) printf '%s' "$VOH"'syscall(1, 1, "", 0);
var GP = Pt { mk2(41, 7), 1 };
syscall(60, GP.b % 256);
' ;;
    VG2) printf '%s' "$VOH"'syscall(1, 1, "", 0);
var GP: Pt = Pt { 1, 1 + mk2(41, 7) };
syscall(60, GP.b % 256);
' ;;
    VG3) printf '%s' "$VOH"'syscall(1, 1, "", 0);
var GT = (3, 1 + mk2(41, 7));
syscall(60, GT.1 % 256);
' ;;
    VG4) printf '%s' "$VOH"'var GM: Mv = Mv { 1 };
syscall(1, 1, "", 0);
var GP = Pt { a: 1, b: GM.m2() };
syscall(60, GP.a % 256);
' ;;
    VGS1) printf '%s' "$VOH"'syscall(1, 1, "", 0);
var GP = Pt { GP.a, 1 };
syscall(60, GP.b % 256);
' ;;
    VGS2) printf '%s' "$VOH"'syscall(1, 1, "", 0);
var GT = (GT.0, 1);
syscall(60, GT.1 % 256);
' ;;
    esac
}
VG_ROWS="VG1 VG2 VG3 VG4 VGS1 VGS2"
vg_msg() {
    case "$1" in
    VGS1) echo "undefined variable 'GP'";;
    VGS2) echo "undefined variable 'GT'";;
    *) echo "vector return type does not match the declared type";;
    esac
}


# ---- 6.7.13 (issues/archived/2026-10-14-vector-local-refusal-hint-every-source.md): the refusal's own words (rows H) ----------
# The out-pointer hint only for a callee held in a variable; a call naming no fn left to the undefined-function path;
# the accepted list naming `*p` (D34). Each row compiles to no artifact with exactly one `error` line.
HINT="through a fn pointer held in a variable, give the target an out-pointer"
MSGL='or a dereference of a pointer to its type (`*p`) - got'
HH='include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn sc(a, b) { return a + b; }
'
h_src() {  # $1 row id -> source on stdout
    case "$1" in
    H1) printf '%s' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 { var v: f64v2 = 5; return lanes(v); }
syscall(60, run());
' ;;
    H2) printf '%s' "$HH"'fn run(): i64 { var w = 3; var v: f64v2 = load64(&w); return lanes(v); }
syscall(60, run());
' ;;
    H3) printf '%s' "$HH"'fn run(): i64 { var w = 3; var v: f64v2 = &w; return lanes(v); }
syscall(60, run());
' ;;
    H4) printf '%s' "$HH"'fn run(): i64 { var fp = &mkv; var v: f64v2 = callptr(fp, 41, 7); return lanes(v); }
syscall(60, run());
' ;;
    H5) printf '%s' 'fn run(): i64 { var v: f64v2 = f64v2_splat(1.0); return 1; }
syscall(60, run());
' ;;
    H6) printf '%s' "$HH"'fn run(): i64 { var w = 3; var v: f64v2 = mkv(1, 2); v = load64(&w); return lanes(v); }
syscall(60, run());
' ;;
    H7) printf '%s' "$HH"'fn run(): i64 { var fp = &mkv; var v: f64v2 = mkv(1, 2); v = fncall2(fp, 41, 7); return lanes(v); }
syscall(60, run());
' ;;
    H8) printf '%s' "$HH"'fn run(): i64 { var v: f64v2 = callptr(&sc, 41, 7); return lanes(v); }
syscall(60, run());
' ;;
    H9) printf '%s' 'fn run(): i64 { var v: f64v2; v = f64v2_splat(1.0); return 1; }
syscall(60, run());
' ;;
    H10) printf '%s' "$HH"'fn run(): i64 { var w: f64v2 = mkv(41, 7); var x = &w; var v: f64v2 = *x; return lanes(v); }
syscall(60, run());
' ;;
    H11) printf '%s' "$HH"'fn run(): i64 { var fp = &mkv; var v: f64v2 = (callptr(fp, 41, 7)); return lanes(v); }
syscall(60, run());
' ;;
    H12) printf '%s' 'fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 { var v: f64v2 = (f64v2_splat(1.0)); return lanes(v); }
syscall(60, run());
' ;;
    H13) printf '%s' 'fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn run(): i64 { var v: f64v2; v = ((f64v2_splat(1.0))); return lanes(v); }
syscall(60, run());
' ;;
    H14) printf '%s' 'fn bad(): f64v2 { return f64v2_splat(1.0); }
fn run(): i64 { var v: f64v2 = bad(); return load64(&v); }
syscall(60, run());
' ;;
    H15) printf '%s' 'fn bad(a): f64v2 { if (a > 0) { return (f64v2_splat(1.0)); } var w: f64v2; return w; }
fn run(): i64 { var v: f64v2 = bad(1); return load64(&v); }
syscall(60, run());
' ;;
    H16) printf '%s' 'fn bad(): f64v2 { return f64v2_splat(1.0); }
syscall(60, 1);
' ;;
    esac
}
H_ROWS="H1 H2 H3 H4 H5 H6 H7 H8 H9 H10 H11 H12 H13 H14 H15"
h_kind() {  # undef = the undefined-function path alone; hint = refused with the hint; plain = refused without it
    case "$1" in
    H5|H9|H12|H13|H14|H15) echo undef;;
    H4|H7|H11) echo hint;;
    *) echo plain;;
    esac
}
h_got() {  # what the refusal names
    case "$1" in
    H1) echo '5';; H2|H6) echo 'load64';; H3) echo '&w';; H4|H8) echo 'callptr';; H7) echo 'fncall2';;
    H10) echo '*x';; H11) echo '(...)';; *) echo '';;
    esac
}
# ---- 6.7.14 (D43): `ret2` in a vector-returning fn (rows T refused once, rows U run) ----------
t_src() {  # $1 row id -> source on stdout
    case "$1" in
    T1) printf '%s' 'fn v(): f64v2 { ret2(41, 7); }
fn main(): i64 { var x: f64v2 = v(); return load64(&x) + load64(&x + 8); }
var r = main(); syscall(60, r);
' ;;
    T2) printf '%s' 'fn v(): f64v4 { ret2(41, 7); }
fn main(): i64 { var x: f64v4 = v(); return load64(&x) + load64(&x + 8); }
var r = main(); syscall(60, r);
' ;;
    T3) printf '%s' 'fn v(): f32v4 { ret2(41, 7); }
fn main(): i64 { var x: f32v4 = v(); return load32(&x) + load32(&x + 4); }
var r = main(); syscall(60, r);
' ;;
    T4) printf '%s' 'fn v(): i32v4 { ret2(41, 7); }
fn main(): i64 { var x: i32v4 = v(); return load32(&x) + load32(&x + 4); }
var r = main(); syscall(60, r);
' ;;
    T5) printf '%s' 'fn bad<T>(a: T): f64v2 { ret2(a, 7); }
fn main(): i64 { var v: f64v2 = bad<i64>(41); var w: f64v2 = bad<i32>(41); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    T6) printf '%s' 'fn bad(x): f64v2 { if (x > 0) { ret2(41, 7); } var v: f64v2; return v; }
fn main(): i64 { var v: f64v2 = bad(1); return load64(&v); }
var r = main(); syscall(60, r);
' ;;
    T7) printf '%s' 'fn v(): f64v2 { return ret2(41, 7); }
fn main(): i64 { var x: f64v2 = v(); return load64(&x) + load64(&x + 8); }
var r = main(); syscall(60, r);
' ;;
    esac
}
T_ROWS="T1 T2 T3 T4 T5 T6 T7"
t_got() { case "$1" in T7) echo 'this expression';; *) echo 'ret2';; esac; }
u_src() {  # $1 row id -> source on stdout; each exits 83 (41 + 42) when right
    case "$1" in
    U1) printf '%s' 'include "lib/fnptr.cyr"
fn good(x): f64v2 { var cl = |y| { ret2(y, y + 1); }; var a, b = fncall1(cl, x); var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn main(): i64 { var v: f64v2 = good(41); return load64(&v) + load64(&v + 8); }
var r = main(); syscall(60, r);
' ;;
    U2) printf '%s' '#inline
fn two(x) { ret2(x, x + 1); }
fn good(x): f64v2 { var a, b = two(x); var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn main(): i64 { var v: f64v2 = good(41); return load64(&v) + load64(&v + 8); }
var r = main(); syscall(60, r);
' ;;
    esac
}
U_ROWS="U1 U2"
# Every Q row on all four legs: Q3's refusal is the value-form argument's, which PE's address-passed parameter runs since
# D30 (`_sarg_pe_vword`, 6.7.14's `_sarg_pe_vform`; it took lane 0 as the address before: exit 5).
q_legs() { echo "host cx aarch64 win64"; }
# Which legs an acceptance row RUNS on: every row on all four. A7's int-class 16-byte pair return
# is a per-target ABI the tuple guard has nothing to do with, and it was kept off two legs until
# each target carried it:
#   cx      — refused the pair outright ("cx: int-class 16B struct pair-return ABI not supported")
#             until 6.7.8 (r0:r4, the multi-value pair's registers).
#   aarch64 — silently lost the second register (41 for 48): the struct pair (x0:x1) and the
#             multi-value slot (x2) disagreed until 6.7.7 (ESTRUCT_PAIR_HI_SYNC); 48 since.
#             Mutation (6.7.8, a scratch copy): aarch64 ESTRUCT_PAIR_HI_SYNC emitting nothing ->
#             RED aarch64 A7 = 41, every other row green. 6.7.13: A7's producer is `return p;` (its
#             `ret2` refused) and the sync is gone with its last producer.
# A8 and A9 (the SCALAR arity-2/arity-3 multi-return) run on all four legs and are green on all
# four, so the "tuple syntax still works" property is not host-only.
a_legs() { echo "host cx aarch64 win64"; }
# Every expectation is derived a different way from the program that produces it: the vector
# rows read a lane the source stored a literal into, A7 sums two distinct fields (41+7=48, and
# 7+41 is the same — so A7 is paired with X10, which has the same operands and must be REFUSED),
# A8/A9 pack each return slot into its own decimal digit so a swap or an unwritten register
# cannot land on the expected number.
a_want() {
    case "$1" in
    A1) echo 41;; A2) echo 7;; A3) echo 41;; A4) echo 7;; A5) echo 41;; A6) echo 33;;
    A7) echo 48;; A8) echo 56;; A9) echo 123;;
    esac
}

# ---- legs ------------------------------------------------------------------------------------
r_msg() { case "$1" in X14) echo "vector global 'G' is read and written through its address";; *) echo "$MSG";; esac; }
refuse_all() {  # $1 leg label  $2 compiler
    for row in $REFUSE_ROWS; do
        r_src "$row" > "$W/r.cyr"
        rc=0
        cat "$W/r.cyr" | "$2" > "$W/r.out" 2>"$W/r.err" || rc=$?
        nrefuse=$((nrefuse+1))
        if ! grep -q "$(r_msg "$row")" "$W/r.err" 2>/dev/null; then
            bad "$1 $row: not refused (rc=$rc, first line: $(head -1 "$W/r.err" 2>/dev/null))"
        elif [ -s "$W/r.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused"
        fi
    done
}

accept_all() {  # $1 leg label  $2 compiler  $3 runner fn name
    for row in $ACCEPT_ROWS; do
        case " $(a_legs "$row") " in *" $1 "*) ;; *) echo "  skip: $1 $row (see a_legs)"; continue;; esac
        a_src "$row" > "$W/a.cyr"
        cat "$W/a.cyr" | "$2" > "$W/a.out" 2>/dev/null || true
        naccept=$((naccept+1))
        if ! [ -s "$W/a.out" ]; then bad "$1 $row: produced no artifact"; continue; fi
        chmod +x "$W/a.out"
        got=0
        ( ulimit -c 0; "$3" "$W/a.out" ) >/dev/null 2>&1 || got=$?
        want=$(a_want "$row")
        if [ "$got" = "$want" ]; then good "$1 $row = $got"; else bad "$1 $row = $got, want $want"; fi
    done
}

# 6.7.11: the receive rows — each Y refused ONCE (one `error` line), by name, with no artifact.
refuse_v_all() {  # $1 leg label  $2 compiler
    for row in $Y_ROWS; do
        y_src "$row" > "$W/y.cyr"
        rc=0
        cat "$W/y.cyr" | "$2" > "$W/y.out" 2>"$W/y.err" || rc=$?
        nrefuse=$((nrefuse+1))
        ne=$(grep -c '^error' "$W/y.err" 2>/dev/null || true)
        if ! grep -q "$MSGV" "$W/y.err" 2>/dev/null; then
            bad "$1 $row: not refused (rc=$rc, first line: $(head -1 "$W/y.err" 2>/dev/null))"
        elif [ "$ne" != 1 ]; then
            bad "$1 $row: $ne error lines (want 1)"
        elif [ -s "$W/y.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused once"
        fi
    done
}
accept_v_all() {  # $1 leg label  $2 compiler  $3 runner fn name
    for row in $V_ROWS; do
        v_src "$row" > "$W/v.cyr"
        rc=0
        cat "$W/v.cyr" | "$2" > "$W/v.out" 2>"$W/v.err" || rc=$?
        naccept=$((naccept+1))
        if ! [ -s "$W/v.out" ]; then bad "$1 $row: produced no artifact (rc=$rc: $(grep -m1 '^error' "$W/v.err" 2>/dev/null))"; continue; fi
        chmod +x "$W/v.out"
        got=0
        ( ulimit -c 0; "$3" "$W/v.out" ) >/dev/null 2>&1 || got=$?
        if [ "$got" = 42 ]; then good "$1 $row = 42"; else bad "$1 $row = $got, want 42"; fi
    done
}

# 6.7.13: the explicit-instance rows — each E built by the leg's compiler (`$3` an env assignment or -) and run;
# each Z refused once, by its own words, with no artifact.
accept_e_all() {  # $1 leg label  $2 compiler  $3 runner fn name  [$4 VAR=value for the compiler]
    for row in $E_ROWS; do
        e_src "$row" > "$W/e.cyr"
        rc=0
        if [ -n "${4:-}" ]; then env "$4" "$2" < "$W/e.cyr" > "$W/e.out" 2>"$W/e.err" || rc=$?
        else "$2" < "$W/e.cyr" > "$W/e.out" 2>"$W/e.err" || rc=$?; fi
        naccept=$((naccept+1))
        if ! [ -s "$W/e.out" ]; then bad "$1 $row: produced no artifact (rc=$rc: $(grep -m1 '^error' "$W/e.err" 2>/dev/null))"; continue; fi
        chmod +x "$W/e.out"
        got=0
        ( ulimit -c 0; "$3" "$W/e.out" ) >/dev/null 2>&1 || got=$?
        want=$(e_want "$row")
        if [ "$got" = "$want" ]; then good "$1 $row = $got"; else bad "$1 $row = $got, want $want"; fi
    done
}
refuse_z_all() {  # $1 leg label  $2 compiler
    for row in $Z_ROWS; do
        z_src "$row" > "$W/z.cyr"
        rc=0
        "$2" < "$W/z.cyr" > "$W/z.out" 2>"$W/z.err" || rc=$?
        nrefuse=$((nrefuse+1))
        zm=$(z_msg "$row")
        ne=$(grep -c '^error' "$W/z.err" 2>/dev/null || true)
        if ! grep -qF "$zm" "$W/z.err" 2>/dev/null; then
            bad "$1 $row: not refused as '$zm' (rc=$rc, first line: $(head -1 "$W/z.err" 2>/dev/null))"
        elif [ "$ne" != 1 ]; then
            bad "$1 $row: $ne error lines (want 1)"
        elif [ -s "$W/z.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused once"
        fi
    done
}

# 6.7.13 (D29): rows C built by the leg's compiler and run (161); rows Q refused once, by their own words, no artifact.
accept_c_all() {  # $1 leg label  $2 compiler  $3 runner fn name  [$4 VAR=value for the compiler]
    for row in $C_ROWS; do
        c_src "$row" > "$W/c.cyr"
        rc=0
        if [ -n "${4:-}" ]; then env "$4" "$2" < "$W/c.cyr" > "$W/c.out" 2>"$W/c.err" || rc=$?
        else "$2" < "$W/c.cyr" > "$W/c.out" 2>"$W/c.err" || rc=$?; fi
        naccept=$((naccept+1))
        if ! [ -s "$W/c.out" ]; then bad "$1 $row: produced no artifact (rc=$rc: $(grep -m1 '^error' "$W/c.err" 2>/dev/null))"; continue; fi
        chmod +x "$W/c.out"
        got=0
        ( ulimit -c 0; "$3" "$W/c.out" ) >/dev/null 2>&1 || got=$?
        if [ "$got" = 161 ]; then good "$1 $row = 161"; else bad "$1 $row = $got, want 161"; fi
    done
}
refuse_q_all() {  # $1 leg label  $2 compiler
    for row in $Q_ROWS; do
        case " $(q_legs "$row") " in *" $1 "*) ;; *) echo "  skip: $1 $row (see q_legs)"; continue;; esac
        q_src "$row" > "$W/q.cyr"
        rc=0
        "$2" < "$W/q.cyr" > "$W/q.out" 2>"$W/q.err" || rc=$?
        nrefuse=$((nrefuse+1))
        qm=$(q_msg "$row")
        ne=$(grep -c '^error' "$W/q.err" 2>/dev/null || true)
        if ! grep -qF "$qm" "$W/q.err" 2>/dev/null; then
            bad "$1 $row: not refused as '$qm' (rc=$rc, first line: $(head -1 "$W/q.err" 2>/dev/null))"
        elif [ "$ne" != 1 ]; then
            bad "$1 $row: $ne error lines (want 1)"
        elif grep -qF "$TPW" "$W/q.err"; then
            bad "$1 $row: '$TPW' for a vector local (no typed pointer)"
        elif [ -s "$W/q.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused once"
        fi
    done
}

# 6.7.15: QF — the filed repro verbatim (issues/2026-10-17-wrapped-by-name-or-method-call-of-another-vector-into-vector-
# local-generic-words.md): its four wrapped sources refused in the by-name call's words, one line each, in order, and
# no generic receive line ("got `(...)`").
qf_src() { printf '%s' "$QW"'fn run(): i64 { var s: S = S { 1 }; var v: f64v2 = (mk4(41)); var w: f64v2 = (s.mv()); return 1; }
fn run2(): i64 { var s: S = S { 1 }; var v: f64v2; v = (mk4(41)); var w: f64v2; w = (s.mv()); return 1; }
syscall(60, run() + run2());
'; }
refuse_qf_all() {  # $1 leg label  $2 compiler
    qf_src > "$W/qf.cyr"
    rc=0
    "$2" < "$W/qf.cyr" > "$W/qf.out" 2>"$W/qf.err" || rc=$?
    nrefuse=$((nrefuse+1))
    got=$(grep '^error' "$W/qf.err" | sed 's/^error:<source>://' | tr '\n' '|')
    want="4:53: vector return type does not match the declared type|4:79: vector return type does not match the declared type|5:57: vector return type does not match the assigned variable|5:86: vector return type does not match the assigned variable|"
    if [ "$got" != "$want" ]; then bad "$1 QF: '$got' (rc=$rc), want '$want'"
    elif [ -s "$W/qf.out" ]; then bad "$1 QF: reported but still emitted an artifact"
    else good "$1 QF refused: the four lines, the mismatch's words"; fi
}

# 6.7.13 (D34): rows P built by the leg's compiler and run (161); rows K refused once, by their own words, no artifact.
accept_p_all() {  # $1 leg label  $2 compiler  $3 runner fn name  [$4 VAR=value for the compiler]
    for row in $P_ROWS; do
        p_src "$row" > "$W/p.cyr"
        rc=0
        if [ -n "${4:-}" ]; then env "$4" "$2" < "$W/p.cyr" > "$W/p.out" 2>"$W/p.err" || rc=$?
        else "$2" < "$W/p.cyr" > "$W/p.out" 2>"$W/p.err" || rc=$?; fi
        naccept=$((naccept+1))
        if ! [ -s "$W/p.out" ]; then bad "$1 $row: produced no artifact (rc=$rc: $(grep -m1 '^error' "$W/p.err" 2>/dev/null))"; continue; fi
        chmod +x "$W/p.out"
        got=0
        ( ulimit -c 0; "$3" "$W/p.out" ) >/dev/null 2>&1 || got=$?
        if [ "$got" = 161 ]; then good "$1 $row = 161"; else bad "$1 $row = $got, want 161"; fi
    done
}
refuse_k_all() {  # $1 leg label  $2 compiler
    for row in $K_ROWS; do
        k_src "$row" > "$W/k.cyr"
        rc=0
        "$2" < "$W/k.cyr" > "$W/k.out" 2>"$W/k.err" || rc=$?
        nrefuse=$((nrefuse+1))
        km=$(k_msg "$row")
        ne=$(grep -c '^error' "$W/k.err" 2>/dev/null || true)
        if ! grep -qF "$km" "$W/k.err" 2>/dev/null; then
            bad "$1 $row: not refused as '$km' (rc=$rc, first line: $(head -1 "$W/k.err" 2>/dev/null))"
        elif [ "$ne" != 1 ]; then
            bad "$1 $row: $ne error lines (want 1)"
        elif [ -s "$W/k.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused once"
        fi
    done
}

# 6.7.14 (D35, D36; D37-D39): a table's rows built by the leg's compiler (`$6` an env assignment, or none) and run (161).
accept_tab_all() {  # $1 leg label  $2 compiler  $3 runner fn name  $4 source fn  $5 rows  [$6 VAR=value]
    for row in $5; do
        "$4" "$row" > "$W/d.cyr"
        rc=0
        if [ -n "${6:-}" ]; then env "$6" "$2" < "$W/d.cyr" > "$W/d.out" 2>"$W/d.err" || rc=$?
        else "$2" < "$W/d.cyr" > "$W/d.out" 2>"$W/d.err" || rc=$?; fi
        naccept=$((naccept+1))
        if ! [ -s "$W/d.out" ]; then bad "$1 $row: produced no artifact (rc=$rc: $(grep -m1 '^error' "$W/d.err" 2>/dev/null))"; continue; fi
        if grep -q '^error' "$W/d.err"; then bad "$1 $row: an error line: $(grep -m1 '^error' "$W/d.err")"; continue; fi
        chmod +x "$W/d.out"
        got=0
        ( ulimit -c 0; "$3" "$W/d.out" ) >/dev/null 2>&1 || got=$?
        if [ "$got" = 161 ]; then good "$1 $row = 161"; else bad "$1 $row = $got, want 161"; fi
    done
}
# ... and a table's rows refused once, an error line holding `$5 <row>`'s words, no artifact.
refuse_tab_all() {  # $1 leg label  $2 compiler  $3 source fn  $4 rows  $5 message fn  [$6 VAR=value]
    for row in $4; do
        "$3" "$row" > "$W/dk.cyr"
        rc=0
        if [ -n "${6:-}" ]; then env "$6" "$2" < "$W/dk.cyr" > "$W/dk.out" 2>"$W/dk.err" || rc=$?
        else "$2" < "$W/dk.cyr" > "$W/dk.out" 2>"$W/dk.err" || rc=$?; fi
        nrefuse=$((nrefuse+1))
        km=$("$5" "$row")
        ne=$(grep -c '^error' "$W/dk.err" 2>/dev/null || true)
        if ! grep '^error' "$W/dk.err" | grep -qF -- "$km"; then
            bad "$1 $row: not refused as '$km' (rc=$rc, first line: $(grep -m1 '^error' "$W/dk.err" 2>/dev/null))"
        elif [ "$ne" != 1 ]; then
            bad "$1 $row: $ne error lines (want 1)"
        elif [ -s "$W/dk.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused once"
        fi
    done
}
dk_msg() { echo "$MSG in a fixed register pair, so \`return\` takes a local of that vector type or a call to a fn declared to return the same one — got \`$(dk_got "$1")\`"; }
# 6.7.16: a table's rows refused with exactly two error lines — the first holding line 1 of `$5 <row>`, the second line 2 —
# and no artifact (a refusal made in sync, and the next statement's own error).
refuse2_tab_all() {  # $1 leg label  $2 compiler  $3 source fn  $4 rows  $5 message fn  [$6 VAR=value]
    for row in $4; do
        "$3" "$row" > "$W/d2.cyr"
        rc=0
        if [ -n "${6:-}" ]; then env "$6" "$2" < "$W/d2.cyr" > "$W/d2.out" 2>"$W/d2.err" || rc=$?
        else "$2" < "$W/d2.cyr" > "$W/d2.out" 2>"$W/d2.err" || rc=$?; fi
        nrefuse=$((nrefuse+1))
        m1=$("$5" "$row" | sed -n 1p)
        m2=$("$5" "$row" | sed -n 2p)
        ne=$(grep -c '^error' "$W/d2.err" 2>/dev/null || true)
        if [ "$ne" != 2 ]; then bad "$1 $row: $ne error lines (want 2; rc=$rc: $(grep '^error' "$W/d2.err" | tr '\n' ' '))"
        elif ! grep '^error' "$W/d2.err" | sed -n 1p | grep -qF -- "$m1"; then bad "$1 $row: first error not '$m1'"
        elif ! grep '^error' "$W/d2.err" | sed -n 2p | grep -qF -- "$m2"; then bad "$1 $row: second error not '$m2'"
        elif [ -s "$W/d2.out" ]; then bad "$1 $row: reported but still emitted an artifact"
        else good "$1 $row refused, the next statement's error kept"; fi
    done
}

# 6.7.13: rows H — the refusal's words, or (H5 H9) the undefined-function path alone; one `error` line, no artifact.
refuse_h_all() {  # $1 leg label  $2 compiler
    for row in $H_ROWS; do
        h_src "$row" > "$W/h.cyr"
        rc=0
        "$2" < "$W/h.cyr" > "$W/h.out" 2>"$W/h.err" || rc=$?
        nrefuse=$((nrefuse+1))
        ne=$(grep -c '^error' "$W/h.err" 2>/dev/null || true)
        nv=$(grep -c "$MSGV" "$W/h.err" 2>/dev/null || true)
        nh=$(grep -c "$HINT" "$W/h.err" 2>/dev/null || true)
        hk=$(h_kind "$row")
        hg="- got \`$(h_got "$row")\`"
        if [ -s "$W/h.out" ]; then
            bad "$1 $row: emitted an artifact (rc=$rc)"
        elif [ "$ne" != 1 ]; then
            bad "$1 $row: $ne error lines (want 1; first: $(head -1 "$W/h.err" 2>/dev/null))"
        elif [ "$hk" = undef ]; then
            if [ "$nv" != 0 ]; then bad "$1 $row: the receive refused a call naming no fn ($(grep -m1 "$MSGV" "$W/h.err" | cut -c1-120))"
            elif grep -qF "$MSG" "$W/h.err"; then bad "$1 $row: the return rule refused a call naming no fn"
            elif grep -qF "$TPW" "$W/h.err"; then bad "$1 $row: '$TPW' for a vector local (no typed pointer)"
            elif ! grep -qF "undefined function 'f64v2_splat'" "$W/h.err"; then bad "$1 $row: no undefined-function warning"
            elif ! grep -qF "refusing to emit" "$W/h.err"; then bad "$1 $row: no refusing-to-emit line"
            else good "$1 $row: the undefined-function path alone"; fi
        elif [ "$nv" != 1 ]; then
            bad "$1 $row: not refused by the receive (rc=$rc, first line: $(head -1 "$W/h.err" 2>/dev/null))"
        elif ! grep -qF "$MSGL" "$W/h.err"; then
            bad "$1 $row: the accepted list does not name the dereference ('$MSGL')"
        elif ! grep -qF -e "$hg" "$W/h.err"; then
            bad "$1 $row: does not name its source ('$hg')"
        elif [ "$hk" = hint ] && [ "$nh" != 1 ]; then
            bad "$1 $row: the fn-pointer hint is missing (a callee held in a variable)"
        elif [ "$hk" = plain ] && [ "$nh" != 0 ]; then
            bad "$1 $row: the fn-pointer hint printed for a source it does not fit"
        else
            good "$1 $row refused once ($hk)"
        fi
    done
}

# 6.7.14: row TP, the control of the typed-pointer warning that skips a vector local: `p = 5;` into a `*Pt` local and
# `q = 7;` into a `*i64` one still warn, twice, and compile.
TPW="assigning non-pointer to typed pointer"
tp_ctl_all() {  # $1 leg label  $2 compiler
    printf '%s' 'struct Pt { x; y; }
fn run(): i64 { var p: *Pt = 0; p = 5; var q: *i64 = 0; q = 7; var s = 0; s = 9; return 1; }
syscall(60, run());
' > "$W/tp.cyr"
    rc=0
    "$2" < "$W/tp.cyr" > "$W/tp.out" 2>"$W/tp.err" || rc=$?
    nrefuse=$((nrefuse+1))
    nt=$(grep -c "^warning.*$TPW" "$W/tp.err" 2>/dev/null || true)
    if [ "$rc" != 0 ]; then bad "$1 TP: the control did not compile (rc=$rc: $(grep -m1 '^error' "$W/tp.err"))"
    elif [ "$nt" != 2 ]; then bad "$1 TP: $nt typed-pointer warnings, want 2 (\`p = 5;\` into *Pt, \`q = 7;\` into *i64)"
    else good "$1 TP: the typed-pointer warning still fires for *Pt and *i64 locals"; fi
}

# 6.7.14: row H16, the filed return repro verbatim — its fn is never called, so x86_64 / aarch64 / PE build it with the
# undefined-function warning alone (as the unwrapped local does) and cx refuses the unresolved call: on every leg no
# `error:<source>` line, no vector-return line, and the warning.
undef_ret_all() {  # $1 leg label  $2 compiler
    h_src H16 > "$W/h16.cyr"
    rc=0
    "$2" < "$W/h16.cyr" > "$W/h16.out" 2>"$W/h16.err" || rc=$?
    nrefuse=$((nrefuse+1))
    if grep -qF "$MSG" "$W/h16.err"; then bad "$1 H16: the return rule refused a call naming no fn (rc=$rc)"
    elif grep -q '^error:<source>' "$W/h16.err"; then bad "$1 H16: an error at the source: $(grep -m1 '^error:<source>' "$W/h16.err" | cut -c1-120)"
    elif ! grep -qF "undefined function 'f64v2_splat'" "$W/h16.err"; then bad "$1 H16: no undefined-function warning (rc=$rc)"
    else good "$1 H16: the undefined-function warning alone (rc=$rc)"; fi
}

# 6.7.14 (D43): rows T refused once, naming what they refuse, no artifact; rows U built and run (83).
refuse_t_all() {  # $1 leg label  $2 compiler
    for row in $T_ROWS; do
        t_src "$row" > "$W/t.cyr"
        rc=0
        "$2" < "$W/t.cyr" > "$W/t.out" 2>"$W/t.err" || rc=$?
        nrefuse=$((nrefuse+1))
        ne=$(grep -c '^error' "$W/t.err" 2>/dev/null || true)
        tg="$MSG in a fixed register pair, so \`return\` takes a local of that vector type or a call to a fn declared to return the same one — got \`$(t_got "$row")\`"
        if ! grep -qF -e "$tg" "$W/t.err" 2>/dev/null; then
            bad "$1 $row: not refused as '...got \`$(t_got "$row")\`' (rc=$rc, first line: $(head -1 "$W/t.err" 2>/dev/null))"
        elif [ "$ne" != 1 ]; then
            bad "$1 $row: $ne error lines (want 1)"
        elif [ -s "$W/t.out" ]; then
            bad "$1 $row: reported but still emitted an artifact"
        else
            good "$1 $row refused once"
        fi
    done
}
accept_u_all() {  # $1 leg label  $2 compiler  $3 runner fn name
    for row in $U_ROWS; do
        u_src "$row" > "$W/u.cyr"
        rc=0
        "$2" < "$W/u.cyr" > "$W/u.out" 2>"$W/u.err" || rc=$?
        naccept=$((naccept+1))
        if ! [ -s "$W/u.out" ]; then bad "$1 $row: produced no artifact (rc=$rc: $(grep -m1 '^error' "$W/u.err" 2>/dev/null))"; continue; fi
        chmod +x "$W/u.out"
        got=0
        ( ulimit -c 0; "$3" "$W/u.out" ) >/dev/null 2>&1 || got=$?
        if [ "$got" = 83 ]; then good "$1 $row = 83"; else bad "$1 $row = $got, want 83"; fi
    done
}

hostr() { timeout 60 "$1"; }
echo "host x86_64:"
refuse_all host "$CC"
accept_all host "$CC" hostr
refuse_v_all host "$CC"
accept_v_all host "$CC" hostr
accept_e_all host "$CC" hostr
accept_e_all host-ir3 "$CC" hostr CYRIUS_IR=3
refuse_z_all host "$CC"
accept_c_all host "$CC" hostr
accept_c_all host-ir3 "$CC" hostr CYRIUS_IR=3
refuse_q_all host "$CC"
refuse_qf_all host "$CC"
accept_p_all host "$CC" hostr
accept_p_all host-ir3 "$CC" hostr CYRIUS_IR=3
refuse_k_all host "$CC"
accept_tab_all host "$CC" hostr d_src "$D_ROWS"
accept_tab_all host-ir3 "$CC" hostr d_src "$D_ROWS" CYRIUS_IR=3
refuse_tab_all host "$CC" dk_src "$DK_ROWS" dk_msg
dv_compile host "$CC"
dv_compile host-ir3 "$CC" CYRIUS_IR=3
accept_tab_all host "$CC" hostr m_src "$M_ROWS"
accept_tab_all host-ir3 "$CC" hostr m_src "$M_ROWS" CYRIUS_IR=3
refuse_tab_all host "$CC" mk_src "$MK_ROWS" mk_msg
accept_tab_all host "$CC" hostr cr_src "$CR_ROWS"
accept_tab_all host "$CC" hostr n_src "$N_ROWS"
accept_tab_all host-ir3 "$CC" hostr n_src "$N_ROWS" CYRIUS_IR=3
refuse_tab_all host "$CC" nk_src "$NK_ROWS" nk_msg
refuse_tab_all host-ir3 "$CC" nk_src "$NK_ROWS" nk_msg CYRIUS_IR=3
accept_tab_all host-ir3 "$CC" hostr cr_src "$CR_ROWS" CYRIUS_IR=3
refuse_tab_all host "$CC" crk_src "$CRK_ROWS" crk_msg
refuse_tab_all host-ir3 "$CC" crk_src "$CRK_ROWS" crk_msg CYRIUS_IR=3
accept_tab_all host "$CC" hostr wr_src "$WR_ROWS"
accept_tab_all host-ir3 "$CC" hostr wr_src "$WR_ROWS" CYRIUS_IR=3
refuse_tab_all host "$CC" wrk_src "$WRK_ROWS" wrk_msg
refuse_tab_all host-ir3 "$CC" wrk_src "$WRK_ROWS" wrk_msg CYRIUS_IR=3
refuse_tab_all host "$CC" ga_src "$GA_ROWS" ga_msg
refuse_tab_all host-ir3 "$CC" ga_src "$GA_ROWS" ga_msg CYRIUS_IR=3
refuse_tab_all host "$CC" gt_src "$GT_ROWS" gt_msg
refuse_tab_all host-ir3 "$CC" gt_src "$GT_ROWS" gt_msg CYRIUS_IR=3
refuse_gaf_all host "$CC"
refuse_tab_all host "$CC" tl_src "$TL_ROWS" tl_msg
refuse_tab_all host-ir3 "$CC" tl_src "$TL_ROWS" tl_msg CYRIUS_IR=3
refuse_tab_all host "$CC" op_src "$OP_ROWS" op_msg
refuse_tab_all host-ir3 "$CC" op_src "$OP_ROWS" op_msg CYRIUS_IR=3
accept_tab_all host "$CC" hostr opc_src "$OPC_ROWS"
accept_tab_all host-ir3 "$CC" hostr opc_src "$OPC_ROWS" CYRIUS_IR=3
refuse_tab_all host "$CC" rv_src "$RV_ROWS" rv_msg
refuse_tab_all host-ir3 "$CC" rv_src "$RV_ROWS" rv_msg CYRIUS_IR=3
accept_tab_all host "$CC" hostr rvc_src "$RVC_ROWS"
accept_tab_all host-ir3 "$CC" hostr rvc_src "$RVC_ROWS" CYRIUS_IR=3
refuse_tab_all host "$CC" sx_src "$SX_ROWS" sx_msg
refuse_tab_all host-ir3 "$CC" sx_src "$SX_ROWS" sx_msg CYRIUS_IR=3
refuse_tab_all host "$CC" va_src "$VA_ROWS" va_msg
refuse_tab_all host-ir3 "$CC" va_src "$VA_ROWS" va_msg CYRIUS_IR=3
refuse2_tab_all host "$CC" vas_src "$VAS_ROWS" vas_msg
refuse2_tab_all host-ir3 "$CC" vas_src "$VAS_ROWS" vas_msg CYRIUS_IR=3
refuse_tab_all host "$CC" vo_src "$VO_ROWS" vo_msg
refuse_tab_all host-ir3 "$CC" vo_src "$VO_ROWS" vo_msg CYRIUS_IR=3
refuse2_tab_all host "$CC" vos_src "$VOS_ROWS" vos_msg
refuse2_tab_all host-ir3 "$CC" vos_src "$VOS_ROWS" vos_msg CYRIUS_IR=3
accept_tab_all host "$CC" hostr voc_src "$VOC_ROWS"
accept_tab_all host-ir3 "$CC" hostr voc_src "$VOC_ROWS" CYRIUS_IR=3
refuse_tab_all host "$CC" vco_src "$VCO_ROWS" vco_msg
refuse_tab_all host-ir3 "$CC" vco_src "$VCO_ROWS" vco_msg CYRIUS_IR=3
refuse2_tab_all host "$CC" vco_src "$VCO2_ROWS" vco_msg
refuse2_tab_all host-ir3 "$CC" vco_src "$VCO2_ROWS" vco_msg CYRIUS_IR=3
refuse_tab_all host "$CC" vl_src "$VL_ROWS" vl_msg
refuse_tab_all host-ir3 "$CC" vl_src "$VL_ROWS" vl_msg CYRIUS_IR=3
refuse2_tab_all host "$CC" vls_src "$VLS_ROWS" vls_msg
refuse2_tab_all host-ir3 "$CC" vls_src "$VLS_ROWS" vls_msg CYRIUS_IR=3
accept_tab_all host "$CC" hostr vlc_src "$VLC_ROWS"
accept_tab_all host-ir3 "$CC" hostr vlc_src "$VLC_ROWS" CYRIUS_IR=3
refuse_ver_all host "$CC"
accept_want_all host "$CC" hostr vs_src "$VS_ROWS" vs_want
accept_want_all host-ir3 "$CC" hostr vs_src "$VS_ROWS" vs_want CYRIUS_IR=3
refuse_tab_all host "$CC" vsk_src "$VSK_ROWS" vsk_msg
refuse_tab_all host-ir3 "$CC" vsk_src "$VSK_ROWS" vsk_msg CYRIUS_IR=3
refuse2_tab_all host "$CC" ws_src "$WS_ROWS" ws_msg
refuse2_tab_all host-ir3 "$CC" ws_src "$WS_ROWS" ws_msg CYRIUS_IR=3
refuse_tab_all host "$CC" wf_src "$WF_ROWS" wf_msg
refuse_tab_all host-ir3 "$CC" wf_src "$WF_ROWS" wf_msg CYRIUS_IR=3
refuse_fw_all host "$CC"
refuse_fw_all host-ir3 "$CC" CYRIUS_IR=3
refuse_tab_all host "$CC" vn_src "$VN_ROWS" vn_msg
refuse_tab_all host-ir3 "$CC" vn_src "$VN_ROWS" vn_msg CYRIUS_IR=3
refuse2_tab_all host "$CC" vns_src "$VNS_ROWS" vns_msg
refuse2_tab_all host-ir3 "$CC" vns_src "$VNS_ROWS" vns_msg CYRIUS_IR=3
refuse_tab_all host "$CC" vg_src "$VG_ROWS" vg_msg
refuse_tab_all host-ir3 "$CC" vg_src "$VG_ROWS" vg_msg CYRIUS_IR=3
accept_tab_all host "$CC" hostr vac_src "$VAC_ROWS"
accept_tab_all host-ir3 "$CC" hostr vac_src "$VAC_ROWS" CYRIUS_IR=3
accept_tab_all host "$CC" hostr gc_src "$GC_ROWS"
accept_tab_all host-ir3 "$CC" hostr gc_src "$GC_ROWS" CYRIUS_IR=3
refuse_h_all host "$CC"
undef_ret_all host "$CC"
tp_ctl_all host "$CC"
refuse_t_all host "$CC"
accept_u_all host "$CC" hostr

echo "cx (cxvm):"
if cat src/main_cx.cyr | "$CC" > "$W/cycc_cx" 2>/dev/null && [ -s "$W/cycc_cx" ] \
   && cat programs/cxvm.cyr | "$CC" > "$W/cxvm" 2>/dev/null && [ -s "$W/cxvm" ]; then
    chmod +x "$W/cycc_cx" "$W/cxvm"
    cxr() { timeout 60 "$W/cxvm" < "$1"; }
    refuse_all cx "$W/cycc_cx"
    accept_all cx "$W/cycc_cx" cxr
    refuse_v_all cx "$W/cycc_cx"
    accept_v_all cx "$W/cycc_cx" cxr
    accept_e_all cx "$W/cycc_cx" cxr
    refuse_z_all cx "$W/cycc_cx"
    accept_c_all cx "$W/cycc_cx" cxr
    refuse_q_all cx "$W/cycc_cx"
    refuse_qf_all cx "$W/cycc_cx"
    accept_p_all cx "$W/cycc_cx" cxr
    refuse_k_all cx "$W/cycc_cx"
    accept_tab_all cx "$W/cycc_cx" cxr d_src "$D_ROWS"
    refuse_tab_all cx "$W/cycc_cx" dk_src "$DK_ROWS" dk_msg
    dv_compile cx "$W/cycc_cx"
    accept_tab_all cx "$W/cycc_cx" cxr m_src "$M_ROWS"
    refuse_tab_all cx "$W/cycc_cx" mk_src "$MK_ROWS" mk_msg
    accept_tab_all cx "$W/cycc_cx" cxr cr_src "$CR_ROWS"
    accept_tab_all cx "$W/cycc_cx" cxr n_src "$N_ROWS"
    refuse_tab_all cx "$W/cycc_cx" nk_src "$NK_ROWS" nk_msg
    refuse_tab_all cx "$W/cycc_cx" crk_src "$CRK_ROWS" crk_msg
    accept_tab_all cx "$W/cycc_cx" cxr wr_src "$WR_ROWS"
    refuse_tab_all cx "$W/cycc_cx" wrk_src "$WRK_ROWS" wrk_msg
    refuse_tab_all cx "$W/cycc_cx" ga_src "$GA_ROWS" ga_msg
    refuse_tab_all cx "$W/cycc_cx" gt_src "$GT_ROWS" gt_msg
    refuse_gaf_all cx "$W/cycc_cx"
    refuse_tab_all cx "$W/cycc_cx" tl_src "$TL_ROWS" tl_msg
    refuse_tab_all cx "$W/cycc_cx" op_src "$OP_ROWS" op_msg
    accept_tab_all cx "$W/cycc_cx" cxr opc_src "$OPC_ROWS"
    refuse_tab_all cx "$W/cycc_cx" rv_src "$RV_ROWS" rv_msg
    accept_tab_all cx "$W/cycc_cx" cxr rvc_src "$RVC_ROWS"
    refuse_tab_all cx "$W/cycc_cx" sx_src "$SX_ROWS" sx_msg
    refuse_tab_all cx "$W/cycc_cx" va_src "$VA_ROWS" va_msg
    refuse2_tab_all cx "$W/cycc_cx" vas_src "$VAS_ROWS" vas_msg
    refuse_tab_all cx "$W/cycc_cx" vo_src "$VO_ROWS" vo_msg
    refuse2_tab_all cx "$W/cycc_cx" vos_src "$VOS_ROWS" vos_msg
    accept_tab_all cx "$W/cycc_cx" cxr voc_src "$VOC_ROWS"
    refuse_tab_all cx "$W/cycc_cx" vco_src "$VCO_ROWS" vco_msg
    refuse2_tab_all cx "$W/cycc_cx" vco_src "$VCO2_ROWS" vco_msg
    refuse_tab_all cx "$W/cycc_cx" vl_src "$VL_ROWS" vl_msg
    refuse2_tab_all cx "$W/cycc_cx" vls_src "$VLS_ROWS" vls_msg
    accept_tab_all cx "$W/cycc_cx" cxr vlc_src "$VLC_ROWS"
    refuse_ver_all cx "$W/cycc_cx"
    accept_want_all cx "$W/cycc_cx" cxr vs_src "$VS_ROWS" vs_want
    refuse_tab_all cx "$W/cycc_cx" vsk_src "$VSK_ROWS" vsk_msg
    refuse2_tab_all cx "$W/cycc_cx" ws_src "$WS_ROWS" ws_msg
    refuse_tab_all cx "$W/cycc_cx" wf_src "$WF_ROWS" wf_msg
    refuse_fw_all cx "$W/cycc_cx"
    refuse_tab_all cx "$W/cycc_cx" vn_src "$VN_ROWS" vn_msg
    refuse2_tab_all cx "$W/cycc_cx" vns_src "$VNS_ROWS" vns_msg
    refuse_tab_all cx "$W/cycc_cx" vg_src "$VG_ROWS" vg_msg
    accept_tab_all cx "$W/cycc_cx" cxr vac_src "$VAC_ROWS"
    accept_tab_all cx "$W/cycc_cx" cxr gc_src "$GC_ROWS"
    refuse_h_all cx "$W/cycc_cx"
undef_ret_all cx "$W/cycc_cx"
tp_ctl_all cx "$W/cycc_cx"
    refuse_t_all cx "$W/cycc_cx"
    accept_u_all cx "$W/cycc_cx" cxr
else
    bad "cx leg: could not build src/main_cx.cyr / programs/cxvm.cyr"
fi

if command -v qemu-aarch64 > /dev/null 2>&1; then
    echo "aarch64 (qemu-aarch64 — EMULATION, not hardware):"
    if cat src/main_aarch64.cyr | "$CC" > "$W/cycc_a64" 2>/dev/null && [ -s "$W/cycc_a64" ]; then
        chmod +x "$W/cycc_a64"
        a64r() { timeout 120 qemu-aarch64 "$1"; }
        refuse_all aarch64 "$W/cycc_a64"
        accept_all aarch64 "$W/cycc_a64" a64r
        refuse_v_all aarch64 "$W/cycc_a64"
        accept_v_all aarch64 "$W/cycc_a64" a64r
        accept_e_all aarch64 "$W/cycc_a64" a64r
        refuse_z_all aarch64 "$W/cycc_a64"
        accept_c_all aarch64 "$W/cycc_a64" a64r
        refuse_q_all aarch64 "$W/cycc_a64"
        refuse_qf_all aarch64 "$W/cycc_a64"
        accept_p_all aarch64 "$W/cycc_a64" a64r
        refuse_k_all aarch64 "$W/cycc_a64"
        accept_tab_all aarch64 "$W/cycc_a64" a64r d_src "$D_ROWS"
        refuse_tab_all aarch64 "$W/cycc_a64" dk_src "$DK_ROWS" dk_msg
        dv_compile aarch64 "$W/cycc_a64"
        accept_tab_all aarch64 "$W/cycc_a64" a64r m_src "$M_ROWS"
        refuse_tab_all aarch64 "$W/cycc_a64" mk_src "$MK_ROWS" mk_msg
        accept_tab_all aarch64 "$W/cycc_a64" a64r cr_src "$CR_ROWS"
        accept_tab_all aarch64 "$W/cycc_a64" a64r n_src "$N_ROWS"
        refuse_tab_all aarch64 "$W/cycc_a64" nk_src "$NK_ROWS" nk_msg
        refuse_tab_all aarch64 "$W/cycc_a64" crk_src "$CRK_ROWS" crk_msg
        accept_tab_all aarch64 "$W/cycc_a64" a64r wr_src "$WR_ROWS"
        refuse_tab_all aarch64 "$W/cycc_a64" wrk_src "$WRK_ROWS" wrk_msg
        refuse_tab_all aarch64 "$W/cycc_a64" ga_src "$GA_ROWS" ga_msg
        refuse_tab_all aarch64 "$W/cycc_a64" gt_src "$GT_ROWS" gt_msg
        refuse_gaf_all aarch64 "$W/cycc_a64"
        refuse_tab_all aarch64 "$W/cycc_a64" tl_src "$TL_ROWS" tl_msg
        refuse_tab_all aarch64 "$W/cycc_a64" op_src "$OP_ROWS" op_msg
        accept_tab_all aarch64 "$W/cycc_a64" a64r opc_src "$OPC_ROWS"
        refuse_tab_all aarch64 "$W/cycc_a64" rv_src "$RV_ROWS" rv_msg
        accept_tab_all aarch64 "$W/cycc_a64" a64r rvc_src "$RVC_ROWS"
        refuse_tab_all aarch64 "$W/cycc_a64" sx_src "$SX_ROWS" sx_msg
        refuse_tab_all aarch64 "$W/cycc_a64" va_src "$VA_ROWS" va_msg
        refuse2_tab_all aarch64 "$W/cycc_a64" vas_src "$VAS_ROWS" vas_msg
        refuse_tab_all aarch64 "$W/cycc_a64" vo_src "$VO_ROWS" vo_msg
        refuse2_tab_all aarch64 "$W/cycc_a64" vos_src "$VOS_ROWS" vos_msg
        accept_tab_all aarch64 "$W/cycc_a64" a64r voc_src "$VOC_ROWS"
        refuse_tab_all aarch64 "$W/cycc_a64" vco_src "$VCO_ROWS" vco_msg
        refuse2_tab_all aarch64 "$W/cycc_a64" vco_src "$VCO2_ROWS" vco_msg
        refuse_tab_all aarch64 "$W/cycc_a64" vl_src "$VL_ROWS" vl_msg
        refuse2_tab_all aarch64 "$W/cycc_a64" vls_src "$VLS_ROWS" vls_msg
        accept_tab_all aarch64 "$W/cycc_a64" a64r vlc_src "$VLC_ROWS"
        refuse_ver_all aarch64 "$W/cycc_a64"
        accept_want_all aarch64 "$W/cycc_a64" a64r vs_src "$VS_ROWS" vs_want
        refuse_tab_all aarch64 "$W/cycc_a64" vsk_src "$VSK_ROWS" vsk_msg
        refuse2_tab_all aarch64 "$W/cycc_a64" ws_src "$WS_ROWS" ws_msg
        refuse_tab_all aarch64 "$W/cycc_a64" wf_src "$WF_ROWS" wf_msg
        refuse_fw_all aarch64 "$W/cycc_a64"
        refuse_tab_all aarch64 "$W/cycc_a64" vn_src "$VN_ROWS" vn_msg
        refuse2_tab_all aarch64 "$W/cycc_a64" vns_src "$VNS_ROWS" vns_msg
        refuse_tab_all aarch64 "$W/cycc_a64" vg_src "$VG_ROWS" vg_msg
        accept_tab_all aarch64 "$W/cycc_a64" a64r vac_src "$VAC_ROWS"
        accept_tab_all aarch64 "$W/cycc_a64" a64r gc_src "$GC_ROWS"
        refuse_h_all aarch64 "$W/cycc_a64"
undef_ret_all aarch64 "$W/cycc_a64"
tp_ctl_all aarch64 "$W/cycc_a64"
        refuse_t_all aarch64 "$W/cycc_a64"
        accept_u_all aarch64 "$W/cycc_a64" a64r
    else
        bad "aarch64 leg: could not build src/main_aarch64.cyr"
    fi
else
    echo "  SKIP: qemu-aarch64 not installed (the pi hardware leg still covers it)"
    GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
fi

if command -v wine > /dev/null 2>&1; then
    echo "win64 (wine — EMULATION, not hardware; the PE arm is the one this refusal sits in front of):"
    export WINEPREFIX="$W/wine" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d'
    if cat src/main_win.cyr | "$CC" > "$W/cycc_win" 2>/dev/null && [ -s "$W/cycc_win" ]; then
        chmod +x "$W/cycc_win"
        wr_() { cp "$1" "$1.exe"; timeout 180 wine "$1.exe"; }
        refuse_all win64 "$W/cycc_win"
        accept_all win64 "$W/cycc_win" wr_
        refuse_v_all win64 "$W/cycc_win"
        accept_v_all win64 "$W/cycc_win" wr_
        accept_e_all win64 "$W/cycc_win" wr_
        refuse_z_all win64 "$W/cycc_win"
        accept_c_all win64 "$W/cycc_win" wr_
        refuse_q_all win64 "$W/cycc_win"
        refuse_qf_all win64 "$W/cycc_win"
        accept_p_all win64 "$W/cycc_win" wr_
        refuse_k_all win64 "$W/cycc_win"
        accept_tab_all win64 "$W/cycc_win" wr_ d_src "$D_ROWS"
        refuse_tab_all win64 "$W/cycc_win" dk_src "$DK_ROWS" dk_msg
        dv_compile win64 "$W/cycc_win"
        accept_tab_all win64 "$W/cycc_win" wr_ m_src "$M_ROWS"
        refuse_tab_all win64 "$W/cycc_win" mk_src "$MK_ROWS" mk_msg
        accept_tab_all win64 "$W/cycc_win" wr_ cr_src "$CR_ROWS"
        accept_tab_all win64 "$W/cycc_win" wr_ n_src "$N_ROWS"
        refuse_tab_all win64 "$W/cycc_win" nk_src "$NK_ROWS" nk_msg
        refuse_tab_all win64 "$W/cycc_win" crk_src "$CRK_ROWS" crk_msg
        accept_tab_all win64 "$W/cycc_win" wr_ wr_src "$WR_ROWS"
        refuse_tab_all win64 "$W/cycc_win" wrk_src "$WRK_ROWS" wrk_msg
        refuse_tab_all win64 "$W/cycc_win" ga_src "$GA_ROWS" ga_msg
        refuse_tab_all win64 "$W/cycc_win" gt_src "$GT_ROWS" gt_msg
        refuse_gaf_all win64 "$W/cycc_win"
        refuse_tab_all win64 "$W/cycc_win" tl_src "$TL_ROWS" tl_msg
        refuse_tab_all win64 "$W/cycc_win" op_src "$OP_ROWS" op_msg
        accept_tab_all win64 "$W/cycc_win" wr_ opc_src "$OPC_ROWS"
        refuse_tab_all win64 "$W/cycc_win" rv_src "$RV_ROWS" rv_msg
        accept_tab_all win64 "$W/cycc_win" wr_ rvc_src "$RVC_ROWS"
        refuse_tab_all win64 "$W/cycc_win" sx_src "$SX_ROWS" sx_msg
        refuse_tab_all win64 "$W/cycc_win" va_src "$VA_ROWS" va_msg
        refuse2_tab_all win64 "$W/cycc_win" vas_src "$VAS_ROWS" vas_msg
        refuse_tab_all win64 "$W/cycc_win" vo_src "$VO_ROWS" vo_msg
        refuse2_tab_all win64 "$W/cycc_win" vos_src "$VOS_ROWS" vos_msg
        accept_tab_all win64 "$W/cycc_win" wr_ voc_src "$VOC_ROWS"
        refuse_tab_all win64 "$W/cycc_win" vco_src "$VCO_ROWS" vco_msg
        refuse2_tab_all win64 "$W/cycc_win" vco_src "$VCO2_ROWS" vco_msg
        refuse_tab_all win64 "$W/cycc_win" vl_src "$VL_ROWS" vl_msg
        refuse2_tab_all win64 "$W/cycc_win" vls_src "$VLS_ROWS" vls_msg
        accept_tab_all win64 "$W/cycc_win" wr_ vlc_src "$VLC_ROWS"
        refuse_ver_all win64 "$W/cycc_win"
        accept_want_all win64 "$W/cycc_win" wr_ vs_src "$VS_ROWS" vs_want
        refuse_tab_all win64 "$W/cycc_win" vsk_src "$VSK_ROWS" vsk_msg
        refuse2_tab_all win64 "$W/cycc_win" ws_src "$WS_ROWS" ws_msg
        refuse_tab_all win64 "$W/cycc_win" wf_src "$WF_ROWS" wf_msg
        refuse_fw_all win64 "$W/cycc_win"
        refuse_tab_all win64 "$W/cycc_win" vn_src "$VN_ROWS" vn_msg
        refuse2_tab_all win64 "$W/cycc_win" vns_src "$VNS_ROWS" vns_msg
        refuse_tab_all win64 "$W/cycc_win" vg_src "$VG_ROWS" vg_msg
        accept_tab_all win64 "$W/cycc_win" wr_ vac_src "$VAC_ROWS"
        accept_tab_all win64 "$W/cycc_win" wr_ gc_src "$GC_ROWS"
        refuse_h_all win64 "$W/cycc_win"
undef_ret_all win64 "$W/cycc_win"
tp_ctl_all win64 "$W/cycc_win"
        refuse_t_all win64 "$W/cycc_win"
        accept_u_all win64 "$W/cycc_win" wr_
    else
        bad "win64 leg: could not build src/main_win.cyr"
    fi
    wineserver -k > /dev/null 2>&1 || true
else
    echo "  SKIP: wine not installed (the cass hardware leg still covers it)"
    GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
fi

# Anti-vacuous. The floor is DERIVED from the row tables (every row on host + cx, the two legs
# that are always present) so adding a row cannot leave a stale hard-coded number behind.
nr_rows=$(set -- $REFUSE_ROWS $Y_ROWS $Z_ROWS $Q_ROWS QF $K_ROWS $H_ROWS H16 TP $T_ROWS $DK_ROWS $MK_ROWS $CRK_ROWS $NK_ROWS $WRK_ROWS $GA_ROWS GAF $TL_ROWS $GT_ROWS $OP_ROWS $RV_ROWS $SX_ROWS $VA_ROWS $VAS_ROWS $VO_ROWS $VOS_ROWS $WS_ROWS $WF_ROWS $FW_ROWS $VN_ROWS $VNS_ROWS $VG_ROWS $VSK_ROWS $VCO_ROWS $VCO2_ROWS $VL_ROWS $VLS_ROWS $VER_ROWS; echo $#)   # 6.7.13: + Q, K, H; 6.7.14: + T, DK, MK; 6.7.15: + QF, CRK, NK, WRK, GA, GAF, TL; 6.7.16: + GT, OP, RV, SX, VA, VAS, VO, VOS, WS, WF, FW, VN, VNS, VG; 6.7.17: + VSK, VCO, VL, VLS, VER (every row runs on host + cx)
[ "$nrefuse" -ge $((nr_rows * 2)) ] || bad "only $nrefuse refusal rows ran (floor $((nr_rows * 2)) = $nr_rows rows x host + cx)"
# The acceptance floor sums a_legs over the two always-present legs rather than multiplying, so
# a row excluded from a leg is subtracted here automatically and an over-broad exclusion lowers
# the floor visibly instead of silently passing.
na_floor=0
for row in $ACCEPT_ROWS; do
    for leg in host cx; do
        case " $(a_legs "$row") " in *" $leg "*) na_floor=$((na_floor + 1));; esac
    done
done
na_floor=$((na_floor + $(set -- $V_ROWS; echo $#) * 2))   # 6.7.11: every V row on host + cx
na_floor=$((na_floor + $(set -- $E_ROWS; echo $#) * 3))   # 6.7.13: every E row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $C_ROWS; echo $#) * 3))   # 6.7.13 (D29): every C row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $P_ROWS; echo $#) * 3))   # 6.7.13 (D34): every P row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $U_ROWS; echo $#) * 2))   # 6.7.14 (D43): every U row on host + cx
na_floor=$((na_floor + $(set -- $D_ROWS; echo $#) * 3))   # 6.7.14 (D35, D36): every D row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $M_ROWS; echo $#) * 3))   # 6.7.14 (D37-D39): every M row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $CR_ROWS; echo $#) * 3))   # 6.7.15: every CR row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $N_ROWS; echo $#) * 3))   # 6.7.15: every N row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $WR_ROWS; echo $#) * 3))   # 6.7.15 (D28): every WR row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $GC_ROWS; echo $#) * 3))   # 6.7.15: every GC row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $OPC_ROWS; echo $#) * 3))   # 6.7.16 (D24): every OPC row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $RVC_ROWS; echo $#) * 3))   # 6.7.16: every RVC row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $VAC_ROWS; echo $#) * 3))   # 6.7.16 (D101): every VAC row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $VOC_ROWS; echo $#) * 3))   # 6.7.16 (D100): every VOC row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $VS_ROWS; echo $#) * 3))   # 6.7.17 (D23): every VS row on host + host IR=3 + cx
na_floor=$((na_floor + $(set -- $VLC_ROWS; echo $#) * 3))   # 6.7.17 (D24): every VLC row on host + host IR=3 + cx
[ "$naccept" -ge "$na_floor" ] || bad "only $naccept acceptance rows ran (floor $na_floor = a_legs summed over host + cx, + the V rows)"
# And every row id in both tables must actually produce a source — a typo'd id would otherwise
# compile an EMPTY program, which cycc accepts (exit 0, runnable binary) and would score a row.
for row in $REFUSE_ROWS $ACCEPT_ROWS $V_ROWS $Y_ROWS $E_ROWS $Z_ROWS $C_ROWS $Q_ROWS $P_ROWS $K_ROWS $H_ROWS H16 $T_ROWS $U_ROWS $D_ROWS $DK_ROWS $M_ROWS $MK_ROWS $CR_ROWS $CRK_ROWS $NK_ROWS $N_ROWS $WR_ROWS $WRK_ROWS $GA_ROWS $GC_ROWS $TL_ROWS $GT_ROWS $OP_ROWS $OPC_ROWS $RV_ROWS $RVC_ROWS $SX_ROWS $VA_ROWS $VAC_ROWS $VAS_ROWS $VO_ROWS $VOS_ROWS $VOC_ROWS $WS_ROWS $WF_ROWS $FW_ROWS $VN_ROWS $VNS_ROWS $VG_ROWS $VS_ROWS $VSK_ROWS $VCO_ROWS $VCO2_ROWS $VL_ROWS $VLS_ROWS $VLC_ROWS $VER_ROWS; do
    if [ "$(r_src "$row"; a_src "$row"; v_src "$row"; y_src "$row"; e_src "$row"; z_src "$row"; c_src "$row"; q_src "$row"; p_src "$row"; k_src "$row"; h_src "$row"; t_src "$row"; u_src "$row"; d_src "$row"; dk_src "$row"; m_src "$row"; mk_src "$row"; cr_src "$row"; crk_src "$row"; nk_src "$row"; n_src "$row"; wr_src "$row"; wrk_src "$row"; ga_src "$row"; gc_src "$row"; tl_src "$row"; gt_src "$row"; op_src "$row"; opc_src "$row"; rv_src "$row"; rvc_src "$row"; sx_src "$row"; va_src "$row"; vac_src "$row"; vas_src "$row"; vo_src "$row"; vos_src "$row"; voc_src "$row"; ws_src "$row"; wf_src "$row"; fw_src "$row"; vn_src "$row"; vns_src "$row"; vg_src "$row"; vs_src "$row"; vsk_src "$row"; vco_src "$row"; vl_src "$row"; vls_src "$row"; vlc_src "$row"; ver_src "$row")" = "" ]; then bad "row $row has no source in any table"; fi
done
# And the message this gate greps for must still be the one the compiler emits.
n=$(grep -c "$MSG" src/frontend/parse_fn.cyr || true)
[ "$n" -ge 1 ] || bad "src/frontend/parse_fn.cyr no longer spells '$MSG' — reworded?"
n=$(grep -c "$MSGV" src/frontend/parse_decl.cyr || true)
[ "$n" -ge 1 ] || bad "src/frontend/parse_decl.cyr no longer spells '$MSGV' — reworded?"
n=$(grep -c "$HINT" src/frontend/parse_decl.cyr || true)
[ "$n" -ge 1 ] || bad "src/frontend/parse_decl.cyr no longer spells '$HINT' — reworded?"
n=$(grep -c "$VAM" src/frontend/parse_decl.cyr || true)
[ "$n" -ge 1 ] || bad "src/frontend/parse_decl.cyr no longer spells '$VAM' — reworded?"
n=$(grep -c "$VLD - '" src/frontend/parse_decl.cyr || true)   # 6.7.17 (D24)
[ "$n" -ge 1 ] || bad "src/frontend/parse_decl.cyr no longer spells '$VLD - ' — reworded?"

echo "simd_return_shapes: $pass passed, $fail failed ($nrefuse refusals, $naccept acceptances)"
# 6.6.11 (K1): an axis that could not run makes the gate a SKIP (77), never a PASS.
if [ "$fail" -eq 0 ] && [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: simd_return_shapes — $GATE_SKIPS axis/leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
[ "$fail" -eq 0 ]
