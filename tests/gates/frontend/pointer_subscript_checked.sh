#!/bin/sh
# tests/gates/frontend/pointer_subscript_checked.sh — 6.7.8 (C2)
#
# What a subscript `x[i]` is, and the shapes it refuses by name. 6.7.8's C2 lane grows this gate
# bite by bite; its first group (C2-2a) is the slice bit.
#
# ST — A STALE SLICE WIDTH IS NO SLICE (C2-2a). A slice local's element width lives in the per-slot
# slice-width table, which most registrations never clear — a fn parameter, a closure parameter —
# so a slot inherited the width of whatever slice last sat there, in ANY earlier fn. An untyped
# parameter then compiled AS A SLICE (6.7.7 and before): `fn b(x, y) { return y[0]; }` read through
# `&y` as a slice header (exit 7 for a buffer holding 7), `y.len` read the frame word above `y`,
# `y.len = 5` wrote it, and the valid `y += 1` was refused as "compound assignment to slice 'y'".
# A slice is now marked by bit 62 of the slot's depth word (SLSLICE, util.cyr), which clears itself
# at the next registration's SLDEP; every slice reader asks `_slice_lw` (parse_types.cyr), which
# trusts the width only behind the bit.
#   ST1  `y[0]` on an untyped parameter after a slice local in an earlier fn: refused (today's
#        "cannot subscript 'y'"), one error line; ST1b the same on a third parameter's slot
#   ST2  `y.len` / `y.len = 5` / `y.ptr = 5`: the non-struct text, one error line
#   ST3  a closure parameter: `|x, p| p[0]` and `|x, p| p.len`: refused, one error line
#   ST4  real slices still read, `.len`, `.ptr`, `.len =`, `.ptr =`: after parameters, in a
#        closure's own body, in a fn after a closure was made (the snapshot restore), after a closed
#        block, in a generic instance, a `slice<T>` spelling, and a 256-byte struct element (its
#        width passes 255) — on x86 (plain, CYRIUS_IR=3), aarch64 (qemu), cx (cxvm) and PE (wine)
#   ST5  `y += 1` on an untyped parameter compiles and runs (7; it was refused as a slice)
#   ST6  a real slice keeps its slice refusals: `s += 1`, `s, x = f2();`, `(s, 1)` — anti-vacuous
#        for the three readers whose answer no ST1-ST3 row reaches
#
# MUTATION LEDGER (scratch trees, each rebuilt with the one change, run as CYCC=<mutant>; 2026-10-10):
#   M1  `_slice_lw` ignores bit 62 (returns the width)  -> RED ST1 ST1b ST2 ST2b ST2c ST3 ST3b ST5
#   M1b SLSLICE never sets bit 62                       -> RED ST4a-e (`cannot subscript 's'`), ST6
#                                                          ST6b ST6c (read as a u128)
#   M1c `_slice_lw` masks the width to a byte (& 0xFF)  -> RED ST4a-e (`s.len` on [Big]: no slice)
#
# P / S0 — THE STEP WORD CARRIES THE ELEMENT KIND (C2-3a). A typed pointer's step (sizeof(T)) is
# all GPSC carried, and `*u8` / `*i8`, `*u32` / `*f32`, `*f64` / `*bool` / `*i64` share steps, so
# C2's `p[i]` and `*p` at the element's width had nothing to load by. The step is now stored and
# carried as one word, `ps | ed << 40` (the element descriptor, parse_decl.cyr `_ek_*`): the slot
# mark (locals, `p: *T` parameters, captures), a field's `_fld_ps`, a return's `_fn_rps`, a global's
# `_gv_ped` beside GVTYPE; an f64 / f32 / bool array records its kind in the descriptor. Nothing
# reads the kind yet — the corpus differential is byte-identical on every target — so these rows
# pin that it changes NOTHING: the readers that use the word as a number take its step.
#   P1  a difference of two pointers of one step and different kinds (`*u32 - *i32`, `*f64 -
#       *i64`, `*u8 - *i8`) is their element count, no new error             (in the PV program)
#   P2  an if-expression over two such pointers keeps the step; P2c different steps keep none
#   P3  `n + p` on a `*u8` / `*i8` (parameter, local, global, field, return) compiles to the bytes
#       of the untyped program — no `n * step` imul
#   P4  `p += 2` on a local, a global and a field, every kind                 (in the PV program)
#   P5  the PV program — typed declarations from another kind's pointer included — has no warning
#   PV  every kind (i8 .. u64, f32, f64, bool, a struct) on every source (local, parameter, global,
#       field, return, capture, if-expression, a generic instance's parameter and return): `p + 1`,
#       `2 + p`, `p - 1`, `(p + 3) - p`, `(p + 1) + 1`, `var q: *T = p + 2`, measured byte-exactly,
#       on x86 (plain, CYRIUS_IR=3), aarch64 (qemu), cx (cxvm) and PE (wine)
#   P6  `*u8` / `*i8` (and step-4, step-8 sets) redeclared globals fold; P6c a different step stays
#       refused
#   S0  `f64[2]` / `f32[4]`, `bool[2]` / `f64[2]`, `f32[2]` / `bool[1]` still fold; S0c / S0d an
#       integer element of the same size stays a different shape
#
# MUTATION LEDGER (C2-3a, scratch trees, 2-stage mutant cycc, the gate as CYCC=<mutant>; 2026-10-10):
#   M5  `_ptr_diff` compares the words                   -> RED P5 PVa-e (P1: "pointer difference
#                                                           of pointers with different element sizes")
#   M6  the if-expression merges the words               -> RED PVa-e (P2: +1 where +4 / +8 / +2)
#   M23 EPTR_SCALE multiplies by the word                -> RED PVa-e: every kind on every source
#                                                           (341 of 513 checks; the struct's kind is 0
#                                                           and passes) — each setter carries its kind;
#                                                           typed_pointer_step.tcyr exits 37 too
#   M24 `_gsgn_shape` keeps the kinds                    -> RED S0a S0b S0e
#   MP3 `_ptr_add` tests the word (`rs > 1`)             -> RED P3 (the imul path)
#   MIP `_int_plus_ptr` multiplies by the word           -> RED PVa-e (`2 + p`)
#   M23 + the factor's step-8 local arm writing the plain step (`_lt_spsc` reverted): 321 fail —
#       the i64 / u64 / f64 / bool LOCAL checks pass again (5 each): that arm is where their kind is set
#
# N0 — AN ELEMENT-TYPED ARRAY RECORDS ITS EXACT N (C2-3b). The bounds-checked mode checks `a[i]`
# against the declared N, and no table held it (a global kept N * sizeof(T) with an 8-byte floor, a
# local its slot span, so `u8[5]` read as 8 elements). N now rides, behind a nonzero descriptor, a
# global's GVSGN bits 16..47 and a stack local's slice-width word (`0 - 2^48 - N`; the closure
# snapshot carries it) — parse_decl.cyr `_arr_gsgn` / `_arr_named_marks`. Nothing reads N until the
# mode's check (C2-8, rows N1-N6 by trip / no-trip), so these rows pin that it changes NOTHING: the
# redeclaration fold compares the descriptor without N, and a bare array's word stays 0x100.
#   N0a `u8[5]` then `u8[6]` (8 B each) fold, and the folded global subscripts as before
#   N0b `i16[3]` / `i16[4]` / `i16[2]` (8 B each, a signed descriptor) fold
#   N0c `u8[8]` then `u8[9]` (8 B vs 16 B) stays refused — the size still decides (anti-vacuous)
#   (S0a / S0e above fold float / bool arrays of different N: f64[2] / f32[4], f32[2] / bool[1])
# Measured with a scratch compiler printing the recorded N at every `a[i]` (2026-10-10): stack
# locals (u8[5], i32[3], u64[1], u8[0], an enum-sized u8[SZ], a const-expression i8[K + 1], a local
# after a closed block, an async fn's u16[9]), a static-fallback u8[200000], declaration-zone and
# post-statement globals, a capture and a nested closure's capture of i32[7], a generic T[3] at
# T = i64 / i16 / i32, f32 / bool / struct / u128 / `*u8` elements, and every fn-local array again
# under CYRIUS_STACK_ARRAYS=0 — each the declared N; the folded `u8[5]` / `u8[6]` global keeps the
# FIRST declaration's N (5), as it keeps its element kind (GVSGN is written before `_gv_fold`).
#
# MUTATION LEDGER (C2-3b, scratch trees, each its 2-stage mutant cycc as build/cycc; 2026-10-10):
#   M24n `_gsgn_shape` keeps N (no `& 0xFFFF`)            -> RED N0a N0b (S0a / S0e stay green:
#        `_ek_legacy` maps a float / bool kind to `g & 0x180`, which drops N with it)
#   MN0  `_arr_gsgn` writes N behind a zero descriptor too -> RED silent_values_checked B12 B13 B15
#        (a bare global's `b OP= v` refusal reads its word as exactly 0x100, `_arr_gbare`)
#
# A / AS / R / W — `p[i]` ON A NAMED `*T`, AND f64 / f32 / bool ELEMENTS (C2-4a; the user's decision,
# 2026-10-10: "p[i] reach: integer, f64, f32 and bool elements"). A name declared `*T` (a local, a
# `p: *T` parameter, a global, a capture, a generic instance's parameter) subscripts as an array does:
# the element at `p + i * sizeof(T)`, the pointer's VALUE the base. Before 6.7.8 it was refused, and so
# were `f64[N]` / `f32[N]` / `bool[N]`. The element is typed as a declared T is (`_esub_load`) and a
# store is checked as a field of T's is (`_esub_assign`, `_ifs_bx_el`); every other name is refused
# by name (`_sub_refuse`).
#   A0  tests/tcyr/crossos/pointer_subscript_values.tcyr compiles with no warning; --syntax-only
#       (cyrius lint) reports nothing
#   A   that file on x86 (plain, CYRIUS_IR=3, CYRIUS_IR=1, CYRIUS_DCE=1), aarch64 (qemu), cx, PE (wine)
#   AS1 an `async fn` (CYRIUS_ASYNC=1): a `p: *i16` parameter, a `*u8` local, f64 / f32 arrays in the
#       heap frame, read and written across two awaits
#   R1  a struct element (`*Pt` parameter, local, global, capture, a generic instance at T = Pt, `*Str`,
#       an untyped impl `self` written): named with its struct; R1h `return self[0];` keeps 6.7.0's
#       refusal, once
#   R2  a pointer / string / enum / vector element (`*cstring`, `*Color`, `**i64`, `*f64v2`), `*u128`
#   R3  an array of struct / enum / cstring / pointer / vector elements
#   R4  an untyped local / parameter / global, a declared i64, a bare / `stack var` / global / captured
#       bare array (their own text), a laundered pointer; R4i since C2-6a a slice element store
#       COMPILES (its rows: tests/gates/frontend/slice_position_refused.sh)
#   R9 / R10 a bool element's `OP=` and a non-bool into one (R10c: boolean values compile); R11 a
#       `: stack` pair stored or combined into an element — each exactly one error line
#   W1-W4 the store warnings (an integer constant into a float element, narrowing into a `*u8`, an f32
#       compound with an f64 operand); W5 none for an i64 element into an f32 element (as an f32 local /
#       field: a float element has no integer width to narrow to)
#
# MUTATION LEDGER (C2-4a, scratch trees, each its 2-stage mutant cycc, this gate +
# array_subscript_forms.sh + typed_array_elem_refusals.sh as CYCC=<mutant>; 2026-10-10):
#   M3    the element's sign ignored (`_ek_w` for `_ek_lw` in _esub_load) -> RED Aa-Ag (`*i8` 0xFF reads
#         255), AS1; array_subscript_forms axis 3 (typed_array_subscript.tcyr's sign rows)
#   M4    f32 rounding dropped for an element (`_ifs_bx_el` k = 2 checks only) -> RED Aa-Ag (`p[0] = 1.5`
#         stores 0, not 0x3FC00000), AS1; typed_array_elem_refusals axis 1b; array_subscript_forms f32_local
#   M7    a local that is no `*T` and no array taken as a `*i64` -> RED ST1 ST1b ST3 R4a R4b R4d-f R4i;
#         array_subscript_forms' bare / scalar / stack rows (they compile)
#   M25   `_arr_sub_load`'s IR record of a signed load dropped -> RED Ab (CYRIUS_IR=3: `*i8` reads
#         6293809); array_subscript_forms axis 3 IR=3
#   MK    the element left untyped (SESTYPE 0) -> RED A0 (20 warnings), A0s, Aa-Ag (`p[1] * 2.0`)
#   MB    a bool element's read not stamped boolean -> RED A0, Aa-Ag (`var b: bool = p[1]` refused)
#   MBASE a local `*T`'s ADDRESS taken as the base -> RED Aa-Ag (exit 139 on x86 / aarch64), AS1;
#         array_subscript_forms pointer_local
#   MCAP  a captured `*T`'s word not loaded -> RED Aa-Ag (capture rows)
#   MGLB  a `*T` global's ADDRESS taken as the base -> RED Aa-Ag (global rows)
#   MR9   the bool-element compound refusal dropped -> RED R9a R9b
#   MR10  the bool-element store check dropped -> RED R10a R10b
#   MSEXW a float element's value width kept -> RED W5 ("narrowing assignment")
#   MPW   every `*T` read as a `*i64` (the word's descriptor ignored) -> RED A0, A0s, Aa-Ag, AS1, R1a-g,
#         R2a-d (27 rows)
#   MSID  the pointee struct never found -> RED R1a-g (the pointer / enum text)
#   MBARE no name taken as a bare array -> RED R4e-h; array_subscript_forms' five bare rows
#   The C2-3b compiler (before this bite) -> RED A0 A0s Aa Ab Af Ag Ae AS1 R1a-g R2a-e R3a-e R4a-i R9-R11
#   W1-W5 (46 rows; Ac / Ad pass: those legs' compilers are built from this tree's src)
#
# B / AS2 / R5-R8 / X — `p[i]` ON A `*T` FIELD OR A CALL RETURNING `*T` (C2-4b; the decision's "bases:
# named variables, fields (`h.p[i]`) and call results (`f()[i]`)"). `h.p[i]`, `a.b.p[i]`, `self.p[i]`,
# `mk(4).p[i]`, `f()[i]`, `g<T>()[i]`, `o.m()[i]` were `expected ';' / '=', got '['`. The base is
# evaluated first, then the index; the element is read / stored as a named `*T`'s, typed by the base's
# DECLARATION (a field's `*T`, a callee's `: *T` — never a scale an argument left behind).
#   B0  tests/tcyr/crossos/pointer_subscript_bases.tcyr compiles with no warning; --syntax-only silent
#   B   that file on x86 (plain, CYRIUS_IR=3, CYRIUS_IR=1, CYRIUS_DCE=1), aarch64 (qemu), cx, PE (wine) —
#       its T1 rows (`return f()[i];` is a call and a load, never a tail call: a `jmp` would return the
#       pointer) and FWD (`fwd()[3]` before `fn fwd(): *u16`) included
#   AS2 a field base and a call base in a suspending `async fn` (CYRIUS_ASYNC=1), across two awaits
#   R5  a field that is no `*T`: read, `=`, `OP=`, the for step, `s.ptr[0]` on a slice, and R5e / R5f
#       `mk(q).n[0]` whose `*i32` ARGUMENT left its scale behind (6.7.7 still adds by it: reported)
#   R6  a call that returns no `*T`: a plain fn (read, statement, for step), `load64(..)`, `fncall1`,
#       `callptr`, a method (read, statement), a generic returning T
#   R1i-k / R2f-g  a `*Pt` field, return and method (the struct named), a `**i64` field, a `*u128` return
#   R7  `a[i][j]` (read, and `a[1][2] = 5`, which was "expected '='"), `h.p[1][2]`, `gp()[1][2] = 5`,
#       `p[0][1] += 1`;  R8  `&a[2]`, `(p + 1)[1]`, `(p)[0]`, `"abc"[1]`, `5[0]` — each one error line
#   X1  --syntax-only (cyrius lint's pre-pass) on field / call / method bases another file declares:
#       rc 0, no error;  X2  it still refuses `get()[1][2]` and `&b[1]` (grammar)
#
# MUTATION LEDGER (C2-4b, scratch trees, each its 2-stage mutant cycc, this gate as CYCC=<mutant>;
# 2026-10-10):
#   M7    a base with no `*T` taken as an `*i64` (`_psub_ed`) -> RED R5a-g R6a-i R8b-e (20 rows build)
#   M8    the `&a[i]` check dropped (`_sub_post`) -> RED R8a X2b (the parenthesis text instead)
#   M22   `return f()[i];` taken as a tail call (PARSE_RETURN accepts `[` after the `)`) -> RED B0 B0s
#         Ba-Bg R6a R2g X2a
#   MW    a field base judged by the scale word (`_sub_word`) -> RED R5e R5f (`mk(q).n[0]` subscripts)
#   MSC   a method taken for a direct call of its name (`_sub_callee`) -> RED B0 Ba-Bg R1k
#   MDIR  a direct call's base judged by the scale word (statement position sets none) -> RED B0 B0s
#         Ba-Bg R7d
#   MFS   PARSE_FIELD_STORE's `[` arm dropped -> RED B0 B0s Ba-Bg R5b-d
#   MSTEP the for step's call arm dropped (`_step_call_sub`) -> RED B0 B0s Ba-Bg R6g X1
#   MSTMT `_stmt_qmark`'s `[` arm dropped -> RED B0 B0s Ba-Bg R6b R6i R1j R7d X1
#   MFLT  `_field_load_type` records no field end (`_flt_ti`) -> RED B0 B0s Ba-Bg R1i R2f R7c
#   MSO   the --syntax-only silence dropped -> RED X1 X2a
#   MR7   `_esub_assign`'s second-`[` refusal dropped -> RED R7b R7d R7e ("expected '='")
#
# D / DR / AS3 / DW / DM / DX — `*p` AT THE ELEMENT'S WIDTH (C2-5; the user's decision, 2026-10-10:
# "`*p`, `*p = v`, `*p OP= v` through a narrow `*T` (`*u8`..`*u32`, `*i8`..`*i32`, `*f32` — f32
# rounding included) read and write at the element's width, the same rule `p[i]` gets"). Before
# 6.7.8 every `*p` loaded and stored 8 bytes. The operand's element comes from the step word, and
# only when the word is the operand's OWN (`_pk_word`: the (code pointer, token) stamp written by a
# name / `*T` field / call in the PARSE_FACTOR wrapper, by pointer arithmetic and an if-expression's
# join, carried across `)`) — the word otherwise still holds the last factor's, e.g. after `m & q`.
#   D0  tests/tcyr/crossos/deref_element_width.tcyr compiles with no warning; --syntax-only silent
#   D   that file on x86 (plain, CYRIUS_IR=3, CYRIUS_IR=1, CYRIUS_DCE=1), aarch64 (qemu), cx, PE (wine):
#       every narrow kind's width / sign / neighbours, eleven OP= with wraparound, every operand form
#       (name, parameter, global, field, call, generic, method, `p ± n`, `n + p`, parentheses, an
#       if-expression, a capture, a generic instance), f32 rounding and typing, the for step, top level,
#       and the operands that stay a WORD (an untyped name, `*i64` / `*f64` / `*bool`, `**pp`, `m & q`,
#       `-(-q)`, `~(~q)`, `0 | q`, a call result's untyped field, a bitwise operand of `+`)
#   DR  the issue's repro VERBATIM (issues/2026-10-08-deref-store-through-narrow-typed-pointer-is-word-
#       store.md; it exited 14) exits 0 on every leg
#   AS3 `*p` through a `*i16` parameter and a `*u8` local in a suspending `async fn`, across awaits
#   DW1-DW3 the store warnings `p[0] = v` gives (an integer constant into a `*f32`, narrowing into a
#       `*u8`, an f32 compound with an f64 operand); DW4 `*p * 2.0` through a `*f64` still warns (the
#       untyped word, the documented rule); DW5 an i64 element into a `*f32` and an f32 OP= warn nothing
#   DM  `*p, x = f2();` through a `*i32` keeps the deref's own refusal, once
#   DX  `*(1 + p) = v` through a `*u8` stores ONE byte and `*(0 + q)` through a `*i8` reads -1 (the C2
#       review; it was a WORD). 6.7.8 carried that kind on a dereference-only stamp; 6.7.9 gives `n + p`
#       p's word (below), which carries it, and the stamp is gone
#   DXc `n + p8` IS that `*u8` (6.7.9; the user's decision 1(b), 2026-10-11; issues/2026-10-10-int-plus-
#       byte-pointer-drops-step.md — `_ptr_add` wrote back the INTEGER's word, 0). DXc1 `(1 + p8) - q32`
#       is the different-sizes error from each one-byte source (local, parameter, global, field, call,
#       `*i8`), as `(p8 + 1) - q32` is (it built a byte difference); DXc2 `var r: *u8 = 1 + p8;` from
#       each source, `*i8`, `7 + (1 + p8)` and a global / field store warn nothing (they warned); DXc3
#       an if-expression of `1 + p8` and `p8`, and `k + p8` on a capture, warn nothing; DXc4 `p8 + 1 -
#       q32` (the control) is still refused; DXc5 `(1 + p8) - p8` and `(1 + i8) - p8` (one size) stay an
#       element count; DXn a narrow SCALAR (`w: u8`, step 1 but no `*T`) stays an integer: `(1 + w) -
#       q32` is `n - p`; DXR the issue's repro VERBATIM: d1, d2, d3 refused, r silent. The value file's
#       onebyte_rows (in typed_pointer_step.tcyr, the PL legs) pin every value, which no row changes.
#   DXs `n + pb` with `pb: *B1` IS that pointer too (6.7.11; the user's decision 2026-10-13: "(a) Yes,
#       extend 1(b)"; issues/2026-10-12-pointer-into-small-byvalue-param-untyped-edges.md): DXs1 `(1 + src)
#       - q32` from each `*B1` source and `(m + pb) - q32` refused (each compiled, a byte difference);
#       DXs2 the control; DXs3 the declaration / assignment / global store silent (they warned); DXs4 one
#       element size an element count; DXs5 an if-expression of `py` and `&s` keeps no step (its warning,
#       and `(if ..) - q32` a plain subtraction) — the argument side is small_struct_pointer_arg.tcyr.
#
# MUTATION LEDGER (C2-5, scratch trees, each its 2-stage mutant cycc, this gate + the value file as
# CYCC=<mutant>; 2026-10-10):
#   M26   a narrow store through ESTORE64 (`_asg_store_w(S, 0)`) -> RED Da-Dg DRa-DRe AS3 DW2 (23 checks)
#   M3    the element's sign ignored in a `*p` read -> RED Da-Dg AS3 (21 checks: `*i8` 0xFF reads 255)
#   M4    the f32 rounding dropped from `*p = v` (the int-into-float check kept) -> RED Da-Dg DRa-DRe
#   MPK1  `_pk_word` trusts the word (no stamp) -> RED Da-Dg (8 word-form checks read an element)
#   MPK2  `_pk_post` takes `-(q)` / `~(q)` for a call -> RED Da-Dg (`*(-(-q))`, `*(~(~q))`)
#   MPK3  `_paren_post` drops the stamp at `)` -> RED D0 D0s Da-Dg (11 checks: `*(p + 1)` a word)
#   MPK4  `_ptr_add` stamps nothing -> RED D0 D0s Da-Dg (10 checks)
#   MPK5  the if-expression's join stamps nothing -> RED Da-Dg (its 4-byte store)
#   MPK6  `_deref_store` reads the operand's element after its push -> RED Da-Dg DRa-DRe AS3 DW1-DW3
#   MPK7  `_pk_post` vouches for any field / call -> RED Da-Dg (`*mkn(q).n`)
#   MPK8 / MPK9 / MPK10  `+`'s left operand, `n + p`'s right, an if-expression branch read through
#         GPSC, not `_pk_word` -> RED Da-Dg (a bitwise operand of `+`, of `n +`, a bitwise branch)
#   MPK11 `_pk_post` vouches for no bare name -> RED Da-Dg DRa-DRe AS3 DW1-DW3 (51 checks)
#   (6.7.9, the one-byte `n + p` keeps p's word — `_add_word`; scratch trees, 2-stage mutant cycc, 2026-10-11):
#   MOB1  `_add_word` writes the left word back (the old rule) -> RED Da-Dg (`*(n + p) = v` stores a
#         word: the dereference reads the word now), DX DXr DXc1 (6) DXc2 DXc3 DXR PL0
#   MOB2  `_add_word` writes any step-1 word (no element-kind test) -> RED DXn, PL0 PL0s PLa-PLg (the value
#         file's `(1 + w) - q` with `w: u8` refused as a pointer difference)
#   (6.7.11, decision 1(b) extended to a one-byte struct pointer — `_add_rb1`; scratch trees, 2026-10-14):
#   the fix reverted (A3's f64 tree, 4b05d52a) -> RED DXs1 (6: compiled, a byte difference) DXs3 (warned)
#   MOB3  `_ptr_add` without `_add_rb1`             -> RED DXs1 (6) DXs3
#   MOB4  `_add_rb1` keeping any step-1 word (no `_hl_psid` typing) -> RED DXn, PL0 PL0s PLa PLb PLf PLg PLe
#         (the value file's `(1 + w) - q` with `w: u8` refused as a pointer difference)
#   The compiler before this bite -> RED DXc1 (6) DXc2 DXc3 DXR PL0 (its two warnings); the values all pass
#   (235 of 235: a step of 1 scales nothing). The dereference-only stamp's removal is proven by a corpus
#   differential: 1098 tree sources compile byte-identically, diagnostics included, with and without it.
#   MSEXW an f32 element's store keeps the value's width -> RED DW5 ("narrowing assignment")
#   M27   `_slot_ptr_step` unmasked: EQUIVALENT — its one caller's `p += n` scales through EPTR_SCALE,
#         which masks too (C2-3a); typed_pointer_step.tcyr and this gate stay green
#   The C2-4b compiler (before this bite) -> RED Da Db De Df Dg DRa DRb DRe AS3 DW1-DW3 (Dc / Dd / DRc /
#   DRd pass: those legs' compilers are built from this tree's src); the value file: 64 of 120 fail
#
# PL / PLR / PLW / PLD — A POINTER'S STEP DIES WITH THE OPERATOR THAT CONSUMED IT (6.7.9; the user's
# decision 1(a), 2026-10-11; issues/2026-10-10-pointer-step-leaks-through-operators.md). The step word
# is the last factor's and only `+` / `-` wrote theirs back, so with `q: *i32` `(x == q) + 100` was 401,
# `(m & q) + 1` 4, `(-q) + 1` -q + 4, `mk(q).n + 1` 4 (6.6.17-6.7.8, every target). Now a comparison,
# `&&` / `||`, `* / % << >> >>>`, `& | ^`, unary `-` / `~`, a postfix `?`, an operator fn's result and
# a field that is no `*T` leave no step.
#   PL0 tests/tcyr/crossos/typed_pointer_step.tcyr (op_rows_*: the issue's table at *i16 / *i32 / *i64 /
#       *Pt, in a `+` and a `-` position, unparenthesised, as the right of `n +`, and the pointer-
#       arithmetic controls; qm_rows: `(p?) + 1`; intrin_rows: a builtin at the head of a term,
#       `bitget(m, 0, q) + 1`, is a plain value — 6.6.17's call rule, which PARSE_TERM's own dispatch
#       skipped) compiles with only its five `#inline ignored` notes; PL0s --syntax-only
#   PL  that file on every leg; PLR the issue's repro VERBATIM (it exited 255) on every leg
#   PLW1-3 `0 | q`, `-q`, `hn(q).n` into a `*i32` warn "assigning non-pointer" (as `q | 0` / `h.n` did);
#       PLWc pointer arithmetic with such an operand (`q + (x == q)`, `q - (k * q)`) warns nothing
#   PLD `p16 - (k * q32)` is `p - n` (it was refused as a different-sizes difference); PLDc `p16 - q32`
#       still is
#   PLWo (6.7.9 review) an operator fn that DECLARES `: *T` gives a pointer stepping by T, as its free
#       call does — `v + q`, `v * q`, `(v + q) + 1` into a `*i32` warn nothing (bite 5 reset the step
#       to 0: `(v + q) + 1` stepped 1, and they warned); PLW4 a plain-return one's result still warns
#
# MUTATION LEDGER (6.7.9, scratch trees, each its 2-stage mutant cycc, this gate as CYCC=<mutant> and
# the value file; 2026-10-11):
#   MPL1  no reset after a comparison (_PLOGIC_ATOM)  -> RED PLa PLb PLf PLg PLe PLRa PLRb PLRe (20 checks)
#   MPL2  none after an `&&` link (_PLOGIC_AND)       -> RED PLa PLb PLf PLg PLe PLRa PLRb PLRe (4)
#   MPL3  none after an `||` link (PCMPE)             -> RED PLa PLb PLf PLg PLe (4)
#   MPL4  none after `* / % << >> >>>` (the TERM loop) -> RED PL* PLR* PLWc PLD (28)
#   MPL5  none after `& | ^` (_pexpr_bit_ps)          -> RED PL* PLR* PLW1 (20)
#   MPL5b `& | ^` clear the word but keep the left step -> RED PL* (8: `q & qq + 1`, `q ^ qq - 1`)
#   MPL6  none after unary `-` (_neg_int)             -> RED PL* PLW2 (8)
#   MPL7  none after unary `~` (_bnot_int)            -> RED PL* PLR* (4)
#   MPL8  a non-`*T` field keeps the word (_field_load_type) -> RED PL* PLR* PLW3 (12)
#   MPL9  an operator fn's result keeps it (EMIT_OP_DISPATCH) -> RED PL* (4: `(v + q) + 1`)
#   MPL10 a postfix `?` keeps it (_PARSE_TERM_IMPL)   -> RED PL* (4: `(p?) + 1`)
#   MPL11 (6.7.9 review) the operator fn's step forced to 0, bite 5's `SPSC(S, 0)` (EMIT_OP_DISPATCH)
#                                                     -> RED PL* (the `Vp` rows) PLWo
#   MPL12 the `+` / `-` loop not taking it (`ps = GPSC(S)` dropped, either arm)
#                                                     -> RED PL* (`vp + q + 2` / `vp - q - 1`)
#   MPL13 the `*` / `/` loop resetting it (`continue` dropped, either arm)
#                                                     -> RED PL* (`vp * q + 1`, `(vp * q) - 1`, `2 + (vp * q)`
#                                                        / `vp / q + 3`) PLWo (the `*` arm)
#   (MPL11-13: every leg, aarch64 / cx included — their compilers built from the mutated copy)
#   MIN1  a builtin keeps its last argument's (PARSE_INTRIN) -> RED PL* (4: `bitget(m, 0, q) + 1`)
#   (PL* / PLR* = the x86 legs and PE; the aarch64 / cx legs' compilers are built from this tree's src)
#   The compiler before this bite -> RED PLa PLb PLf PLg PLe PLRa PLRb PLRe PLW1-3 PLWc PLD (the value
#   file: 112 of 215 fail); its aarch64 / cx compilers exit 255 on the repro and 112 on the value file
#
# AW — THE VALUE OF `await f` IS AN UNTYPED WORD (6.7.11; issues/2026-10-11-await-result-keeps-typed-
# pointer-step.md — the last arm of 6.7.9's decision 1(a), "the pointer step resets after every
# operator that does not produce a pointer"). Neither the force call (`_await_force`) nor a coroutine's
# suspend landing (`_await_coro_suspend`) reset the step the operand factor left, so with `f: *i32`
# `(await f) + 1` was 9 (5 + 1 * sizeof(i32)), on x86_64 and aarch64, in a coroutine too (6.6.17-6.7.10).
#   AW1 the issue's repro VERBATIM: 6 (it was 9); AW2 `f: *u8`; AW2d `((await f) + 1) - q32` with
#       `f: *u8` is `n - p` (it was refused "pointer difference ... different element sizes");
#   AW3 / AW4 / AW4d the same inside a coroutine (an async fn driven by future_force / future_pending;
#       x86 only — aarch64 refuses a mid-body suspend by name); AWc1 / AWc2 the untyped control
#       `var f = five();`, outside and inside; AWc3 the Future pointer `f: *i32` itself still steps
#   (x86 plain and CYRIUS_IR=3; aarch64 (qemu) for the rows outside a coroutine)
# MUTATION LEDGER (6.7.11, scratch trees, each its 2-stage mutant cycc, this gate as CYCC=<mutant>):
#   MAW1 `_await_force` without its `SPSC(S, 0)`        -> RED AW1a AW1b AW2da AW2db (its aarch64
#                                                          compiler: the repro exits 9)
#   MAW2 `_await_coro_suspend` without its `SPSC(S, 0)` -> RED AW3a AW3b AW4da AW4db
#   The compiler before this bite -> RED AW1a AW1b AW2da AW2db AW3a AW3b AW4da AW4db (its aarch64
#   compiler: the repro exits 9)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=pointer_subscript_checked
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper. CHANGELOG [6.6.16] [6.6.17]
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
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# refused <name> <fragment> <what> <body>: compile fails with exactly one error line holding the fragment
refused() {
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$3: compiled (rc 0) — want the refusal \"$2\""
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines, want exactly 1: $(grep '^error' "$T/$1.err" | head -3 | tr '\n' '|')"
    elif grep '^error' "$T/$1.err" | grep -qF "$2"; then ok "$3"
    else bad "$3: wrong refusal: $(grep '^error' "$T/$1.err" | head -1)"; fi
}
# exits <name> <want> <what> <body>: compiles and exits <want>
exits() {
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}

