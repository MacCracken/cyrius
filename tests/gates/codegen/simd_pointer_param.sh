#!/bin/sh
# tests/gates/codegen/simd_pointer_param.sh — 6.7.11
#
# A POINTER-TO-VECTOR PARAMETER (`p: *f64v2`) IS A POINTER: one integer word whose step is the
# vector's size, address-passed like `p: *S`. A vector local passed to it passes its ADDRESS, as a
# struct passed to a `*T` parameter does (6.6.20), and a vector of ANOTHER type is refused by name, as
# a struct of another type is (6.7.3) — the user's decision, 2026-10-13: (a). Both parameter scans
# consumed the `*` and classified the bare vector name, so the parameter was a VALUE-form vector (XMM /
# V registers; a by-pointer copy-in on Win64) and every caller routed it as one: `rd(&b)` was refused
# "value-form SIMD arg must be a local IDENT (inline-replay path)", and `rd(b)` compiled and the body
# dereferenced lane 0's bits (exit 139 on x86_64 and aarch64; cx "guest address out of range").
# Measured on 6.6.10 - 6.7.10. Filed: docs/development/issues/archived/2026-10-10-pointer-to-vector-parameter-is-value-form.md
#
#   R1 the filed repro (the valid call, refused) verbatim: exits 1 on x86_64, x86_64 CYRIUS_IR=3,
#      aarch64 (qemu), cx (cxvm) and PE (wine)
#   R2 the filed repro `rd(b)` verbatim: compiles and exits 0 on the same legs (139 before)
#   R3 the decision: `rd(b)` reads b (lane 0 = 42), `rd(&b)` too (exit 84), on the same legs
#   Y  a vector local of ANOTHER type into a `*V` parameter: exactly one error line, "cannot pass 'f' to a
#      parameter of a different vector type in a call to 'rd'" — f32v4 into `*f64v2`, f64v2 into `*f64v4`,
#      i32v4 into `*f32v4`, i64v2 into `*i32v4`, a forward call, a method, a generic, a tail position,
#      a parenthesised argument; Yw the first on PE (the Win64 arm takes the same route)
#   S  `p[1]` on a `*f64v2` parameter is refused with a `*f64v2` local's text (the element is a vector)
#   T  tests/tcyr/crossos/simd_pointer_param.tcyr on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived
#      from the file (one row per `assert_eq(` call) — `*f64v2` / `*f64v4` / `*f32v4` / `*i32v4` /
#      `*i64v2`, `p + 1` stepping 16 / 32, writes, mixed signatures (the XMM / V ordinals count only the
#      value-form vectors), a stack-passed one, a method, a generic, a tail position, a forward call,
#      `fncall1` / `callptr` with `&b` (an integer register now); the release gate's cross-OS leg runs
#      it on ecb / ach / cass / pi
#
#
# 6.7.12 (D27, the user, 2026-10-15: B — "pass the address for the *V shapes; another pointer kind refused by
# name"): a vector VALUE that is not a named local into a `*V` parameter passes an address — a call result
# through a frame temp (`_sarg_vec_call`), `*pv` as pv (`_dlo_vec`, the step word's vector) — and a vector
# local into a pointer of another kind is refused by name; `*f32v8` is a `*V` (`_ptr_vclass`; 6.7.13: class 10).
# They passed lane 0's bits as the address (139 / 139 / a cx fault / PE 5; on PE `rp(b)` into `*Pt` alone passed `&b` by
# accident and ran — it is refused now too); x86_64 refused the `*V` shapes through 6.7.10 (an x86_64 regression
# in 6.7.11). Filed: docs/development/issues/2026-10-13-vector-value-into-pointer-
# parameter-passes-lane-bits.md
#   R4 the filed repro 1 verbatim (`rd(mkv(42, 7))` + `rd(*pb)`): exit 42 on x86_64 / IR=3 / aarch64 / cx / PE
#   R5 the filed repro 2 verbatim: `rp(b)` and `ri(b)` refused by name, once each (two lines, no binary), on
#      x86_64 and PE; R5e `r8(e)` (and `r8(&e)`) alone exits 42 on x86_64 / IR=3 / aarch64 / cx / PE
#   Y10-Y12 refused by name, once: `rd(mkv4(..))` (a call result of another vector type), `rd(*pq)` (a `*f32v4`
#      into `*f64v2`), `ri(b)` (a vector local into `*i64`); Y13 a top-level `rd(mkv(..))` (no frame for the
#      temp); Yw2 the Y10-Y12 refusals on PE
#   Y13a / Y13c / Yw2d Y13 on aarch64, cx and PE (6.7.13, D40 — the user 2026-10-15: keep the top-level
#      refusal; 6.7.11 compiled it to a fault, 139 on x86_64 and aarch64)
#   Y14-Y22 (6.7.14, issues/2026-10-15-generic-vector-type-arg-refusal-cascades-d27-refusal.md) an explicit generic call
#      whose own type argument is refused is reported ONCE: Y14 the filed repro verbatim `g<f64v2>(b)` (+ D27 "in a
#      call to 'g$i'" before) on x86_64 / aarch64 / cx / PE; Y15 `g<Zork>(b)` (once before too); Y16-Y22 a token that
#      is no name, a slice, a tuple, a nested `Box<f64v2>`, the second argument, u128 with `*pb`, a vector call result
#      (each + D27 / D31 before); Y14k the control `g<i32>(&x)` / `g<Pt>(&p)` on every leg
#   M-TA1 `_explicit_generic_call` without the `_ta_refd` test (2026-10-16) -> RED 11: Y14 Y14a Y14c Y14p Y16-Y22
#       (two or three error lines); Y15 Y14k green
#   M-TA2 `_gen_call_refd` without its panic latch     -> RED 5: Y16-Y18 Y21 Y22 (+ D27 / D31 on the base 'g'); Y14
#       Y15 Y19 Y20 green (their refusal sets the latch itself)
#   T  also carries the D27 rows (`sp_vrows`); 6.7.13 (issues/2026-10-14-parenthesised-fn-pointer-callee-loses-
#      struct-result.md) the callee in parentheses, `rd(callptr((&mkv), 42, 2))` (139 / 139 / 0 / 5 before: an unknown
#      callee's lane bits as the address), as the known callee it is (`_icall_fti`, `_svc_rs`)
#
# 6.7.13 (issues/archived/2026-10-15-value-form-f32v8-parameter-receives-one-word.md): a VALUE-form `v: f32v8` parameter is its
# 32 bytes, as `v: f64v4` is. `_classify_param_type` had no class for f32v8, so it was one integer word and the caller
# pushed lane 0's (`load32(&v + 8)` read 0 on x86_64 / IR=3 / aarch64 / cx / PE; 38 is right). Class 10 takes f64v4's
# 32-byte routing in both scans (mask code 2; Win64's 32-byte copy-in); the mask has no fourth code, so the argument
# check reads the parameter's own type from the definition (`_pv32_param`), on Win64's address push too
# (`_sarg_pe_v32`).
#   V8  the filed repro verbatim: exit 38 on x86_64 / IR=3 / aarch64 / cx / PE (0 before)
#   VY1 / VY2 an f64v4 local into `v: f32v8`, an f32v8 local into `v: f64v4`: one error line, "value-form SIMD arg type
#      mismatch (callee expects f32v8 / f64v4)"; VYw1 / VYw2 the same on PE (both compiled there: Win64 checked no
#      value-form vector argument); VY3 VY1 through an `#inline` fn (the replay's own check)
#   T2 tests/tcyr/crossos/simd_param_then_scalar.tcyr ($N2 rows, axis 7: the repro, f32v8 + scalars, two f32v8, a
#      method, f32v8 + f64v4) on x86_64 / IR=1 / IR=3 / DCE / aarch64 / cx / PE: "N passed, 0 failed (N total)"
#
# MUTATION LEDGER (2026-10-16, 6.7.13, the vectors lane; each change alone in a scratch copy of the tree, this gate run
# there with CYCC=<its 2-stage mutant>; measured):
#   M-V8a `_classify_param_type` without the f32v8 arm      -> RED 29: V8 on every leg (exit 0), VY1 VY3 VYw1
#       (compiled), T2 on every leg (19 passed, 6 failed); and, `*f32v8` no `*V` again, R5 x86 / PE (a third line),
#       R5e and T on every leg ("not a pointer to its vector type"); VY2 VYw2 green (`v: f64v4` keeps its class)
#   M-V8b `_pv32_param` answering 0                          -> RED 9: VY1 (compiled: the mask's f64v4 reading),
#       VYw1 VYw2 (compiled), T2 x86 / IR=1 / IR=3 / DCE / aarch64 / cx (an f32v8 local refused "callee expects
#       f64v4"); V8 VY3 green (the replay checks by its own record), T2 PE green (Win64 routes no mask)
#   M-V8c `_sarg_pe_v32` answering 0                         -> RED 2: VYw1 VYw2 (compiled)
#   M-V8d `_inl_simd_arg` without the f32v8 arm              -> RED 11: V8 x86 / IR=3 / aarch64 / cx, T2 x86 / IR=1 /
#       IR=3 / DCE / aarch64 / cx ("value-form SIMD arg must be a 16-byte vector": the replay took f32v8 for a
#       16-byte one), VY3 (that text); V8 / T2 PE green (Win64 does not replay a vector-parameter fn)
#
# 6.7.13 (issues/archived/2026-10-15-vector-value-into-other-pointer-or-byvalue-struct-and-unreceived-call-sources.md rows 6-7):
# a vector METHOD result into `*V` passes a temp's address, as a by-name call's does (D27) — `_svc_rs` takes `x.m(..)`
# (`_vmc_fi`, the D29 method recogniser); on Win64 the method's hidden result pointer is that temp, before `self`.
# Row 7 (an explicit instance) is the explicit-instance bite's (`_vcall_fi`).
#   OK6 / OK7 the filed rows 6 and 7 verbatim (head + main): exit 42 on x86_64 / IR=3 / aarch64 / cx / PE (139 / 139 /
#      139 / cx 253 / PE 5 before)
#   T  `sp_mrows`: a method result (both lanes, wrapped, f64v4, a generic method's, as a method's argument, through a
#      `*S` receiver, the receiver intact) and `mkg<i64>` / `mkg<i32>` results into `*V` (FLOOR 61)
#   M-R6 `_svc_rs` without the method arm                    -> RED 12: OK6 on every leg (139 / 139 / 139 / cx 253 /
#       PE 5), T on every leg (a fault; cx "54 passed, 7 failed")
# ⛔ 6.7.13 (D31 A, the user's decision, 2026-10-15; the same issue's rows 1-5) — EVERY VECTOR VALUE INTO A POINTER OF
# ANOTHER KIND, OR INTO A BY-VALUE STRUCT PARAMETER, IS REFUSED BY NAME: a call result (`_svc_kind` for an address-passed
# parameter, `_sarg_vec_other` otherwise) and a `*V` dereference (`_dro_vt_for` arms, `_dro_vcheck` refuses; `_svo_vderef`
# by the local's step word otherwise) into `*Pt` / `*i64` with D27's words, a vector local into a by-value struct (`_sarg_vec_ptr`
# / `_sarg_vec_other`) "a vector is not a struct" — on Win64 too, where row 5 ran by accident (42).
#   OK1-OK5 the filed rows 1-5 verbatim on x86_64 / aarch64 / cx / PE: one line each, naming `mkv` / `*pb` / `b`
#   OKX 13 sources in one compile (a method, an explicit instance, callptr, wrapped, `*pb`, a by-value struct of 8 B or
#      less and over, `**f64v2`, fncall2): 13 lines on x86_64 and PE
#   M-K1 `_svc_kind` answering 0                             -> RED 6: OK1 on every leg (compiled), OKX x86 / PE (10 lines)
#   M-K2 `_sarg_vec_other` back to the local only            -> RED 10: OK2 OK4 on every leg (compiled), OKX x86 / PE (6)
#   M-K3 `_dro_vt_for` arming for a `*V` only                -> RED 6: OK3 on every leg (compiled), OKX x86 / PE (12)
#   M-K4 `_sarg_vec_ptr` without the by-value struct arm     -> RED 4: OK5 on every leg (compiled; PE 42 again)
#
# ⛔ 6.7.13 (D32 A, the user's decision, 2026-10-15; issues/2026-10-15-captured-vector-into-other-pointer-kind-passes-
# capture-address.md) — A CLOSURE'S CAPTURED VECTOR MEETS THE LOCAL'S ARGUMENT RULES. `|k| ri(b)` (`p: *i64`) and `|k|
# rp(b)` (`p: *Pt`) passed the capture's address and ran (42 on x86_64 / IR=3 / aarch64 / cx / PE), where `ri(b)` /
# `rp(b)` on the local are refused by name (D27): the capture reached neither vector arm (`_CL_CAP_FIELD_IDX` takes a
# struct capture only, `_sarg_vec_other` a FINDLOCAL local). `_sarg_vec_cap` (address-passed: `_svp_rule`, the local's
# `_sarg_vec_ptr` rules) and `_sarg_vec_other`'s capture arm (`_cl_cap_vec`) give it A2, D27 and D31.
#   CR1 / CR2 the filed repro verbatim (`|k| ri(b)`) and its `|k| rp(b)` twin: one line each on x86_64 / aarch64 / cx / PE
#   CRX 6 captured-vector arguments in one compile (`*u8`, `**f64v2`, wrapped `*i64` / `*Pt`, a by-value struct over 8 B
#      and of 8 B or less): 6 lines on x86_64 and PE; CRY1 / CRY2 / CRYw another vector type into `*f64v2` (A2), once
#   T  `sp_crows` (FLOOR 68): a captured f64v2 / f64v4 / f32v4 into its `*V` (both lanes of the captured copy), wrapped,
#      a method's parameter, a write through it reaching the copy and not the enclosing local
#   M-C1 `_sarg_vec_cap` answering 0 (2026-10-16, measured)  -> RED 9: CR2 on every leg (compiled), CRX x86 / PE (4
#       lines: `rp((b))` / `bv(b)` gone), CRY1 CRY2 CRYw (compiled)
#   M-C2 `_sarg_vec_other` without the capture arm           -> RED 6: CR1 on every leg (compiled), CRX x86 / PE (2
#       lines: `ru` / `rpp` / `ri((b))` / `bv1` gone)
#
# ⛔ 6.7.13 (D33 A, the user's decision, 2026-10-15; issues/archived/2026-10-15-struct-into-vector-pointer-parameter-accepted.md)
# — A STRUCT VALUE INTO A `*V` PARAMETER IS REFUSED BY NAME (a `*V` records no struct, so `_sarg_type_err` compared
# nothing: `_sarg_svec_err`): the filed `rd(s)` read the struct's bytes as the vector (42 on every leg, silently).
#   SV1 the filed repro verbatim: one line on x86_64 / aarch64 / cx / PE; SV2-SV9 a call result, `*ps`, a global, a
#      captured struct, a method result, parenthesised, 24 B into `*f64v4`, 8 B; SVw SV2-SV5 on PE
#   SVok `rd(&s)` and `rd(ps)` (a typed `*Pt`) exit 42 on x86_64 / IR=3 / aarch64 / cx / PE
#   M-S1 `_sarg_svec_err` answering 0                        -> RED 16: SV1 on every leg, SV2-SV9, SVw2-SVw5 (compiled)
#
# 6.7.13 (issues/archived/2026-10-15-vector-deref-through-address-of-or-double-pointer-into-vector-pointer-param.md) — A
# DEREFERENCE THROUGH AN ADDRESS-OF OR A DOUBLE POINTER IS THE VALUE IT NAMES: the filed `rd(*&b)` / `rd(**ppb)` and the
# struct analogues `take(*&s)` / `take(**pps)` pushed the loaded word as the address (139 / 139 / 139 / cx 253 or 252 /
# PE 5). `_dlo_vec` types `&x` of a vector local / parameter / capture / global as its `*V` for the dereference only
# (`_amp_vd`: `&b + n` still steps bytes), `**ppb` is D9 (a)'s step word, and a pin carries its pointee `*S`'s struct
# so the outer `*` of `**pps` names S (`_ppd_note` / `_dlo_ppsid`).
#   DR1-DR5 the two filed repros verbatim, the struct analogue verbatim and its `**pps` form, `rd(*(&b))`: exit 42 on
#      x86_64 / IR=3 / aarch64 / cx / PE; DRY1 / DRY2 / DRYw `rd(*&f)` / `rd(**ppf)` of an f32v4 (A2), DRS1 / DRSw
#      `take(**ppq)` of another 24-byte struct, DRK `rp(*&b)` into `*Pt` (D31), each refused once
#   T  `sp_drows` (FLOOR 79): `*&b`, `*(&b)`, `(*&b)`, `**ppb`, `*&w` of an f64v4, a parameter's, a capture's and a
#      global's `*&`, a write through `*&b`
#   M-DR1 `_amp_vd` answering 0 (2026-10-16, measured)       -> RED 20: DR1 DR5 on every leg (139 / cx 253 / PE 5), DRY1
#       DRYw DRK (compiled), T on every leg
#   M-DR2 `_dlo_ppsid` answering 0                           -> RED 7: DR4 on every leg (139 / cx 252 / PE 5), DRS1 DRSw
#       (compiled); and struct_arg_type_refused.sh D17 D18, small_struct_handle_line.sh R10 on every leg
#   M-DR3 `_pp_intern` keyed without the pointee's struct    -> RED 2: DRS1 DRSw (compiled: `**Q3` shares P3's pin)
#
# ⛔ 6.7.13 (D30 A, the user's decision, 2026-10-15; issues/2026-10-15-vector-call-result-into-value-form-vector-
# parameter.md) — A VECTOR CALL RESULT INTO A VALUE-FORM VECTOR PARAMETER IS PASSED. `lanes(mkv(4, 2))` was refused on
# x86_64 / IR=3 / aarch64 / cx ("value-form SIMD arg: IDENT not found as a local" + "expected ';', got number 4") and
# exited 5 on PE (lane 0 taken as the vector's address); `f64v2_add(a, mkv(3, 4))` the same. SysV / AAPCS64 / cx receive
# the call into a frame temp the vector second pass loads (`_sar_src` / `_sar_vcall`); the inline replay receives it
# into the parameter's slots (`_inl_simd_arg`); Win64 passes the temp's address (`_sarg_vec_call` for a value-form
# parameter, `_pvf_param`). Any other source that is no local is refused once by name, the argument skipped (no
# cascade), and on PE a word into a value-form parameter is refused as on the other three (`_sarg_pe_vword`, pw.cyr).
#   VC1 / VC2 the filed repro verbatim (42) and `f64v2_add(a, mkv(3, 4))` (46) on x86_64 / IR=3 / aarch64 / cx / PE
#   VZ1-VZ4 on x86_64 / aarch64 / cx / PE, each one line: a call of another vector type (A2's words), a top-level call
#      (D40's words), `lanes(5)` (no 'expected ;'), pw.cyr's word local ("must be a 16-byte vector"; PE compiled it: 5)
#   VZw1 / VZw2 on PE, each one line: `lanes(G)` of a vector global and `lanes(nosuch)` — `_sarg_pe_vword`'s refusal skips
#      the argument as SysV's `_sar_src` does (the value parse added "vector global 'G' is read and written through its
#      address .." / "undefined variable 'nosuch'": two lines, where x86_64 / aarch64 / cx and the base PE print one)
#   T3 tests/tcyr/crossos/vector_param_forward_call.tcyr (FLOOR3 29): by name, an explicit instance, fncall2 / callptr
#      (&f), a method; f64v4 / f32v4 / i32v4 / f32v8; between integers, two calls, a local and a call, after six
#      integers, a method's parameter, the inline replay, nested
#   M-VC1 `_sar_vcall` never taking a call                   -> RED 20: VC1 VC2 x86 / IR=3 / aarch64 / cx (refused), VZ1
#       VZ2 x86 / aarch64 / cx (the generic refusal instead), T3 x86 / IR=1 / IR=3 / DCE / aarch64 / cx; PE green
#   M-VC2 `_sarg_vec_call` without the value-form arm (PE)   -> RED 5: VC1 VC2 pe (exit 5), VZ1 VZ2 pe (compiled), T3 pe
#   M-VC3 `_sarg_pe_vword` answering 0                       -> RED 2: VZ3 VZ4 pe (compiled); and simd_return_shapes Q3
#       win64
#   M-VC4 `_inl_simd_arg` without the call arm               -> RED 17: VC1 VC2 x86 / IR=3 / aarch64 / cx (`lanes` and
#       `f64v2_add` are replayed), VZ1 x86 / aarch64 / cx (the generic refusal), T3 x86 / IR=1 / IR=3 / DCE / aarch64 / cx
#   M-VC5 `_arg_push_snap` parsing the refused argument      -> RED 2: VZw1 VZw2 (two error lines each); VZ3pe green
#       (the review fix reverted: `_sarg_pe_vword`'s refusal     (a literal's value parse reports nothing)
#       not skipped)
#
# MUTATION LEDGER (2026-10-15, 6.7.12; each change alone in the tree, this gate run with CYCC=<its 2-stage
# mutant>; measured):
#   M4  `_sarg_vec_call` answers 0 (no call-result arm)    -> RED 15: R4 (139 / 139 / 139 / cx 253 / PE 5),
#                                                             Y10 Y13 Yw2a (compiled), T on every leg
#   M5  `_dlo_vec` answers 0 (no vector park)              -> RED 14: R4 (as M4), Y11 Yw2b, T on every leg
#   M6  `_vec_kind_err` reports nothing                    -> RED 4: R5 x86 / PE (compiled), Y12 Yw2c
#   M7  `_ptr_vclass` without f32v8 (6.7.13: M-V8a)        -> RED 14: R5 (a third line: `r8(e)` refused as a
#                                                             pointer of another kind), R5e on every leg, T
#   (6.7.13, D40) `_sarg_vec_call` without its top-level   -> RED 4: Y13 Y13a Y13c Yw2d (compiled)
#       arm (`_svc_toplevel_err`)
#
# MUTATION LEDGER (2026-10-13; a scratch copy of the tree with the one change, this gate run from that
# copy with CYCC=<its 2-stage mutant>; measured):
#   M0  the fix reverted (the slot-open scans and call)   -> RED 33: R1 (refused "value-form SIMD arg must
#                                                             be a local IDENT"; PE exit 5), R2 (139 / 139 /
#                                                             139 / cx 1 / PE 5), R3, Y1 Y4-Y8 Yw (compiled),
#                                                             Y2 Y3 Y9 (the old text, or a cascade), S1 ("it
#                                                             is not a typed array, a *T .."), T on every leg
#   M1  `_param_class` without class 9 (a `*V` classed as -> RED 32: as M0 but Yw (the value-form path wins;
#       its vector again, both scans)                        the Win64 arm still meets `_sarg_vec_ptr`)
#   M2  `_param_wants_struct_ptr` without the `*V` arm    -> RED 27: R2 R3 Y1-Y9 Yw and T on
#       (no address bit: `rd(b)` pushes lane 0)              every leg; R1 green (`&b` is a pointer)
#   M3  `_sarg_vec_ptr` without the type check            -> RED 10: Y1-Y9 Yw (they compile)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=simd_pointer_param
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper.
WP="$D/wine"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null

fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

TC=tests/tcyr/crossos/simd_pointer_param.tcyr
TC2=tests/tcyr/crossos/simd_param_then_scalar.tcyr   # 6.7.13: rows T2
TC3=tests/tcyr/crossos/vector_param_forward_call.tcyr   # 6.7.13 (D30): rows T3
R1=docs/development/issues/repros/2026-10-10-pointer-to-vector-parameter-is-value-form.cyr
R2=docs/development/issues/repros/2026-10-10-pointer-to-vector-parameter-is-value-form-value.cyr
R4=docs/development/issues/repros/2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits.cyr
R5=docs/development/issues/repros/2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits-other-kinds.cyr
for f in "$TC" "$TC2" "$TC3" "$R1" "$R2" "$R4" "$R5"; do [ -f "$f" ] || { echo "FAIL: $G: $f is missing"; exit 1; }; done
# One row per `assert_eq(` call (the file defines none). The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=81   # 6.7.13: + the parenthesised-callee rows (the receives lane), the method / explicit-instance rows
           # (`sp_mrows`), the captured-vector rows (`sp_crows`, D32), the deref-through rows (`sp_drows`)
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
N2=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC2")
FLOOR2=25
if [ "$N2" -lt "$FLOOR2" ]; then echo "FAIL: $G: only $N2 rows in $TC2 (floor $FLOOR2) — rows were lost"; exit 1; fi
N3=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC3")
FLOOR3=29
if [ "$N3" -lt "$FLOOR3" ]; then echo "FAIL: $G: only $N3 rows in $TC3 (floor $FLOOR3) — rows were lost"; exit 1; fi

