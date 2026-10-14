#!/bin/sh
# tests/gates/codegen/small_struct_handle_line.sh — 6.7.10 (B7-1, B7-1g, B7-1b, B7-1c)
#
# THE HANDLE LINE (the user's decision, 2026-10-12): a struct local of 8 B or less initialised from
# anything that is not a struct value of its type is a HANDLE, as one over 8 B is — its slot holds
# the address, its field writes reach the object, and every consumer that takes its struct copies
# through it. Through 6.7.9 MARK_SMALL_STRUCT marked every such local inline whatever its
# initialiser, so `var q: S8 = alloc(8);` held the ADDRESS as `q.v` and `q.v = 5` never reached the
# heap. Filed: docs/development/issues/2026-10-08-small-struct-local-from-address-is-value-not-
# handle.md (its repro: 17 measured, 237 right). With it (the user's planning decision 6): `var q:
# S = *p;` with `p: *S` COPIES at every size — over 8 B it was a handle holding the word `*p` read —
# and so does every other dereference of a `*S` (the review fix: `(*p)`, `*(p + 1)`, `*h.p`, `*gp()`,
# `*w.mp()`, `(*self)`, locals and globals; B7-1 / B7-1g first took only `* IDENT ;`).
#
# The runtime half is tests/tcyr/crossos/small_struct_handle_line.tcyr (its header carries the
# rule, initialiser by initialiser and consumer by consumer, every 8 B row against its 16 B twin,
# and every size 1..8 B). The release gate's cross-OS leg runs it on ecb / ach / cass / pi; this
# gate runs it on the legs this box has, compilers built from this tree:
#   R0 the filed repro, VERBATIM: exit 237 on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm), PE (wine)
#   R1 the crossos file on the same legs: "N passed, 0 failed (N total)", N derived from the file
#   C  compile rows (x86): C1 a handle <- handle of ANOTHER struct type compiles and rebinds (exit
#      58), as over 8 B; C2 a struct value of another type is still refused by name — `var q: S8 =
#      mku(1);` and, into a handle, `q = mku(1);`; C3 `bs1((t))` with `t: T1` into `p: S1` is
#      refused by name, as `bs1(t)` is (6.7.11: issues/2026-10-08-paren-arg-small-byval-struct-skips-type-check.md,
#      the user's decision 2026-10-13 — it compiled, exit 7, through 6.7.10); C4
#      `var q: S8 = *pu;` with `pu: *U8` (a local or a global) is refused by name, as `= pu` is, at
#      8 and 16 B; C5 `return (a, 1)` with a handle compiles and the element is the handle's word,
#      as at 16 B; C6 a handle of another struct returned from an 8 B struct fn is refused by name
#      (6.7.11, the user's decision 2026-10-13: every other-struct return shape is refused, as at 9-16
#      and over 16 B; 6.7.10 returned its struct's bytes, 3 — tests/gates/frontend/
#      small_struct_return_type_refused.sh carries the whole class)
#      C7 (the review fix) a dereference of a `*U8` / `*UH` at any other spelling — `(*pu)`, `*gu()`,
#      `*w.pu` — is refused by name, as `*pu` is; C8 `(*x)` with x UNTYPED is no struct value: a handle
#      holding the word `*x` reads (decision 1)
#   P  (Linux x86_64 + aarch64) a 7 B handle onto the LAST 7 bytes of a 2-page anonymous mapping
#      whose second page is unmapped: passed by value, returned, an operator's right operand, an
#      if-expression branch, a closure capture's argument and `c = a` — exit 0, no fault (no byte
#      past the object is read)
#   PS (Linux x86_64 + aarch64; the review fix) a method's by-value `self: S7` / `self: S3` whose
#      receiver ends a mapping — a `*S7` local, a handle, a handle global, a `*S7` global, at top level
#      too: exit 0. The receiver was loaded rounded up to 4 / 8 bytes (`_self_value_ra`, 6.6.11)
#   PD (Linux x86_64 + aarch64; the review fix) a local declared from a dereference of a `*S7` ending a
#      mapping — `(*p)`, `*(p + 0)`, `*gp()`, `*w.p` — copies byte-exact: exit 0
#   PX (Linux x86_64 + aarch64; 6.7.11, issues/2026-10-12-small-struct-dereference-reads-past-the-object.md)
#      a dereference `*p` of a struct of N = 1..7 i8 fields ending a mapping (8 B the control) in every
#      value use — a global declared from it in the declaration zone (`*Q`, `(*Q)`, `*gq()`, `*(Q + 0)`,
#      `*WQ.p`, `f(*Q)`) and after it (`*P`, `(*P)`, `*gp()`, `*(P + 0)`), `G = *P`, a by-value and a `*S`
#      argument, at top level and in a fn (locals declared and assigned from it, `return *P`, `return
#      (*P)`): exit 0. Through 6.7.10 `_deref_read` loaded 8 bytes at every size: exit 139 at 1..7 B
#   AS (x86_64, CYRIUS_ASYNC=1 — a mid-body suspend is x86-only so far) an `async fn` body: a
#      handle, a bind, a by-value argument, a copy into the object and a returned handle across two
#      awaits — exit 0
#
# B7-1g — THE HANDLE LINE FOR GLOBALS (the user's decision 5, 2026-10-12: one rule for locals and
# globals at every size): a struct global of 8 B or less initialised from anything that is not a
# struct value of its type is a handle (GVPM 1), as over 8 B. Its runtime half is
# tests/tcyr/crossos/small_struct_global_handle_line.tcyr (the declaration zone — judged from its
# tokens at the end of pass 1, a fn declared below included — and after the first statement; every
# consumer in a fn and at top level; every size 1..8 B):
#   R2 that file on the same legs as R1, N derived from it (floor 267)
#   GC compile rows (x86): GC1 `var ga: Num = 1;` is a handle global — `ga + gb` is pointer
#      arithmetic (3, no `Num_add`), as at 16 B; a struct value global still dispatches (102); GC2
#      `var G: S8 = *GU;` with `GU: *U8` refused by name in the zone and after it, at 8 and 16 B;
#      GC6 (the review fix) `(*GU)` / `*gu()` of another struct refused by name in the zone and after it;
#      GC7 `var G: H = *gp();` with gp declared below G refused by name (pass 1 sizes G);
#      GC8 (the review fix; 6.7.10 decision 11) `var G: S8 = GW.s + A;` — an operator whose left operand is
#      a FIELD dispatches `S8_add`, its result a struct value (exit 19), in the zone, after it and in a fn:
#      the zone's typer (`_gz_lty`) and the parse agree (through the review fix the field did not
#      dispatch: a handle holding the summed first words, exit 9);
#      GC3 `var G: H = *P;` with P declared below G refused by name (pass 1 could not register G
#      inline; `_gci_below`'s refusal); GC4 one global declared a value and a handle refused by name
#      (two shapes), two handle declarations fold; GC5 the sweep repeats: a global bound to a handle
#      declared below it binds, and an operator on such a handle is pointer arithmetic
#   GP (Linux x86_64 + aarch64) a 7 B handle GLOBAL onto the last 7 bytes of a mapping: by value,
#      returned, an operator's right operand, an if-expression branch, `c = G`, and at TOP LEVEL
#      (a hidden global, no frame) — exit 0, no byte past the object read
#
# B7-1b — A POINTER INTO A BY-VALUE STRUCT PARAMETER OF 8 B OR LESS (the user's decision 7, 2026-10-12:
# `&c` into a by-value struct parameter copies through the pointer at every size): a typed pointer or
# an address passes the struct it points at, as over 8 B (that parameter is address-passed). Through
# 6.7.9 the pointer was pushed as the struct's one word and the callee read the address's bits as its
# fields. Filed: docs/development/issues/archived/2026-10-11-typed-pointer-into-small-byvalue-struct-param.md
# (its repro: 0 measured, 111 right). Its runtime half is tests/tcyr/crossos/small_struct_pointer_arg.tcyr
# (every pointer form and consumer against its 16 B twin, the untyped boundary, sizes 1..8 B, top level):
#   R3 that file on the same legs as R1, N derived from it (floor 69)
#   R4 the filed repro, VERBATIM: exit 111 on the same legs (0 = each callee read the pointer's bits)
#   PP (Linux x86_64 + aarch64) a `*S7` onto the last 7 bytes of a mapping passed by value — a `*T`
#      local, a `: *S7` call, an operator's right operand, a `*S7` global, a closure, and at TOP LEVEL
#      (a hidden global temp) — exit 0, no byte past the object read
#
# B7-1c — STRUCT COPIES ARE SIZE-INDEPENDENT (the user's decision 6, 2026-10-12): `l = p` / `G = p` with
# `p: *S` copy the struct p points at, and `q = r` through `q: *S` copies r into the pointee, at every
# size, as over 8 B (where a `*T` local or parameter is a copy-assign handle). Through 6.7.9 a `*T` of a
# struct of 8 B or less was no struct operand: `l = p` / `G = p` stored the POINTER into the first
# field, `q = r` / `p = l` rebound the pointer to r's word, and a call / method / operator /
# if-expression / field result into a `*T` stored the struct's word as the pointer. Its runtime half
# is tests/tcyr/crossos/small_struct_pointer_copy.tcyr (every shape against its 16 B twin, the
# rebinds, closures, sizes 1..8 B with a guard byte):
#   R5 that file on the same legs as R1, N derived from it (floor 67)
#   CP compile rows (x86): a struct value of ANOTHER type is refused by name, as over 8 B — `l = pu`,
#      `pu = l`, `G = pu`, `q = G` (`q: *U8`) and `p = mku(1)`, at 8 B, with the 16 B twins of
#      `l = pu` and `p = mku(1)`; a `*U` of another struct into a `*T` still REBINDS (exit 17)
#   PM (Linux x86_64 + aarch64) a `*S7` onto the last 7 bytes of a mapping: `l = p`, `p = l`, `G = p`,
#      `q = r`, `l = q`, `q = G`, `p = mk7()` — exit 0, no byte past the object read or written
#
# 6.7.10 (the user's decision 11) — A STRUCT-TYPED FIELD OR A `*T` DEREFERENCE AS AN OPERATOR'S LEFT OPERAND
# DISPATCHES `S_add` (`S_sub`, `S_mul`, `S_div`) as a struct variable does, at every size, and the result is
# a struct value. Through 6.7.9 (and 6.7.10 before it) only a variable or a struct result typed the left
# operand: a field or a dereference loaded its first word and the integer arm ran — no operator fn, silently
# (issues/archived/2026-10-08-struct-field-left-operand-never-dispatches.md: `h.p - s` gave 250, 3 - 9). Its
# runtime half is tests/tcyr/crossos/struct_field_left_operand.tcyr (every base shape against its 16 B twin,
# 24 B, sizes 1..8 B with a guard byte, top level):
#   R6 that file on the same legs as R1, N derived from it (floor 88)
#   R7 the filed repro, VERBATIM: exit 139 (`P2_sub(&h.p, &s)` = 100 + 3·10 + 9) on the same legs — and,
#      since 139 is SIGSEGV's code natively, R7d its twin returning `(h.p - s) - 100` (exit 39) beside it
#      (250 / 150 = the integer 3 - 9 the field gave)
#   F  compile rows (x86), each refused exactly as its struct-variable twin: F1 `w.s + 1` / `*p + 1` with no
#      `S8_add` ("undefined function 'S8_add'"); F2 `fn S8_add(a: U8, ..)` — the field passed to a parameter
#      of another struct, by name; F3 `var G: H = GW.s + A;` at top level (a 9-16 B result needs a frame),
#      in the declaration zone and after it; F4 `var R = takeh(*GP + A);` at top level — a dereference-led
#      result as a by-value argument over 8 B — refused as `takeh(GW.s + A)` is (it compiled and SIGSEGV'd)
#
# 6.7.10 (the user's decision 12) — AN UNTYPED `var c = a + b;` WHOSE OPERATOR RETURNS A STRUCT TAKES THE
# STRUCT TYPE AT EVERY SIZE, as over 8 B (where the result's temporary becomes `c`): `c.g` works and `c + c`
# dispatches. Of 8 B or less the result was an untyped word — and 6.7.10's packed fields moved `C4 { r: u8;
# g: u8; b: u8; a: u8; }` from 32 B to 4, so `var c = A + B; c.g = 1;` was refused. Its runtime half is
# tests/tcyr/crossos/struct_operator_result_binding.tcyr (the C4 case, every shape against its 16 B twin,
# the operator's own return type, sizes 1..7 B, top level):
#   R8 that file on the same legs as R1, N derived from it (floor 33)
#   B  (x86) B1 the C4 case as a program: exit 111; B2 an operator returning an INTEGER leaves the binding
#      untyped — `var r = a - b; r.v` is refused ("no struct type in scope for 'r'"), at 8 and 16 B
#
# 6.7.10 (decision 6 completed) — A STRUCT COPY THROUGH A `*T` GLOBAL, A `: *T` CALL OR A `*T` FIELD COPIES THE
# STRUCT, at every size: `l = GP`, `G = GP`, `l = gp()`, `l = w.p` (any chain, wrapped) into a struct value
# copy the pointee, as `l = p` through a `*T` local does (B7-1c). Through 6.7.9 — over 8 B too — each stored
# the POINTER word into the first field. A `*T` or handle destination still rebinds. Its runtime half is
# tests/tcyr/crossos/struct_pointer_source_copy.tcyr (every shape against its 16 B twin, the rebinds, sizes
# 1..7 B with a guard global, top level):
#   R9 that file on the same legs as R1, N derived from it (floor 60; 6.7.11, issues/2026-10-13-struct-field-
#      destination-from-pointer-global-call-or-field.md: a struct-typed FIELD destination — `o.s = GP`, `gp()`,
#      `w.p`, `GP + 0`, `(gp())` at 8 / 16 / 24 B, direct and through a `*O`, a for step, top level, a guard
#      field after `s` — copies too; through 6.7.10 it kept the pointer word; the refusals are
#      struct_copy_source_type_refused.sh's R24-R29)
#   CQ compile rows (x86): a `*U` of another struct is refused by name, as `l = pu` is — `l = GU`, `l = gu()`,
#      `l = w.pu`, and `G = GU` at 16 B; a `*i64` global into a struct value stays its word (exit 1);
#      (ops-6) CQ6 pointer arithmetic on a `*U` — `l = pu + 1`, `l = pu + k` — refused naming the pointer;
#      CQ7 arithmetic on a `*i64` into a struct value stays its word (exit 1)
#   PQ (Linux x86_64 + aarch64) a `*S7` global / `: *S7` call / `*S7` field onto the LAST 7 bytes of a mapping:
#      `l = GP`, `G = GP`, `l = gp()`, `l = w.p`, (ops-6) `l = GP + 0`, at top level `G = GP` — exit 0, no byte
#      past the object read
# (ops-6) POINTER ARITHMETIC ON A `*T` is such a source too: `l = p + 1`, `l = (p + 1)`, `l = 1 + p`, `l = GQ + 1`,
# `G = q - 1` copy the struct the result points at (R9's rows); they stored the pointer word at every size. A
# `*T` or handle destination still rebinds (`q = p + 1`, `p = p + 1` — R9's `r_ar` rows).
#
# 6.7.10 (decision 6, ops-5) — A WHOLE DEREFERENCE OF A `*S` AS AN ADDRESS-PASSED ARGUMENT OR RIGHT OPERAND
# PASSES THE STRUCT IT POINTS AT: `take(*p)`, `take((*p))`, `take(*gp())`, `take(*w.ps)` into a by-value
# parameter over 8 B or a `*S` parameter of any size, and `a - *p` into such an operator parameter, pass the
# pointer, as `take(p)` / `a - p` do. Through 6.7.9 the WORD the dereference read was pushed as the struct's
# address (SIGSEGV; PE an access violation; cx a guest error). Its runtime half is
# tests/tcyr/crossos/struct_deref_whole_operand.tcyr (every shape against its 16 B twin, 24 B, `*S` parameters
# of 1 / 3 / 7 / 8 B, top level):
#   R10 that file on the same legs as R1, N derived from it (floor 78; 6.7.11: the `z` rows — a dereference
#      of a 3 / 5 / 6 / 7 B struct as a value, its padding 0)
#   R11 (6.7.11, issues/2026-10-13-assignment-from-struct-dereference-copies-one-word.md)
#      tests/tcyr/crossos/struct_deref_assign_copy.tcyr on the same legs (floor 76): an ASSIGNMENT from a
#      dereference — `l = *p`, `G = *p`, `o.s = *p`, `q = *p` into a `*S` / a handle's pointee, wrapped, `*(p +
#      0)`, `*gp()`, `*w.p`, through a `*O`, a for step, top level — copies the struct at 3 / 8 / 16 / 24 B
#      (through 6.7.10 one word; the refusals are struct_copy_source_type_refused.sh's R17-R23)
#   R12 (6.7.11, issues/2026-10-13-generic-pointer-returning-call-as-struct-source.md)
#      tests/tcyr/crossos/generic_ptr_struct_source.tcyr on the same legs (floor 72): a GENERIC call declared
#      `: *T` is a struct source, as `fn gp(): *S` is — the seven filed positions at 8 / 16 / 24 B for
#      `gpg<S>()`, `gpi(p)` and `gpv(G)`, the 6.7.11 copy arms (`o.s = gpg<S>()`, `l = *gpg<S>()`), wrapped,
#      `+ 0`, two type parameters, inside another instance, top level (through 6.7.10 the pointer word
#      stored, SIGSEGVs, the field form refused; the compile rows are generic_struct_field.sh's P)
#   R13 (6.7.11, issues/2026-10-12-small-struct-return-takes-another-structs-value.md and
#      issues/2026-10-13-small-struct-return-of-pointer-global-or-call-decision.md)
#      tests/tcyr/crossos/struct_ptrmode_return_copy.tcyr on the same legs (floor 75): a `*T` LOCAL returned
#      from a fn of 8 B or less is the struct it points at, as a `*T` parameter is (6.6.17) — wrapped, 3 / 4 /
#      6 / 8 B, a copy (not an alias), its word's padding 0 (through 6.7.10 the ADDRESS); and `return E;` with E
#      a `*S` global, a `: *S` call (the tail-call shape), a `*S` field, a `*S` local, `GP + 0`, a `: *S` method,
#      a generic `: *T` call, wrapped, or a dereference of one, at 3 / 8 / 16 / 24 B: the struct E points at, a
#      copy (through 6.7.10 the pointer at 3 / 8 B, refused over 8 B); the refusals are
#      tests/gates/frontend/small_struct_return_type_refused.sh and struct_result_type_refused.sh PU
#   D  compile rows (x86): D1 `takeh(*pu)` / `rd8(*pu)` with `pu` a `*U` of another struct refused by name, as
#      a struct variable of another type is; D2 `a - *pu`, `a - *gu()` the same; D3 an untyped `*y` keeps the
#      word it reads (exit 5: the word is the struct's address, as before)
#
# MUTATION LEDGER (2026-10-12; each a scratch copy of the tree with the one change, its compiler
# built from that copy, this gate run from the copy with CYCC=<that compiler>):
#   real tree                                         -> GREEN
#   the B7-0 tree (daae99ed, no handle line)        -> RED 22: R0 exit 17 x7; R1 does not compile x7 (`a = u`
#                                                      between an inline S8 and a U8 is refused); C1; C4 x3
#                                                      (`*pu` compiled); C5 SIGSEGV; P x2; AS
#   M2  PARSE_VAR's mark back to MARK_SMALL_STRUCT    -> RED 19: R0 17 x7, R1 does not compile x7, C1,
#                                                      C5, P x2, AS
#   M3  `_CL_CAP_BASE_RA` without the handle arm     -> RED 16: R0 exit 5 x7 (the capture copied the
#                                                      address word), R1 19 rows x7, P x2
#   M4  `_hl_call_whole` answering 0                  -> RED 11: R1 SIGSEGV (`var q: S8 = mk8(5)` a handle
#                                                      at address 5; cxvm "guest address out of range"), C6, P x2, AS
#   M5  `_sci_sval` never set                         -> RED 7: R1 SIGSEGV (`var q: S8 = a` a handle to 5)
#   M6  `_ret_small_ptrp` without the handle          -> RED 11: R1 20 rows x7 (the address returned), C6,
#                                                      P x2, AS
#   M7  `_sarg_byval_small` without `_hl_bare_val`    -> RED 10: R1 58 rows x7, P x2, AS
#   M8  `_op_rhs` without its arm                     -> RED 9: R1 12 rows x7, P x2
#   M9  `_ie_branch` without its arm                  -> RED 9: R1 10 rows x7, P x2
#   M10 `_hl_small_copy` never copying                -> RED 10: R1 26 rows x7, P x2, AS
#   M11 the rebind after the type check               -> RED 8: R1 does not compile x7, C1
#   M12a `_hl_res_into` answering 0 (method / operator / if-expression results into a handle)
#                                                   -> RED 7: R1 5 rows x7
#   M12b `_hl_call_into` answering 0 (a free call into a handle) -> RED 7: R1 12 rows x7
#   M13a `_hl_bare_val` without the paren peel        -> RED 7: R1 10 rows x7
#   M13b `_hl_ret_k` without the wrap                  -> RED 7: R1 10 rows x7
#   M14 `_hdl_val_ra` loading 8 bytes for 3 / 5 / 6 / 7 B -> RED 2: P x86 and P aarch64 exit 139
#   M15 `_agc_handle_local` without the small arm    -> RED 11: R1 43 rows x7, C2 (`q = mku(1)` into a
#                                                      handle no longer refused), P x2, AS
#   M16 `_sci_star` answering 0 (`*p` to the scalar init) -> RED 10: R1 SIGSEGV x7 (the 16 B `*p` twin
#                                                      a handle holding the first field), C4 x3
#   M17 `_hl_cap_hdl` answering 0                     -> RED 9: R1 15 rows x7, P x2
#   M18 `_ret_small_ptrp` refusing another type's handle -> RED 1: C6 (the address returned)
#   M19 `_sci_sval` neither reset nor cleared on read -> RED 7: R1 does not compile x7 (a stale 1 marks
#                                                      the next handle inline)
#   M20 a CAPTURED handle source counted before the rebind test (`h = cap` rebinds h instead of copying
#       through it, as 16 B does)                   -> RED 7: R1 2 rows x7
# B7-1g MUTATION LEDGER (2026-10-12, the same method; the B7-1 compiler cannot build the R2 file at
# all — `X8 = AU8` between two inline globals of different types is refused, a dyn wants `&QG8`):
#   MG1  `_gz_sweep` returns at once (no zone global becomes a handle) -> RED 15: R2 does not compile x7
#                                                      (`X8 = AU8`), GC1 102, GC4 x3 / GC5 x2 / GP x2 refused
#                                                      by the replay's check (`_gz_agree`: "misread")
#   MG2  `_gz_sval` answering 0 (every zone global a handle) -> RED 8: R2 refused by `_gz_agree` x7 (IN8),
#                                                      GC4 (the check fires before the shape refusal)
#   MG3  `_gz_op` answering 0 (operators typed as no struct) -> RED 7: R2 refused by `_gz_agree` x7 (IO8)
#   MG3b MG3 with `_gz_agree` never refusing        -> RED 7: R2 x7 (a fault on x86 x4 / aarch64 / PE, 3
#                                                      rows on cxvm: the operator results held as addresses)
#                                                      — the replay's check is the net
#   MG4  `_gz_late` answering 2 (after the first statement, the old value slot) -> RED 9: R2 x7 (a fault
#                                                      on x86 x4 / aarch64 / PE, 3 rows on cxvm: the alloc /
#                                                      &x writes stay in the global), GP x2
#   MG5  `_agc_handle_global` without the small arm -> RED 9: R2 x7 (`q = G` copied the address: a fault
#                                                      on x86 x4 / aarch64 / PE, cxvm out of range), GP x2
#   MG6  `_hl_gbare` answering 0                     -> RED 9: R2 61 rows x7 (arguments, operands, branches
#                                                      took the address), GP x2
#   MG7  `_ret_small_ptrp` without `_ret_small_gh`  -> RED 9: R2 19 rows x7 (`return G` the address), GP x2
#   MG8  no top-level temp (`_hl_res_into` / `_hl_call_into` back behind GINFN) -> RED 7: R2 x7 (`X8 =
#                                                      mk8(6)` at top level rebinds X8 to address 6: a fault
#                                                      on every leg, cxvm out of range)
#   MG9  `_hg_val_ra` loading 8 bytes at every size  -> RED 2: GP x86 and GP aarch64 exit 139
#   MG10 `_gz_star` answering 0                      -> RED 7: R2 refused x7 (`var IDH: H = *PSH;` not inline
#                                                      in pass 1: "declared below")
#   MG11 `_gz_star_src` without the type check       -> RED 3: GC2 x3 (`*GU` of a U8 / UH compiled)
#   MG12 the sweep walks once (no repeat)            -> RED 2: GC5 x2 (refused by `_gz_agree`)
#   MG13 `_gz_shapes` returns at once                -> RED 2: GC4 x2 (the literal-then-handle redeclaration
#                                                      compiled; the call-then-handle one caught by `_gz_agree`)
#   MG14 `_gz_reg` not noting a literal              -> RED 1: GC4 (the literal-then-handle redeclaration)
#   MG15 `_gz_chain` without the method arm          -> RED 7: R2 refused by `_gz_agree` x7 (IM8)
#   MG16 `_gz_ie` answering 0                         -> RED 7: R2 refused by `_gz_agree` x7 (IE8)
#   MG17 `_hl_capn` answering 0 (a capture is never checked) -> RED 16: R1 13 rows x7 (a captured handle's
#                                                      consumers), R2 1 row x7 (a capture named like a global),
#                                                      P x2
#   MG18 `_gz_split` without the generic-call skip   -> RED 7: R2 refused by `_gz_agree` x7 (`idg<S8>(..)`)
# B7-1b MUTATION LEDGER (2026-10-12, the same method):
#   the B7-1g tree (f72166c0, no pointer arm)         -> RED 16: R3 3 of 69 rows x7, R4 exit 0 x7, PP exit 1 x2
#                                                      (and struct_arg_type_refused.sh B1-B4)
#   MB1 `_hl_byval_arg` never takes the pointer arm   -> RED 16: R3 x7, R4 exit 0 x7, PP x2 (and B1-B4)
#   MB2 `_hl_parg`: step 1 never a pointer            -> RED 14: R3 33 rows x7 (every `&s` / `&G` / `&b` form),
#                                                      R4 exit 11 x7 (and B1, B2, B4)
#   MB3 `_hl_parg`: step 1 always a pointer (no `_hl_p1`) -> RED 7: R3 x7 (an i8 / i16 / i32 local read
#                                                      through as an address: SIGSEGV; cxvm out of range)
#   MB4 `_hl_p1` without the leftmost-term recursion -> RED 7: R3 1 row x7 (`t1(pa + i)`, i: i32, a value)
#   MB5 `_hl_pval_ra` loading 8 bytes at every size  -> RED 2: PP x86 and PP aarch64 exit 139
#   MB6 `_op_rhs` without its pointer arm            -> RED 9: R3 6 rows x7 (`o + sp`, `o + &s`, the 3 / 7 B
#                                                      operands, top level), PP x2
#   MB7 `_hl_narrow_at` without the `&` / `.` skip   -> RED 7: R3 1 row x7 (`t1(&c8)`, `t1(xb.p)` values)
#   MB8 `_hl_pval_ra` without its top-level arm      -> RED 9: R3 x7 (a frame temp at top level: SIGSEGV /
#                                                      SIGILL, cxvm out of range), PP x2
#   MB9 `_sarg_byval_small` without `_hl_byval_arg`  -> RED 16: R3 5 of 69 rows x7, R4 exit 0 x7, PP x2 (and
#                                                      B1-B4)
# B7-1c MUTATION LEDGER (2026-10-12, the same method):
#   the B7-1b tree (d046368e, no *T operand)          -> RED 14: R5 x7 (`l = p` held the pointer, then
#                                                      `q = r` rebound q: SIGSEGV x86 x4 / aarch64, cxvm out of
#                                                      range, PE a crash), CP1-CP5 (compiled), PM x2 (exit 1)
#   MC1 `_small_sptr` answering 0                     -> RED 14: the same rows as the B7-1b tree
#   MC2 `_hl_cap_addr` without the `*T` arm           -> RED 7: R5 6 rows x7 (`l = p`, `G = p`, `l = q` from a
#                                                      closure's captured `*T`, each with its twin row: the
#                                                      pointer word stored)
#   MC3 `_hl_small_copy` copying 8 bytes at every size -> RED 27: R1 7 rows x7, R2 7 rows x7, R5 7 rows x7 (the
#                                                      guard bytes after 1..7 B objects overwritten), GP x2, PM x2,
#                                                      P x2 (exit 139: the 8-byte copy reads past the mapping)
#   MC4 `_hl_small_copy` without the handle <- handle rebind
#                                                   -> RED 24: R1 / R2 / R5 do not compile x21 (`a = u`,
#                                                      `X8 = AU8`, `p = pu` refused as copies), C1, CP6, GC5 (a
#                                                      handle copied through instead of rebound: SIGSEGV)
# REVIEW-FIX MUTATION LEDGER (2026-10-12, the same method):
#   MR1 `_self_value_ra` loading a 3 / 5 / 6 / 7 B receiver rounded up to 4 / 8 bytes (the 6.6.11 code)
#                                                   -> RED 2: PS x86 and PS aarch64 exit 139
#   MR2 `_sci_dexpr` answering 0 (a local's `(*p)`, `*gp()`, .. to the scalar init: a handle holding the
#       word the dereference read — the B7-1 code) -> RED 13: R1 x7 (SIGSEGV; cxvm out of range; PE a
#                                                      crash), C7 x4 (compiled), PD x2
#   MR3 `_gz_star` without its `_hl_dstar` arm (a global's) -> RED 7: R2 x7 (`var IDPH: H = (*PSH);` not
#                                                      inline in pass 1: refused as "declared below")
#   MR4 `_gci_dx_top` keeping over 8 B to the value store -> RED 7: R2 x7 (`LDPH` a garbage handle: SIGSEGV)
#   MR5 `_hl_dstar` without the paren peel           -> RED 20: R1 x7, R2 x7, C7 x2, GC6 x2, PD x2
#   MR6 `_hl_psid` without the pointer-arithmetic arm -> RED 16: R1 x7, R2 x7 (`*(p + 0)`, `*(0 + p)`),
#                                                      PD x2
#   MR7 `_hl_pchain` without the `*T` field step     -> RED 17: R1 x7, R2 x7, C7 (`*w.pu` compiled), PD x2
#   MR7b `_hl_pchain` without the `: *T` method step -> RED 7: R1 x7 (`*w.mp()`)
#   MR8 `_sci_dexpr` without the type check          -> RED 4: C7 x4 (a `*U` of another struct compiled)
#   MR9 `_sci_dexpr` copying the slot-rounded size (8 bytes for a 7 B struct) -> RED 2: PD x86 and PD
#                                                      aarch64 exit 139
#   MF1 `_gz_chain` without the `*T` global receiver -> RED 7: R2 x7 (`IPM8 = PS8.dbl()` refused as a zone
#                                                      misread)
#   MF2 `_gz_chain` without the `: *T` call receiver -> RED 7: R2 x7 (`IGM8 = gs8().dbl()` a misread)
#   MF3 `_gz_chain` without the `*T` field receiver -> RED 7: R2 x7 (`IWM8 = PWG8.p.dbl()` a misread)
#   MF4 `_gz_fsrc` answering 0 (a field through a `*T` not a value)
#                                                   -> RED 7: R2 x7 (`IPF8 = PW8S.s` a handle holding the
#                                                      field's word: SIGSEGV)
#   MF5 `_gz_lty` dispatching on a field again        -> RED 1: GC8 (the zone refuses `GW.s + A` as a misread)
#       (6.7.10 decision 11 inverted this row: a field now dispatches; MO6 below is its mutant)
# DECISION-11 MUTATION LEDGER (2026-10-12, the same method):
#   the B7 tree (67b9ef93, no field / dereference dispatch) -> RED 29: R6 does not build x7 (`return w.s + a;`
#                                                      from a 9-16 B struct fn refused), R7 250 x7, R7d x7 (SIGSEGV:
#                                                      the integer `h.p - s` kept s's type and `- 100` dispatched
#                                                      P2_sub(&s, 100) — the struct-operator-results item 2), GC8 x3
#                                                      (exit 9), F1 x2 / F2 / F3 x2 (each compiled: no dispatch)
#   MO1  `_flo_note` stamping nothing                 -> RED 28: the B7 tree's rows but F1 `*p + 1`
#   MO2  `_dlo_park` answering 0                      -> RED 8: R6 does not build x7 (`return *p + a;`), F1 `*p + 1`
#   MO3  `_opd_lst` never matching                    -> RED 29: the B7 tree's rows
#   MO4  `_opd_lhs_sv` passing a field's VALUE at every size (no address) -> RED 16: R6 x7 (SIGSEGV; cxvm
#                                                      out of range; PE a crash), R7d x5 (139), R7 / R7d cx, PE
#   MO5  `_ret_lopd` answering 0                      -> RED 7: R6 does not build x7 (`return w.s + a;`)
#   MO6  `_gz_lty` not dispatching on a field (kind 5) -> RED 8: R6 x7 and GC8 (the zone refuses `var TQ8: S8 =
#                                                      GZW8.s + GA8;` as a misread)
#   MO7  `_gz_deref` answering 0                      -> RED 7: R6 x7 (the zone refuses `var TD8: S8 = *GZP8 + GA8;`)
#   MO8  `_opd_operand` without `_hl_pval_ra` (a dereference by value passes the pointer) -> RED 7: R6 22
#                                                      rows x7
#   MO9  `_dlo_opnext` without the wrap skip          -> RED 7: R6 x7 (`(*ps) + a` not parked: a handle holding
#                                                      the integer, SIGSEGV; cxvm 3 rows)
#   MO10 `_flo_addr_ra` without the field's offset    -> RED 21: R6 27 rows x7, R7 119 / R7d 19 x14
#   MO11 `_OP_OPERAND_ADDR` without the `_OPD_SV` arm  -> RED 21: R6 x7 (SIGSEGV; cxvm out of range), R7 / R7d x14
#   MO12 (ops-4) `_try_push_struct_addr_arg` without its `*` arm (a dereference-led argument to the value push)
#                                                   -> RED 9: R6 x7 (`takeh(*ps + a)`: the result's first word pushed
#                                                      as its address — SIGSEGV x86 x4 / aarch64, a PE crash, cxvm 5 rows),
#                                                      F4 x2 (compiled)
# DECISION-12 MUTATION LEDGER (2026-10-12, the same method):
#   the ops-1 tree (no untyped binding typed)        -> RED 8: R8 does not build x7 (`c.g`: "no struct type in
#                                                      scope for 'c'"), B1
#   MB1  `_sc_op_whole` answering 0                    -> RED 8: as the ops-1 tree
#   MB2  `_sc_post_op` never noting the operator's span -> RED 8: as the ops-1 tree
#   MB3  `_var_rhs_post` keeping a leading call's type over the operator's -> RED 7: R8 does not build x7
#                                                      (`var c = mk8(4) * b; c.u` — "unknown field 'u' on 'S8'")
#   MB4  `_sc_op_whole` typing ANY whole result of 8 B or less (a method chain, an if-expression too, not only
#        an operator's) -> GREEN: no row pins that a method chain's or an if-expression's untyped binding stays
#        untyped — decision 12 names operators; whether those take their type too is the user's question
# DECISION-6 (completed) MUTATION LEDGER (2026-10-12, the same method):
#   the ops-2 tree (no *T global / call / field operand) -> RED 13: R9 34 of 38 rows x7 (the pointer word stored:
#                                                      62938168 where 58), CQ1-CQ4 (compiled), PQ x2 (exit 1)
#   MQ1  `_hl_psrc_copy` answering 0                  -> RED 13: as the ops-2 tree
#   MQ3  the copy rounded up to whole words          -> RED 9: R9 the 7 size rows x7 (the guard global after a
#                                                      1..7 B value global overwritten), PQ x2 (exit 139: read past)
#   MQ4  no rebind for a handle / `*T` destination   -> RED 7: R9 2 rows x7 (`q = GP` through `q: *S` copied into
#                                                      the caller's struct: 95 where 19)
#   MQ5  no type check                                -> RED 4: CQ1-CQ4 (a `*U` of another struct copied)
#   MQ6  no step cross-check (`_ps_step(GPSC)` against the size) -> GREEN: defensive — no source is known where
#        `_hl_psrc`'s token typing and the parse's step disagree
#   MQ7  `_hl_psrc` without its `*T` test (`_hl_cp`)  -> GREEN: defensive — every struct-VALUE source reaching the
#        assignment takes its own copy path first (a field `_fla_take`, a call / method / operator its record)
#   (ops-6, 2026-10-13) the ops-5 tree (cf537b6e, no pointer-arithmetic source) -> RED 11: R9 7 of 47 rows x7
#                                                      (the pointer word stored), CQ6 x2 (compiled), PQ x2 (exit 6)
#   MQ8  `_hl_psrc` without its pointer-arithmetic arm -> RED 11: as the ops-5 tree
#   MQ9  `_hl_pnm` naming the last name (no `_hl_psid` side) -> RED 1: CQ6 `l = pu + k` (names 'k')
# OPS-5 MUTATION LEDGER (2026-10-13, the same method):
#   the ops-4 tree (3faadc9e, no whole-dereference operand) -> RED 11: R10 x7 (SIGSEGV x86 x4 / aarch64, a PE
#                                                      crash, cxvm "guest address out of range: 5"), D1 x2 / D2 x2
#                                                      (compiled)
#   MD1  `_dlo_park` without the `_dro_want` arm      -> RED 11: as the ops-4 tree
#   MD2  `_push_struct_expr_arg` without its `_dro_take` arm -> RED 9: R10 x7, D1 x2 (compiled)
#   MD3  `_op_rhs` without its `_dro_take` arm        -> RED 9: R10 x7, D2 x2 (compiled)
#   MD4  `_dro_check` answering 0 (no type check)     -> RED 4: D1 x2 / D2 x2 (compiled)
#   MD5  `_op_rhs`'s want without the wrap (`_dro_want = rb`) -> RED 7: R10 x7 (`a - (*p)`, `a * (*q)`)
# 6.7.11 POINTER-EDGES MUTATION LEDGER (2026-10-14, the same method; R3's `e_` rows,
# issues/2026-10-12-pointer-into-small-byvalue-param-untyped-edges.md; the user's decision 2026-10-13: (a)):
#   the A3 f64 tree (4b05d52a, before the fix)      -> RED R3 x7: 9 rows (the if-expressions of different
#                                                      steps / under a narrow condition, `m + pb`, `n + pb`,
#                                                      the chain, `n + pb2`, `n + sp`); R4 exit 111 (it was 0
#                                                      before B7-1b, still green)
#   ME1  `_hl_parg` without `_hl_ie_ptr`              -> RED R3: the 5 if-expression rows
#   ME2  `_ie_kind` never clearing the all-pointer flag -> RED R3: SIGSEGV (`e_ie_mixed`: the value 5 copied
#                                                      through as an address)
#   ME3  `_ptr_add` without `_add_rb1`                -> RED R3: `m + pb` / `0 + pb`, the chain's `m + 1 + pb`
#                                                      (and pointer_subscript_checked DXs1 x6, DXs3)
#   ME4  `_hl_rcarry` answering 0                     -> RED R3: `n + pb` (i32 / u8), the chain, `n + pb2`, `n + sp`
#   ME5  `_hl_p1` on the FIRST `+` / `-` (no `_hl_lastop`) -> RED R3: the chain (`n - 2 + pb`)
#   (`_add_rb1` without its one-byte size test is an equivalent mutant: a step-1 `*T` struct is one byte.)
# 6.7.11 SMALL-DEREFERENCE MUTATION LEDGER (2026-10-14, the same method; PX and R10's `z` rows,
# issues/2026-10-12-small-struct-dereference-reads-past-the-object.md):
#   real tree                                         -> GREEN
#   MX1  `_deref_small` answering 0 (the word load back) -> RED 21: PX 1..7 B x86 / aarch64 exit 139 (14), R10 20 of
#                                                      78 rows x7 (the padding 'D'..'H', every `z` row)
#   MX2  `_hl_pval_ra` never zeroing its frame temp (`z` ignored) -> RED 7: R10 8 of 78 rows x7 (in a fn, a by-value
#                                                      argument's and a return's padding 0xFF from the frame)
# 6.7.11 ASSIGNMENT-FROM-DEREFERENCE MUTATION LEDGER (2026-10-14, the same method; R11,
# issues/2026-10-13-assignment-from-struct-dereference-copies-one-word.md):
#   the tree before it (cf5838db)                   -> RED 7: R11 42 of 76 rows x7 (one word stored; `q = *p`
#                                                      rebound q)
#   MA1  `_asg_dstar` answering 0 (no name arm)       -> RED 7: R11 36 of 76 rows x7
#   MA2  `_fsc_dstar` answering 0 (no field arm)      -> RED 7: R11 8 of 76 rows x7 (`o.s = *p`, `po.s = *p`, the
#                                                      for step, `GO.s = *gp()` at 16 / 24 B)
# 6.7.11 GENERIC `: *T` SOURCE MUTATION LEDGER (2026-10-14, the same method; R12,
# issues/2026-10-13-generic-pointer-returning-call-as-struct-source.md):
#   the tree before it (7a9938e8)                   -> RED 7: R12 does not build x7 (`gpg<S>().v` refused)
#   MP1 `_hl_pchain` without the generic arm         -> RED 7: R12 exit 139 x5, cxvm out of range, PE a crash (the
#                                                      zone's `var Z: S = *gpg<S>();` a handle holding the word
#                                                      the dereference read)
#   MP2 `_ret_ptr_record` without the binding       -> RED 7: R12 does not build x7
# 6.7.11 SMALL STRUCT RETURN MUTATION LEDGER (2026-10-14, the same method; R13,
# issues/2026-10-12-small-struct-return-takes-another-structs-value.md):
#   the tree before it (3fc1dbbb)                   -> RED 8: R13 18 of 24 rows x7 (the `*T` local's address), C6
#                                                      (compiled, exit 3: U8's bytes as the S8)
#   MS2  `_ret_small_ptr` answering 0                -> RED 7: R13 18 of 24 rows x7
#   (issues/2026-10-13-small-struct-return-of-pointer-global-or-call-decision.md, R13 at 75 rows:)
#   the tree before it (the 8 B refusal commit)     -> RED 7: R13 does not build x7 (`return GP16;` refused)
#   MT3  `_ret_small_ptr` a bare local only (as before) -> RED 7: R13 16 of 75 rows x7 (3 / 8 B: the pointer's word)
#   MT2  `_ret_ptr_src` answering -1                 -> R13 does not build (x86 measured: the 16 B rows refused)
#   MT4  `_tc_small_sret_divert` without `: *X`     -> R13 2 of 75 rows (x86 measured: `return gp3();` /
#                                                      `return gp8();` kept the `jmp`, the pointer's word)
#   MT5  `_ret_ptr_src` without its dereference arm -> R13 does not build (x86 measured: `return *GP16;` refused)
# 6.7.11 FIELD-DESTINATION MUTATION LEDGER (2026-10-14, the same method; R9's `fd` / `fp` / `ff` / top-level rows,
# issues/2026-10-13-struct-field-destination-from-pointer-global-call-or-field.md):
#   MF1  `_fsc_psrc` answering 0 (no pointer-source field arm) -> RED 7: R9 12 of 60 rows x7 (the pointer word
#                                                      stored into the field; the guard row stays green)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
G=small_struct_handle_line
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