# ── ST: a stale slice width is no slice ───────────────────────────────────────────────────────
# `a`'s slice sits in slots 0 (the nameless high half) and 1 (the canonical slot) — `y`'s slot in b.
SA='include "lib/slice.cyr"\nfn a() { var s: [i64] = 0; return 0; }\n'
BUF='var buf[16];\nstore64(&buf, 7);\n'
refused st1 "cannot subscript 'y'" "ST1: y[0] on an untyped parameter after a slice local (was a slice read, exit 7)" \
    "${SA}fn b(x, y) { return y[0]; }\n${BUF}var r = b(1, &buf);\nsyscall(60, r);\n"
refused st1b "cannot subscript 'z'" "ST1b: z[1] on a third parameter's slot (a slice after a parameter)" \
    'include "lib/slice.cyr"\nfn a(p) { var s: [u8] = 0; return p; }\nfn b(x, y, z) { return z[1]; }\nvar buf[16];\nvar r = b(1, 2, &buf);\nsyscall(60, r);\n'
refused st2 "no struct type in scope for 'y'" "ST2: y.len on an untyped parameter (read the frame above y)" \
    "${SA}fn b(x, y) { return y.len; }\n${BUF}var r = b(1, &buf);\nsyscall(60, r);\n"
refused st2b "no struct type in scope for 'y'" "ST2b: y.len = 5 on an untyped parameter (wrote the frame)" \
    "${SA}fn b(x, y) { y.len = 5; return 0; }\n${BUF}var r = b(1, &buf);\nsyscall(60, r);\n"