# The legs this box can run: aarch64 under qemu, cx under the tree's own cxvm, PE under wine.
A64=""; CXCC=""; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
        chmod +x "$D/cc_a64"; A64="$D/cc_a64"
    else bad "aarch64: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 legs (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: PE legs (wine not installed)"; skips=$((skips + 1)); fi

# build_leg <leg> <src> <out>: compile only; 0 = built.
build_leg() {
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3" 2> "$3.err" ;;
    esac
}
# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build)
# and LAST (the last line of its output, CR stripped).
run_leg() {
    RC=-1; LAST=''
    if [ "$1" = pe ]; then build_leg pe "$2" "$3.exe" || return 0
    else build_leg "$1" "$2" "$3" || return 0; fi
    RC=0
    case "$1" in
        x86|x86:*) chmod +x "$3"; timeout 60 "$3" > "$3.out" 2>&1 || RC=$? ;;
        a64)  chmod +x "$3"; timeout 300 qemu-aarch64 "$3" > "$3.out" 2>&1 || RC=$? ;;
        cx)   timeout 300 "$D/cxvm" < "$3" > "$3.out" 2>&1 || RC=$? ;;
        pe)   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$3.exe" > "$3.out" 2> /dev/null) || RC=$? ;;
    esac
    LAST=$(tail -1 "$3.out" | tr -d '\r')
}
OTHER=""
[ -n "$A64" ] && OTHER="$OTHER a64"
[ -n "$CXCC" ] && OTHER="$OTHER cx"
[ "$WINE" = 1 ] && OTHER="$OTHER pe"
# exit_rows <tag> <src> <want> <what>: on every leg
exit_rows() {
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/r_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: did not build: $(grep -h -m1 'error' "$D/r_$n.err" "$D/r_$n.exe.err" 2>/dev/null | head -1)"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: exit $3"
        else bad "$1 $leg: exit $RC, want $3 ($4)"; fi
    done
}