TC=tests/tcyr/crossos/small_struct_handle_line.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
FLOOR=247
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
TG=tests/tcyr/crossos/small_struct_global_handle_line.tcyr
[ -f "$TG" ] || { echo "FAIL: $G: $TG is missing"; exit 1; }
NG=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TG")
GFLOOR=266   # 6.7.11: c_reto_8 (a handle of another struct returned) is a refusal now (row C6)
if [ "$NG" -lt "$GFLOOR" ]; then echo "FAIL: $G: only $NG rows in $TG (floor $GFLOOR) — rows were lost"; exit 1; fi
TP=tests/tcyr/crossos/small_struct_pointer_arg.tcyr
[ -f "$TP" ] || { echo "FAIL: $G: $TP is missing"; exit 1; }
NP=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TP")
PFLOOR=69
if [ "$NP" -lt "$PFLOOR" ]; then echo "FAIL: $G: only $NP rows in $TP (floor $PFLOOR) — rows were lost"; exit 1; fi
TQ=tests/tcyr/crossos/small_struct_pointer_copy.tcyr
[ -f "$TQ" ] || { echo "FAIL: $G: $TQ is missing"; exit 1; }
NQ=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TQ")
QFLOOR=67
if [ "$NQ" -lt "$QFLOOR" ]; then echo "FAIL: $G: only $NQ rows in $TQ (floor $QFLOOR) — rows were lost"; exit 1; fi