refused st2c "no struct type in scope for 'y'" "ST2c: y.ptr = 5 on an untyped parameter" \
    "${SA}fn b(x, y) { y.ptr = 5; return 0; }\n${BUF}var r = b(1, &buf);\nsyscall(60, r);\n"
refused st3 "cannot subscript 'p'" "ST3: |x, p| p[0] — a closure parameter" \
    "${SA}fn b() { var k = |x, p| p[0]; ${BUF}return callptr(k, 1, &buf); }\nsyscall(60, b());\n"
refused st3b "no struct type in scope for 'p'" "ST3b: |x, p| p.len — a closure parameter" \
    "${SA}fn b() { var k = |x, p| p.len; ${BUF}return callptr(k, 1, &buf); }\nsyscall(60, b());\n"
exits st5 7 "ST5: y += 1 on an untyped parameter after a slice local (was refused as a slice)" \
    "${SA}fn b(x, y) { y += 1; return y; }\nvar r = b(1, 6);\nsyscall(60, r);\n"

# ST6: a REAL slice keeps the refusals of the readers no ST1-ST3 row reaches
SL='include "lib/slice.cyr"\nfn f2(): i64 { return (3, 4); }\nfn b(): i64 {\n    var w: i64[2];\n    var s: [i64] = 0;\n    slice_set(&s, &w, 2);\n    var x = 0;\n'
refused st6 "compound assignment to slice 's'" "ST6: s += 1 on a slice (_asg_wide_refused)" \
    "${SL}    s += 1;\n    return x;\n}\nsyscall(60, b());\n"
refused st6b "cannot re-assign slice 's'" "ST6b: s, x = f2(); (_masg_kind)" \
    "${SL}    s, x = f2();\n    return x;\n}\nsyscall(60, b());\n"
refused st6c "not a slice" "ST6c: var t = (s, 1); (_tup_wide_name)" \
    "${SL}    var t = (s, 1);\n    return x;\n}\nsyscall(60, b());\n"

# ST4: real slices on every registration path, on every leg (exit 0; else the failing check's number)
cat > "$T/st4.cyr" <<'EOF'
include "lib/slice.cyr"
# 256 B: a slice of Big has element width 256 (a byte mask on the width would read 0, no slice)
struct Big { f0; f1; f2; f3; f4; f5; f6; f7; f8; f9; f10; f11; f12; f13; f14; f15; f16; f17; f18; f19; f20; f21; f22; f23; f24; f25; f26; f27; f28; f29; f30; f31; }
fn after_params(a, b, c): i64 {
    var buf: i64[4];
    buf[0] = a;
    buf[1] = b;
    buf[2] = c;
    var s: [i64] = 0;
    slice_set(&s, &buf, 3);
    return s[0] + s[1] + s[2] + s.len;
}
fn closure_own(n): i64 {
    var k = |m| { var b: i64[2]; b[0] = m; b[1] = m + 1; var s: [i64] = 0; slice_set(&s, &b, 2); return s[1] + s.len; };
    return callptr(k, n);
}
fn after_closure(): i64 {
    var b: u8[4];
    b[0] = 10;
    b[1] = 20;
    b[2] = 30;
    var s: [u8] = 0;
    slice_set(&s, &b, 3);
    var k = |x, y| x + y;
    var t = callptr(k, 1, 2);
    return s[2] + s.len + t;
}
fn after_block(n): i64 {
    if (n > 0) { var t = n; n = t + 1; }
    var b: u16[2];
    b[0] = 400;
    b[1] = 500;
    var s: [u16] = 0;
    slice_set(&s, &b, 2);
    return s[1] + n;
}
fn gsum<T>(x: T): i64 {
    var b: i64[2];
    b[0] = 7;
    b[1] = 8;
    var s: [i64] = 0;
    slice_set(&s, &b, 2);
    return s[1] + s.len + x;
}
fn fields(): i64 {
    var b: i64[3];
    b[0] = 4;
    var s: [i64] = 0;
    slice_set(&s, &b, 3);
    s.len = 1;
    if (s.ptr != &b) { return 100; }
    s.ptr = &b;
    return s.len + s[0];
}
fn big(): i64 {
    var bg: Big;
    bg.f0 = 3;
    var s: [Big] = 0;
    slice_set(&s, &bg, 1);
    if (s.ptr != &bg) { return 100; }
    return s.len;
}
fn spelled(): i64 {
    var b: i32[2];
    b[0] = 6;
    b[1] = 9;
    var s: slice<i32> = 0;
    slice_set(&s, &b, 2);
    return s[1] + s.len;
}
fn main(): i64 {
    if (after_params(1, 2, 3) != 9) { return 1; }
    if (closure_own(5) != 8) { return 2; }
    if (after_closure() != 36) { return 3; }
    if (after_block(1) != 502) { return 4; }
    if (gsum<i64>(1) != 11) { return 6; }
    if (fields() != 5) { return 7; }
    if (big() != 1) { return 8; }
    if (spelled() != 11) { return 9; }
    return 0;
}
var rc = main();
syscall(60, rc);
EOF
# legs <name> <row> <what> [full]: $T/<name>.cyr built and run on every leg — x86 (plain, CYRIUS_IR=3;
# `full` adds CYRIUS_IR=1 and CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm), PE (wine); exit 0 passes, else the exit (ST4: the failing check's
# number; an assert program: its failure count) and the program's first FAIL line. The cross
# compilers are built once, from this tree, by the compiler under test.
XCC=0
xcc() {
    [ "$XCC" -eq 0 ] || return 0
    XCC=1
    if command -v qemu-aarch64 > /dev/null 2>&1; then
        "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ] && chmod +x "$T/cc_a64" || rm -f "$T/cc_a64"
    fi
    if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
       && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
        chmod +x "$T/cc_cx" "$T/cxvm"
    else rm -f "$T/cc_cx" "$T/cxvm"; fi
}
leg_ok() {   # <label> <exit> <what> <output file>
    if [ "$2" -eq 0 ]; then ok "$1: $3"
    else bad "$1: exit $2 $(grep -m1 'FAIL' "$4" 2> /dev/null || echo '(the failing check'"'"'s number)')"; fi
}
legs() {
    n=$1; r=$2; w=$3
    xcc
    xm="plain IR3"
    [ "${4:-}" = full ] && xm="plain IR3 IR1 DCE1"   # C2-4a: the value file also under IR=1 and DCE=1
    for mode in $xm; do
        case $mode in
            plain) env_=""; lbl="${r}a: x86" ;;
            IR3) env_="CYRIUS_IR=3"; lbl="${r}b: x86, CYRIUS_IR=3" ;;
            IR1) env_="CYRIUS_IR=1"; lbl="${r}f: x86, CYRIUS_IR=1" ;;
            DCE1) env_="CYRIUS_DCE=1"; lbl="${r}g: x86, CYRIUS_DCE=1" ;;
        esac
        rc=0; env $env_ "$CC" < "$T/$n.cyr" > "$T/${n}_$mode" 2> "$T/${n}_$mode.err" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/${n}_$mode.err" | head -1)"; continue; fi
        chmod +x "$T/${n}_$mode"; got=0; timeout 30 "$T/${n}_$mode" > "$T/${n}_$mode.out" 2>&1 || got=$?
        leg_ok "$lbl" "$got" "$w" "$T/${n}_$mode.out"
    done
    if ! command -v qemu-aarch64 > /dev/null 2>&1; then
        echo "  SKIP ${r}c: aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1))
    elif [ ! -x "$T/cc_a64" ]; then bad "${r}c: src/main_aarch64.cyr did not build"
    elif "$T/cc_a64" < "$T/$n.cyr" > "$T/$n.a64" 2> "$T/$n.a64.err" && [ -s "$T/$n.a64" ]; then
        chmod +x "$T/$n.a64"; got=0; (cd "$T" && timeout 60 qemu-aarch64 "./$n.a64" > "$T/$n.a64.out" 2>&1) || got=$?
        leg_ok "${r}c: aarch64 (qemu)" "$got" "$w" "$T/$n.a64.out"
    else bad "${r}c: aarch64: did not compile: $(grep '^error' "$T/$n.a64.err" | head -1)"; fi
    if [ ! -x "$T/cc_cx" ]; then bad "${r}d: src/main_cx.cyr or programs/cxvm.cyr did not build"
    elif "$T/cc_cx" < "$T/$n.cyr" > "$T/$n.cyx" 2> "$T/$n.cyx.err" && [ -s "$T/$n.cyx" ]; then
        got=0; timeout 60 "$T/cxvm" < "$T/$n.cyx" > "$T/$n.cyx.out" 2>&1 || got=$?
        leg_ok "${r}d: cx (cxvm)" "$got" "$w" "$T/$n.cyx.out"
    else bad "${r}d: cx: did not compile: $(grep '^error' "$T/$n.cyx.err" | head -1)"; fi
    if ! command -v wine > /dev/null 2>&1; then
        echo "  SKIP ${r}e: PE leg — wine not installed"; skips=$((skips + 1))
    elif CYRIUS_TARGET_WIN=1 "$CC" < "$T/$n.cyr" > "$T/$n.exe" 2> "$T/$n.exe.err" && [ -s "$T/$n.exe" ]; then
        got=0
        (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$n.exe" > "$T/$n.exe.out" 2>&1) || got=$?
        leg_ok "${r}e: PE (wine)" "$got" "$w" "$T/$n.exe.out"
    else bad "${r}e: PE: did not compile: $(grep '^error' "$T/$n.exe.err" | head -1)"; fi
}
legs st4 ST4 "every real-slice check"