echo "R1. the filed repro, verbatim: \`rd(&b)\` into \`p: *f64v2\` compiles and reads b (exit 1)"
exit_rows R1 "$R1" 1 "1 = rd(&b) read lane 0"
echo "R2. the filed repro, verbatim: \`rd(b)\` compiles and runs (exit 0; 139 before)"
exit_rows R2 "$R2" 0 "rd(b) passes b's address"
echo "R3. the decision: \`rd(b)\` and \`rd(&b)\` both read b's lane 0 (exit 84)"
cat > "$D/r3.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    return rd(b) + rd(&b);
}
var rc = main();
syscall(60, rc);
EOF
exit_rows R3 "$D/r3.cyr" 84 "42 + 42"

# refused <name> <what> <body> [pe|x86|a64|cx [frag]]: compile fails with exactly one error line holding the
# refusal (`FRAG`, the vector-type one, unless a fragment is given), and no binary
FRAG="to a parameter of a different vector type in a call to"
refused() {
    printf '%b' "$3" > "$D/$1.cyr"
    rc=0
    fr=${5:-$FRAG}
    case "${4:-}" in
        pe)  CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$? ;;
        a64) timeout 60 "$A64" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$? ;;
        cx)  timeout 60 "$CXCC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$? ;;
        *)   timeout 60 "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$? ;;
    esac
    n=$(grep -c '^error' "$D/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$2: compiled (rc 0) — want \".. $fr ..\""
    elif [ "$n" -ne 1 ]; then bad "$2: $n error lines, want exactly 1: $(grep '^error' "$D/$1.err" | head -3 | tr '\n' '|')"
    elif ! grep '^error' "$D/$1.err" | grep -qF -- "$fr"; then bad "$2: wrong refusal: $(grep '^error' "$D/$1.err" | head -1)"
    elif [ -s "$D/$1.bin" ]; then bad "$2: refused, but a binary was written"
    else ok "$2"; fi
}
H='include "lib/syscalls.cyr"\ninclude "lib/simd.cyr"\n'
E='var rc = main();\nsyscall(60, rc);\n'
echo "Y. a vector of another type into a \`*V\` parameter: refused by name, once"
refused Y1 "Y1 f32v4 into *f64v2" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(f) + 1; }\n${E}"
refused Y2 "Y2 f64v2 into *f64v4" "${H}fn rd(p: *f64v4): i64 { return load64(p); }\nfn main(): i64 { var f: f64v2 = f64v2_make(1, 2); return rd(f) + 1; }\n${E}"
refused Y3 "Y3 i32v4 into *f32v4" "${H}fn rd(p: *f32v4): i64 { return load32(p); }\nfn main(): i64 { var f: i32v4 = i32v4_make(1, 2, 3, 4); return rd(f) + 1; }\n${E}"
refused Y4 "Y4 i64v2 into *i32v4 (the same size)" "${H}fn rd(p: *i32v4): i64 { return load32(p); }\nfn main(): i64 { var f: i64v2; return rd(f) + 1; }\n${E}"
refused Y5 "Y5 a forward call" "${H}fn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(f) + 1; }\nfn rd(p: *f64v2): i64 { return load64(p); }\n${E}"
refused Y6 "Y6 a method" "${H}struct S { k; }\nimpl S {\n    fn m(self, p: *f64v2): i64 { return load64(p); }\n}\nfn main(): i64 { var s: S; var f: f32v4 = f32v4_make(1, 2, 3, 4); return s.m(f); }\n${E}"
refused Y7 "Y7 a generic" "${H}fn rd<T>(p: *f64v2, x: T): i64 { return load64(p) + x; }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(f, 1) + 1; }\n${E}"
refused Y8 "Y8 a tail position" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(f); }\n${E}"
refused Y9 "Y9 a parenthesised argument" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd((f)) + 1; }\n${E}"
if [ "$WINE" = 1 ]; then
    refused Yw "Yw f32v4 into *f64v2 on PE" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(f); }\n${E}" pe
fi

echo "R4. the filed repro 1, verbatim: \`rd(mkv(42, 7))\` + \`rd(*pb)\` into \`p: *f64v2\` (exit 42; 139 / cx fault / PE 5 before)"
exit_rows R4 "$R4" 42 "a temp's address and pb"
echo "R5. the filed repro 2, verbatim: \`rp(b)\` (\`*Pt\`) and \`ri(b)\` (\`*i64\`) refused by name; \`r8(e)\` (\`*f32v8\`) alone exits 42"
KFRAG="to a parameter that is not a pointer to its vector type in a call to"
for leg in x86 pe; do
    [ "$leg" = pe ] && [ "$WINE" != 1 ] && continue
    rc=0
    if [ "$leg" = pe ]; then CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$R5" > "$D/r5.bin" 2> "$D/r5.err" || rc=$?
    else timeout 60 "$CC" < "$R5" > "$D/r5.bin" 2> "$D/r5.err" || rc=$?; fi
    np=$(grep '^error' "$D/r5.err" | grep -cF "cannot pass 'b' $KFRAG 'rp'" || true)
    ni=$(grep '^error' "$D/r5.err" | grep -cF "cannot pass 'b' $KFRAG 'ri'" || true)
    n=$(grep -c '^error' "$D/r5.err" || true)
    if [ "$rc" -eq 0 ]; then bad "R5 $leg: compiled - want rp(b) and ri(b) refused"
    elif [ "$n" -ne 2 ] || [ "$np" -ne 1 ] || [ "$ni" -ne 1 ]; then bad "R5 $leg: $n error lines (rp $np, ri $ni), want one each: $(grep '^error' "$D/r5.err" | head -3 | tr '\n' '|')"
    elif [ -s "$D/r5.bin" ]; then bad "R5 $leg: refused, but a binary was written"
    else ok "R5 $leg: rp(b) and ri(b) refused by name, once each"; fi
done
printf '%s\n' 'include "lib/syscalls.cyr"' 'include "lib/simd.cyr"' \
  'fn r8(p: *f32v8): i64 { return load32(p); }' \
  'fn main(): i64 {' \
  '    var e: f32v8 = f32v8_make(42, 2, 3, 4, 5, 6, 7, 8);' \
  '    return r8(e) + r8(&e) - 42;' \
  '}' 'var rc = main();' 'syscall(60, rc);' > "$D/r5e.cyr"
exit_rows R5e "$D/r5e.cyr" 42 "r8(e) passes &e"
echo "Y10-Y13. refused by name, once"
refused Y10 "Y10 a call result of another vector type (f64v4 into *f64v2)" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn mkv4(a): f64v4 { var v: f64v4; return v; }\nfn main(): i64 { return rd(mkv4(1)) + 1; }\n${E}"
refused Y11 "Y11 a dereference of another vector type (*f32v4 into *f64v2)" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); var pq: *f32v4 = &f; return rd(*pq) + 1; }\n${E}"
refused Y12 "Y12 a vector local into *i64" "${H}fn ri(p: *i64): i64 { return *p; }\nfn main(): i64 { var b: f64v2 = f64v2_make(42, 7); return ri(b) + 1; }\n${E}" x86 "$KFRAG"
Y13B="${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn mkv(a, b): f64v2 { return f64v2_make(a, b); }\nvar r1 = rd(mkv(42, 7));\nsyscall(60, r1);\n"
Y13F="returns a vector by value, and a vector result needs storage in a fn's frame"
refused Y13 "Y13 a top-level rd(mkv(..)) (no frame for the temp)" "$Y13B" x86 "$Y13F"
# D40 (the user, 2026-10-15: keep the top-level refusal): the same refusal on aarch64 and cx (6.7.11's
# aarch64 compiled it to a fault, 139 under qemu; its x86_64 too). CHANGELOG [6.7.13]
[ -n "$A64" ] && refused Y13a "Y13 on aarch64" "$Y13B" a64 "$Y13F"
[ -n "$CXCC" ] && refused Y13c "Y13 on cx" "$Y13B" cx "$Y13F"
if [ "$WINE" = 1 ]; then
    refused Yw2a "Yw2 Y10 on PE" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn mkv4(a): f64v4 { var v: f64v4; return v; }\nfn main(): i64 { return rd(mkv4(1)) + 1; }\n${E}" pe
    refused Yw2b "Yw2 Y11 on PE" "${H}fn rd(p: *f64v2): i64 { return load64(p); }\nfn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); var pq: *f32v4 = &f; return rd(*pq) + 1; }\n${E}" pe
    refused Yw2c "Yw2 Y12 on PE" "${H}fn ri(p: *i64): i64 { return *p; }\nfn main(): i64 { var b: f64v2 = f64v2_make(42, 7); return ri(b) + 1; }\n${E}" pe "$KFRAG"
    refused Yw2d "Yw2 Y13 on PE (D40)" "$Y13B" pe "$Y13F"