# The filed repro, verbatim (docs/development/issues/archived/2026-10-08-small-struct-local-from-address-is-value-not-handle.md).
cat > "$D/repro.cyr" <<'EOF'
include "lib/alloc.cyr"
struct S8 { v; }
struct H { a; b; }
var h8 = 0;
var h16 = 0;
fn run(): i64 {
    h8 = alloc(8);
    h16 = alloc(16);
    var q: S8 = h8;          # same result with alloc(8) or a `fn gp(): *S8` call
    var hq: H = h16;
    q.v = 5;
    hq.a = 7;
    var f = |d| { q.v = q.v + d; hq.a = hq.a + d; return 0; };
    callptr(f, 10);
    return load64(h8) * 100 + load64(h16);   # heap words behind each local
}
alloc_init();
var r = run();
syscall(60, r % 256);
EOF

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

# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build)
# and LAST (the last line of its output, CR stripped).
run_leg() {
    RC=-1; LAST=''
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3.exe" 2> "$3.err" || return 0 ;;
    esac
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
XLEGS="x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1"

echo "R0. the filed repro, verbatim (exit 237; 17 = the 8 B local held the address as its value)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/repro.cyr" "$D/r0_$n"
    if [ "$RC" -eq -1 ]; then bad "R0 $leg: did not build: $(grep '^error' "$D/r0_$n.err" | head -1)"
    elif [ "$RC" -eq 237 ]; then ok "R0 $leg: exit 237"
    else bad "R0 $leg: exit $RC, want 237"; fi
done

echo "R1. $TC ($N rows)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "R1 $leg: the values file did not build: $(grep '^error' "$D/t_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "R1 $leg: $LAST"
    else bad "R1 $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

echo "R2. $TG ($NG rows: the handle line for globals)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TG" "$D/g_$n"
    if [ "$RC" -eq -1 ]; then bad "R2 $leg: the values file did not build: $(grep '^error' "$D/g_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NG passed, 0 failed ($NG total)" ]; then ok "R2 $leg: $LAST"
    else bad "R2 $leg: exit $RC, '$LAST' (want '$NG passed, 0 failed ($NG total)') $(grep -m3 'FAIL' "$D/g_$n.out" | tr '\n' ' ')"; fi
done

echo "R3. $TP ($NP rows: a pointer into a by-value struct parameter of 8 B or less)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TP" "$D/pa_$n"
    if [ "$RC" -eq -1 ]; then bad "R3 $leg: the values file did not build: $(grep '^error' "$D/pa_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NP passed, 0 failed ($NP total)" ]; then ok "R3 $leg: $LAST"
    else bad "R3 $leg: exit $RC, '$LAST' (want '$NP passed, 0 failed ($NP total)') $(grep -m3 'FAIL' "$D/pa_$n.out" | tr '\n' ' ')"; fi
done

# The filed repro, verbatim (docs/development/issues/archived/2026-10-11-typed-pointer-into-small-byvalue-struct-param.md).
cat > "$D/repro_b.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S1 { u; }
struct S4 { a: i32; }
fn bs1(b: S1): i64 { return b.u; }
fn bs4(b: S4): i64 { return b.a; }
fn go(): i64 {
    var s: S1; s.u = 5;
    var t: S4; t.a = 6;
    var sp: *S1 = &s;
    var tp: *S4 = &t;
    var r = 0;
    if (bs1(sp) == 5) { r = r + 1; }      # a `*S1` local into `b: S1` (8 B, passed by value)
    if (bs4(tp) == 6) { r = r + 10; }     # a `*S4` local into `b: S4` (4 B)
    if (bs1(&s) == 5) { r = r + 100; }    # `&s` into `b: S1`
    return r;
}
syscall(60, go());
EOF
echo "R4. the filed pointer-argument repro, verbatim (exit 111; 0 = each callee read the pointer's bits)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/repro_b.cyr" "$D/r4_$n"
    if [ "$RC" -eq -1 ]; then bad "R4 $leg: did not build: $(grep '^error' "$D/r4_$n.err" | head -1)"
    elif [ "$RC" -eq 111 ]; then ok "R4 $leg: exit 111"
    else bad "R4 $leg: exit $RC, want 111"; fi
done

echo "R5. $TQ ($NQ rows: struct copies through a *T of 8 B or less)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TQ" "$D/pq_$n"
    if [ "$RC" -eq -1 ]; then bad "R5 $leg: the values file did not build: $(grep '^error' "$D/pq_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NQ passed, 0 failed ($NQ total)" ]; then ok "R5 $leg: $LAST"
    else bad "R5 $leg: exit $RC, '$LAST' (want '$NQ passed, 0 failed ($NQ total)') $(grep -m3 'FAIL' "$D/pq_$n.out" | tr '\n' ' ')"; fi
done

TD=tests/tcyr/crossos/struct_deref_whole_operand.tcyr
[ -f "$TD" ] || { echo "FAIL: $G: $TD is missing"; exit 1; }
ND=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TD")
DFLOOR=78
if [ "$ND" -lt "$DFLOOR" ]; then echo "FAIL: $G: only $ND rows in $TD (floor $DFLOOR) — rows were lost"; exit 1; fi

TF=tests/tcyr/crossos/struct_field_left_operand.tcyr
[ -f "$TF" ] || { echo "FAIL: $G: $TF is missing"; exit 1; }
NF=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TF")
FFLOOR=88
if [ "$NF" -lt "$FFLOOR" ]; then echo "FAIL: $G: only $NF rows in $TF (floor $FFLOOR) — rows were lost"; exit 1; fi
echo "R6. $TF ($NF rows: a struct-typed field or a *T dereference as an operator's left operand)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TF" "$D/fl_$n"
    if [ "$RC" -eq -1 ]; then bad "R6 $leg: the values file did not build: $(grep '^error' "$D/fl_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NF passed, 0 failed ($NF total)" ]; then ok "R6 $leg: $LAST"
    else bad "R6 $leg: exit $RC, '$LAST' (want '$NF passed, 0 failed ($NF total)') $(grep -m3 'FAIL' "$D/fl_$n.out" | tr '\n' ' ')"; fi
done

# The filed repro, verbatim (docs/development/issues/archived/2026-10-08-struct-field-left-operand-never-dispatches.md).
cat > "$D/repro_f.cyr" <<'EOF'
struct P2 { x; y; }
struct H { n; p: P2; }
fn P2_sub(a: *P2, b: *P2): i64 { return 100 + a.x * 10 + b.x; }
fn main(): i64 {
    var h: H = H { 1, 3, 4 };
    var s: P2 = P2 { 9, 9 };
    return h.p - s;
}
syscall(60, main());
EOF
sed 's/    return h.p - s;/    return (h.p - s) - 100;/' "$D/repro_f.cyr" > "$D/repro_fd.cyr"
echo "R7. the filed field-left-operand repro, verbatim (exit 139 = P2_sub; 250 = the integer 3 - 9), and its twin (R7d, exit 39)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/repro_f.cyr" "$D/r7_$n"
    if [ "$RC" -eq -1 ]; then bad "R7 $leg: did not build: $(grep '^error' "$D/r7_$n.err" | head -1)"
    elif [ "$RC" -eq 139 ]; then ok "R7 $leg: exit 139"
    else bad "R7 $leg: exit $RC, want 139"; fi
    run_leg "$leg" "$D/repro_fd.cyr" "$D/r7d_$n"
    if [ "$RC" -eq -1 ]; then bad "R7d $leg: did not build: $(grep '^error' "$D/r7d_$n.err" | head -1)"
    elif [ "$RC" -eq 39 ]; then ok "R7d $leg: exit 39"
    else bad "R7d $leg: exit $RC, want 39"; fi
done

TB=tests/tcyr/crossos/struct_operator_result_binding.tcyr
[ -f "$TB" ] || { echo "FAIL: $G: $TB is missing"; exit 1; }
NB=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TB")
BFLOOR=33
if [ "$NB" -lt "$BFLOOR" ]; then echo "FAIL: $G: only $NB rows in $TB (floor $BFLOOR) — rows were lost"; exit 1; fi
echo "R8. $TB ($NB rows: an untyped binding of a struct-returning operator takes the struct type)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TB" "$D/ob_$n"
    if [ "$RC" -eq -1 ]; then bad "R8 $leg: the values file did not build: $(grep '^error' "$D/ob_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NB passed, 0 failed ($NB total)" ]; then ok "R8 $leg: $LAST"
    else bad "R8 $leg: exit $RC, '$LAST' (want '$NB passed, 0 failed ($NB total)') $(grep -m3 'FAIL' "$D/ob_$n.out" | tr '\n' ' ')"; fi
done

TS=tests/tcyr/crossos/struct_pointer_source_copy.tcyr
[ -f "$TS" ] || { echo "FAIL: $G: $TS is missing"; exit 1; }
NS=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TS")
SFLOOR=60
if [ "$NS" -lt "$SFLOOR" ]; then echo "FAIL: $G: only $NS rows in $TS (floor $SFLOOR) — rows were lost"; exit 1; fi
echo "R9. $TS ($NS rows: a struct copy through a *T global, a : *T call or a *T field)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TS" "$D/ps_$n"
    if [ "$RC" -eq -1 ]; then bad "R9 $leg: the values file did not build: $(grep '^error' "$D/ps_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NS passed, 0 failed ($NS total)" ]; then ok "R9 $leg: $LAST"
    else bad "R9 $leg: exit $RC, '$LAST' (want '$NS passed, 0 failed ($NS total)') $(grep -m3 'FAIL' "$D/ps_$n.out" | tr '\n' ' ')"; fi
done

echo "R10. $TD ($ND rows: a whole dereference of a *S as an address-passed argument or right operand)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TD" "$D/dw_$n"
    if [ "$RC" -eq -1 ]; then bad "R10 $leg: the values file did not build: $(grep '^error' "$D/dw_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$ND passed, 0 failed ($ND total)" ]; then ok "R10 $leg: $LAST"
    else bad "R10 $leg: exit $RC, '$LAST' (want '$ND passed, 0 failed ($ND total)') $(grep -m3 'FAIL' "$D/dw_$n.out" | tr '\n' ' ')"; fi
done

TA=tests/tcyr/crossos/struct_deref_assign_copy.tcyr
[ -f "$TA" ] || { echo "FAIL: $G: $TA is missing"; exit 1; }
NA=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TA")
AFLOOR=76
if [ "$NA" -lt "$AFLOOR" ]; then echo "FAIL: $G: only $NA rows in $TA (floor $AFLOOR) — rows were lost"; exit 1; fi
echo "R11. $TA ($NA rows: an assignment from a dereference of a *S copies the struct)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TA" "$D/da_$n"
    if [ "$RC" -eq -1 ]; then bad "R11 $leg: the values file did not build: $(grep '^error' "$D/da_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NA passed, 0 failed ($NA total)" ]; then ok "R11 $leg: $LAST"
    else bad "R11 $leg: exit $RC, '$LAST' (want '$NA passed, 0 failed ($NA total)') $(grep -m3 'FAIL' "$D/da_$n.out" | tr '\n' ' ')"; fi
done

TGP=tests/tcyr/crossos/generic_ptr_struct_source.tcyr
[ -f "$TGP" ] || { echo "FAIL: $G: $TGP is missing"; exit 1; }
NGP=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TGP")
GPFLOOR=72
if [ "$NGP" -lt "$GPFLOOR" ]; then echo "FAIL: $G: only $NGP rows in $TGP (floor $GPFLOOR) — rows were lost"; exit 1; fi
echo "R12. $TGP ($NGP rows: a generic call declared : *T is a struct source)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TGP" "$D/gp_$n"
    if [ "$RC" -eq -1 ]; then bad "R12 $leg: the values file did not build: $(grep '^error' "$D/gp_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NGP passed, 0 failed ($NGP total)" ]; then ok "R12 $leg: $LAST"
    else bad "R12 $leg: exit $RC, '$LAST' (want '$NGP passed, 0 failed ($NGP total)') $(grep -m3 'FAIL' "$D/gp_$n.out" | tr '\n' ' ')"; fi
done

TRC=tests/tcyr/crossos/struct_ptrmode_return_copy.tcyr
[ -f "$TRC" ] || { echo "FAIL: $G: $TRC is missing"; exit 1; }
NRC=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TRC")
RCFLOOR=75
if [ "$NRC" -lt "$RCFLOOR" ]; then echo "FAIL: $G: only $NRC rows in $TRC (floor $RCFLOOR) — rows were lost"; exit 1; fi
echo "R13. $TRC ($NRC rows: a *T returned by value from a struct fn is the struct it points at)"
for leg in $XLEGS $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TRC" "$D/rc_$n"
    if [ "$RC" -eq -1 ]; then bad "R13 $leg: the values file did not build: $(grep '^error' "$D/rc_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$NRC passed, 0 failed ($NRC total)" ]; then ok "R13 $leg: $LAST"
    else bad "R13 $leg: exit $RC, '$LAST' (want '$NRC passed, 0 failed ($NRC total)') $(grep -m3 'FAIL' "$D/rc_$n.out" | tr '\n' ' ')"; fi
done

# crow <label> <want-exit | refuse:<text>> <program> — an x86 compile (and run) row.
crow() {
    printf '%b' "$3" > "$D/c.cyr"
    if "$CC" < "$D/c.cyr" > "$D/c.bin" 2> "$D/c.err"; then
        case "$2" in
            refuse:*) bad "$1: compiled, want the refusal '${2#refuse:}'"; return ;;
        esac
        chmod +x "$D/c.bin"; rc=0; timeout 60 "$D/c.bin" > /dev/null 2>&1 || rc=$?
        if [ "$rc" = "$2" ]; then ok "$1: exit $rc"; else bad "$1: exit $rc, want $2"; fi
    else
        case "$2" in
            refuse:*) if grep -q "${2#refuse:}" "$D/c.err"; then ok "$1: refused by name"
                      else bad "$1: refused, but not with '${2#refuse:}': $(grep -m1 '^error' "$D/c.err")"; fi ;;
            *) bad "$1: does not compile: $(grep -m1 '^error' "$D/c.err")" ;;
        esac
    fi
}
echo "C. compile rows (x86)"
crow "C1 handle <- handle of another struct type rebinds" 58 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nstruct U8 { u; }\nfn f() { var x = alloc(8); var a: S8 = x; a.v = 5; var u: U8 = alloc(8); u.u = 3; a = u; a.v = 8; return load64(x) * 10 + u.u; }\nalloc_init();\nsyscall(60, f());\n'
crow "C1 its 16 B twin" 58 \
  'include "lib/alloc.cyr"\nstruct H { v; w; }\nstruct UH { u; x; }\nfn f() { var x = alloc(16); var a: H = x; a.v = 5; var u: UH = alloc(16); u.u = 3; a = u; a.v = 8; return load64(x) * 10 + u.u; }\nalloc_init();\nsyscall(60, f());\n'