# ── P / S0: the step word carries the element kind (C2-3a) ────────────────────────────────────
# P1-P5 + the source x kind arithmetic: one assert program, generated — every element kind (i8 u8
# i16 u16 i32 u32 i64 u64 f32 f64 bool, and a 24-byte struct) on every pointer source (a local, a
# parameter, a global, a field, a `*T` return, a capture, an if-expression, a generic instance's
# parameter and return), each `p + 1`, `2 + p`, `p - 1`, `(p + 3) - p`, `(p + 1) + 1`, a typed
# `var q: *T = p + 2` and `p += 2` measured byte-exactly against `&pv_buf`. Address arithmetic only
# (nothing is dereferenced), so a leaked kind is a wrong number, never a fault.
pv_src() {   # <pointer expr> <label> <sizeof(T)>
    cat <<EOF
    a = $1 + 1;
    assert_eq(a - B, $3, "$2: p + 1");
    a = 2 + $1;
    assert_eq(a - B, 2 * $3, "$2: 2 + p");
    a = $1 - 1;
    assert_eq(a - B, 0 - $3, "$2: p - 1");
    a = ($1 + 3) - $1;
    assert_eq(a, 3, "$2: (p + 3) - p");
    a = ($1 + 1) + 1;
    assert_eq(a - B, 2 * $3, "$2: (p + 1) + 1");
EOF
}
pv_kind() {   # <T> <sizeof(T)>
    k=$1; s=$2
    cat <<EOF
struct PVH_$k { p: *$k; }
var PVG_$k: *$k = 0;
fn pvr_$k(): *$k { return &pv_buf; }
fn pvp_$k(p: *$k, c): i64 {
    var B = &pv_buf;
    var a = 0;
$(pv_src p "$k parameter" "$s")
$(pv_src "(if (c) { p } else { p })" "$k if-expression" "$s")
$(pv_src "pvr_$k()" "$k return" "$s")
    return 0;
}
fn pvl_$k(): i64 {
    var B = &pv_buf;
    var a = 0;
    var p: *$k = &pv_buf;
$(pv_src p "$k local" "$s")
    var q: *$k = p + 2;
    a = q;
    assert_eq(a - B, 2 * $s, "$k local: var q: *$k = p + 2");
    PVG_$k = &pv_buf;
$(pv_src "PVG_$k" "$k global" "$s")
    var h: PVH_$k;
    h.p = &pv_buf;
$(pv_src h.p "$k field" "$s")
    var k1 = || { var B1 = &pv_buf; var a1 = p + 1; return a1 - B1; };
    assert_eq(callptr(k1), $s, "$k capture: p + 1");
    var k2 = || { var B2 = &pv_buf; var a2 = 2 + p; return a2 - B2; };
    assert_eq(callptr(k2), 2 * $s, "$k capture: 2 + p");
    var k3 = || { return (p + 3) - p; };
    assert_eq(callptr(k3), 3, "$k capture: (p + 3) - p");
    p += 2;
    a = p;
    assert_eq(a - B, 2 * $s, "$k local: p += 2");
    PVG_$k += 2;
    a = PVG_$k;
    assert_eq(a - B, 2 * $s, "$k global: p += 2");
    h.p += 2;
    a = h.p;
    assert_eq(a - B, 2 * $s, "$k field: p += 2");
    return 0;
}
EOF
}
PVK="i8:1 u8:1 i16:2 u16:2 i32:4 u32:4 i64:8 u64:8 f32:4 f64:8 bool:8 Pt:24"
{
    printf 'include "lib/assert.cyr"\nstruct Pt { x; y; z; }\nvar pv_buf: i64[32];\n'
    for ks in $PVK; do pv_kind "${ks%%:*}" "${ks#*:}"; done
    cat <<EOF
fn pvg<T>(p: *T, s): i64 {
    var B = &pv_buf;
    var a = 0;
$(pv_src p "generic parameter" s)
    return 0;
}
fn pvgr<T>(): *T { return &pv_buf; }
fn pvgc<T>(s): i64 {
    var B = &pv_buf;
    var a = 0;
$(pv_src "pvgr<T>()" "generic return" s)
    return 0;
}
# P1 a difference of two pointers of one step and different kinds is their element count (no new
# error); P2 an if-expression over two such pointers keeps the step (P2c: different steps keep
# none, as before); P5 a typed declaration from one of another kind takes no warning.
fn pvmix(c, gf: *f64): i64 {
    var B = &pv_buf;
    var a = 0;
    var p32: *i32 = &pv_buf;
    var pu: *u32 = &pv_buf;
    pu = pu + 3;
    assert_eq(pu - p32, 3, "P1 *u32 - *i32 (locals)");
    PVG_i64 = &pv_buf;
    assert_eq((gf + 2) - PVG_i64, 2, "P1 *f64 parameter - *i64 global");
    var h: PVH_u8;
    h.p = &pv_buf;
    assert_eq((h.p + 5) - pvr_i8(), 5, "P1 *u8 field - *i8 return");
    a = (if (c) { p32 } else { pu }) + 1;
    assert_eq(a - B, 4, "P2 (if (c) { *i32 } else { *u32 }) + 1");
    a = (if (c) { gf } else { PVG_i64 }) + 1;
    assert_eq(a - B, 8, "P2 (if (c) { *f64 } else { *i64 }) + 1");
    a = (if (c) { pvr_u16() } else { pvr_i16() }) + 1;
    assert_eq(a - B, 2, "P2 (if (c) { *u16 call } else { *i16 call }) + 1");
    var p16: *i16 = &pv_buf;
    a = (if (c) { p32 } else { p16 }) + 1;
    assert_eq(a - B, 1, "P2c (if (c) { *i32 } else { *i16 }) + 1: no step");
    var qx: *u32 = p32 + 1;
    a = qx;
    assert_eq(a - B, 4, "P5 var q: *u32 = (*i32) + 1");
    var qf: *f32 = pu - 3;
    a = qf;
    assert_eq(a - B, 0, "P5 var q: *f32 = (*u32) - 3");
    return 0;
}
alloc_init();
EOF
    for ks in $PVK; do k=${ks%%:*}; printf 'pvp_%s(&pv_buf, 1);\npvl_%s();\n' "$k" "$k"; done
    for ks in i8:1 i16:2 i32:4 i64:8 f64:8 Pt:24; do
        printf 'pvg<%s>(&pv_buf, %s);\npvgc<%s>(%s);\n' "${ks%%:*}" "${ks#*:}" "${ks%%:*}" "${ks#*:}"
    done
    printf 'pvmix(1, &pv_buf);\nsyscall(60, assert_summary());\n'
} > "$T/pv.cyr"
# P5: no declaration of the program warns (`assigning non-pointer to typed pointer` and the like)
rc=0; "$CC" < "$T/pv.cyr" > "$T/pv.chk" 2> "$T/pv.chk.err" || rc=$?
nw=$(grep -c '^warning\|^error' "$T/pv.chk.err" || true)
if [ "$rc" -eq 0 ] && [ "$nw" -eq 0 ]; then ok "P5: the step-word program compiles with no warning ($(grep -c 'assert_eq' "$T/pv.cyr") checks)"
else bad "P5: rc $rc, $nw diagnostic line(s): $(grep '^warning\|^error' "$T/pv.chk.err" | head -2 | tr '\n' '|')"; fi
legs pv PV "every source x kind step, P1 P2 P4 P5"

# P3: `n + p` on a 1-byte pointee is a plain add on every source — byte-identical to the same
# program with untyped pointers (a kind read as part of the step took 6.6.17's `n * step` imul path).
p3_gen() {   # <pointer annotation> <return annotation>
    printf 'var b: i64[2];\nvar G%s = 0;\nstruct H { p%s; }\nfn r()%s { return &b; }\nfn f(n, p%s): i64 { var q%s = &b; var h: H; h.p = &b; G = &b; return (n + p) + (n + q) + (n + G) + (n + h.p) + (n + r()); }\nsyscall(60, f(3, &b) - 5 * &b);\n' "$1" "$1" "$2" "$1" "$1"
}
p3_gen "" ": i64" > "$T/p3u.cyr"
p3_gen ": *u8" ": *u8" > "$T/p3t.cyr"
p3_gen ": *i8" ": *i8" > "$T/p3s.cyr"
rc=0
"$CC" < "$T/p3u.cyr" > "$T/p3u.bin" 2> /dev/null || rc=1
"$CC" < "$T/p3t.cyr" > "$T/p3t.bin" 2> /dev/null || rc=1
"$CC" < "$T/p3s.cyr" > "$T/p3s.bin" 2> /dev/null || rc=1
if [ "$rc" -ne 0 ]; then bad "P3: a variant did not compile"
elif cmp -s "$T/p3u.bin" "$T/p3t.bin" && cmp -s "$T/p3u.bin" "$T/p3s.bin"; then
    chmod +x "$T/p3t.bin"; got=0; timeout 10 "$T/p3t.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq 15 ]; then ok "P3: n + p on *u8 / *i8 (parameter, local, global, field, return) == untyped, bytes and value (15)"
    else bad "P3: exit $got, want 15"; fi
else bad "P3: n + p on a *u8 / *i8 differs from the untyped program (the kind took the imul path)"; fi

# P6: a `*T` global redeclared with another kind of the same step folds into one global (the kind
# is no shape: `_gv_ped` beside GVTYPE); a different step stays refused (P6c, anti-vacuous).
exits p6 3 "P6: var G: *u8 / var G: *i8 fold (G + 3 steps 1)" \
    'var buf: i64[2];\nvar G: *u8 = 0;\nvar G: *i8 = 0;\nfn f(): i64 { G = &buf; var a = G + 3; return a - &buf; }\nsyscall(60, f());\n'
exits p6b 12 "P6b: *u32 / *f32 / *i32 fold (step 4)" \
    'var buf: i64[2];\nvar G: *u32 = 0;\nvar G: *f32 = 0;\nvar G: *i32 = 0;\nfn f(): i64 { G = &buf; var a = G + 3; return a - &buf; }\nsyscall(60, f());\n'
exits p6d 24 "P6d: *f64 / *bool / *u64 fold (step 8)" \
    'var buf: i64[2];\nvar G: *f64 = 0;\nvar G: *bool = 0;\nvar G: *u64 = 0;\nfn f(): i64 { G = &buf; var a = G + 3; return a - &buf; }\nsyscall(60, f());\n'
refused p6c "global 'G' redeclared with a different type or size" "P6c: *u8 then *u16 stays refused" \
    'var buf: i64[2];\nvar G: *u8 = 0;\nvar G: *u16 = 0;\nsyscall(60, 0);\n'

# S0: an f64 / f32 / bool array records its kind in the descriptor, which the redeclaration fold
# reads through `_ek_legacy` — `f64[2]` / `f32[4]` / `bool[2]` (16 B each) fold as in 6.7.6; an
# integer element of the same size stays a different shape (S0c, S0d: anti-vacuous).
exits s0a 7 "S0a: f64[2] then f32[4] fold" 'var A: f64[2];\nvar A: f32[4];\nsyscall(60, 7);\n'
exits s0b 7 "S0b: bool[2] then f64[2] fold" 'var A: bool[2];\nvar A: f64[2];\nsyscall(60, 7);\n'
exits s0e 7 "S0e: f32[2] then bool[1] fold (8 B)" 'var A: f32[2];\nvar A: bool[1];\nsyscall(60, 7);\n'
refused s0c "global 'A' redeclared with a different type or size" "S0c: f64[2] then i64[2] stays refused" \
    'var A: f64[2];\nvar A: i64[2];\nsyscall(60, 7);\n'
refused s0d "global 'A' redeclared with a different type or size" "S0d: f32[4] then u32[4] stays refused" \
    'var A: f32[4];\nvar A: u32[4];\nsyscall(60, 7);\n'

# ── N0: an element-typed array records its exact N (C2-3b) ───────────────────────────────────
# N is no redeclaration shape: two declarations of one storage still fold, whatever their N.
exits n0a 9 "N0a: u8[5] then u8[6] fold (8 B), A[4] = 9 reads back" \
    'var A: u8[5];\nvar A: u8[6];\nfn f(): i64 { A[4] = 9; A[0] = 1; return A[4]; }\nsyscall(60, f());\n'
exits n0b 7 "N0b: i16[3] / i16[4] / i16[2] fold (8 B, signed), A[1] = -3 reads back" \
    'var A: i16[3];\nvar A: i16[4];\nvar A: i16[2];\nfn f(): i64 { A[1] = 0 - 3; return A[1] + 10; }\nsyscall(60, f());\n'
refused n0c "global 'A' redeclared with a different type or size" "N0c: u8[8] then u8[9] stays refused (8 B vs 16 B)" \
    'var A: u8[8];\nvar A: u8[9];\nsyscall(60, 7);\n'

