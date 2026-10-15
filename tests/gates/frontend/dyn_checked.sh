#!/bin/sh
# tests/gates/frontend/dyn_checked.sh — 6.7.8 (the checked `dyn` lane: bite D4, the keyword and the type;
# bite D5, forming; bite D6, the call; bite D7, the tools and the guide)
#
# CHECKED `dyn`. The user's decisions (2026-10-07): `o: dyn Show` is an ordinary 16-byte struct of two
# words {data, vtable} — ADR-002's one-word model holds; the compiler builds and verifies the vtable from
# `impl Show for T`; `o.show()` is an indirect call visible in the declared type; static dispatch stays
# the default. D4 lands the word and the type: `dyn` is reserved (token 173); `dyn X` is folded into ONE
# identifier token named `dyn X` before any prepass records a token index (`_dyn_fold`), registered as a
# struct of two 8-byte words (" data", " vtable" — no field access reaches them) before any user struct
# (`_dyn_prepass`), so every struct position takes it unchanged; every position the decisions leave open
# is refused by name, once per token. D5 FORMS one: at a destination typed `dyn Tr`, from a `*T` the
# compiler knows, a declared scalar or a literal (decision 1); the pair (Tr, T) checked once, at its first
# forming (decision 4: full signatures; decision 2: `self: T` of 8 B or less), its vtable a hidden global
# filled at every forming site (decision 6: a default's slot is T's instance). The rows that form (TY2,
# PF, the A legs' tests/tcyr/crossos/dyn_objects.tcyr) dispatch BY HAND — `o.show()` is bite D6. The P rows
# take a dyn value from a record's dyn field (heap memory, `get`), the way a program would keep one.
#
#   K   the reserved word: `var dyn`, `fn dyn`, a field `dyn`, a method `dyn` — "got reserved keyword 'dyn'"
#   TY  each position compiles (and runs, the two words intact): TY1 a local copy, TY2 a global after the
#       first statement (its annotation resolves — the value is the backstop's), TY3 a parameter, TY4 a
#       return threaded through three fns declared below the caller (the rough pair scan, H3), TY5 a
#       struct field, TY6 a trait member's signature
#   S   S2 `struct H { a; o: dyn Show; b; }` is 32 bytes, `b` intact; S3 a forward call to a fn declared
#       below taking `(o: dyn Show, k)` (pass 1's parameter scan, H4); S5 `#derive` refuses a dyn field
#   T   the type positions the decisions leave open: T1 `dyn X` where X is no trait; T2 `dyn A + B` (one
#       report, the parse in sync); T3 `dyn` with no trait name in a type position; T4 a type argument
#       (`Vec<dyn S>`, `Box<dyn S>`, `f<dyn S>(..)`, `Pr<i64, dyn S>`); T5 a pointer (`*dyn S`, `**`,
#       `*fn(dyn S)`); T6 an array / slice / tuple / multi-value element; T7 `dyn S<..>`; T8 `sizeof`;
#       T9 `impl .. for dyn S` / `impl dyn S`; T10 any other position (an expression, a name); T11 in a
#       generic (signature or body), `async`, `const` or `#naked` fn; T12 a dyn field in a generic struct,
#       in a union, or a union holding a struct that holds one; T13 a `const` (its own refusal)
#   U   uninitialised: U1 `var o: dyn S;` in a fn; U2 `var h: H;` where H holds a dyn (directly, through a
#       nested struct, through a generic instance), and `var hs: H[N]` — struct locals are not zeroed
#   V   opacity (decision 7): V1 a dyn name as a value; V2 `&o`; V3 a whole dyn field as a value; V4 a
#       dyn-returning call as a value (not a destination's whole expression; an un-annotated `var x =
#       (mk());`), and (review) a whole one into a destination that is not that dyn — an assignment to
#       an untyped / i64 / `*T` variable or global or a for step, a declaration annotated with no
#       struct, a top-level declaration after the first statement, a tail `return` from a fn that
#       does not return it (V4h-V4z); V5 `o.data` / `o.vtable` / `o.0` / `o.m` (FINDFIELD's own words); V6 a multi-value
#       destructure; V7 `return (a, b)` / `ret2` in a fn returning a dyn; V8 a struct literal writing a
#       dyn field's words; the backstops (`var o: dyn S = 5;`, `o = 5;`, `h.o = 5;`)
#   P   every destination of a dyn call result takes it whole — a var (annotated, inferred), an
#       assignment, a field store, an argument, a struct-literal element, a `return` (tail, wrapped,
#       non-tail in a `defer` fn) — bare and wrapped in parentheses; a method result too; the values
#       checked word by word (the over-refusal mutation M-T10 turns these RED)
#   H28 the fold across a newline and a comment; the caret of a diagnostic sits on `dyn`
#   X   `--syntax-only` (cyrius lint's pre-pass) reports no dyn refusal (they resolve types), and still
#       reports the reserved word
#   TT  the tools: `[embed]`'s reserved list holds `dyn` (embed_manifest_refusals.sh derives and checks
#       it); cyrius-lsp colours `dyn` a keyword (and `dynamo` not); the VS Code grammar lists it. (D7) the
#       source tools on a dyn sample, each built here from this tree: TT4 `cyrius header` (a dyn parameter
#       is one `cyr_val`), TT5 cyrfmt --check (the sample and crossos/dyn_objects.tcyr), TT6 `cyrius lint`
#       (the sample, and a file whose dyn's trait lives in a sibling), TT7 cyrdoc (the signatures
#       verbatim), TT8 api-surface (`f/2`), TT9 type-audit (`: dyn Area` is annotated); TT10 the guide's
#       "Trait objects: `dyn`" examples compile with no warning and exit the values their comments state
#   F   (D5) the forming refusals, each once, at the source: F1 an untyped name (a local, a parameter,
#       a slot a scalar local of another fn left stamped — M-F11's row — a for-in variable); F2 a bare
#       inline struct (a local, a global); F3 `&` of a pointer / a handle / a scalar / a dyn; F4 a
#       closure's captured name; F5 any other expression (`alloc(16)`, a string, `&h.p`, `n + 1`, an
#       enum constant, a call returning i64, `callptr`, a struct literal's element); F6 no `impl Tr for
#       T` (a literal, a struct); F7 `self: Q` by value, Q of 8 B or less (decision 2); F8 a signature
#       that differs (a parameter's type, the return type, generic-ness, a `...`, `self: Q`, a scalar's
#       `self: *T`, a pointer to a scalar) — one report per pair, at its first forming; (review) F8i /
#       F8j a slot method returning a `: stack` pair where the member declares one value (an impl
#       above and below the forming site); F9 a `#naked`
#       slot method (an `async` one cannot be written in an impl); F10 a slot method private to another
#       file (two files); F11 a FORM at top level into an assignment, a field, an argument
#   AL  (6.7.8 integration, the merge fix) the slot word's two 6.7.8 stamps held apart — C2's slice bit
#       62 (SLSLICE) and this lane's declared-scalar bit 63 (SLDSC), merged on one bit: a slice local is
#       no dyn source (AL1; AL2 in the slot a declared scalar of another fn held); a declared scalar is
#       no slice — `y += 1` / `y[0]` / `y.len` on a declared `y: i64` parameter in a slice's old slot
#       (AL3-AL5), `n += 1` / `n.len` on a `var n: i32` (AL6, AL7), a captured declared scalar
#       subscripted in a closure (AL8); a real slice in a dyn unit reads, writes and `OP=`s (AL9);
#       (review) the closure snapshot restores bit 63 WITH the names it validates (`_dsc_tn`): a
#       closure's own declared scalar in the slot of the enclosing fn's left that one's dyn naming the
#       closure local's type — the wrong impl (AL10: 3005 for 1005, exit 213) or refused as "no `impl
#       Num for cstring`" (AL11) — and an inline generic instance's the same (AL12, AL13), a closure
#       nested in a closure (AL14); each on x86, aarch64, cx and PE (the AX legs, after A)
#   K   (D5) a declaration-zone dyn in a `kernel;` build is named late, as every non-constant zone
#       initializer is; the program's own forming runs
#   PF  (D5) a parenthesised FORM source at every destination (a local, a zone and a post-statement
#       global, an assignment, a field, an argument, a return)
#   C   (D6) the call `o.m(..)` — an indirect call through slot k, the data word as `self`, the callee
#       the trait member's PROTOTYPE `dyn Show.m` — refused by name once, at the method's name, the call
#       consumed (a chain on it, a dyn argument of it): C1 a member the trait does not declare, C2 a
#       generic member (decision 3), C3 a member with no untyped `self` first, C4 a variadic one, C5 one
#       returning multiple values or a vector (a u128 return is refused too, but no impl can define one:
#       defensive), C6 a named argument, C7 the arity (`'dyn Show.add' expects 2 arguments`); C8 a call
#       through a dyn returning a dyn used as a value / untyped argument / destructured (V4, V6), one
#       returning i64 as a forming source (F5); C9 at top level a 16 B result into a global after the
#       first statement or in the declaration zone (the replay kept the data word alone: SIGSEGV) and a
#       24 B one and a chain, each refused once; C10 top-level and zone calls run (the micro-frame);
#       (review) C11 the call's value class is the trait member's — a `: Result` member's pair into one
#       name refused ("bind both"), a one-value member destructured refused (fn scope, assignment,
#       declaration zone), and `o.div(d)?` / a forwarding wrapper's `?` run (rc 139 before)
#   PD  (D6) every destination of a call through a dyn takes its dyn result whole (a var — annotated,
#       wrapped, inferred —, an assignment, a field, an argument, a struct-literal element, a return);
#       one returning `*P` FORMS (the forming classifier reads the prototype)
#   X4  (D6) `--syntax-only` with a dyn of a trait in a sibling file: the calls are silent, a grammar
#       error in their arguments is not; X5 a build names no prototype "undefined"
#   S   (D6) what a prototype is not: S4 `object;` — one unreferenced UND symbol `dyn Show.show`, and GNU
#       ld links the object; S5 `shared;` exports none; S6 no CYRIUS_SYMS line; S7 no unreachable-fn note
#   CG  (D6) what the call is: CG1 x86 `call [rbp+disp32]` (ff 95) per call; CG2 PE the same, and none of
#       ECALLPTR_PE's forced-alignment anchor (`push rbx; mov rbx, rsp; and rsp, -16`). The anchor count's
#       `grep -o` matches NOTHING when CG2 passes, so it is `|| true`'d: under `bash -eo pipefail` (GitHub's
#       shell semantics) the failing grep failed the pipeline and `set -e` ended the gate right after CG1,
#       exit 1 (6.7.10 review; `bash -eo pipefail` on this file: exit 0, and 1 with the `|| true` dropped)
#   IX  (6.7.8 integration) where the checked dyn meets C2's subscripts, `*p` width, slices and the
#       bounds-checked mode: IX1 tests/tcyr/crossos/dyn_subscripts.tcyr (a dyn method's `self.p[i]` read /
#       `=` / `+=` and its typed array local; a dyn call's `*T` result subscripted, `o.ptr()[i]`, and a
#       `*u8` one's `o.bp()[i]` / `*o.bp()` writing one byte; a `*u8` dereference in a dyn method; a slice
#       and a dyn formed from a declared `i32` in one fn) on x86 — mode off with no warning, CYRIUS_IR=3,
#       CYRIUS_DCE=1, the mode by CYRIUS_BOUNDS=1 (the rung `--bounds` sets) and by a `#bounds` line —
#       and on qemu-aarch64, cx and wine, mode off and on; IX2 under the mode, the violation of a dyn
#       method's `self.p[i]` (a negative index) and its typed array's `a[i]` (its N) in an INCLUDED file
#       (named, with the line) and of a dyn call's `*T` result `o.ptr()[m]` at the entry's line: exit 134
#       and exactly the one line, the in-range run (k=0) exit 11 and silent — x86, aarch64, cx, PE;
#       IX3 the mode on a program that forms dyns (dyn_objects.tcyr, every assertion, every target) and,
#       mode off, not a byte of the checker in either dyn file (unset == CYRIUS_BOUNDS=0)
#   A   the P program and (D6) the PD program on x86 (default, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu),
#       cx (cxvm), PE (wine, a private prefix); (D5, D6) tests/tcyr/crossos/dyn_objects.tcyr under
#       CYRIUS_IR=1 / 3 and CYRIUS_DCE=1, and on qemu-aarch64 and wine (cx runs it in
#       codegen/cx_crossos_rows_run.sh R9), and (CW) with no warning. A leg whose tool is missing is a SKIP
#       that names it (exit 77).
#
# MUTATION LEDGER (2026-10-10, bite D4; each a one-edit scratch COPY of src/, its compiler rebuilt from
# the mutated src, then this gate run with CYCC= the mutant; each measured RED, the real tree 115/115; the
# base compiler (the lane's HEAD before D4) is RED on 107 of them):
#   M-T1  the fold disabled (`_dyn_fold` returns at once)          -> 100 rows (every TY / S / T / U / V / P
#         row, H28a / H28b, X1, the A legs: `dyn Show` is two tokens)
#   M-T2  the fold placed AFTER `_tr_prepass`                       -> TY6 (the trait / impl records keep
#         pre-compaction token indices: an impl after a dyn-typed trait member is read one token off)
#   M-T3  no position rule (`_dyn_pos` accepts any predecessor)     -> T4a-e, T5a-c, T6b-e, T8a-b, T9a-b, T10a-d
#   M-T4  no `+ B` drop in the fold                                 -> T2 (a parse cascade)
#   M-T5  the prev-`<` arm gone                                     -> T4a, T4b, T4c, T4e (T4d is the `,` arm)
#   M-T6  `_dyn_rchk` gone from `_tup_rchk`                          -> V1a-l, V2a-b, V4a-g (BUILT)
#   M-T7  `PP_DDYN` gone                                            -> S5 (BUILT, every field after `o` lost)
#   M-T8  `_embed_reserved_list` without ` dyn` (cbt/manifest.cyr)   -> toolchain/embed_manifest_refusals.sh
#         axis 5 ("reserved names cbt accepts: dyn") and TT1
#   M-T9  `_tup_var` without `_dyn_var` (U1 / U2)                   -> U1, U2a, U2b, U2d (BUILT)
#   M-T10 V4's destination exemption gone (every dyn result refused) -> TY6, P1-P21, A x86 IR3 / DCE / aarch64 /
#         cx / PE (the over-refusal is caught)
#   M-T11 no `_dyn_ret_arm` (`return pass(o);` in a dyn fn unarmed)  -> P1-P21 and the A legs
#   M-T12 a bare `dyn` reported but not turned into an identifier  -> T3c (a second error: the return type's
#         ERR_EXPECT names the reserved word)
#   M-T13 a dyn type in a value position not turned into `0`         -> T10a (a second "undefined variable")
#   M-T14 `_dyn_held` not recursive (a direct dyn field only)       -> U2b, U2d (BUILT)
#   M-T15 V3 (`_tup_fld_rchk`'s dyn arm) gone                        -> V3a-c (BUILT)
#   M-T16 V8 (`_spi_nested`'s dyn refusal) gone                      -> V8 (BUILT: the dyn's words from 2, 3)
#   M-T17 the async by-value struct-parameter refusal not skipping a dyn -> T11c (a second error, advising
#         `o: *dyn Show`, which is refused)
#   M-T18 the union arm of `_dyn_field_chk` gone                     -> T12b, T12c (BUILT)
#   M-T19 the destination exemption reaching through `(` (`_sc_want` before the call) -> V4d (BUILT: an
#         un-annotated `var x = (pass(o));` kept the dyn's DATA word as an i64)
#   M-T20 no enclosing-fn check (T11)                                -> T11a-f
#   M-T21 no trait-name check (T1)                                   -> T1a-c, H28b
#   M-T22 the `+ B` drop not reported                                -> T2 (BUILT)
#   M-T23 V6 (`_dt_arity_check`'s dyn arm) gone                      -> V6a (BUILT)
#   M-T24 V7 (`_mret_land`'s dyn arm) gone                           -> V7a, V7b (BUILT)
#   M-T25 the backstop's whole-call skip gone                        -> TY2b (a second error)
#   M-T26 the backstop's dyn arm gone (`_tup_ptr_refuse`)            -> TY2, V9a (BUILT)
#   M-T27 a bare `dyn` not recorded by the fold (T3)                 -> T3a-f (BUILT, or another error)
#   M-T28 the async struct-RETURN refusal not skipping a dyn          -> T11d
#   M-T29 the generic-struct arm of `_dyn_field_chk` gone             -> T12a (BUILT)
#   M-T30 `_arr_ebytes` without `_dyn_uninit`                         -> U2c (BUILT)
#   M-T31 / M-T32 the assignment / field-store backstops' dyn arms gone -> V9b / V9c
#   M-T33 the type-argument refusal not skipping the bare `dyn`        -> T3f (a second error)
#   MTT2 / MTT3 the VS Code grammar / the LSP's len-3 arm without `dyn` -> TT2 / TT3
# D5 (2026-10-10; the same method, the real tree green on every row and on dyn_objects.tcyr; "A" = the
# dyn_objects legs this gate runs with the mutant itself — x86 IR=3 / DCE and PE; the qemu leg's compiler is
# built from the real src — and the file run natively):
#   M-F1  no fill (`_dyn_fill` stores no slot)                        -> TY2, K, PF, A (rc 139: a call through 0)
#   M-F2  no `_sarg_escapes` in `_dyn_sarg`                           -> A (rc 139: the TC rows — the undiverted
#         tail call frees the temp its callee copies from; the no-parameter caller and the loop)
#   M-F3  data and vtable words swapped in `_dyn_build`              -> TY2, K, PF, A (rc 139)
#   M-F4  slots reversed (slot j filled at 8 * (n - 1 - j))          -> A (28 of the file's rows)
#   M-F5  plain `T_m` for a slot (no `_tr_prefix`)                   -> A (§defaults: the collision row read
#         the inherent `base`, 999)
#   M-F6  a default member's slot left 0                             -> A (rc 139: slot 1, `twice`, through 0)
#   M-F7  the pair check skipped (`_dyn_pair_chk` answers 1)         -> F7, F8a-f, F8h, F9 (BUILT)
#   M-F8  decision 2 skipped (`self: T` of 8 B or less accepted)     -> F7 (BUILT)
#   M-F9  no visibility check at a forming site                      -> F10 (BUILT)
#   M-F10 `_gci_inline`'s dyn arm gone (a zone dyn not inline)       -> F11a, F11b, K, PF, A (the backstop
#         refuses every zone dyn global: "cannot initialize dyn Show 'Z' with a value that is not a dyn")
#   M-F11 bit 63 ignored (any slot's stale `_dsc_tn` name trusted)   -> F1c (BUILT: an untyped local formed as
#         the i64 a scalar local of another fn left in its slot)
#   M-F12 no `_dsc_inl` (the #inline replay's parameters unstamped)  -> A (§inline: F1 in the replay, the file
#         does not build)
#   M-F13 the fill only at a pair's FIRST forming site               -> PF, A (rc 139: §sites — the site that
#         runs first, second in source order, calls through an empty table)
#   M-F14 the impl read AFTER the source is parsed (`_dyn_emit`)     -> A (§scalars `nested`: the outer dyn
#         built with the vtable of the `dyn Num` formed inside its source — a find of this bite, fixed)
# D6 (2026-10-10; the same method, the real tree green on every row and on dyn_objects.tcyr — 197 rows, the
# lane's HEAD before D6 RED on 34 of them; "A" = this gate's legs run with the mutant itself — x86 IR=1 / 3
# / DCE, PE; the qemu leg's compiler is built from the real src, so the aarch64 column is dyn_objects.tcyr
# compiled by the MUTANT's aarch64 fork and run under qemu):
#   M-C1  the prototype's parameters not recorded (no `_prescan_params`) -> C7a-b, C8a-d, C9a-d, C10, PD, X5,
#         CG2, S4, S5, CW, A (every call: "'dyn Show.show' expects 0 arguments, got 1")
#   M-C2  the data and vtable words swapped at the call            -> C10, PD, X5a, A (rc 139; PE 5)
#   M-C3  no `_call_ret_marks` (an f64 result untyped)              -> CW ("integer arithmetic with an f64 right
#         operand"), A (the two f64-result rows of dyn_objects)
#   M-C4  no `_sc_x8` (aarch64's X8 for a retptr result)            -> dyn_objects under qemu with the mutant's
#         aarch64 fork: rc 139 (x86, cx and PE pass the retptr as int arg 0: untouched)
#   M-C5  the callee loaded AFTER the arguments                     -> A (C-ORD: 77/78 — the reseated dyn's
#         method ran with the old data word); qemu rc 139 (x0, `self`, clobbered by the late load)
#   M-C6  PE through ECALLPTR_PE                                    -> CG2 (3 anchors, 0 `ff 95`), A PE (75/78:
#         the stack arguments misplaced under its forced alignment)
#   M-C7  no top-level micro-frame                                  -> C10, A (rc 139: the callee spilled through
#         the loader's rbp)
#   M-C8  named arguments not refused                               -> C6
#   M-C9  a generic member callable                                 -> C2
#   M-C10 `_meth_fn_at`'s dyn arm gone (no lookahead sees a prototype) -> C8c, C8d, C9a, C9b (BUILT), PD, A pd
#         (a `*P` result no longer forms: "not a dyn")
#   M-C11 `_dyn_src_call`'s method arm gone                         -> C9a (a second error, "not a dyn")
#   M-C12 `_gvi_expr` back on `_sc_global_mismatch` alone           -> C9b (BUILT: the zone replay kept the data
#         word alone, a SIGSEGV at the first call). 6.7.9: that refusal (`_sc_global_pair`) subsumed 6.7.8's
#         dyn-only `_gvi_dyn_mcall`, removed (struct_result_type_refused.sh, rows Z).
#   M-C13 no arity check (C7)                                       -> C7a, C7b (BUILT)
#   M-C14 a multi-value member not refused (C5)                     -> C5a, C5b
#   M-C15 a refused call's arguments parsed, not stepped over       -> C1c (a second error: V1 on `o`)
#   M-P1  the prototype without its owner (no SFFI)                 -> X5b, CW ("warning: undefined function
#         'dyn Show.show'")
# Defensive, no killing row (named): M-P2, `_impl_tnoff` / `_cur_ii` not cleared around the prototype's
# scan — the call pushes `self` itself (parameter 0 is never marshalled), so no reader sees parameter 0's
# marks; kept so a prototype records its trait member's signature and nothing of the impl being parsed
# (dyn_objects' `HS.via` makes the first `show` prototype inside an impl). M-P3, the `_dyn_p2` guard gone
# — no pass-1 path reaches `_meth_fn_at` with a dyn receiver (measured with an instrumented compiler over
# zone dyn calls, destructures and copies); kept so a prototype can never be made before every struct is
# registered. C5's `u128` arm — no fn or method can declare a `u128` return ("expected identifier, got
# reserved keyword 'u128'"), so a trait member that does has no impl to form.
# Defensive, no killing row (named): `_dyn_f9`'s `async` arm — an impl body cannot hold an `async fn`
# ("expected '}', got async"), and a trait member is never one. `_op_fn_peek`'s dyn arm ("dyn Show has no operators") — every dyn
# operand is refused at its factor first (V1 / V3 / V4 clear the stamp, V4 the `_lsc` record), so no
# operator dispatch is reached with a dyn type today; the arm keeps a future path from dispatching
# `dyn Show_add`. (M-T34, the arm removed, leaves every row green.)
# D7 (2026-10-10; no tool and no compiler source changed — the TT4-TT10 rows pin what the tools already
# do with `dyn`; each mutation a one-edit scratch copy of the tree, its tool or compiler rebuilt from it,
# this gate run with CYCC= that tree's compiler; the real tree 207/207):
#   MTT4  `cyrius header` skips a parameter's type as ONE word (cbt/quality.cyr: past `: ` to a space
#         or `,`) -> TT4 (`cyr_val total(cyr_val a, cyr_val Area, cyr_val b, cyr_val Area);`: the
#         type's second word read as a parameter)
#   MTT6  `cyrius lint`'s pre-pass without --syntax-only (cbt/commands.cyr `_lint_syntax_prepass`)
#         -> TT6 (sib) (rc 1, "does not parse or compile": the sibling's trait is not in scope)
#   MTT10 the guide's first example stating `= 40` (docs/guides/cyrius-guide.md) -> TT10 (example 1: exit 39)
#   M-C2  (D6's, re-measured) the call's data and vtable words swapped (src/) -> the TT sample row and TT10
#         (all three examples: rc 139), with the D6 rows (17 rows)
# REVIEW (2026-10-10; the same method — a one-edit scratch copy of src/, its compiler rebuilt, this gate
# run with CYCC= the mutant; the real tree 234/234, the lane's HEAD before the review RED on the 27 new
# rows and on dyn_objects.tcyr's §pairs):
#   MR1  the prototype not flagged 256 for a `: Result` member     -> C11a, C11b, C11f, A dyn_objects (rc 139)
#   MR2  the prototype not flagged 1024 for a one-value member     -> C11c, C11d, C11e (BUILT)
#   MR3  the value-class check (F8 code 10) gone                   -> F8i, F8j (BUILT)
#   MR4  `_dyn_slot_pair` without the body scan (flag only)        -> F8j (BUILT: the impl below the site)
#   MR5  `_enum_decl_pair` answering 0 (no member is a pair)       -> C11a-f, CW, A dyn_objects
#   MR7  `_pcmpe_struct_assign` without `_dyn_dst_chk`             -> V4h-V4m, V4u (BUILT) (6.7.10 B7-1c: V4h-V4l,
#        V4u — V4m is refused by the copy's type check first, as its 16 B twin V4m2 always was)
#   MR8  `_sc_var_receive` without `_scv_dyn_chk`                  -> V4q, V4r (BUILT)
#   MR9  `_sc_global_receive` without its dyn arm                  -> V4s, V4t (BUILT)
#   MR10 `_dyn_var` without `_dyn_var_ann`                         -> V4n, V4o, V4p (BUILT)
#   MR11 the tail call not diverted for a dyn callee               -> V4v-V4z (BUILT)
#   MR12 V4's exemption not recorded (`_dyn_xb`)                   -> V4h-V4m, V4q-V4u (BUILT) (6.7.10 B7-1c: V4m
#        and V4m2 keep the type check's refusal)
#   (MR6, `_gsc_chain` gone: tests/tcyr/crossos/generic_struct_inference.tcyr G9 — the file does not build,
#   and the value rows read 4 for 8.)
# INTEGRATION (2026-10-10, the 6.7.8 merge of the C2 and dyn lanes; the real tree green on every row):
#   M-AL1 SLDSC / GLDSC on bit 62 — the merge as it stood, aliased with C2's SLSLICE (the merge commit's
#         own compiler)                                              -> AL1 (refused as "no `impl Num for
#         cstring`"), AL2 (BUILT), AL3 (refused: "compound assignment to slice 'y'"), AL4 (BUILT), AL5
#         (BUILT), AL6 (refused as a slice), AL7 (BUILT), AL8 (the captured-slice text); AL9 green
#   M-AL2 SLSLICE never sets bit 62 (C2's M1b)                         -> AL9, IX1 (every leg: `s[1]` "cannot
#         subscript"), IX3 dyn_subscripts
#   M-AL3 the snapshot without `_dsc_snap` / `_dsc_unsnap` — the integration tip 85ee576f (and the dyn
#         lane's 7482deb2) as it stood (a whole-tree copy, its own cross compilers) -> AL10 (exit 213),
#         AL11 (refused: "no `impl Num for cstring`"), AL12 (213), AL13 (refused), AL14 (165) — on x86
#         and every AX leg (aarch64, cx, PE)
# The IX rows (each mutant a one-edit scratch copy of the WHOLE tree, its cycc built from it, this gate run
# from that tree — so the aarch64 and cx legs' compilers carry the mutation too; the real tree green):
#   M-AL1 (above)                                                      -> IX1 every leg (`n += 1` "compound
#         assignment to slice"), IX3 dyn_subscripts
#   MX1  a dyn prototype records no `*T` step (`_fn_rps` zeroed in `_dyn_proto`) -> IX1 every leg, IX2 every
#        leg and k ("cannot subscript the result of 'ptr'"), IX3 dyn_subscripts; CW
#   MX2  `_deref_ed` answers 0 (every `*p` a word)                     -> IX1 every leg (5 of 26: §result's
#        `*o.bp()`, §deref)
#   MX3  the checker's `*T` rule trips at 0 (`i <= 0`)                 -> IX1 the mode-on legs, IX2 k=0 every leg
#   MX4  the site's line off by one (`_bck_line`)                      -> IX2 k=1-3 every leg
#   MX5  the checker's upper bound `i > n` (N itself in range)         -> IX2 k=2 every leg
#   MX6  the checker injected with the mode off (`_bnd_finish`)        -> IX3 both files' mode-off rows; S7
#   MX7  the injected checker's text broken (a missing `;`)            -> IX1 / IX3 the mode-on legs, IX2 every
#        leg and k (`<bounds>:5:1: expected ';'`)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: dyn_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: dyn_checked: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# silent_values_checked.sh helper.
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
exits() {   # <name> <want> <what> <source>
    printf '%b' "$4" > "$T/$1.cyr"
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
# A trait, a record holding a dyn, and the helpers every P / TY row uses: `get(mkw(d, v))` reads a dyn
# whose words are (d, v) out of a heap record (D4 forms none); `dw(o)` reads the two words back through
# a wrapper struct (`load64(&w)`: data, `+ 8`: vtable) as d * 10 + v.
SH='trait Show { fn show(self): i64; }\nstruct P { a; b; }\nimpl Show for P { fn show(self): i64 { return self.a; } }\n'
HP='include "lib/alloc.cyr"\ntrait Show { fn show(self): i64; }\nstruct W { o: dyn Show; }\nstruct H { a; o: dyn Show; b; }\nfn mkw(d, v): i64 { var m = alloc(16); store64(m, d); store64(m + 8, v); return m; }\nfn get(w: *W): dyn Show { var o: dyn Show = w.o; return o; }\nfn pass(o: dyn Show): dyn Show { return o; }\nfn dw(o: dyn Show): i64 { var w: W = W { o }; return load64(&w) * 10 + load64(&w + 8); }\nfn g(x): i64 { return x; }\n'
FO='fn f(o: dyn Show): i64 { '
FE=' }\nsyscall(60, 0);\n'
FM='fn main(): i64 {\n    alloc_init();\n    var o: dyn Show = get(mkw(4, 9));\n'
ME='}\nsyscall(60, main());\n'
RV='used as a value - call one of its methods, or copy it whole into a dyn'

# ── K: the reserved word ───────────────────────────────────────────────────────────────────────────
KW="got reserved keyword 'dyn'"
refused k01 "$KW" "K1: \`var dyn = 5;\`" 'fn f(): i64 { var dyn = 5; return 0; }\nsyscall(60, f());\n'
refused k02 "$KW" "K2: \`fn dyn()\`" 'fn dyn(): i64 { return 1; }\nsyscall(60, 0);\n'
refused k03 "$KW" "K3: a field \`dyn\`" 'struct Q { a; dyn; }\nsyscall(60, 0);\n'
refused k04 "$KW" "K4: a method \`p.dyn()\`" "${SH}fn f(p: P): i64 { return p.dyn(); }\nsyscall(60, 0);\n"

# ── TY: each position compiles, its two words intact ───────────────────────────────────────────────
exits ty1 49 "TY1: a local, copied (\`var o2: dyn Show = o;\`)" "${HP}${FM}    var o2: dyn Show = o;\n    var o3: dyn Show = o2;\n    return dw(o3);\n${ME}"
exits ty2 3 "TY2: a global after the first statement, formed (D5) from \`&P0\` and dispatched by hand" "${SH}struct W { o: dyn Show; }\nfn dk(o: dyn Show): i64 { var w: W = W { o }; return callptr(load64(load64(&w + 8)), load64(&w)); }\nvar P0 = P { 3, 4 };\nsyscall(1, 1, \"\", 0);\nvar G: dyn Show = &P0;\nsyscall(60, dk(G));\n"
refused ty2b "'mkd' returns a struct by value, and a struct result needs storage in a fn's frame" "TY2b: \`var G: dyn Show = mkd();\` at top level: the call refuses itself, once (not also \"not a dyn\")" "${HP}fn mkd(): dyn Show { return get(mkw(4, 9)); }\nsyscall(1, 1, \"\", 0);\nvar G: dyn Show = mkd();\nsyscall(60, 0);\n"
exits ty3 49 "TY3: a parameter (\`fn dw(o: dyn Show)\`)" "${HP}${FM}    return dw(o);\n${ME}"
exits ty4 49 "TY4: a return threaded through three fns declared below the caller (the rough pair scan)" "${HP}${FM}    var r: dyn Show = a1(o);\n    return dw(r);\n}\nfn a1(o: dyn Show): dyn Show { var x: dyn Show = a2(o); return x; }\nfn a2(o: dyn Show): dyn Show { var y: dyn Show = a3(o); return y; }\nfn a3(o: dyn Show): dyn Show { var z: dyn Show = o; return z; }\nsyscall(60, main());\n"
exits ty5 170 "TY5: a struct field — the literal \`H { 1, o, 7 }\`, a store \`h.o = o2;\`, a read \`dw(h.o)\`" "${HP}${FM}    var h: H = H { 1, o, 7 };\n    var o2: dyn Show = get(mkw(5, 6));\n    h.o = o2;\n    return h.a * 100 + h.b * 10 + dw(h.o) - 56;\n${ME}"
exits ty6 49 "TY6: a trait member's signature (\`fn mix(self, o: dyn Show, k): dyn Show;\`), its impl called" "${HP}trait Mix { fn mix(self, o: dyn Show, k): dyn Show; }\nstruct P { a; b; }\nimpl Mix for P { fn mix(self, o: dyn Show, k): dyn Show { var r: dyn Show = o; return r; } }\n${FM}    var p = P { 1, 2 };\n    var r: dyn Show = p.mix(o, 3);\n    return dw(r);\n${ME}"

# ── S: shapes ──────────────────────────────────────────────────────────────────────────────────────
exits s02 32 "S2: \`struct H { a; o: dyn Show; b; }\` is 32 bytes, \`a\` / \`b\` intact around the 16-byte dyn" "${HP}${FM}    var h: H = H { 3, o, 7 };\n    if (h.a * 10 + h.b != 37) { return 1; }\n    if (dw(h.o) != 49) { return 2; }\n    return sizeof(H);\n${ME}"
exits s03 149 "S3: a forward call to \`fn later(o: dyn Show, k)\` declared below (pass 1 scans the dyn parameter)" "${HP}${FM}    return later(o, 100);\n}\nfn later(o: dyn Show, k): i64 { return dw(o) + k; }\nsyscall(60, main());\n"
refused s05 "#derive reads named field types; 'o' is a dyn (in the declaration of D)" "S5: \`#derive\` on a struct with a dyn field (the walk read \`dyn\` as the type and \`Show\` as a field)" "${SH}#derive(accessors)\nstruct D { a; o: dyn Show; b; }\nsyscall(60, 0);\n"

# ── T: type positions left open ────────────────────────────────────────────────────────────────────
refused t01a "'Nope' is not a trait - \`dyn\` takes a declared trait's name" "T1a: \`dyn Nope\`" "${SH}fn f(o: dyn Nope): i64 { return 0; }\nsyscall(60, 0);\n"
refused t01b "'P' is not a trait" "T1b: \`dyn P\`, a struct" "${SH}fn f(o: dyn P): i64 { return 0; }\nsyscall(60, 0);\n"
refused t01c "'T' is not a trait" "T1c: \`dyn T\`, a type parameter's name" "${SH}fn f(o: dyn T): i64 { return 0; }\nsyscall(60, 0);\n"
refused t02 "\`dyn A + B\` is refused - a dyn holds one vtable, of one trait" "T2: \`dyn Show + Eq\` (one report, the parse in sync)" "${SH}trait Eq { fn eq(self): i64; }\nfn f(o: dyn Show + Eq, k): i64 { return k; }\nsyscall(60, 0);\n"
T3M="\`dyn\` takes a trait's name - \`dyn Show\` for \`trait Show\`"
refused t03a "$T3M" "T3a: \`o: dyn)\` (the parameter type arm took any one token)" "${SH}fn f(o: dyn): i64 { return 0; }\nsyscall(60, 0);\n"
refused t03b "$T3M" "T3b: \`var o: dyn = 5;\`" "${SH}fn f(): i64 { var o: dyn = 5; return 0; }\nsyscall(60, 0);\n"
refused t03c "$T3M" "T3c: \`var o: dyn;\` and a return \`: dyn\`" "${SH}fn f(): dyn { return 0; }\nsyscall(60, 0);\n"
refused t03d "$T3M" "T3d: \`Vec<dyn>\` (it compiled)" "${SH}include \"lib/vec.cyr\"\nfn f(v: Vec<dyn>): i64 { return 0; }\nsyscall(60, 0);\n"
refused t03e "$T3M" "T3e: \`*dyn\` (it compiled)" "${SH}fn f(v: *dyn): i64 { return 0; }\nsyscall(60, 0);\n"
refused t03f "$T3M" "T3f: \`Pr<i64, dyn>\`" "${SH}struct Pr<A, B> { a: A; b: B; }\nfn f(): i64 { var b: Pr<i64, dyn>; return 0; }\nsyscall(60, 0);\n"
T4M="dyn Show cannot be a type argument - a collection holds pointers to records that hold a dyn"
refused t04a "$T4M" "T4a: \`Vec<dyn Show>\`" "${SH}include \"lib/vec.cyr\"\nfn f(v: Vec<dyn Show>): i64 { return 0; }\nsyscall(60, 0);\n"
refused t04b "$T4M" "T4b: \`Box<dyn Show>\`" "${SH}struct Box<T> { v: T; }\nfn f(b: Box<dyn Show>): i64 { return 0; }\nsyscall(60, 0);\n"
refused t04c "$T4M" "T4c: \`g<dyn Show>(o)\`" "${SH}fn g<T>(x: T): i64 { return 0; }\nfn f(o: dyn Show): i64 { return g<dyn Show>(o); }\nsyscall(60, 0);\n"
refused t04d "$T4M" "T4d: \`Pr<i64, dyn Show>\` (the second argument)" "${SH}struct Pr<A, B> { a: A; b: B; }\nfn f(b: Pr<i64, dyn Show>): i64 { return 0; }\nsyscall(60, 0);\n"
refused t04e "$T4M" "T4e: \`Box<Box<dyn Show>>\` (nested, \`>>\`)" "${SH}struct Box<T> { v: T; }\nfn f(b: Box<Box<dyn Show>>): i64 { return 0; }\nsyscall(60, 0);\n"
T5M="a pointer to dyn Show is refused"
refused t05a "$T5M" "T5a: \`*dyn Show\`" "${SH}fn f(o: *dyn Show): i64 { return 0; }\nsyscall(60, 0);\n"
refused t05b "$T5M" "T5b: \`**dyn Show\`" "${SH}fn f(): i64 { var p: **dyn Show = 0; return 0; }\nsyscall(60, 0);\n"
refused t05c "dyn Show cannot be a \`*fn(..)\` parameter" "T5c: \`*fn(dyn Show): i64\` (a trait member's parameter)" "${SH}trait Cb { fn on(self, cb: *fn(dyn Show): i64): i64; }\nsyscall(60, 0);\n"
refused t06a "dyn Show cannot be an array element" "T6a: \`dyn Show[4]\`" "${SH}fn f(): i64 { var a: dyn Show[4]; return 0; }\nsyscall(60, 0);\n"
refused t06b "dyn Show cannot be a slice element" "T6b: \`[dyn Show]\`" "${SH}fn f(): i64 { var a: [dyn Show] = 0; return 0; }\nsyscall(60, 0);\n"
refused t06c "dyn Show cannot be a slice element" "T6c: \`slice<dyn Show>\`" "${SH}fn f(): i64 { var a: slice<dyn Show> = 0; return 0; }\nsyscall(60, 0);\n"
refused t06d "dyn Show cannot be a tuple or multi-value element" "T6d: \`(dyn Show, i64)\`" "${SH}fn f(): i64 { var t: (dyn Show, i64); return 0; }\nsyscall(60, 0);\n"
refused t06e "dyn Show cannot be a tuple or multi-value element" "T6e: a multi-value return \`: (i64, dyn Show)\`" "${SH}fn f(): (i64, dyn Show) { return (1, 2); }\nsyscall(60, 0);\n"
refused t07 "dyn Show takes no type arguments - a trait has none" "T7: \`dyn Show<i64>\`" "${SH}fn f(o: dyn Show<i64>): i64 { return 0; }\nsyscall(60, 0);\n"
refused t08a "sizeof(dyn Show) is refused" "T8a: \`sizeof(dyn Show)\`" "${SH}fn f(): i64 { return sizeof(dyn Show); }\nsyscall(60, f());\n"
refused t08b "sizeof(dyn Show) is refused" "T8b: \`#assert sizeof(dyn Show) == 16\`" "${SH}#assert sizeof(dyn Show) == 16, \"x\"\nsyscall(60, 0);\n"
T9M="\`impl\` takes a type that is not a dyn"
refused t09a "$T9M" "T9a: \`impl Show for dyn Show\`" "${SH}impl Show for dyn Show { fn show(self): i64 { return 1; } }\nsyscall(60, 0);\n"
refused t09b "$T9M" "T9b: \`impl dyn Show\`" "${SH}impl dyn Show { fn show2(self): i64 { return 1; } }\nsyscall(60, 0);\n"
T10M="dyn Show is a type - write it after a \`:\` (\`o: dyn Show\`)"
refused t10a "$T10M" "T10a: an expression \`var x = dyn Show;\`" "${SH}fn f(): i64 { var x = dyn Show; return 0; }\nsyscall(60, 0);\n"
refused t10b "$T10M" "T10b: a name \`struct dyn Show\`" "${SH}struct dyn Show { a; }\nsyscall(60, 0);\n"
refused t10c "$T10M" "T10c: a parameter with no name \`fn f(dyn Show)\`" "${SH}fn f(dyn Show): i64 { return 0; }\nsyscall(60, 0);\n"
refused t10d "$T10M" "T10d: \`var dyn Show = 1;\`" "${SH}fn f(): i64 { var dyn Show = 1; return 0; }\nsyscall(60, 0);\n"
refused t11a "a dyn type in a generic fn is refused" "T11a: a generic fn's signature" "${SH}fn g<T>(x: T, o: dyn Show): i64 { return 0; }\nsyscall(60, 0);\n"
refused t11b "a dyn type in a generic fn is refused" "T11b: a generic fn's body" "${SH}fn h<T>(x: T, k): i64 {\n    if (k > 0) { var o: dyn Show; }\n    return 0;\n}\nsyscall(60, 0);\n"
printf '%b' "include \"lib/alloc.cyr\"\n${SH}async fn g(o: dyn Show, k): i64 { return k; }\nsyscall(60, 0);\n" > "$T/t11c.cyr"
rc=0; CYRIUS_ASYNC=1 timeout 60 "$CC" < "$T/t11c.cyr" > "$T/t11c.bin" 2> "$T/t11c.err" || rc=$?
if [ "$rc" -ne 0 ] && [ "$(grep -c '^error' "$T/t11c.err")" -eq 1 ] && grep -qF "a dyn type in an \`async fn\` is refused" "$T/t11c.err"; then ok "T11c: an \`async fn\`'s dyn parameter (CYRIUS_ASYNC=1): refused once (not also as a by-value struct parameter)"
else bad "T11c: rc $rc: $(grep '^error' "$T/t11c.err" | head -2 | tr '\n' '|')"; fi
printf '%b' "include \"lib/alloc.cyr\"\n${SH}async fn g(k): dyn Show { return k; }\nsyscall(60, 0);\n" > "$T/t11d.cyr"
rc=0; CYRIUS_ASYNC=1 timeout 60 "$CC" < "$T/t11d.cyr" > "$T/t11d.bin" 2> "$T/t11d.err" || rc=$?
if [ "$rc" -ne 0 ] && grep -qF "a dyn type in an \`async fn\` is refused" "$T/t11d.err" && ! grep -qF 'a Future carries one i64' "$T/t11d.err"; then ok "T11d: an \`async fn\` returning a dyn: refused at its type (not also as a struct returned by value)"
else bad "T11d: rc $rc: $(grep '^error' "$T/t11d.err" | head -2 | tr '\n' '|')"; fi
refused t11e "a dyn type in a \`const fn\` is refused" "T11e: a \`const fn\`" "${SH}const fn g(o: dyn Show): i64 { return 0; }\nsyscall(60, 0);\n"
refused t11f "a dyn type in a \`#naked\` fn is refused" "T11f: a \`#naked\` fn" "${SH}#naked\nfn g(o: dyn Show) { asm { 0xC3; } }\nsyscall(60, 0);\n"
exits t11g 0 "T11g: a fn below a bodyless generic trait member is not \`inside\` it" "${SH}trait Pk { fn pick<U>(self, u: U): i64; }\nstruct Hd { o: dyn Show; }\nsyscall(60, sizeof(Hd) - 16);\n"
refused t12a "a dyn field in a generic struct is refused" "T12a: a dyn field in a generic struct" "${SH}struct B<T> { v: T; o: dyn Show; }\nsyscall(60, 0);\n"
refused t12b "a union cannot hold a dyn" "T12b: a union member" "${SH}union U { o: dyn Show; x: i64; }\nsyscall(60, 0);\n"
refused t12c "a union cannot hold a dyn" "T12c: a union member holding a struct that holds one" "${SH}struct Hd { a; o: dyn Show; }\nunion U { h: Hd; x: i64; }\nsyscall(60, 0);\n"
refused t13 "a const takes no type annotation" "T13: \`const C: dyn Show\` (the const's own refusal)" "${SH}const C: dyn Show = 5;\nsyscall(60, 0);\n"

# ── U: uninitialised — struct locals are not zeroed ────────────────────────────────────────────────
UM="with its value - "
refused u01 "declare dyn Show 'o' ${UM}struct locals are not zeroed" "U1: \`var o: dyn Show;\` in a fn" "${SH}fn f(): i64 { var o: dyn Show; return 0; }\nsyscall(60, 0);\n"
refused u02a "declare Hd 'h' ${UM}it holds a dyn" "U2a: \`var h: Hd;\`, Hd holding a dyn" "${SH}struct Hd { a; o: dyn Show; }\nfn f(): i64 { var h: Hd; h.a = 1; return h.a; }\nsyscall(60, 0);\n"
refused u02b "declare H2 'h' ${UM}it holds a dyn" "U2b: through a nested struct field" "${SH}struct Hd { a; o: dyn Show; }\nstruct H2 { h: Hd; b; }\nfn f(): i64 { var h: H2; return 0; }\nsyscall(60, 0);\n"
refused u02c "an array of Hd in a fn is refused" "U2c: \`var hs: Hd[4];\`" "${SH}struct Hd { a; o: dyn Show; }\nfn f(): i64 { var hs: Hd[4]; return 0; }\nsyscall(60, 0);\n"
refused u02d "declare Box\$Hd 'b' ${UM}it holds a dyn" "U2d: through a generic instance \`Box<Hd>\`" "${SH}struct Hd { a; o: dyn Show; }\nstruct Box<T> { v: T; }\nfn f(): i64 { var b: Box<Hd>; return 0; }\nsyscall(60, 0);\n"
exits u03 3 "U3: a struct holding no dyn is still declared uninitialised (unchanged)" "${SH}struct Q { a; b; }\nfn f(): i64 { var q: Q; q.a = 1; q.b = 2; return q.a + q.b; }\nsyscall(60, f());\n"

# ── V: opacity — a dyn is not a value (decision 7) ─────────────────────────────────────────────────
refused v01a "dyn Show 'o' $RV" "V1a: \`o + 1\` (no \`dyn Show_add\` dispatch)" "${HP}${FO}return o + 1;${FE}"
refused v01b "dyn Show 'o' $RV" "V1b: \`1 + o\`" "${HP}${FO}return 1 + o;${FE}"
refused v01c "dyn Show 'o' $RV" "V1c: \`if (o)\`" "${HP}${FO}if (o) { return 1; } return 0;${FE}"
refused v01d "dyn Show 'o' $RV" "V1d: \`!o\`" "${HP}${FO}return !o;${FE}"
refused v01e "dyn Show 'o' $RV" "V1e: \`-o\`" "${HP}${FO}return -o;${FE}"
refused v01f "dyn Show 'o' $RV" "V1f: \`var x = o;\` (it took the data word)" "${HP}${FO}var x = o; return x;${FE}"
refused v01g "dyn Show 'o' $RV" "V1g: an untyped argument \`g(o)\`" "${HP}${FO}return g(o);${FE}"
refused v01h "dyn Show 'o' $RV" "V1h: \`load64(o)\`" "${HP}${FO}return load64(o);${FE}"
refused v01i "dyn Show 'o' $RV" "V1i: \`callptr(&g, o)\`" "${HP}${FO}return callptr(&g, o);${FE}"
refused v01j "dyn Show 'o' $RV" "V1j: \`match o\`" "${HP}${FO}match o { _ => { return 1; } } return 0;${FE}"
refused v01k "dyn Show 'o' $RV" "V1k: \`while (o)\`" "${HP}${FO}while (o) { return 1; } return 0;${FE}"
refused v01l "dyn Show 'o' $RV" "V1l: \`(o) + 1\`" "${HP}${FO}return (o) + 1;${FE}"
refused v01m "compound assignment to struct 'o' is refused" "V1m: \`o += 1\` (the struct rule's own refusal)" "${HP}${FO}o += 1; return 0;${FE}"
refused v02a "the words of dyn Show 'o' are not addressable" "V2a: \`&o\` (a parameter)" "${HP}${FO}return &o;${FE}"
refused v02b "the words of dyn Show 'o2' are not addressable" "V2b: \`var p = &o2;\` (a local)" "${HP}${FO}var o2: dyn Show = o; var p = &o2; return p;${FE}"
refused v03a "dyn Show 'o' (a field) $RV" "V3a: \`h.o + 1\`" "${HP}${FO}var h: H = H { 1, o, 2 }; return h.o + 1;${FE}"
refused v03b "dyn Show 'o' (a field) $RV" "V3b: \`g(w.o)\`, an untyped argument" "${HP}${FO}var w: W = W { o }; return g(w.o);${FE}"
refused v03c "dyn Show 'o' (a field) $RV" "V3c: \`return w.o;\` from an i64 fn" "${HP}${FO}var w: W = W { o }; return w.o;${FE}"
refused v04a "a dyn Show result $RV" "V4a: \`pass(o) + 1\`" "${HP}${FO}return pass(o) + 1;${FE}"
refused v04b "a dyn Show result $RV" "V4b: \`g(pass(o))\`, an untyped argument" "${HP}${FO}return g(pass(o));${FE}"
refused v04c "a dyn Show result $RV" "V4c: \`(pass(o)) + 1\`" "${HP}${FO}return (pass(o)) + 1;${FE}"
refused v04d "a dyn Show result $RV" "V4d: an un-annotated \`var x = (pass(o));\` (it kept the data word)" "${HP}${FO}var x = (pass(o)); return 0;${FE}"
refused v04e "a dyn Show result $RV" "V4e: a method result, \`p.mk(o) + 1\`" "${HP}struct Q { a; b; }\nimpl Q { fn mk(self, o: dyn Show): dyn Show { return o; } }\n${FO}var q = Q { 1, 2 }; return q.mk(o) + 1;${FE}"
refused v04f "a dyn Show result $RV" "V4f: \`1 + p.mk(o)\`" "${HP}struct Q { a; b; }\nimpl Q { fn mk(self, o: dyn Show): dyn Show { return o; } }\n${FO}var q = Q { 1, 2 }; return 1 + q.mk(o);${FE}"
refused v04g "a dyn Show result $RV" "V4g: \`return pass(o);\` from an i64 fn" "${HP}fn f(o: dyn Show, k): i64 { if (k > 0) { return 1; } return (pass(o)); }\nsyscall(60, 0);\n"
# (review, 2026-10-10) V4 lets a whole dyn result through for a DESTINATION — which must then be that
# dyn. Every row below compiled and handed the program the dyn's DATA word: an assignment arms for any
# target, a declaration whose annotation is no struct took the call's struct (or its first word), a
# top-level declaration after the first statement kept the first word, and a tail call jumped past
# the factor. Refused by name, once, at the call.
RD="a dyn Show result $RV"
QM='struct Q { a; b; }\nimpl Q { fn mk(self, o: dyn Show): dyn Show { return o; } }\n'
refused v04h "$RD" "V4h: \`x = pass(o);\` into an untyped local" "${HP}${FO}var x = 0; x = pass(o); return x;${FE}"
refused v04i "$RD" "V4i: \`x = pass(o);\` into an \`i64\` local" "${HP}${FO}var x: i64 = 0; x = pass(o); return x;${FE}"
refused v04j "$RD" "V4j: \`GU = pass(o);\` into an untyped global" "${HP}var GU = 0;\n${FO}GU = pass(o); return GU;${FE}"
refused v04k "$RD" "V4k: a classic-for step \`x = pass(o)\`" "${HP}${FO}var x = 0; for (var i = 0; i < 1; x = pass(o)) { i = 1; } return x;${FE}"
refused v04l "$RD" "V4l: \`x = q.mk(o);\`, a method result" "${HP}${QM}${FO}var q = Q { 1, 2 }; var x = 0; x = q.mk(o); return x;${FE}"
# 6.7.10 (B7-1c): a `*S1` of 8 bytes is a struct operand of `=`, as over 8 B (the user's decision 6: struct
# copies are size-independent), so the dyn result is refused as a struct of ANOTHER type, by the copy's
# type check ahead of the dyn check — the message its 16 B twin always gave. Still refused once, at the call.
RX="cannot copy 'pass' into a variable of a different struct/vector type: 'sp'"
refused v04m "$RX" "V4m: \`sp = pass(o);\` into a \`*S1\` local (S1 of 8 bytes)" "${HP}struct S1 { a; }\n${FO}var s = S1 { 1 }; var sp: *S1 = &s; sp = pass(o); return 0;${FE}"
refused v04m2 "$RX" "V4m: its 16 B twin, into a \`*S2\` local" "${HP}struct S2 { a; b; }\n${FO}var s = S2 { 1, 2 }; var sp: *S2 = &s; sp = pass(o); return 0;${FE}"
refused v04n "$RD" "V4n: \`var y: i64 = pass(o);\` (y became the dyn its annotation says it is not)" "${HP}${FO}var y: i64 = pass(o); return 0;${FE}"
refused v04o "$RD" "V4o: \`var y: u8 = pass(o);\`" "${HP}${FO}var y: u8 = pass(o); return 0;${FE}"
refused v04p "$RD" "V4p: \`var y: f64 = pass(o);\`" "${HP}${FO}var y: f64 = pass(o); return 0;${FE}"
refused v04q "$RD" "V4q: \`var y: *W = pass(o);\` (only a pointer warning)" "${HP}${FO}var y: *W = pass(o); return 0;${FE}"
refused v04r "$RD" "V4r: \`var y: i64 = q.mk(o);\`, a method result" "${HP}${QM}${FO}var q = Q { 1, 2 }; var y: i64 = q.mk(o); return y;${FE}"
refused v04s "$RD" "V4s: a top-level \`var G = get(..);\` after the first statement (it kept the data word)" "${HP}syscall(1, 1, \"\", 0);\nvar G = get(mkw(4, 9));\nsyscall(60, 0);\n"
refused v04t "$RD" "V4t: a top-level \`var G: i64 = get(..);\` after the first statement" "${HP}syscall(1, 1, \"\", 0);\nvar G: i64 = get(mkw(4, 9));\nsyscall(60, 0);\n"
refused v04u "$RD" "V4u: a top-level \`GU = get(..);\`" "${HP}var GU = 0;\nsyscall(1, 1, \"\", 0);\nGU = get(mkw(4, 9));\nsyscall(60, 0);\n"
refused v04v "$RD" "V4v: \`return pass(o);\` from an i64 fn — a TAIL call (it jumped past the factor)" "${HP}fn r(o: dyn Show): i64 { return pass(o); }\nsyscall(60, 0);\n"
refused v04w "$RD" "V4w: ... from an untyped fn" "${HP}fn r(o: dyn Show) { return pass(o); }\nsyscall(60, 0);\n"
refused v04x "$RD" "V4x: ... from a fn returning \`*W\`" "${HP}fn r(o: dyn Show): *W { return pass(o); }\nsyscall(60, 0);\n"
refused v04y "$RD" "V4y: ... from a fn returning a struct of 8 bytes" "${HP}struct S1 { a; }\nfn r(o: dyn Show): S1 { return pass(o); }\nsyscall(60, 0);\n"
refused v04z "$RD" "V4z: ... from a closure's body" "${HP}${FO}var d = |k| { return get(mkw(k, k)); }; return 0;${FE}"
VF="unknown field '"
refused v05a "${VF}data' on struct 'dyn Show'" "V5a: \`o.data\`" "${HP}${FO}return o.data;${FE}"
refused v05b "${VF}vtable' on struct 'dyn Show'" "V5b: \`o.vtable\`" "${HP}${FO}return o.vtable;${FE}"
refused v05c "${VF}data' on struct 'dyn Show'" "V5c: \`o.data = 5;\`" "${HP}${FO}o.data = 5; return 0;${FE}"
refused v05d "${VF}0' on struct 'dyn Show'" "V5d: \`o.0\`" "${HP}${FO}return o.0;${FE}"
refused v05e "${VF}show' on struct 'dyn Show'" "V5e: \`o.show\` (no call)" "${HP}${FO}return o.show;${FE}"
refused v06a "multi-value destructure of a dyn Show 'pass' result" "V6a: \`var a, b = pass(o);\`" "${HP}${FO}var a, b = pass(o); return a;${FE}"
refused v06b "cannot re-assign from 'pass' - it returns struct 'dyn Show', not multiple values" "V6b: \`a, b = pass(o);\` (the re-assignment's own refusal)" "${HP}${FO}var a = 0; var b = 0; a, b = pass(o); return a;${FE}"
refused v07a "a fn returning dyn Show returns a whole dyn" "V7a: \`return (a, b);\` in a fn returning a dyn" "${HP}fn mk(a, b): dyn Show { return (a, b); }\nsyscall(60, 0);\n"
refused v07b "a fn returning dyn Show returns a whole dyn" "V7b: \`ret2(a, b)\`" "${HP}fn mk(a, b): dyn Show { ret2(a, b); }\nsyscall(60, 0);\n"
refused v08 "dyn Show 'o' (a field) is set from a whole dyn - a struct literal cannot write its words" "V8: \`H { 1, 2, 3, 4 }\` (its leaves were the dyn's two words)" "${HP}${FO}var h: H = H { 1, 2, 3, 4 }; return h.a;${FE}"
# Since D5 a literal FORMS (F6 when no impl takes it); the backstops still meet a source the classifier
# leaves to the struct paths — the value of a callee that resolves nowhere.
refused v09a "cannot initialize dyn Show 'x' with a value that is not a dyn" "V9a: backstop \`var x: dyn Show = nofn();\`" "${HP}${FO}var x: dyn Show = nofn(); return 0;${FE}"
refused v09b "cannot assign a value that is not a dyn to dyn Show 'x'" "V9b: backstop \`x = nofn();\`" "${HP}${FO}var x: dyn Show = o; x = nofn(); return 0;${FE}"
refused v09c "cannot store a value that is not a dyn into dyn Show 'o' (a field)" "V9c: backstop \`h.o = nofn();\`" "${HP}${FO}var h: H = H { 1, o, 2 }; h.o = nofn(); return 0;${FE}"

# ── F: forming (D5) — every refusal once, at the source ────────────────────────────────────────────
SN='trait Show { fn show(self): i64; }\nstruct P { a; b; }\nimpl Show for P { fn show(self): i64 { return self.a; } }\ntrait Num { fn num(self): i64; }\nimpl Num for i64 { fn num(self): i64 { return self; } }\nenum Color { Red, Green, Blue }\nstruct H { a; o: dyn Show; b; }\nstruct HP { p: P; }\nfn g(x): i64 { return x; }\n'
FF='cannot form dyn Show from '
FN='cannot form dyn Num from '
UT=' - an untyped name may hold a pointer (ADR-002)'
refused f01a "${FN}'x'${UT}" "F1a: an untyped local" "${SN}fn f(): i64 { var x = 5; var o: dyn Num = x; return 0; }\nsyscall(60, 0);\n"
refused f01b "${FN}'x'${UT}" "F1b: an untyped parameter" "${SN}fn f(x): i64 { var o: dyn Num = x; return 0; }\nsyscall(60, 0);\n"
refused f01c "${FN}'u'${UT}" "F1c: an untyped local in the slot a declared \`n: i64\` of another fn held (bit 63 is the stamp's validity)" "${SN}fn a(): i64 { var n: i64 = 5; return n; }\nfn b(): i64 { var u = 7; var o: dyn Num = u; return 0; }\nsyscall(60, a());\n"
refused f01d "${FN}'i'${UT}" "F1d: a for-in variable (no declared type)" "${SN}fn f(): i64 { for i in 0..3 { var o: dyn Num = i; } return 0; }\nsyscall(60, 0);\n"
refused f02a "${FF}'p' - no implicit \`&\`: write \`&p\`" "F2a: a bare inline struct local" "${SN}fn f(): i64 { var p = P { 1, 2 }; var o: dyn Show = p; return 0; }\nsyscall(60, 0);\n"
refused f02b "${FF}'G0' - no implicit \`&\`: write \`&G0\`" "F2b: a bare inline struct global" "${SN}var G0 = P { 1, 2 };\nfn f(): i64 { var o: dyn Show = G0; return 0; }\nsyscall(60, 0);\n"
refused f03a "${FF}\`&q\` - it is a pointer already: write \`q\`" "F3a: \`&q\` of a \`q: *P\` parameter" "${SN}fn f(q: *P): i64 { var o: dyn Show = &q; return 0; }\nsyscall(60, 0);\n"
refused f03b "${FF}\`&h\` - it is a pointer already: write \`h\`" "F3b: \`&h\` of a pointer-mode handle" "${SN}include \"lib/alloc.cyr\"\nfn f(): i64 { var h: P = alloc(16); var o: dyn Show = &h; return 0; }\nsyscall(60, 0);\n"
refused f03c "${FN}\`&n\` - a dyn of a scalar holds its value: write \`n\`" "F3c: \`&n\` of a declared scalar" "${SN}fn f(): i64 { var n: i64 = 5; var o: dyn Num = &n; return 0; }\nsyscall(60, 0);\n"
refused f03d "${FF}\`&o\` - it is a dyn: copy it whole (\`= o\`)" "F3d: \`&o\` of a dyn" "${SN}fn f(o: dyn Show): i64 { var o2: dyn Show = &o; return 0; }\nsyscall(60, 0);\n"
refused f04 "${FF}'p' - a closure's captured name: bind it to a declared variable first" "F4: a closure's captured name" "${SN}include \"lib/alloc.cyr\"\nfn f(): i64 { var p = P { 1, 2 }; var c = || { var o: dyn Show = p; return 0; }; return 0; }\nsyscall(60, 0);\n"
F5M="this expression - a dyn is formed from a \`*T\` the compiler knows"
refused f05a "${FF}${F5M}" "F5a: \`alloc(16)\` (never a pointer-mode dyn)" "${SN}include \"lib/alloc.cyr\"\nfn f(): i64 { var o: dyn Show = alloc(16); return 0; }\nsyscall(60, 0);\n"
refused f05b "${FF}${F5M}" "F5b: a string literal" "${SN}fn f(): i64 { var o: dyn Show = \"abc\"; return 0; }\nsyscall(60, 0);\n"
refused f05c "${FF}${F5M}" "F5c: \`&h.p\`" "${SN}fn f(): i64 { var p = P { 1, 2 }; var h = HP { p }; var o: dyn Show = &h.p; return 0; }\nsyscall(60, 0);\n"
refused f05d "${FN}${F5M}" "F5d: an operator \`n + 1\`" "${SN}fn f(): i64 { var n: i64 = 1; var o: dyn Num = n + 1; return 0; }\nsyscall(60, 0);\n"
refused f05e "${FN}${F5M}" "F5e: an enum constant \`Color.Blue\`" "${SN}fn f(): i64 { var o: dyn Num = Color.Blue; return 0; }\nsyscall(60, 0);\n"
refused f05f "${FN}${F5M}" "F5f: a call returning i64" "${SN}fn f(): i64 { var o: dyn Num = g(1); return 0; }\nsyscall(60, 0);\n"
refused f05g "${FN}${F5M}" "F5g: \`callptr(&g, 1)\`" "${SN}fn f(): i64 { var o: dyn Num = callptr(&g, 1); return 0; }\nsyscall(60, 0);\n"
refused f05h "a struct literal does not form a dyn - form it first (\`var d: dyn Show = ..;\`)" "F5h: \`H { 1, &p, 2 }\` (the element taken whole: no cascade)" "${SN}fn f(): i64 { var p = P { 1, 2 }; var h: H = H { 1, &p, 2 }; return h.a; }\nsyscall(60, 0);\n"
refused f06a "no \`impl Show for i64\` - a dyn Show is formed only from a type that implements Show" "F6a: a literal with no \`impl Show for i64\`" "${SN}fn f(): i64 { var o: dyn Show = 5; return 0; }\nsyscall(60, 0);\n"
refused f06b "no \`impl Show for Q\`" "F6b: a \`*Q\` with no \`impl Show for Q\`" "${SN}struct Q { a; }\nfn f(q: *Q): i64 { var o: dyn Show = q; return 0; }\nsyscall(60, 0);\n"
refused f07 "cannot form dyn T2 from Q - its method 'sh' takes \`self: Q\` by value, and a struct of 8 bytes or less arrives in a register" "F7: \`self: Q\`, Q of 8 B (decision 2), naming the method" "${SN}struct Q { a; }\ntrait T2 { fn sh(self): i64; }\nimpl T2 for Q { fn sh(self: Q): i64 { return self.a; } }\nfn f(q: *Q): i64 { var o: dyn T2 = q; return 0; }\nsyscall(60, 0);\n"
F8M="cannot form dyn T2 from P - its method"
refused f08a "${F8M} 'sh' does not match its declaration in trait T2: parameter 'n' has another type (an untyped parameter is i64)" "F8a: a parameter's type (\`n: u8\` for an untyped \`n\`)" "${SN}trait T2 { fn sh(self, n): i64; }\nimpl T2 for P { fn sh(self, n: u8): i64 { return n; } }\nfn f(q: *P): i64 { var o: dyn T2 = q; return 0; }\nsyscall(60, 0);\n"
refused f08b "${F8M} 'sh' does not match its declaration in trait T2: the return type differs" "F8b: the return type (\`: i32\` for none)" "${SN}trait T2 { fn sh(self); }\nimpl T2 for P { fn sh(self): i32 { return 1; } }\nfn f(q: *P): i64 { var o: dyn T2 = q; return 0; }\nsyscall(60, 0);\n"
refused f08c "${F8M} 'pk' does not match its declaration in trait T2: one is generic, the other is not" "F8c: generic-ness" "${SN}trait T2 { fn pk<U>(self, u: U): i64; }\nimpl T2 for P { fn pk(self, u): i64 { return 1; } }\nfn f(q: *P): i64 { var o: dyn T2 = q; return 0; }\nsyscall(60, 0);\n"
refused f08d "${F8M} 'sh' does not match its declaration in trait T2: a variadic \`...\` differs" "F8d: a variadic \`...\`" "${SN}trait T2 { fn sh(self, ...): i64; }\nimpl T2 for P { fn sh(self, a): i64 { return 1; } }\nfn f(q: *P): i64 { var o: dyn T2 = q; return 0; }\nsyscall(60, 0);\n"
refused f08e "${F8M} 'sh' does not match its declaration in trait T2: its \`self\` is not P" "F8e: \`self: Q\` in an impl for P" "${SN}struct Q { a; }\ntrait T2 { fn sh(self): i64; }\nimpl T2 for P { fn sh(self: Q): i64 { return 1; } }\nfn f(q: *P): i64 { var o: dyn T2 = q; return 0; }\nsyscall(60, 0);\n"
refused f08f "cannot form dyn T2 from i64 - its method 'sh' does not match its declaration in trait T2: \`self: *T\` - the dyn of a scalar holds its value" "F8f: a scalar impl's \`self: *i64\`" "${SN}trait T2 { fn sh(self): i64; }\nimpl T2 for i64 { fn sh(self: *i64): i64 { return 1; } }\nfn f(): i64 { var n: i64 = 5; var o: dyn T2 = n; return 0; }\nsyscall(60, 0);\n"
refused f08g "${FN}'q' - a pointer to a scalar: the dyn of a scalar holds its value" "F8g: a \`q: *i64\` into a scalar impl" "${SN}fn f(q: *i64): i64 { var o: dyn Num = q; return 0; }\nsyscall(60, 0);\n"
refused f08h "${F8M} 'z' does not match its declaration in trait T2: the return type differs" "F8h: one report per pair — three forming sites in two fns, one error at the first" "${SN}trait T2 { fn sh(self): i64; fn z(self): i64; }\nimpl T2 for P { fn sh(self): i64 { return 1; } fn z(self): i32 { return 1; } }\nfn f(q: *P): i64 { var o: dyn T2 = q; var o2: dyn T2 = q; return 0; }\nfn h(q: *P): i64 { var o: dyn T2 = q; return 0; }\nsyscall(60, 0);\n"
# (review, 2026-10-10) The value class: a call through a dyn returns what the trait member declares
# (its prototype's flag), so a slot method returning a `: stack` pair under a member that declares one
# value is refused — `o.div(d)?` took the boxed lowering and dereferenced the tag (rc 139).
P10="does not match its declaration in trait Dv: it returns a \`: stack\` pair (a tag and a payload) where the trait declares one value"
SDV='include "lib/result.cyr"\nstruct Dn { x; y; }\n'
refused f08i "cannot form dyn Dv from Dn - its method 'div' ${P10}" "F8i: an untyped member whose impl returns \`Ok(..)\` / \`Err(..)\` (\`o.div(d)?\` dereferenced the tag)" "${SDV}trait Dv { fn div(self, d); }\nimpl Dv for Dn { fn div(self, d) { if (d == 0) { return Err(99); } return Ok(self.x / d); } }\nfn q(p: *Dn, d) { var o: dyn Dv = p; var v = o.div(d)?; return Ok(v + 1000); }\nsyscall(60, 0);\n"
refused f08j "cannot form dyn Dv from Dn - its method 'div' ${P10}" "F8j: a \`: i64\` member, the impl BELOW the forming site (its body read before pass 2 reaches it)" "${SDV}trait Dv { fn div(self, d): i64; }\nfn q(p: *Dn, d): i64 { var o: dyn Dv = p; var v = o.div(d); return v; }\nimpl Dv for Dn { fn div(self, d): i64 { return mkr(self.x, d); } }\nfn mkr(x, d) { if (d == 0) { return Err(99); } return Ok(x / d); }\nsyscall(60, 0);\n"
refused f09 "${F8M} 'sh' is \`#naked\` - a dyn calls its methods as plain fns" "F9: a \`#naked\` slot method" "${SN}trait T2 { fn sh(self): i64; }\nimpl T2 for P { #naked\nfn sh(self): i64 { asm { 0xC3; } } }\nfn f(q: *P): i64 { var o: dyn T2 = q; return 0; }\nsyscall(60, 0);\n"
mkdir -p "$T/f10"
printf 'private\ntrait Show { fn show(self): i64; }\npublic struct P { a; b; }\nimpl Show for P { fn show(self): i64 { return self.a; } }\n' > "$T/f10/a.cyr"
printf 'include "a.cyr"\nfn f(q: *P): i64 { var o: dyn Show = q; return 0; }\nsyscall(60, 0);\n' > "$T/f10/main.cyr"
rc=0; (cd "$T/f10" && timeout 60 "$CC" < main.cyr > m.bin 2> m.err) || rc=$?
if [ "$rc" -ne 0 ] && [ "$(grep -c '^error' "$T/f10/m.err")" -eq 1 ] && grep -qF "'P_show' is private to its file" "$T/f10/m.err"; then ok "F10: a slot method private to another file is refused at the forming site (the \`&f\` rule)"
else bad "F10: rc $rc: $(grep '^error' "$T/f10/m.err" | head -2 | tr '\n' '|')"; fi
TLM="a dyn formed at top level has no frame to be built in - form it inside a fn"
refused f11a "$TLM" "F11a: a top-level assignment \`o = &P0;\`" "${SN}var P0 = P { 1, 2 };\nvar Z: dyn Show = &P0;\nsyscall(1, 1, \"\", 0);\nZ = &P0;\nsyscall(60, 0);\n"
refused f11b "$TLM" "F11b: a top-level field store \`h.o = &P0;\`" "${SN}var P0 = P { 1, 2 };\nvar Z: dyn Show = &P0;\nvar ZH: H = H { 1, Z, 2 };\nsyscall(1, 1, \"\", 0);\nZH.o = &P0;\nsyscall(60, 0);\n"
refused f11c "$TLM" "F11c: a top-level argument \`tk(&P0)\`" "${SN}fn tk(o: dyn Show): i64 { return 0; }\nvar P0 = P { 1, 2 };\nsyscall(1, 1, \"\", 0);\ntk(&P0);\nsyscall(60, 0);\n"

# ── AL: the slot word's two 6.7.8 stamps held apart (the integration's merge fix) ──────────────────
# C2's slice bit (SLSLICE, depth-word bit 62) and this lane's declared-scalar validity bit (SLDSC) were
# merged on the SAME bit. Each unit below spells `dyn` (fn c), so every declared scalar is stamped.
AS='include "lib/slice.cyr"\ntrait Num { fn num(self): i64; }\nimpl Num for i64 { fn num(self): i64 { return self; } }\nfn c(): i64 { var o: dyn Num = 4; return o.num(); }\n'
SLA='fn a() { var s: [i64] = 0; return 0; }\n'
refused al1 "${FN}'s'${UT}" "AL1: a slice local as a dyn source is no declared scalar (aliased: \"no impl Num for cstring\", a stale name)" "${AS}fn b(): i64 { var s: [i64] = 0; var o: dyn Num = s; return 0; }\nsyscall(60, b());\n"
refused al2 "${FN}'s'${UT}" "AL2: ... in the slot a declared \`n: i64\` of another fn held (aliased: BUILT, the slice formed as that i64)" "${AS}fn a(): i64 { var z: i64 = 0; var n: i64 = 5; var o: dyn Num = n; return o.num(); }\nfn b(): i64 { var s: [i64] = 0; var o: dyn Num = s; return o.num(); }\nsyscall(60, a());\n"
exits al3 7 "AL3: \`y += 1\` on a declared \`y: i64\` parameter in a slice's old slot (aliased: refused as a slice)" "${AS}${SLA}fn b(x, y: i64): i64 { y += 1; return y; }\nsyscall(60, b(1, 6));\n"
refused al4 "cannot subscript 'y': it is not a typed array" "AL4: \`y[0]\` on that parameter (aliased: a slice read of &y, SIGSEGV)" "${AS}${SLA}fn b(x, y: i64): i64 { return y[0]; }\nsyscall(60, b(1, 6));\n"
refused al5 "no struct type in scope for 'y'" "AL5: \`y.len\` on that parameter (aliased: read the frame)" "${AS}${SLA}fn b(x, y: i64): i64 { return y.len; }\nsyscall(60, b(1, 6));\n"
exits al6 6 "AL6: \`n += 1\` on a declared \`var n: i32\` (aliased: its signed-narrow mark read as a slice width)" "${AS}fn b(): i64 { var n: i32 = 0 - 5; n += 1; return n + 10; }\nsyscall(60, b());\n"
refused al7 "no struct type in scope for 'n'" "AL7: \`n.len\` on a declared \`var n: i32\` (aliased: BUILT)" "${AS}fn b(): i64 { var n: i32 = 0 - 5; return n.len; }\nsyscall(60, b());\n"
refused al8 "cannot subscript 'n': it is not a typed array" "AL8: a closure subscripting a captured declared \`n: i64\` (aliased: the snapshot's bit read as a captured slice)" "${AS}fn b(): i64 { var n: i64 = 7; var k = || n[0]; return callptr(k); }\nsyscall(60, b());\n"
exits al9 48 "AL9: a real slice in a dyn unit still reads, writes and \`OP=\`s (anti-vacuous)" "${AS}fn b(): i64 { var w: i64[2]; w[0] = 4; w[1] = 5; var s: [i64] = 0; slice_set(&s, &w, 2); s[1] += 1; return s[0] * 10 + s[1] + s.len; }\nsyscall(60, b());\n"
# AL10-AL14 (review) — a closure body (and an inline generic instance) reuses the frame slots from 0; the
# snapshot put the enclosing slot's bit 63 back but not its `_dsc_tn` name, so a declared scalar of the
# body in that slot decided the enclosing one's dyn. AL10 is the reporter's program verbatim; AL11 its
# refusal variant (the closure's `cstring` in x's slot). The AX block runs each on aarch64, cx and PE.
NM='trait Num { fn num(self): i64; }\nimpl Num for i64 { fn num(self): i64 { return self + 1000; } }\n'
NU='impl Num for u8 { fn num(self): i64 { return self + 3000; } }\n'
exits al10 5 "AL10: a closure's \`var y: u8\` in the slot of a declared \`x: i64\`, then \`var o: dyn Num = x;\` (it took \`impl Num for u8\`: 213)" "include \"lib/fnptr.cyr\";\n${NM}${NU}fn main(): i64 {\n    var x: i64 = 5;\n    var f = || { var y: u8 = 3; return y; };\n    var o: dyn Num = x;\n    return o.num() - 1000 + fncall0(f) - 3;\n}\nsyscall(60, main());\n"
exits al11 5 "AL11: ... a closure's \`var s: cstring\` there (refused: \"no impl Num for cstring\" at a declared \`i64\`)" "include \"lib/fnptr.cyr\";\n${NM}fn main(): i64 {\n    var x: i64 = 5;\n    var f = || { var s: cstring = \"ab\"; return 0; };\n    var o: dyn Num = x;\n    return o.num() - 1000 + fncall0(f);\n}\nsyscall(60, main());\n"
exits al12 5 "AL12: an inline generic instance's (\`g(p)\`, T = a struct) \`var s: u8\` in x's slot (213)" "${NM}${NU}struct Pt { x; y; }\nfn g<T>(a: T): i64 { var s: u8 = 3; return a.x + s; }\nfn main(): i64 {\n    var w0 = 0; var w1 = 0; var w2 = 0;\n    var x: i64 = 5;\n    var p = Pt { 0, 0 };\n    var r = g(p);\n    var o: dyn Num = x;\n    return o.num() - 1000 + r - 3 + w0 + w1 + w2;\n}\nsyscall(60, main());\n"
exits al13 5 "AL13: ... its \`var s: cstring\` there (refused at a declared \`i64\`)" "${NM}struct Pt { x; y; }\nfn g<T>(a: T): i64 { var s: cstring = \"ab\"; return a.x; }\nfn main(): i64 {\n    var w0 = 0; var w1 = 0; var w2 = 0;\n    var x: i64 = 5;\n    var p = Pt { 0, 0 };\n    var r = g(p);\n    var o: dyn Num = x;\n    return o.num() - 1000 + r + w0 + w1 + w2;\n}\nsyscall(60, main());\n"
exits al14 5 "AL14: a closure nested in a closure, each forming from its own declared scalar (165)" "include \"lib/fnptr.cyr\";\n${NM}${NU}fn main(): i64 {\n    var x: i64 = 5;\n    var f = || { var y: u8 = 3; var p: dyn Num = y; return p.num(); };\n    var o: dyn Num = x;\n    var g = || {\n        var z: i64 = 7;\n        var h = || { var q: u8 = 1; return q; };\n        var oz: dyn Num = z;\n        return oz.num() + fncall0(h);\n    };\n    return o.num() - 1000 + fncall0(f) - 3003 + fncall0(g) - 1008;\n}\nsyscall(60, main());\n"

# ── K: a declaration-zone dyn in a `kernel;` build ─────────────────────────────────────────────────────
printf '%b' "kernel;\n${SH}struct W { o: dyn Show; }\nvar P0 = P { 1, 2 };\nvar KD: dyn Show = &P0;\nfn dk(o: dyn Show): i64 { var w: W = W { o }; return callptr(load64(load64(&w + 8)), load64(&w)); }\nfn main(): i64 {\n    var o: dyn Show = &P0;\n    return dk(o) + 40;\n}\nsyscall(60, main());\n" > "$T/k01.cyr"
rc=0; CYRIUS_ELF64_KERNEL=1 timeout 60 "$CC" < "$T/k01.cyr" > "$T/k01.bin" 2> "$T/k01.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "K: the ELF64 kernel build failed: $(grep -m1 '^error' "$T/k01.err")"
else chmod +x "$T/k01.bin"; got=0; timeout 10 "$T/k01.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -ne 41 ]; then bad "K: the kernel program exits $got, want 41 (its own forming)"
    elif [ "$(grep -c 'in a kernel build the initializer of' "$T/k01.err")" -ne 1 ] || ! grep -q "in a kernel build the initializer of 'KD'" "$T/k01.err"; then bad "K: want exactly one late-initializer warning, for KD: $(grep warning "$T/k01.err" | head -2 | tr '\n' '|')"
    else ok "K: a kernel build names the zone dyn KD late; the program's own forming runs (exit 41)"; fi
fi

# ── PF: a parenthesised FORM source at every destination ───────────────────────────────────────────
exits pf 42 "PF: \`((&p))\` / \`(q)\` as a local, a zone and a post-statement global, an assignment, a field, an argument, a return" "${SH}struct W { o: dyn Show; }\nstruct H2 { a; o: dyn Show; }\nfn dk(o: dyn Show): i64 { var w: W = W { o }; return callptr(load64(load64(&w + 8)), load64(&w)); }\nfn rt(q: *P): dyn Show { return ((q)); }\nvar P0 = P { 3, 4 };\nvar Z: dyn Show = ((&P0));\nfn f(): i64 {\n    var p = P { 5, 6 };\n    var o: dyn Show = ((&p));\n    if (dk(o) != 5) { return 1; }\n    o = (&P0);\n    if (dk(o) != 3) { return 2; }\n    var h = H2 { 1, o };\n    h.o = ((&p));\n    if (dk(h.o) != 5) { return 3; }\n    if (dk(((&p))) != 5) { return 4; }\n    if (dk(rt(&p)) != 5) { return 5; }\n    if (dk(Z) != 3) { return 6; }\n    return 42;\n}\nsyscall(1, 1, \"\", 0);\nvar G: dyn Show = ((&P0));\nif (dk(G) != 3) { syscall(60, 7); }\nsyscall(60, f());\n"

# ── C: the call through a dyn (D6) — every refusal once, at the method's name, the call consumed ─────
SC6='trait Show { fn show(self): i64; fn pick<U>(self, u: U): i64; fn nos(): i64; fn tself(self: i64): i64; fn va(self, ...): i64; fn two(self): (i64, i64); fn vec(self): f64v2; fn add(self, k): i64; fn me(self): dyn Show; fn big(self): Big; }\nstruct Big { a; b; c; }\nstruct P { a; b; }\nimpl Show for P { fn show(self): i64 { return self.a; } fn pick<U>(self, u: U): i64 { return 1; } fn nos(): i64 { return 2; } fn tself(self: i64): i64 { return 3; } fn va(self, ...): i64 { return 4; } fn two(self): (i64, i64) { return (1, 2); } fn vec(self): f64v2 { var v: f64v2; return v; } fn add(self, k): i64 { return k; } fn me(self): dyn Show { return self; } fn big(self): Big { var g = Big { 1, 2, 3 }; return g; } }\ntrait Num { fn num(self): i64; }\nimpl Num for i64 { fn num(self): i64 { return self; } }\nfn g(x): i64 { return x; }\n'
CF='fn f(o: dyn Show): i64 { '
CE=' }\nsyscall(60, 0);\n'
CT="${SC6}var P0 = P { 5, 6 };\nvar Z: dyn Show = &P0;\n"
refused c01a "trait Show declares no method 'nope' - a dyn Show calls only the methods its trait declares" "C1a: a member the trait does not declare" "${SC6}${CF}return o.nope(1);${CE}"
refused c01b "trait Show declares no method 'nope'" "C1b: ... a chain on the refused call is consumed (one report)" "${SC6}${CF}return o.nope().show();${CE}"
refused c01c "trait Show declares no method 'nope'" "C1c: ... a dyn argument of the refused call is not read as a value (one report)" "${SC6}${CF}return o.nope(o);${CE}"
refused c02 "'pick' is generic - a call through a dyn Show has no instance of it to run: call it on the concrete type" "C2: a generic member (decision 3)" "${SC6}${CF}return o.pick(5);${CE}"
C3M="takes no untyped \`self\` first - a call through a dyn Show passes its data word as an untyped \`self\`"
refused c03a "'nos' $C3M" "C3a: a member with no \`self\`" "${SC6}${CF}return o.nos();${CE}"
refused c03b "'tself' $C3M" "C3b: a member whose \`self\` is typed (\`self: i64\`)" "${SC6}${CF}return o.tself();${CE}"
refused c04 "'va' is variadic - a call through a dyn Show passes a fixed argument list" "C4: a variadic member" "${SC6}${CF}return o.va(1, 2);${CE}"
C5M="- a call through a dyn Show returns one value - an integer, a float, a pointer or a struct"
refused c05a "'two' returns multiple values $C5M" "C5a: a multi-value member, destructured (\`var a, b = o.two();\`)" "${SC6}${CF}var a, b = o.two(); return a;${CE}"
refused c05b "'two' returns multiple values $C5M" "C5b: ... as a statement" "${SC6}${CF}o.two(); return 0;${CE}"
refused c05c "'vec' returns a vector $C5M" "C5c: a member returning a vector" "${SC6}${CF}o.vec(); return 0;${CE}"
refused c06 "named arguments need a direct call - a call through a dyn Show passes arguments by position" "C6: a named argument" "${SC6}${CF}return o.add(k: 5);${CE}"
refused c07a "'dyn Show.add' expects 2 arguments, got 3" "C7a: too many arguments (\`self\` counted, as a method call counts it)" "${SC6}${CF}return o.add(5, 6);${CE}"
refused c07b "'dyn Show.add' expects 2 arguments, got 1" "C7b: too few" "${SC6}${CF}return o.add();${CE}"
refused c08a "a dyn Show result $RV" "C8a (V4): a call through a dyn returning a dyn, used as a value (\`o.me() + 1\`)" "${SC6}${CF}return o.me() + 1;${CE}"
refused c08b "a dyn Show result $RV" "C8b (V4): ... as an untyped argument" "${SC6}${CF}return g(o.me());${CE}"
refused c08c "multi-value destructure of a dyn Show 'dyn Show.me' result - a dyn is one value" "C8c (V6): ... destructured" "${SC6}${CF}var a, b = o.me(); return a;${CE}"
refused c08d "cannot form dyn Num from this expression" "C8d (F5): a call through a dyn returning an i64 as a forming source" "${SC6}${CF}var n: dyn Num = o.show(); return 0;${CE}"
TLS="returns a struct by value, and a struct result needs storage in a fn's frame"
refused c09a "'dyn Show.me' $TLS" "C9a: a 16 B result at top level into a global after the first statement (one report, not also \"not a dyn\")" "${CT}syscall(1, 1, \"\", 0);\nvar G2: dyn Show = Z.me();\nsyscall(60, 0);\n"
refused c09b "'dyn Show.me' $TLS" "C9b: ... into a declaration-zone global (the replay stored the data word alone: a SIGSEGV)" "${CT}var Z2: dyn Show = Z.me();\nsyscall(60, 0);\n"
refused c09c "'dyn Show.big' $TLS" "C9c: a 24 B (retptr) result at top level" "${CT}syscall(1, 1, \"\", 0);\nvar b = Z.big();\nsyscall(60, 0);\n"
refused c09d "'dyn Show.me' $TLS" "C9d: a chain on a 16 B result at top level" "${CT}syscall(1, 1, \"\", 0);\nvar x = Z.me().show();\nsyscall(60, x);\n"
exits c10 42 "C10: a call at top level and in a zone initialiser (the indirect call's micro-frame), nested, as a statement" "${CT}var ZN = Z.add(Z.show());\nsyscall(1, 1, \"\", 0);\nZ.show();\nvar k = Z.add(Z.add(36));\nif (ZN != 5) { syscall(60, 1); }\nsyscall(60, k + Z.show() + 1);\n"
# (review, 2026-10-10) C11 — a call through a dyn returns the trait member's VALUE CLASS, as a direct call
# returns its fn's: a `: Result` member's pair is refused into one name (it kept the tag), and a
# one-value member's result into a destructure (b took a stale register: 77 / 1).
SPR='include "lib/result.cyr"\ntrait Dv { fn div(self, d): Result; fn fi(self, n): i64; }\nstruct Dn { x; y; }\nimpl Dv for Dn { fn div(self, d): Result { if (d == 0) { return Err(99); } return Ok(self.x / d); } fn fi(self, n): i64 { return self.x + n; } }\nfn mk2(): (i64, i64) { return (100, 77); }\n'
BB="a \`: stack\` enum returns two values — bind both"
DT="multi-value destructure binds 2 names, but 'dyn Dv.fi' returns 1 value"
refused c11a "$BB" "C11a: \`var v = o.div(3);\` on a \`: Result\` member" "${SPR}fn f(p: *Dn): i64 { var o: dyn Dv = p; var v = o.div(3); return v; }\nsyscall(60, 0);\n"
refused c11b "$BB" "C11b: \`v = o.div(3);\`" "${SPR}fn f(p: *Dn): i64 { var o: dyn Dv = p; var v = 0; v = o.div(3); return v; }\nsyscall(60, 0);\n"
refused c11c "$DT" "C11c: \`var a, b = o.fi(1);\` on a \`: i64\` member" "${SPR}fn f(p: *Dn): i64 { var o: dyn Dv = p; var x, y = mk2(); var a, b = o.fi(1); return b; }\nsyscall(60, 0);\n"
refused c11d "$DT" "C11d: \`a, b = o.fi(1);\`" "${SPR}fn f(p: *Dn): i64 { var o: dyn Dv = p; var a = 0; var b = 0; a, b = o.fi(1); return b; }\nsyscall(60, 0);\n"
refused c11e "$DT" "C11e: a declaration-zone \`var za, zb = TK.fi(1);\`" "${SPR}var GD = Dn { 3, 0 };\nvar TK: dyn Dv = &GD;\nvar za, zb = TK.fi(1);\nsyscall(60, zb);\n"
exits c11f 42 "C11f: \`o.div(d)?\` and \`wrap(p, d)?\` above a wrapper \`return o.div(d);\` (rc 139: the tag dereferenced)" "${SPR}fn uz(p: *Dn, d) { var v = wrap(p, d)?; return Ok(v + 1); }\nfn q(p: *Dn, d) { var o: dyn Dv = p; var v = o.div(d)?; return Ok(v + 1000); }\nfn wrap(p: *Dn, d) { var o: dyn Dv = p; return o.div(d); }\nfn main(): i64 {\n    var p = Dn { 12, 0 };\n    var g, h = q(&p, 4);\n    if (g != 0 || h != 1003) { return 1; }\n    var i, j = q(&p, 0);\n    if (i == 0 || j != 99) { return 2; }\n    var k, l = uz(&p, 3);\n    if (k != 0 || l != 5) { return 3; }\n    var m, n = uz(&p, 0);\n    if (m == 0 || n != 99) { return 4; }\n    return 42;\n}\nsyscall(60, main());\n"

# ── PD: every destination of a call through a dyn takes its dyn result whole; a `*T` result forms ────
PD='trait Show { fn show(self): i64; fn me(self): dyn Show; fn pp(self): *P; }\nstruct P { a; b; }\nimpl Show for P { fn show(self): i64 { return self.a * 10 + self.b; } fn me(self): dyn Show { return self; } fn pp(self): *P { return self; } }\nstruct H { a; o: dyn Show; b; }\nfn take(k, o: dyn Show, j): i64 { return k * 1000 + o.show() * 10 + j; }\nfn rme(o: dyn Show): dyn Show { return o.me(); }\nfn rmw(o: dyn Show): dyn Show { return (o.me()); }\nfn rmd(o: dyn Show): dyn Show {\n    defer { syscall(1, 1, "", 0); }\n    return o.me();\n}\nfn main(): i64 {\n    var p = P { 4, 9 };\n    var q = P { 1, 2 };\n    var o: dyn Show = &p;\n    var y1: dyn Show = o.me();\n    if (y1.show() != 49) { return 1; }\n    var y2: dyn Show = (o.me());\n    if (y2.show() != 49) { return 2; }\n    var y3 = o.me();\n    if (y3.show() != 49) { return 3; }\n    var z: dyn Show = &q;\n    z = o.me();\n    if (z.show() != 49) { return 4; }\n    z = &q;\n    z = (o.me());\n    if (z.show() != 49) { return 5; }\n    var h = H { 7, z, 8 };\n    h.o = &q;\n    h.o = o.me();\n    if (h.o.show() != 49) { return 6; }\n    h.o = &q;\n    h.o = (o.me());\n    if (h.o.show() + h.a * 1000 + h.b * 100 != 7849) { return 7; }\n    if (take(3, o.me(), 5) != 3495) { return 8; }\n    if (take(3, (o.me()), 5) != 3495) { return 9; }\n    var h2 = H { 6, o.me(), 2 };\n    if (h2.o.show() + h2.a * 1000 + h2.b * 100 != 6249) { return 10; }\n    if (rme(o).show() != 49) { return 11; }\n    if (rmw(o).show() != 49) { return 12; }\n    if (rmd(o).show() != 49) { return 13; }\n    var f1: dyn Show = o.pp();\n    if (f1.show() != 49) { return 14; }\n    var f2: dyn Show = (o.pp());\n    if (f2.show() != 49) { return 15; }\n    f2 = q.pp();\n    if (f2.show() != 12) { return 16; }\n    return 42;\n}\nsyscall(60, main());\n'
exits pd 42 "PD1-PD16: a call through a dyn returning a dyn into a var (annotated, wrapped, inferred), an assignment (bare, wrapped), a field (bare, wrapped), an argument (bare, wrapped), a struct-literal element, a \`return\` (bare, wrapped, in a \`defer\` fn); one returning \`*P\` FORMS (the prototype types it)" "$PD"

# ── X / S / CG: what a prototype is not, and what the call is (D6) ─────────────────────────────────────
mkdir -p "$T/x4"
printf 'fn f(o: dyn Shw): i64 { return o.show(5) + o.other(o, 2); }\nsyscall(60, 0);\n' > "$T/x4/a.cyr"
rc=0; "$CC" --syntax-only < "$T/x4/a.cyr" > /dev/null 2> "$T/x4/a.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/x4/a.err"; then ok "X4a: --syntax-only, a dyn of a trait in a sibling file: its calls are silent"
else bad "X4a: rc $rc: $(grep '^error' "$T/x4/a.err" | head -1)"; fi
printf 'fn f(o: dyn Shw): i64 { return o.show(1 + ); }\nsyscall(60, 0);\n' > "$T/x4/b.cyr"
rc=0; "$CC" --syntax-only < "$T/x4/b.cyr" > /dev/null 2> "$T/x4/b.err" || rc=$?
if [ "$rc" -ne 0 ] && [ "$(grep -c '^error' "$T/x4/b.err")" -eq 1 ] && grep -qF "unexpected ')'" "$T/x4/b.err"; then ok "X4b: ... and a grammar error in such a call's arguments is still reported"
else bad "X4b: rc $rc: $(grep '^error' "$T/x4/b.err" | head -2 | tr '\n' '|')"; fi
S0='trait Show { fn show(self): i64; fn sq(self, k): i64; }\nstruct P { a; b; }\nimpl Show for P { fn show(self): i64 { return self.a * 10 + self.b; } fn sq(self, k): i64 { return k * k; } }\n'
printf '%b' "${S0}fn main(): i64 {\n    var p = P { 4, 9 };\n    var o: dyn Show = &p;\n    return o.show() + o.sq(2) + o.show() - 56;\n}\nsyscall(60, main());\n" > "$T/x5.cyr"
rc=0; CYRIUS_SYMS="$T/x5.syms" timeout 60 "$CC" < "$T/x5.cyr" > "$T/x5.bin" 2> "$T/x5.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "X5/S6/S7: rc $rc: $(grep '^error' "$T/x5.err" | head -1)"
else
    chmod +x "$T/x5.bin"; got=0; timeout 10 "$T/x5.bin" || got=$?
    [ "$got" -eq 46 ] && ok "X5a: three calls through a dyn, two members: exit 46" || bad "X5a: exit $got, want 46"
    if grep -q 'undefined function' "$T/x5.err"; then bad "X5b: a prototype is reported undefined: $(grep 'undefined' "$T/x5.err" | head -1)"
    else ok "X5b: no \"undefined function 'dyn Show.show'\" (a prototype's owner is the trait's file)"; fi
    if grep -q 'unreachable fns' "$T/x5.err"; then bad "S7: a fully reachable program notes unreachable fns (a prototype counted?): $(grep unreachable "$T/x5.err")"
    else ok "S7: no \`note: N unreachable fns\` for a fully reachable program (a prototype has no body to count)"; fi
    if [ -s "$T/x5.syms" ] && grep -q ' P_show$' "$T/x5.syms" && ! grep -q 'dyn' "$T/x5.syms"; then ok "S6: the CYRIUS_SYMS dump holds P_show and no prototype"
    else bad "S6: CYRIUS_SYMS: $(grep -c . "$T/x5.syms" 2>/dev/null) lines, $(grep 'dyn' "$T/x5.syms" 2>/dev/null | head -1)"; fi
    ff=$(od -An -tx1 -v "$T/x5.bin" | tr -s ' \n' '\n\n' | awk 'p == "ff" && $1 == "95" { n++ } { p = $1 } END { print n + 0 }')
    [ "$ff" -eq 3 ] && ok "CG1: x86 — each call is \`call [rbp+disp32]\` (ff 95): 3 for 3 calls" || bad "CG1: x86 holds $ff \`ff 95\`, want 3"
fi
if CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/x5.cyr" > "$T/x5.exe" 2> "$T/x5.werr" && [ -s "$T/x5.exe" ]; then
    ff=$(od -An -tx1 -v "$T/x5.exe" | tr -s ' \n' '\n\n' | awk 'p == "ff" && $1 == "95" { n++ } { p = $1 } END { print n + 0 }')
    an=$(od -An -tx1 -v "$T/x5.exe" | tr -s ' \n' '\n\n' | awk '{ w = w " " $1 } END { print w }' | { grep -o ' 53 48 89 e3 48 83 e4 f0' || true; } | wc -l)
    if [ "$ff" -eq 3 ] && [ "$an" -eq 0 ]; then ok "CG2: PE — the frame-slot \`call [rbp+disp32]\` (3), never ECALLPTR_PE's forced alignment (0 anchors)"
    else bad "CG2: PE holds $ff \`ff 95\` (want 3) and $an ECALLPTR_PE anchors (want 0)"; fi
else bad "CG2: the PE build failed: $(grep -m1 '^error' "$T/x5.werr")"; fi
printf '%b' "object;\n${S0}fn app_entry(): i64 {\n    var p = P { 4, 9 };\n    var o: dyn Show = &p;\n    return o.show();\n}\n" > "$T/s4.cyr"
rc=0; timeout 60 "$CC" < "$T/s4.cyr" > "$T/s4.o" 2> "$T/s4.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "S4: the object build failed: $(grep -m1 '^error' "$T/s4.err")"
elif ! command -v readelf > /dev/null 2>&1 || ! command -v ld > /dev/null 2>&1; then echo "  SKIP S4 — readelf / ld not installed"; skips=$((skips + 1))
else
    readelf -sW "$T/s4.o" > "$T/s4.syms" 2>&1
    lrc=0; ld -e app_entry -o "$T/s4.out" "$T/s4.o" > "$T/s4.ld" 2>&1 || lrc=$?
    if grep -q 'UND dyn Show.show$' "$T/s4.syms" && [ "$(grep -c 'dyn' "$T/s4.syms")" -eq 1 ] && [ "$lrc" -eq 0 ]; then ok "S4: \`object;\` — the prototype is one unreferenced UND symbol (\`dyn Show.show\`), and GNU ld links the object"
    else bad "S4: ld rc $lrc ($(head -1 "$T/s4.ld")); dyn symbols: $(grep 'dyn' "$T/s4.syms" | tr '\n' '|')"; fi
fi
printf '%b' "shared;\n${S0}fn app_entry(): i64 {\n    var p = P { 4, 9 };\n    var o: dyn Show = &p;\n    return o.show();\n}\n" > "$T/s5.cyr"
rc=0; timeout 60 "$CC" < "$T/s5.cyr" > "$T/s5.so" 2> "$T/s5.err" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$T/s5.so" ]; then bad "S5: the shared build failed: $(grep -m1 '^error' "$T/s5.err")"
elif grep -aq 'dyn Show' "$T/s5.so"; then bad "S5: \`shared;\` exports a \`dyn Show.*\` name"
elif ! grep -aq 'app_entry' "$T/s5.so"; then bad "S5: \`shared;\` lost its own export app_entry (the check is vacuous)"
else ok "S5: \`shared;\` exports app_entry and no prototype"; fi

# ── P: every destination of a dyn call result takes it whole ───────────────────────────────────────
# The value rows: each line returns its own code when the dyn it received is not (4, 9).
PB="${HP}struct Q { a; b; }\nimpl Q { fn mk(self, o: dyn Show): dyn Show { return o; } }\nfn take(k, o: dyn Show, j): i64 { return k * 1000 + dw(o) * 10 + j; }\nfn rw(o: dyn Show): dyn Show { return (pass(o)); }\nfn rd(o: dyn Show): dyn Show {\n    defer { syscall(1, 1, \"\", 0); }\n    return pass(o);\n}\nfn rr(o: dyn Show, k): dyn Show {\n    if (k > 0) { return rr(o, k - 1); }\n    return pass(o);\n}\n${FM}    var q = Q { 1, 2 };\n"
PL='    var y1: dyn Show = pass(o);\n    if (dw(y1) != 49) { return 1; }\n    var y2: dyn Show = (pass(o));\n    if (dw(y2) != 49) { return 2; }\n    var x3 = pass(o);\n    if (dw(x3) != 49) { return 3; }\n    var z: dyn Show = get(mkw(1, 2));\n    z = pass(o);\n    if (dw(z) != 49) { return 4; }\n    z = get(mkw(1, 2));\n    z = (pass(o));\n    if (dw(z) != 49) { return 5; }\n    var h: H = H { 7, get(mkw(1, 2)), 8 };\n    h.o = pass(o);\n    if (dw(h.o) != 49) { return 6; }\n    h.o = get(mkw(1, 2));\n    h.o = (pass(o));\n    if (dw(h.o) + h.a * 1000 + h.b * 100 != 7849) { return 7; }\n    if (take(3, pass(o), 5) != 3495) { return 8; }\n    if (take(3, (pass(o)), 5) != 3495) { return 9; }\n    var h2: H = H { 6, pass(o), 2 };\n    if (dw(h2.o) + h2.a * 1000 + h2.b * 100 != 6249) { return 10; }\n    var m1: dyn Show = q.mk(o);\n    if (dw(m1) != 49) { return 11; }\n    var m2: dyn Show = (q.mk(o));\n    if (dw(m2) != 49) { return 12; }\n    var m3 = q.mk(o);\n    if (dw(m3) != 49) { return 13; }\n    z = q.mk(o);\n    if (dw(z) != 49) { return 14; }\n    if (take(2, q.mk(o), 1) != 2491) { return 15; }\n    if (dw(rw(o)) != 49) { return 16; }\n    if (dw(rd(o)) != 49) { return 17; }\n    if (dw(rr(o, 3)) != 49) { return 18; }\n    if (dw(pass(pass(o))) != 49) { return 19; }\n    var c = || dw(o);\n    if (callptr(c) != 49) { return 20; }\n    secret var s: dyn Show = o;\n    if (dw(s) != 49) { return 21; }\n    return 42;\n'
exits p01 42 "P1-P21: var (annotated, wrapped, inferred), assignment (bare, wrapped), field store (bare, wrapped), argument (bare, wrapped), struct-literal element, a method result (var / wrapped / inferred / assignment / argument), return (wrapped, non-tail in a \`defer\` fn, after a tail call), a nested call, a closure capture, \`secret var\` — each takes the dyn whole" "${PB}${PL}${ME}"

# ── H28: the fold, across a newline and a comment; the caret on `dyn` ───────────────────────────────
exits h28a 49 "H28a: \`dyn\` and its trait split across a newline and a comment fold to one type" "${HP}fn k(o: dyn\n    # a comment\n    Show): i64 { return dw(o); }\n${FM}    return k(o);\n${ME}"
printf '%b' "${SH}fn f(o: dyn\n    Nope): i64 { return 0; }\nsyscall(60, 0);\n" > "$T/h28b.cyr"
build h28b
cl=$(grep -A2 '^error' "$T/h28b.err" | sed -n 3p)
if [ "$rc" -ne 0 ] && grep -qF "error:<source>:4:9: 'Nope' is not a trait" "$T/h28b.err" && [ "$cl" = "            ^" ]; then ok "H28b: a diagnostic on a folded \`dyn Nope\` points at \`dyn\` (4:9, the caret under it)"
else bad "H28b: rc $rc: $(head -3 "$T/h28b.err" | tr '\n' '|')"; fi
exits h28c 7 "H28c: a unit spelling no \`dyn\` folds nothing (\`dynamo\` stays a name)" 'fn f(): i64 { var dynamo = 7; return dynamo; }\nsyscall(60, f());\n'

# ── X: --syntax-only (cyrius lint's pre-pass) ──────────────────────────────────────────────────────
printf '%b' "${SH}fn f(o: dyn Nope, v: *dyn Show): i64 { var u: dyn Show; return 0; }\nsyscall(60, 0);\n" > "$T/x01.cyr"
rc=0; "$CC" --syntax-only < "$T/x01.cyr" > /dev/null 2> "$T/x01.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/x01.err"; then ok "X1: --syntax-only reports no dyn refusal (T1 / T5 / U1 resolve types)"
else bad "X1: --syntax-only rc $rc: $(grep '^error' "$T/x01.err" | head -1)"; fi
printf 'fn f(): i64 { var dyn = 5; return 0; }\nsyscall(60, f());\n' > "$T/x02.cyr"
rc=0; "$CC" --syntax-only < "$T/x02.cyr" > /dev/null 2> "$T/x02.err" || rc=$?
if [ "$rc" -ne 0 ] && grep -qF "$KW" "$T/x02.err"; then ok "X2: --syntax-only still reports \`var dyn\` (the reserved word is grammar)"
else bad "X2: --syntax-only rc $rc: $(head -1 "$T/x02.err")"; fi

printf '%b' "${SN}fn f(x): i64 { var o: dyn Num = x; var p = P { 1, 2 }; var o2: dyn Show = p; var o3: dyn Show = 5; return 0; }\nsyscall(60, 0);\n" > "$T/x03.cyr"
rc=0; "$CC" --syntax-only < "$T/x03.cyr" > /dev/null 2> "$T/x03.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/x03.err"; then ok "X3: --syntax-only reports no forming refusal (F1 / F2 / F6 resolve names and impls)"
else bad "X3: --syntax-only rc $rc: $(grep '^error' "$T/x03.err" | head -1)"; fi

# ── TT: the tools ──────────────────────────────────────────────────────────────────────────────────
if awk '/^fn _embed_reserved_list\(/,/^}/' cbt/manifest.cyr | grep -q ' dyn '; then ok "TT1: \`[embed]\`'s reserved list holds \`dyn\` (embed_manifest_refusals.sh axis 5 checks it against the compiler)"
else bad "TT1: cbt/manifest.cyr _embed_reserved_list lacks dyn"; fi
if grep -q '|trait|const|dyn)' editors/vscode/syntaxes/cyrius.tmLanguage.json; then ok "TT2: the VS Code grammar lists \`dyn\` as a keyword"
else bad "TT2: editors/vscode/syntaxes/cyrius.tmLanguage.json lacks dyn"; fi
mkdir -p "$T/tl" "$T/tl/home"
printf 'trait Show { fn show(self): i64; }\nfn f(o: dyn Show): i64 { return 0; }\nvar dynamo = 1;\n' > "$T/tl/st.cyr"
if "$CC" < programs/cyrius-lsp.cyr > "$T/tl/lsp" 2> "$T/tl/lsp.err" && [ "$(wc -c < "$T/tl/lsp")" -gt 20000 ]; then
    chmod +x "$T/tl/lsp"
    lsp_frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c | tr -d ' ')" "$1"; }
    { lsp_frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
      lsp_frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file://'"$T/tl/st.cyr"'","languageId":"cyrius","version":1,"text":""}}}'
      lsp_frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/semanticTokens/full","params":{"textDocument":{"uri":"file://'"$T/tl/st.cyr"'"}}}'
      lsp_frame '{"jsonrpc":"2.0","id":99,"method":"shutdown"}'; } > "$T/tl/lsp.in"
    (cd "$T/tl" && PATH=/usr/bin:/bin HOME="$T/tl/home" timeout 30 ./lsp < lsp.in > lsp.out 2> lsp.run.err) || :
    grep -o '"id":2,"result":{"data":\[[0-9,]*\]' "$T/tl/lsp.out" | sed 's/.*\[//; s/\]$//' | tr ',' '\n' | \
        awk 'NF { a[n++] = $1 } END { l = 0; c = 0; for (i = 0; i + 4 < n; i += 5) { if (a[i] > 0) { l += a[i]; c = a[i + 1] } else { c += a[i + 1] }; print l ":" c ":" a[i + 2] ":" a[i + 3] } }' > "$T/tl/st.tok"
    if grep -qx '1:8:3:5' "$T/tl/st.tok" && ! grep -q '^2:4:6:5$' "$T/tl/st.tok"; then ok "TT3: cyrius-lsp colours \`dyn\` a keyword (1:8, type 5), \`dynamo\` not"
    else bad "TT3: cyrius-lsp semantic tokens: $(tr '\n' ' ' < "$T/tl/st.tok")"; fi