crow "C2 var q: S8 = mku(1) (a U8 value) refused" "refuse:fn return struct-id differs from declared var type" \
  'struct S8 { v; }\nstruct U8 { u; }\nfn mku(n): U8 { var r: U8; r.u = n; return r; }\nfn f() { var q: S8 = mku(1); return q.v; }\nsyscall(60, f());\n'
crow "C2 q = mku(1) into an S8 handle refused" "refuse:cannot copy 'mku' into a variable of a different struct/vector type: 'q'" \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nstruct U8 { u; }\nfn mku(n): U8 { var r: U8; r.u = n; return r; }\nfn f() { var q: S8 = alloc(8); q = mku(1); return q.v; }\nalloc_init();\nsyscall(60, f());\n'
crow "C3 bs1((t)) with t: T1 into p: S1 refused by name (6.7.11, the user's decision 2026-10-13)" "refuse:cannot pass 't' to a parameter of a different struct type in a call to 'bs1'" \
  'struct S1 { a: i8; }\nstruct T1 { b: i8; }\nfn bs1(p: S1) { return p.a; }\nfn f() { var t: T1; t.b = 7; return bs1((t)); }\nsyscall(60, f());\n'
crow "C4 var q: S8 = *pu (pu: *U8) refused" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'q'" \
  'struct S8 { v; }\nstruct U8 { u; }\nfn f() { var u: U8; u.u = 4; var pu: *U8 = &u; var q: S8 = *pu; return q.v; }\nsyscall(60, f());\n'