# ── R / A: `p[i]` on a named `*T`, and f64 / f32 / bool elements (C2-4a) ─────────────────────
# A: the value file on every leg (x86 plain / IR=1 / IR=3 / DCE=1, aarch64, cx, PE), with no
# warning (a float element's value has no integer width to narrow from; an f32 into an f32 element
# is not re-rounded), and silent under --syntax-only.
PSV=tests/tcyr/crossos/pointer_subscript_values.tcyr
[ -f "$PSV" ] || { echo "FAIL: $G: $PSV missing"; exit 1; }
cp "$PSV" "$T/psv.cyr"
rc=0; "$CC" < "$T/psv.cyr" > "$T/psv.chk" 2> "$T/psv.chk.err" || rc=$?
nw=$(grep -c '^warning\|^error' "$T/psv.chk.err" || true)
if [ "$rc" -eq 0 ] && [ "$nw" -eq 0 ]; then ok "A0: the value file compiles with no warning ($(grep -c 'assert' "$T/psv.cyr") asserts)"
else bad "A0: rc $rc, $nw diagnostic line(s): $(grep '^warning\|^error' "$T/psv.chk.err" | head -2 | tr '\n' '|')"; fi
rc=0; "$CC" --syntax-only < "$T/psv.cyr" > /dev/null 2> "$T/psv.so.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error\|^warning' "$T/psv.so.err"; then ok "A0s: --syntax-only (cyrius lint) reports nothing"
else bad "A0s: --syntax-only rc $rc: $(grep '^error\|^warning' "$T/psv.so.err" | head -1)"; fi
legs psv A "every kind on every named base: read, =, OP=, the for step" full

# AS: an `async fn` (CYRIUS_ASYNC=1) — a `p: *T` parameter, a `*T` local and f64 / f32 arrays in its
# heap frame, read and written across two awaits.
printf '#!/bin/sh\nCYRIUS_ASYNC=1 exec "%s" "$@"\n' "$CC" > "$T/acc"; chmod +x "$T/acc"
CC_SV=$CC; CC="$T/acc"
exits as1 0 "AS1: p[i], a[i] on f64[3] / f32[2] in a suspending async fn, across awaits" \
    'include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/async.cyr"\nvar B: i64[4];\nfn nopark(): i64 { return 0; }\nasync fn steps(q: *i16): i64 {\n    var p: *u8 = &B;\n    var a: f64[3];\n    var c: f32[2];\n    a[1] = 1.5;\n    c[1] = 2.5;\n    p[1] = 250;\n    q[2] = 0 - 3;\n    var s1 = await nopark();\n    p[1] += 10;\n    a[1] *= 2.0;\n    q[2] -= 4;\n    var s2 = await nopark();\n    if (a[1] != 3.0) { return 1; }\n    if (load32(&c + 4) != 0x40200000) { return 2; }\n    return p[1] * 100 + q[2] + 100;\n}\nfn main(): i64 {\n    alloc_init();\n    var C = steps(&B + 16);\n    var r1 = future_force(C);\n    var r2 = future_force(C);\n    var r3 = future_force(C);\n    if (r3 != 493) { syscall(60, 10 + r3 % 100); }\n    if (load16(&B + 20) != 65529) { syscall(60, 3); }\n    syscall(60, 0);\n    return 0;\n}\nvar e = main();\n'
CC=$CC_SV

# R1-R4: every name whose element no subscript loads is refused BY NAME at the `[`, once, the
# brackets consumed (no cascade). The texts share "a subscript takes an integer, f64, f32 or bool
# element" (R1-R3).
EL="a subscript takes an integer, f64, f32 or bool element"
PT='struct Pt { x; y; }\nvar B: i64[8];\n'
R1="cannot subscript 'p': $EL - step with p + i to an element of struct 'Pt'"
refused r1a "$R1" "R1a: p[1] on a \`p: *Pt\` parameter" "${PT}fn f(p: *Pt): i64 { return p[1]; }\nsyscall(60, f(&B));\n"
refused r1b "$R1" "R1b: p[1] = 5 on a \`*Pt\` local" "${PT}fn f(): i64 { var p: *Pt = &B; p[1] = 5; return 0; }\nsyscall(60, f());\n"
refused r1c "cannot subscript 'G': $EL - step with p + i to an element of struct 'Pt'" "R1c: G[0] += 1 on a \`*Pt\` global" "${PT}var G: *Pt = 0;\nfn f(): i64 { G[0] += 1; return 0; }\nsyscall(60, f());\n"
refused r1d "$R1" "R1d: p[0] on a captured \`*Pt\`" "include \"lib/alloc.cyr\"\n${PT}fn f(p: *Pt): i64 { var k = || p[0]; return 0; }\nalloc_init();\nsyscall(60, f(&B));\n"
refused r1e "$R1" "R1e: p[0] in a generic instance at T = Pt (once; the base's T is its i64)" "${PT}fn g<T>(p: *T): i64 { return p[0]; }\nfn f(): i64 { return g<Pt>(&B); }\nsyscall(60, f());\n"
refused r1f "cannot subscript 'p': $EL - step with p + i to an element of struct 'Str'" "R1f: a \`*Str\` (a struct)" "include \"lib/str.cyr\"\nfn f(p: *Str): i64 { return p[1]; }\nsyscall(60, 0);\n"
refused r1g "cannot subscript 'self': $EL - step with p + i to an element of struct 'Pt'" "R1g: \`self[0] = 1\` on an untyped impl self" "${PT}impl Pt { fn m(self): i64 { self[0] = 1; return 0; } }\nsyscall(60, 0);\n"
refused r1h "arithmetic on an untyped \`self\` is refused" "R1h: \`return self[0];\` keeps the 6.7.0 self refusal, once" "${PT}impl Pt { fn m(self): i64 { return self[0]; } }\nsyscall(60, 0);\n"
R2="cannot subscript 'p': $EL - its element is a pointer, string, enum or vector; load at p + i"
refused r2a "$R2" "R2a: a \`*cstring\` parameter" 'fn f(p: *cstring): i64 { return p[1]; }\nsyscall(60, 0);\n'
refused r2b "$R2" "R2b: a \`*Color\` (enum) local" 'enum Color { RED = 0; BLUE = 1; }\nvar B: i64[2];\nfn f(): i64 { var p: *Color = &B; return p[1]; }\nsyscall(60, f());\n'
refused r2c "$R2" "R2c: a \`**i64\` local" 'var B: i64[2];\nfn f(): i64 { var p: **i64 = &B; p[1] = 0; return 0; }\nsyscall(60, f());\n'
refused r2d "$R2" "R2d: a \`*f64v2\` local" 'fn f(): i64 { var b: i64[8]; var p: *f64v2 = &b; return p[1]; }\nsyscall(60, f());\n'
refused r2e "cannot subscript 'p': a u128 element does not fit one register" "R2e: a \`*u128\` parameter" 'fn f(p: *u128): i64 { return p[1]; }\nsyscall(60, 0);\n'
R3="cannot subscript 'a': $EL - its element is a struct, pointer, enum, string or vector; use &a + i * sizeof(T)"
refused r3a "$R3" "R3a: a \`Pt[2]\` local" "${PT}fn f(): i64 { var a: Pt[2]; return a[1]; }\nsyscall(60, f());\n"
refused r3b "$R3" "R3b: a \`Color[2]\` local" 'enum Color { RED = 0; BLUE = 1; }\nfn f(): i64 { var a: Color[2]; return a[1]; }\nsyscall(60, f());\n'
refused r3c "$R3" "R3c: a \`cstring[2]\` local" 'fn f(): i64 { var a: cstring[2]; a[0] = 0; return 0; }\nsyscall(60, f());\n'
refused r3d "$R3" "R3d: a \`*i64[2]\` local" 'fn f(): i64 { var a: *i64[2]; return a[1]; }\nsyscall(60, f());\n'
refused r3e "$R3" "R3e: an \`f64v2[2]\` global" 'var a: f64v2[2];\nfn f(): i64 { return a[1]; }\nsyscall(60, f());\n'
R4="it is not a typed array, a *T or a slice local"
refused r4a "cannot subscript 'x': $R4" "R4a: an untyped local" 'fn f(): i64 { var x = 5; return x[0]; }\nsyscall(60, f());\n'
refused r4b "cannot subscript 'x': $R4" "R4b: an untyped parameter" 'fn f(x): i64 { return x[0]; }\nsyscall(60, f(0));\n'
refused r4c "cannot subscript 'x': $R4" "R4c: an untyped global" 'var x = 5;\nfn f(): i64 { return x[0]; }\nsyscall(60, f());\n'
refused r4d "cannot subscript 'n': $R4" "R4d: a declared i64 local, written" 'fn f(): i64 { var n: i64 = 5; n[0] = 1; return 0; }\nsyscall(60, f());\n'
BA="a bare \`var a[N]\` states no element width"
refused r4e "cannot subscript 'b': $BA" "R4e: a bare local array" 'fn f(): i64 { var b[16]; b[1] = 5; return 0; }\nsyscall(60, f());\n'
refused r4f "cannot subscript 'b': $BA" "R4f: a \`stack var\` buffer" 'fn f(): i64 { stack var b[16]; return b[0]; }\nsyscall(60, f());\n'
refused r4g "cannot subscript 'b': $BA" "R4g: a bare global array" 'var b[4];\nfn f(): i64 { return b[1]; }\nsyscall(60, f());\n'
refused r4h "cannot subscript 'b': $BA" "R4h: a captured bare array" 'include "lib/alloc.cyr"\nfn f(): i64 { var b[16]; var k = || b[0]; return 0; }\nalloc_init();\nsyscall(60, f());\n'
exits r4i 9 "R4i: a slice element store compiles since C2-6a (it was refused by name here)" 'include "lib/slice.cyr"\nfn f(): i64 { var b: u8[4]; var s: [u8] = 0; slice_set(&s, &b, 4); s[1] = 9; return b[1]; }\nsyscall(60, f());\n'
refused r4j "cannot subscript 'q': $R4" "R4j: a pointer laundered through an untyped name (\`var q = p;\`) is a plain word" 'var B: i64[2];\nfn f(): i64 { var p: *i32 = &B; var q = p; return q[0]; }\nsyscall(60, f());\n'

# R9-R11: the element store's checks, as a field of T's.
BP='var B: i64[4];\nfn f(x): i64 {\n    var p: *bool = &B;\n    var a: bool[2];\n'
BE='\n    return 0;\n}\nsyscall(60, f(1));\n'
R9="is refused - its result is not a bool"
refused r9a "compound assignment to a bool element of 'p' $R9" "R9a: p[0] += 1 on a \`*bool\`" "${BP}    p[0] += 1;${BE}"
refused r9b "compound assignment to a bool element of 'a' $R9" "R9b: a[0] |= true on a \`bool[2]\`" "${BP}    a[0] |= true;${BE}"
refused r10a "cannot store a value that is not a bool into a bool element of 'p'" "R10a: p[0] = 5 on a \`*bool\`" "${BP}    p[0] = 5;${BE}"
refused r10b "cannot store a value that is not a bool into a bool element of 'a'" "R10b: a[1] = x (untyped) on a \`bool[2]\`" "${BP}    a[1] = x;${BE}"
exits r10c 0 "R10c: a boolean value into a bool element compiles (x > 0, true, !p[0], p[0] && a[1])" "${BP}    p[0] = x > 0;\n    a[1] = true;\n    a[0] = !p[0];\n    p[1] = p[0] && a[1];\n    if (p[1] == false) { return 1; }${BE}"
LP='enum R: stack { ROk(v); RErr(e); }\nfn mk(n) { return ROk(n); }\nvar B: i64[2];\n'
R11="a \`: stack\` enum returns two values"
refused r11a "$R11" "R11a: p[0] = mk(1); (the tag stored)" "${LP}fn f(): i64 { var p: *i64 = &B; p[0] = mk(1); return 0; }\nsyscall(60, f());\n"
refused r11b "$R11" "R11b: p[0] += mk(1);" "${LP}fn f(): i64 { var p: *i64 = &B; p[0] += mk(1); return 0; }\nsyscall(60, f());\n"

# W: the stores warn as a field's do — an integer constant into a float element (kept bits), an
# integer narrowed into a narrow element; an f32's compound with an f64 operand (as an f32 local's).
# warns <name> <fragment> <what> <body>: compiles, and stderr has the warning
warns() {
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"
    elif grep '^warning' "$T/$1.err" | grep -qF "$2"; then ok "$3"
    else bad "$3: no warning \"$2\": $(grep '^warning' "$T/$1.err" | head -1)"; fi
}
WI="an integer stored into an f64/f32 slot keeps its integer bits"
warns w1 "$WI" "W1: p[0] = 1 on a \`*f64\`" 'var B: i64[2];\nfn f(): i64 { var p: *f64 = &B; p[0] = 1; return 0; }\nsyscall(60, f());\n'
warns w2 "$WI" "W2: a[0] = 2 on an \`f32[2]\`" 'fn f(): i64 { var a: f32[2]; a[0] = 2; return 0; }\nsyscall(60, f());\n'
warns w3 "narrowing assignment" "W3: p[0] = w (an i32) on a \`*u8\`" 'var B: i64[2];\nfn f(): i64 { var w: i32 = 300; var p: *u8 = &B; p[0] = w; return p[0]; }\nsyscall(60, f());\n'
warns w4 "f32 arithmetic with a non-f32 right operand" "W4: p[0] *= 2.0 on a \`*f32\` (as \`x *= 2.0\` on an f32 local)" 'var B: i64[2];\nfn f(): i64 { var p: *f32 = &B; p[0] = 1.5; p[0] *= 2.0; return 0; }\nsyscall(60, f());\n'
# W5: a float element's store has no integer width to narrow to — an i64 element into an f32
# element warns nothing, as `x = a[1]` into an f32 local and `h.f = a[1]` into an f32 field do.
printf '%b' 'var B: i64[2];\nfn f(): i64 {\n    var a: i64[2];\n    a[1] = 3;\n    var p: *f32 = &B;\n    var c: f32[2];\n    var q: f32 = 0.5;\n    p[0] = a[1];\n    p[1] = q;\n    p[1] += q;\n    c[0] = a[1];\n    c[1] -= q;\n    return 0;\n}\nsyscall(60, f());\n' > "$T/w5.cyr"
rc=0; timeout 60 "$CC" < "$T/w5.cyr" > "$T/w5.bin" 2> "$T/w5.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning\|^error' "$T/w5.err"; then ok "W5: an i64 element into an f32 element / f32[2], and f32 OP=, warn nothing"
else bad "W5: rc $rc: $(grep '^warning\|^error' "$T/w5.err" | head -1)"; fi