else bad "TT3: could not build programs/cyrius-lsp.cyr: $(head -1 "$T/tl/lsp.err")"; fi

# ── TT (D7): the source tools on a dyn sample; the guide's dyn examples run ─────────────────────────
# Each tool is built HERE from this tree's source with $CC (a mutant's source builds a mutant's tool),
# and the sample first compiles and runs — it is real dyn source, not a tool's guess at it. No tool
# learned `dyn`: they read text, and `dyn Area` is a type with a space in it (the rows pin that).
mkdir -p "$T/tt/w" "$T/tt/hh" "$T/tt/lh/bin" "$T/tt/ap/src" "$T/tt/ta/lib"
cat > "$T/tt/w/ds.cyr" <<'EOF'
# A shape that has an area.
trait Area {
    fn area(self): i64;
    fn twice(self): i64 { return self.area() * 2; }
}

struct Sq { s; }

impl Area for Sq {
    fn area(self): i64 { return self.s * self.s; }
}

# The sum of two shapes' areas, each called through its vtable.
fn total(a: dyn Area, b: dyn Area): i64 {
    return a.area() + b.twice();
}

# A square seen as an Area: the dyn holds `q`, not a copy.
fn as_area(q: *Sq): dyn Area {
    var o: dyn Area = q;
    return o;
}