fi
# 6.7.14 (issues/2026-10-15-generic-vector-type-arg-refusal-cascades-d27-refusal.md): an explicit call whose own type
# argument is refused mints no instance and is reported once. The refused `f64v2` read as i64 minted `g$i`, whose parse
# cleared the panic latch, so D27 judged `b` against its `p: *i64` too (a second line naming `g$i`); a refusal that sets
# no latch (a tuple, a slice, a token that is no name, u128) met D27 / D31 on the base `g`. `_ta_refd` (set by every
# type-argument refusal, cleared when the list opens) sends the call to `_gen_call_refd`: the base, its arguments
# consumed and not judged.
echo "Y14-Y22. an explicit generic call with a refused type argument: refused once (D27 not after it)"
GTH="${H}struct Pt { x; y; }\nstruct Box<T> { v: T; }\nfn g<T>(p: *T): i64 { return load64(p); }\nfn g2<T, U>(p: *T, q: *U): i64 { return load64(p); }\nfn mkv(): f64v2 { return f64v2_make(1, 2); }\n"
GTF="generic type-args must be a scalar (i8/i16/i32/i64) or a struct"
Y14B="${H}fn g<T>(p: *T): i64 { return load64(p); }\nfn main(): i64 {\n    var b: f64v2 = f64v2_make(42, 7); return g<f64v2>(b);\n}\n${E}"
refused Y14 "Y14 the filed repro verbatim, g<f64v2>(b) (+ D27 naming g\$i before)" "$Y14B" x86 "$GTF"
[ -n "$A64" ] && refused Y14a "Y14 on aarch64" "$Y14B" a64 "$GTF"
[ -n "$CXCC" ] && refused Y14c "Y14 on cx" "$Y14B" cx "$GTF"
refused Y14p "Y14 on PE" "$Y14B" pe "$GTF"
gty() { refused "$1" "$2" "${GTH}fn main(): i64 {\n    var x = 3; var b: f64v2 = f64v2_make(42, 7); var pb: *f64v2 = &b; return $3;\n}\n${E}" x86 "$4"; }
gty Y15 "Y15 g<Zork>(b)" 'g<Zork>(b)' "unknown type 'Zork' as a type argument"
gty Y16 "Y16 g<1>(b), a type argument that is no name (+ D27 naming g before)" 'g<1>(b)' "a type argument is a type name, got number 1"
gty Y17 "Y17 g<[u8]>(b), a slice (+ D27 before)" 'g<[u8]>(b)' "a slice cannot be a type argument"
gty Y18 "Y18 g<(i64, i64)>(b), a tuple (+ D27 before)" 'g<(i64, i64)>(b)' "a tuple type cannot be a type argument"
gty Y19 "Y19 g<Box<f64v2>>(b), nested (+ D27 naming g\$Box\$i before)" 'g<Box<f64v2>>(b)' "$GTF"
gty Y20 "Y20 g2<i32, f64v2>(b, b), the second argument (+ D27 twice before)" 'g2<i32, f64v2>(b, b)' "$GTF"
gty Y21 "Y21 g<u128>(*pb), a dereference (+ D31 before)" 'g<u128>(*pb)' "u128 cannot be a type argument"
gty Y22 "Y22 g<1>(mkv()), a vector call result (+ D31 before)" 'g<1>(mkv())' "a type argument is a type name, got number 1"
printf '%b' "${GTH}fn main(): i64 {\n    var x = 3; var p = Pt { 1, 2 }; return g<i32>(&x) + g<Pt>(&p) * 10 - 13;\n}\n${E}" > "$D/y14k.cyr"
exit_rows Y14k "$D/y14k.cyr" 0 "control: g<i32>(&x) + g<Pt>(&p) * 10 - 13"

# 6.7.13 — rows 6-7 of issues/archived/2026-10-15-vector-value-into-other-pointer-or-byvalue-struct-and-unreceived-call-sources.md,
# the filed head and mains verbatim: a vector METHOD result and an explicit-instance result into `*f64v2` (D27's own rule
# once the sources are typed; 139 / 139 / 139 / cx 253 / PE 5 before — row 7 is the explicit-instance bite's).
OKH='include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct Pt { x; y; }
struct S2 { k; }
impl S2 { fn mv(self, a, b): f64v2 { return f64v2_make(a, b); } }
fn rp(p: *Pt): i64 { return p.x; }
fn ri(p: *i64): i64 { return *p; }
fn bv(p: Pt): i64 { return p.x; }
fn rd(p: *f64v2): i64 { return load64(p); }
fn mkv(a, b): f64v2 { return f64v2_make(a, b); }
fn mkg<T>(a: T, b: T): f64v2 { return f64v2_make(a, b); }'
echo "OK6-OK7. the filed rows 6-7, verbatim: \`rd(s.mv(42, 7))\` and \`rd(mkg<i64>(42, 7))\` into \`p: *f64v2\` (exit 42)"
printf '%s\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$OKH" 'var s: S2; return rd(s.mv(42, 7));' > "$D/ok6.cyr"
printf '%s\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$OKH" 'return rd(mkg<i64>(42, 7));' > "$D/ok7.cyr"
exit_rows OK6 "$D/ok6.cyr" 42 "a method result's temp"
exit_rows OK7 "$D/ok7.cyr" 42 "an explicit instance's temp"
# 6.7.13 (D31 A, the user's decision, 2026-10-15) — rows 1-5 of the same issue, the filed head and mains verbatim: a vector
# call result and a `*V` dereference into a pointer of another kind, and a vector local into a by-value struct
# parameter, each refused by name, once (139 / 139 / 139 / cx 253 / PE 5 before; row 5 PE 42 by accident).
echo "OK1-OK5. the filed rows 1-5, verbatim: refused by name, once, on x86_64 / aarch64 / cx / PE (D31 A)"
printf '%s\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$OKH" 'return rp(mkv(42, 7));' > "$D/ok1.src"
printf '%s\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$OKH" 'return ri(mkv(42, 7));' > "$D/ok2.src"
printf '%s\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$OKH" 'var b: f64v2 = f64v2_make(42, 7); var pb: *f64v2 = &b; return rp(*pb);' > "$D/ok3.src"
printf '%s\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$OKH" 'var b: f64v2 = f64v2_make(42, 7); var pb: *f64v2 = &b; return ri(*pb);' > "$D/ok4.src"
printf '%s\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$OKH" 'var b: f64v2 = f64v2_make(42, 7); return bv(b);' > "$D/ok5.src"
for lg in x86 a64 cx pe; do
    case "$lg" in a64) [ -n "$A64" ] || continue;; cx) [ -n "$CXCC" ] || continue;; pe) [ "$WINE" = 1 ] || continue;; esac
    refused "OK1$lg" "OK1 $lg: rp(mkv(42, 7)) into *Pt" "$(cat "$D/ok1.src")" "$lg" "cannot pass 'mkv' $KFRAG 'rp'"
    refused "OK2$lg" "OK2 $lg: ri(mkv(42, 7)) into *i64" "$(cat "$D/ok2.src")" "$lg" "cannot pass 'mkv' $KFRAG 'ri'"
    refused "OK3$lg" "OK3 $lg: rp(*pb) into *Pt" "$(cat "$D/ok3.src")" "$lg" "cannot pass '*pb' $KFRAG 'rp'"
    refused "OK4$lg" "OK4 $lg: ri(*pb) into *i64" "$(cat "$D/ok4.src")" "$lg" "cannot pass '*pb' $KFRAG 'ri'"
    refused "OK5$lg" "OK5 $lg: bv(b), a vector local into a by-value Pt" "$(cat "$D/ok5.src")" "$lg" "cannot pass 'b' to a by-value struct parameter in a call to 'bv' - a vector is not a struct"