# ── B / R5-R8 / X: `p[i]` on a `*T` field or a call returning `*T` (C2-4b) ────────────────────
# B: the value file on every leg, with no warning, silent under --syntax-only.
PSB=tests/tcyr/crossos/pointer_subscript_bases.tcyr
[ -f "$PSB" ] || { echo "FAIL: $G: $PSB missing"; exit 1; }
cp "$PSB" "$T/psb.cyr"
rc=0; "$CC" < "$T/psb.cyr" > "$T/psb.chk" 2> "$T/psb.chk.err" || rc=$?
nw=$(grep -c '^warning\|^error' "$T/psb.chk.err" || true)
if [ "$rc" -eq 0 ] && [ "$nw" -eq 0 ]; then ok "B0: the bases file compiles with no warning ($(grep -c 'assert' "$T/psb.cyr") asserts)"
else bad "B0: rc $rc, $nw diagnostic line(s): $(grep '^warning\|^error' "$T/psb.chk.err" | head -2 | tr '\n' '|')"; fi
rc=0; "$CC" --syntax-only < "$T/psb.cyr" > /dev/null 2> "$T/psb.so.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error\|^warning' "$T/psb.so.err"; then ok "B0s: --syntax-only (cyrius lint) reports nothing"
else bad "B0s: --syntax-only rc $rc: $(grep '^error\|^warning' "$T/psb.so.err" | head -1)"; fi
legs psb B "field, call, generic-call and method bases: read, =, OP=, the for step, T1, FWD" full

# AS2: a field base and a call base in a suspending `async fn` (CYRIUS_ASYNC=1), across two awaits.
CC_SV=$CC; CC="$T/acc"
exits as2 10 "AS2: h.p[i] and bp()[i] in a suspending async fn, across awaits" \
    'include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/async.cyr"\nstruct H { n; p: *i32; }\nvar B: i32[8];\nfn bp(): *i32 { return &B; }\nfn nopark(): i64 { return 0; }\nasync fn st(): i64 {\n    var h: H;\n    h.p = &B;\n    h.p[1] = 4;\n    var s1 = await nopark();\n    bp()[2] = 6;\n    h.p[1] += bp()[2];\n    var s2 = await nopark();\n    return h.p[1];\n}\nfn main(): i64 {\n    alloc_init();\n    var C = st();\n    var r1 = future_force(C);\n    var r2 = future_force(C);\n    var r3 = future_force(C);\n    syscall(60, r3);\n    return 0;\n}\nvar e = main();\n'
CC=$CC_SV

# R5 / R6: a field that is no `*T`, a call that returns none — by name, once, the statement parsed on.
# R5e: a call result's field whose call left a `*i32` ARGUMENT's scale behind (`mk(q).n`): the base
# is judged by the field's declaration, not by that scale.
HH='struct Pt { x; y; }\nstruct H { n; p: *i32; q: *Pt; pp: **i64; }\nvar B: i64[8];\n'
R5="cannot subscript field 'n': it is not a *T field"
refused r5a "$R5" "R5a: h.n[1] read (an i64 field)" "${HH}fn f(): i64 { var h: H; return h.n[1]; }\nsyscall(60, f());\n"
refused r5b "$R5" "R5b: h.n[1] = 3" "${HH}fn f(): i64 { var h: H; h.n[1] = 3; return 0; }\nsyscall(60, f());\n"
refused r5c "$R5" "R5c: h.n[1] += 3" "${HH}fn f(): i64 { var h: H; h.n[1] += 3; return 0; }\nsyscall(60, f());\n"
refused r5d "$R5" "R5d: the for step h.n[i] = 1" "${HH}fn f(): i64 { var h: H; for (var i = 0; i < 2; h.n[i] = 1) { i = i + 1; } return 0; }\nsyscall(60, f());\n"
refused r5e "$R5" "R5e: mk(q).n[0] with a \`*i32\` argument (its scale is no base)" "${HH}fn mk(q: *i32): H { var h: H; h.n = 1; h.p = q; return h; }\nfn f(): i64 { var q: *i32 = &B; return mk(q).n[0]; }\nsyscall(60, f());\n"
refused r5f "$R5" "R5f: mk(q).n[0] = 1 as a statement" "${HH}fn mk(q: *i32): H { var h: H; h.n = 1; h.p = q; return h; }\nfn f(): i64 { var q: *i32 = &B; mk(q).n[0] = 1; return 0; }\nsyscall(60, f());\n"
refused r5g "cannot subscript field 'ptr': it is not a *T field" "R5g: s.ptr[0] on a slice (its .ptr is a plain word)" 'include "lib/slice.cyr"\nfn f(): i64 { var b: u8[4]; var s: [u8] = 0; slice_set(&s, &b, 4); return s.ptr[0]; }\nsyscall(60, f());\n'
R6=": it does not return a *T"
refused r6a "cannot subscript the result of 'f'$R6" "R6a: f()[1] read (an i64 return)" "${HH}fn f(): i64 { return 5; }\nfn g(): i64 { return f()[1]; }\nsyscall(60, g());\n"
refused r6b "cannot subscript the result of 'f'$R6" "R6b: f()[1] = 2 as a statement" "${HH}fn f(): i64 { return 5; }\nfn g(): i64 { f()[1] = 2; return 0; }\nsyscall(60, g());\n"
refused r6c "cannot subscript the result of 'load64'$R6" "R6c: load64(&B)[1] (a builtin)" "${HH}fn g(): i64 { return load64(&B)[1]; }\nsyscall(60, g());\n"
refused r6d "cannot subscript the result of 'fncall1'$R6" "R6d: fncall1(&f, 1)[0] (an indirect call)" "include \"lib/fnptr.cyr\"\n${HH}fn f(x): i64 { return &B; }\nfn g(): i64 { return fncall1(&f, 1)[0]; }\nsyscall(60, g());\n"
refused r6e "cannot subscript the result of 'callptr'$R6" "R6e: callptr(k, 1)[0]" "${HH}fn g(): i64 { var k = |x| x; return callptr(k, 1)[0]; }\nsyscall(60, g());\n"
refused r6f "cannot subscript the result of 'm'$R6" "R6f: h.m()[1] read (a method returning i64)" "${HH}impl H { fn m(self): i64 { return 0; } }\nfn g(): i64 { var h: H; return h.m()[1]; }\nsyscall(60, g());\n"
refused r6i "cannot subscript the result of 'm'$R6" "R6i: h.m()[0] = 1 as a statement" "${HH}impl H { fn m(self): i64 { return 0; } }\nfn g(): i64 { var h: H; h.m()[0] = 1; return 0; }\nsyscall(60, g());\n"
refused r6g "cannot subscript the result of 'f'$R6" "R6g: the for step f()[i] = 1" "${HH}fn f(): i64 { return 5; }\nfn g(): i64 { for (var i = 0; i < 2; f()[i] = 1) { i = i + 1; } return 0; }\nsyscall(60, g());\n"
refused r6h "cannot subscript the result of 'gv'$R6" "R6h: gv<i32>()[0] (a generic returning T)" "${HH}fn gv<T>(): T { return 0; }\nfn g(): i64 { return gv<i32>()[0]; }\nsyscall(60, g());\n"
EL2="a subscript takes an integer, f64, f32 or bool element"
refused r1i "cannot subscript field 'q': $EL2 - its element is struct 'Pt'" "R1i: h.q[1] on a \`q: *Pt\` field" "${HH}fn f(): i64 { var h: H; return h.q[1]; }\nsyscall(60, f());\n"
refused r1j "cannot subscript the result of 'gq': $EL2 - its element is struct 'Pt'" "R1j: gq()[1] = 2 on a \`*Pt\` return" "${HH}fn gq(): *Pt { return &B; }\nfn f(): i64 { gq()[1] = 2; return 0; }\nsyscall(60, f());\n"
refused r1k "cannot subscript the result of 'mq': $EL2 - its element is struct 'Pt'" "R1k: h.mq()[0] on a method returning \`*Pt\`" "${HH}impl H { fn mq(self): *Pt { return &B; } }\nfn f(): i64 { var h: H; return h.mq()[0]; }\nsyscall(60, f());\n"
refused r2f "cannot subscript field 'pp': $EL2 - its element is a pointer, string, enum or vector" "R2f: h.pp[1] on a \`**i64\` field" "${HH}fn f(): i64 { var h: H; return h.pp[1]; }\nsyscall(60, f());\n"
refused r2g "cannot subscript the result of 'gu': a u128 element does not fit one register" "R2g: gu()[1] on a \`*u128\` return" "${HH}fn gu(): *u128 { return &B; }\nfn f(): i64 { return gu()[1]; }\nsyscall(60, f());\n"

# R7 / R8: grammar — a second `[..]`, an address, a parenthesised or literal base.
R7="a subscript's result is an element, not an array - a second [..] is not supported"
refused r7a "$R7" "R7a: a[1][2] read on an i32[4]" "${HH}fn f(): i64 { var a: i32[4]; return a[1][2]; }\nsyscall(60, f());\n"
refused r7b "$R7" "R7b: a[1][2] = 5 (was \"expected '='\")" "${HH}fn f(): i64 { var a: i32[4]; a[1][2] = 5; return 0; }\nsyscall(60, f());\n"
refused r7c "$R7" "R7c: h.p[1][2] read" "${HH}fn f(): i64 { var h: H; h.p = &B; return h.p[1][2]; }\nsyscall(60, f());\n"
refused r7d "$R7" "R7d: gp()[1][2] = 5 as a statement" "${HH}fn gp(): *i32 { return &B; }\nfn f(): i64 { gp()[1][2] = 5; return 0; }\nsyscall(60, f());\n"
refused r7e "$R7" "R7e: p[0][1] += 1 on a named \`*i32\`" "${HH}fn f(): i64 { var p: *i32 = &B; p[0][1] += 1; return 0; }\nsyscall(60, f());\n"
refused r8a "&a[i] is not supported - write &a + i * sizeof(T) (or p + i)" "R8a: &a[2]" "${HH}fn f(): i64 { var a: i32[4]; var q = &a[2]; return q; }\nsyscall(60, f());\n"
R8="a subscript's base is a name, a *T field or a call returning *T - name the pointer first"
refused r8b "$R8" "R8b: (p + 1)[1]" "${HH}fn f(): i64 { var p: *i32 = &B; return (p + 1)[1]; }\nsyscall(60, f());\n"
refused r8c "$R8" "R8c: (p)[0]" "${HH}fn f(): i64 { var p: *i32 = &B; return (p)[0]; }\nsyscall(60, f());\n"
refused r8d "$R8" "R8d: \"abc\"[1]" "${HH}fn f(): i64 { return \"abc\"[1]; }\nsyscall(60, f());\n"
refused r8e "$R8" "R8e: 5[0]" "${HH}fn f(): i64 { return 5[0]; }\nsyscall(60, f());\n"

# X1: --syntax-only (cyrius lint's pre-pass) on bases another file declares — an untyped receiver,
# undefined fns — reads, stores, compounds and steps: rc 0, no error (the "undefined function"
# warnings are --syntax-only's own, as for `get();`). X2: the grammar refusals still report there.
printf '%b' 'fn f(h): i64 {\n    var a = h.p[1] + get()[2] + mk(3).p[0] + h.m()[1] + h.q.r[2];\n    h.p[1] = 5;\n    h.p[2] += 1;\n    h.q.r[2] = 1;\n    get()[2] = 7;\n    mk(4).p[1] = 3;\n    h.m()[0] = 1;\n    for (var i = 0; i < 2; get()[i] += 1) { i = i + 1; }\n    for (var i = 0; i < 2; h.p[i] += 1) { i = i + 1; }\n    for (var i = 0; i < 2; h.m()[i] = 1) { i = i + 1; }\n    return a;\n}\n' > "$T/x1.cyr"
rc=0; "$CC" --syntax-only < "$T/x1.cyr" > /dev/null 2> "$T/x1.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/x1.err"; then ok "X1: --syntax-only on field / call / method bases from another file: rc 0, no error"
else bad "X1: --syntax-only rc $rc: $(grep '^error' "$T/x1.err" | head -1)"; fi
so_refused() {   # <name> <fragment> <what> <body>: --syntax-only fails with exactly one error line holding it
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; "$CC" --syntax-only < "$T/$1.cyr" > /dev/null 2> "$T/$1.err" || rc=$?
    n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$3: rc 0 — want \"$2\""
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines, want 1"
    elif grep '^error' "$T/$1.err" | grep -qF "$2"; then ok "$3"
    else bad "$3: wrong refusal: $(grep '^error' "$T/$1.err" | head -1)"; fi
}
so_refused x2a "$R7" "X2a: --syntax-only still refuses get()[1][2]" 'fn f(): i64 { return get()[1][2]; }\n'
so_refused x2b "&a[i] is not supported" "X2b: --syntax-only still refuses &b[1]" 'fn f(): i64 { var b: i32[4]; var q = &b[1]; return q; }\n'

# ── D: `*p` at the element's width (C2-5) ─────────────────────────────────────────────────────
# D: the value file on every leg (x86 plain / IR=1 / IR=3 / DCE=1, aarch64, cx, PE), with no
# warning, silent under --syntax-only.
DEW=tests/tcyr/crossos/deref_element_width.tcyr
[ -f "$DEW" ] || { echo "FAIL: $G: $DEW missing"; exit 1; }
cp "$DEW" "$T/dew.cyr"
rc=0; "$CC" < "$T/dew.cyr" > "$T/dew.chk" 2> "$T/dew.chk.err" || rc=$?
nw=$(grep -c '^warning\|^error' "$T/dew.chk.err" || true)
if [ "$rc" -eq 0 ] && [ "$nw" -eq 0 ]; then ok "D0: the deref file compiles with no warning ($(grep -c 'assert' "$T/dew.cyr") asserts)"
else bad "D0: rc $rc, $nw diagnostic line(s): $(grep '^warning\|^error' "$T/dew.chk.err" | head -2 | tr '\n' '|')"; fi
rc=0; "$CC" --syntax-only < "$T/dew.cyr" > /dev/null 2> "$T/dew.so.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error\|^warning' "$T/dew.so.err"; then ok "D0s: --syntax-only (cyrius lint) reports nothing"
else bad "D0s: --syntax-only rc $rc: $(grep '^error\|^warning' "$T/dew.so.err" | head -1)"; fi
legs dew D "*p / *p = v / *p OP= v at the element: every narrow kind, operand and the word forms" full