# The area of `o` plus `k`.
fn f(o: dyn Area, k): i64 { return o.area() + k; }

fn main(): i64 {
    var q = Sq { 3 };
    var r = Sq { 4 };
    var a: dyn Area = &q;
    var b: dyn Area = as_area(&r);
    return total(a, b) + f(a, 1) - 10;
}
syscall(60, main());
EOF
# A file whose dyn's trait and type live in a sibling (a manifest prepends it): lint sees this alone.
cat > "$T/tt/w/sib.cyr" <<'EOF'
# The sum of two areas.
fn total2(a: dyn Area, b: dyn Area): i64 {
    return a.area() + b.twice();
}

# A square seen as an Area.
fn mk(q: *Sq): dyn Area {
    var o: dyn Area = q;
    return o;
}
EOF
ttool() {   # <name> <source, from the tree root>: built with $CC into $T/tt/<name>
    rc=0; "$CC" < "$ROOT/$2" > "$T/tt/$1" 2> "$T/tt/$1.err" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$T/tt/$1" ]; then bad "TT: $2 does not build: $(grep '^error' "$T/tt/$1.err" | head -1)"; return 1; fi
    chmod +x "$T/tt/$1"
}
rc=0; ( cd "$T/tt/w" && timeout 60 "$CC" < ds.cyr > ds.bin 2> ds.err ) || rc=$?
got=-1; if [ "$rc" -eq 0 ]; then chmod +x "$T/tt/w/ds.bin"; got=0; timeout 10 "$T/tt/w/ds.bin" || got=$?; fi
if [ "$rc" -ne 0 ] || [ "$got" -ne 41 ] || grep -q 'warning' "$T/tt/w/ds.err"; then
    bad "TT: the dyn sample: rc $rc, exit $got (want 41, no warning): $(grep '^error\|warning' "$T/tt/w/ds.err" | head -1)"
