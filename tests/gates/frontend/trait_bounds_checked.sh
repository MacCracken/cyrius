#!/bin/sh
# tests/gates/frontend/trait_bounds_checked.sh — 6.7.1 (C3)
#
# TRAIT BOUNDS ON TYPE PARAMETERS ARE CHECKED: `fn f<T: Show + Eq>`, `struct Box<T: Show>`.
#
# Before 6.7.1 `<T: Show>` minted a SECOND type parameter named `Show`, so `f(p)` with a struct was
# refused as "a struct beside a second type argument" and nothing was checked. The user's decisions
# (2026-10-07): a bound is a CONTRACT — on a bounded T, `v.m()` must be a method of a bound's trait,
# checked at the generic's definition; `T: A + B` requires every impl; a bound is satisfied by
# `impl Trait for X` whatever X is. The runtime half is tests/tcyr/crossos/trait_bounds.tcyr.
#
#   D  the definition: an undeclared trait in a bound; a method no bound declares (the contract),
#      also on a `var q: T` local; a method two bounds declare (ambiguous); a bound with type
#      arguments; a bound on a third type parameter (6.7.16: the third parameter itself is refused, its bound
#      with it — the user's D8); `<T: >` — each refused once, by name
#   I  an instantiation whose type has no impl: inferred, explicit, the i64 base reached by a scalar
#      call (whose body is then the dead stub), `&g`, a tail call, a second bounded parameter, and
#      an unbounded generic forwarding its T to a bounded one — refused once, naming the trait and
#      the `impl` it needs
#   S  a bounded generic STRUCT: `Box<R>`, a written `Box<i64>` and a bare `Box` (its i64 base) with
#      no impl are refused; `struct W<T> { b: Box<T>; }` is fine until W's i64 base is used; a
#      generic fn instantiating `Box<T>` has no i64 instance (refused at `mk(5)`, not at `mk`)
#   B  (6.7.14) more than 64 bounded receivers in one generic: the receivers' table (`_bnr_tab`) held 64
#      and dropped the rest, so a later `z.show()` was no bounded site and the i64 base (live: `impl Show
#      for i64`) refused it — "no struct type in scope for 'z'". B1 a parameter, 65 `var cN: T = v;`, then
#      `z.show()`: exit 5; B1b 130 (two growths). issues/archived/2026-10-14-generic-carrier-table-caps-at-64-silently.md
#   F  (6.7.14) A GENERIC FORWARDING ITS T TO A BOUNDED GENERIC: the stub scan counted the forward a struct use
#      whenever the callee's base was bad for its bound, so `fn o<T>(x: T) { return gb(x); }` with only `impl Show
#      for f64` had the stub base, which has no scalar instance — `o(h)` / `o<f64>(h)` were refused "uses its type
#      parameter as a struct" with a note naming i64. The forward now makes o's base bad at i64 alone
#      (`_bnd_base_bad` -> `_bbs_fwd_bad`): o(h) calls o$f64, o(3) is refused naming the forward and the impl i64
#      lacks. F0 the filed repro verbatim (5); F1 o<f64>(h); F2 o(3) refused once, the forward and the note, not the
#      stub text; F3 both impls (56); F4 / F4b two levels o2 -> o -> gb; F5 an explicit gb<T>(x) forward with a
#      struct too; F6 / F6b a generic method forward (6.7.16: F6b names it `P.gbm`, as the source spells it, in the
#      refusal and its note — it named the fn table's `P_gbm`; generic_method_infer.sh N3a-N3d); F7 / F7b a forward to
#      a generic instantiating a bounded
#      struct; F8 / F8b / F8c / F8d mutual recursion (a cycle ends); F9 &o; F10 a tail call; F11 the definition alone;
#      F12 a chain of 64 forwards (6.7.14's reach: `_bbf_dep`'s cap, lifted by 6.7.15's F13-F15e).
#      I7 (an unbounded generic forwarding to a bounded one, u(5)) now names the forward, not the stub text.
#      Filed: docs/development/issues/archived/2026-10-14-generic-forwarding-to-bounded-generic-refused-at-f64.md
#      Mutants (2026-10-16, a one-edit scratch copy of the tree each, its 2-stage cycc, this gate run from it):
#      MF1 `_bnd_base_bad` without its forwarding arm (`_bbs_fwd_bad` answering 0) -> RED I7 and every F row but F3
#      (the forwarder's i64 base is emitted and refused at its definition naming gb, called or not — F11 too);
#      MF2 the stub scan's mode 1 counting a bound-bad callee again (6.7.1's test; = the compiler before) -> RED I7
#      F0 F1 F2 F4 F4b F5 F6 F6b F7 F7b F8b F8c F9 F10 (refused, or with the struct-stub text and no note);
#      MF3 `_bbf_push` never deduping (no visited list) -> RED F8d (the compile hangs: every level of the three-way
#      cycle branches twice, to the depth cap);
#      MF4 (2026-10-17) the depth cap at 32 (`_bbf_dep > 32`) -> RED F12 (o33's base refused at its definition)
#   F13-F15e (6.7.15) THE JUDGEMENT HAS NO DEPTH CAP: it answered "not bad" past 64 forwards, so the 66th generic's base
#      kept an i64 instance whose call into the chain was refused at its definition ("generic 'o64' has no i64 instance:
#      it forwards its type parameter to 'o63'"). Each generic's verdict is memoised (`_bbm_get` / `_bbm_put`: a bad one
#      always, a not-bad one only when the whole judgement found nothing) and the cap is gone. F13 the filed repro (70
#      forwards, 5), F13b 66 (the old boundary), F13c 70 defined deepest first, F14 / F14b 120 either order, F14c
#      o119(3) refused once naming its forward, F14d a 3000-deep chain whose one error is the instance-nesting refusal;
#      F15 / F15b / F15c a 40-generic forwarding ring (one exit to gb: 10 at f64, r7(3, 1) refused; no exit: 8 at i64);
#      F15d / F15e a cycle judged from its other end first (A(h, 2) 6; A(3, 2) refused naming X). The cost half is
#      bound_forward_chain_scale.sh (serial). Filed: docs/development/issues/2026-10-17-bounded-forward-judgement-capped-
#      at-64-deep.md
#      Mutants (2026-10-18, a one-edit scratch copy of src/ each, CYCC= its cycc): the lane's previous compiler (b71f8853)
#      -> RED 7: F13 F13b F13c F14 F14b F14c F14d; MMC1 the 64-deep cap back beside the memo -> RED 2: F13c F14b (a chain
#      defined deepest first); MMC2 a not-bad verdict kept inside a judgement that ends bad -> RED 2: F15d F15e (A's base
#      emitted, X(x) at i64 refused at A's definition); MMC3 no memo (no cap) -> green here, RED in
#      bound_forward_chain_scale.sh (7-15x)
#   F14d-F14g (6.7.16) THE CALL THAT INSTANTIATES A CHAIN IS BOUNDED BY THE STACK, NOT BY 256 LEVELS
#      (issues/archived/2026-10-18-generic-forwarding-chain-hits-instance-nesting-cap.md). An instance is parsed nested inside
#      the call that reaches it, and each link spent two of the parser's 256 levels: the filed 122-link chain was
#      "nesting too deep (over 256 levels)". An instance's body counts its own levels (`_rd_inst_enter`) and the
#      stack bounds the chain (`_rd_enter`: 6 MB, ~300 links). On x86 the enclosing fn's jump-target table (1023) held
#      every nested instance's targets — ~190 links were "function exceeds 1023 jump targets (x86 LASE cap)" — and an
#      instance's range is now opaque there instead (`_jt_merge`, `_jir_in`; the sibling shape, many generics
#      instantiated in one fn, is jump_target_cap.sh). F14d a 3000-deep chain: refused ONCE by the stack bound, naming
#      the instance count; F14e the filed repro verbatim (122 links, 5); F14f 200 bounded links (5); F14g 200 links
#      with no bound, `sizeof(T)` at the end (8). On every host: tests/tcyr/crossos/generic_forward_chain_deep.tcyr.
#      Mutants (2026-10-20, a one-edit scratch copy of src/ each, CYCC= its cycc): no `_rd_inst_enter` reset -> RED
#      F14d F14e F14f F14g ("over 256 levels"); no stack bound -> RED F14d (rc 139); the 6.3.35 merge back (an
#      instance's targets into the enclosing table, no opaque range) -> RED F14f F14g ("1023 jump targets").
#   BC (6.7.14) A BOUNDED CALL ON A STRUCT CARRIER'S T FIELD: `b.v.show()` with `b: Box<T>` (`v: T`), `T: Show`, was
#      no bounded site (only a name declared `T` / `*T` was), so 6.7.11's carrier rule counted it a struct use: the
#      base was the stub, and `gs(bi)` with `bi: Box<i64>` was refused although `impl Show for i64` exists. The call
#      is now a bounded site (`_bnd_fsite`), the scan reads it as a trait use (`_gs_bfield`), and at a scalar T the
#      bound's impl takes the field's value as `self` (`_load_bs_field`; a method on a scalar field leaf had no path
#      at all). BC0 the filed repro verbatim (65); BC1 gs(b) alone; BC2 a `*Box<T>` carrier; BC3 no i64 impl: gs(bi)
#      refused naming `impl Show for i64`; BC4 f64 / i32 instances; BC5 a `var c: Box<T>` carrier, a `var r =`
#      receive and a statement; BC6 gs<i64>(bi); BC7 a method no bound declares (kept its reading through 6.7.14;
#      refused since 6.7.15's D5, the BD rows); BC8 a non-inlinable caller; BC9 the documented workaround unchanged;
#      BC10 the definition alone (no i64 impl).
#      Filed: docs/development/issues/archived/2026-10-14-bounded-method-call-on-carrier-field-is-a-struct-use.md
#      Mutants (2026-10-16, a one-edit scratch copy of the tree each, its 2-stage cycc, this gate run from it):
#      MBC1 `_bnd_sites` without the `_bnd_fsite` call (no site) -> RED BC0 BC2 BC4-BC6 BC8 (the stub refusal);
#      MBC2 `_gs_bfield` answering 0 (the site recorded, the scan still a struct use) -> RED BC0 BC2 BC4-BC6 BC8;
#      MBC3 `_fld_meth_inline` without its scalar arm (no `_load_bs_field`) -> RED BC0 BC2 BC4-BC6 BC8 ("expected
#      ';', got '.'" at the definition, every BC row that builds the i64 base)
#   BD (6.7.15, the user's D5 (a), 2026-10-18) THE CONTRACT HOLDS ON A CARRIER'S T FIELD: `b.v.other()` under
#      `fn gs<T: Show>(b: Box<T>)`, a method no trait of the bound declares, compiled and called Pt's own `other` (the
#      filed repro exited 77), where `v.other()` on a `v: T` is refused at the definition; `_bnd_fsite` recorded
#      nothing. It now refuses through `_bnd_site`'s two refusals (`_bnd_site_refuse`; the note names the field chain):
#      BD0 the filed repro verbatim (once, at 7:45, the note on 'b.v'); BD1 the definition alone; BD2 a `*Box<T>`
#      carrier; BD3 a `var c: Box<T>` carrier; BD4 the bound on the second type parameter; BD5 `Two<i64, T>`'s field;
#      BD6 a generic method; BD7 a method two bounds declare (ambiguous; refused only at an instance's call before, with
#      a cascade, and compiled uncalled); BDK unchanged — an unbounded `Box<T>`, an unbounded slot beside a bounded
#      one, a `f: *T` field, `b.v.show() + b.v.y`. BC7 moves from its 6.7.11 reading to the refusal.
#      Filed: docs/development/issues/archived/2026-10-16-bound-contract-unchecked-on-carrier-field-call.md
#      Mutants (2026-10-18, a one-edit scratch copy of src/ each, CYCC= its cycc): the lane's previous compiler
#      (4c483d56) -> RED 10: BC7 BD0 (both rows) BD1-BD6 (built) BD7 (the instance's message); MBD1 `_bnd_fsite` without
#      its unbounded-slot test -> RED 1: BDK; MBD2 the note without the field arm -> RED 1: BD0's note ('b'); MBD3 two
#      declaring traits recording nothing again -> RED 1: BD7
#   N  (6.7.14) a bound refusal the panic latch swallows prints nothing: after a stub generic's refusal in
#      the same statement (`gs(5) + gb(3)`), `gb(3)`'s error was swallowed but its note was printed alone —
#      "the bound on type parameter 'T' needs `impl Show for i64`" under gs's error. N1: one error line, no
#      note. Mutant (the `_panic` test in `_bnd_check` removed, a one-edit scratch copy of the tree, its 2-stage
#      cycc, this gate run from it) -> RED N1 (the orphan note). N2 (6.7.15) the contract's own note (`_bnd_site_refuse`)
#      is behind `_err_quiet` too: four refusals, the latch holding after the first, print one error and one note
#      (four notes before). Mutant: the lane's previous compiler (da30dffe) -> RED N2. 6.7.16: no refusal of the
#      contract is swallowed any more (NS), so N2's four refusals print four errors, each with its note.
#   NS (6.7.16) EVERY CONTRACT REFUSAL OF A COMPILE PRINTS: the site scan (`_bnd_sites`) is a pass-1 pre-scan that
#      nothing resyncs, so the first refusal's panic latch swallowed every later one — another generic's, a second in
#      one body, an ambiguous one — and they were fixed one compile at a time. `_bnd_site_refuse` reports with the
#      latch saved, cleared and put back. NS0 the filed repro verbatim (6:38 and 7:38, two notes); NS1 one body's two
#      `b.v.other()`; NS2 an ambiguous refusal (a name, a carrier's field) after a contract refusal; NS3 pass-2 errors
#      around them still print; NS4 a generic method's (recorded in pass 2) beside a fn's.
#      Filed: docs/development/issues/archived/2026-10-18-later-bound-contract-refusals-swallowed-in-pass-one.md
#      Mutant (2026-10-20): the lane's previous compiler (10afe6e68, the fix reverted) -> RED 8: N2, NS0 (both rows),
#      NS1 (both rows), NS2, NS3, NS4 (one error each).
#   BX (6.7.16, the user's D4, 2026-10-19) THE EXPLICIT SPELLING `v.m<..>(..)` IS HELD TO THE CONTRACT: the site scan keyed a
#      call by `name . name (` / `name . f . name (`, so `v.other<i64>(1)` under `T: Show` was no site — it compiled and
#      called Pt's own `other` (the filed repro exited 154) where `v.other(1)` is refused at the definition; and a bound's
#      own generic member called so, `v.show<i64>(1)`, was a struct use of T: the base the stub, refused at a scalar T.
#      `_bnd_mopen` takes `<..>(` after the method's name when every name in the list is a type (`_bnd_tyname`: the
#      generic's own T, a scalar, a struct / union / enum declared anywhere), so a comparison `v.y < a, c > (1)` stays one;
#      the stub scan reads the site as a trait use (`_bs_opens` in `_gs_use` / `_gs_bfield`); at a scalar T the member
#      arm reads the list (`_mtargs_bs`, `_field_load_on`'s scalar arm), and a refused site mints nothing (`_meth_xsite`).
#      BX0 the filed repro verbatim (7:38, 8:45, the notes on 'v' and 'b.v'); BX1 the definition alone, two in one body;
#      BX2 a `p: *T`, a `var c: Box<T>`, a `*Box<T>`, the second type parameter, a generic method; BX3 lists of two, of a
#      struct declared below, of a nested instance; BX4-BX6 a bound's generic member `v.show<i64>(1)` at a struct T, at a
#      scalar T, and `b.v.show<i64>(1)` at a scalar T (7 each); BX7 the list kept, not re-inferred (sizeof(i16) / (i8) /
#      (i32)); BX8 a refused site at an instance prints the definition's one error; BXK unchanged — a comparison on a
#      bounded T's field, `if (v.y < a)`, an unbounded T's explicit call; BXU a list naming no type is no site (the call's
#      own "unknown type"). The run-time half on every backend: tests/tcyr/crossos/trait_bound_explicit_member.tcyr.
#      Filed: docs/development/issues/archived/2026-10-18-explicit-method-type-args-escape-bound-contract.md
#      Mutants (2026-10-20, a one-edit scratch copy of src/ each, CYCC= its cycc): the previous compiler (24a74beff, the
#      fix reverted) -> RED 9: BX0 (both rows) BX1 BX2 BX3 (built) BX5 BX6 BX7 (the stub) BX8; MBX1 `_bnd_mopen` taking
#      `(` alone -> RED 9, the same; MBX2 `_bnd_tyname` taking any name -> RED 2: BXK (the comparison refused) BXU; MBX3
#      `_mtargs_at` without its scalar arm -> RED 3: BX5 BX6 BX7; MBX4 `_bs_opens` taking `(` alone -> RED 3: BX5 BX6 BX7
#      (the stub); MBX5 `_meth_xsite` minting at a refused site -> RED 1: BX8 (Pt.other<i64>'s own refusal too); MBX6 no
#      `_meth_targs` in the scalar arm -> RED 3: BX5 BX6 BX7; MBX7 no `_declared_any` -> RED 1: BX3 (a struct declared
#      below).
#   BXS (6.7.16) `--syntax-only` (cyrius lint) parses BX5-BX7 silently: a scalar T's receiver has no struct, and the
#      chain walk left the explicit list — "expected ';', got '>'", a syntax error the file does not have; the walk
#      (`_synonly_chain_call`) now steps a method's list (`_synonly_mlist`) and parses the call (lint_reports_unparseable.sh
#      axis 14, a sibling's struct). Mutants (2026-10-20): the previous compiler (f272ffabf) -> RED 3: BXS x3;
#      `_synonly_chain_call` without `_synonly_mlist` -> RED 3: BXS x3; the `sid == 0` arm back on `_synonly_skip_chain`
#      -> RED 3: BXS x3.
#   VB (6.7.15, the user's D10 (a), 2026-10-18) A VEC ELEMENT'S GENERIC STRUCT IS HELD TO ITS BOUNDS: `var w: Vec<Box<Pt>>
#      = 0;` with `struct Box<T: Show>` and no `impl Show for Pt` compiled (the filed repro exited 5) — the element's
#      list was read for names only (6.7.14's D5), the bound judged only where an instance is minted. Judged at the
#      element now, nothing minted (`_vec_el_targs`, `_tck_nest`, `_vbnd_judge`): VB0 the filed repro verbatim (once, at
#      6:16, with the note); VB1 with the impl (5); VB2 a struct field; VB3 / VB3b `Vec<Box<i64>>` and a bare `Vec<Box>`
#      (the i64 base's bound); VB4 nested (`Vec<Two<Box<Pt>, i64>>`, `Vec<Vec<Box<Pt>>>`), a parameter, a global; VB5 a
#      generic's `Vec<Box<T>>` judged per instance, not in its base; VB6 a generic struct's field at `W<Pt>`; VB7 once
#      per (struct, arguments); VB8 a refused argument alone; VB9 the list reads on after it; VBK the impl present (23).
#      A signature's or a pointer field's `_targ_chk` judges no bound (off outside a Vec element).
#      Filed: docs/development/issues/archived/2026-10-16-vec-element-generic-struct-bound-unchecked.md
#      Mutants (2026-10-18, a one-edit scratch copy of src/ each, CYCC= its cycc): the lane's previous compiler
#      (13fd8844) -> RED 13: VB0 (both rows) VB2 VB3 VB3b VB4-VB4d VB5 VB6 VB7 VB9 (each built); MVB1 `_vec_el_targs`
#      without the element's judgement -> RED 10: VB0 (both) VB2 VB3 VB4b-VB4d VB5 VB6 VB7; MVB2 `_tck_nest` without its
#      judgement -> RED 2: VB4 VB9; MVB3 `_vec_el_bare` answering 0 -> RED 1: VB3b; MVB4 `_vbnd_judge` keeping the panic
#      latch -> RED 1: VB9 (one line); MVB5 `_type_arg_leaf`'s type-parameter arm not marking the list -> RED 1: VBK (a
#      generic's base judged at i64)
#   VN (6.7.16, the user's D10, 2026-10-19) A VEC ELEMENT'S GENERIC STRUCT WHOSE ARGUMENT IS ITSELF AN INSTANCE is
#      judged as the by-value form: `var w: Vec<Box<Box<R>>> = 0;` with `struct Box<T: Show>` and `impl Show for R`
#      compiled (exit 5) — only minting names `Box<R>`, so the outer list was marked unjudgeable — while
#      `var b: Box<Box<R>>;` is refused: no `impl Show for Box<R>` can be written. The inner list, judged in its turn,
#      now stands in the outer slot as a PENDING instance (`_pn_of`, nothing minted) that no impl names, its note
#      spelled as `_mint_generic_name` would. VN0 the filed repro verbatim (once at 7:16, the note `impl Show for
#      Box$R`); VN1 `Vec<SB<UB<R>>>` (outer bounded, inner unbounded); VN2 an unbounded outer over an instance builds;
#      VN3 `Vec<Box<Box<i64>>>`'s inner base judged as 6.7.15 judged it (its two lines); VN4 a field, a parameter, a
#      global; VN5 deeper — the first refused list alone (`Vec<Box<Box<Box<R>>>>`), a pending argument's own pending
#      argument named whole (`UB$UB$R`); VN6 a generic's `Vec<Box<Box<T>>>` per instance; VN7 once per (struct,
#      arguments), the by-value form among them (`_pn_canon`); VN8 an `impl Show for Box` names no instance.
#      Filed: docs/development/issues/archived/2026-10-18-vec-element-nested-instance-argument-bound-unjudged.md
#      Mutants (2026-10-20; MVN1 / MVN2 a one-edit scratch copy of the tree each, CYCC= its cycc): the lane's previous
#      compiler (cacd0ff68) -> RED 15: VN0 VN1 VN5 VN5b (both rows each), VN4 VN4b VN4c VN6 (each built), VN7 (the
#      by-value line alone), VN8 (both rows: the element built); MVN1 `_pn_canon` answering its argument -> RED 1: VN7
#      (two lines); MVN2 `_tck_nest` keeping a refused list's enclosing list judgeable -> RED 1: VN5 (a second line)
#   RB (6.7.17, the user's D1, 2026-10-22) A BOUNDED SITE ON A REBOUND RECEIVER IS NO SITE: in `fn g<T: Show>(x: T)` the
#      `x` of a closure's `|x|`, of `for x in ..` and of `var q, x = two();` is that rebinding's own untyped word, so
#      `x.other()` there is the plain fn's "no struct type in scope for 'x'" at the definition, not the contract's
#      "method 'other' is not in the bound" (a site of g's x: RB1-RB3), nor `x.show()` a call of the bound's impl on the
#      word (struct_result_type_refused.sh RB0-RB3: SIGSEGV at T = Pt); a carrier's `|b| b.v.other()` the same (RB4); the
#      explicit spelling `|x| x.show<i64>()` (RB5; it was "'i64.show' is not a generic method"). RBK: g's own
#      `x.other()` past the closure is still the contract's refusal. issues/2026-10-21-generic-tparam-name-rebound-by-
#      closure-param-forin-destructure-read-as-t-sigsegv.md. Mutants (2026-10-22, a one-edit scratch copy of the tree
#      each, CYCC= its cycc): the tree before (e65604d5d) -> RED 5: RB1-RB5 (the contract's words, RB5 "'i64.show' is
#      not a generic method"); `_bnd_sites` without its rebound test -> RED 4: RB1 RB2 RB3 RB5; `_bnd_fsite` without
#      its rebound test -> RED 1: RB4
#   C  ANTI-VACUOUS: the same shapes with the impl present build and run; an unbounded `T` keeps
#      per-instance method resolution; a program with no bound is untouched
#   DS (6.7.17, met in genb GB1) PASS 2 STEPS A STRUCT'S `<..>` NESTED: `_tl_skip_struct` stopped at the first `>`, so
#      `struct B<T: Show<i64>>` (one `>>` token) ran pass 2 to the end of the file — D5's line, then "undefined
#      function 'main'" with the later fn bodies never parsed — and `<T: Show<i64> >` added "expected '{', got '>'".
#      DS1 / DS2 D5's line and the next fn's own error, both spellings; DS3 (control) bounded structs, then a bounded
#      generic below them (exit 4). Mutant (2026-10-22): the compiler before (e65604d5d) -> RED DS1 DS2.
#      DS4 the same class in pass 1's fn skip (`_prescan_skip_fn`): `fn d<U: Show<i64>>` stepped pass 1 past the end
#      of the file, so a later struct's field error was never reported. Mutant: 5ffeb0420 (DS1's fix alone) -> RED DS4.
#   DL (6.7.17, met in genb GB1) A BOUND'S REFUSAL PUTS THE PANIC LATCH BACK (`_bnd_make`): pass 1 has no statement
#      resync, so `fn c<U: Nope2>`'s "unknown trait" held the latch to the end of the scan and swallowed every later
#      generic's bound refusal and every later struct's field error. DL1 a fn's, a struct's and a fn's unknown bound,
#      in source order; DL2 a struct's field error and a fn body's error after one; DL3 a malformed bound `<U: 5>` and
#      a bound with arguments `<U: Show<i64> >`, each with the next struct's error; DL4 two impl methods' (pass 2).
#      Mutant (2026-10-22): the compiler before (e65604d5d) -> RED DL1-DL4 (the first line alone, DL2 its pass-2 line too).
#   DW (6.7.17, met in genb GB1) A BOUND'S TRAIT IS NO TYPE PARAMETER, AND A NAME PAST A NESTED LIST IS ONE: the walkers
#      that answer "is this name a type parameter here" (`_fn_tp_has`, `_arr_fn_tparam`, `_is_own_tparam`) took every
#      name of the list to its first `>` — `fn f<T: Show>(x: T, y: Show)` and a body's `var z: Show` compiled where
#      `fn g(y: Show)` is "unknown type 'Show'", and `struct B<T: Show<i64>, U> { a: U; }` added "unknown type 'U'"
#      (under CYRIUS_MONOMORPH=0 too, with `fn k<T: Show<i64>, U>(u: U)`'s two). One reader (`_tpl_has`): depth-tracked,
#      a bound's names excluded. DW1 the signature's and the body's `Show` refused as g's is; DW2 no "unknown type 'U'"
#      past a refused list, plain and under the flag; DW3 (control) `<T: Show + Eq, U>` a struct's and a fn's, `U` and
#      `T[2]` in the body (exit 13). Mutant (2026-10-22): the compiler before (84a9da229) -> RED DW1 DW2 (both legs).
#   TM (6.7.17, the user's D4, 2026-10-22: "Refuse with the fn's words") A TRAIT MEMBER'S BOUNDS ARE LOOKED UP:
#      `trait T { fn i<U, V: Nope>(self): i64; }` compiled (exit 3) where `fn i<U, V: Nope>` is "unknown trait 'Nope' in
#      the bound on type parameter 'V'" — the bound reader ran at a fn's and an impl method's definition only. The
#      member's list is read and judged by the fn's own reader (`_tr_tp_bounds`: `_capture_tparams` + `_bnd_make`), in
#      pass 1 in source order. TM1 the filed repro verbatim, plain and --syntax-only (as the fn's); TM2 a member's
#      unknown, malformed (`X: 5`), argument-taking (`Y: Show<i64>`) bound and a default body's (inherited: once), then
#      the next declaration's and fn's own errors; TM3 a bound naming a trait declared below the member builds (exit
#      5); TM4 CYRIUS_MONOMORPH=0 reads no bound — the member's and the fn's spelling both build, as before. The cross
#      legs are generic_tparam_count_refused.sh A [a64] / [cx] / [pe] / [macho] TM1. Issue row 2. Mutant (2026-10-22):
#      the compiler before (8cdae35c6) -> RED TM1 (both rows: built) TM2 (an inherited default's line, Foo's and `1 2`'s
#      alone); generic_tparam_count_refused.sh T6 and A [pe] / [macho] TM1.
#
# Mutations (scratch trees, each RED here — run 2026-10-07): `_capture_tparams` not reading a bound
#   (every identifier a type parameter again) -> D1 builds, D2-D4 refused only by the cascade;
#   `_bnd_check_fn` answering 0 -> I1/I2 refused only as undefined fns, I3 BUILDS; `_bnd_site` not
#   refusing -> D2/D3 refused only by the cascade; `_bnd_base_bad` answering 0 -> I3-I5 refused
#   with the struct-stub message instead of the bound's; `_bnd_sbase` a no-op -> S2-S4 BUILD; no
#   quiet mode in `_sfield_gen` -> S4 BUILDS (W's base never learns it holds a Box<i64>).
# 6.7.11 I8: `_gen_call_inst` resolving the inner call with the cursor left on the outer one -> RED
#   I8's column (the refusal named `gx`'s column, 12 for 15 in the filed shape).
# 6.7.14 B1 / B1b: `_bnr_add` dropping the 65th bounded receiver again (a one-edit scratch copy of the
#   tree, its 2-stage mutant cycc, this gate run from it) -> RED B1 / B1b ("generic 'f' has no i64 (or
#   other scalar) instance": `z.show()` was no bounded site, so the scan counted it a struct use; with the
#   T-typed names' table capped too, as at the slot open, it is "no struct type in scope for 'z'").
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: trait_bounds_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: trait_bounds_checked: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() {   # <name> <message fragment> <what>
    build "$1"
    n=$(grep -c '^error' "$T/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -qF "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines (want 1): $(grep '^error' "$T/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once"; fi
}
exits() {   # <name> <want> <what>
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
H='struct Pt { x; y; }
struct R { r; }
trait Show { fn show(self): i64; }
trait Eq { fn eq(self, o: Pt): i64; }
trait Size { fn size(self): i64; }
trait Other { fn size(self): i64; }
impl Show for Pt { fn show(self): i64 { return self.x + self.y; } }
impl Size for Pt { fn size(self): i64 { return 2; } }
impl Other for Pt { fn size(self): i64 { return 3; } }'
P='var p: Pt; p.x = 40; p.y = 2;'
mk() {   # <name> <decls> <main body>
    printf '%s\n%s\nfn main(): i64 { %s %s }\nsyscall(60, main());\n' "$H" "$2" "$P" "$3" > "$T/$1.cyr"
}

# D — the definition
mk d1 'fn f<T: Shw>(v: T): i64 { return 1; }' 'return f(p);'
refused d1 "unknown trait 'Shw' in the bound on type parameter 'T'" "D1: an undeclared trait in a bound"
mk d2 'fn f<T: Show>(v: T): i64 { return v.size(); }' 'return f(p);'
refused d2 "method 'size' is not in the bound on type parameter 'T'" "D2: the contract — v.size() under T: Show"
mk d3 'fn f<T: Show>(v: T): i64 { var q: T = v; return q.nope(); }' 'return f(p);'
refused d3 "method 'nope' is not in the bound on type parameter 'T'" "D3: the contract on a var q: T local"
mk d4 'fn f<T: Size + Other>(v: T): i64 { return v.size(); }' 'return f(p);'
refused d4 "ambiguous method 'size': more than one trait in this type parameter's bound declares it" "D4: two bounds declare the method"
mk d5 'fn f<T: Show<i64>>(v: T): i64 { return 1; }' 'return f(p);'
refused d5 "a trait in a bound takes no type arguments: 'Show'" "D5: a bound with type arguments"
mk d6 'fn f<A, B, C: Show>(a: A): i64 { return 1; }' 'return f(p);'
refused d6 "a third type parameter 'C': a generic takes at most two type parameters" "D6: a bound on a third type parameter (6.7.16 D8: the parameter refused)"
mk d7 'fn f<T: >(v: T): i64 { return 1; }' 'return f(p);'
refused d7 "expected a trait name in a type parameter's bound" "D7: <T: >"

# I — instantiations
B1='fn f<T: Show>(v: T): i64 { var t = 0; var i = 0; while (i < 1) { t = t + v.show(); i = i + 1; } return t; }'
mk i1 "$B1" 'var r: R; r.r = 1; return f(r);'
refused i1 "generic 'f': its type argument does not implement trait 'Show'" "I1: f(r), R has no impl Show (inferred)"
grep -qF "needs \`impl Show for R\`" "$T/i1.err" && ok "I1: the note names the impl it needs" || bad "I1: no note naming \`impl Show for R\`"
mk i2 "$B1" 'var r: R; r.r = 1; return f<R>(r);'
refused i2 "generic 'f': its type argument does not implement trait 'Show'" "I2: f<R>(r), explicit"
mk i3 "$B1" 'return f(5);'
refused i3 "generic 'f': its type argument does not implement trait 'Show'" "I3: f(5), the i64 base"
grep -qF "needs \`impl Show for i64\`" "$T/i3.err" && ok "I3: the note names \`impl Show for i64\`" || bad "I3: no note naming \`impl Show for i64\`"
printf 'include "lib/fnptr.cyr"\n%s\n%s\nfn main(): i64 { var g = &f; return fncall1(g, 5); }\nsyscall(60, main());\n' "$H" "$B1" > "$T/i4.cyr"
refused i4 "generic 'f': its type argument does not implement trait 'Show'" "I4: &f (its address is the i64 base)"
mk i5 "$B1
fn h(n): i64 { return f(n); }" 'return h(5);'
refused i5 "generic 'f': its type argument does not implement trait 'Show'" "I5: return f(n); (a tail call)"
mk i6 'fn g<A: Show, B: Size>(a: A, b: B): i64 { return a.show() + b.size(); }' 'var r: R; r.r = 1; return g(p, r);'
refused i6 "generic 'g': its type argument does not implement trait 'Size'" "I6: the second bounded parameter"
mk i7 "$B1
fn u<T>(v: T): i64 { return f(v); }" 'return u(5);'
refused i7 "generic 'u' has no i64 instance: it forwards its type parameter to 'f'" "I7: an unbounded generic forwarding T to a bounded one, u(5) (6.7.14: names the forward)"
grep -qF "needs \`impl Show for i64\`" "$T/i7.err" && ok "I7: the note names \`impl Show for i64\`" || bad "I7: no note naming \`impl Show for i64\`"
# 6.7.11: a bounded generic CALLED AS ANOTHER GENERIC'S ARGUMENT is resolved while the outer call infers T
# (a generic call's own result binds T, `_gen_call_inst`) — its refusal still names the inner call's column.
mk i8 'struct Box<T> { v: T; n; }
fn mkb<T: Show>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn gx<T>(b: Box<T>): i64 { return b.n; }
fn g<T>(p: T): i64 { return p.n; }' 'var r: R; r.r = 1; return gx(mkb(r)) + g(mkb(r));'
refused i8 "generic 'mkb': its type argument does not implement trait 'Show'" "I8: gx(mkb(r)) + g(mkb(r)), R has no impl Show"
c8=$(grep '^fn main' "$T/i8.cyr" | awk '{ print index($0, "gx(mkb") + 3 }')
if grep -q ":$c8: generic 'mkb'" "$T/i8.err"; then ok "I8: ... reported at the inner call (column $c8)"
else bad "I8: not reported at the inner call's column $c8: $(grep '^error' "$T/i8.err" | head -1)"; fi

# S — bounded generic structs
SB='struct Box<T: Show> { v: T; n; }'
mk s1 "$SB" 'var b: Box<R>; return 1;'
refused s1 "generic 'Box': its type argument does not implement trait 'Show'" "S1: Box<R>"
mk s2 "$SB" 'var b: Box<i64>; return 1;'
refused s2 "generic 'Box': its type argument does not implement trait 'Show'" "S2: a written Box<i64>"
mk s3 "$SB
fn bs(b: Box): i64 { return b.n; }" 'return 1;'
refused s3 "generic 'Box': its type argument does not implement trait 'Show'" "S3: a bare Box (its i64 base)"
mk s4 "$SB
struct W<T> { b: Box<T>; m; }" 'var w: W<Pt>; w.b.v = p; w.m = 1; var u: W; return 1;'
refused s4 "generic struct 'W' has no i64 instance" "S4: W<Pt> is fine; the bare W's Box<i64> is not"
mk s5 "$SB
fn mk<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 1; return b; }" 'var a: Box<Pt> = mk(p); return mk(5).n;'
refused s5 "generic 'mk' has no i64 instance" "S5: mk(p) is fine; mk(5) would need Box<i64>"

# B — more than 64 bounded receivers (6.7.14). `brgen <name> <n>`: f's parameter v and <n> locals.
brgen() {
    _bd='impl Show for i64 { fn show(self): i64 { return self + 1; } }
fn f<T: Show>(v: T): i64 {'
    k=1; while [ "$k" -le "$2" ]; do _bd="$_bd
    var c$k: T = v;"; k=$((k + 1)); done
    mk "$1" "$_bd
    var z: T = v;
    return z.show();
}" 'return f(p) + f(2) - 40;'
}
brgen b1 65
exits b1 5 "B1: 66 bounded receivers (v + 65 locals), then z.show() — on Pt (42) and on i64 (3)"
brgen b1b 130
exits b1b 5 "B1b: 131 bounded receivers (the table grows twice)"

# F — a generic forwarding its T to a bounded generic (6.7.14)
cat > "$T/f0.cyr" <<'EOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
fn gb<T: Show>(x: T): i64 { return x.show(); }
fn o<T>(x: T): i64 { return gb(x); }
fn main(): i64 { var h: f64 = 1.5; return o(h); }
syscall(60, main());
EOF
exits f0 5 "F0: the filed repro, verbatim — o(h) forwards an f64 to gb, which has only impl Show for f64"
FH='struct Pt { x; y; }
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
impl Show for Pt { fn show(self): i64 { return self.y; } }
fn gb<T: Show>(x: T): i64 { return x.show(); }
fn o<T>(x: T): i64 { return gb(x); }'
fmk() {   # <name> <decls> <main body>
    printf 'include "lib/syscalls.cyr"\ninclude "lib/fnptr.cyr"\n%s\n%s\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$FH" "$2" "$3" > "$T/$1.cyr"
}
fwdref() {   # <name> <generic> <callee> <root> <what>: refused once, naming the forward and the impl i64 lacks
    refused "$1" "generic '$2' has no i64 instance: it forwards its type parameter to '$3'" "$5"
    if grep -q "uses its type parameter as a struct" "$T/$1.err"; then bad "$5: ... with the struct-stub text"; fi
    if [ "$(grep -c '^  note:' "$T/$1.err")" -ne 1 ]; then bad "$5: $(grep -c '^  note:' "$T/$1.err") note lines (want 1)"
    elif ! grep -qF "$4" "$T/$1.err"; then bad "$5: the note does not say: $4"
    else ok "$5: one note: $4"; fi
}
fmk f1 '' 'var h: f64 = 1.5; return o<f64>(h);'
exits f1 5 "F1: o<f64>(h), explicit"
fmk f2 '' 'return o(3);'
fwdref f2 o gb "the bound on type parameter 'T' of 'gb' needs \`impl Show for i64\`" "F2: o(3), only the f64 impl"
fmk f3 'impl Show for i64 { fn show(self): i64 { return 6; } }' 'var h: f64 = 1.5; return o(h) * 10 + o(3);'
exits f3 56 "F3: with impl Show for i64 too, o(h) * 10 + o(3)"
fmk f4 'fn o2<T>(x: T): i64 { return o(x); }' 'var h: f64 = 1.5; var p: Pt; p.x = 1; p.y = 4; return o2(h) * 10 + o2(p);'
exits f4 54 "F4: two levels, o2(h) -> o -> gb (5) and o2(p) (4)"
fmk f4b 'fn o2<T>(x: T): i64 { return o(x); }' 'return o2(3);'
fwdref f4b o2 o "the bound on type parameter 'T' of 'gb' needs \`impl Show for i64\`" "F4b: o2(3), two levels — the note names the chain's end"
fmk f5 'fn ox<T>(x: T): i64 { return gb<T>(x); }' 'var h: f64 = 1.5; var p: Pt; p.x = 1; p.y = 4; return ox(h) + ox(p) * 10;'
exits f5 45 "F5: an explicit forward gb<T>(x), f64 and a struct"
FM='struct P { a; }
impl P { fn gbm<T: Show>(self, x: T): i64 { return self.a + x.show(); } }
fn om<T>(q: P, x: T): i64 { return q.gbm(x); }'
fmk f6 "$FM" 'var q: P = P { 10 }; var h: f64 = 1.5; return om(q, h);'
exits f6 15 "F6: a forward to a bounded generic METHOD, q.gbm(x)"
fmk f6b "$FM" 'var q: P = P { 10 }; return om(q, 3);'
fwdref f6b om P.gbm "the bound on type parameter 'T' of 'P.gbm' needs \`impl Show for i64\`" "F6b: om(q, 3) (the method as the source spells it, 6.7.16)"
FS='struct Box<T: Show> { v: T; n; }
fn mkn<T>(x: T): i64 { var b: Box<T>; b.v = x; b.n = 3; return b.n; }
fn os<T>(x: T): i64 { return mkn(x); }'
fmk f7 "$FS" 'var h: f64 = 1.5; return os(h);'
exits f7 3 "F7: a forward to a generic instantiating a bounded struct Box<T: Show>"
fmk f7b "$FS" 'return os(3);'
fwdref f7b os mkn "'mkn' instantiates the bounded generic struct 'Box' with its type parameter, and i64 does not satisfy its bound" "F7b: os(3)"
FC='fn pa<T>(x: T, n): i64 { if (n == 0) { return gb(x); } return pb(x, n - 1) + 1; }
fn pb<T>(x: T, n): i64 { if (n == 0) { return 2; } return pa(x, n - 1) + 2; }'
fmk f8 'fn qa<T>(x: T, n): i64 { if (n == 0) { return 1; } return qb(x, n - 1) + 1; }
fn qb<T>(x: T, n): i64 { if (n == 0) { return 2; } return qa(x, n - 1) + 2; }' 'return qa(3, 3);'
exits f8 6 "F8: control — two generics forwarding to each other, no bound reached: qa(3, 3) runs"
fmk f8b "$FC" 'var h: f64 = 1.5; return pa(h, 3) * 10 + pb(h, 3);'
exits f8b 70 "F8b: the cycle reaches gb: pa(h, 3) / pb(h, 3) at f64"
fmk f8c "$FC" 'return pb(3, 3);'
fwdref f8c pb pa "the bound on type parameter 'T' of 'gb' needs \`impl Show for i64\`" "F8c: pb(3, 3) through the cycle"
# F8d: three generics forwarding to each other two ways — each is scanned once per judgement (`_bbf_vis`);
# without the visited list the walk branches at every level (2^64 scans to its depth cap): a hung compile.
fmk f8d 'fn ra<T>(x: T, n): i64 { if (n == 0) { return 1; } return rb(x, n - 1) + rc(x, n - 1); }
fn rb<T>(x: T, n): i64 { if (n == 0) { return 2; } return ra(x, n - 1) + rc(x, n - 1); }
fn rc<T>(x: T, n): i64 { if (n == 0) { return 3; } return ra(x, n - 1) + rb(x, n - 1); }' 'return ra(3, 2);'
rc=0; timeout 60 "$CC" < "$T/f8d.cyr" > "$T/f8d.bin" 2> "$T/f8d.err" || rc=$?
if [ "$rc" -eq 124 ]; then bad "F8d: a three-way forwarding cycle: the compile did not finish in 60 s"
elif [ "$rc" -ne 0 ]; then bad "F8d: a three-way forwarding cycle: rc $rc: $(grep '^error' "$T/f8d.err" | head -1)"
else chmod +x "$T/f8d.bin"; got=0; "$T/f8d.bin" || got=$?
    if [ "$got" -eq 7 ]; then ok "F8d: a three-way forwarding cycle compiles and runs: exit 7"; else bad "F8d: exit $got, want 7"; fi
fi
fmk f9 '' 'var g = &o; return fncall1(g, 3);'
fwdref f9 o gb "needs \`impl Show for i64\`" "F9: &o"
fmk f10 'fn h(n): i64 { return o(n); }' 'return h(3);'
fwdref f10 o gb "needs \`impl Show for i64\`" "F10: return o(n); (a tail call)"
fmk f11 '' 'return 9;'
exits f11 9 "F11: the definition alone, never called"
# F12: the judgement follows a chain of 64 forwards (o63 -> .. -> o0 -> gb), 6.7.14's stated reach.
{ printf 'include "lib/syscalls.cyr"\ntrait Show { fn show(self): i64; }\nimpl Show for f64 { fn show(self): i64 { return 5; } }\n'
  printf 'fn gb<T: Show>(x: T): i64 { return x.show(); }\nfn o0<T>(x: T): i64 { return gb(x); }\n'
  k=1; while [ "$k" -lt 64 ]; do printf 'fn o%d<T>(x: T): i64 { return o%d(x); }\n' "$k" "$((k - 1))"; k=$((k + 1)); done
  printf 'fn main(): i64 { var h: f64 = 1.5; return o63(h); }\nsyscall(60, main());\n'; } > "$T/f12.cyr"
exits f12 5 "F12: a chain of 64 forwards to gb at f64, o63(h)"
# F13-F15 (6.7.15): the judgement has no depth cap — it is memoised per generic (`_bbm_get` / `_bbm_put`), so any
# chain is judged once per generic. `fchain <name> <n> [rev] [call]`: o0 -> gb, oK -> oK-1 (o0..o<n-1>), in source
# order or reversed (the deepest first, so its judgement walks the whole chain), main returning <call>.
fchain() {
    { printf 'include "lib/syscalls.cyr"\ntrait Show { fn show(self): i64; }\nimpl Show for f64 { fn show(self): i64 { return 5; } }\n'
      printf 'fn gb<T: Show>(x: T): i64 { return x.show(); }\n'
      if [ "${3:-}" = rev ]; then
          k=$(($2 - 1)); while [ "$k" -ge 1 ]; do printf 'fn o%d<T>(x: T): i64 { return o%d(x); }\n' "$k" "$((k - 1))"; k=$((k - 1)); done
          printf 'fn o0<T>(x: T): i64 { return gb(x); }\n'
      else
          printf 'fn o0<T>(x: T): i64 { return gb(x); }\n'
          k=1; while [ "$k" -lt "$2" ]; do printf 'fn o%d<T>(x: T): i64 { return o%d(x); }\n' "$k" "$((k - 1))"; k=$((k + 1)); done
      fi
      printf 'fn main(): i64 { var h: f64 = 1.5; return %s; }\nsyscall(60, main());\n' "${4:-o$(($2 - 1))(h)}"; } > "$T/$1.cyr"
}
fchain f13 70
exits f13 5 "F13: the filed repro, verbatim — a chain of 70 forwards, o69(h) (refused at o65's definition before: the 64-deep cap)"
fchain f13b 66
exits f13b 5 "F13b: 66 forwards, the old boundary"
fchain f13c 70 rev
exits f13c 5 "F13c: 70 forwards defined deepest first"
fchain f14 120
exits f14 5 "F14: a chain of 120 forwards, o119(h)"
fchain f14b 120 rev 'o119(h) + o60(h) - 5'
exits f14b 5 "F14b: 120 forwards defined deepest first, o119(h) + o60(h) - 5"
fchain f14c 120 '' 'o119(3)'
fwdref f14c o119 o118 "needs \`impl Show for i64\`" "F14c: o119(3) — refused once, naming the forward and the chain end's impl"
fchain f14d 3000 '' 'o2999(h)'
build f14d
if [ "$rc" -eq 0 ]; then bad "F14d: a 3000-deep chain at f64: BUILT (the stack bound is its limit)"
elif [ "$rc" -ne 1 ]; then bad "F14d: a 3000-deep chain at f64: rc $rc (a signal? want the refusal, rc 1)"
elif [ "$(grep -c '^error' "$T/f14d.err")" -ne 1 ] || ! grep -q "nesting too deep ([0-9]* generic instances, each parsed inside the call that reaches it, used over 6 MB of the compiler's stack)" "$T/f14d.err"; then
    bad "F14d: a 3000-deep chain at f64: not the stack bound's refusal alone: $(grep '^error' "$T/f14d.err" | head -2 | tr '\n' '|')"
else ok "F14d: a 3000-deep chain at f64: the stack bound's refusal alone, $(grep -o '[0-9]* generic instances' "$T/f14d.err") (no definition refused); its time is bound_forward_chain_scale.sh"; fi
# F14e: the filed repro, verbatim (its generator, n = 122): `describe` bounded, o0 -> describe, main's own return.
filedchain() { n=$2; { echo 'trait Show { fn show(self): i64; }'
  echo 'fn describe<T: Show>(x: T): i64 { return x.show(); }'
  echo 'impl Show for f64 { fn show(self): i64 { return 5; } }'
  echo 'fn o0<T>(x: T): i64 { return describe(x); }'
  i=1; while [ $i -lt $n ]; do echo "fn o$i<T>(x: T): i64 { return o$((i-1))(x); }"; i=$((i+1)); done
  echo "fn main(): i64 { var h: f64 = 1.5; return o$((n-1))(h); }"; } > "$T/$1.cyr"; }
filedchain f14e 122
exits f14e 5 "F14e: the filed repro verbatim, 122 links at f64 (was: nesting too deep (over 256 levels))"
fchain f14f 200
exits f14f 5 "F14f: 200 bounded links at f64, o199(h)"
{ printf 'include "lib/syscalls.cyr"\nfn z0<T>(x: T): i64 { return sizeof(T); }\n'
  k=1; while [ "$k" -lt 200 ]; do printf 'fn z%d<T>(x: T): i64 { return z%d(x); }\n' "$k" "$((k - 1))"; k=$((k + 1)); done
  printf 'fn main(): i64 { var h: f64 = 1.5; return z199(h); }\nsyscall(60, main());\n'; } > "$T/f14g.cyr"
exits f14g 8 "F14g: 200 links with no bound, sizeof(T) at the end, z199(h)"
# F15: cycles still end, and are judged right: a ring of 40 generics (rK -> rK+1, r39 -> r0) with one exit to gb (r20)
{ printf 'include "lib/syscalls.cyr"\ntrait Show { fn show(self): i64; }\nimpl Show for f64 { fn show(self): i64 { return 5; } }\n'
  printf 'fn gb<T: Show>(x: T): i64 { return x.show(); }\n'
  k=0; while [ "$k" -lt 40 ]; do
      if [ "$k" -eq 20 ]; then printf 'fn r20<T>(x: T, n: i64): i64 { if (n <= 0) { return gb(x); } return r21(x, n - 1); }\n'
      else printf 'fn r%d<T>(x: T, n: i64): i64 { if (n <= 0) { return 0; } return r%d(x, n - 1); }\n' "$k" "$(( (k + 1) % 40 ))"; fi
      k=$((k + 1)); done
  printf 'fn main(): i64 { var h: f64 = 1.5; return r0(h, 20) + r30(h, 30); }\nsyscall(60, main());\n'; } > "$T/f15.cyr"
exits f15 10 "F15: a 40-generic forwarding ring with one exit to gb, at f64 (r0 and r30 reach r20 with n = 0)"
sed 's/return r0(h, 20) + r30(h, 30);/return r7(3, 1);/' "$T/f15.cyr" > "$T/f15b.cyr"
fwdref f15b r7 r8 "needs \`impl Show for i64\`" "F15b: r7(3, 1) through the ring — refused once"
sed 's/return gb(x); } return r21/return 4; } return r21/' "$T/f15.cyr" | sed 's/return r0(h, 20) + r30(h, 30);/var a = 2; return r0(a, 20) + r30(a, 30);/' > "$T/f15c.cyr"
exits f15c 8 "F15c: the same ring with no exit to a bound — every member's i64 base runs"
# F15d: a "not bad" answered inside a judgement that ends bad is not kept. X's base is judged first: X -> A -> X (in
# progress, skipped) leaves A "not bad" for that judgement, then X -> C -> gb ends it bad. A reaches gb through X, so
# A's own judgement must find it: its base skipped, A(h) at f64 runs (a kept "not bad" emitted A's base, whose X(x) at
# i64 was refused at A's definition).
fmk f15d 'fn X<T>(x: T, n: i64): i64 { if (n <= 0) { return 0; } return A(x, n - 1) + C(x); }
fn A<T>(x: T, n: i64): i64 { if (n <= 0) { return 1; } return X(x, n - 1); }
fn C<T>(x: T): i64 { return gb(x); }' 'var h: f64 = 1.5; return A(h, 2);'
exits f15d 6 "F15d: a cycle judged from its other end first — A(h, 2) at f64 (1 + 5)"
fmk f15e 'fn X<T>(x: T, n: i64): i64 { if (n <= 0) { return 0; } return A(x, n - 1) + C(x); }
fn A<T>(x: T, n: i64): i64 { if (n <= 0) { return 1; } return X(x, n - 1); }
fn C<T>(x: T): i64 { return gb(x); }' 'return A(3, 2);'
fwdref f15e A X "needs \`impl Show for i64\`" "F15e: A(3, 2) — refused once at the call, naming its forward"

# BC — a bounded call on a struct carrier's T field (6.7.14)
cat > "$T/bc0.cyr" <<'EOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for i64 { fn show(self): i64 { return self + 1; } }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
struct Box<T> { v: T; n; }
fn gs<T: Show>(b: Box<T>): i64 { return b.v.show(); }
fn go(): i64 {
    var b: Box<Pt>; b.v.x = 1; b.v.y = 6; b.n = 2;
    var bi: Box<i64>; bi.v = 4; bi.n = 1;
    return gs(b) * 10 + gs(bi);
}
syscall(60, go());
EOF
exits bc0 65 "BC0: the filed repro, verbatim — gs(b) * 10 + gs(bi), b.v.show() on Pt and on i64"
BCH='trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
struct Box<T> { v: T; n; }'
BCI='impl Show for i64 { fn show(self): i64 { return self + 1; } }'
BCB='var b: Box<Pt>; b.v.x = 1; b.v.y = 6; b.n = 2; var bi: Box<i64>; bi.v = 4; bi.n = 1;'
bcmk() {   # <name> <decls> <go body>
    printf 'include "lib/syscalls.cyr"\n%s\n%s\nfn go(): i64 { %s %s }\nsyscall(60, go());\n' "$BCH" "$2" "$BCB" "$3" > "$T/$1.cyr"
}
BCG='fn gs<T: Show>(b: Box<T>): i64 { return b.v.show(); }'
bcmk bc1 "$BCG" 'return gs(b);'
exits bc1 6 "BC1: gs(b) alone, no i64 impl"
bcmk bc2 "$BCI
fn gp<T: Show>(b: *Box<T>): i64 { return b.v.show() + b.n; }" 'return gp(&b) * 10 + gp(&bi);'
exits bc2 86 "BC2: a *Box<T> carrier, gp(&b) * 10 + gp(&bi)"
bcmk bc3 "$BCG" 'return gs(bi);'
refused bc3 "generic 'gs': its type argument does not implement trait 'Show'" "BC3: gs(bi) with no impl Show for i64"
grep -qF "needs \`impl Show for i64\`" "$T/bc3.err" && ok "BC3: the note names \`impl Show for i64\`" || bad "BC3: no note naming \`impl Show for i64\`"
bcmk bc4 "impl Show for f64 { fn show(self): i64 { return 30; } }
impl Show for i32 { fn show(self): i64 { return self + 40; } }
$BCG" 'var bf: Box<f64>; bf.v = 1.5; bf.n = 1; var bw: Box<i32>; bw.v = 2; bw.n = 1; return gs(bf) + gs(bw);'
exits bc4 72 "BC4: f64 and i32 instances, gs(bf) + gs(bw) (30 + 42)"
bcmk bc5 "$BCI
fn gl<T: Show>(b: Box<T>): i64 { var c: Box<T> = b; var r = c.v.show(); c.v.show(); return r + c.n; }" 'return gl(b) * 10 + gl(bi);'
exits bc5 86 "BC5: a var c: Box<T> carrier, var r = c.v.show(); and the statement c.v.show();"
bcmk bc6 "$BCI
$BCG" 'return gs<i64>(bi) + gs(bi);'
exits bc6 10 "BC6: gs<i64>(bi), explicit"
bcmk bc7 "$BCI
impl Pt { fn other(self): i64 { return 77; } }
fn go2<T: Show>(b: Box<T>): i64 { return b.v.other(); }" 'return go2(b);'
refused bc7 "method 'other' is not in the bound on type parameter 'T'" "BC7: b.v.other(), a method no bound declares — refused at the definition (6.7.15's D5; it kept its 6.7.11 reading, 77)"
bcmk bc8 "$BCI
fn gn<T: Show>(b: Box<T>): i64 { return b.v.show() + b.n; }" 'var s = 0; var i = 0; while (i < 3) { s = s + gn(bi); i = i + 1; } return s;'
exits bc8 18 "BC8: in a loop, gn(bi) three times"
bcmk bc9 "$BCI
fn gw<T: Show>(b: Box<T>): i64 { var t: T = b.v; return t.show(); }" 'return gw(b) * 10 + gw(bi);'
exits bc9 65 "BC9: the documented workaround (var t: T = b.v;) unchanged"
bcmk bc10 "$BCG" 'return 4;'
exits bc10 4 "BC10: the definition alone, no impl Show for i64"

# BD — 6.7.15 (D5): the bound's contract holds on a carrier's T field, as on a T-typed name
cat > "$T/bd0.cyr" <<'EOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
impl Pt { fn other(self): i64 { return 77; } }
struct Box<T> { v: T; n; }
fn gs<T: Show>(b: Box<T>): i64 { return b.v.other(); }
fn go(): i64 { var b: Box<Pt>; b.v.x = 1; b.v.y = 6; b.n = 2; return gs(b); }
syscall(60, go());
EOF
BDM="method 'other' is not in the bound on type parameter 'T'"
refused bd0 "error:<source>:7:45: $BDM" "BD0: the filed repro, verbatim — b.v.other() under T: Show (exit 77 before)"
grep -qF "call only its traits' methods on 'b.v'" "$T/bd0.err" && ok "BD0: the note names the field chain 'b.v'" || bad "BD0: no note naming 'b.v': $(grep '^  note' "$T/bd0.err" | head -1)"
BDH="$BCH
impl Pt { fn other(self): i64 { return 77; } }"
bdmk() {   # <name> <decls> <go body>
    printf 'include "lib/syscalls.cyr"\n%s\n%s\nfn go(): i64 { %s %s }\nsyscall(60, go());\n' "$BDH" "$2" "$BCB" "$3" > "$T/$1.cyr"
}
bdmk bd1 'fn gs<T: Show>(b: Box<T>): i64 { return b.v.other(); }' 'return 4;'
refused bd1 "$BDM" "BD1: the definition alone, never called — refused there"
bdmk bd2 'fn gp<T: Show>(b: *Box<T>): i64 { return b.v.other(); }' 'return gp(&b);'
refused bd2 "$BDM" "BD2: a *Box<T> carrier"
bdmk bd3 'fn gl<T: Show>(x: T): i64 { var c: Box<T>; c.v = x; var r = c.v.other(); return r; }' 'return 4;'
refused bd3 "$BDM" "BD3: a var c: Box<T> carrier, var r = c.v.other();"
bdmk bd4 'fn g2<U, T: Show>(k: U, b: Box<T>): i64 { return b.v.other() + k; }' 'return g2(1, b);'
refused bd4 "$BDM" "BD4: the bound on the SECOND type parameter (fn g2<U, T: Show>)"
bdmk bd5 'struct Two<A, B> { a: A; b: B; }
fn gt<T: Show>(w: Two<i64, T>): i64 { return w.b.other(); }' 'return 4;'
refused bd5 "$BDM" "BD5: Two<i64, T>'s second field, w.b.other()"
bdmk bd6 'struct Q { k; }
impl Q { fn m<T: Show>(self, b: Box<T>): i64 { return b.v.other(); } }' 'return 4;'
refused bd6 "$BDM" "BD6: in a generic method"
bdmk bd7 'trait Disp { fn show(self): i64; }
impl Disp for Pt { fn show(self): i64 { return 50; } }
fn ga<T: Show + Disp>(b: Box<T>): i64 { return b.v.show(); }' 'return ga(b);'
refused bd7 "ambiguous method 'show': more than one trait in this type parameter's bound declares it, e.g. 'Disp'" "BD7: a method two bounds both declare — ambiguous, at the definition (refused at the instance's call before, with a cascade)"
bdmk bdk 'fn gu<T>(b: Box<T>): i64 { return b.v.other(); }
fn g3<T: Show, U>(t: T, b: Box<U>): i64 { return b.v.other(); }
struct PB<T> { p: *T; n; }
fn gq<T: Show>(b: PB<T>): i64 { return b.p.other(); }
fn gx<T: Show>(b: Box<T>): i64 { return b.v.show() + b.v.y; }' 'var p: Pt; var pt: Pt; pt.y = 6; var q: PB<Pt>; q.p = &pt; q.n = 1; return gu(b) + g3(p, b) - gq(q) + gx(b) - 77;'
exits bdk 12 "BDK: unchanged — an unbounded Box<T> (77), an unbounded slot beside a bounded one (77), a f: *T field (77), b.v.show() + b.v.y (12)"

# N — a bound refusal swallowed by the panic latch (6.7.14)
mk n1 'fn gb<T: Show>(x: T): i64 { var t = 0; var i = 0; while (i < 1) { t = t + x.show(); i = i + 1; } return t; }
fn gs<T>(q: T): i64 { var s = 0; var i = 0; while (i < 2) { s = s + q.y; i = i + 1; } return s; }' 'var b = gs(5) + gb(3); return b;'
refused n1 "generic 'gs' has no i64 (or other scalar) instance" "N1: gs(5) + gb(3) — the stub's refusal"
# 6.7.16 (the user's D1): the stub's refusal carries its own note, the line that needs a struct; no other.
if grep "^  note:" "$T/n1.err" | grep -vq "'gs' takes a field of a value typed by its type parameter"; then bad "N1: an orphan note under the stub's error: $(grep '^  note:' "$T/n1.err" | grep -v "'gs' takes a field" | head -1)"
elif ! grep -q "^  note: <source>:[0-9]*:[0-9]*: 'gs' takes a field" "$T/n1.err"; then bad "N1: the stub's own note is missing"
else ok "N1: the stub's own note, and no orphan note for the swallowed gb(3) refusal"; fi
# N2 (6.7.15): a contract refusal the latch swallowed (a second definition's `v.other()`, a second `b.v.other()` in one
# body) printed its note alone under the first's. 6.7.16 (NS below): none is swallowed — four refusals, four errors,
# each with its note (one error and one note through 6.7.15).
mk n2 'impl Pt { fn other(self): i64 { return 77; } }
struct Box<T> { v: T; n; }
fn g1<T: Show>(v: T): i64 { return v.other(); }
fn g2<T: Show>(v: T): i64 { return v.other(); }
fn gm<T: Show>(b: Box<T>): i64 { var r = b.v.other(); b.v.other(); return r; }' 'return 4;'
build n2
ne=$(grep -c "^error:<source>:[0-9]*:[0-9]*: method 'other' is not in the bound on type parameter 'T'" "$T/n2.err")
nn=$(grep -c '^  note:' "$T/n2.err")
na=$(grep -c '^error' "$T/n2.err")
if [ "$rc" -ne 0 ] && [ "$ne" -eq 4 ] && [ "$na" -eq 4 ] && [ "$nn" -eq 4 ]; then ok "N2: four contract refusals, four errors, four notes (6.7.16)"
else bad "N2: rc $rc, $ne contract errors of $na, $nn notes (want 4 / 4 / 4)"; fi

# C — anti-vacuous
mk c1 'trait Eq2 { fn eq2(self, o: Pt): i64; }
impl Eq2 for Pt { fn eq2(self, o: Pt): i64 { return self.x - o.x; } }
fn f<T: Show + Eq2>(a: T, b: T): i64 { return a.show() + a.eq2(b); }
fn s<T: Size>(v: T): i64 { return v.size(); }
impl Show for i64 { fn show(self): i64 { return self + 1; } }
fn g<T: Show>(v: T): i64 { return v.show(); }
struct Box<T: Show> { v: T; n; }
fn u<T>(v: T): i64 { return v.show(); }' 'var b: Box<Pt>; b.n = 0; return f(p, p) - 42 + s(p) + g(5) - 6 + b.n + u(p) - 42 + 42;'
exits c1 44 "C1: T: Show + Eq2, a colliding size picked by T: Size, i64's impl, Box<Pt>, an unbounded T"
printf 'fn id<T>(v: T): i64 { return v + 1; }\nsyscall(60, id(41));\n' > "$T/c2.cyr"
exits c2 42 "C2: a program with no bound"

# VB — 6.7.15 (D10): a Vec element's generic struct is held to its bounds, nothing minted
errs() {   # <name> <n> <what> <fragment>...: refused with exactly <n> `^error` lines, each fragment among them
    nm=$1; want=$2; what=$3; shift 3
    build "$nm"
    k=$(grep -c '^error' "$T/$nm.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$what: BUILT (rc 0)"; return; fi
    if [ "$k" -ne "$want" ]; then bad "$what: $k error lines (want $want): $(grep '^error' "$T/$nm.err" | head -3 | tr '\n' ' ')"; return; fi
    for l in "$@"; do
        if ! grep -qF -- "$l" "$T/$nm.err"; then bad "$what: no line '$l': $(grep '^error' "$T/$nm.err" | head -3 | tr '\n' ' ')"; return; fi
    done
    ok "$what: refused, $k error line(s) as wanted"
}
cat > "$T/vb0.cyr" <<'EOF'
include "lib/vec.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
struct Box<T: Show> { v: T; n; }
fn main(): i64 {
    var w: Vec<Box<Pt>> = 0;
    return 5;
}
syscall(60, main());
EOF
VBE="generic 'Box': its type argument does not implement trait 'Show'"
errs vb0 1 "VB0: the filed repro verbatim — the bound's error once, at the element (it built: exit 5)" "error:<source>:6:16: $VBE"
grep -qF "needs \`impl Show for Pt\`" "$T/vb0.err" && ok "VB0: ... with its note" || bad "VB0: no note naming \`impl Show for Pt\`"
sed 's/^struct Pt { x; y; }$/struct Pt { x; y; }\nimpl Show for Pt { fn show(self): i64 { return self.x; } }/' "$T/vb0.cyr" > "$T/vb1.cyr"
exits vb1 5 "VB1: the repro with \`impl Show for Pt\` present"
VBH='include "lib/vec.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
struct R { r; }
struct Box<T: Show> { v: T; n; }
struct Two<A, B> { a: A; b: B; }
impl Show for R { fn show(self): i64 { return self.r; } }'
vb() { printf '%s\n%s\nsyscall(60, 7);\n' "$VBH" "$2" > "$T/$1.cyr"; }
vb vb2 'struct H { items: Vec<Box<Pt>>; k; }'
errs vb2 1 "VB2: a struct field items: Vec<Box<Pt>>" "error:<source>:8:23: $VBE"
vb vb3 'fn f(): i64 { var w: Vec<Box<i64>> = 0; return 5; }'
errs vb3 1 "VB3: Vec<Box<i64>> — the i64 base's bound, as var b: Box<i64>" "error:<source>:8:26: $VBE"
vb vb3b 'fn g(): i64 { var u: Vec<Box> = 0; return 5; }'
errs vb3b 1 "VB3b: a bare Vec<Box> — as var b: Box;" "error:<source>:8:26: $VBE"
vb vb4 'fn f(): i64 { var w: Vec<Two<Box<Pt>, i64>> = 0; return 5; }'
errs vb4 1 "VB4: nested, Vec<Two<Box<Pt>, i64>>" "error:<source>:8:30: $VBE"
vb vb4b 'fn f(): i64 { var w: Vec<Vec<Box<Pt>>> = 0; return 5; }'
errs vb4b 1 "VB4b: nested, Vec<Vec<Box<Pt>>>" "error:<source>:8:30: $VBE"
vb vb4c 'fn f(m: Vec<Box<Pt>>): i64 { return 5; }'
errs vb4c 1 "VB4c: a parameter m: Vec<Box<Pt>>, at the definition" "error:<source>:8:13: $VBE"
vb vb4d 'var GW: Vec<Box<Pt>> = 0;'
errs vb4d 1 "VB4d: a global" "error:<source>:8:13: $VBE"
vb vb5 'fn g<T>(x: T): i64 { var w: Vec<Box<T>> = 0; return 5; }
fn f(): i64 { var p: Pt; var r = R { 1 }; return g(p) + g(r) + g<Pt>(p) + g<R>(r); }'
errs vb5 1 "VB5: a generic's Vec<Box<T>> — judged per instance (Pt once), not in its base" "error:<source>:8:33: $VBE"
vb vb6 'struct W<T> { items: Vec<Box<T>>; k; }
fn f(): i64 { var a: W<R>; var b: W<Pt>; return 5; }'
errs vb6 1 "VB6: a generic struct's items: Vec<Box<T>>, W<Pt> at the field, W<R> fine" "error:<source>:8:26: $VBE"
vb vb7 'fn f(): i64 { var w: Vec<Box<Pt>> = 0; var u: Vec<Box<Pt>> = 0; var b: Box<Pt>; return 5; }'
errs vb7 1 "VB7: once per (struct, arguments), as every bound refusal" "error:<source>:8:26: $VBE"
vb vb8 'fn f(): i64 { var w: Vec<Box<nosuch>> = 0; return 5; }'
errs vb8 1 "VB8: a refused argument stands alone" "unknown type 'nosuch' as a type argument"
vb vb9 'fn f(): i64 { var w: Vec<Two<Box<Pt>, nosuch>> = 0; return 5; }'
errs vb9 2 "VB9: the list reads on after the bound's error" "error:<source>:8:30: $VBE" "unknown type 'nosuch' as a type argument"
cat > "$T/vbk.cyr" <<'EOF'
include "lib/vec.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
struct R { r; }
struct Box<T: Show> { v: T; n; }
struct Two<A, B> { a: A; b: B; }
impl Show for R { fn show(self): i64 { return self.r; } }
struct H { items: Vec<Box<R>>; k; }
struct W<T> { items: Vec<Box<T>>; k; }
var GW: Vec<Box<R>> = 0;
fn g<T>(x: T): i64 { var w: Vec<Box<T>> = 0; return 2; }
fn pm(m: Vec<Box<R>>, n: Vec<Two<Pt, i64>>): i64 { return 3; }
fn main(): i64 {
    var a: Vec<Box<R>> = 0;
    var b: Vec<Two<Box<R>, Pt>> = 0;
    var c: Vec<Vec<Box<R>>> = 0;
    var d: Vec<Pt> = 0;
    var h: H;
    var w: W<R>;
    var r = R { 1 };
    return g(r) + g<R>(r) + pm(0, 0) + sizeof(Box<R>);
}
syscall(60, main());
EOF
exits vbk 23 "VBK: with the impl — Vec<Box<R>> (local, field, global, parameter), nested, a generic's Vec<Box<T>> at R, W<R>, an unbounded Two, Vec<Pt>"

# VN — 6.7.16 (D10): a Vec element's generic struct whose argument is itself an instance, judged as by value
cat > "$T/vn0.cyr" <<'EOF'
include "lib/vec.cyr"
trait Show { fn show(self): i64; }
struct R { r; }
struct Box<T: Show> { v: T; n; }
impl Show for R { fn show(self): i64 { return self.r; } }
fn main(): i64 {
    var w: Vec<Box<Box<R>>> = 0;
    return 5;
}
syscall(60, main());
EOF
errs vn0 1 "VN0: the filed repro verbatim — refused once, at the element (it built: exit 5)" "error:<source>:7:16: $VBE"
note() {   # <name> <instance> <what>
    if grep -qF "needs \`impl Show for $2\`" "$T/$1.err"; then ok "$3: the note names $2"
    else bad "$3: no note naming $2: $(grep note "$T/$1.err" | tr '\n' ' ')"; fi
}
note vn0 'Box$R' "VN0"
VNH='include "lib/vec.cyr"
trait Show { fn show(self): i64; }
struct R { r; }
struct Box<T: Show> { v: T; n; }
struct UB<T> { v: T; }
struct SB<T: Show> { v: T; }
impl Show for R { fn show(self): i64 { return self.r; } }'
vn() { printf '%s\n%s\nsyscall(60, 7);\n' "$VNH" "$2" > "$T/$1.cyr"; }
SBE="generic 'SB': its type argument does not implement trait 'Show'"
vn vn1 'fn f(): i64 { var w: Vec<SB<UB<R>>> = 0; return 5; }'
errs vn1 1 "VN1: Vec<SB<UB<R>>>, an unbounded inner instance" "error:<source>:8:26: $SBE"
note vn1 'UB$R' "VN1"
printf '%s\n%s\nsyscall(60, f());\n' "$VNH" 'fn f(): i64 { var w: Vec<UB<Box<R>>> = 0; var u: Vec<UB<UB<R>>> = 0; return 5; }' > "$T/vn2.cyr"
exits vn2 5 "VN2: an unbounded outer struct over an instance builds"
vn vn3 'fn f(): i64 { var w: Vec<Box<Box<i64>>> = 0; return 5; }'
errs vn3 2 "VN3: Vec<Box<Box<i64>>> — the inner base, judged as 6.7.15 judged it" "error:<source>:8:30: $VBE" "error:<source>:8:26: $VBE"
note vn3 'Box' "VN3: the outer against impl Show for Box (a base, no instance)"
vn vn4 'struct H2 { w: Vec<Box<Box<R>>>; k; }'
errs vn4 1 "VN4: a struct field" "error:<source>:8:20: $VBE"
vn vn4b 'fn f(m: Vec<Box<Box<R>>>): i64 { return 5; }'
errs vn4b 1 "VN4b: a parameter, at the definition" "error:<source>:8:13: $VBE"
vn vn4c 'var GW: Vec<Box<Box<R>>> = 0;'
errs vn4c 1 "VN4c: a global" "error:<source>:8:13: $VBE"
vn vn5 'fn f(): i64 { var w: Vec<Box<Box<Box<R>>>> = 0; return 5; }'
errs vn5 1 "VN5: Vec<Box<Box<Box<R>>>> — the first refused list alone, as by value" "error:<source>:8:30: $VBE"
note vn5 'Box$R' "VN5"
vn vn5b 'fn f(): i64 { var w: Vec<Box<UB<UB<R>>>> = 0; return 5; }'
errs vn5b 1 "VN5b: Vec<Box<UB<UB<R>>>>" "error:<source>:8:26: $VBE"
note vn5b 'UB$UB$R' "VN5b"
vn vn6 'fn g<T>(x: T): i64 { var w: Vec<Box<Box<T>>> = 0; return 5; }
fn f(): i64 { var r = R { 1 }; return g(r) + g<R>(r); }'
errs vn6 1 "VN6: a generic's Vec<Box<Box<T>>> — per instance (R once), not in its base" "error:<source>:8:33: $VBE"
vn vn7 'fn f(): i64 { var w: Vec<Box<Box<R>>> = 0; var b: Box<Box<R>>; var u: Vec<Box<Box<R>>> = 0; return 5; }'
errs vn7 1 "VN7: once per (struct, arguments), the by-value form among them" "error:<source>:8:26: $VBE"
vn vn8 'impl Show for Box { fn show(self): i64 { return 1; } }
fn f(): i64 { var w: Vec<Box<Box<R>>> = 0; return 5; }'
errs vn8 2 "VN8: impl Show for Box names no instance — the element refused (the impl's own i64 line apart)" "error:<source>:9:26: $VBE"
note vn8 'Box$R' "VN8"

# NS — 6.7.16: every contract refusal of a compile prints (`_bnd_site_refuse` reports without the panic latch; the site
# scan is a pre-scan nothing resyncs, so the first refusal's latch swallowed the rest)
cat > "$T/ns0.cyr" <<'EOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
impl Pt { fn other(self): i64 { return 77; } }
fn g1<T: Show>(v: T): i64 { return v.other(); }
fn g2<T: Show>(v: T): i64 { return v.other(); }
fn go(): i64 { return 3; }
syscall(60, go());
EOF
errs ns0 2 "NS0: the filed repro verbatim — g1's and g2's refusals both print (g2's was swallowed)" "error:<source>:6:38: $BDM" "error:<source>:7:38: $BDM"
nn=$(grep -c "^  note: a bound is the contract for a bounded type parameter - call only its traits' methods on 'v'" "$T/ns0.err")
if [ "$nn" -eq 2 ]; then ok "NS0: two notes, one per refusal"; else bad "NS0: $nn notes (want 2)"; fi
NSH='include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
impl Pt { fn other(self): i64 { return 77; } }
struct Box<T> { v: T; n; }'
ns() { printf '%s\n%s\nsyscall(60, 3);\n' "$NSH" "$2" > "$T/$1.cyr"; }
ns ns1 'fn gm<T: Show>(b: Box<T>): i64 { var r = b.v.other(); b.v.other(); return r; }'
errs ns1 2 "NS1: two refusals in one body (b.v.other() twice) both print" "error:<source>:7:46: $BDM" "error:<source>:7:59: $BDM"
nn=$(grep -c "on 'b.v', or add" "$T/ns1.err")
if [ "$nn" -eq 2 ]; then ok "NS1: two notes naming 'b.v'"; else bad "NS1: $nn notes naming 'b.v' (want 2)"; fi
ns ns2 'trait Disp { fn show(self): i64; }
impl Disp for Pt { fn show(self): i64 { return 50; } }
fn g1<T: Show>(v: T): i64 { return v.other(); }
fn ga<T: Show + Disp>(v: T): i64 { return v.show(); }
fn gf<T: Show + Disp>(b: Box<T>): i64 { return b.v.show(); }'
errs ns2 3 "NS2: an ambiguous refusal (a name, a carrier's field) after a contract refusal prints" "error:<source>:9:38: $BDM" "error:<source>:10:45: ambiguous method 'show'" "error:<source>:11:52: ambiguous method 'show'"
ns ns3 'fn g1<T: Show>(v: T): i64 { return v.other(); }
fn gk(): i64 { var k = 1 2; return 3; }
fn g2<T: Show>(v: T): i64 { return v.other(); }
fn gk2(): i64 { var j = 4 5; return 3; }'
errs ns3 4 "NS3: pass-2 errors around them still print, after both refusals" "error:<source>:7:38: $BDM" "error:<source>:9:38: $BDM" "error:<source>:8:26: expected ';'" "error:<source>:10:27: expected ';'"
ns ns4 'impl Pt { fn m<T: Show>(self, v: T): i64 { return v.other(); } }
fn g1<T: Show>(v: T): i64 { return v.other(); }'
errs ns4 2 "NS4: a generic method's refusal (recorded in pass 2) and a fn's both print" "error:<source>:7:53: $BDM" "error:<source>:8:38: $BDM"

# BX — 6.7.16 (the user's D4, 2026-10-19): the explicit spelling `v.m<..>(..)` is held to the contract, and a bound's own
# generic member called with it is the bound's call (at a scalar T too)
cat > "$T/bx0.cyr" <<'EOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
impl Pt { fn other<V>(self, k: V): i64 { return 77; } }
struct Box<T> { v: T; n; }
fn gn<T: Show>(v: T): i64 { return v.other<i64>(1); }
fn gs<T: Show>(b: Box<T>): i64 { return b.v.other<i64>(1); }
fn go(): i64 { var p: Pt; p.y = 6; var b: Box<Pt>; b.v.y = 6; return gn(p) + gs(b); }
syscall(60, go());
EOF
errs bx0 2 "BX0: the filed repro verbatim — refused at both definitions (exit 154 before)" "error:<source>:7:38: $BDM" "error:<source>:8:45: $BDM"
if grep -qF "methods on 'v', or add" "$T/bx0.err" && grep -qF "methods on 'b.v', or add" "$T/bx0.err"; then ok "BX0: the notes name 'v' and 'b.v'"
else bad "BX0: the notes do not name 'v' and 'b.v': $(grep '^  note' "$T/bx0.err" | tr '\n' ' ')"; fi
BXH='include "lib/syscalls.cyr"
trait Show { fn show<V>(self, k: V): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show<V>(self, k: V): i64 { return self.y + sizeof(V); } }
impl Pt { fn other<V>(self, k: V): i64 { return 77; } }
struct Box<T> { v: T; n; }'
bx() { printf '%s\n%s\n%s\n' "$BXH" "$2" "$3" > "$T/$1.cyr"; }
bx bx1 'fn gn<T: Show>(v: T): i64 { var a = v.other<i64>(1); var b = v.other<i64>(2); return a + b; }' 'syscall(60, 3);'
errs bx1 2 "BX1: the definition alone, never called — both calls of one body refused there" "error:<source>:7:39: $BDM" "error:<source>:7:64: $BDM"
bx bx2 'fn gp<T: Show>(p: *T): i64 { return p.other<i32>(1); }
fn gl<T: Show>(x: T): i64 { var c: Box<T>; c.v = x; var r = c.v.other<i64>(1); return r; }
fn gq<T: Show>(b: *Box<T>): i64 { return b.v.other<i64>(1); }
fn g2<U, T: Show>(k: U, b: Box<T>): i64 { return b.v.other<i64>(1) + k; }
struct Q { k; }
impl Q { fn m<T: Show>(self, v: T): i64 { return v.other<i64>(1); } }' 'syscall(60, 3);'
errs bx2 5 "BX2: a p: *T, a var c: Box<T>, a *Box<T>, the second type parameter, a generic method" "error:<source>:7:39: $BDM" "error:<source>:8:65: $BDM" "error:<source>:9:46: $BDM" "error:<source>:10:54: $BDM" "error:<source>:12:52: $BDM"
bx bx3 'fn gn<T: Show>(v: T): i64 { return v.other<Pt, i64>(1); }
fn gl<T: Show>(v: T): i64 { return v.other<Later>(1); }
fn gb<T: Show>(v: T): i64 { return v.other<Box<i64>>(1); }
struct Later { a; }' 'syscall(60, 3);'
errs bx3 3 "BX3: lists of two, of a struct declared below, of a nested instance (a \`>>\` close)" "error:<source>:7:38: $BDM" "error:<source>:8:38: $BDM" "error:<source>:9:38: $BDM"
bx bx4 'fn gn<T: Show>(v: T): i64 { return v.show<i64>(1); }' 'fn go(): i64 { var p: Pt; p.y = 6; return gn(p) - 7; }
syscall(60, go());'
exits bx4 7 "BX4: a bound's own generic member, v.show<i64>(1), at a struct T (6 + 8 - 7)"
BXS='impl Show for i64 { fn show<V>(self, k: V): i64 { return self + sizeof(V); } }'
bx bx5 "$BXS
fn gn<T: Show>(v: T): i64 { return v.show<i64>(1); }" 'syscall(60, gn(0 - 1));'
exits bx5 7 "BX5: ... at a scalar T, impl Show for i64 (refused before: the stub base)"
bx bx6 "$BXS
fn gs<T: Show>(b: Box<T>): i64 { return b.v.show<i64>(1); }" 'fn go(): i64 { var b: Box<i64>; b.v = 0 - 1; b.n = 0; return gs(b); }
syscall(60, go());'
exits bx6 7 "BX6: the field form b.v.show<i64>(1) at a scalar T (refused before: the stub base)"
bx bx7 "$BXS
fn gn<T: Show>(v: T): i64 { return v.show<i16>(1) * 10 + v.show<i8>(1); }
fn gs<T: Show>(b: Box<T>): i64 { return b.v.show<i32>(1); }" 'fn go(): i64 { var p: Pt; p.y = 1; var b: Box<i64>; b.v = 1; b.n = 0; var c: Box<Pt>; c.v.y = 1; return gn(p) + gn(1) + gs(b) + gs(c); }
syscall(60, go());'
exits bx7 74 "BX7: the list is kept, not re-inferred — sizeof(i16), sizeof(i8), sizeof(i32) at a struct and a scalar T (32 + 32 + 5 + 5)"
bx bxk 'fn g<T: Show>(v: T, a, c): i64 { return id2(v.y < a, c > (1)); }
fn gf<T: Show>(b: Box<T>, a, c): i64 { return id2(b.v.y < a, c > (1)); }
fn gi<T: Show>(v: T, a): i64 { if (v.y < a) { return 1; } return 0; }
fn u<T>(v: T): i64 { return v.other<i64>(1); }
fn id2(a, b): i64 { return a * 10 + b; }' 'fn go(): i64 { var p: Pt; p.y = 6; var b: Box<Pt>; b.v.y = 6; return g(p, 9, 3) + gf(b, 9, 3) + gi(p, 9) + u(p) - 100; }
syscall(60, go());'
exits bxk 0 "BXK: unchanged — a comparison on a bounded T's field (v.y < a, c > (1); not a type list), if (v.y < a), an unbounded T's explicit call (77)"
bx bxu 'fn gn<T: Show>(v: T): i64 { return v.other<Nope>(1); }' 'fn go(): i64 { var p: Pt; p.y = 6; return gn(p); }
syscall(60, go());'
refused bxu "unknown type 'Nope' as a type argument" "BXU: a list naming no type is no site — the call reports its unknown type"
cat > "$T/bx8.cyr" <<'EOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
impl Pt { fn other<V>(self, k: V): i64 { return k.x; } }
fn gn<T: Show>(v: T): i64 { return v.other<i64>(1); }
fn go(): i64 { var p: Pt; p.y = 6; return gn(p); }
syscall(60, go());
EOF
errs bx8 1 "BX8: a refused site's call is consumed quietly at the instance — nothing minted, so Pt.other<i64>'s own refusal does not print" "error:<source>:6:38: $BDM"
# BXS (6.7.16): --syntax-only (cyrius lint) parses the explicit spelling at a scalar T — the receiver has no struct,
# and the chain walk left the list: "expected ';', got '>'", a syntax error the file does not have.
for b in bx5 bx6 bx7; do
    src=0; "$CC" --syntax-only < "$T/$b.cyr" > /dev/null 2> "$T/$b.so" || src=$?
    if [ "$src" -eq 0 ] && [ "$(grep -c '^error' "$T/$b.so")" -eq 0 ]; then ok "BXS: --syntax-only on $b is silent (rc 0)"
    else bad "BXS: --syntax-only on $b: rc $src: $(grep '^error' "$T/$b.so" | head -2 | tr '\n' '|')"; fi
done

# DS — 6.7.17: pass 2 steps a struct's `<..>` nested (`_tl_skip_struct`)
printf 'trait Show { fn show(self): i64; }\nstruct B<T: Show<i64>> { a; }\nfn main(): i64 { var x = 1 2; return 0; }\nsyscall(60, main());\n' > "$T/ds1.cyr"
errs ds1 2 "DS1: struct B<T: Show<i64>> — D5's line, and the next fn's own (it was \"undefined function 'main'\")" \
    "error:<source>:2:13: a trait in a bound takes no type arguments: 'Show'" "error:<source>:3:28: expected ';', got number 2"
printf 'trait Show { fn show(self): i64; }\nstruct B<T: Show<i64> > { a; }\nfn main(): i64 { var x = 1 2; return 0; }\nsyscall(60, main());\n' > "$T/ds2.cyr"
errs ds2 2 "DS2: struct B<T: Show<i64> > — no \"expected '{', got '>'\"" \
    "error:<source>:2:13: a trait in a bound takes no type arguments: 'Show'" "error:<source>:3:28: expected ';', got number 2"
printf 'trait Show { fn show(self): i64; }\nimpl Show for i64 { fn show(self): i64 { return self; } }\nstruct B<T: Show> { a: T; }\nstruct C<T, U: Show> { a: T; b: U; }\nfn g<T: Show>(v: T): i64 { return v.show(); }\nfn main(): i64 { var c: C<i8, i64>; c.b = 3; return c.b + g(1); }\nsyscall(60, main());\n' > "$T/ds3.cyr"
exits ds3 4 "DS3: bounded structs, then a bounded generic below them"
printf 'trait Show { fn show(self): i64; }\nfn d<U: Show<i64>>(u: U): i64 { return 1; }\nstruct Q { a: Foo; }\nsyscall(60, 3);\n' > "$T/ds4.cyr"
errs ds4 2 "DS4: fn d<U: Show<i64>> — D5's line, and the next struct's own (pass 1's fn skip)" \
    "error:<source>:2:9: a trait in a bound takes no type arguments: 'Show'" "error:<source>:3:15: unknown type 'Foo' for struct field 'a'"

# DL — 6.7.17: a bound's refusal puts the panic latch back (`_bnd_make`)
UTB="in the bound on type parameter"
printf 'fn a<U: Nope>(u: U): i64 { return 1; }\nstruct B<T: Zork> { a; }\nfn c<U: Nope2>(u: U): i64 { return 1; }\nsyscall(60, 3);\n' > "$T/dl1.cyr"
errs dl1 3 "DL1: three unknown bounds, a fn's, a struct's and a fn's — each its line (it was the first alone)" \
    "error:<source>:1:9: unknown trait 'Nope' $UTB 'U'" "error:<source>:2:13: unknown trait 'Zork' $UTB 'T'" \
    "error:<source>:3:9: unknown trait 'Nope2' $UTB 'U'"
printf 'fn c<U: Nope2>(u: U): i64 { return 1; }\nstruct Q { a: Foo; }\nfn main(): i64 { var x = 1 2; return 0; }\nsyscall(60, 3);\n' > "$T/dl2.cyr"
errs dl2 3 "DL2: a struct's field error and a fn body's after it" "error:<source>:1:9: unknown trait 'Nope2' $UTB 'U'" \
    "error:<source>:2:15: unknown type 'Foo' for struct field 'a'" "error:<source>:3:28: expected ';', got number 2"
printf 'trait Show { fn show(self): i64; }\nfn c<U: 5>(u: U): i64 { return 1; }\nstruct Q { a: Foo; }\nfn d<U: Show<i64> >(u: U): i64 { return 1; }\nstruct R { b: Bar; }\nsyscall(60, 3);\n' > "$T/dl3.cyr"
errs dl3 4 "DL3: a malformed bound and a bound with arguments, each with the next struct's error" \
    "error:<source>:2:9: expected a trait name in a type parameter's bound" "error:<source>:3:15: unknown type 'Foo' for struct field 'a'" \
    "error:<source>:4:9: a trait in a bound takes no type arguments: 'Show'" "error:<source>:5:15: unknown type 'Bar' for struct field 'b'"
printf 'struct M { x; }\nimpl M { fn m<V: Nope4>(self, v: V): i64 { return 1; } fn n<V: Nope5>(self, v: V): i64 { return 1; } }\nsyscall(60, 3);\n' > "$T/dl4.cyr"
errs dl4 2 "DL4: two impl methods' unknown bounds" "error:<source>:2:18: unknown trait 'Nope4' $UTB 'V'" "error:<source>:2:64: unknown trait 'Nope5' $UTB 'V'"

# DW — 6.7.17: a bound's trait is no type parameter; a name past a nested list is one (`_tpl_has`)
printf 'trait Show { fn show(self): i64; }\nimpl Show for i64 { fn show(self): i64 { return self; } }\nfn f<T: Show>(x: T, y: Show): i64 { return 1; }\nfn h<T: Show>(x: T): i64 { var z: Show = 0; return 1; }\nfn g(y: Show): i64 { return 1; }\nsyscall(60, f(1, 2) + h(1));\n' > "$T/dw1.cyr"
errs dw1 3 "DW1: y: Show in a bounded generic's signature and body, as in g's" "error:<source>:3:24: unknown type 'Show' for parameter 'y'" \
    "error:<source>:4:35: unknown type 'Show' for variable 'z'" "error:<source>:5:9: unknown type 'Show' for parameter 'y'"
printf 'trait Show { fn show(self): i64; }\nstruct B<T: Show<i64>, U> { a: U; }\nstruct C<T<i64>, U> { a: U; }\nfn k<T: Show<i64>, U>(u: U): i64 { var q: U = u; return q; }\nsyscall(60, 3);\n' > "$T/dw2.cyr"
errs dw2 3 "DW2: no \"unknown type 'U'\" past a refused list" "error:<source>:2:13: a trait in a bound takes no type arguments: 'Show'" \
    "error:<source>:3:11: a type parameter is a name, got '<'" "error:<source>:4:9: a trait in a bound takes no type arguments: 'Show'"
rc=0; CYRIUS_MONOMORPH=0 "$CC" < "$T/dw2.cyr" > /dev/null 2> "$T/dw2m.err" || rc=$?
if [ "$rc" -ne 0 ] && [ "$(grep -c '^error' "$T/dw2m.err")" -eq 1 ] && grep -qF "error:<source>:3:11: a type parameter is a name, got '<'" "$T/dw2m.err"; then
    ok "DW2 [mono0]: the list's own line alone (the flag reads no bound)"
else bad "DW2 [mono0]: rc $rc: $(grep '^error' "$T/dw2m.err" | tr '\n' '|')"; fi
printf 'trait Show { fn show(self): i64; }\ntrait Eq { fn eq(self, o): i64; }\nimpl Show for i64 { fn show(self): i64 { return self; } }\nimpl Eq for i64 { fn eq(self, o): i64 { return 1; } }\nstruct B<T: Show + Eq, U> { a: T; b: U; }\nfn k<T: Show + Eq, U>(t: T, u: U): U { var q: U = u; var a: T[2]; return q + sizeof(T); }\nfn main(): i64 { var b: B<i64, i8>; b.b = 3; return b.b + k(1, 2); }\nsyscall(60, main());\n' > "$T/dw3.cyr"
exits dw3 13 "DW3: <T: Show + Eq, U> — a struct's and a fn's U, T[2] in the body"

# TM — 6.7.17 (the user's D4): a trait member's bounds are looked up (`_tr_tp_bounds`)
printf 'trait T { fn i<U, V: Nope>(self): i64; }\nstruct P { x; }\nfn main(): i64 { return 3; }\nsyscall(60, main());\n' > "$T/tm1.cyr"
TM1="error:<source>:1:22: unknown trait 'Nope' in the bound on type parameter 'V'"
errs tm1 1 "TM1: the filed repro verbatim (it built: exit 3)" "$TM1"
src=0; "$CC" --syntax-only < "$T/tm1.cyr" > /dev/null 2> "$T/tm1.so" || src=$?
if [ "$src" -ne 0 ] && [ "$(grep -c '^error' "$T/tm1.so")" -eq 1 ] && grep -qF "$TM1" "$T/tm1.so"; then ok "TM1: --syntax-only reports it, as the fn's spelling"
else bad "TM1: --syntax-only: rc $src: $(grep '^error' "$T/tm1.so" | tr '\n' '|')"; fi
cat > "$T/tm2.cyr" <<'EOF'
trait Show { fn show(self): i64; }
trait T { fn i<U, V: Nope>(self): i64; fn j<W: Show>(self): i64; fn k<X: 5>(self): i64; fn l<Y: Show<i64>>(self): i64; fn m<Z: Zork>(self): i64 { return 1; } }
struct P { x; }
impl T for P { fn i<U, V: Show>(self): i64 { return 1; } fn j<W: Show>(self): i64 { return 2; } fn k<X: Show>(self): i64 { return 3; } fn l<Y: Show>(self): i64 { return 4; } }
struct Q { a: Foo; }
fn main(): i64 { var y = 1 2; return 3; }
syscall(60, main());
EOF
errs tm2 6 "TM2: an unknown, a malformed, an argument-taking and an inherited default's bound — then the next declaration's and fn's own" \
    "error:<source>:2:22: unknown trait 'Nope' in the bound on type parameter 'V'" "error:<source>:2:74: expected a trait name in a type parameter's bound" \
    "error:<source>:2:97: a trait in a bound takes no type arguments: 'Show'" "error:<source>:2:128: unknown trait 'Zork' in the bound on type parameter 'Z'" \
    "error:<source>:5:15: unknown type 'Foo' for struct field 'a'" "error:<source>:6:28: expected ';', got number 2"
printf 'trait T { fn i<U: Later>(self): i64; }\ntrait Later { fn la(self): i64; }\nstruct P { x; }\nimpl Later for i64 { fn la(self): i64 { return self; } }\nimpl T for P { fn i<U: Later>(self): i64 { return 5; } }\nfn main(): i64 { var p = P { 1 }; return p.i(); }\nsyscall(60, main());\n' > "$T/tm3.cyr"
exits tm3 5 "TM3: a member's bound naming a trait declared below it"
printf 'fn i<U, V: Nope>(u: U): i64 { return 1; }\ntrait T { fn i<U, V: Nope>(self): i64; }\nfn main(): i64 { return i(2) + 2; }\nsyscall(60, main());\n' > "$T/tm4.cyr"
rc=0; CYRIUS_MONOMORPH=0 "$CC" < "$T/tm4.cyr" > "$T/tm4.bin" 2> "$T/tm4.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "TM4: CYRIUS_MONOMORPH=0: rc $rc: $(grep '^error' "$T/tm4.err" | head -1)"
else chmod +x "$T/tm4.bin"; got=0; "$T/tm4.bin" || got=$?
    if [ "$got" -eq 3 ]; then ok "TM4: CYRIUS_MONOMORPH=0 reads no bound — the fn's and the member's spelling alike (exit 3)"; else bad "TM4: exit $got, want 3"; fi
fi

# RB — 6.7.17 (the user's D1): a bounded site on a rebound receiver is no site
RBH='include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
trait Show { fn show(self): i64; }
impl Show for Pt { fn show(self): i64 { return self.x + self.y; } }
impl Show for i64 { fn show(self): i64 { return self + 100; } }
impl Pt { fn other(self): i64 { return 77; } }
fn two(): (i64, i64) { return (1, 2); }'
rb() { printf '%s\n%s\nfn main(): i64 { return 0; }\nsyscall(60, main());\n' "$RBH" "$2" > "$T/$1.cyr"; }
RBM="no struct type in scope for 'x'; a method call needs its struct declaration"
rb rb1 'fn g<T: Show>(x: T): i64 { var f = |x| { return x.other(); }; return fncall1(f, 5); }'
errs rb1 1 "RB1: |x| x.other() — the closure's own x, not a site of g's" "error:<source>:10:56: $RBM"
rb rb2 'fn g<T: Show>(x: T): i64 { var s = 0; for x in 0..2 { s = s + x.other(); } return s; }'
errs rb2 1 "RB2: for x in 0..2 { x.other() } — the loop's own x" "error:<source>:10:70: $RBM"
rb rb3 'fn g<T: Show>(x: T): i64 { var q, x = two(); return x.other() + q; }'
errs rb3 1 "RB3: var q, x = two(); x.other() — the destructure's own x" "error:<source>:10:60: $RBM"
rb rb4 'fn g<T: Show>(b: Box<T>): i64 { var f = |b| { return b.v.other(); }; return fncall1(f, 5); }'
errs rb4 1 "RB4: |b| b.v.other() — the closure's own b, not a carrier's field site" "error:<source>:10:57: no struct type in scope for 'b'; a '.field' access needs its struct declaration"
rb rb5 'fn g<T: Show>(x: T): i64 { var f = |x| { return x.show<i64>(); }; return fncall1(f, 5); }'
errs rb5 1 "RB5: |x| x.show<i64>() — the explicit spelling on the closure's own x" "error:<source>:10:60: $RBM"
rb rbk 'fn g<T: Show>(x: T): i64 { var f = |x| { return x + 1; }; return x.other() + fncall1(f, 1); }'
errs rbk 1 "RBK: g's own x.other() past the closure — the contract's refusal" "error:<source>:10:68: $BDM"

if [ "$fails" -ne 0 ]; then echo "FAIL: trait_bounds_checked — $fails row(s) red"; exit 1; fi
echo "PASS: trait_bounds_checked — bounds checked at the definition (D1-D7), at every instantiation incl. the i64 base, &g, a tail call and an inner generic call (I1-I8), and on generic structs incl. their i64 base (S1-S5); past 64 bounded receivers (B, 6.7.14); a generic forwarding T to a bounded one is bad at i64 alone, named by its forward (F, 6.7.14), at any depth (F13-F15e, 6.7.15); a bounded call on a carrier's T field is a trait use, a scalar T's taking the field's value (BC, 6.7.14), and held to the bound's contract (BD, 6.7.15); a refusal the panic latch swallows prints no orphan note (N, 6.7.14; the contract's too, N2, 6.7.15), and no contract refusal is swallowed (NS, 6.7.16); the explicit spelling v.m<..>(..) is held to the contract and a bound's generic member called so is the bound's call, at a scalar T too, and --syntax-only parses it (BX, BXS, 6.7.16); a Vec element's generic struct held to its bounds (VB, 6.7.15), an argument that is itself an instance judged as by value (VN, 6.7.16); a trait member's bounds looked up with a fn's words (TM, 6.7.17's D4); well-formed bounded code runs (C)"