# DR: the issue's repro VERBATIM (issues/2026-10-08-deref-store-through-narrow-typed-pointer-is-word-
# store.md) — it exited 14; the element-width rule makes it 0 — on every leg.
printf '%s\n' 'fn main(): i64 {' '    var b: i32[2];' '    b[0] = 1; b[1] = 7;' '    var q: *i32 = &b;' \
    '    *q = 5;                         # writes 8 bytes: b[1] becomes 0' '    var a: f32[2];' \
    '    store32(&a + 4, 0x40400000);    # a[1] = 3.0f' '    var p: *f32 = &a;' \
    '    *p = 1.5;                       # 1.5'"'"'s f64 bits as a word: a[0] = 0, a[1] = 0x3FF80000' \
    '    var e = 0;' '    if (b[0] != 5) { e = e | 1; }' '    if (b[1] != 7) { e = e | 2; }' \
    '    if (load32(&a) != 0x3FC00000) { e = e | 4; }      # f32 1.5' \
    '    if (load32(&a + 4) != 0x40400000) { e = e | 8; }  # a[1] untouched' '    return e;' '}' \
    'syscall(60, main());' > "$T/dr.cyr"
legs dr DR "the issue's repro exits 0 (it exited 14)"

# AS3: `*p` through a `p: *i16` parameter and a `*u8` local in a suspending `async fn`, across awaits.
CC_SV=$CC; CC="$T/acc"
exits as3 0 "AS3: *p, *p = v, *p OP= v on a *i16 parameter and a *u8 local in a suspending async fn" \
    'include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/async.cyr"\nvar B: i64[2];\nfn nopark(): i64 { return 0; }\nasync fn st(q: *i16): i64 {\n    var p: *u8 = &B + 1;\n    *p = 250;\n    *q = 0 - 3;\n    var s1 = await nopark();\n    *p += 10;\n    *q -= 4;\n    var s2 = await nopark();\n    return *p * 100 + *q + 100;\n}\nfn main(): i64 {\n    alloc_init();\n    store64(&B, 0x7777777777777777);\n    var C = st(&B + 4);\n    var r1 = future_force(C);\n    var r2 = future_force(C);\n    var r3 = future_force(C);\n    if (r3 != 493) { syscall(60, 10 + r3 % 100); }\n    if (load64(&B) != 0x7777FFF977770477) { syscall(60, 3); }\n    syscall(60, 0);\n    return 0;\n}\nvar e = main();\n'
CC=$CC_SV

# DW: the stores warn as `p[0] = v` does (the approved rule): an integer constant into a `*f32`, a
# wider integer into a `*u8`, an f32 compound with an f64 operand; `*p * 2.0` through a `*f64` is
# still the untyped word (the documented rule — p[0] is the typed spelling); DW5 an i64 into a
# `*f32` and an f32 compound warn nothing.
warns dw1 "$WI" "DW1: *p = 1 through a \`*f32\`" 'var B: i64[2];\nfn f(): i64 { var p: *f32 = &B; *p = 1; return 0; }\nsyscall(60, f());\n'
warns dw2 "narrowing assignment" "DW2: *p = w (an i32) through a \`*u8\`" 'var B: i64[2];\nfn f(): i64 { var w: i32 = 300; var p: *u8 = &B; *p = w; return *p; }\nsyscall(60, f());\n'
warns dw3 "f32 arithmetic with a non-f32 right operand" "DW3: *p *= 2.0 through a \`*f32\` (as \`x *= 2.0\` on an f32 local)" 'var B: i64[2];\nfn f(): i64 { var p: *f32 = &B; *p = 1.5; *p *= 2.0; return 0; }\nsyscall(60, f());\n'
warns dw4 "integer arithmetic with an f64 right operand" "DW4: *p * 2.0 through a \`*f64\` stays the untyped word" 'var B: i64[2];\nfn f(): i64 { var p: *f64 = &B; var x = *p * 2.0; return x; }\nsyscall(60, f());\n'
printf '%b' 'var B: i64[2];\nfn f(): i64 {\n    var a: i64[2];\n    a[1] = 3;\n    var p: *f32 = &B;\n    var q: f32 = 0.5;\n    *p = a[1];\n    *(p + 1) = q;\n    *(p + 1) += q;\n    return 0;\n}\nsyscall(60, f());\n' > "$T/dw5.cyr"
rc=0; timeout 60 "$CC" < "$T/dw5.cyr" > "$T/dw5.bin" 2> "$T/dw5.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning\|^error' "$T/dw5.err"; then ok "DW5: an i64 element into a \`*f32\`, and an f32 OP=, warn nothing"
else bad "DW5: rc $rc: $(grep '^warning\|^error' "$T/dw5.err" | head -1)"; fi

# DM: a narrow `*p` in a multi-value assignment keeps the deref's own refusal, once.
refused dm "\`*p\` is not one" "DM: *p, x = f2(); through a \`*i32\`" 'fn f2(): i64 { return (3, 4); }\nvar B: i64[2];\nfn f(): i64 { var p: *i32 = &B; var x = 0; *p, x = f2(); return x; }\nsyscall(60, f());\n'

# DX: `*(1 + p)` through a ONE-byte `*T` is the element (the C2 review; it was a WORD). 6.7.9: `n + p`
# keeps p's word, as `p + n` does, so the dereference reads it there. The value file's D6b / D6c hold
# every base and form.
exits dx 3 "DX: *(1 + p) = v through a \`*u8\` stores one byte" \
    'var B: i64[2];\nfn f(): i64 { store64(&B, 0x1111111111111111); var p: *u8 = &B; *(1 + p) = 0; if (load64(&B) == 0x1111111111110011) { return 3; } if (load64(&B) == 0x11) { return 2; } return 1; }\nsyscall(60, f());\n'
exits dxr 3 "DXr: *(0 + q) through a \`*i8\` reads -1 (sign-extended)" \
    'var B: i64[2];\nfn f(): i64 { store64(&B, 0x11111111111111FF); var q: *i8 = &B; if (*(0 + q) == 0 - 1) { return 3; } return 1; }\nsyscall(60, f());\n'
# DXc: `n + p8` IS that `*u8` (6.7.9; the user's decision 1(b), 2026-10-11; issues/2026-10-10-int-plus-
# byte-pointer-drops-step.md). It wrote the integer's word back, 0: `(1 + p8) - q32` built a byte
# difference where `(p8 + 1) - q32` is refused, and `var r: *u8 = 1 + p8;` warned where `p8 + 1` is
# silent. Each one-byte source (a local, a parameter, a global, a field, a call, a capture), `*i8`
# too, both diagnostics; DXc4 the control; DXn a narrow SCALAR (step 1, no `*T`) stays an integer.
DXH='var B: i64[2];\nvar G8: *u8 = 0;\nstruct H8 { n; b: *u8; }\nfn mk8(): *u8 { return &B; }\n'
for src in p8 a8 G8 h.b 'mk8()' si8; do
    refused "dxc1_$(printf '%s' "$src" | tr -dc 'a-z0-9')" "pointer difference of pointers with different element sizes" \
        "DXc1: (1 + $src) - q32 is the different-sizes error, as ($src + 1) - q32 is (it was a byte difference)" \
        "${DXH}fn f(a8: *u8): i64 { var p8: *u8 = &B; var si8: *i8 = &B; var h: H8; h.b = &B; G8 = &B; var q32: *u32 = &B; return (1 + $src) - q32; }\nsyscall(60, f(&B));\n"
done
printf '%b' "${DXH}fn f(a8: *u8, ai8: *i8): i64 {\n    var p8: *u8 = &B;\n    var h: H8;\n    h.b = &B;\n    G8 = &B;\n    var r1: *u8 = 1 + p8;\n    var r2: *u8 = 2 + a8;\n    var r3: *u8 = 3 + G8;\n    var r4: *u8 = 4 + h.b;\n    var r5: *u8 = 5 + mk8();\n    var r6: *i8 = 6 + ai8;\n    var r7: *u8 = 7 + (1 + p8);\n    G8 = 1 + p8;\n    h.b = 2 + p8;\n    return *r1;\n}\nsyscall(60, f(&B, &B));\n" > "$T/dxc2.cyr"
rc=0; timeout 60 "$CC" < "$T/dxc2.cyr" > "$T/dxc2.bin" 2> "$T/dxc2.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning\|^error' "$T/dxc2.err"; then ok "DXc2: n + p from each one-byte source into a *u8 / *i8 declaration or global warns nothing"
else bad "DXc2: rc $rc: $(grep '^warning\|^error' "$T/dxc2.err" | head -2 | tr '\n' '|')"; fi
printf '%b' 'include "lib/alloc.cyr"\nvar B: i64[2];\nfn f(): i64 {\n    alloc_init();\n    var c = 1;\n    var p8: *u8 = &B;\n    var q: *u8 = if (c > 0) { 1 + p8 } else { p8 };\n    var g = |k| { var z: *u8 = k + p8; return z; };\n    return *q;\n}\nsyscall(60, f());\n' > "$T/dxc3.cyr"
rc=0; timeout 60 "$CC" < "$T/dxc3.cyr" > "$T/dxc3.bin" 2> "$T/dxc3.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning\|^error' "$T/dxc3.err"; then ok "DXc3: an if-expression of 1 + p8 and p8, and k + p8 on a capture, into a *u8 warn nothing"
else bad "DXc3: rc $rc: $(grep '^warning\|^error' "$T/dxc3.err" | head -2 | tr '\n' '|')"; fi
refused dxc4 "pointer difference of pointers with different element sizes" "DXc4: p8 + 1 - q32 is still the different-sizes error" \
    'var B: i64[2];\nfn f(): i64 { var p8: *u8 = &B; var q32: *u32 = &B; return p8 + 1 - q32; }\nsyscall(60, f());\n'
exits dxc5 1 "DXc5: (1 + p8) - p8 and (1 + i8) - p8 stay legal (one element size): an element count" \
    'var B: i64[2];\nfn f(): i64 { var p8: *u8 = &B; var i8: *i8 = &B; return (1 + p8) - p8 + ((1 + i8) - p8) - 1; }\nsyscall(60, f());\n'
exits dxn 6 "DXn: (1 + w) - q32 with w: u8 (a narrow scalar, no *T) is still n - p" \
    'var B: i64[2];\nfn f(): i64 { var w: u8 = 5; var q32: *u32 = &B; var qa: i64 = q32; return (1 + w) - q32 + qa; }\nsyscall(60, f());\n'
# DXs: 6.7.11 — decision 1(b) EXTENDED TO A ONE-BYTE STRUCT POINTER (the user's decision, 2026-10-13: "(a)
# Yes, extend 1(b) in `_add_word`"; issues/2026-10-12-pointer-into-small-byvalue-param-untyped-edges.md):
# `n + pb` with `pb: *B1` is that pointer, as `n + p8` is. A one-byte struct's word carries no element
# kind, so `_add_word` wrote no step: `(1 + pb) - q32` was a byte difference (exit 1, no diagnostic) and
# `var r: *B1 = 1 + pb;` warned. DXs1 each `*B1` source (a local, a parameter, a global, a field, a call)
# and an i64 local on the left refused as DXc1 is; DXs2 the control `(pb + 1) - q32`; DXs3 the
# declaration and assignment silent; DXs4 one element size stays an element count; DXs5 an if-expression
# of `py` / `&s` keeps its merged word (no step): the `*B7` declaration still warns and `(if ..) - q32`
# stays a plain subtraction (the argument side is small_struct_pointer_arg.tcyr's).
DXS='var B: i64[2];\nstruct B1 { a: u8; }\nstruct B7 { a: u32; b: u16; c: u8; }\nvar GB: *B1 = 0;\nstruct HB { n; pb: *B1; }\nfn mkb(): *B1 { return &B; }\n'
for src in pb ab GB h.pb 'mkb()'; do
    refused "dxs1_$(printf '%s' "$src" | tr -dc 'a-z0-9')" "pointer difference of pointers with different element sizes" \
        "DXs1: (1 + $src) - q32 with a *B1 is the different-sizes error (it was a byte difference)" \
        "${DXS}fn f(ab: *B1): i64 { var pb: *B1 = &B; var h: HB; h.pb = &B; GB = &B; var q32: *u32 = &B; return (1 + $src) - q32; }\nsyscall(60, f(&B));\n"
done
refused dxs1m "pointer difference of pointers with different element sizes" "DXs1m: (m + pb) - q32 with m an i64 local" \
    "${DXS}fn f(): i64 { var pb: *B1 = &B; var m = 1; var q32: *u32 = &B; return (m + pb) - q32; }\nsyscall(60, f());\n"
refused dxs2 "pointer difference of pointers with different element sizes" "DXs2: (pb + 1) - q32 is still the different-sizes error" \
    "${DXS}fn f(): i64 { var pb: *B1 = &B; var q32: *u32 = &B; return (pb + 1) - q32; }\nsyscall(60, f());\n"
printf '%b' "${DXS}fn f(): i64 {\n    var pb: *B1 = &B;\n    var m = 3;\n    var r: *B1 = 1 + pb;\n    var g: *B1 = pb;\n    g = m + pb;\n    GB = 2 + pb;\n    return 0;\n}\nsyscall(60, f());\n" > "$T/dxs3.cyr"
rc=0; timeout 60 "$CC" < "$T/dxs3.cyr" > "$T/dxs3.bin" 2> "$T/dxs3.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning\|^error' "$T/dxs3.err"; then ok "DXs3: 1 + pb, m + pb, 2 + pb into a *B1 declaration, local and global warn nothing"
else bad "DXs3: rc $rc: $(grep '^warning\|^error' "$T/dxs3.err" | head -2 | tr '\n' '|')"; fi
exits dxs4 1 "DXs4: (1 + pb) - pb stays legal (one element size): an element count" \
    "${DXS}fn f(): i64 { var pb: *B1 = &B; return (1 + pb) - pb; }\nsyscall(60, f());\n"
warns dxs5 "assigning non-pointer to typed pointer" "DXs5: var r: *B7 = if (c == 1) { py } else { &s }; still warns (its merged word is no step)" \
    "${DXS}fn f(c): i64 { var s: B7; var py: *B7 = &s; var r: *B7 = if (c == 1) { py } else { &s }; return 0; }\nsyscall(60, f(1));\n"
exits dxs5b 0 "DXs5b: (if (c == 1) { py } else { &s }) - q32 stays a plain subtraction" \
    "${DXS}fn f(c): i64 { var s: B7; var py: *B7 = &B; var q32: *u32 = &B; var d = (if (c == 1) { py } else { &s }) - q32; return d * 0; }\nsyscall(60, f(1));\n"
# DXR: the issue's repro VERBATIM: exactly its three differences refused (lines 9, 10, 11 — d2 was
# silent), and no warning at r (line 8).
DXRP=docs/development/issues/repros/2026-10-10-int-plus-byte-pointer-drops-step.cyr
[ -f "$DXRP" ] || { echo "FAIL: $G: $DXRP missing"; exit 1; }
rc=0; timeout 60 "$CC" < "$DXRP" > "$T/dxr_rep.bin" 2> "$T/dxr_rep.err" || rc=$?
dl=$(grep '^error' "$T/dxr_rep.err" | grep 'pointer difference of pointers with different element sizes' | sed 's/^error:<source>:\([0-9]*\):.*/\1/' | tr '\n' ' ')
if [ "$rc" -ne 0 ] && [ "$dl" = "9 10 11 " ] && [ "$(grep -c '^error' "$T/dxr_rep.err")" -eq 3 ] && ! grep -q '^warning' "$T/dxr_rep.err"; then
    ok "DXR: the issue's repro: d1, d2 and d3 refused, r silent"
else bad "DXR: rc $rc, refused lines '$dl': $(grep '^warning\|^error' "$T/dxr_rep.err" | head -4 | tr '\n' '|')"; fi

# ── PL: a pointer's step dies with the operator that consumed it (6.7.9) ──────────────────────
# PL0: the value file (its op_rows_* section holds the issue's table) compiles with only the five
# `#inline ignored` notes it has always had, and --syntax-only reports no error; PL: it on every leg.
TPS=tests/tcyr/crossos/typed_pointer_step.tcyr
[ -f "$TPS" ] || { echo "FAIL: $G: $TPS missing"; exit 1; }
cp "$TPS" "$T/tps.cyr"
rc=0; "$CC" < "$T/tps.cyr" > "$T/tps.chk" 2> "$T/tps.chk.err" || rc=$?
nw=$(grep '^warning\|^error' "$T/tps.chk.err" | grep -vc '#inline ignored: pointer (\*T) parameter' || true)
if [ "$rc" -eq 0 ] && [ "$nw" -eq 0 ]; then ok "PL0: the step file compiles, no new diagnostic ($(grep -c 'assert_eq' "$T/tps.cyr") asserts)"
else bad "PL0: rc $rc, $nw diagnostic line(s): $(grep '^warning\|^error' "$T/tps.chk.err" | grep -v '#inline ignored' | head -2 | tr '\n' '|')"; fi
rc=0; "$CC" --syntax-only < "$T/tps.cyr" > /dev/null 2> "$T/tps.so.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/tps.so.err"; then ok "PL0s: --syntax-only (cyrius lint) reports no error"
else bad "PL0s: --syntax-only rc $rc: $(grep '^error' "$T/tps.so.err" | head -1)"; fi
legs tps PL "every operator that consumes a pointer leaves no step, at *i16 / *i32 / *i64 / *Pt; the controls step; a one-byte n + p keeps its values" full
# PLR: the issue's repro VERBATIM (issues/2026-10-10-pointer-step-leaks-through-operators.md; it exited
# 255, every row wrong) on every leg.
PLRP=docs/development/issues/repros/2026-10-10-pointer-step-leaks-through-operators.cyr
[ -f "$PLRP" ] || { echo "FAIL: $G: $PLRP missing"; exit 1; }
cp "$PLRP" "$T/plr.cyr"
legs plr PLR "the issue's repro exits 0 (it exited 255)"
# PLW: what such a value is told when it goes into a `*T`: a plain integer, so `0 | q`, `-q` and an
# untyped field of a call warn as `q | 0` and `h.n` always did; PLWc: pointer arithmetic does not.
PLH='struct Hn { n; m; }\nfn hn(q): Hn { var h: Hn; h.n = 0; h.m = 0; return h; }\nvar B: i64[8];\n'
warns plw1 "assigning non-pointer to typed pointer" "PLW1: var r: *i32 = 0 | q; warns as q | 0 does" \
    "${PLH}fn f(): i64 { var q: *i32 = &B; var r: *i32 = 0 | q; return 0; }\nsyscall(60, f());\n"