else
    # TT4: `cyrius header` — a dyn parameter is ONE `cyr_val` (it travels by address, as every struct
    # over 8 bytes does); its type, with the space in it, is skipped whole to the parameter's `,`. A
    # trait member and an impl method are not FFI surface (brace depth), nor is `main`. A dyn RETURN
    # is the {data, vtable} pair, `cyr_val2` (6.7.11: it printed `cyr_val as_area(..)`, the vtable
    # lost — issues/archived/2026-10-10-cyrius-header-ignores-struct-returns.md).
    if ttool cyrius cbt/cyrius.cyr; then
        rc=0; ( cd "$T/tt/w" && CYRIUS_HOME="$T/tt/hh" HOME="$T/tt/hh" timeout 60 "$T/tt/cyrius" header ds.cyr > "$T/tt/hdr.out" 2>&1 ) || rc=$?
        miss=""
        for l in 'cyr_val total(cyr_val a, cyr_val b);' 'cyr_val2 as_area(cyr_val q);   /* returns dyn Area, 16 B */' 'cyr_val f(cyr_val o, cyr_val k);'; do
            grep -qxF "$l" "$T/tt/hdr.out" || miss="$miss [$l]"
        done
        n=$(grep -cE '^cyr_val2? ' "$T/tt/hdr.out" || true)
        if [ "$rc" -eq 0 ] && [ -z "$miss" ] && [ "$n" -eq 3 ]; then ok "TT4: cyrius header: \`fn f(o: dyn Area, k)\` is \`cyr_val f(cyr_val o, cyr_val k);\`, \`as_area(..): dyn Area\` the pair \`cyr_val2\` (3 prototypes, no trait member / impl method)"
        else bad "TT4: cyrius header rc $rc, $n prototype(s); missing:$miss; got: $(grep -E '^cyr_val2? ' "$T/tt/hdr.out" | tr '\n' '|')"; fi
    fi
    # TT5: cyrfmt has no type rule — the sample and the crossos dyn file are canonical as written.
    if ttool cyrfmt programs/cyrfmt.cyr; then
        rc=0; "$T/tt/cyrfmt" --check "$T/tt/w/ds.cyr" > "$T/tt/fmt.out" 2>&1 || rc=$?
        rc2=0; "$T/tt/cyrfmt" --check "$ROOT/tests/tcyr/crossos/dyn_objects.tcyr" >> "$T/tt/fmt.out" 2>&1 || rc2=$?
        if [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ]; then ok "TT5: cyrfmt --check: the dyn sample and crossos/dyn_objects.tcyr are canonical"
        else bad "TT5: cyrfmt --check rc $rc / $rc2: $(head -2 "$T/tt/fmt.out" | tr '\n' '|')"; fi
    fi
    # TT6: `cyrius lint` (its --syntax-only pre-pass, then cyrlint) — the sample, and a file whose dyn's
    # trait lives in a sibling (silent: the pre-pass resolves no names). The wrapper runs the cycc
    # BESIDE it, so this compiler is copied next to it.
    if [ -x "$T/tt/cyrius" ] && ttool cyrlint programs/cyrlint.cyr; then
        cp "$CC" "$T/tt/lh/bin/cycc"; cp "$T/tt/cyrius" "$T/tt/cyrlint" "$T/tt/lh/bin/"
        for x in ds sib; do
            rc=0; ( cd "$T/tt/w" && CYRIUS_HOME="$T/tt/lh" HOME="$T/tt/lh" timeout 120 "$T/tt/lh/bin/cyrius" lint "$x.cyr" > "$T/tt/l$x.out" 2> "$T/tt/l$x.err" ) || rc=$?
            if [ "$rc" -eq 0 ] && grep -qx '0 warnings' "$T/tt/l$x.out" && [ -z "$(grep -v '^0 untracked deferrals$' "$T/tt/l$x.err")" ]; then ok "TT6 ($x): cyrius lint: rc 0, 0 warnings, nothing else said"
            else bad "TT6 ($x): cyrius lint rc $rc: $(cat "$T/tt/l$x.err" "$T/tt/l$x.out" | grep -v '^===' | head -2 | tr '\n' '|')"; fi
        done
    elif [ ! -x "$T/tt/cyrius" ]; then bad "TT6: no cyrius CLI (TT4 did not build it)"; fi
    # TT7: cyrdoc — each signature verbatim, a dyn parameter and a dyn return included, with its doc.
    if ttool cyrdoc programs/cyrdoc.cyr; then
        rc=0; ( cd "$T/tt/w" && timeout 20 "$T/tt/cyrdoc" ds.cyr ) > "$T/tt/doc.out" 2>&1 || rc=$?
        miss=""
        for l in '### `fn total(a: dyn Area, b: dyn Area): i64`' "The sum of two shapes' areas, each called through its vtable." '### `fn as_area(q: *Sq): dyn Area`' '### `fn f(o: dyn Area, k): i64`'; do
            grep -qxF "$l" "$T/tt/doc.out" || miss="$miss [$l]"
        done
        if [ "$rc" -eq 0 ] && [ -z "$miss" ]; then ok "TT7: cyrdoc: the dyn signatures verbatim, with their docs"
        else bad "TT7: cyrdoc rc $rc; missing:$miss"; fi
    fi
    # TT8: api-surface — a dyn parameter is one parameter (`f/2`, `total/2`).
    cp "$T/tt/w/ds.cyr" "$T/tt/ap/src/ds.cyr"
    if ttool api programs/cyrius_api_surface.cyr; then
        rc=0; ( cd "$T/tt/ap" && timeout 20 "$T/tt/api" --update --scope=project --snapshot="$T/tt/A.snap" ) > "$T/tt/api.out" 2>&1 || rc=$?
        got=$(grep '^ds::' "$T/tt/A.snap" 2> /dev/null | tr '\n' ' ')
        if [ "$rc" -eq 0 ] && [ "$got" = 'ds::as_area/1 ds::f/2 ds::main/0 ds::total/2 ' ]; then ok "TT8: api-surface: a dyn parameter is one (ds::f/2, ds::total/2)"
        else bad "TT8: api-surface rc $rc: got '$got'"; fi
    fi
    # TT9: type-audit — `fn as_area(..): dyn Area` is annotated (every fn of the sample is).
    cp "$T/tt/w/ds.cyr" "$T/tt/ta/lib/ds.cyr"
    if ttool tau programs/cyrius_type_audit.cyr; then
        rc=0; ( cd "$T/tt/ta" && timeout 20 "$T/tt/tau" --module=ds > "$T/tt/ta.out" 2> "$T/tt/ta.err" ) || rc=$?
        if [ "$rc" -eq 0 ] && grep -q '^  ds: 7/7 annotated' "$T/tt/ta.out" "$T/tt/ta.err" && ! grep -q '^  ds::' "$T/tt/ta.out"; then ok "TT9: type-audit: a \`: dyn Area\` return is annotated (7/7)"
        else bad "TT9: type-audit rc $rc: $(grep 'ds' "$T/tt/ta.out" "$T/tt/ta.err" | head -2 | tr '\n' '|')"; fi
    fi