crow "C4 var q: H = *pu (pu: *UH) refused" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'q'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nfn f() { var u: UH; u.u = 4; var pu: *UH = &u; var q: H = *pu; return q.v; }\nsyscall(60, f());\n'
crow "C4 var q: S8 = *GU (GU: *U8) refused" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'q'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar GU: *U8 = 0;\nfn f() { var u: U8; u.u = 4; GU = &u; var q: S8 = *GU; return q.v; }\nsyscall(60, f());\n'
crow "C7 var q: S8 = (*pu) (pu: *U8) refused (any dereference)" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'q'" \
  'struct S8 { v; }\nstruct U8 { u; }\nfn f() { var u: U8; u.u = 4; var pu: *U8 = &u; var q: S8 = (*pu); return q.v; }\nsyscall(60, f());\n'
crow "C7 var q: H = (*pu) (pu: *UH) refused" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'q'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nfn f() { var u: UH; u.u = 4; var pu: *UH = &u; var q: H = (*pu); return q.v; }\nsyscall(60, f());\n'
crow "C7 var q: S8 = *gu() (a : *U8 fn) refused" "refuse:cannot copy 'gu' into a variable of a different struct/vector type: 'q'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar GV = U8 { 4 };\nfn gu(): *U8 { return &GV; }\nfn f() { var q: S8 = *gu(); return q.v; }\nsyscall(60, f());\n'
crow "C7 var q: S8 = *w.pu (a *U8 field) refused" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'q'" \
  'struct S8 { v; }\nstruct U8 { u; }\nstruct WU { pu: *U8; }\nfn f() { var u: U8; u.u = 4; var w = WU { &u }; var q: S8 = *w.pu; return q.v; }\nsyscall(60, f());\n'
crow "C8 var q: S8 = (*x) with x untyped: a handle (decision 1), holding the word *x reads" 7 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nfn f() { var o = alloc(8); store64(o, 0); var cell = alloc(8); store64(cell, o); var x = cell; var q: S8 = (*x); q.v = 7; return load64(o); }\nalloc_init();\nsyscall(60, f());\n'
crow "C5 return (a, 1) with a handle: the element is its word" 3 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nfn f(): (i64, i64) { var a: S8 = alloc(8); a.v = 3; return (a, 1); }\nalloc_init();\nvar x, y = f();\nsyscall(60, load64(x));\n'
crow "C5 its 16 B twin" 3 \
  'include "lib/alloc.cyr"\nstruct H { v; w; }\nfn f(): (i64, i64) { var a: H = alloc(16); a.v = 3; return (a, 1); }\nalloc_init();\nvar x, y = f();\nsyscall(60, load64(x));\n'
crow "C6 a U8 handle returned from an S8 fn refused by name (6.7.11)" "refuse:a fn returning the struct .S8. takes a value of that struct, or a pointer to one — got .u. (a .U8.)" \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nstruct U8 { u; }\nfn f(): S8 { var u: U8 = alloc(8); u.u = 3; return u; }\nfn g() { var q: S8 = f(); return q.v; }\nalloc_init();\nsyscall(60, g());\n'

echo "GC. compile rows for globals (x86)"
crow "GC1 var ga: Num = 1 is a handle global: ga + gb is pointer arithmetic, no dispatch" 3 \
  'struct Num { v; }\nfn Num_add(a, b) { return a * 100 + b; }\nvar ga: Num = 1;\nvar gb: Num = 2;\nfn f() { return ga + gb; }\nsyscall(60, f());\n'