warns plw2 "assigning non-pointer to typed pointer" "PLW2: var r: *i32 = -q; warns" \
    "${PLH}fn f(): i64 { var q: *i32 = &B; var r: *i32 = -q; return 0; }\nsyscall(60, f());\n"
warns plw3 "assigning non-pointer to typed pointer" "PLW3: var r: *i32 = hn(q).n; warns as h.n does" \
    "${PLH}fn f(): i64 { var q: *i32 = &B; var r: *i32 = hn(q).n; return 0; }\nsyscall(60, f());\n"
printf '%b' "${PLH}fn f(): i64 {\n    var q: *i32 = &B;\n    var x = 0;\n    var k = 1;\n    var a: *i32 = q + (x == q);\n    var b: *i32 = (q);\n    var c: *i32 = q - (k * q);\n    var d: *i32 = (x == q) + q;\n    return 0;\n}\nsyscall(60, f());\n" > "$T/plwc.cyr"
rc=0; timeout 60 "$CC" < "$T/plwc.cyr" > "$T/plwc.bin" 2> "$T/plwc.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning\|^error' "$T/plwc.err"; then ok "PLWc: q + (x == q), (q), q - (k * q), (x == q) + q into a *i32 warn nothing"
else bad "PLWc: rc $rc: $(grep '^warning\|^error' "$T/plwc.err" | head -1)"; fi
# PLWo: an operator fn that DECLARES `: *T` gives a pointer, as its free call does (6.7.9 review: bite
# 5 reset its step to 0 and warned): into a `*i32` `v + q`, `v * q`, `(v + q) + 1` warn nothing; PLW4
# its control, a plain-return operator fn's result, warns as `0 | q` does.
printf '%b' "struct Vp { x; }\nfn Vp_add(a, b): *i32 { return b; }\nfn Vp_mul(a, b): *i32 { return b; }\nvar B: i64[8];\nfn f(): i64 {\n    var q: *i32 = &B;\n    var v: Vp;\n    v.x = 0;\n    var a: *i32 = v + q;\n    var b: *i32 = v * q;\n    var c: *i32 = (v + q) + 1;\n    return 0;\n}\nsyscall(60, f());\n" > "$T/plwo.cyr"
rc=0; timeout 60 "$CC" < "$T/plwo.cyr" > "$T/plwo.bin" 2> "$T/plwo.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning\|^error' "$T/plwo.err"; then ok "PLWo: v + q, v * q, (v + q) + 1 with a : *i32 operator fn into a *i32 warn nothing"
else bad "PLWo: rc $rc: $(grep '^warning\|^error' "$T/plwo.err" | head -1)"; fi
warns plw4 "assigning non-pointer to typed pointer" "PLW4: var r: *i32 = v + q; with a plain-return operator fn warns" \
    'struct Vo { x; }\nfn Vo_add(a, b): i64 { return 10; }\nvar B: i64[8];\nfn f(): i64 { var q: *i32 = &B; var v: Vo; v.x = 0; var r: *i32 = v + q; return 0; }\nsyscall(60, f());\n'
# PLD: `p16 - (k * q32)` is `p - n` (an integer count), no longer the different-sizes difference it
# was refused as — k * q32 is no pointer; `p16 - q32` stays that error (DXc4's shape).
exits pld 3 "PLD: p16 - (k * q32) steps the integer by 2 (it was refused as a pointer difference)" \
    'var B: i64[8];\nfn f(): i64 { var p: *i16 = &B + 64; var q: *i32 = &B; var k = 1; var pa: i64 = p; var qa: i64 = q; var r = p - (k * q); if (pa - r == 2 * qa) { return 3; } return 1; }\nsyscall(60, f());\n'
refused pldc "pointer difference of pointers with different element sizes" "PLDc: p16 - q32 is still the different-sizes error" \
    'var B: i64[8];\nfn f(): i64 { var p: *i16 = &B; var q: *i32 = &B; return p - q; }\nsyscall(60, f());\n'

# ── AW: the value of `await f` is an untyped word (6.7.11) ────────────────────────────────────
# awx <name> <row> <want> <what> [a64]: $T/<name>.cyr under CYRIUS_ASYNC=1 on x86 (plain, CYRIUS_IR=3)
# and, with `a64`, aarch64 (qemu) — the coroutine rows are x86 only: aarch64 refuses a mid-body
# suspend by name ("x86-only so far").
awx() {
    for mode in plain IR3; do
        case $mode in
            plain) env_=""; lbl="${2}a: x86" ;;
            IR3) env_="CYRIUS_IR=3"; lbl="${2}b: x86, CYRIUS_IR=3" ;;
        esac
        rc=0; env CYRIUS_ASYNC=1 $env_ "$CC" < "$T/$1.cyr" > "$T/$1_$mode" 2> "$T/$1_$mode.err" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl — $4: rc $rc: $(grep '^error' "$T/$1_$mode.err" | head -1)"; continue; fi
        chmod +x "$T/$1_$mode"; got=0; timeout 10 "$T/$1_$mode" > /dev/null 2>&1 || got=$?
        if [ "$got" -eq "$3" ]; then ok "$lbl — $4: exit $got"; else bad "$lbl — $4: exit $got, want $3"; fi
    done
    [ "${5:-}" = a64 ] || return 0
    xcc
    if ! command -v qemu-aarch64 > /dev/null 2>&1; then
        echo "  SKIP ${2}c: aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1))
    elif [ ! -x "$T/cc_a64" ]; then bad "${2}c: src/main_aarch64.cyr did not build"
    elif CYRIUS_ASYNC=1 "$T/cc_a64" < "$T/$1.cyr" > "$T/$1.a64" 2> "$T/$1.a64.err" && [ -s "$T/$1.a64" ]; then
        chmod +x "$T/$1.a64"; got=0; (cd "$T" && timeout 60 qemu-aarch64 "./$1.a64" > /dev/null 2>&1) || got=$?
        if [ "$got" -eq "$3" ]; then ok "${2}c: aarch64 (qemu) — $4: exit $got"; else bad "${2}c: aarch64 (qemu) — $4: exit $got, want $3"; fi
    else bad "${2}c: aarch64 — $4: did not compile: $(grep '^error' "$T/$1.a64.err" | head -1)"; fi
}
# aw_src <annotation> <coroutine 0/1> <result expression>: `five()`'s Future in `f`, awaited outside a
# coroutine (main) or inside one (an async fn driven by future_force / future_pending)
aw_src() {
    printf 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/async.cyr"\nvar B: i64[2];\nasync fn five(): i64 { return 5; }\n'
    if [ "$2" -eq 1 ]; then
        printf 'async fn outer(): i64 {\n    var f%s = five();\n    var r = %s;\n    return r;\n}\n' "$1" "$3"
        printf 'fn main(): i64 {\n    alloc_init();\n    var C = outer();\n    var r = future_force(C);\n    while (future_pending(C)) { r = future_force(C); }\n    return r;\n}\nsyscall(60, main());\n'
    else
        printf 'fn main(): i64 {\n    alloc_init();\n    var f%s = five();\n    var r = %s;\n    return r;\n}\nsyscall(60, main());\n' "$1" "$3"
    fi
}
# AW1: the issue's repro VERBATIM (issues/2026-10-11-await-result-keeps-typed-pointer-step.md; it
# exited 9: the `1` scaled by sizeof(i32)).
cat > "$T/aw1.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/async.cyr"
async fn five(): i64 { return 5; }
fn main(): i64 {
    alloc_init();
    var f: *i32 = five();
    var r = (await f) + 1;
    return r;
}
syscall(60, main());
EOF
awx aw1 AW1 6 "the issue's repro: (await f) + 1 with f: *i32 is 6 (it was 9)" a64
aw_src ': *u8' 0 '(await f) + 1' > "$T/aw2.cyr"
awx aw2 AW2 6 "(await f) + 1 with f: *u8" a64
printf 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/async.cyr"\nvar B: i64[2];\nasync fn five(): i64 { return 5; }\nfn main(): i64 {\n    alloc_init();\n    var f: *u8 = five();\n    var q: *u32 = &B;\n    var qa: i64 = q;\n    return ((await f) + 1) - q + qa;\n}\nsyscall(60, main());\n' > "$T/aw2d.cyr"
awx aw2d AW2d 6 "((await f) + 1) - q32 with f: *u8 is n - p (it was refused as a different-sizes difference)" a64
aw_src ': *i32' 1 '(await f) + 1' > "$T/aw3.cyr"
awx aw3 AW3 6 "inside a coroutine, (await f) + 1 with f: *i32 (it was 9)"
aw_src ': *u8' 1 '(await f) + 1' > "$T/aw4.cyr"
awx aw4 AW4 6 "inside a coroutine, (await f) + 1 with f: *u8"
printf 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/async.cyr"\nvar B: i64[2];\nasync fn five(): i64 { return 5; }\nasync fn outer(): i64 {\n    var f: *u8 = five();\n    var q: *u32 = &B;\n    var qa: i64 = q;\n    return ((await f) + 1) - q + qa;\n}\nfn main(): i64 {\n    alloc_init();\n    var C = outer();\n    var r = future_force(C);\n    while (future_pending(C)) { r = future_force(C); }\n    return r;\n}\nsyscall(60, main());\n' > "$T/aw4d.cyr"
awx aw4d AW4d 6 "inside a coroutine, ((await f) + 1) - q32 with f: *u8 is n - p (it was refused)"
aw_src '' 0 '(await f) + 1' > "$T/awc1.cyr"
awx awc1 AWc1 6 "the untyped control var f = five(); (await f) + 1" a64
aw_src '' 1 '(await f) + 1' > "$T/awc2.cyr"
awx awc2 AWc2 6 "the untyped control inside a coroutine"
aw_src ': *i32' 0 'f + 1 - f' > "$T/awc3.cyr"
awx awc3 AWc3 1 "the control: the Future pointer f: *i32 itself still steps (f + 1 - f is 1)" a64

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a stale slice width is no slice (ST1-ST6); the step word carries the element kind with no change to any step, difference, merge, warning or fold (P1-P6, PV legs, S0); an array's exact N is no fold shape (N0); p[i] on a named *T and f64 / f32 / bool arrays read, store and combine at the element (A legs, AS), every other name refused by name (R1-R4), the element stores checked (R9-R11, W); p[i] on a *T field and a call returning *T (B legs), every other base refused by name (R5-R8, R1i-R2g), silent under --syntax-only for another file's bases (X); *p, *p = v and *p OP= v through a narrow *T at the element (D legs, DR, AS3, DW, DM), a one-byte n + p too (DX, DXr); a one-byte n + p is that *T, as p + n is (DXc1-5, DXn, DXR), a one-byte struct pointer's too (DXs1-5); a pointer's step dies with the operator that consumed it (PL legs, PLR, PLW, PLD), an operator fn's declared \`: *T\` keeps it (PL legs, PLWo); the value of \`await f\` is an untyped word, outside a coroutine and inside one (AW1-AW4d, AWc)"