fi
# TT10: the guide's dyn examples (docs/guides/cyrius-guide.md, "Trait objects: `dyn` (6.7.8)") compile
# with no warning and exit the value each one's `return` comment states (`# 9 + 10 + 20 = 39`) —
# guide_examples_compile.sh only compiles a block, so a stated value that is wrong would ship green
# there. Floor: the section's 3 examples.
awk -v out="$T/tt/gx" '
  /^```/ { if (infence) { infence = 0; next } infence = 1; lang = substr($0, 4); gsub(/[ \t\r]/, "", lang)
           want = insec && lang == "cyrius"; if (want) { nb++; f = out nb ".cyr"; printf "" > f } next }
  infence { if (want) print >> f; next }
  /^## / { insec = ($0 ~ /^## Trait objects: `dyn`/) }
' docs/guides/cyrius-guide.md
nb=0
while [ -s "$T/tt/gx$((nb + 1)).cyr" ]; do
    nb=$((nb + 1))
    w=$(grep -E '^[[:space:]]*return .*#.*= [0-9]+[[:space:]]*$' "$T/tt/gx$nb.cyr" | tail -1 | sed -E 's/.*= ([0-9]+)[[:space:]]*$/\1/')
    if [ -z "$w" ]; then bad "TT10: the guide's dyn example $nb states no value (a \`return ..; # .. = N\` line)"; continue; fi
    { printf 'include "lib/alloc.cyr"\ninclude "lib/vec.cyr"\n'; cat "$T/tt/gx$nb.cyr"; } > "$T/tt/gxp$nb.cyr"
    rc=0; timeout 60 "$CC" < "$T/tt/gxp$nb.cyr" > "$T/tt/gx$nb.bin" 2> "$T/tt/gx$nb.err" || rc=$?
    got=-1; if [ "$rc" -eq 0 ]; then chmod +x "$T/tt/gx$nb.bin"; got=0; timeout 10 "$T/tt/gx$nb.bin" || got=$?; fi
    if [ "$rc" -eq 0 ] && [ "$got" -eq "$w" ] && ! grep -q 'warning' "$T/tt/gx$nb.err"; then ok "TT10: the guide's dyn example $nb exits $w, the value its comment states"
    else bad "TT10: the guide's dyn example $nb: rc $rc, exit $got (its comment states $w; no warning wanted): $(grep '^error\|warning' "$T/tt/gx$nb.err" | head -1)"; fi
done
[ "$nb" -ge 3 ] || bad "TT10: the guide's dyn section yields $nb example(s) (floor 3) — the extractor or the section moved"

# ── A: the P program and (D6) the PD program on every backend ──────────────────────────────────────
printf '%b' "${PB}${PL}${ME}" > "$T/ap.cyr"
printf '%b' "$PD" > "$T/pd.cyr"
for mode in IR3 DCE; do
    if [ "$mode" = IR3 ]; then ev=CYRIUS_IR=3; else ev=CYRIUS_DCE=1; fi
    for pg in ap pd; do
        rc=0; env $ev "$CC" < "$T/$pg.cyr" > "$T/${pg}_$mode.bin" 2> "$T/${pg}_$mode.err" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "A $pg $mode: rc $rc: $(grep '^error' "$T/${pg}_$mode.err" | head -1)"
        else chmod +x "$T/${pg}_$mode.bin"; got=0; timeout 10 "$T/${pg}_$mode.bin" || got=$?
            [ "$got" -eq 42 ] && ok "A x86 $ev: the $pg program exits 42" || bad "A x86 $ev: the $pg program exits $got, want 42"; fi
    done
done
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        for pg in ap pd; do
            if "$T/cc_a64" < "$T/$pg.cyr" > "$T/$pg.a" 2> "$T/$pg.aerr"; then
                chmod +x "$T/$pg.a"; got=0; (cd "$T" && timeout 60 qemu-aarch64 "./$pg.a" > /dev/null 2>&1) || got=$?
                [ "$got" -eq 42 ] && ok "A aarch64 (qemu): the $pg program exits 42" || bad "A aarch64 (qemu): the $pg program exits $got, want 42"
            else bad "A aarch64: the $pg program did not compile: $(grep '^error' "$T/$pg.aerr" | head -1)"; fi
        done
    else bad "A aarch64: could not build src/main_aarch64.cyr"; fi
else echo "  SKIP A aarch64 — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$CC" < programs/cxvm.cyr > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    for pg in ap pd; do
        if "$T/cc_cx" < "$T/$pg.cyr" > "$T/$pg.cyx" 2> "$T/$pg.cxerr" && [ -s "$T/$pg.cyx" ]; then
            got=0; timeout 60 "$T/cxvm" < "$T/$pg.cyx" > /dev/null 2>&1 || got=$?
            [ "$got" -eq 42 ] && ok "A cx (cxvm): the $pg program exits 42" || bad "A cx (cxvm): the $pg program exits $got, want 42"
        else bad "A cx: the $pg program did not compile: $(grep '^error' "$T/$pg.cxerr" | head -1)"; fi
    done
else bad "A cx: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
if command -v wine > /dev/null 2>&1; then
    for pg in ap pd; do
        if CYRIUS_TARGET_WIN=1 "$CC" < "$T/$pg.cyr" > "$T/$pg.exe" 2> "$T/$pg.werr" && [ -s "$T/$pg.exe" ]; then
            got=0
            (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$pg.exe" > /dev/null 2>&1) || got=$?
            [ "$got" -eq 42 ] && ok "A PE (wine): the $pg program exits 42" || bad "A PE (wine): the $pg program exits $got, want 42"
        else bad "A PE: the $pg program did not compile: $(grep '^error' "$T/$pg.werr" | head -1)"; fi
    done
else echo "  SKIP A PE — wine not installed"; skips=$((skips + 1)); fi

# AX: AL10-AL14 on aarch64 (qemu), cx (cxvm) and PE (wine) — the snapshot is the shared frontend's; each
# fork's compiler is the one the A legs built from this tree. Each exits 5.
for a in al10 al11 al12 al13 al14; do
    if [ -x "$T/cc_a64" ]; then
        if "$T/cc_a64" < "$T/$a.cyr" > "$T/$a.a" 2> "$T/$a.aerr"; then
            chmod +x "$T/$a.a"; got=0; (cd "$T" && timeout 60 qemu-aarch64 "./$a.a" > /dev/null 2>&1) || got=$?
            [ "$got" -eq 5 ] && ok "AX $a aarch64 (qemu): exit 5" || bad "AX $a aarch64 (qemu): exit $got, want 5"
        else bad "AX $a aarch64: did not compile: $(grep '^error' "$T/$a.aerr" | head -1)"; fi
    else echo "  SKIP AX $a aarch64 — qemu-aarch64 or the aarch64 compiler missing"; skips=$((skips + 1)); fi
    if [ -x "$T/cc_cx" ] && [ -x "$T/cxvm" ]; then
        if "$T/cc_cx" < "$T/$a.cyr" > "$T/$a.cyx" 2> "$T/$a.cxerr" && [ -s "$T/$a.cyx" ]; then
            got=0; timeout 60 "$T/cxvm" < "$T/$a.cyx" > /dev/null 2>&1 || got=$?
            [ "$got" -eq 5 ] && ok "AX $a cx (cxvm): exit 5" || bad "AX $a cx (cxvm): exit $got, want 5"
        else bad "AX $a cx: did not compile: $(grep '^error' "$T/$a.cxerr" | head -1)"; fi
    else bad "AX $a cx: no cx compiler / cxvm (the A legs build them)"; fi
    if command -v wine > /dev/null 2>&1; then
        if CYRIUS_TARGET_WIN=1 "$CC" < "$T/$a.cyr" > "$T/$a.exe" 2> "$T/$a.werr" && [ -s "$T/$a.exe" ]; then
            got=0
            (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$a.exe" > /dev/null 2>&1) || got=$?
            [ "$got" -eq 5 ] && ok "AX $a PE (wine): exit 5" || bad "AX $a PE (wine): exit $got, want 5"
        else bad "AX $a PE: did not compile: $(grep '^error' "$T/$a.werr" | head -1)"; fi
    else echo "  SKIP AX $a PE — wine not installed"; skips=$((skips + 1)); fi
done

# (D5, D6) tests/tcyr/crossos/dyn_objects.tcyr, the forming and calling file: every assertion passes
# under CYRIUS_IR=1, CYRIUS_IR=3 and CYRIUS_DCE=1, on qemu-aarch64 and under wine (the count derived
# from its source), and (D6) it compiles with no warning (an f64 result is typed, no prototype is
# "undefined").
DO=tests/tcyr/crossos/dyn_objects.tcyr
DON=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$DO")
rc=0; "$CC" < "$DO" > "$T/do_cw.bin" 2> "$T/do_cw.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'warning' "$T/do_cw.err"; then ok "CW: dyn_objects.tcyr compiles with no warning on x86"
else bad "CW: rc $rc: $(grep 'warning\|^error' "$T/do_cw.err" | head -1)"; fi
dosum() {   # <label> <exit> <output file>
    if [ "$2" -eq 0 ] && [ "$(tail -1 "$3")" = "$DON passed, 0 failed ($DON total)" ]; then ok "$1: $DON/$DON"
    else bad "$1: exit $2, $(tail -1 "$3")"; fi
}
for mode in IR1 IR3 DCE; do
    if [ "$mode" = IR3 ]; then ev=CYRIUS_IR=3; elif [ "$mode" = IR1 ]; then ev=CYRIUS_IR=1; else ev=CYRIUS_DCE=1; fi
    rc=0; env $ev "$CC" < "$DO" > "$T/do_$mode.bin" 2> "$T/do_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "A dyn_objects x86 $ev: rc $rc: $(grep '^error' "$T/do_$mode.err" | head -1)"
    else chmod +x "$T/do_$mode.bin"; got=0; (cd "$T" && timeout 60 "./do_$mode.bin" > "do_$mode.out" 2>&1) || got=$?
        dosum "A dyn_objects x86 $ev" "$got" "$T/do_$mode.out"; fi
done
if command -v qemu-aarch64 > /dev/null 2>&1 && [ -x "$T/cc_a64" ]; then
    if "$T/cc_a64" < "$DO" > "$T/do.a" 2> "$T/do.aerr"; then
        chmod +x "$T/do.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 ./do.a > do.aout 2>&1) || got=$?
        dosum "A dyn_objects aarch64 (qemu)" "$got" "$T/do.aout"
    else bad "A dyn_objects aarch64: did not compile: $(grep '^error' "$T/do.aerr" | head -1)"; fi
else echo "  SKIP A dyn_objects aarch64 — qemu-aarch64 or the aarch64 compiler missing"; skips=$((skips + 1)); fi
if command -v wine > /dev/null 2>&1; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$DO" > "$T/do.exe" 2> "$T/do.werr" && [ -s "$T/do.exe" ]; then
        got=0
        (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine ./do.exe > do.wout 2>&1) || got=$?
        tr -d '\r' < "$T/do.wout" > "$T/do.wout2"
        dosum "A dyn_objects PE (wine)" "$got" "$T/do.wout2"
    else bad "A dyn_objects PE: did not compile: $(grep '^error' "$T/do.werr" | head -1)"; fi
else echo "  SKIP A dyn_objects PE — wine not installed"; skips=$((skips + 1)); fi

# ── IX: the 6.7.8 integration — the checked dyn meets C2's subscripts, `*p` at the element's width, slice
# stores and the bounds-checked mode (each row also on aarch64 / cx / PE where a leg runs) ──────────────
DS=tests/tcyr/crossos/dyn_subscripts.tcyr
DSN=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$DS")
[ "$DSN" -ge 26 ] || bad "IX: dyn_subscripts.tcyr holds $DSN assertions (floor 26) — the count or the file moved"
ixsum() {   # <label> <exit> <output file> <want count>
    tr -d '\r' < "$3" > "$3.n"
    if [ "$2" -eq 0 ] && [ "$(tail -1 "$3.n")" = "$4 passed, 0 failed ($4 total)" ]; then ok "$1: $4/$4"
    else bad "$1: exit $2, $(tail -1 "$3.n")"; fi
}
ixv() {     # <label> <exit> <stderr file> <the one line wanted>
    tr -d '\r' < "$3" > "$3.n"
    if [ "$2" -eq 134 ] && [ "$(wc -l < "$3.n")" -eq 1 ] && [ "$(cat "$3.n")" = "$4" ]; then ok "$1: exit 134, \`$4\`"
    else bad "$1: exit $2, stderr \`$(head -2 "$3.n" | tr '\n' '|')\` (want 134 and \`$4\`)"; fi
}
ixwine() {  # <exe> <stdout> <stderr>: the exit status in $got
    got=0
    (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$1" > "$2" 2> "$3") || got=$?
}
{ echo '#bounds'; cat "$DS"; } > "$T/ds_line.tcyr"
# IX1 tests/tcyr/crossos/dyn_subscripts.tcyr — a dyn method's `self.p[i]` (read, `=`, `+=`) and its typed
# array local, a dyn call's `*T` result subscripted (`o.ptr()[i]`, a `*u8` one's `o.bp()[i]` / `*o.bp()`
# writing one byte), a `*u8` dereference in a dyn method, a slice and a dyn formed from a declared `i32`
# in one fn — every assertion, with the mode off (no warning), CYRIUS_IR=3, CYRIUS_DCE=1, and under the
# bounds-checked mode (CYRIUS_BOUNDS=1, the rung `cyrius build --bounds` sets; and the file's own
# `#bounds` line): every index in range, nothing trips.
for leg in off IR3 DCE BOUNDS line; do
    src="$DS"; ev=""
    case $leg in IR3) ev=CYRIUS_IR=3 ;; DCE) ev=CYRIUS_DCE=1 ;; BOUNDS) ev=CYRIUS_BOUNDS=1 ;; line) src="$T/ds_line.tcyr" ;; esac
    rc=0; env $ev "$CC" < "$src" > "$T/ds_$leg.bin" 2> "$T/ds_$leg.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "IX1 x86 $leg: rc $rc: $(grep '^error' "$T/ds_$leg.err" | head -1)"; continue; fi
    if [ "$leg" = off ] && grep -q 'warning' "$T/ds_$leg.err"; then bad "IX1 x86 off: a warning: $(grep warning "$T/ds_$leg.err" | head -1)"; fi
    chmod +x "$T/ds_$leg.bin"; got=0; (cd "$T" && timeout 60 "./ds_$leg.bin" > "ds_$leg.out" 2>&1) || got=$?
    ixsum "IX1 dyn_subscripts x86 $leg" "$got" "$T/ds_$leg.out" "$DSN"