crow "GC1 its 16 B twin" 3 \
  'struct V2 { a; b; }\nfn V2_add(a, b) { return 77; }\nvar ga: V2 = 1;\nvar gb: V2 = 2;\nfn f() { return ga + gb; }\nsyscall(60, f());\n'
crow "GC1 a global struct value still dispatches" 102 \
  'struct Num { v; }\nfn Num_add(a, b) { return a * 100 + b; }\nvar ga = Num { 1 };\nvar gb = Num { 2 };\nfn f() { return ga + gb; }\nsyscall(60, f());\n'
crow "GC2 var G: S8 = *GU (GU: *U8) refused in the declaration zone" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'G'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar GV = U8 { 4 };\nvar GU: *U8 = &GV;\nvar G: S8 = *GU;\nsyscall(60, G.v);\n'
crow "GC2 var G: H = *GU (GU: *UH) refused in the declaration zone" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'G'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nvar GV = UH { 4, 0 };\nvar GU: *UH = &GV;\nvar G: H = *GU;\nsyscall(60, G.v);\n'
crow "GC2 var G: S8 = *GU refused after the first statement" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'G'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar GV = U8 { 4 };\nvar GU: *U8 = &GV;\nvar k = 0;\nk = 1;\nvar G: S8 = *GU;\nsyscall(60, G.v);\n'
crow "GC6 var G: S8 = (*GU) (GU: *U8) refused in the declaration zone (any dereference)" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'G'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar GV = U8 { 4 };\nvar GU: *U8 = &GV;\nvar G: S8 = (*GU);\nsyscall(60, G.v);\n'
crow "GC6 var G: H = *gu() (a : *UH fn) refused in the declaration zone" "refuse:cannot copy 'gu' into a variable of a different struct/vector type: 'G'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nvar GV = UH { 4, 0 };\nfn gu(): *UH { return &GV; }\nvar G: H = *gu();\nsyscall(60, G.v);\n'
crow "GC6 var G: S8 = *gu() refused after the first statement" "refuse:cannot copy 'gu' into a variable of a different struct/vector type: 'G'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar GV = U8 { 4 };\nfn gu(): *U8 { return &GV; }\nvar k = 0;\nk = 1;\nvar G: S8 = *gu();\nsyscall(60, G.v);\n'
crow "GC6 var G: H = (*GU) refused after the first statement" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'G'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nvar GV = UH { 4, 0 };\nvar GU: *UH = &GV;\nvar k = 0;\nk = 1;\nvar G: H = (*GU);\nsyscall(60, G.v);\n'
crow "GC7 var G: H = *gp() with gp declared below it refused by name (over 8 B pass 1 sizes G)" "refuse:from a dereference of a global or fn declared below it" \
  'struct H { v; w; }\nvar A = H { 4, 0 };\nvar G: H = *gp();\nfn gp(): *H { return &A; }\nsyscall(60, G.v);\n'
crow "GC8 var G: S8 = GW.s + A in the zone: a field left operand dispatches S8_add (decision 11), a value — the zone agrees" 19 \
  'struct S8 { v; }\nfn S8_add(a: S8, b: S8): S8 { var z: S8; z.v = a.v * 3 + b.v; return z; }\nstruct W { s: S8; n; }\nvar A = S8 { 4 };\nvar S0 = S8 { 5 };\nvar GW = W { S0, 1 };\nvar G: S8 = GW.s + A;\nsyscall(60, load64(&G));\n'
crow "GC8 the same after the first statement" 19 \
  'struct S8 { v; }\nfn S8_add(a: S8, b: S8): S8 { var z: S8; z.v = a.v * 3 + b.v; return z; }\nstruct W { s: S8; n; }\nvar A = S8 { 4 };\nvar S0 = S8 { 5 };\nvar GW = W { S0, 1 };\nvar k = 0;\nk = 1;\nvar G: S8 = GW.s + A;\nsyscall(60, load64(&G));\n'
crow "GC8 a local: the same" 19 \
  'struct S8 { v; }\nfn S8_add(a: S8, b: S8): S8 { var z: S8; z.v = a.v * 3 + b.v; return z; }\nstruct W { s: S8; n; }\nfn f() { var a = S8 { 4 }; var s0 = S8 { 5 }; var w = W { s0, 1 }; var q: S8 = w.s + a; return load64(&q); }\nsyscall(60, f());\n'
crow "GC3 var G: H = *P with P declared below it refused by name" "refuse:from a global declared below it" \
  'struct H { v; w; }\nvar G: H = *P;\nvar A = H { 4, 0 };\nvar P: *H = &A;\nsyscall(60, G.v);\n'
crow "GC4 a global declared a value and then a handle is refused" "refuse:redeclared with a different type or size" \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nvar G = S8 { 1 };\nvar G: S8 = alloc(8);\nsyscall(60, G.v);\n'
crow "GC4 ... a call value and then a handle" "refuse:redeclared with a different type or size" \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nfn mk(n): S8 { var r: S8; r.v = n; return r; }\nvar G: S8 = mk(1);\nvar G: S8 = alloc(8);\nsyscall(60, G.v);\n'
crow "GC4 two handle declarations of one global fold" 6 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nvar G: S8 = alloc(8);\nvar G: S8 = alloc(8);\nfn f() { G.v = 6; return load64(load64(&G)); }\nsyscall(60, f());\n'
crow "GC5 a global bound to a handle declared BELOW it binds (the sweep repeats)" 4 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nvar G2: S8 = G1;\nvar G1: S8 = alloc(8);\nfn f() { G1.v = 1; G2 = G1; G2.v = 4; return G1.v; }\nsyscall(60, f());\n'
crow "GC5 a dispatch on a handle declared below it is pointer arithmetic (the sweep repeats)" 0 \
  'include "lib/alloc.cyr"\nstruct S8 { v; }\nfn S8_add(a: S8, b: S8): S8 { var r: S8; r.v = 77; return r; }\nvar G2: S8 = G1 + 8;\nvar G1: S8 = alloc(8);\nsyscall(60, load64(&G2) - 8);\n'

echo "CP. struct copies through a *T of 8 B or less: another struct type refused by name, as over 8 B (x86)"
crow "CP1 l = pu (pu: *U8) refused" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'l'" \
  'struct S8 { v; }\nstruct U8 { u; }\nfn f() { var u: U8; u.u = 4; var pu: *U8 = &u; var l: S8; l.v = 1; l = pu; return l.v; }\nsyscall(60, f());\n'
crow "CP1 its 16 B twin" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'l'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nfn f() { var u: UH; u.u = 4; var pu: *UH = &u; var l: H; l.v = 1; l = pu; return l.v; }\nsyscall(60, f());\n'
crow "CP2 pu = l (pu: *U8) refused" "refuse:cannot copy 'l' into a variable of a different struct/vector type: 'pu'" \
  'struct S8 { v; }\nstruct U8 { u; }\nfn f() { var u: U8; u.u = 4; var pu: *U8 = &u; var l: S8; l.v = 1; pu = l; return u.u; }\nsyscall(60, f());\n'
crow "CP3 G = pu (pu: *U8) refused" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'G'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar G = S8 { 0 };\nfn f() { var u: U8; u.u = 4; var pu: *U8 = &u; G = pu; return G.v; }\nsyscall(60, f());\n'
crow "CP4 q = G through q: *U8 refused" "refuse:cannot copy 'G' into a variable of a different struct/vector type: 'q'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar G = S8 { 0 };\nfn f(q: *U8) { q = G; return q.u; }\nfn g() { var u: U8; u.u = 4; return f(&u); }\nsyscall(60, g());\n'
crow "CP5 p = mku(1) (a U8 value) into p: *S8 refused" "refuse:cannot copy 'mku' into a variable of a different struct/vector type: 'p'" \
  'struct S8 { v; }\nstruct U8 { u; }\nfn mku(n): U8 { var r: U8; r.u = n; return r; }\nfn f() { var x: S8; x.v = 1; var p: *S8 = &x; p = mku(1); return x.v; }\nsyscall(60, f());\n'
crow "CP5 its 16 B twin" "refuse:cannot copy 'mku' into a variable of a different struct/vector type: 'p'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nfn mku(n): UH { var r: UH; r.u = n; r.x = 0; return r; }\nfn f() { var x: H; x.v = 1; var p: *H = &x; p = mku(1); return x.v; }\nsyscall(60, f());\n'
crow "CP6 p = pu (a *U8 into a *S8) rebinds" 17 \
  'struct S8 { v; }\nstruct U8 { u; }\nfn f() { var a: S8; a.v = 1; var u: U8; u.u = 2; var p: *S8 = &a; var pu: *U8 = &u; p = pu; p.v = 7; return a.v * 10 + u.u; }\nsyscall(60, f());\n'

echo "CQ. a struct copy through a *T global / : *T call / *T field: another struct type refused by name (x86)"
crow "CQ1 l = GU (GU: *U8 a global) refused" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'l'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar XU = U8 { 4 };\nvar GU: *U8 = &XU;\nfn f() { var l: S8; l.v = 1; l = GU; return l.v; }\nsyscall(60, f());\n'
crow "CQ2 l = gu() (a : *U8 fn) refused" "refuse:cannot copy 'gu' into a variable of a different struct/vector type: 'l'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar XU = U8 { 4 };\nfn gu(): *U8 { return &XU; }\nfn f() { var l: S8; l.v = 1; l = gu(); return l.v; }\nsyscall(60, f());\n'
crow "CQ3 l = w.pu (a *U8 field) refused" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'l'" \
  'struct S8 { v; }\nstruct U8 { u; }\nstruct WU { pu: *U8; }\nvar XU = U8 { 4 };\nfn f() { var w = WU { &XU }; var l: S8; l.v = 1; l = w.pu; return l.v; }\nsyscall(60, f());\n'
crow "CQ4 G = GU at 16 B (GU: *UH) refused" "refuse:cannot copy 'GU' into a variable of a different struct/vector type: 'G'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nvar XU = UH { 4, 0 };\nvar GU: *UH = &XU;\nvar G = H { 0, 0 };\nfn f() { G = GU; return G.v; }\nsyscall(60, f());\n'
crow "CQ5 l = GI (GI: *i64) into a struct value stays its word" 1 \
  'struct S8 { v; }\nvar XI = 4;\nvar GI: *i64 = &XI;\nfn f() { var l: S8; l.v = 1; l = GI; return l.v == load64(&GI); }\nsyscall(60, f());\n'
crow "CQ6 l = pu + 1 (pointer arithmetic on a *U8) refused" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'l'" \
  'struct S8 { v; }\nstruct U8 { u; }\nvar XU = U8 { 4 };\nfn f() { var pu: *U8 = &XU; var l: S8; l.v = 1; l = pu + 1; return l.v; }\nsyscall(60, f());\n'
crow "CQ6 l = pu + k (16 B) refused naming the pointer" "refuse:cannot copy 'pu' into a variable of a different struct/vector type: 'l'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nvar XU = UH { 4, 0 };\nfn f() { var k = 0; var pu: *UH = &XU; var l: H; l.v = 1; l = pu + k; return l.v; }\nsyscall(60, f());\n'
crow "CQ7 l = pi + 0 (pi: *i64) into a struct value stays its word" 1 \
  'struct S8 { v; }\nvar XI = 4;\nfn f() { var pi: *i64 = &XI; var l: S8; l.v = 1; l = pi + 0; return l.v == pi; }\nsyscall(60, f());\n'

echo "B. an untyped binding of an operator result (x86)"
crow "B1 the C4 case: var c = A + B; c.g = 1; c + c" 111 \
  'struct C4 { r: u8; g: u8; b: u8; a: u8; }\nfn C4_add(a: C4, b: C4): C4 { var r: C4; r.r = a.r + b.r; r.g = a.g + b.g; r.b = a.b + b.b; r.a = a.a + b.a; return r; }\nfn f() { var A = C4 { 1, 2, 3, 4 }; var B = C4 { 10, 20, 30, 40 }; var c = A + B; c.g = 1; var d = c + c; var k = 0; if (c.r == 11) { if (c.g == 1) { if (c.b == 33) { if (c.a == 44) { k = k + 1; } } } } if (d.g == 2) { if (d.a == 88) { k = k + 10; } } if (A.g == 2) { k = k + 100; } return k; }\nsyscall(60, f());\n'
crow "B2 var r = a - b with S8_sub returning i64: r untyped" "refuse:no struct type in scope for 'r'" \
  'struct S8 { v; }\nfn S8_sub(a: S8, b: S8): i64 { return a.v - b.v; }\nfn f() { var a = S8 { 7 }; var b = S8 { 4 }; var r = a - b; return r.v; }\nsyscall(60, f());\n'
crow "B2 its 16 B twin" "refuse:no struct type in scope for 'r'" \
  'struct H { v; w; }\nfn H_sub(a: H, b: H): i64 { return a.v - b.v; }\nfn f() { var a = H { 7, 0 }; var b = H { 4, 0 }; var r = a - b; return r.v; }\nsyscall(60, f());\n'

echo "F. a field / dereference left operand refused exactly as a struct variable is (x86)"
crow "F1 w.s + 1 with no S8_add refused" "refuse:undefined function 'S8_add'" \
  'struct S8 { v; }\nstruct W { n; s: S8; }\nfn f() { var w = W { 1, 5 }; return w.s + 1; }\nsyscall(60, f());\n'