done
# Every vector source into every such parameter, in ONE compile: each refused on its own line (no `_panic` latch) — a
# method / an explicit instance / callptr / a wrapped call / a wrapped `*pb` into `*Pt` / `*i64`, a call / a local /
# `*pb` into a by-value struct of 8 B or less and over, a local / a call into `**f64v2`, fncall2 into `*Pt`.
printf '%s\nfn rpp(p: **f64v2): i64 { return 0; }\nstruct P1 { x; }\nfn bv1(p: P1): i64 { return p.x; }\nfn main(): i64 { var s: S2; var b: f64v2 = mkv(42, 7); var pb: *f64v2 = &b;\n  return rp(s.mv(1, 2)) + ri(mkg<i64>(1, 2)) + ri(callptr(&mkv, 1, 2)) + ri((mkv(1, 2))) + ri((*pb)) + bv1(mkv(1, 2)) + bv1(b) + bv1(*pb) + bv(mkv(1, 2)) + bv(*pb) + rpp(b) + rpp(mkv(1, 2)) + rp(fncall2(&mkv, 1, 2));\n}\nsyscall(60, main());\n' "$(printf '%s\ninclude "lib/fnptr.cyr"' "$OKH")" > "$D/okx.cyr"
for lg in x86 pe; do
    [ "$lg" = pe ] && [ "$WINE" != 1 ] && continue
    rc=0
    if [ "$lg" = pe ]; then CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$D/okx.cyr" > "$D/okx.bin" 2> "$D/okx.err" || rc=$?
    else timeout 60 "$CC" < "$D/okx.cyr" > "$D/okx.bin" 2> "$D/okx.err" || rc=$?; fi
    n=$(grep -c '^error' "$D/okx.err" || true)
    nk=$(grep '^error' "$D/okx.err" | grep -c "$KFRAG\|to a by-value struct parameter in a call to" || true)
    if [ "$rc" -eq 0 ]; then bad "OKX $lg: compiled - want 13 refusals"
    elif [ "$n" -ne 13 ] || [ "$nk" -ne 13 ]; then bad "OKX $lg: $n error lines ($nk by name), want 13: $(grep '^error' "$D/okx.err" | head -3 | tr '\n' '|')"
    elif [ -s "$D/okx.bin" ]; then bad "OKX $lg: refused, but a binary was written"
    else ok "OKX $lg: 13 vector sources into another pointer kind / a by-value struct, each refused once"; fi
done

# 6.7.13 (D32 A, the user's decision, 2026-10-15; issues/2026-10-15-captured-vector-into-other-pointer-kind-passes-
# capture-address.md) — a closure's CAPTURED vector meets the local's argument rules: the filed repro (`|k| ri(b)`, `p:
# *i64`) and its `|k| rp(b)` twin (`p: *Pt`) passed the capture's address and ran (42 on x86_64 / IR=3 / aarch64 / cx /
# PE), where `ri(b)` / `rp(b)` on the local are refused by name (D27, R5 / Y12).
echo "CR. a captured vector into a pointer of another kind: refused by name, once (D32 A)"
cat > "$D/cr1.src" <<'EOF'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
include "lib/fnptr.cyr"
struct Pt { x; y; }
fn rp(p: *Pt): i64 { return p.x; }
fn ri(p: *i64): i64 { return *p; }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    var c = |k| ri(b) + k;       # outside a closure, ri(b) is refused by name (D27)
    return fncall1(c, 0);
}
var rc = main();
syscall(60, rc);
EOF
sed 's/|k| ri(b) + k;       # outside a closure, ri(b) is refused by name (D27)/|k| rp(b) + k;/' "$D/cr1.src" > "$D/cr2.src"
grep -q '|k| rp(b) + k;' "$D/cr2.src" || bad "CR2: the rp twin was not derived from the filed repro"
for lg in x86 a64 cx pe; do
    case "$lg" in a64) [ -n "$A64" ] || continue;; cx) [ -n "$CXCC" ] || continue;; pe) [ "$WINE" = 1 ] || continue;; esac
    refused "CR1$lg" "CR1 $lg: the filed repro, |k| ri(b) into *i64" "$(cat "$D/cr1.src")" "$lg" "cannot pass 'b' $KFRAG 'ri' - pass &b for its address"
    refused "CR2$lg" "CR2 $lg: |k| rp(b) into *Pt" "$(cat "$D/cr2.src")" "$lg" "cannot pass 'b' $KFRAG 'rp' - pass &b for its address"
done
# Every rule a vector local meets, on its captured copy: another vector type into `*V` (A2's refusal, which stops the
# parse as the local's does: one row each, CRY); in ONE compile, another pointer kind (`*u8`, `**f64v2`, wrapped into
# `*i64` / `*Pt`) and a by-value struct over 8 B and of 8 B or less (D31) — 6 lines, on x86_64 and PE; a captured `*V`
# of its type compiles (no line).
printf '%s\n' 'include "lib/syscalls.cyr"' 'include "lib/simd.cyr"' 'include "lib/fnptr.cyr"' 'struct Pt { x; y; }' 'struct P1 { x; }' \
  'fn rd(p: *f64v2): i64 { return load64(p); }' 'fn rp(p: *Pt): i64 { return p.x; }' 'fn ri(p: *i64): i64 { return *p; }' \
  'fn ru(p: *u8): i64 { return load8(p); }' 'fn rpp(p: **f64v2): i64 { return 0; }' 'fn bv(p: Pt): i64 { return p.x; }' \
  'fn bv1(p: P1): i64 { return p.x; }' \
  'fn main(): i64 {' '    var b: f64v2 = f64v2_make(42, 7);' \
  '    var c = |k| ru(b) + rpp(b) + ri((b)) + rp((b)) + bv(b) + bv1(b) + rd(b) + k;' \
  '    return fncall1(c, 0);' '}' 'syscall(60, main());' > "$D/crx.cyr"
for lg in x86 pe; do
    [ "$lg" = pe ] && [ "$WINE" != 1 ] && continue
    rc=0
    if [ "$lg" = pe ]; then CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$D/crx.cyr" > "$D/crx.bin" 2> "$D/crx.err" || rc=$?
    else timeout 60 "$CC" < "$D/crx.cyr" > "$D/crx.bin" 2> "$D/crx.err" || rc=$?; fi
    n=$(grep -c '^error' "$D/crx.err" || true)
    nk=$(grep '^error' "$D/crx.err" | grep -c "$KFRAG\|to a by-value struct parameter in a call to" || true)
    if [ "$rc" -eq 0 ]; then bad "CRX $lg: compiled - want 6 refusals"
    elif [ "$n" -ne 6 ] || [ "$nk" -ne 6 ]; then bad "CRX $lg: $n error lines ($nk by name), want 6: $(grep '^error' "$D/crx.err" | head -3 | tr '\n' '|')"
    elif [ -s "$D/crx.bin" ]; then bad "CRX $lg: refused, but a binary was written"
    else ok "CRX $lg: 6 captured-vector arguments the local's rules refuse, each once"; fi
done
CRH="${H}include \"lib/fnptr.cyr\"\nfn rd(p: *f64v2): i64 { return load64(p); }\n"
CRY1B="${CRH}fn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); var c = |k| rd(f) + k; return fncall1(c, 0); }\n${E}"
refused CRY1 "CRY1 a captured f32v4 into *f64v2 (A2)" "$CRY1B"
refused CRY2 "CRY2 a captured f64v4 into *f64v2 (A2)" "${CRH}fn main(): i64 { var w: f64v4 = f64v4_make(1, 2, 3, 4); var c = |k| rd(w) + k; return fncall1(c, 0); }\n${E}"
[ "$WINE" = 1 ] && refused CRYw "CRYw CRY1 on PE" "$CRY1B" pe

# 6.7.13 (D33 A, the user's decision, 2026-10-15; issues/archived/2026-10-15-struct-into-vector-pointer-parameter-accepted.md) —
# A STRUCT VALUE INTO A `*V` PARAMETER IS REFUSED BY NAME, the mirror of 6.7.3 / A2 / D27: the filed `rd(s)` (`s: Pt`,
# `p: *f64v2`) passed the struct's address and the callee read its bytes as the vector (42 on x86_64 / IR=3 / aarch64 /
# cx / PE). `rd(&s)` and a typed `*Pt` pointer convert freely, as ever.
echo "SV. a struct value into a \`*V\` parameter: refused by name, once (D33 A); \`rd(&s)\` passes"
cat > "$D/sv1.src" <<'EOF2'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct Pt { x; y; }
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 { var s: Pt; s.x = 42; s.y = 7; return rd(s); }
var rc = main();
syscall(60, rc);
EOF2
SVF="to a parameter that is a pointer to a vector type in a call to 'rd'"
for lg in x86 a64 cx pe; do
    case "$lg" in a64) [ -n "$A64" ] || continue;; cx) [ -n "$CXCC" ] || continue;; pe) [ "$WINE" = 1 ] || continue;; esac
    refused "SV1$lg" "SV1 $lg: the filed repro, rd(s) with s: Pt" "$(cat "$D/sv1.src")" "$lg" "cannot pass 's' $SVF"