done
for m in 0 1; do
    if [ -x "$T/cc_a64" ]; then
        rc=0; CYRIUS_BOUNDS=$m "$T/cc_a64" < "$DS" > "$T/ds$m.a" 2> "$T/ds$m.aerr" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "IX1 aarch64 CYRIUS_BOUNDS=$m: rc $rc: $(grep '^error' "$T/ds$m.aerr" | head -1)"
        else chmod +x "$T/ds$m.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 "./ds$m.a" > "ds$m.aout" 2>&1) || got=$?
            ixsum "IX1 dyn_subscripts aarch64 (qemu) CYRIUS_BOUNDS=$m" "$got" "$T/ds$m.aout" "$DSN"; fi
    else echo "  SKIP IX1 aarch64 CYRIUS_BOUNDS=$m — qemu-aarch64 or the aarch64 compiler missing"; skips=$((skips + 1)); fi
    if [ -x "$T/cc_cx" ] && [ -x "$T/cxvm" ]; then
        rc=0; CYRIUS_BOUNDS=$m "$T/cc_cx" < "$DS" > "$T/ds$m.cyx" 2> "$T/ds$m.cxerr" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "IX1 cx CYRIUS_BOUNDS=$m: rc $rc: $(grep '^error' "$T/ds$m.cxerr" | head -1)"
        else got=0; timeout 120 "$T/cxvm" < "$T/ds$m.cyx" > "$T/ds$m.cxout" 2>&1 || got=$?
            ixsum "IX1 dyn_subscripts cx (cxvm) CYRIUS_BOUNDS=$m" "$got" "$T/ds$m.cxout" "$DSN"; fi
    else bad "IX1 cx: no cx compiler / cxvm (the A legs build them)"; fi
    if command -v wine > /dev/null 2>&1; then
        rc=0; CYRIUS_BOUNDS=$m CYRIUS_TARGET_WIN=1 "$CC" < "$DS" > "$T/ds$m.exe" 2> "$T/ds$m.werr" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "IX1 PE CYRIUS_BOUNDS=$m: rc $rc: $(grep '^error' "$T/ds$m.werr" | head -1)"
        else ixwine "ds$m.exe" "ds$m.wout" "ds$m.wrerr"; ixsum "IX1 dyn_subscripts PE (wine) CYRIUS_BOUNDS=$m" "$got" "$T/ds$m.wout" "$DSN"; fi
    else echo "  SKIP IX1 PE CYRIUS_BOUNDS=$m — wine not installed"; skips=$((skips + 1)); fi