crow "F1 its variable twin, s + 1" "refuse:undefined function 'S8_add'" \
  'struct S8 { v; }\nfn f() { var s = S8 { 5 }; return s + 1; }\nsyscall(60, f());\n'
crow "F1 *p + 1 (p: *S8) with no S8_add refused" "refuse:undefined function 'S8_add'" \
  'struct S8 { v; }\nfn f() { var s = S8 { 5 }; var p: *S8 = &s; return *p + 1; }\nsyscall(60, f());\n'
crow "F2 w.s + a into S8_add(a: U8, ..) refused by name" "refuse:cannot pass 'w' to a parameter of a different struct type in a call to 'S8_add'" \
  'struct S8 { v; }\nstruct U8 { u; }\nstruct W { n; s: S8; }\nfn S8_add(a: U8, b: S8): i64 { return a.u; }\nfn f() { var w = W { 1, 5 }; var a = S8 { 4 }; return w.s + a; }\nsyscall(60, f());\n'
crow "F2 its variable twin" "refuse:cannot pass 's' to a parameter of a different struct type in a call to 'S8_add'" \
  'struct S8 { v; }\nstruct U8 { u; }\nfn S8_add(a: U8, b: S8): i64 { return a.u; }\nfn f() { var s = S8 { 5 }; var a = S8 { 4 }; return s + a; }\nsyscall(60, f());\n'
crow "F3 var G: H = GW.s + A in the zone refused (a 9-16 B result needs a frame)" "refuse:'H_add' returns a struct by value, and a struct result needs storage in a fn's frame" \
  'struct H { v; w; }\nstruct W { n; s: H; }\nfn H_add(a: H, b: H): H { var r: H; r.v = a.v + b.v; r.w = 0; return r; }\nvar GW = W { 1, 5, 0 };\nvar A = H { 4, 0 };\nvar G: H = GW.s + A;\nsyscall(60, G.v);\n'
crow "F3 ... after the first statement" "refuse:'H_add' returns a struct by value, and a struct result needs storage in a fn's frame" \
  'struct H { v; w; }\nstruct W { n; s: H; }\nfn H_add(a: H, b: H): H { var r: H; r.v = a.v + b.v; r.w = 0; return r; }\nvar GW = W { 1, 5, 0 };\nvar A = H { 4, 0 };\nvar k = 0;\nk = 1;\nvar G: H = GW.s + A;\nsyscall(60, G.v);\n'

crow "F4 var R = takeh(*GP + A) at top level refused (a dereference-led 9-16 B result as an argument needs a frame)" "refuse:'H_add' returns a struct by value, and a struct result needs storage in a fn's frame" \
  'struct H { v; w; }\nfn H_add(a: H, b: H): H { var r: H; r.v = a.v + b.v; r.w = 0; return r; }\nfn takeh(s: H): i64 { return s.v; }\nvar X = H { 5, 0 };\nvar GP: *H = &X;\nvar A = H { 4, 0 };\nvar R = takeh(*GP + A);\nsyscall(60, R);\n'
crow "F4 ... after the first statement" "refuse:'H_add' returns a struct by value, and a struct result needs storage in a fn's frame" \
  'struct H { v; w; }\nfn H_add(a: H, b: H): H { var r: H; r.v = a.v + b.v; r.w = 0; return r; }\nfn takeh(s: H): i64 { return s.v; }\nvar X = H { 5, 0 };\nvar GP: *H = &X;\nvar A = H { 4, 0 };\nvar k = 0;\nk = 1;\nvar R = takeh(*GP + A);\nsyscall(60, R);\n'
crow "F4 its field twin, takeh(GW.s + A)" "refuse:'H_add' returns a struct by value, and a struct result needs storage in a fn's frame" \
  'struct H { v; w; }\nstruct W { n; s: H; }\nfn H_add(a: H, b: H): H { var r: H; r.v = a.v + b.v; r.w = 0; return r; }\nfn takeh(s: H): i64 { return s.v; }\nvar GW = W { 1, 5, 0 };\nvar A = H { 4, 0 };\nvar k = 0;\nk = 1;\nvar R = takeh(GW.s + A);\nsyscall(60, R);\n'

echo "D. a whole dereference as an address-passed argument or right operand: another struct refused by name (x86)"
crow "D1 takeh(*pu) (pu: *UH) refused" "refuse:cannot pass 'pu' to a parameter of a different struct type in a call to 'takeh'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nfn takeh(s: H): i64 { return s.v; }\nfn f() { var y = UH { 5, 0 }; var pu: *UH = &y; return takeh(*pu); }\nsyscall(60, f());\n'
crow "D1 rd8(*pu) into a *S8 parameter (pu: *U8) refused" "refuse:cannot pass 'pu' to a parameter of a different struct type in a call to 'rd8'" \
  'struct S8 { v; }\nstruct U8 { u; }\nfn rd8(p: *S8): i64 { return p.v; }\nfn f() { var y = U8 { 5 }; var pu: *U8 = &y; return rd8(*pu); }\nsyscall(60, f());\n'
crow "D2 a - *pu (pu: *UH) refused" "refuse:cannot pass 'pu' to a parameter of a different struct type in a call to 'H_sub'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nfn H_sub(a: H, b: H): i64 { return a.v - b.v; }\nfn f() { var a = H { 9, 0 }; var y = UH { 5, 0 }; var pu: *UH = &y; return a - *pu; }\nsyscall(60, f());\n'
crow "D2 a - *gu() (a : *UH fn) refused" "refuse:cannot pass 'gu' to a parameter of a different struct type in a call to 'H_sub'" \
  'struct H { v; w; }\nstruct UH { u; x; }\nvar GY = UH { 5, 0 };\nfn gu(): *UH { return &GY; }\nfn H_sub(a: H, b: H): i64 { return a.v - b.v; }\nfn f() { var a = H { 9, 0 }; return a - *gu(); }\nsyscall(60, f());\n'
crow "D3 takeh(*y) with y untyped keeps the word it reads (the struct's address here)" 5 \
  'struct H { v; w; }\nfn takeh(s: H): i64 { return s.v; }\nfn f() { var x = H { 5, 0 }; var cell = &x; var y = &cell; return takeh(*y); }\nsyscall(60, f());\n'

cat > "$D/pq.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S7 { a: i32; b: i16; c: i8; }
struct W7 { n; p: *S7; }
var GP: *S7 = 0;
var G = S7 { 0, 0, 0 };
fn take7(s: S7): i64 { return s.a + s.b + s.c; }
fn gp(): *S7 { return GP; }
fn run(): i64 {
    var m = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (m <= 0) { return 90; }
    if (syscall(SYS_MUNMAP, m + 4096, 4096) != 0) { return 91; }
    GP = m + 4096 - 7;
    GP.a = 100;
    GP.b = 20;
    GP.c = 3;
    var l: S7;
    l = GP;
    if (take7(l) != 123) { return 1; }
    G = GP;
    if (take7(G) != 123) { return 2; }
    var k: S7;
    k = gp();
    if (take7(k) != 123) { return 3; }
    var w: W7;
    w.n = 0;
    w.p = GP;
    var j: S7;
    j = w.p;
    if (take7(j) != 123) { return 4; }
    var ma: S7;
    ma = GP + 0;
    if (take7(ma) != 123) { return 6; }
    return 0;
}
var e = run();
var T = S7 { 0, 0, 0 };
if (e == 0) { T = GP; if (take7(T) != 123) { e = 5; } }
syscall(60, e);
EOF
echo "PQ. a *S7 global / : *S7 call / *S7 field onto the last 7 bytes of a mapping: l = GP, G = GP, l = gp(), l = w.p, top level — no byte past it"
for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
    run_leg "$leg" "$D/pq.cyr" "$D/pq_$leg"
    if [ "$RC" -eq -1 ]; then bad "PQ $leg: did not build: $(grep '^error' "$D/pq_$leg.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "PQ $leg: exit 0"
    else bad "PQ $leg: exit $RC, want 0 (139 = a byte past the object read)"; fi
done

cat > "$D/gp.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S7 { a: i32; b: i16; c: i8; }
var GA: S7 = 0;
var GZ = S7 { 0, 0, 0 };
fn take7(s: S7): i64 { return s.a + s.b + s.c; }
fn r7(): S7 { return GA; }
fn S7_add(l: S7, r: S7): S7 { var t: S7; t.a = l.a + r.a; t.b = l.b + r.b; t.c = l.c + r.c; return t; }
fn run(): i64 {
    var p = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (p <= 0) { return 90; }
    if (syscall(SYS_MUNMAP, p + 4096, 4096) != 0) { return 91; }
    GA = p + 4096 - 7;
    GA.a = 100;
    GA.b = 20;
    GA.c = 3;
    if (take7(GA) != 123) { return 1; }
    var q: S7 = r7();
    if (take7(q) != 123) { return 2; }
    var w: S7 = GZ + GA;
    if (take7(w) != 123) { return 3; }
    var v: S7 = if (q.a == 100) { GA } else { GZ };
    if (take7(v) != 123) { return 4; }
    var c: S7;
    c = GA;
    if (take7(c) != 123) { return 5; }
    return 0;
}
var e = run();
if (e == 0) { if (take7(GA) != 123) { e = 6; } }
var t: S7 = GZ + GA;
if (e == 0) { if (take7(t) != 123) { e = 7; } }
syscall(60, e);
EOF
echo "GP. a 7 B handle GLOBAL ending a mapping, in a fn and at top level: no byte past it is read"
for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
    run_leg "$leg" "$D/gp.cyr" "$D/gp_$leg"
    if [ "$RC" -eq -1 ]; then bad "GP $leg: did not build: $(grep '^error' "$D/gp_$leg.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "GP $leg: exit 0"
    else bad "GP $leg: exit $RC, want 0 (139 = a read past the object)"; fi
done

cat > "$D/pp.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S7 { a: i32; b: i16; c: i8; }
fn take7(s: S7): i64 { return s.a + s.b + s.c; }
fn S7_add(l: S7, r: S7): i64 { return take7(l) * 1000 + take7(r); }
fn mk7(): S7 { var t: S7; t.a = 0; t.b = 0; t.c = 0; return t; }
fn pid(p: *S7): *S7 { return p; }
var GP: *S7 = 0;
fn run(): i64 {
    var p = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (p <= 0) { return 90; }
    if (syscall(SYS_MUNMAP, p + 4096, 4096) != 0) { return 91; }
    var x: *S7 = 0;
    x = p + 4096 - 7;
    x.a = 100;
    x.b = 20;
    x.c = 3;
    GP = x;
    if (take7(x) != 123) { return 1; }
    if (take7(pid(x)) != 123) { return 2; }
    if (mk7() + x != 123) { return 3; }
    if (take7(GP) != 123) { return 4; }
    var f = |d| take7(x) + d;
    if (callptr(f, 0) != 123) { return 5; }
    return 0;
}
var e = run();
if (e == 0) { if (take7(GP) != 123) { e = 6; } }
if (e == 0) { if (mk7() + GP != 123) { e = 7; } }
syscall(60, e);
EOF
echo "PP. a *S7 onto the last 7 bytes of a mapping, passed by value, in a fn and at top level: no byte past it is read"
for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
    run_leg "$leg" "$D/pp.cyr" "$D/pp_$leg"
    if [ "$RC" -eq -1 ]; then bad "PP $leg: did not build: $(grep '^error' "$D/pp_$leg.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "PP $leg: exit 0"
    else bad "PP $leg: exit $RC, want 0 (139 = a read past the object)"; fi
done

cat > "$D/pm.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S7 { a: i32; b: i16; c: i8; }
var G7 = S7 { 0, 0, 0 };
fn take7(s: S7): i64 { return s.a + s.b + s.c; }
fn mk7(): S7 { var t: S7; t.a = 200; t.b = 40; t.c = 6; return t; }
fn qr(q: *S7, r: S7): i64 { q = r; return 0; }
fn lq(q: *S7): i64 { var l: S7; l = q; return take7(l); }
fn qg(q: *S7): i64 { q = G7; return 0; }
fn run(): i64 {
    var m = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (m <= 0) { return 90; }
    if (syscall(SYS_MUNMAP, m + 4096, 4096) != 0) { return 91; }
    var p: *S7 = 0;
    p = m + 4096 - 7;
    p.a = 100;
    p.b = 20;
    p.c = 3;
    var l: S7;
    l = p;
    if (take7(l) != 123) { return 1; }
    G7 = p;
    if (take7(G7) != 123) { return 2; }
    if (lq(p) != 123) { return 3; }
    var r: S7;
    r.a = 200;
    r.b = 40;
    r.c = 6;
    qr(p, r);
    if (p.a + p.b + p.c != 246) { return 4; }
    l.a = 300;
    l.b = 50;
    l.c = 9;
    p = l;
    if (p.a + p.b + p.c != 359) { return 5; }
    qg(p);
    if (p.a + p.b + p.c != 123) { return 6; }
    p = mk7();
    if (p.a + p.b + p.c != 246) { return 7; }
    return 0;
}
syscall(60, run());
EOF
echo "PM. a *S7 onto the last 7 bytes of a mapping: l = p, G = p, l = q, q = r, p = l, q = G, p = mk7() — no byte past it"
for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
    run_leg "$leg" "$D/pm.cyr" "$D/pm_$leg"
    if [ "$RC" -eq -1 ]; then bad "PM $leg: did not build: $(grep '^error' "$D/pm_$leg.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "PM $leg: exit 0"
    else bad "PM $leg: exit $RC, want 0 (139 = a byte past the object read or written)"; fi