done
SVH="${H}include \"lib/fnptr.cyr\"\nstruct Pt { x; y; }\nstruct Q { a; b; c; }\nstruct P1 { x; }\nvar G = Pt { 42, 7 };\nfn rd(p: *f64v2): i64 { return load64(p); }\nfn rd4(p: *f64v4): i64 { return load64(p); }\nfn mkp(): Pt { var s: Pt; s.x = 42; s.y = 7; return s; }\nimpl Pt { fn dup(self): Pt { return self; } }\n"
refused SV2 "SV2 rd(mkp()), a struct call result" "${SVH}fn main(): i64 { return rd(mkp()); }\n${E}" x86 "cannot pass 'mkp' $SVF"
refused SV3 "SV3 rd(*ps), a *Pt dereference" "${SVH}fn main(): i64 { var s: Pt; s.x = 42; var ps: *Pt = &s; return rd(*ps); }\n${E}" x86 "cannot pass 'ps' $SVF"
refused SV4 "SV4 rd(G), a struct global" "${SVH}fn main(): i64 { return rd(G); }\n${E}" x86 "cannot pass 'G' $SVF"
refused SV5 "SV5 |k| rd(s), a captured struct" "${SVH}fn main(): i64 { var s: Pt; s.x = 42; var c = |k| rd(s) + k; return fncall1(c, 0); }\n${E}" x86 "cannot pass 's' $SVF"
refused SV6 "SV6 rd(s.dup()), a method result" "${SVH}fn main(): i64 { var s: Pt; s.x = 42; return rd(s.dup()); }\n${E}" x86 "$SVF"
refused SV7 "SV7 rd((s)), parenthesised" "${SVH}fn main(): i64 { var s: Pt; s.x = 42; return rd((s)); }\n${E}" x86 "cannot pass 's' $SVF"
refused SV8 "SV8 a 24-byte struct into *f64v4" "${SVH}fn main(): i64 { var q: Q; q.a = 42; return rd4(q); }\n${E}" x86 "cannot pass 'q' to a parameter that is a pointer to a vector type in a call to 'rd4'"
refused SV9 "SV9 an 8-byte struct into *f64v2" "${SVH}fn main(): i64 { var t: P1; t.x = 42; return rd(t); }\n${E}" x86 "cannot pass 't' $SVF"
if [ "$WINE" = 1 ]; then
    refused SVw2 "SVw SV2 on PE" "${SVH}fn main(): i64 { return rd(mkp()); }\n${E}" pe "cannot pass 'mkp' $SVF"
    refused SVw3 "SVw SV3 on PE" "${SVH}fn main(): i64 { var s: Pt; s.x = 42; var ps: *Pt = &s; return rd(*ps); }\n${E}" pe "cannot pass 'ps' $SVF"
    refused SVw4 "SVw SV4 on PE" "${SVH}fn main(): i64 { return rd(G); }\n${E}" pe "cannot pass 'G' $SVF"
    refused SVw5 "SVw SV5 on PE" "${SVH}fn main(): i64 { var s: Pt; s.x = 42; var c = |k| rd(s) + k; return fncall1(c, 0); }\n${E}" pe "cannot pass 's' $SVF"
fi
printf '%s\n' 'include "lib/syscalls.cyr"' 'include "lib/simd.cyr"' 'struct Pt { x; y; }' \
  'fn rd(p: *f64v2): i64 { return load64(p); }' \
  'fn main(): i64 { var s: Pt; s.x = 42; s.y = 7; var ps: *Pt = &s; return rd(&s) + rd(ps) - 42; }' \
  'var rc = main();' 'syscall(60, rc);' > "$D/svok.cyr"
exit_rows SVok "$D/svok.cyr" 42 "rd(&s) and rd(ps) convert freely"

# 6.7.13 (issues/archived/2026-10-15-vector-deref-through-address-of-or-double-pointer-into-vector-pointer-param.md) — a
# dereference of an ADDRESS-OF a vector, or of a `**V` / `**S`, is the vector / the struct: the filed `rd(*&b)` /
# `rd(**ppb)` and their struct analogues `take(*&s)` / `take(**pps)` pushed the loaded word as the address (139 on
# x86_64 / IR=3 / aarch64, cx 253 / 252, PE 5). `_dlo_vec` reads `&x` of a vector as its `*V` (`_amp_vd`; `&b + n`
# itself still steps bytes), `**ppb` by D9 (a)'s step word, and `**pps` of a `**S` by its pin's struct (`_dlo_ppsid`).
echo "DR. a dereference through an address-of or a double pointer, into \`*V\` / \`*S\`: the value it names (exit 42)"
cat > "$D/dr1.cyr" <<'EOF2'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    return rd(*&b);            # want 42
}
var rc = main();
syscall(60, rc);
EOF2
cat > "$D/dr2.cyr" <<'EOF2'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    var pb: *f64v2 = &b;
    var ppb: **f64v2 = &pb;
    return rd(**ppb);          # want 42
}
var rc = main();
syscall(60, rc);
EOF2
cat > "$D/dr3.cyr" <<'EOF2'
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn main(): i64 {
    var s: P3; s.a = 1; s.b = 2; s.c = 42;
    return take(*&s);          # want 42; `var ps: *P3 = &s; var pps: **P3 = &ps; take(**pps)` the same
}
var rc = main();
syscall(60, rc);
EOF2
sed 's/    return take(\*&s);          # want 42; `var ps: \*P3 = &s; var pps: \*\*P3 = &ps; take(\*\*pps)` the same/    var ps: *P3 = \&s; var pps: **P3 = \&ps; return take(**pps);/' "$D/dr3.cyr" > "$D/dr4.cyr"
grep -q 'return take(\*\*pps);' "$D/dr4.cyr" || bad "DR4: the **pps form was not derived from the filed struct analogue"
sed 's/rd(\*&b);            # want 42/rd(*(\&b));/' "$D/dr1.cyr" > "$D/dr5.cyr"
grep -q 'rd(\*(&b));' "$D/dr5.cyr" || bad "DR5: the *(&b) form was not derived from the filed repro"
exit_rows DR1 "$D/dr1.cyr" 42 "rd(*&b): the filed repro, &b passed"
exit_rows DR2 "$D/dr2.cyr" 42 "rd(**ppb): the filed repro, *ppb passed"
exit_rows DR3 "$D/dr3.cyr" 42 "take(*&s): the struct analogue, &s passed"
exit_rows DR4 "$D/dr4.cyr" 42 "take(**pps): the struct analogue, *pps passed"
exit_rows DR5 "$D/dr5.cyr" 42 "rd(*(&b))"
DRH="${H}struct Pt { x; y; }\nstruct P3 { a; b; c; }\nstruct Q3 { x; y; z; }\nfn rd(p: *f64v2): i64 { return load64(p); }\nfn rp(p: *Pt): i64 { return p.x; }\nfn take(p: *P3): i64 { return p.c; }\n"
refused DRY1 "DRY1 rd(*&f), f an f32v4 (A2)" "${DRH}fn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(*&f) + 1; }\n${E}" x86 "cannot pass 'f' $FRAG 'rd'"
refused DRY2 "DRY2 rd(**ppf), ppf a **f32v4 (A2)" "${DRH}fn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); var pf: *f32v4 = &f; var ppf: **f32v4 = &pf; return rd(**ppf) + 1; }\n${E}" x86 "cannot pass 'ppf' $FRAG 'rd'"
refused DRS1 "DRS1 take(**ppq), ppq a **Q3 (another 24-byte struct, its pin declared after P3's)" "${DRH}fn main(): i64 { var s: P3; var ps: *P3 = &s; var pps: **P3 = &ps; var q: Q3; var pq: *Q3 = &q; var ppq: **Q3 = &pq; return take(**ppq) + take(**pps); }\n${E}" x86 "cannot pass 'ppq' to a parameter of a different struct type in a call to 'take'"
refused DRK "DRK rp(*&b) into *Pt: a vector dereference into another pointer kind (D31)" "${DRH}fn main(): i64 { var b: f64v2 = f64v2_make(42, 7); return rp(*&b) + 1; }\n${E}" x86 "cannot pass '*b' $KFRAG 'rp'"
if [ "$WINE" = 1 ]; then
    refused DRYw1 "DRYw DRY1 on PE" "${DRH}fn main(): i64 { var f: f32v4 = f32v4_make(1, 2, 3, 4); return rd(*&f) + 1; }\n${E}" pe "cannot pass 'f' $FRAG 'rd'"
    refused DRSw1 "DRSw DRS1 on PE" "${DRH}fn main(): i64 { var s: P3; var ps: *P3 = &s; var pps: **P3 = &ps; var q: Q3; var pq: *Q3 = &q; var ppq: **Q3 = &pq; return take(**ppq) + take(**pps); }\n${E}" pe "cannot pass 'ppq' to a parameter of a different struct type in a call to 'take'"
fi