done

# IX2 a violation under the mode, from where the features meet — a dyn method's `self.p[i]` (a `*T`
# field: a negative index) and its typed array local `a[i]` (its exact N) in an INCLUDED file, named by
# its include path and the line; a dyn call's `*T` result `o.ptr()[m]` at the entry's line. Exit 134 and
# exactly the one line; the in-range program (k = 0) exits 11 with nothing on stderr. Every target.
mkdir -p "$T/ix"
printf 'trait Buf { fn at(self, i): i64; fn ptr(self): *i64; fn el(self, i): i64; }\nstruct Rec { p: *i64; }\nimpl Buf for Rec {\n    fn at(self, i): i64 { return self.p[i]; }\n    fn ptr(self): *i64 { return self.p; }\n    fn el(self, i): i64 {\n        var a: i64[4];\n        a[0] = 1;\n        return a[i];\n    }\n}\n' > "$T/ix/dlib.cyr"
printf 'include "dlib.cyr"\nvar MEM[4];\nfn main(k): i64 {\n    store64(&MEM, 5);\n    var r = Rec { &MEM };\n    var o: dyn Buf = &r;\n    var m = 0 - 2;\n    if (k == 1) { return o.at(0 - 1); }\n    if (k == 2) { return o.el(4); }\n    if (k == 3) { return o.ptr()[m]; }\n    return o.at(0) + o.el(0) + o.ptr()[0];\n}\nsyscall(60, main(K));\n' > "$T/ix/main.tpl"
IXW1='bounds: index -1 out of [0, ...) at dlib.cyr:4'
IXW2='bounds: index 4 out of [0, 4) at dlib.cyr:9'
IXW3='bounds: index -2 out of [0, ...) at <source>:10'
for k in 0 1 2 3; do sed "s/main(K)/main($k)/" "$T/ix/main.tpl" > "$T/ix/m$k.cyr"; done
ixk() {     # <leg> <k> <exit> <stderr file>
    case $2 in
        0) if [ "$3" -eq 11 ] && [ ! -s "$4" ]; then ok "IX2 $1 k=0: in range, exit 11, stderr empty"
           else bad "IX2 $1 k=0: exit $3 (want 11), stderr \`$(head -1 "$4")\`"; fi ;;
        1) ixv "IX2 $1 k=1: a dyn method's \`self.p[i]\`, i = -1, in an included file" "$3" "$4" "$IXW1" ;;
        2) ixv "IX2 $1 k=2: a dyn method's typed array \`a[i]\`, i = N" "$3" "$4" "$IXW2" ;;
        3) ixv "IX2 $1 k=3: a dyn call's \`*T\` result \`o.ptr()[m]\`, m = -2" "$3" "$4" "$IXW3" ;;
    esac
}
for k in 0 1 2 3; do
    rc=0; (cd "$T/ix" && CYRIUS_BOUNDS=1 timeout 60 "$CC" < "m$k.cyr" > "m$k.bin" 2> "m$k.err") || rc=$?
    if [ "$rc" -ne 0 ]; then bad "IX2 x86 k=$k: rc $rc: $(grep '^error' "$T/ix/m$k.err" | head -1)"
    else chmod +x "$T/ix/m$k.bin"; got=0; timeout 10 "$T/ix/m$k.bin" > /dev/null 2> "$T/ix/m$k.rerr" || got=$?; ixk x86 "$k" "$got" "$T/ix/m$k.rerr"; fi
    if [ -x "$T/cc_a64" ]; then
        rc=0; (cd "$T/ix" && CYRIUS_BOUNDS=1 timeout 60 "$T/cc_a64" < "m$k.cyr" > "m$k.a" 2> "m$k.aerr") || rc=$?
        if [ "$rc" -ne 0 ]; then bad "IX2 aarch64 k=$k: rc $rc: $(grep '^error' "$T/ix/m$k.aerr" | head -1)"
        else chmod +x "$T/ix/m$k.a"; got=0; (cd "$T/ix" && timeout 60 qemu-aarch64 "./m$k.a" > /dev/null 2> "m$k.arerr") || got=$?; ixk "aarch64 (qemu)" "$k" "$got" "$T/ix/m$k.arerr"; fi
    fi
    if [ -x "$T/cc_cx" ] && [ -x "$T/cxvm" ]; then
        rc=0; (cd "$T/ix" && CYRIUS_BOUNDS=1 timeout 60 "$T/cc_cx" < "m$k.cyr" > "m$k.cyx" 2> "m$k.cxerr") || rc=$?
        if [ "$rc" -ne 0 ]; then bad "IX2 cx k=$k: rc $rc: $(grep '^error' "$T/ix/m$k.cxerr" | head -1)"
        else got=0; timeout 60 "$T/cxvm" < "$T/ix/m$k.cyx" > /dev/null 2> "$T/ix/m$k.cxrerr" || got=$?; ixk "cx (cxvm)" "$k" "$got" "$T/ix/m$k.cxrerr"; fi
    fi
    if command -v wine > /dev/null 2>&1; then
        rc=0; (cd "$T/ix" && CYRIUS_BOUNDS=1 CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "m$k.cyr" > "../ixm$k.exe" 2> "m$k.werr") || rc=$?
        if [ "$rc" -ne 0 ]; then bad "IX2 PE k=$k: rc $rc: $(grep '^error' "$T/ix/m$k.werr" | head -1)"
        else ixwine "ixm$k.exe" "ixm$k.wout" "ixm$k.wrerr"; ixk "PE (wine)" "$k" "$got" "$T/ixm$k.wrerr"; fi
    fi