done

cat > "$D/p.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S7 { a: i32; b: i16; c: i8; }
fn take7(s: S7): i64 { return s.a + s.b + s.c; }
fn r7(x): S7 { var h: S7 = x; return h; }
fn S7_add(l: S7, r: S7): S7 { var t: S7; t.a = l.a + r.a; t.b = l.b + r.b; t.c = l.c + r.c; return t; }
fn run(): i64 {
    var p = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (p <= 0) { return 90; }
    if (syscall(SYS_MUNMAP, p + 4096, 4096) != 0) { return 91; }
    var x = p + 4096 - 7;
    var a: S7 = x;
    a.a = 100;
    a.b = 20;
    a.c = 3;
    var s = take7(a);
    if (s != 123) { return 1; }
    var q: S7 = r7(x);
    if (take7(q) != 123) { return 2; }
    var z: S7;
    z.a = 0;
    z.b = 0;
    z.c = 0;
    var w: S7 = z + a;
    if (take7(w) != 123) { return 3; }
    var v: S7 = if (s == 123) { a } else { z };
    if (take7(v) != 123) { return 4; }
    var f = |d| { return take7(a) + d; };
    if (callptr(f, 0) != 123) { return 5; }
    var c: S7;
    c = a;
    if (take7(c) != 123) { return 6; }
    return 0;
}
syscall(60, run());
EOF
echo "P. a 7 B handle ending a mapping: no byte past it is read (Linux x86_64, aarch64)"
for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
    run_leg "$leg" "$D/p.cyr" "$D/p_$leg"
    if [ "$RC" -eq -1 ]; then bad "P $leg: did not build: $(grep '^error' "$D/p_$leg.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "P $leg: exit 0"
    else bad "P $leg: exit $RC, want 0 (139 = a read past the object)"; fi
done

cat > "$D/ps.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S7 { a: i32; b: i16; c: i8; }
fn S7_sum(self: S7): i64 { return self.a + self.b + self.c; }
struct S3 { a: i16; c: i8; }
fn S3_sum(self: S3): i64 { return self.a + self.c; }
var GH: S7 = 0;
var GP: *S7 = 0;
fn run(): i64 {
    var m = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (m <= 0) { return 90; }
    if (syscall(SYS_MUNMAP, m + 4096, 4096) != 0) { return 91; }
    var pp: *S7 = 0;
    pp = m + 4096 - 7;
    pp.a = 100;
    pp.b = 20;
    pp.c = 3;
    if (pp.sum() != 123) { return 1; }
    var h: S7 = m + 4096 - 7;
    if (h.sum() != 123) { return 2; }
    GH = m + 4096 - 7;
    if (GH.sum() != 123) { return 3; }
    GP = pp;
    if (GP.sum() != 123) { return 4; }
    var m3 = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (syscall(SYS_MUNMAP, m3 + 4096, 4096) != 0) { return 92; }
    var p3: *S3 = 0;
    p3 = m3 + 4096 - 3;
    p3.a = 40;
    p3.c = 2;
    if (p3.sum() != 42) { return 5; }
    var v = S7 { 1, 2, 3 };
    if (v.sum() != 6) { return 6; }
    return 0;
}
var e = run();
if (e == 0) { if (GP.sum() != 123) { e = 7; } }
if (e == 0) { if (GH.sum() != 123) { e = 8; } }
syscall(60, e);
EOF
echo "PS. a by-value self of 7 / 3 B ending a mapping (a *T, a handle, a handle global, a *T global, at top level): no byte past it is read"
for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
    run_leg "$leg" "$D/ps.cyr" "$D/ps_$leg"
    if [ "$RC" -eq -1 ]; then bad "PS $leg: did not build: $(grep '^error' "$D/ps_$leg.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "PS $leg: exit 0"
    else bad "PS $leg: exit $RC, want 0 (139 = a read past the receiver)"; fi
done

cat > "$D/pd.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct S7 { a: i32; b: i16; c: i8; }
struct PW7 { p: *S7; }
fn take7(s: S7): i64 { return s.a + s.b + s.c; }
var GP7: *S7 = 0;
fn gp7(): *S7 { return GP7; }
fn run(): i64 {
    var m = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    if (m <= 0) { return 90; }
    if (syscall(SYS_MUNMAP, m + 4096, 4096) != 0) { return 91; }
    var pp: *S7 = 0;
    pp = m + 4096 - 7;
    pp.a = 100;
    pp.b = 20;
    pp.c = 3;
    GP7 = pp;
    var q: S7 = (*pp);
    if (take7(q) != 123) { return 1; }
    var r: S7 = *(pp + 0);
    if (take7(r) != 123) { return 2; }
    var s: S7 = *gp7();
    if (take7(s) != 123) { return 3; }
    var w = PW7 { pp };
    var t: S7 = *w.p;
    if (take7(t) != 123) { return 4; }
    return 0;
}
syscall(60, run());
EOF
echo "PD. a dereference initialiser of a *S7 ending a mapping — (*p), *(p + 0), *gp(), *w.p: no byte past it is read"
for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
    run_leg "$leg" "$D/pd.cyr" "$D/pd_$leg"
    if [ "$RC" -eq -1 ]; then bad "PD $leg: did not build: $(grep '^error' "$D/pd_$leg.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "PD $leg: exit 0"
    else bad "PD $leg: exit $RC, want 0 (139 = a read past the object)"; fi
done

# px_src N: every consumer of a dereference `*p` of an N-byte struct (N i8 fields) ending a mapping; the
# exit names the first row that read a wrong first byte, 139 a read past the object (6.7.11).
px_src() {
    _f=""; _l=""; _i=0
    while [ "$_i" -lt "$1" ]; do _f="$_f f$_i: i8;"; _l="$_l${_l:+, }$((_i + 1))"; _i=$((_i + 1)); done
    cat <<EOF
include "lib/syscalls.cyr"
struct SN {$_f }
fn page_end(): *SN {
    var m = syscall(SYS_MMAP, 0, 8192, 3, 0x22, 0 - 1, 0);
    syscall(SYS_MUNMAP, m + 4096, 4096);
    var p = m + 4096 - $1;
    var i = 0;
    while (i < $1) { store8(p + i, 65 + i); i = i + 1; }
    return p;
}
fn ok(s: SN): i64 { if (s.f0 != 65) { return 0; } return 1; }
fn okp(s: *SN): i64 { if (s.f0 != 65) { return 0; } return 1; }
var P: *SN = 0;
fn gp(): *SN { return P; }
var Q: *SN = page_end();
fn gq(): *SN { return Q; }
struct WN { p: *SN; }
var WQ = WN { Q };
var GZ1: SN = *Q;
var GZ2: SN = (*Q);
var GZ3: SN = *gq();
var GZ4: SN = *(Q + 0);
var GZ5: SN = *WQ.p;
var TZ6 = ok(*Q);
fn rd(): SN { return *P; }
fn rdp(): SN { return (*P); }
fn infn(): i64 {
    var l1: SN = *P;
    if (ok(l1) == 0) { return 21; }
    var l2: SN = (*P);
    if (ok(l2) == 0) { return 22; }
    var l3: SN = *gp();
    if (ok(l3) == 0) { return 23; }
    var l4: SN = *(P + 0);
    if (ok(l4) == 0) { return 24; }
    var l5: SN = SN { $_l };
    l5 = *P;
    if (ok(l5) == 0) { return 25; }
    if (ok(*P) == 0) { return 26; }
    if (ok((*P)) == 0) { return 27; }
    if (ok(*gp()) == 0) { return 28; }
    var l6: SN = rd();
    if (ok(l6) == 0) { return 29; }
    var l7: SN = rdp();
    if (ok(l7) == 0) { return 30; }
    if (okp(*P) == 0) { return 31; }
    return 0;
}
var e = 0;
if (ok(GZ1) == 0) { e = 1; }
if (ok(GZ2) == 0) { e = 2; }
if (ok(GZ3) == 0) { e = 3; }
if (ok(GZ4) == 0) { e = 4; }
if (ok(GZ5) == 0) { e = 5; }
if (TZ6 == 0) { e = 6; }
P = page_end();
var G1: SN = *P;
if (ok(G1) == 0) { e = 7; }
var G2: SN = (*P);
if (ok(G2) == 0) { e = 8; }
var G3: SN = *gp();
if (ok(G3) == 0) { e = 9; }
var G4: SN = *(P + 0);
if (ok(G4) == 0) { e = 10; }
var G5: SN = SN { $_l };
G5 = *P;
if (ok(G5) == 0) { e = 11; }
if (ok(*P) == 0) { e = 12; }
if (okp(*P) == 0) { e = 13; }
if (e == 0) { e = infn(); }
syscall(SYS_EXIT, e);
EOF
}
echo "PX. a dereference *p of a struct of 1..7 B ending a mapping (8 B the control), every consumer — a global's declaration (the zone, after it), G = *p, l = *p, f(*p), f(*p) into a *S, return *p, in a fn and at top level: no byte past it is read"
for n in 1 2 3 4 5 6 7 8; do
    px_src "$n" > "$D/px$n.cyr"
    for leg in x86 $( [ -n "$A64" ] && echo a64 ); do
        run_leg "$leg" "$D/px$n.cyr" "$D/px${n}_$leg"
        if [ "$RC" -eq -1 ]; then bad "PX $n B $leg: did not build: $(grep '^error' "$D/px${n}_$leg.err" | head -1)"
        elif [ "$RC" -eq 0 ]; then ok "PX $n B $leg: exit 0"
        else bad "PX $n B $leg: exit $RC, want 0 (139 = a read past the object; 1..31 the row)"; fi
    done
done

cat > "$D/as.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/async.cyr"
struct S8 { v; }
struct T6 { a: i32; b: i16; }
fn take8(s: S8): i64 { return s.v; }
fn take6(s: T6): i64 { return s.a * 10 + s.b; }
fn mk8(n): S8 { var r: S8; r.v = n; return r; }
fn ret8(): S8 { var h: S8 = alloc(8); h.v = 4; return h; }
fn nopark(): i64 { return 0; }
var GX = 0;
var GY = 0;
async fn st(): i64 {
    var a: S8 = GX;
    a.v = 5;
    var s1 = await nopark();
    var q: S8 = a;
    a.v = a.v + take8(a);
    var t: T6 = GY;
    t.a = 7;
    t.b = 0 - 2;
    var s2 = await nopark();
    if (q.v != 10) { return 1; }
    var c: S8 = mk8(3);
    a = c;
    c.v = 0;
    var r: S8 = ret8();
    return take8(a) * 1000 + load64(GX) * 100 + take6(t) + r.v * 10000;
}
fn main(): i64 {
    alloc_init();
    GX = alloc(8);
    GY = alloc(8);
    var C = st();
    var r1 = future_force(C);
    var r2 = future_force(C);
    var r3 = future_force(C);
    if (r3 != 43368) { syscall(60, 10 + r3 % 100); }
    syscall(60, 0);
    return 0;
}
var e = main();
EOF
echo "AS. an async fn body across two awaits (CYRIUS_ASYNC=1; x86_64)"
for leg in x86:CYRIUS_ASYNC=1; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$D/as.cyr" "$D/as_$n"
    if [ "$RC" -eq -1 ]; then bad "AS $leg: did not build: $(grep '^error' "$D/as_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "AS $leg: exit 0"
    else bad "AS $leg: exit $RC, want 0"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a struct local or global of 8 B or less from a non-struct-value initialiser is a handle, as over 8 B: the filed repro (R0) and every initialiser / consumer / size row for locals (R1) and globals (R2) on x86_64 / IR / DCE / aarch64 / cx / PE, the compile rows (C, GC), no read past a 7 B object, local or global (P, GP), nor past a by-value receiver (PS) or a dereferenced source (PD), nor past a dereference of a 1..7 B struct in any value use (PX), an async body (AS); a pointer into a by-value struct parameter of 8 B or less passes its struct (R3, the filed repro R4, no read past it: PP); a struct copy through a *T of 8 B or less copies the struct (R5, CP, no byte past it: PM); a struct-typed field or a *T dereference as an operator's left operand dispatches (R6, the filed repro R7, F, GC8); an untyped binding of a struct-returning operator takes its type at every size (R8, B); a struct copy through a *T global, a : *T call or a *T field copies the struct (R9, CQ, no byte past it: PQ); a whole dereference of a *S as an address-passed argument or right operand passes its struct (R10, D); an assignment from a dereference of a *S copies the struct (R11); a generic call declared : *T is a struct source (R12); a *T returned by value from a struct fn is the struct it points at (R13)"