echo "V8. the filed repro, verbatim: a value-form \`v: f32v8\` parameter is its 32 bytes (exit 38; 0 before)"
cat > "$D/v8.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn lanes8(v: f32v8): i64 { return load32(&v + 8) * 10 + load32(&v + 28); }
fn main(): i64 {
    var e: f32v8 = f32v8_make(1, 2, 3, 4, 5, 6, 7, 8);
    return lanes8(e);
}
var rc = main();
syscall(60, rc);
EOF
exit_rows V8 "$D/v8.cyr" 38 "lane 2 * 10 + lane 7"
echo "VY. the other 32-byte vector into a value-form \`v: f32v8\` / \`v: f64v4\` parameter: refused by name, once"
VFR8="value-form SIMD arg type mismatch (callee expects f32v8)"
VFR4="value-form SIMD arg type mismatch (callee expects f64v4)"
# (an `if` keeps g from the inline replay, so the call's own check runs; VY3 is the replay's)
VY1B="${H}fn g(v: f32v8): i64 { if (load32(&v) == 9) { return 0; } return load32(&v + 8); }\nfn main(): i64 { var e: f64v4 = f64v4_make(1, 2, 3, 4); return g(e) + 1; }\n${E}"
VY2B="${H}fn g(v: f64v4): i64 { if (load64(&v) == 9) { return 0; } return load64(&v + 8); }\nfn main(): i64 { var e: f32v8 = f32v8_make(1, 2, 3, 4, 5, 6, 7, 8); return g(e) + 1; }\n${E}"
refused VY1 "VY1 an f64v4 local into v: f32v8" "$VY1B" x86 "$VFR8"
refused VY2 "VY2 an f32v8 local into v: f64v4" "$VY2B" x86 "$VFR4"
refused VY3 "VY3 VY1 through an #inline fn (the inline replay)" "${H}#inline\nfn g(v: f32v8): i64 { return load32(&v + 8); }\nfn main(): i64 { var e: f64v4 = f64v4_make(1, 2, 3, 4); return g(e); }\n${E}" x86 "$VFR8"
if [ "$WINE" = 1 ]; then
    refused VYw1 "VYw1 VY1 on PE" "$VY1B" pe "$VFR8"
    refused VYw2 "VYw2 VY2 on PE" "$VY2B" pe "$VFR4"
fi

# 6.7.13 (D30 A) — a vector CALL RESULT into a value-form vector parameter is passed (issues/2026-10-15-vector-call-
# result-into-value-form-vector-parameter.md).
echo "VC. a vector call result into a value-form parameter: passed (D30 A)"
printf '%s\n' 'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }' \
  'fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }' \
  'fn run(): i64 {' \
  '    return lanes(mkv(4, 2));' \
  '}' \
  'syscall(60, run());' > "$D/vc1.cyr"
exit_rows VC1 "$D/vc1.cyr" 42 "the filed repro: lanes(mkv(4, 2))"
printf '%s\n' 'include "lib/syscalls.cyr"' 'include "lib/simd.cyr"' \
  'fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }' \
  'fn main(): i64 {' \
  '    var a: f64v2 = mkv(1, 2);' \
  '    var r: f64v2 = f64v2_add(a, mkv(3, 4));' \
  '    return load64(&r) * 10 + load64(&r + 8);' \
  '}' 'var rc = main();' 'syscall(60, rc);' > "$D/vc2.cyr"
exit_rows VC2 "$D/vc2.cyr" 46 "f64v2_add(a, mkv(3, 4)): (1 + 3) * 10 + (2 + 4)"
VCH="${H}fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }\nfn mk4(a): f64v4 { var v: f64v4; store64(&v, a); return v; }\nfn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }\n"
VZ1B="${VCH}fn main(): i64 { return lanes(mk4(1)); }\n${E}"
VZ2B="${VCH}var r1 = lanes(mkv(4, 2));\nsyscall(60, r1);\n"
VZ3B="${VCH}fn main(): i64 { return lanes(5); }\n${E}"
VZ3F="a value-form vector argument to 'lanes' is a local of its type or a call declared to return it"
VZ4B="fn lanes(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }\nfn run(): i64 {\n    var x = 5;\n    return lanes(x);\n}\nsyscall(60, run());\n"
VZ4F="value-form SIMD arg must be a 16-byte vector"
for lg in x86 a64 cx pe; do
    case "$lg" in a64) [ -n "$A64" ] || continue;; cx) [ -n "$CXCC" ] || continue;; pe) [ "$WINE" = 1 ] || continue;; esac
    refused "VZ1$lg" "VZ1 $lg: a call of another vector type (f64v4 into x: f64v2)" "$VZ1B" "$lg"
    refused "VZ2$lg" "VZ2 $lg: a top-level lanes(mkv(..)) (no frame for the temp, D40)" "$VZ2B" "$lg" "$Y13F"
    refused "VZ3$lg" "VZ3 $lg: lanes(5), one line (no 'expected ;' cascade)" "$VZ3B" "$lg" "$VZ3F"
    refused "VZ4$lg" "VZ4 $lg: pw.cyr, a word local (PE: parity with the three)" "$VZ4B" "$lg" "$VZ4F"
done
if [ "$WINE" = 1 ]; then
    refused VZw1 "VZw1 pe: lanes(G) of a vector global, one line (skipped: no 'vector global' second line)" \
        "${VCH}var G: f64v2 = 0;\nfn main(): i64 { store64(&G, 4); store64(&G + 8, 2); return lanes(G); }\n${E}" pe "$VZ3F"
    refused VZw2 "VZw2 pe: lanes(nosuch), one line (skipped: no 'undefined variable' second line)" \
        "${VCH}fn main(): i64 { return lanes(nosuch); }\n${E}" pe "$VZ3F"
fi

echo "S. \`p[1]\` on a \`*f64v2\` parameter is refused as on a \`*f64v2\` local (a vector element: load at p + i)"
printf '%b' "${H}fn rd(p: *f64v2): i64 { var x = p[1]; return 0; }\nfn main(): i64 { return 0; }\n${E}" > "$D/s1.cyr"
printf '%b' "${H}fn rl(): i64 { var b: f64v2; var p: *f64v2 = &b; var x = p[1]; return 0; }\nfn main(): i64 { return 0; }\n${E}" > "$D/s2.cyr"
rc1=0; "$CC" < "$D/s1.cyr" > /dev/null 2> "$D/s1.err" || rc1=$?
rc2=0; "$CC" < "$D/s2.cyr" > /dev/null 2> "$D/s2.err" || rc2=$?
m1=$(grep '^error' "$D/s1.err" | sed 's/^error:<source>:[0-9]*:[0-9]*: //')
m2=$(grep '^error' "$D/s2.err" | sed 's/^error:<source>:[0-9]*:[0-9]*: //')
if [ "$rc1" -eq 0 ] || [ -z "$m1" ]; then bad "S1 the parameter's p[1]: rc $rc1, no refusal"
elif [ "$m1" != "$m2" ]; then bad "S1 the parameter's p[1] is refused otherwise than the local's: '$m1' vs '$m2'"
else ok "S1 the parameter's p[1] is the local's refusal: $(printf '%s' "$m1" | cut -c1-70)"; fi

echo "T. $TC ($N rows)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -h -m1 'error' "$D/t_$n.err" "$D/t_$n.exe.err" 2>/dev/null | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

echo "T2. $TC2 ($N2 rows)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC2" "$D/t2_$n"
    if [ "$RC" -eq -1 ]; then bad "T2 $leg: the values file did not build: $(grep -h -m1 'error' "$D/t2_$n.err" "$D/t2_$n.exe.err" 2>/dev/null | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N2 passed, 0 failed ($N2 total)" ]; then ok "T2 $leg: $LAST"
    else bad "T2 $leg: exit $RC, '$LAST' (want '$N2 passed, 0 failed ($N2 total)') $(grep -m3 'FAIL' "$D/t2_$n.out" | tr '\n' ' ')"; fi
done

echo "T3. $TC3 ($N3 rows)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC3" "$D/t3_$n"
    if [ "$RC" -eq -1 ]; then bad "T3 $leg: the values file did not build: $(grep -h -m1 'error' "$D/t3_$n.err" "$D/t3_$n.exe.err" 2>/dev/null | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N3 passed, 0 failed ($N3 total)" ]; then ok "T3 $leg: $LAST"
    else bad "T3 $leg: exit $RC, '$LAST' (want '$N3 passed, 0 failed ($N3 total)') $(grep -m3 'FAIL' "$D/t3_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a \`*V\` parameter is a pointer: the filed repros (R1 R2 R4 R5) and the decisions (R3, D27) on x86_64 / IR / aarch64 / cx / PE, the refusals each once (Y), the subscript (S), and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE; a value-form f32v8 parameter (V8, VY, $N2 rows T2); a vector call result into a value-form parameter (VC, VZ, $N3 rows T3); an explicit generic call with a refused type argument reported once (Y14-Y22)"