done

# IX3 the mode on programs that form dyns: dyn_objects.tcyr (no subscript of its own — the checker
# rides along unused) passes every assertion under CYRIUS_BOUNDS=1 on every target; and with the mode
# off not a byte of the checker exists in either dyn file — unset == CYRIUS_BOUNDS=0, byte for byte.
rc=0; CYRIUS_BOUNDS=1 "$CC" < "$DO" > "$T/dob.bin" 2> "$T/dob.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "IX3 dyn_objects x86 CYRIUS_BOUNDS=1: rc $rc: $(grep '^error' "$T/dob.err" | head -1)"
else chmod +x "$T/dob.bin"; got=0; (cd "$T" && timeout 60 ./dob.bin > dob.out 2>&1) || got=$?; ixsum "IX3 dyn_objects x86 CYRIUS_BOUNDS=1" "$got" "$T/dob.out" "$DON"; fi
if [ -x "$T/cc_a64" ]; then
    rc=0; CYRIUS_BOUNDS=1 "$T/cc_a64" < "$DO" > "$T/dob.a" 2> "$T/dob.aerr" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "IX3 dyn_objects aarch64 CYRIUS_BOUNDS=1: rc $rc: $(grep '^error' "$T/dob.aerr" | head -1)"
    else chmod +x "$T/dob.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 ./dob.a > dob.aout 2>&1) || got=$?; ixsum "IX3 dyn_objects aarch64 (qemu) CYRIUS_BOUNDS=1" "$got" "$T/dob.aout" "$DON"; fi
fi
if [ -x "$T/cc_cx" ] && [ -x "$T/cxvm" ]; then
    rc=0; CYRIUS_BOUNDS=1 "$T/cc_cx" < "$DO" > "$T/dob.cyx" 2> "$T/dob.cxerr" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "IX3 dyn_objects cx CYRIUS_BOUNDS=1: rc $rc: $(grep '^error' "$T/dob.cxerr" | head -1)"
    else got=0; timeout 120 "$T/cxvm" < "$T/dob.cyx" > "$T/dob.cxout" 2>&1 || got=$?; ixsum "IX3 dyn_objects cx (cxvm) CYRIUS_BOUNDS=1" "$got" "$T/dob.cxout" "$DON"; fi
fi
if command -v wine > /dev/null 2>&1; then
    rc=0; CYRIUS_BOUNDS=1 CYRIUS_TARGET_WIN=1 "$CC" < "$DO" > "$T/dob.exe" 2> "$T/dob.werr" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "IX3 dyn_objects PE CYRIUS_BOUNDS=1: rc $rc: $(grep '^error' "$T/dob.werr" | head -1)"
    else ixwine dob.exe dob.wout dob.wrerr; ixsum "IX3 dyn_objects PE (wine) CYRIUS_BOUNDS=1" "$got" "$T/dob.wout" "$DON"; fi
fi
for f in "$DO" "$DS"; do
    b=$(basename "$f" .tcyr)
    rc=0; "$CC" < "$f" > "$T/$b.off" 2> /dev/null || rc=$?
    CYRIUS_BOUNDS=0 "$CC" < "$f" > "$T/$b.off0" 2> /dev/null || rc=$?
    if [ "$rc" -ne 0 ]; then bad "IX3 $b mode off: rc $rc"
    elif ! cmp -s "$T/$b.off" "$T/$b.off0"; then bad "IX3 $b: unset and CYRIUS_BOUNDS=0 differ"
    elif grep -q 'bounds: index' "$T/$b.off"; then bad "IX3 $b: the checker's text is in a mode-off binary"
    else ok "IX3 $b mode off: no checker byte, unset == CYRIUS_BOUNDS=0"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: dyn_checked — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: dyn_checked — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: dyn_checked — \`dyn\`: the reserved word (K); the type in a local, a global, a parameter, a return, a field and a trait signature (TY, S); every open type position refused by name (T1-T13); uninitialised dyn locals (U); opacity — no value, no address, no words (V1-V9); every forming refusal once, at its source (F1-F11), the slice and declared-scalar stamps apart and the closure / instance snapshot's names put back, every target (AL, AX), the zone dyn of a kernel build (K), wrapped sources (PF); every destination of a dyn result takes it whole (P); the fold across lines (H28); --syntax-only (X); the tools — embed, LSP, grammar, header, fmt, lint, doc, api-surface, type-audit — and the guide's dyn examples (TT); the P program and dyn_objects.tcyr on x86 / IR=3 / DCE / aarch64 / cx / PE (A); where dyn meets C2's subscripts, \`*p\` width, slices and the bounds-checked mode, every target (IX)"
