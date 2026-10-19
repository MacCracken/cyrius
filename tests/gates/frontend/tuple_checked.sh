#!/bin/sh
# tests/gates/frontend/tuple_checked.sh — 6.7.7 (B4)
#
# TUPLES AS VALUES. The user's decision (2026-10-08): `(a, b)` builds a value laid out as an anonymous
# struct of 8-byte slots; `t.0` / `t.1` read and write it (`OP=` included); `(i64, f64)` is a type
# wherever a struct type goes; `var t: (i64, i64) = f();` captures every value of a multi-value call
# and `a, b = f();` re-assigns existing variables; `var x = f();` keeps its first-value meaning. A
# shape the decision leaves open is refused by name, never given a default meaning.
#
#   L  the lexer: `.` then a digit after an IDENT, `)` or `]` is a selector (IDENT DOT IDENT"0"), and
#      every other `.digit` lexes exactly as before — ranges, floats, `t. 0` with a space
#   S  shapes: S2 a struct with a tuple field (its layout, the neighbours intact); S3 a forward call
#      to a fn declared below with a tuple parameter and a second one (pass 1's parameter scan);
#      S5 `#derive` on a struct with a tuple field is refused by name
#   R  the shapes the decision leaves open, each refused by name (one error line, its fragment):
#      R1 an element outside i64 / f64 / bool; R2 arity and spelling; R3 a type position outside
#      a var / a struct field / a parameter (R3q-R3z, 6.7.11: a `Vec<( .. )>` annotation in every
#      position — the user's decision (a), 2026-10-13); R4 a tuple in a generic fn / struct; R6 an `async fn`
#      tuple parameter; R11 a tuple (or a tuple field) used as a value; R12 a non-tuple source into
#      a tuple place (an argument of another struct or tuple type too); R13 methods; R17 a
#      multi-value call as a tuple argument (`g(f())`: bind it first; R17v / R17w an integer or bool literal
#      or an argument made only of literals and operators, 6.7.14's D44 / 6.7.15's D36); R21 `t.N` spellings
#      that name no element
#   P  positive: the type, `t.N`, copies, fields, parameters — exit codes, values distinguishable
#   T4 — the literal `(a, b)`, accepted in five positions (a `var` initializer in a fn and in either
#      global zone, an assignment to a tuple variable, a tuple field store, a tuple argument, and
#      `return`'s multi-value arm) and refused by name everywhere else:
#      C  compatibility — `(|a, b| ..)` and `(pk<A, B>(..))` stay one value as an initializer and a
#         `return` (PARSE_RETURN's paren-depth comma scan took the two returns for multi-value ones)
#      S1 a wrapped `((a, b))` in every accepting position; S4 a zone literal global's neighbour
#         intact (8n bytes registered in pass 1); K1 `kernel;` parity with a struct literal global
#         (constant elements baked, a call element named late)
#      R2 a literal's shape (trailing comma, empty element, arity, > 256); R4d an un-annotated literal
#         in a generic fn; R5 a tuple in a const context; R7 an un-annotated float element ("declare
#         the tuple's type", the user's decision 2026-10-09); R8 a struct / tuple / u128 / vector /
#         slice element (a `Str` handle and a `*T` are i64s, R8i), an integer into an f64 element
#         warned (R8j); R9 a literal in any other position; R10 a literal assignment / field store /
#         argument at top level (no frame for its temp)
#      PW every `_pwrap_k` caller that can see a literal gives a named outcome, never "expected ')'"
#      AS a literal local in a suspending `async fn`, read and re-assigned across awaits; SEC1
#         `secret var t = ( .. );` wiped whole at the epilogue
#   T5 — the bridge: a tuple CAPTURES a multi-value call by its type (`var t: T = f();`, `t = f();`, `G = f();`,
#      both global zones), `return t;` from a fn declared with its values, and `a, b = f();` re-assigning
#      existing variables (the positive shapes are tuple_values.tcyr's capture / returns / reassign, the A rows):
#      R14 `return t;` from a fn that does not declare those values (S6: an undeclared fn's, refused once), an
#         arity / class mismatch, a closure, an `async fn`, `return h.p;`
#      R15 `f().0` on a multi-value call: the refusal says how to read the values
#      R16 a capture refused: a struct / vector callee, an arity or element-class disagreement, > 3 elements, a
#         `: f64` callee into a non-f64 element, an unchecked callee into a bool element; a one-value callee,
#         `f()?` and a call that is not the whole value are R12 ("not a tuple"); R16cp (6.7.14) `callptr(fp, ..)`
#         captured in every spelling, its callee unknown; R16pw (6.7.14, D45) parentheses around the whole call
#         are transparent (R16l, R16q and R19d were refusals until then)
#      R17i-l a multi-value call stored into a tuple FIELD: bind it first; R17m-r (6.7.15) wrapped, R17 alone
#      R18 `a, b = f()` targets that are no plain variable, > 3, a duplicate, a const / enum constant, a struct /
#         tuple / vector / array / u128 / slice / f32 target, a bool target from a non-bool value, an undefined
#         or captured name; R19 a right-hand side that is not one whole call (the destructure's texts);
#         R20 `(a, b) = f();` / `var (q, r) = f();` unchanged
#      AS2 a capture, a re-capture and `a, q = f()` in a SUSPENDING `async fn` across awaits (CG1: the stores are
#         addressed — the coroutine's heap frame orders an aggregate from its low slot)
#      AS3 (6.7.9) a tuple captured by a closure in a SUSPENDING `async fn`, before and after the await (the capture
#         copy is addressed too; it walked the slots and reversed the words)
#   T6 — generics, const fns, closures (the positive closure and defer shapes are tuple_values.tcyr's `closures` /
#      `defers`; a tuple across an `await` is AS1 - AS3, `return t;` in an `async fn` R14m / R14p, a tuple
#      parameter R6a):
#      R4e-R4q a tuple binding a type parameter by INFERENCE (`first(t)` minted `first$(i64, i64)`): a local, a
#         parameter, a global, either type parameter, a struct-reading or value-using generic body, a capture / a
#         re-capture / a destructure of the call, a tail call, a generic declared below, an #inline replay — each
#         refused once; R4r a struct, an element and a scalar still bind T
#      R5e-R5h a const fn's tuple parameter (used, unused, called in a const, after a `Pair<i64, i64>` one), refused
#         once at its definition; R5i the other const fn parameters untouched
#      CL1-CL2 re-assigning a whole captured tuple is refused, as any captured assignment is (6.7.11: naming the
#      capture, `'t' is captured by value; ..`, not "undefined variable": issues/archived/2026-10-08-struct-operator-results.md #6)
#   CS (6.7.11) — one mistake, one error, at its place (the cascade issue's shapes 1-4 and 8, its repros verbatim)
#   T7 — the tools that read a signature by hand (rows T1 / T2; the CLI and the LSP built from this tree with $CC):
#      T1 `cyrius header` (cbt/quality.cyr cmd_header) cut the parameter list at its FIRST `)` and skipped a type to
#         its first `,`: `fn g(t: (i64, i64), x)` printed `cyr_val g(cyr_val t, cyr_val i64);`. A tuple parameter is
#         one `cyr_val` (it travels as an address) and the parameters after it are kept; T1b with the list
#         read past the first `)`, a malformed one (`fn bad(a (b), c)`) still ends — the walk steps every byte
#      T2 cyrius-lsp's semantic tokens (`_lsp_collect_locals`): a tuple type's `,` reset the walk to "parameter
#         name" and its `)` ended the signature — `i64` / `bool` were coloured as parameters (all through the file:
#         the table is by name) and the parameters after the tuple were not
#   X  `--syntax-only` (cyrius lint's pre-pass): a fn with a tuple parameter, and a call to a
#      sibling file's fn with a tuple argument, report nothing; X4 literals, a sibling's fn given one;
#      X5 sibling targets and callees in captures and `a, b = f()`, `return t;`
#      X6 a tuple given to a generic, a const fn's tuple parameter: silent (lint judges no type); X7 a syntax
#      error after that call in its statement is still reported (the compile's refusal latches; lint must not)
#   I  with B6's default and named arguments (the 6.7.7 integration, b4_plan §9): I1 a tuple parameter beside a
#      defaulted one, filled, named, reordered, and forward; I2 a named tuple-literal argument in a direct call and
#      two tail calls (objdump: both `call`s); I3 / I3b a tuple parameter takes no default; I4 / I4b a named
#      multi-value argument into a tuple parameter: bind it first
#   A  tests/tcyr/crossos/tuple_values.tcyr with its full assertion count (derived from the source)
#      on x86 (default, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm), PE
#      (wine, a private prefix). A leg whose tool is missing is a SKIP that names it (exit 77).
#   B4 review (2026-10-09):
#      ZG the declaration zone's pass 1 reads `name<..>(` by its tokens (a generic declared below): ZG1 / ZG2 one
#         value, ZG3 a wrapped one-value call refused (it stored one word), ZG4 (6.7.14, D45) a wrapped multi-value
#         call captured (it stored one word, then was refused until 6.7.14), ZG5 / ZG6 a literal holding one is
#         `(i64, i64)`, ZG7 / ZG8 a capture of one; ZG9 a non-tuple annotation registers no tuple; ZG10 / ZG11 a
#         `<` comparison spelled like a type list refused by name where the two readings disagree
#      R8k-R8p a `: stack` pair as a literal element (a one-slot store, T5b's rule): refused; `f(x)?` consumes it
#      R9n / R9s / PW5 / PW7 a literal just inside `return`'s own parentheses names the return's spelling; R9t a
#         nested element there keeps the general text
#      R14q / R14r `return t;` of 4 or more elements: no fn declares them (the advice was a second refusal)
#      R19i-R19o `a, b = f();` from a struct- or vector-returning callee (24 B, 16 B, a method, a vector, an explicit
#         generic, a for step) refused by name, as the capture refuses it; R19m the aarch64 compiler too (A5 leg)
#
# MUTATION LEDGER (2026-10-09; each a one-edit scratch COPY of the tree, its compiler rebuilt from the
# mutated src, then this gate run with CYCC= the mutant):
#   M1  `_lex_dot` without the previous-token guard (every `.digit` a selector) -> L1 (a range's
#       `..10` lexes DOT IDENT"10": "undefined variable '10'"). L2's shapes never reach the guard
#       (`1.5` is one LEXNUM token; `1.0.5`'s refusal names the `.` either way). The same mutant
#       compiles 8 tree files differently from the base compiler (ranges in crossos tcyrs).
#   M1b the guard without `)` (11)                                               -> L3c
# THE EVIDENCE BEYOND THESE ROWS (T1, 2026-10-09): every .cyr / .tcyr / .fcyr / .bcyr in the tree
# (1051 files, default and CYRIUS_DCE=1) compiles byte-identical — stdout, stderr and exit code —
# with the T1 compiler and the base build/cycc (e44470b7); the aarch64, cx and PE
# (CYRIUS_TARGET_WIN=1) compilers likewise over tests/tcyr/crossos/. No program that compiled before
# lexes differently.
# T2 (2026-10-09; the same recipe; each mutant measured RED, the real tree 101/101):
#   M2  no `_sdef_tup_prescan` (PARSE_STRUCT_DEF)  -> 16 rows: S2, P2, P3, every struct-field R row
#       (R4b R11m R11n R11q R12j-R12l R13d) and A1-A4 / A7 — "internal error: a tuple field type was
#       not interned before its struct" (the field arm's lookup misses; it never REGSTRUCTs mid-definition)
#   M10b the pointer-mode backstop removed (`_tup_ptr_refuse` returns 0) -> R12e-R12i BUILD (a tuple
#       declared from a value took one word into a pointer-mode slot). (The plan's M10 is T5's
#       `_ret_tuple_var` mutation; this bite owns M10b, which T2 makes a refusal with rows.)
#   M11 `_tup_rchk` removed (PARSE_FACTOR)         -> R11a-l and R11o-r RED (BUILT, or a stray
#       `(i64, i64)_add` undefined-function / if-expression error); R11m / R11n stay green — the field
#       form is `_tup_fld_rchk`'s, at the load
#   M16 the element vocabulary check removed      -> R1a R1b R1d R1h R1i BUILD (every name an i64)
#   M17 the generic refusals removed (`_tup_gen_chk`, the prescan's) -> R4a R4b BUILD
#   M18 the `#derive` refusal removed (`PP_DTUP`) -> S5 BUILDS (every field after `t` silently loses
#       its derived code)
#   M13d `_tup_meth_chk` without its digit arm    -> R13e-R13i RED (`p.0()` calls `P_0`)
# THE EVIDENCE BEYOND THESE ROWS (T2, 2026-10-09): the same 1051 files compile byte-identical —
# stdout, stderr and exit code, default and CYRIUS_DCE=1 — with the T2 compiler and the T1 one, and
# the aarch64, cx and PE compilers likewise over all 537 pre-existing tests/tcyr files. No program
# that compiled before T2 compiles differently.
# T3 (2026-10-09; the same recipe; each mutant measured RED, the real tree 120/120):
#   M3  no pass-1 parameter arm (`_prescan_params_scan` without `_tup_pscan`) -> S3 and A1-A4 / A7
#       (a forward call counted one parameter with no struct-mask bit: the tuple was read as a value)
#   M14 no `g(f())` refusal (`_tup_arg_call` dropped) -> R17a-R17f BUILD; R17a's binary exits 139 (the
#       first value pushed as the tuple's address)
#   M14b no method / operator refusal (`_tup_arg_mrc` dropped) -> R17g, R17h BUILD; both binaries exit 139
#   Mbv pass 1 records no prologue copy (`_tup_bvcp` a no-op) -> A1-A4 / A7: tuple_values' "after an earlier
#       call to a copying callee declared below: kept" (the tail call diverted for nothing)
#   Masy the `async fn` tuple branch dropped -> R6a: the struct message, advising `t: *(i64, i64)`
# THE EVIDENCE BEYOND THESE ROWS (T3, 2026-10-09): every .cyr / .tcyr / .fcyr / .bcyr in src lib programs cbt
# tests benches fuzz bootstrap docs/development/issues but tuple_values.tcyr (1034 files) compiles byte-identical —
# stdout, stderr and exit code; default, CYRIUS_DCE=1 and --syntax-only — with the T3 compiler and the T2 one, and
# the aarch64, cx and PE compilers likewise over all 537 other tests/tcyr files.
# T4 (2026-10-09; the same recipe, run FROM the scratch copy so its cross legs build from the mutated
# src too; each mutant measured RED, the real tree 187/187):
#   M4  no zone fold (`_gci_inline` without `_tup_gci`) -> S1, S4, K1, R10a and A1-A7 (pass 1 registered
#       an 8-byte pointer-mode slot: "cannot initialize tuple 'G' with a value that is not a tuple")
#   M5  no literal arm before the unwraps (`_tup_asg` in `_try_aggregate_copy_assign`, `_tup_sarg_lit` in
#       `_sarg_paren`) -> S1, R2j, R2k, R9c, R9k, R10a, R10b, PW1 / PW3 ("expected ')'" or the value
#       refusal), AS1, X4 and A1-A7
#   M6  the literal argument without `_sarg_escapes` -> A1-A7: the tailcalls rows (the `jmp` kept: same
#       depth, and the temp read from the freed frame, 52 where 60 is right)
#   M7a the local literal's span recorded LAST (after its stores) -> AS1 (the coroutine frame splits it)
#   M7b the local / temp element stores through EFLSTORE -> AS1 and A3 (CYRIUS_IR=3: the swap reads 0)
#   M12 a non-tuple annotation's literal taken as `(i64 x n)` -> R9d-R9g, PW4 (BUILT, or a cascade). The
#       plan's M12 shape (`var t: T = 5;` built) is T2's M10b, the pointer-mode refusal, already measured.
#   M20 `_tup_lit_stray` removed -> R8g, R9a, R9b, R9d-R9i, R9l-R9n, R9p-R9r, PW4, PW5, PW7-PW9, X4
#       ("expected ')', got ','", or a second error after the named one)
#   M21 `_tup_commas` without the closure / generic steps (`_tok_item_end` alone) -> C1-C4
# THE EVIDENCE BEYOND THESE ROWS (T4, 2026-10-09): every .cyr / .tcyr / .fcyr / .bcyr in src lib programs cbt
# tests benches fuzz bootstrap docs/development/issues but tuple_values.tcyr (1034 files) compiles byte-identical —
# stdout, stderr and exit code; default, CYRIUS_DCE=1 and --syntax-only — with the T4 compiler and the T3 one, and
# the aarch64, cx and PE compilers likewise over all 537 other tests/tcyr files.
# T5 (2026-10-09; the same recipe, run FROM the scratch copy; each mutant measured RED, the real tree 269/269 —
# the crossos file at 168 assertions):
#   M8a the drain stores in push order (slot k takes the value pushed k-th from the top) -> AS2 and A1-A7 (`(5, 9)`
#       captured as 95, arity 3 as 321)
#   M8b arity 3 without `EMOVRA_R3` (the third value is rdx's again) -> AS2 and A1-A7 (122 where 123 is right, in a
#       capture, a zone capture and `a, b, c = f()`)
#   M8c (CG1) a local capture's slots stored through EFLSTORE, not addressed -> AS2 (the coroutine frame's word order;
#       the stack frame's and IR=3's happen to agree)
#   M9  no `_ret_tuple_var` -> R14a-c, R14f-j, R14l, R14m, R14o, R14p (the value refusal instead) and A1-A7 (the
#       file does not build); R14d gives two errors
#   M10 `return t;` loads slot 1 into rax and slot 0 into rdx -> A1-A7 (`return t;` 95 where 59 is right)
#   M10b the pointer-mode backstop removed (`_tup_ptr_refuse` returns 0) -> R12e-i and R16k-o BUILD (the capture
#       declines those right-hand sides to it)
#   M13 no `_tup_asg` call arm -> R16p, R16w, AS2 and A1-A7 (`t = f();` is "not a tuple"; a `: stack` pair "bind both")
#   M15 `_masg_stmt` without `_dt_arity_check` (since the review, in `_masg_callee`) -> R19f, R19g BUILD
#   M19 the capture's class check removed (`_tup_cap_class` -> 1) -> R16a-k, R16p, R16r-t, R16v, R16w, R12c, R12g BUILD
#   M22 PARSE_FIELD_STORE's first-target `,` refusal removed -> R18a, R18d ("expected '=', got ','")
#   M23 `_masg_stmt` reads its targets back from `_masg_ix` AFTER the call -> A1-A7 (a multi-value assignment in a
#       closure among the arguments re-used the table: the outer stores went to the closure's slots, 26 where 813)
#   (`_ret_tuple_var` runs for every `return`: its wrap scan is one linear pass. A `_pwrap_k` peel there was
#   quadratic in the depth — tests/gates/diagnostics/recursion_depth_bounded.sh's `nested parens @ 65536`
#   timed out, 99 s — and that row is the guard.)
# THE EVIDENCE BEYOND THESE ROWS (T5, 2026-10-09): the same 1034 files compile byte-identical — stdout, stderr and exit
# code; default, CYRIUS_DCE=1 and --syntax-only — with the T5 compiler and the T4 one, and the aarch64, cx and PE
# compilers likewise over all 537 other tests/tcyr files.
# T6 (2026-10-09; the same recipe, run FROM the scratch copy; each mutant measured RED, the real tree 292/292 — the
# crossos file at 191 assertions):
#   M17i `_gen_infer_tp` without its tuple check (the plan's M17: `first(t)` builds) -> R4e-R4j, R4n-R4q BUILD (each
#       minted a `$(i64, i64)` instance); R4k / R4l / R4m refused by another message (the instance's body, the capture)
#   M17p `_gen_tup_bind` without the panic latch -> R4i, R4j, R4l, R4m (a second error: the other argument, the stub
#       base's refusal, the capture's / assignment's decline)
#   M17r `_tup_cap_check` without its recovery (a refused callee's capture judged anyway) -> R4l (the base's one value
#       declined: the tuple undeclared, `u.0` "no struct type in scope for 'u'")
#   M17s `_gen_tup_bind` without its `--syntax-only` guard -> X7 (lint's pre-pass latched the statement: the syntax
#       error after the call went unreported)
#   M5t `_ce_check_fn` without `_ce_tup_param` -> R5e ("expected ';', got '.'"), R5f-R5h BUILD
#   M5w `_ce_tup_param` reading only the first parameter -> R5h BUILDS
# THE EVIDENCE BEYOND THESE ROWS (T6, 2026-10-09): the same 1034 files compile byte-identical — stdout, stderr and exit
# code; default, CYRIUS_DCE=1 and --syntax-only — with the T6 compiler and the T5b one, and the aarch64, cx and PE
# compilers likewise over all 538 tests/tcyr files (tuple_values.tcyr's new sections included: T6 adds refusals only).
# T7 (2026-10-09; the same recipe, run FROM the scratch copy — the rows build the CLI and the LSP from its cbt/ and
# programs/; each mutant measured RED, the real tree 295/295):
#   MT1a cmd_header's list end back to the first `)`   -> T1 (`g(cyr_val t)`: the parameters after the tuple lost)
#   MT1b the parameter skip back to the first `,`       -> T1 (`g(cyr_val t, cyr_val i64, cyr_val x)`)
#   MT1c the skip only after a `:` (the old guard)       -> T1b (a `)` the name scan stops at is never stepped: the
#        walk never ends, timeout)
#   MT2a `_lsp_collect_locals` never counts a `(` in a type -> T2 (`i64` / `bool` parameters, `u` / `z` lost)
#   MT2b its `,` resets to "param name" at any depth    -> T2 (the same)
#   MT2c its `)` ends the signature at any depth        -> T2 (`u` / `z` lost)
# T7 changes no src/: the compiler is T6's, byte for byte.
# B4 REVIEW (2026-10-09; the same recipe — a scratch copy of src/ + lib/, its compiler built with build/cycc, this
# gate run with CYCC= the mutant; the cross legs build from the real tree; each mutant measured RED, the real tree
# green):
#   Mz1 `_tup_gopen` always `_gcall_open` (no pass-1 token reading) -> ZG1, ZG5-ZG8, ZG10, ZG11 and A1-A4 / A7
#       (TV_C2 "not a tuple"); ZG2-ZG4 are held by Mz2's annotation test and `_gvi_tup_odd`
#   Mz2 `_tup_gci_in` without its annotation test -> ZG9 (`var G: i64 = (1, 2);` registered a tuple: a second
#       error, "tuple 'G' used as a value", at `G + H`)
#   Mz3 `_gvi_tup_odd` returns 0 -> ZG11 (the replay's value path: "expected ';', got '>'")
#   Mz4 `_gvi_tup_slot` returns 1 -> ZG10 BUILDS (three elements stored into the two pass 1 registered)
#   Mz5 `_tup_elem_val` without `_refuse_lossy_pair` -> R8k-R8o BUILD
#   Mz6 `_masg_callee` without its struct / vector arms -> R19i-R19l, R19n, R19o BUILD
#   Mz7 `_tup_ret_wrap` returns 0 -> R9n, R9s, PW5, PW7 (the general text)
#   Mz7b `_tup_ret_wrap` without its `_pwrap_k` test (any literal right after `return (`) -> R9t (the return text)
#   Mz8 `_ret_tup_err` without its arity arm -> R14q, R14r (the declaration advice)
#   Mz9 (6.7.13) `_tup_elem_val` without its `_ess_deref` arm -> R8s-R8x BUILD, R8z BUILT
# 6.7.7 INTEGRATION (B4 x B6, 2026-10-09; the same recipe, mutants of the merged src/; the I rows and the tcyr on x86):
#   MI1 `_prescan_params_scan`'s tuple arm and its non-name type arm two `if`s again (the hunk-picked merge) ->
#       I1, I2, I4, I4b (pass 1 counts `t: (i64, i64), k` as one parameter: B6's two-pass backstop), the tcyr
#       (`tv_later`: "expects 1 argument, got 2")
#   MI2 `_pd_call_fills` without its named-call line (a full-arity named tail call reaches the tail arm) -> I2,
#       I4b ("undefined variable" at the label), the tcyr
#   MI3 `_ce_factor`'s tuple-literal arm never taken -> I3 ("expected ')', got ','")
#   MI3b `_pd_pclass` without its `(` arm -> I3b BUILDS (a tuple parameter given the default 0)
#   MI4 `_pd_arg_at` pushes the bare value, bypassing `_call_arg_one`'s gates (b4_plan H19) -> I1 (a named
#       tuple variable "used as a value"), I2 (a named literal refused as a stray), I4 / I4b BUILD, the tcyr
# 6.7.8 REPAIR (the dyn lane; a scratch copy, its compiler rebuilt, this gate run with CYCC= the mutant):
#   MR4 `_tok_enclosing_fn` (extracted from `_tup_gen_chk`) without its `;` / `}` stop -> R4s, R4t ("a tuple
#       type in a generic fn": the scan ran past a bodyless generic trait member to the next `{`)
# 6.7.11 REPAIR 1 (the returns lane; the same recipe):
#   MRL `_body_ends_in_loop` returns 0 -> R16x BUILDS (a callee ending in `loop { return x; }` captured a stale rdx)
#   (6.7.13) `_cond_is_one` without its `true` arm -> R16x-true BUILDS
#   MRA `_prescan_ret_arity` records nothing -> R16y-R16ab BUILD; MRC `_tup_cap_class` without its count arm ->
#       R16y-R16ab BUILD
#   MRP `_mret_ret_check` answering 0 -> R16ad BUILDS; MRL2 its late report not yielding to the arms' own refusal ->
#       R9n, R9s, R9t, R14n give two errors; MRT its tuple-local arm dropped -> A1-A4, A7 (tuple_values.tcyr's
#       `return t;` refused)
#   (the cascades, CS; each mutant built from a scratch copy of src/, this gate run with CYCC= it)
#   MCS1 `_tup_rv_chain` answering 0 -> CS1, CS1b, CS1c (a report per operand)
#   MCS2 `_asg_capture_refused` answering 0 -> CS2 (`u` "used as a value" too, the caret on the `;`), CS2b (the caret)
#   MCS3a `_tup_asg_chk` not marking its refusal -> CS3 (the typed-pointer warning on `t = 5;`); MCS3b `_ptr_annot` not
#       marking a refused `*( .. )` -> CS3, CS3b (the warning on `= 0`)
#   MCS4a `_tup_var_refd` declaring nothing -> CS4, CS4b, CS4c, CS4d ("undefined variable" / "no struct type" at each
#       use); MCS4b `_tup_gci_in` registering no tuple over 256 -> CS4e (the use's error printed before the refusal)
#   MCS8 `_tup_svtype_p1` reporting in pass 1 -> CS8, CS8c (R12 first, then the real cause); MCS8b `_gvi_tup_late`
#       saying nothing -> CS8b BUILDS (the replay's report is what refuses a scalar declared below)
# 6.7.11 REPAIR 1 (the genfe lane, unit G4; a one-edit copy of src/, its compiler built by the fixed one, this gate
# run with CYCC= the mutant; issues/archived/2026-10-09-vec-annotation-type-argument-unchecked.md):
#   MV1 `_vec_ann_chk` returning at once (every `Vec<..>` annotation unread again) -> R3q-R3z BUILD
#   MV2 `_vec_ann_list` without its nested-`Vec` arm (a nested `<..>` skipped) -> R3w BUILDS
#   MV3 `_param_type_step` without its check -> R3t, R3v BUILD; MV4 `_pty_name` without it -> R3v2 BUILDS
#   MV7 `_gen_ann_sid` without its check -> R3q, R3r, R3s, R3w, R3x, R3z BUILD (the `*Vec` / parameter rows stay red)
# 6.7.13 REPAIR 3 (the multivalue lane, unit M1; a one-edit copy of src/, its compiler built by the fixed one, this gate
# run with CYCC= the mutant; issues/archived/2026-10-14-undeclared-multi-value-call-into-tuple-parameter-crashes.md):
#   MU1 `_tup_arg_call` back to the declared-only guard (`GFRS != MULTIRET_SID`) -> R17u1, R17u3 BUILD
#   MU2 `_tup_arg_mrc` back to the declared-only guard -> R17u2 BUILDS
# Defensive, no killing row (named): `_tok_start` set to the digit before LEXID — today every
# diagnostic at a selector points at the token AFTER it, so the IDENT's own offset is not observed;
# the guard's `]` (29) — no valid program today follows a subscript with `.field`, so `a[1].0` is
# "expected ';', got '.'" with or without it.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: tuple_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: tuple_checked: mktemp -d failed"; exit 1; }
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
P='struct P { a; b; }\n'
# 6.7.14 — ROWS ON EVERY TARGET: `refused4` / `exits4` compile (and run) a row on x86_64, aarch64 (cross; qemu),
# cx (cxvm) and PE (CYRIUS_TARGET_WIN=1; wine, the private prefix), the cross compilers built from this tree by
# $CC on first use. A missing tool is a SKIP that names it.
X4=0
X4L="x86_64 pe"
_x4_init() {
    [ "$X4" -eq 1 ] && return 0
    X4=1
    if command -v qemu-aarch64 > /dev/null 2>&1; then
        if "$CC" < src/main_aarch64.cyr > "$T/x4_a64" 2> /dev/null && [ -s "$T/x4_a64" ]; then chmod +x "$T/x4_a64"; X4L="$X4L aarch64"
        else bad "the 4-leg rows: src/main_aarch64.cyr did not build"; fi
    else echo "  SKIP the 4-leg rows' aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
    if "$CC" < src/main_cx.cyr > "$T/x4_cx" 2> /dev/null && [ -s "$T/x4_cx" ] && "$CC" < programs/cxvm.cyr > "$T/x4_vm" 2> /dev/null && [ -s "$T/x4_vm" ]; then
        chmod +x "$T/x4_cx" "$T/x4_vm"; X4L="$X4L cx"
    else bad "the 4-leg rows: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
    X4W=0
    if command -v wine > /dev/null 2>&1; then X4W=1
    else echo "  SKIP the 4-leg rows' PE run leg — wine not installed (the PE refusals still run)"; skips=$((skips + 1)); fi
}
_x4_cc() {   # <leg> <name>: $T/<name>.<leg> (+ .<leg>.err); rc in $rc
    rc=0
    case $1 in
        x86_64)  timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || rc=$? ;;
        aarch64) timeout 60 "$T/x4_a64" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || rc=$? ;;
        cx)      timeout 60 "$T/x4_cx" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || rc=$? ;;
        pe)      CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || rc=$? ;;
    esac
}
refused4() {   # <name> <message fragment> <what> <source>: refused once on every leg, no binary
    _x4_init
    printf '%b' "$4" > "$T/$1.cyr"
    for leg in $X4L; do
        _x4_cc "$leg" "$1"
        n=$(grep -c '^error' "$T/$1.$leg.err")
        if [ "$rc" -eq 0 ]; then bad "$3 ($leg): BUILT (rc 0)"
        elif ! grep -qF "$2" "$T/$1.$leg.err"; then bad "$3 ($leg): refused, but not as expected: $(grep '^error' "$T/$1.$leg.err" | head -1)"
        elif [ "$n" -ne 1 ]; then bad "$3 ($leg): $n error lines (want 1): $(grep '^error' "$T/$1.$leg.err" | head -2 | tr '\n' '|')"
        elif [ -s "$T/$1.$leg" ]; then bad "$3 ($leg): refused, but a binary was written"
        else ok "$3 ($leg): refused once"; fi
    done
}
exits4() {   # <name> <want> <what> <source>: compiles and exits <want> on every leg
    _x4_init
    printf '%b' "$4" > "$T/$1.cyr"
    for leg in $X4L; do
        _x4_cc "$leg" "$1"
        if [ "$rc" -ne 0 ] || [ ! -s "$T/$1.$leg" ]; then bad "$3 ($leg): rc $rc: $(grep '^error' "$T/$1.$leg.err" | head -1)"; continue; fi
        chmod +x "$T/$1.$leg"; got=0
        case $leg in
            x86_64)  timeout 10 "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            aarch64) timeout 60 qemu-aarch64 "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            cx)      timeout 60 "$T/x4_vm" < "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            pe)      [ "$X4W" -eq 1 ] || continue
                     mkdir -p "$WHM"; cp "$T/$1.$leg" "$T/$1.exe"
                     (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                         WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$1.exe" > /dev/null 2>&1) || got=$? ;;
        esac
        if [ "$got" -eq "$2" ]; then ok "$3 ($leg): exit $got"; else bad "$3 ($leg): exit $got, want $2"; fi
    done
}

# ── L: the lexer ─────────────────────────────────────────────────────────────────────────────────
# L1: every range whose upper bound is a digit run — after a number, an IDENT, `)` and `]`. Its second
# `.` follows a DOT token, so the selector guard never fires on it.
exits l01 250 "L1: ranges \`0..10\`, \`a..5\`, \`a..hi\`, \`g(4)..6\`, \`arr[0]..5\` intact" 'fn g(x): i64 { return x; }\nfn f(c): i64 {\n    var s = 0;\n    var a = 2;\n    var hi = 6;\n    var arr: i64[2];\n    arr[0] = 3;\n    for i in 0..10 { s = s + 1; }\n    for i in a..5 { s = s + 10; }\n    for i in a..hi { s = s + 20; }\n    for i in g(4)..6 { s = s + 40; }\n    for i in arr[0]..5 { s = s + 25; }\n    return s;\n}\nsyscall(60, f(1));\n'
exits l02 3 "L2: \`1.5\` / \`0.25\` are still float literals (their binary64 bits)" 'var x = 1.5;\nvar y = 0.25;\nsyscall(60, (x == 0x3FF8000000000000) + (y == 0x3FD0000000000000) * 2);\n'
refused l02b "expected ';', got '.'" "L2b: \`1.0.5\` is still a float then a stray \`.\`" 'fn f(): i64 { var y = 1.0.5; return 0; }\nsyscall(60, f());\n'
refused l03 "unknown field '0' on struct 'P'" "L3: \`p.0\` on a named struct is a field selector" "${P}fn f(): i64 { var p: P; p.a = 1; return p.0; }\nsyscall(60, f());\n"
refused l03b "unknown field '0x1' on struct 'P'" "L3b: \`p.0x1\` is ONE selector (the whole alnum run), not a hex number" "${P}fn f(): i64 { var p: P; return p.0x1; }\nsyscall(60, f());\n"
refused l03c "unknown field '0' on struct 'P'" "L3c: after \`)\` too — \`mk().0\` (was \"expected ';', got '.'\")" "${P}fn mk(): P { var p: P; p.a = 1; p.b = 2; return p; }\nfn f(): i64 { return mk().0; }\nsyscall(60, f());\n"
refused l04 "unknown field '0' on struct 'P'" "L4: \`p.0.1\` is two selectors (the error names '0', not a float 0.1)" "${P}fn f(): i64 { var p: P; return p.0.1; }\nsyscall(60, f());\n"
# L4b: `--syntax-only` (what `cyrius lint` runs) reads `p.0.1` as a selector chain, exactly as `p.a.b`.
printf 'fn f(p): i64 { return p.0.1 + p.a.b; }\nsyscall(60, f(0));\n' > "$T/l04b.cyr"
rc=0; "$CC" --syntax-only < "$T/l04b.cyr" > /dev/null 2> "$T/l04b.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$T/l04b.err"; then ok "L4b: --syntax-only reads \`p.0.1\` as a chain, as \`p.a.b\`"
else bad "L4b: --syntax-only rc $rc: $(grep '^error' "$T/l04b.err" | head -1)"; fi
refused l05 "expected identifier, got number 0" "L5: \`p. 0\` (a space) is still a number, not a selector" "${P}fn f(): i64 { var p: P; return p. 0; }\nsyscall(60, f());\n"

# ── S: shapes ──────────────────────────────────────────────────────────────────────────────────────
TH='struct H { a; p: (i64, i64); b; }\n'
exits s02 47 "S2: \`struct H { a; p: (i64, i64); b; }\` is 32 bytes, and \`b\` is intact after \`p.1\` is written" "${TH}fn f(): i64 {\n    var h: H;\n    h.a = 1;\n    h.b = 7;\n    h.p.0 = 3;\n    h.p.1 = 9;\n    if (sizeof(H) != 32) { return 99; }\n    return h.b * 10 - h.p.1 - h.a * 14;\n}\nsyscall(60, f());\n"
# S3: a forward call to a fn declared BELOW with a tuple parameter and then a second one. Pass 1's
# parameter scan stopped at the `(`: one parameter counted, no struct-mask bit — the call was refused
# ("expects 1 argument") or, with the arity right, pushed the tuple's first word as its address.
exits s03 64 "S3: \`later(t, 1000)\` before \`fn later(t: (i64, i64), k)\` (pass 1 scans the tuple parameter)" 'fn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 5;\n    t.1 = 9;\n    var r = later(t, 1000);\n    return r - 1000 + t.0;\n}\nfn later(t: (i64, i64), k): i64 {\n    t.0 = t.0 + 100;\n    return t.0 * 10 + t.1 + k;\n}\nsyscall(60, f() - 1000);\n'
refused s05 "#derive reads named field types; 't' is a tuple (in the declaration of D)" "S5: \`#derive\` on a struct with a tuple field (it silently dropped every later field's code)" '#derive(accessors)\nstruct D { a; t: (i64, i64); b; }\nfn f(): i64 { var d: D; d.a = 3; return d.a; }\nsyscall(60, f());\n'

# ── R1: the element vocabulary is i64 / f64 / bool ─────────────────────────────────────────────────
V='fn f(): i64 {\n    var t: '
W=';\n    return 0;\n}\nsyscall(60, f());\n'
refused r01a "a tuple element is i64, f64 or bool, not 'i32'" "R1a: \`(i32, i64)\` (narrow integers: 6.7.8's B7)" "${V}(i32, i64)${W}"
refused r01b "a tuple element is i64, f64 or bool, not 'u64'" "R1b: \`(u64, i64)\`" "${V}(u64, i64)${W}"
refused r01c "a tuple element is i64, f64 or bool, not a pointer" "R1c: \`(*i64, i64)\`" "${V}(*i64, i64)${W}"
refused r01d "a tuple element is i64, f64 or bool, not struct 'P'" "R1d: \`(P, i64)\`, a struct element" "${P}${V}(P, i64)${W}"
refused r01e "a tuple element is i64, f64 or bool, not a nested tuple" "R1e: \`((i64, i64), i64)\`" "${V}((i64, i64), i64)${W}"
refused r01f "a tuple element is i64, f64 or bool, not u128" "R1f: \`(u128, i64)\`" "${V}(u128, i64)${W}"
refused r01g "a tuple element is i64, f64 or bool, not a slice" "R1g: \`([u8], i64)\`" "${V}([u8], i64)${W}"
refused r01h "unknown type 'Nope' as a tuple element" "R1h: an unknown name" "${V}(Nope, i64)${W}"
refused r01i "a tuple element is i64, f64 or bool, not 'f32'" "R1i: \`(f32, i64)\`" "${V}(f32, i64)${W}"
refused r01j "a tuple element is i64, f64 or bool, not 'i32'" "R1j: a parameter \`t: (i32, i64)\`" 'fn g(t: (i32, i64)): i64 { return 1; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'

# ── R2: arity and spelling ─────────────────────────────────────────────────────────────────────────
refused r02a "a tuple type has 2 or more elements - \`()\` is empty" "R2a: \`()\`" "${V}()${W}"
refused r02b "a tuple type has 2 or more elements - write the one type without parentheses" "R2b: \`(i64)\`" "${V}(i64)${W}"
refused r02c "a trailing comma in a tuple type" "R2c: \`(i64, i64,)\`" "${V}(i64, i64,)${W}"
refused r02d "a trailing comma in a tuple type" "R2d: \`(i64,)\` (one error, not two)" "${V}(i64,)${W}"
refused r02e "an empty element in a tuple type" "R2e: \`(i64, , i64)\`" "${V}(i64, , i64)${W}"

# ── R3: type positions the decision leaves open ────────────────────────────────────────────────────
refused r03a "a tuple type cannot be a pointer target" "R3a: \`*(i64, i64)\`" 'fn f(): i64 {\n    var p: *(i64, i64) = 0;\n    return 3;\n}\nsyscall(60, f());\n'
refused r03b "a tuple type cannot be a slice element" "R3b: \`[(i64, i64)]\`" 'fn f(): i64 {\n    var s: [(i64, i64)] = 0;\n    return 3;\n}\nsyscall(60, f());\n'
refused r03c "a tuple type cannot be a slice element" "R3c: \`slice<(i64, i64)>\`" 'fn f(): i64 {\n    var s: slice<(i64, i64)> = 0;\n    return 3;\n}\nsyscall(60, f());\n'
refused r03d "a tuple type cannot be an array element" "R3d: \`(i64, i64)[4]\`, a local" "${V}(i64, i64)[4]${W}"
refused r03e "a tuple type cannot be an array element" "R3e: \`(i64, i64)[4]\`, a declaration-zone global" 'var G: (i64, i64)[4];\nsyscall(60, 3);\n'
refused r03f "a tuple type cannot be a sizeof operand" "R3f: \`sizeof((i64, i64))\`" 'fn f(): i64 { return sizeof((i64, i64)); }\nsyscall(60, f());\n'
refused r03g "a tuple type cannot be a sizeof operand" "R3g: \`#assert sizeof((i64, i64))\` (no \"#assert failed\" after it)" 'fn f(): i64 {\n    #assert sizeof((i64, i64)) == 16, "x"\n    return 3;\n}\nsyscall(60, f());\n'
refused r03h "a tuple type cannot be a type argument" "R3h: \`B<(i64, i64)>\` (it said \"unknown type 'struct'\")" 'struct B<T> { v: T; }\nfn f(): i64 { var b: B<(i64, i64)>; return 3; }\nsyscall(60, f());\n'
refused r03i "a tuple type cannot be a type argument" "R3i: \`id<(i64, i64)>(3)\` (it said \"undefined variable 'id'\")" 'fn id<T>(x: T): T { return x; }\nfn f(): i64 { return id<(i64, i64)>(3); }\nsyscall(60, f());\n'
refused r03j "union field 't' cannot be a tuple" "R3j: a union field" 'union U { a; t: (i64, i64); }\nfn f(): i64 { var u: U; u.a = 3; return u.a; }\nsyscall(60, f());\n'
refused r03k "a tuple has no methods - \`impl\` on a tuple type is refused" "R3k: \`impl (i64, i64) {\`" 'impl (i64, i64) {\n    fn m(self): i64 { return 1; }\n}\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r03l "a tuple has no methods - \`impl\` on a tuple type is refused" "R3l: \`impl Tr for (i64, i64) {\`" 'trait Tr { fn m(self): i64; }\nimpl Tr for (i64, i64) {\n    fn m(self): i64 { return 1; }\n}\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r03m "a tuple type cannot be a multi-value return element" "R3m: \`fn g(): ((i64, i64), i64)\`" 'fn g(): ((i64, i64), i64) { return (1, 2); }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r03n "a tuple in a const fn" "R3n: a tuple local in a const fn's evaluation" 'const fn cf(x: i64): i64 {\n    var t: (i64, i64);\n    return x;\n}\nconst C = cf(3);\nsyscall(60, C);\n'
refused r03o "a tuple type cannot be a Vec element" "R3o: a \`Vec<(i64, i64)>\` struct field (it said \"expected identifier\")" 'struct W { v: Vec<(i64, i64)>; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r03p "a tuple type cannot be a pointer target" "R3p: a parameter \`t: *(i64, i64)\`" 'fn g(t: *(i64, i64)): i64 { return 1; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
# R3q-R3z (6.7.11) — a `Vec<( .. )>` ANNOTATION, refused as the field form (R3o) refuses it: the user's
# decision (a), 2026-10-13 — a `Vec<T>` annotation reads its T. Each compiled through 6.7.10 (its `<..>`
# skipped unread). One error each, the generic fn's over its base and two instances too.
VTE="a tuple type cannot be a Vec element"
refused r03q "$VTE" "R3q: a local \`var v: Vec<(i64, i64)>\`" 'fn f(): i64 {\n    var v: Vec<(i64, i64)> = 0;\n    return 3;\n}\nsyscall(60, f());\n'
refused r03r "$VTE" "R3r: a declaration-zone global" 'var G: Vec<(i64, i64)> = 0;\nfn f(): i64 { return G; }\nsyscall(60, f());\n'
refused r03s "$VTE" "R3s: a global after the first statement" 'fn f(): i64 { return 3; }\nf();\nvar G: Vec<(i64, i64)> = 0;\nsyscall(60, G);\n'
refused r03t "$VTE" "R3t: a parameter, called above its definition (pass 1 counts 2: no arity error)" 'fn f(): i64 { return g(0, 3); }\nfn g(v: Vec<(i64, i64)>, b): i64 { return b; }\nsyscall(60, f());\n'
refused r03u "$VTE" "R3u: a \`*Vec<(i64, i64)>\` local" 'fn f(): i64 {\n    var b = 0;\n    var p: *Vec<(i64, i64)> = &b;\n    return 3;\n}\nsyscall(60, f());\n'
refused r03v "$VTE" "R3v: a \`p: *Vec<(i64, i64)>\` parameter" 'fn g(p: *Vec<(i64, i64)>): i64 { return 1; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r03v2 "$VTE" "R3v2: a \`p: **Vec<(i64, i64)>\` parameter" 'fn g(p: **Vec<(i64, i64)>): i64 { return 1; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r03w "$VTE" "R3w: \`Vec<Vec<(i64, i64)>>\` (the nested Vec read the same way)" 'fn f(): i64 {\n    var v: Vec<Vec<(i64, i64)>> = 0;\n    return 3;\n}\nsyscall(60, f());\n'
refused r03x "$VTE" "R3x: \`sizeof(Vec<(i64, i64)>)\`" 'fn f(): i64 { return sizeof(Vec<(i64, i64)>); }\nsyscall(60, f());\n'
refused r03y "$VTE" "R3y: a \`p: *Vec<(i64, i64)>\` struct field" 'struct H { p: *Vec<(i64, i64)>; n; }\nfn f(): i64 { var h: H; h.n = 3; return h.n; }\nsyscall(60, f());\n'
refused r03z "$VTE" "R3z: in a generic fn called at i64, a struct and i64 again (once, not per instance)" 'struct Pt { x; y; }\nfn g<T>(x: T): i64 {\n    var v: Vec<(i64, i64)> = 0;\n    return 1;\n}\nfn f(): i64 { var p: Pt; return g(1) + g(p) + g(2); }\nsyscall(60, f());\n'

# ── R4: generics ───────────────────────────────────────────────────────────────────────────────────
refused r04a "a tuple type in a generic fn is refused" "R4a: a tuple local in a generic fn" 'fn g<T>(x: T): T {\n    var t: (i64, i64);\n    t.0 = x;\n    return t.0;\n}\nfn f(): i64 { return g(3); }\nsyscall(60, f());\n'
refused r04b "a tuple field in a generic struct is refused" "R4b: a tuple field in a generic struct" 'struct B<T> { v: T; t: (i64, i64); }\nfn f(): i64 { var b: B<i64>; b.v = 3; return b.v; }\nsyscall(60, f());\n'
refused r04c "a tuple type in a generic fn is refused" "R4c: a tuple parameter in a generic fn's signature" 'fn g<T>(x: T, t: (i64, i64)): T { return x; }\nfn f(): i64 { return g(3, 0); }\nsyscall(60, f());\n'
refused r04d "a tuple type in a generic fn is refused" "R4d: an un-annotated literal in a generic fn (it mints its type there; once over the instances)" 'fn g<T>(x: T): T {\n    var t = (x, 1);\n    return t.0;\n}\nfn f(): i64 { return g(3) + g(4); }\nsyscall(60, f());\n'
# R4s / R4t (6.7.8 repair) — the enclosing-fn scan stops at a bodyless trait member's `;`: it ran on to the
# next `{`, so a tuple right after a trait whose LAST member is generic and bodyless was refused as "in a
# generic fn" (6.7.7) — a zone global's annotation, and a struct field (the struct's own `{` taken for the
# member's body).
exits r04s 3 "R4s: a tuple zone global right after \`trait Tr { fn pick<U>(..): i64; }\` (not in a generic fn)" 'trait Tr { fn pick<U>(self, u: U): i64; }\nvar t: (i64, i64) = (1, 2);\nsyscall(60, t.0 + t.1);\n'
exits r04t 7 "R4t: a struct's tuple field right after the same trait" 'trait Tr { fn pick<U>(self, u: U): i64; }\nstruct H { a; p: (i64, i64); }\nfn f(): i64 { var h: H; h.p.0 = 3; h.p.1 = 4; return h.p.0 + h.p.1; }\nsyscall(60, f());\n'
# R4e-R4r (T6) — a tuple never binds a type parameter by INFERENCE: `first(t)` minted `first$(i64, i64)`, a
# generic over a tuple. Refused once, at the argument, whatever the generic's body (a struct-reading stub's
# refusal and an inlined `x.0` stay quiet), the call's position or its receiver (a capture keeps the tuple).
RB="a tuple cannot bind a type parameter: '"
FG='fn first<T>(x: T): i64 { return 7; }\n'
IG='fn id<T>(x: T): T { return x; }\n'
refused r04e "${RB}first' is generic" "R4e: \`first(t)\`, a tuple local (it minted \`first\$(i64, i64)\`)" "${FG}fn f(): i64 {\n    var t = (5, 9);\n    return first(t) + 1;\n}\nsyscall(60, f());\n"
refused r04f "${RB}first' is generic" "R4f: a tuple parameter" "${FG}fn f(t: (i64, i64)): i64 { return first(t); }\nfn g(): i64 {\n    var t = (1, 2);\n    return f(t);\n}\nsyscall(60, g());\n"
refused r04g "${RB}first' is generic" "R4g: a tuple global, at top level" "${FG}var T0 = (1, 2);\nvar G2 = first(T0);\nsyscall(60, G2);\n"
refused r04h "${RB}two' is generic" "R4h: the second type parameter, \`two(1, t)\`" 'fn two<A, B>(x: A, y: B): i64 { return 7; }\nfn f(): i64 {\n    var t = (5, 9);\n    return two(1, t);\n}\nsyscall(60, f());\n'
refused r04i "${RB}two' is generic" "R4i: both, \`two(t, t)\` (once)" 'fn two<A, B>(x: A, y: B): i64 { return 7; }\nfn f(): i64 {\n    var t = (5, 9);\n    var y = two(t, t);\n    return y;\n}\nsyscall(60, f());\n'
refused r04j "${RB}fld' is generic" "R4j: a generic reading T as a struct (\`x.0\`): no stub refusal, no error in its inlined body" 'fn fld<T>(x: T): i64 { return x.0; }\nfn f(): i64 {\n    var t = (5, 9);\n    return fld(t);\n}\nsyscall(60, f());\n'
refused r04k "${RB}add1' is generic" "R4k: a generic using T as a value (\`x + 1\`)" 'fn add1<T>(x: T): i64 { return x + 1; }\nfn f(): i64 {\n    var t = (5, 9);\n    var y = add1(t);\n    return y;\n}\nsyscall(60, f());\n'
refused r04l "${RB}id' is generic" "R4l: \`var u: (i64, i64) = id(t);\` then \`u.0\` (the tuple kept, the call skipped)" "${IG}fn f(): i64 {\n    var t = (5, 9);\n    var u: (i64, i64) = id(t);\n    return u.0;\n}\nsyscall(60, f());\n"
refused r04m "${RB}id' is generic" "R4m: \`u = id(t);\` into an existing tuple" "${IG}fn f(): i64 {\n    var t = (5, 9);\n    var u: (i64, i64);\n    u = id(t);\n    return u.0;\n}\nsyscall(60, f());\n"
refused r04n "${RB}mk' is generic" "R4n: \`var a, b = mk(t);\`, the destructure" 'fn mk<T>(x: T): (i64, i64) { return (1, 2); }\nfn f(): i64 {\n    var t = (5, 9);\n    var a, b = mk(t);\n    return a + b;\n}\nsyscall(60, f());\n'
refused r04o "${RB}first' is generic" "R4o: a tail call in a loop, \`return first(t);\`" "${FG}fn f(n): i64 {\n    var t = (5, 9);\n    while (n > 0) {\n        n = n - 1;\n        if (n == 3) { return first(t); }\n    }\n    return 0;\n}\nsyscall(60, f(5));\n"
refused r04p "${RB}later' is generic" "R4p: a generic declared below the call" 'fn f(): i64 {\n    var t = (5, 9);\n    return later(t);\n}\nfn later<T>(x: T): i64 { return 7; }\nsyscall(60, f());\n'
refused r04q "${RB}first' is generic" "R4q: in an #inline fn replayed twice (once)" "${FG}#inline\nfn h(t: (i64, i64)): i64 { return first(t); }\nfn f(): i64 {\n    var t = (5, 9);\n    return h(t) + h(t);\n}\nsyscall(60, f());\n"
exits r04r 21 "R4r: a struct, an element and a scalar still bind T (\`first(p)\`, \`first(t.0)\`, \`first(5)\`)" "${P}${FG}fn f(): i64 {\n    var p = P { 1, 2 };\n    var t = (5, 9);\n    return first(p) + first(t.0) + first(5);\n}\nsyscall(60, f());\n"

# ── R6: async ──────────────────────────────────────────────────────────────────────────────────────
# An `async fn` runs its body at force time, so a by-value struct parameter is refused (the inherited
# rule, `_refuse_async_struct_param`). Its usual advice is a pointer, which a tuple cannot be: the
# tuple form names the type and says to pass the elements.
printf '#!/bin/sh\nCYRIUS_ASYNC=1 exec "%s" "$@"\n' "$CC" > "$T/acc"; chmod +x "$T/acc"
CC_SV=$CC; CC="$T/acc"
refused r06a "async fn parameter 't' is a tuple (i64, i64), which an \`async fn\` does not capture yet - pass its elements as separate parameters" "R6a: an \`async fn\` with a tuple parameter (CYRIUS_ASYNC=1)" 'include "lib/alloc.cyr"\nasync fn af(t: (i64, i64)): i64 { return t.0; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
CC=$CC_SV

# ── R11: a whole tuple is not a value ──────────────────────────────────────────────────────────────
TT='fn g(x): i64 { return x; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 1;\n    t.1 = 2;\n'
TE='\n    return 0;\n}\nsyscall(60, f());\n'
U="tuple 't' used as a value"
refused r11a "$U" "R11a: \`t == 5\`" "${TT}    if (t == 5) { return 1; }${TE}"
refused r11b "$U" "R11b: \`t + 1\`" "${TT}    return t + 1;${TE}"
refused r11c "$U" "R11c: \`!t\`" "${TT}    if (!t) { return 1; }${TE}"
refused r11d "$U" "R11d: \`if (t)\`" "${TT}    if (t) { return 1; }${TE}"
refused r11e "$U" "R11e: \`while (t)\`" "${TT}    while (t) { return 1; }${TE}"
refused r11f "$U" "R11f: \`match t\`" "${TT}    match t { 1 => { return 1; } _ => { return 0; } }${TE}"
refused r11g "$U" "R11g: \`switch (t)\`" "${TT}    switch (t) { case 1: return 1; default: return 0; }${TE}"
refused r11h "$U" "R11h: \`for x in t\`" "include \"lib/alloc.cyr\"\ninclude \"lib/vec.cyr\"\n${TT}    var s = 0;\n    for x in t { s = s + x; }${TE}"
refused r11i "$U" "R11i: an untyped-parameter argument \`g(t)\`" "${TT}    return g(t);${TE}"
refused r11j "$U" "R11j: \`load64(t)\`" "${TT}    return load64(t);${TE}"
refused r11k "$U" "R11k: an un-annotated \`var x = t;\`" "${TT}    var x = t;\n    return x;${TE}"
refused r11l "$U" "R11l: \`callptr(fp, t)\`" "${TT}    var fp = &g;\n    return callptr(fp, t);${TE}"
refused r11m "tuple field 'p' used as a value" "R11m: a tuple FIELD, \`h.p == 5\`" "${TH}fn f(): i64 {\n    var h: H;\n    h.p.0 = 1;\n    if (h.p == 5) { return 1; }\n    return 0;\n}\nsyscall(60, f());\n"
refused r11n "tuple field 'p' used as a value" "R11n: a tuple field as an untyped argument" "${TH}fn g(x): i64 { return x; }\nfn f(): i64 {\n    var h: H;\n    return g(h.p);\n}\nsyscall(60, f());\n"
refused r11o "$U" "R11o: an if-expression branch" "${TT}    var y = if (t.0 == 1) { t } else { 0 };\n    return y;${TE}"
refused r11p "$U" "R11p: \`-t\`" "${TT}    return -t;${TE}"
refused r11q "tuple 'G' used as a value" "R11q: a global, \`G + 1\`" "${TH}var GH = H { 1, 2, 3, 4 };\nvar G: (i64, i64) = GH.p;\nfn f(): i64 { return G + 1; }\nsyscall(60, f());\n"
refused r11r "$U" "R11r: a closure's capture, \`|| t + 1\`" "include \"lib/alloc.cyr\"\n${TT}    alloc_init();\n    var c = || t + 1;\n    return fncall0(c);${TE}"

# ── R12: a value that is no tuple into a tuple place (non-literal shapes) ──────────────────────────
A12="cannot assign a value that is not a tuple to tuple"
I12="cannot initialize tuple"
refused r12a "$A12 't'" "R12a: \`t = 5\`" "${TT}    t = 5;${TE}"
refused r12b "$A12 't'" "R12b: \`t = x\`, a scalar" "${TT}    var x = 3;\n    t = x;${TE}"
refused r12c "$A12 't'" "R12c: \`t = g(3)\`, a scalar call" "${TT}    t = g(3);${TE}"
refused r12d "$A12 't'" "R12d: \`t = (g(3))\`" "${TT}    t = (g(3));${TE}"
refused r12e "$I12 'u' with a value that is not a tuple" "R12e: \`var u: (i64, i64) = 5;\`" "${TT}    var u: (i64, i64) = 5;${TE}"
refused r12f "$I12 'u' with a value that is not a tuple" "R12f: \`= x + 1\`" "${TT}    var x = 2;\n    var u: (i64, i64) = x + 1;${TE}"
refused r12g "$I12 'u' with a value that is not a tuple" "R12g: an address (it would be pointer-mode)" "${TT}    var u: (i64, i64) = g(4096);${TE}"
refused r12h "$I12 'G' with a value that is not a tuple" "R12h: a declaration-zone global \`var G: (i64, i64) = 5;\`" 'var G: (i64, i64) = 5;\nsyscall(60, 0);\n'
refused r12i "$I12 'G' with a value that is not a tuple" "R12i: a global after the first statement" 'syscall(1, 1, "", 0);\nvar G: (i64, i64) = 5;\nsyscall(60, 0);\n'
refused r12j "cannot store a value that is not a tuple into tuple field 'p'" "R12j: \`h.p = 5\`" "${TH}fn f(): i64 {\n    var h: H;\n    h.p = 5;\n    return 0;\n}\nsyscall(60, f());\n"
refused r12k "$A12 'G'" "R12k: a global, \`G = 5\` at top level" "${TH}var GH = H { 1, 2, 3, 4 };\nvar G: (i64, i64) = GH.p;\nG = 5;\nsyscall(60, 0);\n"
refused r12l "$A12 'G'" "R12l: a classic-for step \`G = 5\`" "${TH}var GH = H { 1, 2, 3, 4 };\nvar G: (i64, i64) = GH.p;\nfn f(): i64 {\n    for (var i = 0; i < 2; G = 5) { i = i + 1; }\n    return 0;\n}\nsyscall(60, f());\n"
refused r12m "cannot copy 'p' into a variable of a different struct/vector type: 't'" "R12m: a struct into a tuple (by sid)" "${P}${TT}    var p: P;\n    t = p;${TE}"
refused r12n "cannot copy 'u' into a variable of a different struct/vector type: 't'" "R12n: another tuple type" "${TT}    var u: (i64, f64);\n    t = u;${TE}"
refused r12o "cannot copy 'u' into a variable of a different struct/vector type: 'v'" "R12o: another tuple type, a declaration" "${TT}    var u: (i64, f64);\n    var v: (i64, i64) = u;${TE}"
refused r12p "uninitialized variable not allowed" "R12p: \`var G: (i64, i64);\` in the declaration zone keeps its one \"uninitialized\" refusal" 'var G: (i64, i64);\nsyscall(60, 0);\n'
# R12q-s: an argument is type-checked by sid against a tuple parameter (`_sarg_type_err`), both ways.
TK='fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\n'
refused r12q "cannot pass 'p' to a parameter of a different struct type in a call to 'take'" "R12q: a struct as a tuple argument" "${P}${TK}fn f(): i64 {\n    var p: P;\n    p.a = 1;\n    return take(p);\n}\nsyscall(60, f());\n"
refused r12r "cannot pass 'u' to a parameter of a different struct type in a call to 'take'" "R12r: another tuple type as the argument" "${TK}fn f(): i64 {\n    var u: (i64, f64);\n    u.0 = 1;\n    return take(u);\n}\nsyscall(60, f());\n"
refused r12s "cannot pass 't' to a parameter of a different struct type in a call to 'tp'" "R12s: a tuple as a struct argument" "${P}fn tp(p: P): i64 { return p.a; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 1;\n    return tp(t);\n}\nsyscall(60, f());\n"

# ── R13: a tuple has no methods ────────────────────────────────────────────────────────────────────
M13="a tuple has no methods"
refused r13a "$M13 - 'm' is not a method of a tuple" "R13a: \`t.m()\`" "${TT}    return t.m();${TE}"
refused r13b "$M13 - 'm' is not a method of a tuple" "R13b: \`t.m();\` as a statement" "${TT}    t.m();${TE}"
refused r13c "$M13 - '0' is not a method of a tuple" "R13c: \`t.0(1)\`" "${TT}    return t.0(1);${TE}"
refused r13d "$M13 - 'm' is not a method of a tuple" "R13d: \`h.p.m()\`, a tuple field" "${TH}fn f(): i64 {\n    var h: H;\n    return h.p.m();\n}\nsyscall(60, f());\n"

# R13e-i: `x.0(..)` on ANY receiver. Since T1 lexed `p.0` as a selector, `p.0()` on a struct resolved as the
# method `P_0` and CALLED a user `fn P_0(self)` (exit 7) — it was "expected identifier, got number 0".
PM='struct P { a; b; }\nfn P_0(self): i64 { return 7; }\n'
D13="a method name cannot start with a digit - '0' is an element selector"
refused r13e "$D13" "R13e: \`p.0()\` on a named struct (a user \`fn P_0(self)\` is not called)" "${PM}fn f(): i64 {\n    var p: P;\n    return p.0();\n}\nsyscall(60, f());\n"
refused r13f "$D13" "R13f: \`p.0();\` as a statement" "${PM}fn f(): i64 {\n    var p: P;\n    p.0();\n    return 3;\n}\nsyscall(60, f());\n"
refused r13g "$D13" "R13g: \`mk().0()\`, on a call's result" "${PM}fn mk(): P {\n    var p: P;\n    return p;\n}\nfn f(): i64 { return mk().0(); }\nsyscall(60, f());\n"
refused r13h "$D13" "R13h: \`q.p.0()\`, on a nested struct field" "${PM}struct Q { p: P; }\nfn f(): i64 {\n    var q: Q;\n    return q.p.0();\n}\nsyscall(60, f());\n"
refused r13i "$D13" "R13i: \`p.0().a\` — the chain after it is consumed (one error)" "${PM}fn f(): i64 {\n    var p: P;\n    var x = p.0().a;\n    return x;\n}\nsyscall(60, f());\n"

# ── R17: a multi-value call is not a tuple argument ───────────────────────────────────────────────
# The parameter takes a tuple's ADDRESS; the call leaves its values in the return registers, so the
# value push handed the callee the first value as an address (x86: SIGSEGV). Bind it first.
MK='fn mk(a): (i64, i64) { return (a, a + 1); }\n'
R17="is not a tuple argument - bind it first: \`var t: (i64, i64) = "
refused r17a "a multi-value call 'mk' $R17" "R17a: \`take(mk(3))\` in a fn" "${MK}${TK}fn f(): i64 { return take(mk(3)) + 1; }\nsyscall(60, f());\n"
refused r17b "a multi-value call 'mk' $R17" "R17b: at top level" "${MK}${TK}syscall(60, take(mk(3)));\n"
refused r17c "a multi-value call 'mk' $R17" "R17c: a tail call, \`mk\` declared below" "${TK}fn f(): i64 { return take(mk(3)); }\n${MK}syscall(60, f());\n"
refused r17d "a multi-value call 'mk' $R17" "R17d: the second argument, in a loop's tail call" "fn take2(k, t: (i64, i64)): i64 { return t.0 * 10 + t.1 + k; }\n${MK}fn f(): i64 {\n    var i = 0;\n    while (i < 3) {\n        if (i == 2) { return take2(1, mk(3)); }\n        i = i + 1;\n    }\n    return 0;\n}\nsyscall(60, f());\n"
refused r17e "a multi-value call 'mk' $R17" "R17e: an explicit generic \`mk<i64>(3)\`" "fn mk<T>(a: T): (i64, i64) { return (a, a + 1); }\n${TK}fn f(): i64 { return take(mk<i64>(3)); }\nsyscall(60, f());\n"
refused r17f "a multi-value call 'mk' $R17" "R17f: \`take((mk(3)))\`, parenthesised" "${MK}${TK}fn f(): i64 { return take((mk(3))); }\nsyscall(60, f());\n"
refused r17g "a multi-value call 'B_mk' $R17" "R17g: a method \`take(b.mk(3))\`" "struct B { v; }\nimpl B { fn mk(self, a): (i64, i64) { return (a, a + self.v); } }\n${TK}fn f(): i64 {\n    var b: B;\n    b.v = 1;\n    return take(b.mk(3));\n}\nsyscall(60, f());\n"
refused r17h "a multi-value call 'P_add' $R17" "R17h: an operator \`take(p + q)\`" "${P}fn P_add(a: P, b: P): (i64, i64) { return (a.a + b.a, a.b + b.b); }\n${TK}fn f(): i64 {\n    var p = P { 1, 2 };\n    var q = P { 3, 4 };\n    return take(p + q);\n}\nsyscall(60, f());\n"
# R17u (6.7.13, issues/archived/2026-10-14-undeclared-multi-value-call-into-tuple-parameter-crashes.md): an UNDECLARED
# callee whose every return is \`(a, b)\` (counted by 6.7.11's pass 1, \`_mv_callee\`) is a multi-value call too — its
# first value was pushed as the tuple's address (x86 / aarch64 rc 139, cx guest error 1, PE 5). The repros verbatim.
MKU='fn mku(a) { return (a, a + 1); }\n'
refused r17u1 "a multi-value call 'mku' $R17" "R17u1: \`take(mku(3))\`, mku undeclared (counted)" "${MKU}${TK}fn f(): i64 { return take(mku(3)); }\nsyscall(60, f());\n"
refused r17u2 "a multi-value call 'B_mku' $R17" "R17u2: a method \`take(b.mku(3))\`, undeclared (counted)" "struct B { z; }\nimpl B { fn mku(self, a) { return (a, a + 1); } }\n${TK}fn f(): i64 { var b = B { 0 }; return take(b.mku(3)); }\nsyscall(60, f());\n"
refused r17u3 "a multi-value call 'mk3' is not a tuple argument - bind it first: \`var t: (i64, i64, i64) = mk3(..);\`" "R17u3: a counted 3-value callee into \`(i64, i64, i64)\`" 'fn mk3(a) { return (a, a + 1, a + 2); }\nfn take(t: (i64, i64, i64)): i64 { return t.0 * 100 + t.1 * 10 + t.2; }\nfn f(): i64 { return take(mk3(1)); }\nsyscall(60, f());\n'
exits r17u4 45 "R17u4: a mixed-arity undeclared callee is not judged (its one-value path hands a tuple's address)" "var G: (i64, i64) = (4, 5);\nfn mkm(a) { if (a == 0) { return (1, 2); } return &G; }\n${TK}fn f(): i64 { return take(mkm(1)); }\nsyscall(60, f());\n"
refused r17u5 "a multi-value call 'mk' $R17" "R17u5: the declared callee, the same text (control)" "${MK}${TK}fn f(): i64 { return take(mk(3)); }\nsyscall(60, f());\n"
# R17v (6.7.14, D44, the user's decision of 2026-10-16; issues/archived/2026-10-15-non-tuple-word-into-tuple-parameter-dereferenced.md)
# — what can never be a tuple's address is refused into a tuple parameter: an integer literal (`_tup_arg_lit`, its own
# words) and a call returning several values from a fn declared ONE scalar, which pass 1 counted (6.7.13's D23 B
# shape; `_mv_callee_any`), R17's words — each compiled and the callee read through the value (139 / 139 / 1 / 5 on
# x86_64 / aarch64 / cx / PE). An untyped word stays the address (R17v9: `take(&t)`, `take(u)`, `take(mk())` run on
# every leg). `take(one(3))` — a one-value call — is a word like those and still compiles and crashes (the decision:
# the caller's to make it an address), so it has no row. Every row on all four legs.
# Mutations (scratch trees, run 2026-10-17, CYCC= the mutant): the tree before (6d54e86c) -> R17v1-R17v8, R17v10,
# R17v11 BUILD on every leg; `_tup_arg_call` back to `_mv_callee` -> R17v2, R17v3, R17v6; `_tup_arg_mrc` back to
# `_mv_callee` -> R17v4, R17v5; `_sc_post_small` noting `_mv_callee` only -> R17v4, R17v5; `_try_push_struct_addr_arg`
# without its `_tup_arg_lit` call -> R17v1, R17v7, R17v8, R17v10, R17v11; `_tup_arg_lit` without its generic skip ->
# R4c (two error lines: its `g(3, 0)`'s literal reported beside the generic's own tuple-parameter refusal).
LIT="cannot pass an integer to tuple parameter 't' (i64, i64) of 'take' - it takes a tuple"
refused4 r17v1 "2:27: $LIT" "R17v1: the issue's \`take(5)\` verbatim" 'fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn f(): i64 { return take(5); }\nsyscall(60, f());\n'
refused4 r17v2 "3:27: a multi-value call 'g2' $R17" "R17v2: the issue's \`take(g2(3))\`, \`g2\` declared \`: i64\`, verbatim" 'fn g2(a): i64 { return (a, a + 1); }\nfn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn f(): i64 { return take(g2(3)); }\nsyscall(60, f());\n'
refused4 r17v3 "a multi-value call 'g2' $R17" "R17v3: ... \`g2\`'s values from \`ret2\` (counted since 6.7.14)" 'fn g2(a): i64 { ret2(a, a + 1); }\nfn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn f(): i64 { return take(g2(3)); }\nsyscall(60, f());\n'
refused4 r17v4 "a multi-value call 'X_g2' is not a tuple argument" "R17v4: a method \`take(x.g2(3))\` declared \`: i64\`" 'struct X { v; }\nimpl X { fn g2(self, a): i64 { return (a, a + 1); } }\nfn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn f(): i64 { var x = X { 0 }; return take(x.g2(3)); }\nsyscall(60, f());\n'
refused4 r17v5 "a multi-value call 'P_add' is not a tuple argument" "R17v5: an operator \`take(p + q)\`, \`P_add\` declared \`: i64\`" "${P}fn P_add(a: P, b: P): i64 { return (a.a + b.a, a.b + b.b); }\nfn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn f(): i64 { var p = P { 1, 2 }; var q = P { 3, 4 }; return take(p + q); }\nsyscall(60, f());\n"
refused4 r17v6 "a multi-value call 'g2' is not a tuple argument - bind it first: \`var t: (f64, f64) = g2(..);\`" "R17v6: a \`: f64\` callee's two values into \`(f64, f64)\`" 'fn g2(x): f64 { return (f64_from(x), f64_from(x + 1)); }\nfn take(t: (f64, f64)): i64 { return f64_to(t.0) * 10 + f64_to(t.1); }\nfn f(): i64 { return take(g2(3)); }\nsyscall(60, f());\n'
refused4 r17v7 "2:29: $LIT" "R17v7: \`take((5))\`, wrapped" 'fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn f(): i64 { var a = take((5)); return a; }\nsyscall(60, f());\n'
refused4 r17v8 "cannot pass an integer to tuple parameter 't' (i64, i64) of 'take2'" "R17v8: the second argument, \`take2(1, 0x10)\` at top level" 'fn take2(k, t: (i64, i64)): i64 { return t.0 * 10 + t.1 + k; }\nsyscall(60, take2(1, 0x10));\n'
exits4 r17v9 34 "R17v9: an untyped word is the address — \`take(&t)\`, \`take(u)\`, \`take(mk())\` (\`mk\`: i64 returning an alloc)" 'include "lib/alloc.cyr"\nfn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn mk(): i64 { var p = alloc(16); store64(p, 3); store64(p + 8, 4); return p; }\nfn f(): i64 { alloc_init(); var t: (i64, i64) = (3, 4); var u = &t; return take(&t) + take(u) + take(mk()) - 68; }\nsyscall(60, f());\n'
refused4 r17v10 "$LIT" "R17v10: an \`#inline\` callee" '#inline\nfn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn f(): i64 { return take(5) + 1; }\nsyscall(60, f());\n'
refused4 r17v11 "cannot pass an integer to tuple parameter 't' (i64, i64) of 'X.take'" "R17v11: a method's tuple parameter, \`x.take(5)\`" 'struct X { v; }\nimpl X { fn take(self, t: (i64, i64)): i64 { return t.0 * 10 + t.1; } }\nfn f(): i64 { var x = X { 0 }; return x.take(5); }\nsyscall(60, f());\n'
# R17w (6.7.15, D36, the user's decision of 2026-10-18; issues/2026-10-17-tuple-parameter-negated-bool-or-constant-
# expression-literal-dereferenced.md) — an argument made ONLY of literals and operators is no tuple either: \`take(-5)\`,
# \`take((-5))\`, \`take(true)\` and \`take(5 + 0)\` (the filed table, each in the filed template) compiled and the callee
# read through the value (139 / 139 / 1 / 5 on x86_64 / aarch64 / cx / PE). \`_tal_scan\` reads the whole argument:
# integer / char literals, \`true\` / \`false\`, operators and parentheses only — "an integer", or "a bool" when every
# literal is \`true\` / \`false\`. A name (a const too), a call and \`&t\` keep passing the address (R17w12), and so does a
# literal expression into a parameter that is not a tuple; a generic's tuple parameter stays R4 alone (R17w13).
# Mutations (scratch trees, run 2026-10-18, every leg): the tree before (4862a462) -> R17w1-R17w11 BUILD (R17w12 /
# R17w13 hold); \`_sarg_paren\` without its \`_tup_arg_lit\` call -> R17w8 BUILDS; \`_tal_end\` answering 1 for a
# bool-only argument -> R17w3, R17w4, R17w10 name "an integer"; \`_tal_scan\` taking a name as a literal -> R17w12
# refused (R17v9, the A rows and every tuple-variable argument too); \`_tup_arg_lit\` without its generic skip ->
# R17w13 and R4c two error lines.
TW='fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\n'
BOOLT="cannot pass a bool to tuple parameter 't' (i64, i64) of 'take' - it takes a tuple"
refused4 r17w1 "2:27: $LIT" "R17w1: \`take(-5)\`, the filed template" "${TW}fn f(): i64 { return take(-5); }\nsyscall(60, f());\n"
refused4 r17w2 "2:28: $LIT" "R17w2: \`take((-5))\`" "${TW}fn f(): i64 { return take((-5)); }\nsyscall(60, f());\n"
refused4 r17w3 "2:27: $BOOLT" "R17w3: \`take(true)\` is a bool" "${TW}fn f(): i64 { return take(true); }\nsyscall(60, f());\n"
refused4 r17w4 "2:27: $BOOLT" "R17w4: \`take(false)\`" "${TW}fn f(): i64 { return take(false); }\nsyscall(60, f());\n"
refused4 r17w5 "2:27: $LIT" "R17w5: \`take(5 + 0)\`" "${TW}fn f(): i64 { return take(5 + 0); }\nsyscall(60, f());\n"
refused4 r17w6 "2:27: $LIT" "R17w6: \`take(~0)\`" "${TW}fn f(): i64 { return take(~0); }\nsyscall(60, f());\n"
refused4 r17w7 "2:28: $LIT" "R17w7: \`take((1 << 3))\`" "${TW}fn f(): i64 { return take((1 << 3)); }\nsyscall(60, f());\n"
refused4 r17w8 "2:27: $LIT" "R17w8: \`take((1) + 2)\`, a \`(\`-led literal expression" "${TW}fn f(): i64 { return take((1) + 2); }\nsyscall(60, f());\n"
refused4 r17w9 "2:35: cannot pass an integer to tuple parameter 't' (i64, i64) of 'take2'" "R17w9: the second argument \`take2(1 + 2, -5)\` (the first, no tuple, is not judged)" 'fn take2(k, t: (i64, i64)): i64 { return t.0 * 10 + t.1 + k; }\nfn f(): i64 { return take2(1 + 2, -5); }\nsyscall(60, f());\n'
refused4 r17w10 "cannot pass a bool to tuple parameter 't' (i64, i64) of 'X.take'" "R17w10: a method's tuple parameter, \`x.take(!true)\`" 'struct X { v; }\nimpl X { fn take(self, t: (i64, i64)): i64 { return t.0 * 10 + t.1; } }\nfn f(): i64 { var x = X { 0 }; return x.take(!true); }\nsyscall(60, f());\n'
refused4 r17w11 "2:18: $LIT" "R17w11: at top level, \`take('a' - 1)\`" "${TW}syscall(60, take('a' - 1));\n"
exits4 r17w12 34 "R17w12: still the address — \`take(&t)\`, \`take(u)\`, \`take(mk())\`, a const \`take(C)\` (compiled, not taken), and a literal expression into a parameter that is no tuple" 'include "lib/alloc.cyr"\nconst C = 0;\nfn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn take2(k, t: (i64, i64)): i64 { return t.0 * 10 + t.1 + k; }\nfn mk(): i64 { var p = alloc(16); store64(p, 3); store64(p + 8, 4); return p; }\nfn f(x): i64 { alloc_init(); var t: (i64, i64) = (3, 4); var u = &t; if (x == 0) { return take(C); } return take(&t) + take(u) + take(mk()) + take2(-1 + 1, t) - 102; }\nsyscall(60, f(1));\n'
refused4 r17w13 "1:12: a tuple type in a generic fn is refused" "R17w13: a generic's tuple parameter, \`g(-5, 0)\`: R4 alone" 'fn g<T>(t: (i64, i64), x: T): T { return x; }\nfn f(): i64 { return g(-5, 0); }\nsyscall(60, f());\n'

# ── R21: `t.N` spellings that name no element ──────────────────────────────────────────────────────
refused r21a "unknown field '2' on struct '(i64, i64)'" "R21a: \`t.2\` past the arity (a read)" "${TT}    return t.2;${TE}"
refused r21b "unknown field '2' on struct '(i64, i64)'" "R21b: \`t.2 = 1\` (a write)" "${TT}    t.2 = 1;${TE}"
refused r21c "unknown field '01' on struct '(i64, i64)'" "R21c: \`t.01\`" "${TT}    return t.01;${TE}"
refused r21d "unknown field '0x1' on struct '(i64, i64)'" "R21d: \`t.0x1\`" "${TT}    return t.0x1;${TE}"
refused r21e "unknown field '1_0' on struct '(i64, i64)'" "R21e: \`t.1_0\`" "${TT}    return t.1_0;${TE}"

# ── P: positive ────────────────────────────────────────────────────────────────────────────────────
exits p01 59 "P1: \`var t: (i64, i64);\` then \`t.0 = 5; t.1 = 9;\`" 'fn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 5;\n    t.1 = 9;\n    return t.0 * 10 + t.1;\n}\nsyscall(60, f());\n'
exits p02 96 "P2: copies are by value (a declaration, an assignment, a field)" "${TH}fn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 5;\n    t.1 = 9;\n    var u: (i64, i64) = t;\n    u.0 = 6;\n    var w: (i64, i64);\n    w = u;\n    u.1 = 1;\n    var h: H;\n    h.p = w;\n    w.0 = 0;\n    return h.p.0 * 10 + h.p.1 + t.0 * 0 + (u.1 - 1) * 50 + (t.0 - 5) * 7 + 27;\n}\nsyscall(60, f());\n"
exits p03 23 "P3: a declaration-zone global copied from a struct literal's tuple field" "${TH}var GH = H { 1, 2, 3, 4 };\nvar G: (i64, i64) = GH.p;\nsyscall(60, G.0 * 10 + G.1);\n"
exits p04 61 "P4: f64 and bool elements keep their kind" 'fn f(): i64 {\n    var t: (i64, f64, bool);\n    t.0 = 6;\n    t.1 = 0.5;\n    t.2 = true;\n    t.1 *= 2.0;\n    var k = 0;\n    if (t.2) { k = 1; }\n    if (t.1 == 1.0) { k = k + t.0 * 10; }\n    return k;\n}\nsyscall(60, f());\n'
exits p05 64 "P5: a tuple parameter is the callee's copy (its write never reaches the caller)" 'fn take(t: (i64, i64), k): i64 {\n    t.0 = t.0 + 100;\n    return t.0 * 10 + t.1 + k;\n}\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 5;\n    t.1 = 9;\n    var r = take(t, 1000);\n    return r - 1000 + t.0;\n}\nsyscall(60, f() - 1000);\n'
# P6: `#inline` on a fn with a tuple parameter falls back to a call (the struct rule, `_inl_param_why`)
printf '#inline\nfn ti(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 4;\n    t.1 = 2;\n    return ti(t) + ti((t));\n}\nsyscall(60, f());\n' > "$T/p06.cyr"
build p06
if [ "$rc" -ne 0 ]; then bad "P6: rc $rc: $(grep '^error' "$T/p06.err" | head -1)"
elif ! grep -q "#inline ignored: struct/aggregate parameter" "$T/p06.err"; then bad "P6: no '#inline ignored' warning: $(head -1 "$T/p06.err")"
else chmod +x "$T/p06.bin"; got=0; timeout 10 "$T/p06.bin" || got=$?
    if [ "$got" -eq 84 ]; then ok "P6: \`#inline\` with a tuple parameter: a call (warned), exit 84"; else bad "P6: exit $got, want 84"; fi
fi

# ── T4: the literal `(a, b)` ───────────────────────────────────────────────────────────────────────
# C — compatibility (the planners' q1 / q5 / q7 / q8). PARSE_RETURN's own paren-depth comma scan took
# `return (|a, b| a + b);` and `return (pk<i64, i64>(1, 2));` for multi-value returns ("expected ','");
# the literal's ONE detector (`_tup_commas`) steps a leading closure's bars and a generic call's type
# arguments, so both return their value and the two parenthesised initialisers stay one value.
CL='include "lib/alloc.cyr"\ninclude "lib/fnptr.cyr"\n'
GP='fn pk<A, B>(x: A, y: B): i64 { return 40 + x; }\n'
exits c01 7 "C1: \`var f = (|a, b| a + b);\` is still a parenthesised closure" "${CL}fn m(): i64 { var f = (|a, b| a + b); return fncall2(f, 3, 4); }\nalloc_init();\nsyscall(60, m());\n"
exits c02 7 "C2: \`return (|a, b| a + b);\` returns the closure (it was \"expected ','\")" "${CL}fn mk() { return (|a, b| a + b); }\nfn m(): i64 { var f = mk(); return fncall2(f, 3, 4); }\nalloc_init();\nsyscall(60, m());\n"
exits c03 41 "C3: \`return (pk<i64, i64>(1, 2));\` returns the call (it was \"expected ','\")" "${GP}fn m(): i64 { return (pk<i64, i64>(1, 2)); }\nsyscall(60, m());\n"
exits c04 41 "C4: \`var r = (pk<i64, i64>(1, 2));\` is still one value" "${GP}fn m(): i64 { var r = (pk<i64, i64>(1, 2)); return r; }\nsyscall(60, m());\n"

# S1 — a WRAPPED literal `((a, b))` in every accepting position (the 6.7.6 transparency rule; `_pwrap_k`
# counts the literal's own `(` as a wrap, so an unwrap that stepped inside parsed `1` then "expected ')'").
exits s01 42 "S1: \`((a, b))\` as a local (typed, inferred), an assignment, a field store, an argument, a global in either zone" 'struct H { a; p: (i64, i64); }\nfn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nvar G: (i64, i64) = ((1, 2));\nfn f(): i64 {\n    var t: (i64, i64) = ((3, 4));\n    var u = ((5, 6));\n    t = ((t.1, t.0));\n    var h: H;\n    h.p = ((7, 8));\n    return take(((9, 1))) - 91 + take(t) - 43 + take(u) - 56 + take(h.p) - 78 + take(G) - 12;\n}\nsyscall(1, 1, "", 0);\nvar G2 = ((2, 3));\nsyscall(60, f() + G2.0 * 10 + G2.1 + 19);\n'
# S4 — a declaration-zone tuple literal global is registered 8n bytes inline (pass 1's `_tup_gci`): an
# element write leaves the next global intact (one 8-byte slot would put `G.1` on it).
exits s04 77 "S4: zone \`var G: (i64, i64) = (1, 2); var H = 7;\` (and an un-annotated one): H intact after \`G.1 = 9\`" 'var G: (i64, i64) = (1, 2);\nvar H = 7;\nvar U = (3, 4);\nvar V = 70;\nG.1 = 9;\nU.1 = 9;\nsyscall(60, H + V + (G.1 - 9) + (U.1 - 9) + (G.0 - 1) + (U.0 - 3));\n'

# K1 — `kernel;` parity with a struct literal global: in an x86 kernel build the deferred replay runs
# AFTER the top-level program, so a zone literal of constants is BAKED into the image exactly as
# `var G = P { 3, 4 };` is (`_spc_try`, closing at the tuple's `)`; float elements and `-1.5` too), and
# one with a call element stays late and is named — as the struct literal with a call is.
cat > "$T/k01.cyr" <<'EOF'
kernel;
struct KP { a; b; }
var KS = KP { 3, 4 };
var KT: (i64, i64) = (3, 4);
var KU = (5, 6);
var KF: (i64, f64) = (7, 2.5);
var KN: (i64, f64) = (8, -1.5);
fn kf(): i64 { return 9; }
var KW = (kf(), 1);
var KX = KP { kf(), 1 };
fn ck(got, want, k): i64 { if (got != want) { syscall(60, k); } return 0; }
ck(KS.a * 10 + KS.b, 34, 1);
ck(KT.0 * 10 + KT.1, 34, 2);
ck(KU.0 * 10 + KU.1, 56, 3);
ck(load64(&KF + 8), 0x4004000000000000, 4);
ck(KF.0, 7, 5);
ck(load64(&KN + 8), 0xBFF8000000000000, 6);
ck(KW.0 + KW.1, 0, 7);
ck(KX.a + KX.b, 0, 8);
syscall(60, 100);
EOF
rc=0; CYRIUS_ELF64_KERNEL=1 "$CC" < "$T/k01.cyr" > "$T/k01.bin" 2> "$T/k01.err" || rc=$?
KW_='in a kernel build the initializer of'
if [ "$rc" -ne 0 ]; then bad "K1: the ELF64 kernel build failed: $(grep -m1 '^error' "$T/k01.err")"
else chmod +x "$T/k01.bin"; got=0; timeout 10 "$T/k01.bin" > /dev/null 2>&1 || got=$?
    nw=$(grep -c "$KW_" "$T/k01.err" || true)
    if [ "$got" -ne 100 ]; then bad "K1: the kernel program read a wrong value at check $got (2-6 a baked tuple, 7 the late one)"
    elif [ "$nw" -ne 2 ] || ! grep -q "$KW_ 'KW'" "$T/k01.err" || ! grep -q "$KW_ 'KX'" "$T/k01.err"; then bad "K1: $nw late-initializer warnings, want exactly KW and KX: $(grep "$KW_" "$T/k01.err" | head -3 | tr '\n' '|')"
    else ok "K1: kernel build — constant zone tuples baked (the struct literal's parity), the call element named late"; fi
fi

# R2 — a literal's own shape.
TL='fn take(t: (i64, i64)): i64 { return t.0; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 1;\n    t.1 = 2;\n'
refused r02f "a trailing comma in a tuple literal" "R2f: \`(1, 2,)\`" "${TL}    var q = (1, 2,);${TE}"
refused r02g "a trailing comma in a tuple literal" "R2g: \`(1,)\` (one error)" "${TL}    var q = (1,);${TE}"
refused r02h "an empty element in a tuple literal" "R2h: \`(1, , 2)\`" "${TL}    var q = (1, , 2);${TE}"
refused r02i "tuple (i64, i64) has 2 elements - this literal has 3" "R2i: an annotated literal of another arity (the name is still declared: no cascade)" "${TL}    var q: (i64, i64) = (1, 2, 3);\n    q.0 = 4;\n    return q.0;${TE}"
refused r02j "tuple (i64, i64) has 2 elements - this literal has 3" "R2j: assigned" "${TL}    t = (1, 2, 3);${TE}"
refused r02k "tuple (i64, i64) has 2 elements - this literal has 3" "R2k: an argument \`take((1, 2, 3))\`" "${TL}    return take((1, 2, 3));${TE}"
big='(0'; i=1; while [ $i -lt 257 ]; do big="$big, $i"; i=$((i + 1)); done; big="$big)"
refused r02l "a tuple literal has at most 256 elements" "R2l: 257 elements" "${TL}    var q = ${big};${TE}"

# R5 — a tuple is not a constant: refused by the const evaluator (`_ce_factor`), by name.
refused r05a "a tuple in a const context" "R5a: \`const C = (1, 2);\` (it was \"expected ')', got ','\")" 'const C = (1, 2);\nsyscall(60, 0);\n'
refused r05b "a tuple in a const context" "R5b: a tuple literal in a const fn's evaluation" 'const fn cf(x: i64): i64 {\n    var t = (x, 1);\n    return t.0;\n}\nconst C = cf(3);\nsyscall(60, C);\n'
refused r05c "a tuple in a const context" "R5c: \`#assert (1, 2) == 3\`" 'fn f(): i64 {\n    #assert (1, 2) == 3, "x"\n    return 0;\n}\nsyscall(60, f());\n'
refused r05d "a tuple in a const context" "R5d: \`return (x, 1)\` in a const fn's evaluation" 'const fn cf(x: i64): i64 {\n    return (x, 1);\n}\nconst C = cf(3);\nsyscall(60, C);\n'
# R5e-R5i (T6) — a const fn takes no TUPLE parameter (a compile-time evaluation binds one value per
# parameter): refused at its definition, once — used or not, called at run time or in a const.
CF="const fn parameter 't' is a tuple, which a compile-time evaluation does not take - pass its elements as separate parameters"
refused r05e "$CF" "R5e: \`t.0\` in its body (it was \"expected ';', got '.'\")" 'const fn cf(t: (i64, i64)): i64 { return t.0; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
refused r05f "$CF" "R5f: an unused one, called at run time (it compiled: a constant nowhere)" 'const fn cf(t: (i64, i64)): i64 { return 3; }\nfn f(): i64 {\n    var t = (1, 2);\n    return cf(t);\n}\nsyscall(60, f());\n'
refused r05g "$CF" "R5g: called in a const, \`const C = cf(1);\` (once)" 'const fn cf(t: (i64, i64)): i64 { return 3; }\nconst C = cf(1);\nsyscall(60, C);\n'
refused r05h "$CF" "R5h: after a parameter whose type holds a comma (\`p: Pair<i64, i64>\`) and an untyped one" 'struct Pair<A, B> { a: A; b: B; }\nconst fn cf(p: Pair<i64, i64>, k, t: (i64, f64)): i64 { return k; }\nfn f(): i64 { return 3; }\nsyscall(60, f());\n'
exits r05i 3 "R5i: const fns with i64 / f64 / bool and \`Pair<i64, i64>\` parameters are untouched" 'struct Pair<A, B> { a: A; b: B; }\nconst fn cf(a: i64, b: f64, c: bool): i64 { return a; }\nconst fn cg(p: Pair<i64, i64>, k: i64): i64 { return k; }\nconst C = cf(3, 1.5, true);\nsyscall(60, C);\n'

# R7 — an UN-annotated literal's elements are i64 (ADR-002: an untyped float is an integer); a float
# element is refused: declare the tuple's type (the user's decision, 2026-10-09).
D7="declare the tuple's type"
refused r07a "$D7" "R7a: \`var p = (1, 2.5);\`" "${TL}    var p = (1, 2.5);${TE}"
refused r07b "$D7" "R7b: an f64-typed element \`(1, y)\`" "${TL}    var y: f64 = 1.5;\n    var p = (1, y);${TE}"
refused r07c "$D7" "R7c: a declaration-zone global \`var G = (1, 2.5);\`" 'var G = (1, 2.5);\nsyscall(60, 0);\n'
refused r07d "$D7" "R7d: a global after the first statement" 'syscall(1, 1, "", 0);\nvar G = (2.5, 1);\nsyscall(60, 0);\n'
exits r07e 25 "R7e: annotated, \`var p: (i64, f64) = (1, 2.5);\` is an f64 element" 'fn f(): i64 {\n    var p: (i64, f64) = (1, 2.5);\n    if (p.1 == 2.5) { return 25; }\n    return 1;\n}\nsyscall(60, f());\n'

# R8 — an element is an i64 / f64 / bool VALUE: a struct (by its static type; a heap handle and a
# `*T` are pointers, i64s), a tuple, a u128, a vector and a slice are refused by name.
E8="a tuple element is i64, f64 or bool, not"
refused r08a "$E8 struct 'P'" "R8a: a struct local \`(p, 1)\`" "${P}${TL}    var p: P;\n    var q = (p, 1);${TE}"
refused r08b "tuple 't' used as a value" "R8b: a tuple \`(t, 1)\` (its factor's refusal, once)" "${TL}    var q = (t, 1);${TE}"
refused r08c "$E8 u128" "R8c: a u128" "${TL}    var w: u128 = 5;\n    var q = (w, 1);${TE}"
refused r08d "$E8 a vector" "R8d: an f64v2" "${TL}    var v: f64v2;\n    var q = (v, 1);${TE}"
refused r08e "$E8 a slice" "R8e: a slice" "${TL}    var s: [u8] = 0;\n    var q = (s, 1);${TE}"
refused r08f "$E8 struct 'P'" "R8f: a struct-valued call \`(mk(), 1)\`" "${P}fn mk(): P { var p: P; p.a = 1; p.b = 2; return p; }\n${TL}    var q = (mk(), 1);${TE}"
# 6.7.11: parentheses wrapping a whole element are transparent, as around a by-value struct argument
# (`_expr_struct_sid`, issues/archived/2026-10-08-paren-arg-small-byval-struct-skips-type-check.md): `((p), 1)`
# and `((mk()), 1)` compiled through 6.7.10, storing the struct's first word.
refused r08q "$E8 struct 'P'" "R8q: a wrapped struct local \`((p), 1)\`" "${P}${TL}    var p: P;\n    var q = ((p), 1);${TE}"
refused r08r "$E8 struct 'P'" "R8r: a wrapped struct-valued call \`(((mk())), 1)\`" "${P}fn mk(): P { var p: P; p.a = 1; p.b = 2; return p; }\n${TL}    var q = (((mk())), 1);${TE}"
refused r08g "a tuple \`( .. )\` is a value only" "R8g: a nested literal \`((1, 2), 3)\`" "${TL}    var q = ((1, 2), 3);${TE}"
# R8s-R8x (6.7.13, issues/archived/2026-10-14-dereference-as-tuple-element-stores-first-word.md, the user's D2 (a), 2026-10-15):
# a whole dereference of a `*S` is a struct value (6.7.10 decision 6), so as an element it is refused by name as
# `(p, 1)` is (through `_ess_deref`, the argument's arm); through 6.7.12 each compiled and stored S's FIRST WORD.
# The pointer itself and a field through it are i64s and still compile (R8y).
DP='struct P { a; b; }\nstruct WP { k; p: *P; }\nvar GX = P { 7, 9 };\nvar GP: *P = &GX;\nfn gp(): *P { return &GX; }\n'
refused r08s "$E8 struct 'P'" "R8s: a wrapped dereference \`((*ps), 1)\`" "${DP}${TL}    var x: P;\n    var ps: *P = &x;\n    var q = ((*ps), 1);${TE}"
refused r08t "$E8 struct 'P'" "R8t: a \`: *P\` call's \`(*gp(), 1)\`" "${DP}${TL}    var q = (*gp(), 1);${TE}"
refused r08u "$E8 struct 'P'" "R8u: a \`*P\` field's \`(1, *w.p)\`" "${DP}${TL}    var w = WP { 0, GP };\n    var q = (1, *w.p);${TE}"
refused r08v "$E8 struct 'P'" "R8v: a dereference of an address-of \`(*(&x), 1)\`" "${DP}${TL}    var x: P;\n    var q = (*(&x), 1);${TE}"
refused r08w "$E8 struct 'P'" "R8w: top level \`var G = (*GP, 1);\`" "${DP}var G = (*GP, 1);\nsyscall(60, G.1);\n"
refused r08x "$E8 struct 'P'" "R8x: a tuple argument \`take((*GP, 1))\`" "${DP}${TL}    return take((*GP, 1));${TE}"
exits r08y 77 "R8y: \`(ps, 1)\` and \`(ps.a, 1)\` — the pointer and a field through it are i64s" "${DP}fn f(): i64 {\n    var ps: *P = &GX;\n    var q = (ps, 1);\n    var r = (ps.a, 1);\n    var pq: *P = q.0;\n    return pq.b * 10 - 20 + r.0 * q.1;\n}\nsyscall(60, f());\n"
# The filed repro, verbatim: refused at each element, as `(s, w)` is (two struct values: two refusals), no binary.
printf 'struct P8 { a; }\nstruct P16 { a; b; }\nfn go(): i64 {\n    var s: P8; s.a = 7;\n    var w: P16; w.a = 5; w.b = 9;\n    var ps: *P8 = &s;\n    var pw: *P16 = &w;\n    var t: (i64, i64) = (*ps, *pw);\n    return t.0 * 10 + t.1;\n}\nsyscall(60, go());\n' > "$T/r08z.cyr"
build r08z
if [ "$rc" -eq 0 ]; then bad "R8z: the filed (*ps, *pw) BUILT (75 = each struct's first word)"
elif [ -s "$T/r08z.bin" ]; then bad "R8z: refused but still emitted a binary"
elif ! grep -qF "$E8 struct 'P8'" "$T/r08z.err" || ! grep -qF "$E8 struct 'P16'" "$T/r08z.err"; then bad "R8z: want P8 and P16 named: $(grep '^error' "$T/r08z.err" | head -2 | tr '\n' '|')"
elif [ "$(grep -c '^error' "$T/r08z.err")" -ne 2 ]; then bad "R8z: $(grep -c '^error' "$T/r08z.err") error lines (want 2, one per element)"
else ok "R8z: the filed (*ps, *pw), verbatim: refused at each element by name, no binary"; fi
refused r08h "cannot store a value that is not a bool into bool field '1'" "R8h: a non-bool into a bool element" "${TL}    var q: (i64, bool) = (1, 5);${TE}"
exits r08i 7 "R8i: a \`Str\` handle and a \`*T\` are pointers — i64 elements" "include \"lib/str.cyr\"\n${P}fn f(): i64 {\n    alloc_init();\n    var p: P;\n    p.a = 4;\n    var pp: *P = &p;\n    var s = str_from(\"abc\");\n    var q = (s, pp);\n    return str_len(q.0) + load64(q.1);\n}\nsyscall(60, f());\n"
printf 'fn f(): i64 {\n    var q: (f64, i64) = (1, 5);\n    return q.1;\n}\nsyscall(60, f());\n' > "$T/r08j.cyr"
build r08j
if [ "$rc" -ne 0 ]; then bad "R8j: rc $rc: $(grep '^error' "$T/r08j.err" | head -1)"
elif ! grep -q "an integer stored into an f64/f32 slot keeps its integer bits" "$T/r08j.err"; then bad "R8j: no keep-its-bits warning: $(head -1 "$T/r08j.err")"
else chmod +x "$T/r08j.bin"; got=0; timeout 10 "$T/r08j.bin" || got=$?
    if [ "$got" -eq 5 ]; then ok "R8j: an integer into an f64 element keeps its bits, warned (the struct literal's rule), exit 5"; else bad "R8j: exit $got, want 5"; fi
fi

# R8k-R8p (B4 review) — an element is a ONE-SLOT store: a `: stack` pair there kept the tag and dropped the
# payload (`var t = (f(7), 3);` was (0, 3), exit 3), as `t.0 = f(7);` would and is refused (T5b). Refused at
# every literal position; `f(7)?` consumes the pair and stays an element.
SE='enum R: stack { Ok(v), Err(e) }\nfn f(x) { return Ok(x); }\n'
LP="a \`: stack\` enum returns two values"
refused r08k "$LP" "R8k: \`var t = (f(7), 3);\`" "${SE}fn m(): i64 {\n    var t = (f(7), 3);\n    return t.0 * 10 + t.1;\n}\nsyscall(60, m());\n"
refused r08l "$LP" "R8l: \`t = (f(7), 3);\`" "${SE}fn m(): i64 {\n    var t: (i64, i64);\n    t = (f(7), 3);\n    return t.0;\n}\nsyscall(60, m());\n"
refused r08m "$LP" "R8m: \`h.p = (f(7), 3);\`" "${SE}struct HQ { a; p: (i64, i64); }\nfn m(): i64 {\n    var h: HQ;\n    h.p = (f(7), 3);\n    return h.p.0;\n}\nsyscall(60, m());\n"
refused r08n "$LP" "R8n: a literal argument \`take((f(7), 2))\`" "${SE}fn take(t: (i64, i64)): i64 { return t.0; }\nfn m(): i64 { return take((f(7), 2)); }\nsyscall(60, m());\n"
refused r08o "$LP" "R8o: a declaration-zone global \`var G = (f(7), 3);\`" "${SE}var G = (f(7), 3);\nsyscall(60, G.0);\n"
exits r08p 73 "R8p: \`(f(x)?, 3)\` in a pair-returning fn — \`?\` consumes the pair" "${SE}fn g(x) {\n    var t = (f(x)?, 3);\n    return Ok(t.0 * 10 + t.1);\n}\nfn m(): i64 {\n    var tag, val = g(7);\n    return val;\n}\nsyscall(60, m());\n"

# R9 — a literal anywhere outside the five accepting positions: refused by name, once, the parse in step.
S9="a tuple \`( .. )\` is a value only as a \`var\` initializer, assigned to a tuple variable or field, as a tuple argument, or after \`return\` - here one value is expected"
TG="${P}struct HP { a; q: P; }\nfn g(x): i64 { return x; }\nfn tp(p: P): i64 { return p.a; }\n${TL}"
refused r09a "$S9" "R9a: an operand \`(1, 2) + 3\`" "${TG}    var x = (1, 2) + 3;${TE}"
refused r09b "$S9" "R9b: an untyped parameter's argument \`g((1, 2))\`" "${TG}    return g((1, 2));${TE}"
refused r09c "a tuple literal is passed only to a tuple parameter - this parameter of 'tp' is not a tuple" "R9c: a struct parameter's argument" "${TG}    return tp((1, 2));${TE}"
refused r09d "a tuple literal cannot initialize 'k' - its declared type is not a tuple" "R9d: \`var k: i64 = (1, 2);\` (k still declared)" "${TG}    var k: i64 = (1, 2);\n    return k;${TE}"
refused r09e "a tuple literal cannot initialize 'k' - its declared type is not a tuple" "R9e: a struct annotation" "${TG}    var k: P = (1, 2);\n    return k.a;${TE}"
refused r09f "a tuple literal cannot initialize 'k' - its declared type is not a tuple" "R9f: a bool annotation" "${TG}    var k: bool = (1, 2);${TE}"
refused r09g "a tuple literal cannot initialize 's' - its declared type is not a tuple" "R9g: a slice annotation" "${TG}    var s: [u8] = (1, 2);${TE}"
refused r09h "$S9" "R9h: \`(1, 2).0\`" "${TG}    var x = (1, 2).0;${TE}"
refused r09i "$S9" "R9i: an if-expression branch" "${TG}    var x = if (t.0 == 1) { (1, 2) } else { 0 };${TE}"
refused r09j "unexpected '('" "R9j: an expression statement \`(1, 2);\` keeps its error" "${TG}    (1, 2);${TE}"
refused r09k "cannot assign a tuple literal to 'p' - it is not a tuple" "R9k: into a struct variable" "${TG}    var p: P;\n    p = (1, 2);${TE}"
refused r09l "$S9" "R9l: into a scalar variable \`x = (1, 2);\`" "${TG}    var x = 0;\n    x = (1, 2);${TE}"
refused r09m "$S9" "R9m: \`callptr(fp, (1, 2))\`" "${TG}    var fp = &g;\n    return callptr(fp, (1, 2));${TE}"
# R9n / R9s (B4 review): the stray literal just inside `return`'s own parentheses names the return's spelling —
# the general text lists "after `return`" as a place a literal goes, which this shape is not.
RR="a multi-value return is written \`return (a, b);\` - drop the extra parentheses"
refused r09n "$RR" "R9n: \`return ((1, 2));\` (a multi-value return keeps its exact spelling)" "fn mk(): (i64, i64) { return ((1, 2)); }\nfn f(): i64 {\n    var a, b = mk();\n    return a;\n}\nsyscall(60, f());\n"
refused r09s "$RR" "R9s: \`return (((1, 2)));\` (any depth)" "fn mk(): (i64, i64) { return (((1, 2))); }\nsyscall(60, 0);\n"
refused r09t "$S9" "R9t: \`return ((1, 2), 3);\` — a nested literal ELEMENT keeps the general text" "fn mk(): (i64, i64, i64) { return ((1, 2), 3); }\nsyscall(60, 0);\n"
refused r09o "cannot store a tuple literal into field 'q' - it is not a tuple" "R9o: into a struct field of another type" "${TG}    var h: HP;\n    h.q = (1, 2);${TE}"
refused r09p "$S9" "R9p: into a scalar field" "${TG}    var h: HP;\n    h.a = (1, 2);${TE}"
refused r09q "$S9" "R9q: a struct-literal element \`P { (1, 2), 3 }\`" "${TG}    var h = P { (1, 2), 3 };${TE}"
refused r09r "$S9" "R9r: a \`match\` scrutinee" "${TG}    match (1, 2) { 1 => { return 1; } _ => { return 0; } }${TE}"

# R10 — at top level an assignment, field store or argument has no frame for the literal's temp.
refused r10a "a tuple literal assigned at top level has no frame to be built in - assign 'G' inside a fn" "R10a: \`G = (3, 4);\` at top level" 'var G: (i64, i64) = (1, 2);\nG = (3, 4);\nsyscall(60, G.0);\n'
refused r10b "a tuple literal argument at top level has no frame to be built in - call 'take' inside a fn" "R10b: \`take((1, 2))\` at top level" 'fn take(t: (i64, i64)): i64 { return t.0; }\nsyscall(60, take((1, 2)));\n'
refused r10c "a tuple literal stored at top level has no frame to be built in - store it into 'p' inside a fn" "R10c: \`GH.p = (5, 6);\` at top level" "${TH}var GH = H { 1, 2, 3, 4 };\nGH.p = (5, 6);\nsyscall(60, GH.a);\n"

# PW — every `_pwrap_k` caller that can see a literal gives a NAMED outcome, never "expected ')'":
# `_asg_paren`, `_fsc_paren`, `_sarg_paren` (accept: S1; refuse: R9k R9o R9c wrapped below),
# `_gci_src` / `_gci_take` (the zone fold claims first: S1), `_sci_pname` / `_scv_peel` (`_tup_var`
# claims first), `_ret_peel` (both struct-return classes) and `_ret_expr_head`, `_op_big_arm` /
# `_op_rhs_pair_call` (an operator's right operand: the factor's refusal).
B3='struct B3 { a; b; c; }\n'
refused pw1 "cannot assign a tuple literal to 'p' - it is not a tuple" "PW1: \`p = ((1, 2));\`, a struct variable (_asg_paren)" "${TG}    var p: P;\n    p = ((1, 2));${TE}"
refused pw2 "cannot store a tuple literal into field 'q' - it is not a tuple" "PW2: \`h.q = ((1, 2));\` (_fsc_paren)" "${TG}    var h: HP;\n    h.q = ((1, 2));${TE}"
refused pw3 "a tuple literal is passed only to a tuple parameter - this parameter of 'tp' is not a tuple" "PW3: \`tp(((1, 2)))\` (_sarg_paren)" "${TG}    return tp(((1, 2)));${TE}"
refused pw4 "a tuple literal cannot initialize 'k' - its declared type is not a tuple" "PW4: \`var k: P = ((1, 2));\` (_scv_peel / _sci_pname)" "${TG}    var k: P = ((1, 2));\n    return k.a;${TE}"
refused pw5 "$RR" "PW5: \`return ((1, 2));\` from a 16-byte \`: P\` fn (_ret_peel, the pair class)" "${P}fn mk(): P { return ((1, 2)); }\nfn f(): i64 {\n    var p: P = mk();\n    return p.a;\n}\nsyscall(60, f());\n"
refused pw6 "struct-return fn: return must be a bare local identifier" "PW6: \`return ((1, 2));\` from a 24-byte \`: B3\` fn (_ret_peel, the retptr class: its own refusal)" "${B3}fn mk(): B3 { return ((1, 2)); }\nfn f(): i64 {\n    var p: B3 = mk();\n    return p.a;\n}\nsyscall(60, f());\n"
refused pw7 "$RR" "PW7: \`return ((1, 2)) + 1;\` (_ret_expr_head)" 'fn mk(): i64 { return ((1, 2)) + 1; }\nsyscall(60, mk());\n'
refused pw8 "$S9" "PW8: \`p + (1, 2)\`, a by-value struct operand (_op_big_arm)" "${P}fn P_add(a: P, b: P): P {\n    var r: P;\n    r.a = a.a + b.a;\n    r.b = a.b + b.b;\n    return r;\n}\nfn f(): i64 {\n    var p = P { 1, 2 };\n    var q = p + (1, 2);\n    return q.a;\n}\nsyscall(60, f());\n"
refused pw9 "$S9" "PW9: \`p + ((1, 2))\` into a tuple operand (_op_rhs_pair_call)" "${P}fn P_add(a: P, b: (i64, i64)): P {\n    var r: P;\n    r.a = a.a + b.0;\n    r.b = a.b + b.1;\n    return r;\n}\nfn f(): i64 {\n    var p = P { 1, 2 };\n    var q = p + ((1, 2));\n    return q.a;\n}\nsyscall(60, f());\n"

# SEC — `secret var t = (..);` is wiped at the epilogue, all 8n bytes (the struct rule: the slot delta
# PARSE_VAR's literal reserved). The frame-reuse scan of tests/tcyr/lang/secret.tcyr; the plain control
# proves the scan sees a survivor. (Measured on aarch64 / cx / PE too, 2026-10-09.)
exits sec1 0 "SEC1: \`secret var t = (S, S, S, S);\` and \`secret var w: (i64, i64) = (..);\` leave nothing on the stack" 'var SEC = 0x5EC5EC5EC5EC5EC5;\nfn write_secret(): i64 {\n    secret var t = (SEC, SEC, SEC, SEC);\n    var u: (i64, i64) = (t.0 + 1, t.3 + 1);\n    secret var w: (i64, i64) = (u.1 - 1, SEC);\n    return 0;\n}\nfn write_plain(): i64 {\n    var t = (SEC, SEC, SEC, SEC);\n    var w: (i64, i64) = (t.1, SEC);\n    return 0;\n}\nfn scan_for_secret(): i64 {\n    var window: i64[64];\n    var found = 0;\n    var i = 0;\n    while (i < 64) {\n        if (load64(&window + i * 8) == SEC) { found = found + 1; }\n        i = i + 1;\n    }\n    return found;\n}\nfn f(): i64 {\n    write_secret();\n    var a = scan_for_secret();\n    write_plain();\n    var b = scan_for_secret();\n    if (a != 0) { return 10 + a; }\n    if (b == 0) { return 99; }\n    return 0;\n}\nsyscall(60, f());\n'

# AS — a literal local in a SUSPENDING `async fn` (CYRIUS_ASYNC=1), read and re-assigned across awaits:
# the block's span is recorded before its first store and every store is addressed, so the coroutine's
# heap frame (whose slots ascend, `_ECORO_AGG_OFF`) holds it whole.
printf '#!/bin/sh\nCYRIUS_ASYNC=1 exec "%s" "$@"\n' "$CC" > "$T/acc4"; chmod +x "$T/acc4"
CC_SV=$CC; CC="$T/acc4"
exits as1 0 "AS1: \`var t = (5, 6, 7);\` in a suspending async fn, \`t = (t.2, t.0, b);\` between awaits" 'include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/async.cyr"\nstruct P2 { x; y; }\nfn nopark(): i64 { return 0; }\nasync fn steps(C): i64 {\n    var a = 3;\n    var t = (5, 6, 7);\n    var p = P2 { 1, 2 };\n    var b = 4;\n    var s1 = await nopark();\n    t = (t.2, t.0, b);\n    var s2 = await nopark();\n    return t.0 * 1000 + t.1 * 100 + t.2 * 10 + a + p.y * 10000;\n}\nfn main(): i64 {\n    alloc_init();\n    var C = steps(0);\n    var r1 = future_force(C);\n    var r2 = future_force(C);\n    var r3 = future_force(C);\n    if (r3 != 27543) { syscall(60, 1); }\n    syscall(60, 0);\n    return 0;\n}\nvar e = main();\n'
CC=$CC_SV

# ── T5: the bridge — a tuple CAPTURES a multi-value call by its type, `return t;`, `a, b = f();` ────
# The positive shapes (every callee class, `t = f()`, a for step, both global zones, `return t;` from a
# local / parameter / global / defer fn / loop / #inline replay, `a, b = f()` everywhere, the re-poll
# loop) are tests/tcyr/crossos/tuple_values.tcyr's `capture` / `returns` / `reassign` (the A rows).
MK='fn mk(a): (i64, i64) { return (a, a + 1); }\n'
MF='fn mkf(a): (i64, f64) { return (a, 1.5); }\n'
F5='fn f(): i64 {\n'
F5V='fn f(): i64 {\n    var a = 0;\n    var b = 0;\n'
E5='\n    return 0;\n}\nsyscall(60, f());\n'
CAP="cannot capture '"
# R14 — `return t;` from a fn that does not declare those values: refused by name (it was the value refusal).
RT="cannot return tuple 't' (i64, i64)"
RTD=" - a tuple is returned by a fn declared with its values, \`: (i64, i64)\`"
TL5='    var t = (1, 2);\n    return t;\n}\n'
refused r14a "$RT$RTD" "R14a (S6): an undeclared fn's \`return t;\`, refused once" "fn g() {\n${TL5}syscall(60, g());\n"
refused r14b "$RT$RTD" "R14b: a scalar fn" "fn g(): i64 {\n${TL5}syscall(60, g());\n"
refused r14c "$RT$RTD" "R14c: an 8-byte struct fn (its value class)" "struct Q { a; }\nfn g(): Q {\n${TL5}syscall(60, 0);\n"
refused r14d "is returned in two registers, so \`return\` takes a local of that struct or a call returning it" "R14d: a 9-16 B struct fn: its own class refuses \`t\` (once)" "${P}fn g(): P {\n${TL5}syscall(60, 0);\n"
refused r14e "struct-return: identifier type != fn ret_sid" "R14e: a retptr struct fn: \`_ret_struct_big\` reports first" "struct P3 { a; b; c; }\nfn g(): P3 {\n    var t = (1, 2, 3);\n    return t;\n}\nsyscall(60, 0);\n"
refused r14f "$RT$RTD" "R14f: a vector fn" "fn g(): f64v2 {\n${TL5}syscall(60, 0);\n"
refused r14g "$RT from 'g' - it returns (i64, i64, i64)" "R14g: an arity mismatch" "fn g(): (i64, i64, i64) {\n${TL5}syscall(60, 0);\n"
refused r14h "$RT from 'g' - it returns (i64, f64)" "R14h: an element class mismatch (i64 / f64)" "fn g(): (i64, f64) {\n${TL5}syscall(60, 0);\n"
refused r14i "$RT from 'g' - it returns (bool, i64)" "R14i: an i64 element into a declared bool value" "fn g(): (bool, i64) {\n${TL5}syscall(60, 0);\n"
refused r14j "cannot return tuple 't' (bool, i64) from 'g' - it returns (i64, i64)" "R14j: a bool element into a declared i64 value (classes match exactly)" "fn g(): (i64, i64) {\n    var t: (bool, i64) = (true, 2);\n    return t;\n}\nsyscall(60, 0);\n"
refused r14k "tuple 't' used as a value" "R14k: a closure's \`return t;\` of a captured tuple: the value refusal" "include \"lib/alloc.cyr\"\nfn g(): i64 {\n    var t = (1, 2);\n    var c = fncall0(|| { return t; });\n    return c;\n}\nsyscall(60, 0);\n"
refused r14l "cannot return tuple 'u' (i64, i64)$RTD" "R14l: a closure's own tuple local" "include \"lib/alloc.cyr\"\nfn g(): i64 {\n    var c = fncall0(|| { var u = (3, 4); return u; });\n    return c;\n}\nsyscall(60, 0);\n"
refused r14n "tuple field 'p' used as a value" "R14n: \`return h.p;\` (a tuple field)" "struct H { a; p: (i64, i64); }\nfn g(): (i64, i64) {\n    var h: H;\n    return h.p;\n}\nsyscall(60, 0);\n"
refused r14o "cannot return tuple 'G' (i64, i64)$RTD" "R14o: a tuple global from a scalar fn" "var G = (1, 2);\nfn g(): i64 { return G; }\nsyscall(60, g());\n"
# R14q / R14r (B4 review): a tuple of 4 or more is returned by no fn — the advice to declare its values led
# to a second refusal ("multi-value return needs 2 or 3 types").
R4V=" - a fn returns at most 3 values: return its elements, or pass the tuple to a parameter"
refused r14q "cannot return tuple 't' (i64, i64, i64, i64)$R4V" "R14q: a 4-element tuple from an undeclared fn" "fn g() {\n    var t = (1, 2, 3, 4);\n    return t;\n}\nsyscall(60, 0);\n"
refused r14r "cannot return tuple 't' (i64, i64, i64, i64, i64)$R4V" "R14r: ... a 5-element one from a scalar fn" "fn g(): i64 {\n    var t = (1, 2, 3, 4, 5);\n    return t;\n}\nsyscall(60, 0);\n"
printf '#!/bin/sh\nCYRIUS_ASYNC=1 exec "%s" "$@"\n' "$CC" > "$T/acc5"; chmod +x "$T/acc5"
CC_SV=$CC; CC="$T/acc5"
# R14m: 6.7.11 — a declared multi-value `async fn` is refused at its declaration, once (its `return t;`
# agrees with it), tests/gates/frontend/async_multi_value_return_refused.sh
refused r14m "\`async fn g\` returns 2 values, and a Future carries one i64 - return a pointer to a struct holding them" "R14m: an \`async fn\` declared \`: (i64, i64)\` (its Future carries one i64)" "include \"lib/alloc.cyr\"\nasync fn g(): (i64, i64) {\n${TL5}syscall(60, 0);\n"
refused r14p "$RT from an \`async fn\` - it returns one value" "R14p: an undeclared \`async fn\`" "include \"lib/alloc.cyr\"\nasync fn g() {\n${TL5}syscall(60, 0);\n"
CC=$CC_SV
# R15 — `f().N` on a multi-value call: today's refusal plus how to read the values.
R15="cannot take a field of the result of 'mk': it returns 2 values - bind them first, \`var t: (i64, i64) = mk(..);\`, then read \`t.0\`"
refused r15a "$R15" "R15a: \`return mk(1).0;\`" "${MK}fn f(): i64 { return mk(1).0; }\nsyscall(60, f());\n"
refused r15b "$R15" "R15b: in an operand" "${MK}fn f(): i64 { var x = mk(1).0 + 1; return x; }\nsyscall(60, f());\n"
refused r15c "it returns 2 values - bind them first, \`var t: (i64, f64) = B_mk(..);\`" "R15c: a method's result (its declared values spelled)" "struct B { v; }\nimpl B { fn mk(self, a): (i64, f64) { return (a, 1.5); } }\nfn f(): i64 { var b: B; return b.mk(1).1; }\nsyscall(60, f());\n"
# R16 — a capture refused, mirroring the destructure. Its own texts for a callee class or element that
# disagrees; a one-value callee, \`f()?\` or any other value is no capture at all — the tuple's "not a tuple"
# refusal (R12). (\`callptr\` was R16o until 6.7.14: R16cp. A wrapped call was R16l / R16q until 6.7.14: R16pw.)
refused r16a "${CAP}mkf' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16a: an f64 value into an i64 element" "${MK}${MF}${F5}    var t: (i64, i64) = mkf(1);${E5}"
refused r16b "${CAP}mk' into tuple (f64, f64) - it returns 2 values, (i64, i64)" "R16b: an i64 value into an f64 element" "${MK}${F5}    var t: (f64, f64) = mk(1);${E5}"
refused r16c "${CAP}mk' into tuple (bool, i64) - it returns 2 values, (i64, i64)" "R16c: a non-bool value into a bool element" "${MK}${F5}    var t: (bool, i64) = mk(1);${E5}"
refused r16d "${CAP}mk' into tuple (i64, i64, i64) - it returns 2 values, (i64, i64)" "R16d: a declared-arity mismatch (3 from 2)" "${MK}${F5}    var t: (i64, i64, i64) = mk(1);${E5}"
refused r16e "${CAP}mk3' into tuple (i64, i64) - it returns 3 values, (i64, i64, i64)" "R16e: ... (2 from 3)" "fn mk3(a): (i64, i64, i64) { return (a, a, a); }\n${F5}    var t: (i64, i64) = mk3(1);${E5}"
refused r16f "${CAP}mk' into tuple (i64, i64, i64, i64) - a call returns at most 3 values" "R16f: 4 or more elements" "${MK}${F5}    var t: (i64, i64, i64, i64) = mk(1);${E5}"
refused r16g "${CAP}mkp' into tuple (i64, i64) - it returns struct 'P', not a tuple" "R16g: a struct-returning callee" "${P}fn mkp(): P { var p: P; p.a = 1; p.b = 2; return p; }\n${F5}    var t: (i64, i64) = mkp();${E5}"
refused r16h "${CAP}vv' into tuple (i64, i64) - it returns a vector, not a tuple" "R16h: a vector-returning callee" "fn vv(): f64v2 { var v: f64v2; return v; }\n${F5}    var t: (i64, i64) = vv();${E5}"
refused r16i "${CAP}mf2' into tuple (i64, f64) - it is declared \`: f64\`, so every value it returns is an f64" "R16i: a \`: f64\` callee into an i64 element" "fn mf2(a): f64 { ret2(a, a); }\n${F5}    var t: (i64, f64) = mf2(1);${E5}"
refused r16j "${CAP}dm' into tuple (bool, i64) - element 0 is a bool, and the call does not declare that value bool" "R16j: an undeclared callee into a bool element" "fn dm(a, b) { return (a / b, a % b); }\n${F5}    var t: (bool, i64) = dm(1, 2);${E5}"
refused r16k "$I12 't' with a value that is not a tuple" "R16k: a provably one-value callee (the R12 refusal)" "fn one(x) { return x; }\n${F5}    var t: (i64, i64) = one(1);${E5}"
exits4 r16l 12 "R16l: a wrapped call \`(mk(1))\` captures (6.7.14, D45: it was R12)" "${MK}fn f(): i64 {\n    var t: (i64, i64) = (mk(1));\n    return t.0 * 10 + t.1;\n}\nsyscall(60, f());\n"
refused r16m "$I12 't' with a value that is not a tuple" "R16m: \`f()?\` (one value)" "enum Res: stack { Ok(v); Err(e); }\nfn sok(x) { return Ok(x); }\nfn g(): i64 { var t: (i64, i64) = sok(1)?; return Ok(t.0); }\nsyscall(60, 0);\n"
refused r16n "$I12 't' with a value that is not a tuple" "R16n: a call that is not the whole value" "${MK}${F5}    var t: (i64, i64) = mk(1) + 1;${E5}"
refused r16p "${CAP}mkf' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16p: \`t = f();\` into an existing tuple" "${MK}${MF}${F5}    var t: (i64, i64);\n    t = mkf(1);${E5}"
exits4 r16q 12 "R16q: \`t = (mk(1));\`, wrapped, captures (6.7.14, D45: it was R12)" "${MK}fn f(): i64 {\n    var t: (i64, i64);\n    t = (mk(1));\n    return t.0 * 10 + t.1;\n}\nsyscall(60, f());\n"
refused r16r "${CAP}mk' into tuple (i64, f64) - it returns 2 values, (i64, i64)" "R16r: a declaration-zone capture (the replay judges the callee)" "${MK}var G: (i64, f64) = mk(1);\nsyscall(60, 0);\n"
refused r16s "$I12 'G' with a value that is not a tuple" "R16s: a zone capture of a one-value callee (pass 1 registered it inline)" "fn one(x) { return x; }\nvar G: (i64, i64) = one(1);\nsyscall(60, 0);\n"
refused r16t "${CAP}mk' into tuple (i64, i64, i64) - it returns 2 values, (i64, i64)" "R16t: a global capture after the first statement" "${MK}syscall(1, 1, \"\", 0);\nvar G: (i64, i64, i64) = mk(1);\nsyscall(60, 0);\n"
refused r16u "$A12 'G'" "R16u: \`G = mk(2) + 1;\` at top level (R12)" "${MK}var G: (i64, i64) = mk(1);\nG = mk(2) + 1;\nsyscall(60, 0);\n"
refused r16v "${CAP}mk' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16v: a method's declared values" "struct B { v; }\nimpl B { fn mk(self, a): (i64, f64) { return (a, 1.5); } }\n${F5}    var b: B;\n    var t: (i64, i64) = b.mk(1);${E5}"
refused r16w "${CAP}mk' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16w: a classic-for step \`t = mk(i)\`" "${MF}fn mk(a): (i64, f64) { return (a, 0.5); }\n${F5}    var t: (i64, i64);\n    for (var i = 0; i < 2; t = mk(i)) { i = i + 1; }${E5}"
# R16x (6.7.11) — a callee whose body ends in an infinite loop no \`break\` leaves is provably one value too
# (\`_body_ends_in_loop\`): the R12 refusal, where it captured a stale second register.
refused r16x "$I12 't' with a value that is not a tuple" "R16x: a callee ending in \`loop { return x; }\` (6.7.11: one value, R12)" "fn one(x) { loop { return x; } }\n${F5}    var t: (i64, i64) = one(1);${E5}"
refused r16xt "$I12 't' with a value that is not a tuple" "R16x-true: a callee ending in \`while (true) { return x; }\` (6.7.13, D27 A)" "fn one(x) { while (true) { return x; } }\n${F5}    var t: (i64, i64) = one(1);${E5}"
# R16y-R16ab (6.7.11) — an UNDECLARED callee whose every \`return\` is \`(..)\` of one arity returns that many
# values (pass 1, \`_prescan_ret_arity\`): a capture of another count is refused as a declared one is (it took
# a stale r8 / dropped one); the matching count still captures.
DMU='fn dm(a, b) { return (a / b, a % b); }\n'
refused r16y "${CAP}dm' into tuple (i64, i64, i64) - it returns 2 values" "R16y: 3 from an undeclared 2 (6.7.11)" "${DMU}${F5}    var t: (i64, i64, i64) = dm(17, 5);${E5}"
refused r16z "${CAP}h3' into tuple (i64, i64) - it returns 3 values" "R16z: 2 from an undeclared 3" "fn h3(a) { return (a, a + 1, a + 2); }\n${F5}    var t: (i64, i64) = h3(1);${E5}"
refused r16aa "${CAP}dm' into tuple (i64, i64, i64) - it returns 2 values" "R16aa: a declaration-zone capture" "${DMU}var G: (i64, i64, i64) = dm(17, 5);\nsyscall(60, 0);\n"
refused r16ab "${CAP}dm' into tuple (i64, i64, i64) - it returns 2 values" "R16ab: \`t = dm(..);\` into an existing tuple" "${DMU}${F5}    var t: (i64, i64, i64);\n    t = dm(17, 5);${E5}"
exits r16ac 32 "R16ac: \`var t: (i64, i64) = dm(17, 5);\` (the matching count) still captures" "${DMU}fn f(): i64 {\n    var t: (i64, i64) = dm(17, 5);\n    return t.0 * 10 + t.1;\n}\nsyscall(60, f());\n"
# R16ad (6.7.11) — the triage's capture of a declared \`: (i64, i64)\` fn that returns ONE value: its \`u.1\` was
# a stale rdx; the fn itself is refused now (a fn declared with its values returns them).
refused r16ad "'f1' returns 2 values - return (a, b)" "R16ad: \`var u: (i64, i64) = f1();\`, \`f1\` declared \`: (i64, i64)\` returning \`2\`" "fn f1(): (i64, i64) { return 2; }\n${F5}    var u: (i64, i64) = f1();${E5}"
# R16r2 (6.7.14, D42, the user's decision of 2026-10-16) — `ret2(a, b)` is two values to pass 1's count
# (issues/archived/2026-10-15-ret2-body-not-counted-three-names-read-stale-register.md): a 3-tuple capture of a fn left only
# through `ret2(..);` / `return ret2(..);` is refused as R16y's `return (a, b);` fn is (`t.2` read the seeded 88 on
# every target); the 2-tuple capture still runs. Mutations (scratch trees, run 2026-10-17): the tree before
# (c4930b46) -> R16r2a-R16r2d BUILD on every leg; `_prescan_ret_arity`'s ret2 arm back to the bail, or `_ar_exits`
# without its `ret2(..);` tail -> R16r2a, R16r2c, R16r2d BUILD; `_ret_stmt_arity` without its ret2 arm -> R16r2b.
H88='fn h(): (i64, i64, i64) { return (1, 77, 88); }\n'
refused4 r16r2a "${CAP}g2' into tuple (i64, i64, i64) - it returns 2 values" "R16r2a: the issue's 3-tuple capture of a \`ret2(1, 2);\` fn" "${H88}fn g2() { ret2(1, 2); }\nfn main(): i64 { var x, y, w = h(); var t: (i64, i64, i64) = g2(); return t.2; }\nsyscall(60, main());\n"
refused4 r16r2b "${CAP}g2' into tuple (i64, i64, i64) - it returns 2 values" "R16r2b: ... of \`return ret2(1, 2);\` in a \`: i64\` fn" "${H88}fn g2(): i64 { return ret2(1, 2); }\nfn main(): i64 { var x, y, w = h(); var t: (i64, i64, i64) = g2(); return t.2; }\nsyscall(60, main());\n"
refused4 r16r2c "${CAP}g2' into tuple (i64, i64, i64) - it returns 2 values" "R16r2c: a declaration-zone capture" "fn g2(x) { ret2(x, 1); }\nvar G: (i64, i64, i64) = g2(4);\nsyscall(60, 0);\n"
refused4 r16r2d "${CAP}g2' into tuple (i64, i64, i64) - it returns 2 values" "R16r2d: \`t = g2(..);\` into an existing 3-tuple" "fn g2(x) { ret2(x, 1); }\n${F5}    var t: (i64, i64, i64);\n    t = g2(4);${E5}"
exits4 r16r2e 41 "R16r2e: \`var t: (i64, i64) = g2(4);\` (the matching count) still captures" "fn g2(x) { ret2(x, 1); }\nfn main(): i64 { var t: (i64, i64) = g2(4); return t.0 * 10 + t.1; }\nsyscall(60, main());\n"
# R16cp (6.7.14) — \`callptr(fp, ..)\` IS A CALL TO THE CAPTURE, as to the destructure since 6.7.13 (\`_dt_call_open_cp\`;
# issues/archived/2026-10-15-tuple-capture-of-callptr-refused.md): its callee is unknown, so its count is not judged — as for
# \`fncallN\`, its lowering, which already captured. Each spelling was R12 "not a tuple" on every target (R16o until
# 6.7.14). Mutations (scratch trees, the gate run from each, every leg; run 2026-10-17): the tree before (0d0a054d) ->
# R16cpa-R16cpf refused, R16cpj R16cpk the R12 text, A1-A7 (TV_CP); \`_tup_cap_check\` back to \`_dt_call_open\` ->
# R16cpa-R16cpf, R16cpj, R16cpk, A1-A7; \`_tup_gci_call\` back, or \`_gvi_cap_tok\` without its \`callptr\` arm -> R16cpb,
# A1-A7; \`_tup_asg\` without its \`callptr\` arm -> R16cpd, R16cpe, A1-A7; \`_tcap_callee_pr\` without it -> R16cpj,
# R16cpk (no callee named).
CPT='fn two(a): (i64, i64) { return (a, a + 1); }\n'
exits4 r16cpa 6 "R16cpa: the issue's \`var t: (i64, i64) = callptr(fp, 5);\` verbatim" "${CPT}fn main(): i64 {\n    var fp = &two;\n    var t: (i64, i64) = callptr(fp, 5);\n    return t.1;\n}\nsyscall(60, main());\n"
exits4 r16cpb 56 "R16cpb: a declaration-zone \`var G: (i64, i64) = callptr(fp, 5);\`" "${CPT}var fp = &two;\nvar G: (i64, i64) = callptr(fp, 5);\nsyscall(60, G.0 * 10 + G.1);\n"
exits4 r16cpc 56 "R16cpc: ... a global after the first statement" "${CPT}var fp = &two;\nsyscall(1, 1, \"\", 0);\nvar G: (i64, i64) = callptr(fp, 5);\nsyscall(60, G.0 * 10 + G.1);\n"
exits4 r16cpd 6 "R16cpd: \`t = callptr(fp, 5);\` into an existing tuple" "${CPT}fn main(): i64 {\n    var fp = &two;\n    var t: (i64, i64);\n    t = callptr(fp, 5);\n    return t.1;\n}\nsyscall(60, main());\n"
exits4 r16cpe 112 "R16cpe: \`G = callptr(fp, 5);\` at top level, and a classic-for step \`t = callptr(fp, i)\`" "${CPT}var fp = &two;\nvar G: (i64, i64) = (0, 0);\nG = callptr(fp, 5);\nfn f(): i64 {\n    var t: (i64, i64);\n    for (var i = 0; i < 2; t = callptr(fp, i)) { i = i + 1; }\n    return t.0 * 10 + t.1;\n}\nsyscall(60, G.0 * 10 + G.1 + f() + 33);\n"
exits4 r16cpf 67 "R16cpf: a 3-tuple through \`callptr\`" "fn three(a): (i64, i64, i64) { return (a, a + 1, a + 2); }\nfn main(): i64 {\n    var fp = &three;\n    var t: (i64, i64, i64) = callptr(fp, 5);\n    return t.0 * 100 + t.1 * 10 + t.2;\n}\nsyscall(60, main() - 500);\n"
refused4 r16cpg "$I12 't' with a value that is not a tuple" "R16cpg: \`callptr(fp, 5) + 1\` is no capture (R12)" "${CPT}fn main(): i64 {\n    var fp = &two;\n    var t: (i64, i64) = callptr(fp, 5) + 1;\n    return t.1;\n}\nsyscall(60, main());\n"
refused4 r16cph "$A12 't'" "R16cph: ... \`t = callptr(fp, 5) + 1;\`" "${CPT}fn main(): i64 {\n    var fp = &two;\n    var t: (i64, i64) = (0, 0);\n    t = callptr(fp, 5) + 1;\n    return t.1;\n}\nsyscall(60, main());\n"
refused4 r16cpi "$I12 'G' with a value that is not a tuple" "R16cpi: ... a declaration-zone \`= callptr(fp, 5) + 1;\`" "${CPT}var fp = &two;\nvar G: (i64, i64) = callptr(fp, 5) + 1;\nsyscall(60, G.1);\n"
refused4 r16cpj "${CAP}callptr' into tuple (bool, i64) - element 0 is a bool, and the call does not declare that value bool" "R16cpj: an unknown callee into a bool element (as \`fncall1\`'s)" "${CPT}fn main(): i64 {\n    var fp = &two;\n    var t: (bool, i64) = callptr(fp, 5);\n    return t.1;\n}\nsyscall(60, main());\n"
refused4 r16cpk "${CAP}callptr' into tuple (i64, i64, i64, i64) - a call returns at most 3 values" "R16cpk: 4 elements" "${CPT}fn main(): i64 {\n    var fp = &two;\n    var t: (i64, i64, i64, i64) = callptr(fp, 5);\n    return t.1;\n}\nsyscall(60, main());\n"
# R16pw (6.7.14, D45, the user's decision of 2026-10-16) — PARENTHESES AROUND THE WHOLE CALL ARE TRANSPARENT to the
# capture, as to the destructure (destructure_one_value_refused.sh axis 8) and every other consumer of a whole call
# (issues/archived/2026-10-15-paren-wrapped-call-destructure-refused.md: \`var t: (i64, i64) = (two(3));\` was "not a tuple" on
# x86_64 / aarch64 / cx / PE). \`_tup_cap_check\` steps into k parentheses wrapping ONE call (\`_dt_wrap_k\`) and the
# caller closes them after the call (\`_tcap_k\`), so the capture compiles as the unwrapped one does. Still refused
# by their own texts: a wrapped one-value callee (R12), a class disagreement (at the call), a wrap holding more than
# the call or followed by more (R12). Mutations (scratch trees, the gate run from each, every leg, run 2026-10-17):
# the tree before (79b72c77) -> R16l, R16q, R19d, ZG4, R16pwa-R16pwh refused, R16pwj R16pwm R16pwo the R12 text,
# A1-A7; \`_dt_wrap_k\` answering 0 -> the same less the assignments (R16q, R16pwd, R16pwe, R16pwo: \`_asg_paren\`
# peels those); \`_tup_cap_check\` without its \`_dt_wrap_in\` -> R16l, R16pwa-R16pwc, R16pwf-R16pwh, R16pwj, R16pwm,
# ZG4, A1-A7; \`_tup_gci_call\` without its wrap arm, or \`_gvi_cap_tok\` without it -> ZG4, R16pwb, R16pwm, A1-A7;
# \`_tup_var_cap\` without its \`_pw_close\` -> R16l, R16pwa, R16pwc, R16pwf-R16pwh, A1-A7; \`_gvi_tup_cap\` without
# it -> ZG4, R16pwb, A1-A7; the 6.7.7 \`_asg_wrapd\` guard back in \`_tup_asg_call\` -> R16q, R16pwd, R16pwe,
# R16pwo, A1-A7.
PWT='fn two(x): (i64, i64) { return (x, x + 1); }\n'
exits4 r16pwa 34 "R16pwa: the issue's capture \`var t: (i64, i64) = (two(3));\`" "${PWT}fn f(): i64 {\n    var t: (i64, i64) = (two(3));\n    return t.0 * 10 + t.1;\n}\nsyscall(60, f());\n"
exits4 r16pwb 34 "R16pwb: a declaration-zone \`var G: (i64, i64) = (two(3));\`" "${PWT}var G: (i64, i64) = (two(3));\nsyscall(60, G.0 * 10 + G.1);\n"
exits4 r16pwc 34 "R16pwc: ... after the first statement, \`((two(3)))\`" "${PWT}syscall(1, 1, \"\", 0);\nvar G: (i64, i64) = ((two(3)));\nsyscall(60, G.0 * 10 + G.1);\n"
exits4 r16pwd 79 "R16pwd: \`t = (two(3));\` in a fn and \`G = ((two(4)));\` at top level" "${PWT}var G: (i64, i64) = (0, 0);\nG = ((two(4)));\nfn f(): i64 {\n    var t: (i64, i64) = (0, 0);\n    t = (two(3));\n    return t.0 * 10 + t.1;\n}\nsyscall(60, f() + G.0 * 10 + G.1);\n"
exits4 r16pwe 23 "R16pwe: a classic-for step \`t = (two(i))\`" "${PWT}fn f(): i64 {\n    var t: (i64, i64);\n    for (var i = 0; i < 2; t = (two(i))) { i = i + 1; }\n    return t.0 * 10 + t.1;\n}\nsyscall(60, f());\n"
exits4 r16pwf 17 "R16pwf: a wrapped \`: stack\` pair captured as the unwrapped one is (tag 1, payload 7)" "enum Res: stack { ROk(v); RErr(e); }\nfn sf(x) { return RErr(x); }\nfn f(): i64 {\n    var t: (i64, i64) = (sf(7));\n    return t.0 * 10 + t.1;\n}\nsyscall(60, f());\n"
exits4 r16pwg 61 "R16pwg: \`(callptr(fp, 5))\`, a method \`(b.mk(4))\` and an explicit generic \`(g<i64>(1))\`" "${PWT}struct B { v; }\nimpl B { fn mk(self, a): (i64, i64) { return (a, a + self.v); } }\nfn g<T>(a: T): (i64, i64) { return (a, a + 1); }\nfn f(): i64 {\n    var fp = &two;\n    var b: B;\n    b.v = 3;\n    var t: (i64, i64) = (callptr(fp, 5));\n    var u: (i64, i64) = (b.mk(4));\n    var w: (i64, i64) = (g<i64>(1));\n    return t.0 * 10 + t.1 - u.0 + u.1 - w.1;\n}\nsyscall(60, f() + 4);\n"
exits4 r16pwh 67 "R16pwh: a 3-tuple \`((three(5)))\`" "fn three(a): (i64, i64, i64) { return (a, a + 1, a + 2); }\nfn f(): i64 {\n    var t: (i64, i64, i64) = ((three(5)));\n    return t.0 * 100 + t.1 * 10 + t.2 - 500;\n}\nsyscall(60, f());\n"
refused4 r16pwi "$I12 't' with a value that is not a tuple" "R16pwi: a wrapped one-value callee \`(one(1))\` (R12, as unwrapped)" "fn one(x) { return x; }\n${F5}    var t: (i64, i64) = (one(1));${E5}"
refused4 r16pwj "3:26: ${CAP}mkf' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16pwj: a class disagreement through the wrap, at the call" "${MF}fn f(): i64 {\n    var t: (i64, i64) = (mkf(1));\n    return t.0;\n}\nsyscall(60, f());\n"
refused4 r16pwk "$I12 't' with a value that is not a tuple" "R16pwk: \`(two(1)) + 1\` and \`(two(1) + 1)\` are values (R12)" "${PWT}${F5}    var t: (i64, i64) = (two(1)) + 1;${E5}"
refused4 r16pwl "$I12 't' with a value that is not a tuple" "R16pwl: ... \`(two(1) + 1)\`" "${PWT}${F5}    var t: (i64, i64) = (two(1) + 1);${E5}"
refused4 r16pwm "2:22: ${CAP}mkf' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16pwm: a declaration-zone class disagreement through the wrap" "${MF}var G: (i64, i64) = (mkf(3));\nsyscall(60, G.0);\n"
refused4 r16pwn "$I12 'G' with a value that is not a tuple" "R16pwn: a declaration-zone wrapped one-value callee (R12)" "fn one(x) { return x; }\nvar G: (i64, i64) = (one(3));\nsyscall(60, G.0);\n"
refused4 r16pwo "${CAP}mkf' into tuple (i64, i64) - it returns 2 values, (i64, f64)" "R16pwo: \`t = (mkf(1));\`, a class disagreement" "${MF}${F5}    var t: (i64, i64) = (0, 0);\n    t = (mkf(1));${E5}"
refused4 r16pwp "$A12 't'" "R16pwp: \`t = (one(1));\` (R12)" "fn one(x) { return x; }\n${F5}    var t: (i64, i64) = (0, 0);\n    t = (one(1));${E5}"
# ZG (B4 review) — THE DECLARATION ZONE READS A GENERIC CALL BY ITS TOKENS. Pass 1 sizes a zone global before
# the fns below it are declared, and read `pk<i64, i64>(..)` with `pk` declared below as a comparison: the comma
# between its type arguments was a tuple comma there and none in the replay. ZG1 / ZG2 compiled before tuples (base
# exit 12) and were refused ("tuple 'G' used as a value"); ZG3 / ZG4 stored one word ((12, 0) / (1, 0)); ZG5 / ZG6
# typed the literal (i64, i64, i64); ZG7 / ZG8 refused a capture the destructure takes. What the token reading
# still gets wrong — a `<` comparison spelled like a type list — is refused by name (ZG10, ZG11), never stored.
ZPK='fn pk<A, B>(a: A, b: B): i64 { return a * 10 + b; }\n'
ZH='var H = 77;\n'
exits zg1 12 "ZG1: \`var G = (pk<i64, i64>(1, 2));\`, \`pk\` declared below, is one value" "var G = (pk<i64, i64>(1, 2));\n${ZH}${ZPK}fn main(): i64 { return G + H - 77; }\nsyscall(60, main());\n"
exits zg2 12 "ZG2: ... \`var G: i64 = (pk<i64, i64>(1, 2));\`" "var G: i64 = (pk<i64, i64>(1, 2));\n${ZH}${ZPK}fn main(): i64 { return G + H - 77; }\nsyscall(60, main());\n"
refused zg3 "$I12 'G' with a value that is not a tuple" "ZG3: \`var G: (i64, i64) = (pk<i64, i64>(1, 2));\`, a wrapped one-value call (it stored (12, 0))" "var G: (i64, i64) = (pk<i64, i64>(1, 2));\n${ZH}${ZPK}fn main(): i64 { return G.0 * 10 + G.1 + H - 77; }\nsyscall(60, main());\n"
exits zg4 12 "ZG4: ... a wrapped multi-value call captures (6.7.14, D45; it stored (1, 0), then was R12)" "var G: (i64, i64) = (pk2<i64, i64>(1, 2));\n${ZH}fn pk2<A, B>(a: A, b: B): (i64, i64) { return (a, b); }\nfn main(): i64 { return G.0 * 10 + G.1 + H - 77; }\nsyscall(60, main());\n"
exits zg5 135 "ZG5: \`var G = (pk<i64, i64>(1, 2), 3);\` is (i64, i64): a tuple argument and a copy" "var G = (pk<i64, i64>(1, 2), 3);\n${ZH}${ZPK}fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }\nfn main(): i64 {\n    var u: (i64, i64) = G;\n    return take(G) + u.0 + H - 77;\n}\nsyscall(60, main());\n"
refused zg6 "unknown field '2' on struct '(i64, i64)'" "ZG6: ... and \`G.2\` names no element" "var G = (pk<i64, i64>(1, 2), 3);\n${ZH}${ZPK}fn main(): i64 {\n    G.2 = 5;\n    return H;\n}\nsyscall(60, main());\n"
exits zg7 56 "ZG7: a capture \`var G: (i64, i64) = g2<i64>(5);\`, \`g2\` declared below" "var G: (i64, i64) = g2<i64>(5);\n${ZH}fn g2<T>(a: T): (i64, i64) { return (a, a + 1); }\nfn main(): i64 { return G.0 * 10 + G.1 + H - 77; }\nsyscall(60, main());\n"
exits zg8 56 "ZG8: ... \`pk2<i64, i64>(5, 6)\`" "var G: (i64, i64) = pk2<i64, i64>(5, 6);\n${ZH}fn pk2<A, B>(a: A, b: B): (i64, i64) { return (a, b); }\nfn main(): i64 { return G.0 * 10 + G.1 + H - 77; }\nsyscall(60, main());\n"
refused zg9 "a tuple literal cannot initialize 'G' - its declared type is not a tuple" "ZG9: \`var G: i64 = (1, 2);\` registers no tuple (\`G + H\` stays an i64: one error)" 'var G: i64 = (1, 2);\nvar H = 7;\nsyscall(60, G + H);\n'
refused zg10 "the declaration zone reads a \`<\` comparison in the tuple literal of 'G' as an explicit generic call" "ZG10: \`(x < a, b > (c), 5)\`: two elements in pass 1, three in the replay — refused, never stored past the slot" 'var G = (x < a, b > (c), 5);\nvar x = 1;\nvar a = 2;\nvar b = 3;\nvar c = 4;\nvar H = 7;\nsyscall(60, G.0 + H);\n'
refused zg11 "$I12 'G' with a value that is not a tuple" "ZG11: \`var G: (i64, i64) = a < b > (c);\`: a whole call in pass 1, a comparison in the replay — refused, never the value store" 'var G: (i64, i64) = a < b > (c);\nvar H = 77;\nvar a = 1;\nvar b = 2;\nvar c = 3;\nsyscall(60, G.0 + H - 77);\n'
# R17 — a multi-value call stored into a tuple FIELD: bind it first (the argument form is T3's R17a-h).
R17F="is not stored into a tuple field - bind it first: \`var t: (i64, i64) = "
TH5='struct H { a; p: (i64, i64); }\n'
refused r17i "a multi-value call 'mk' $R17F" "R17i: \`h.p = mk(3);\`" "${TH5}${MK}${F5}    var h: H;\n    h.p = mk(3);${E5}"
refused r17j "a multi-value call 'B.mk' $R17F" "R17j: a method" "${TH5}struct B { v; }\nimpl B { fn mk(self, a): (i64, i64) { return (a, a); } }\n${F5}    var h: H;\n    var b: B;\n    h.p = b.mk(3);${E5}"
refused r17k "a multi-value call 'mk' $R17F" "R17k: a global's field, at top level" "${TH5}${MK}var GH = H { 1, 2, 3 };\nGH.p = mk(3);\nsyscall(60, 0);\n"
refused r17l "a multi-value call 'mk' $R17F" "R17l: a classic-for step's field" "${TH5}${MK}${F5}    var h: H;\n    for (var i = 0; i < 2; h.p = mk(i)) { i = i + 1; }${E5}"
# R17m-r (6.7.15, issues/2026-10-17-wrapped-multi-value-call-into-tuple-field-reports-twice.md) — a WRAPPED multi-value
# call into a tuple field is R17 alone: the issue's program verbatim gave R17 at the call (3:32) and then R12 at the
# wrap's \`(\` (3:31). \`_tup_fsc_call\` notes its report (\`_tfc_rep\`) and \`_fsc_paren\` marks the wrap's \`(\` reported,
# so the store's R12 stays quiet, as it does unwrapped (one token). A wrapped ONE-value call keeps its single R12
# line at the wrap. Every leg (the cross compilers built from this tree). Mutation (run 2026-10-18): \`_fsc_paren\`
# without its \`_tn_once(S, st)\` -> R17m, R17n, R17q, R17r two error lines on every leg.
TWO17='struct H { a; p: (i64, i64); }\nfn two(x): (i64, i64) { return (x, x + 1); }\n'
refused4 r17m "3:32: a multi-value call 'two' $R17F" "R17m: \`h.p = (two(3));\`, the issue's program verbatim" "${TWO17}fn t(): i64 { var h: H; h.p = (two(3)); return h.p.0 * 10 + h.p.1; }\nsyscall(60, t());\n"
refused4 r17n "3:33: a multi-value call 'two' $R17F" "R17n: \`h.p = ((two(3)));\`" "${TWO17}fn t(): i64 { var h: H; h.p = ((two(3))); return h.p.0 * 10 + h.p.1; }\nsyscall(60, t());\n"
refused4 r17o "3:31: a multi-value call 'two' $R17F" "R17o: unwrapped \`h.p = two(3);\` (unchanged)" "${TWO17}fn t(): i64 { var h: H; h.p = two(3); return h.p.0 * 10 + h.p.1; }\nsyscall(60, t());\n"
refused4 r17p "4:31: cannot store a value that is not a tuple into tuple field 'p'" "R17p: a wrapped one-value call \`h.p = (one(3));\` keeps its one R12 line" "${TWO17}fn one(x) { return x; }\nfn t(): i64 { var h: H; h.p = (one(3)); return h.p.0 * 10 + h.p.1; }\nsyscall(60, t());\n"
refused4 r17q "a multi-value call 'B.mk' $R17F" "R17q: a wrapped method \`h.p = (b.mk(3));\`" "${TH5}struct B { v; }\nimpl B { fn mk(self, a): (i64, i64) { return (a, a); } }\n${F5}    var h: H;\n    var b: B;\n    h.p = (b.mk(3));${E5}"
refused4 r17r "a multi-value call 'mk' $R17F" "R17r: a wrapped classic-for step's field" "${TH5}${MK}${F5}    var h: H;\n    for (var i = 0; i < 2; h.p = (mk(i))) { i = i + 1; }${E5}"
# R18 — `a, b = f();` re-assigns plain variables: every other target refused by name (each was "expected '='").
NP="a multi-value assignment \`a, b = f();\` re-assigns plain variables"
TGT=" from a multi-value call - its targets are i64, f64 or bool variables"
refused r18a "$NP - a field is not one" "R18a: a field first target \`h.x, b = ..\`" "struct H1 { x; }\n${MK}${F5V}    var h: H1;\n    h.x, b = mk(1);${E5}"
refused r18b "$NP - an element is not one" "R18b: a subscript first target" "${MK}${F5V}    var arr: i64[2];\n    arr[0], b = mk(1);${E5}"
refused r18c "$NP - \`*p\` is not one" "R18c: a deref first target" "${MK}${F5V}    var p = &a;\n    *p, b = mk(1);${E5}"
refused r18d "$NP - a field is not one" "R18d: a tuple element first target \`t.0, b = ..\`" "${MK}${F5V}    var t = (1, 2);\n    t.0, b = mk(1);${E5}"
refused r18e "$NP - a field is not one" "R18e: a later field target" "${MK}${F5V}    var h = (1, 2);\n    a, h.0 = mk(1);${E5}"
refused r18f "$NP - an element is not one" "R18f: a later subscript target" "${MK}${F5V}    var arr: i64[2];\n    a, arr[1] = mk(1);${E5}"
refused r18g "$NP - \`*p\` is not one" "R18g: a later deref target" "${MK}${F5V}    var p = &a;\n    a, *p = mk(1);${E5}"
refused r18h "$NP - its form is \`=\`, not a compound \`OP=\`" "R18h: \`a, b += f();\`" "${MK}${F5V}    a, b += mk(1);${E5}"
refused r18i "a multi-value assignment re-assigns 2 or 3 variables - a call returns at most 3 values" "R18i: 4 targets" "${MK}${F5V}    var c = 0;\n    var d = 0;\n    a, b, c, d = mk(1);${E5}"
refused r18j "a multi-value assignment re-assigns each variable once - this one is named twice" "R18j: a duplicate target" "${MK}${F5V}    a, a = mk(1);${E5}"
refused r18k "cannot assign to const 'C'" "R18k: a const target" "${MK}const C = 1;\n${F5V}    a, C = mk(1);${E5}"
refused r18l "cannot assign to enum constant 'EA'" "R18l: an enum constant target" "${MK}enum E { EA, EB }\n${F5V}    EA, b = mk(1);${E5}"
refused r18m "cannot re-assign struct 'p'$TGT" "R18m: a struct target" "${P}${MK}${F5V}    var p: P;\n    p, b = mk(1);${E5}"
refused r18n "cannot re-assign tuple 't' from a multi-value call - capture the call into it whole: \`t = f();\`" "R18n: a tuple target" "${MK}${F5V}    var t = (1, 2);\n    t, b = mk(1);${E5}"
refused r18o "cannot re-assign vector 'v'$TGT" "R18o: a vector target" "${MK}${F5V}    var v: f64v2;\n    v, b = mk(1);${E5}"
refused r18p "cannot re-assign array 'arr'$TGT" "R18p: an array target" "${MK}${F5V}    var arr: i64[2];\n    arr, b = mk(1);${E5}"
refused r18q "cannot re-assign u128 'u'$TGT" "R18q: a u128 target" "${MK}${F5V}    var u: u128 = 0;\n    u, b = mk(1);${E5}"
refused r18r "cannot re-assign slice 's'$TGT" "R18r: a slice target" "${MK}${F5V}    var s: [u8] = 0;\n    s, b = mk(1);${E5}"
refused r18s "cannot re-assign f32 'x'$TGT" "R18s: an f32 target" "${MK}${F5V}    var x: f32 = 0.0;\n    x, b = mk(1);${E5}"
refused r18t "cannot assign a value that is not a bool to bool 'k' - the call does not declare that value bool" "R18t: a bool target from a declared i64 value" "${MK}${F5V}    var k: bool = false;\n    k, b = mk(1);${E5}"
refused r18u "cannot assign a value that is not a bool to bool 'k' - the call does not declare that value bool" "R18u: a bool target from an undeclared callee" "fn dm(a, b) { return (a / b, a % b); }\n${F5V}    var k: bool = false;\n    k, b = dm(1, 2);${E5}"
refused r18v "undefined variable 'zz'" "R18v: an undefined target (as \`x = ..\` reports it)" "${MK}${F5V}    zz, b = mk(1);${E5}"
refused r18w "'a' is captured by value; a captured name is not assignable in a closure" "R18w: a closure's captured target (as \`x = ..\` inside a closure)" "include \"lib/alloc.cyr\"\n${MK}${F5V}    var c = fncall0(|| { var z = 0; a, z = mk(1); return z; });${E5}"
refused r18x "cannot re-assign tuple 'GV' from a multi-value call" "R18x: a global tuple target" "${MK}var GV = (1, 2);\n${F5V}    GV, b = mk(1);${E5}"
# R19 — a right-hand side that is not one whole call: the destructure's own texts.
R19="multi-value destructure needs a call on the right-hand side"
refused r19a "$R19" "R19a: \`a, b = 5;\`" "${MK}${F5V}    a, b = 5;${E5}"
refused r19b "$R19" "R19b: \`a, b = (b, a);\` (a literal is no call)" "${MK}${F5V}    a, b = (b, a);${E5}"
refused r19c "$R19" "R19c: \`a, b = t;\`" "${MK}${F5V}    var t = (1, 2);\n    a, b = t;${E5}"
exits4 r19d 12 "R19d: a wrapped call re-assigns (6.7.14, D45: it was \"needs a call\")" "${MK}${F5V}    a, b = (mk(1));\n    return a * 10 + b;\n}\nsyscall(60, f());\n"
refused r19e "$R19" "R19e: a call that is not the whole value" "${MK}${F5V}    a, b = mk(1) + 1;${E5}"
refused r19f "multi-value destructure binds 2 names, but 'one' returns 1 value" "R19f: a provably one-value callee" "fn one(x) { return x; }\n${F5V}    a, b = one(1);${E5}"
refused r19g "multi-value destructure count does not match the fn's declared return arity" "R19g: a declared-arity mismatch" "fn mk3(a): (i64, i64, i64) { return (a, a, a); }\n${F5V}    a, b = mk3(1);${E5}"
refused r19h "$R19" "R19h: a classic-for step whose value is not a call" "${MK}${F5V}    for (var i = 0; i < 2; a, b = i) { i = i + 1; }${E5}"
# R19i-R19o (B4 review) — a struct- or vector-returning callee is no multi-value call: refused by name, as the
# capture refuses it. It stored meaningless values: a 24 B struct's (its retptr's words: exit 1 where 59 on x86,
# aarch64 and PE), a 16 B one's second word read from the multi-value register (x2) where aarch64's struct pair
# put it in x1 (59 on x86, 50 on aarch64 before the 6.7.7 aarch64 fix — R19m, the aarch64 compiler, is in the A5
# leg). The refusal stands on the B4 decision (a struct callee is no multi-value call), not on the registers.
RA="cannot re-assign from '"
SP3='struct P3 { a; b; c; }\nfn mk(): P3 { var p: P3; p.a = 5; p.b = 9; p.c = 4; return p; }\n'
SPP='fn mkp(): P { var p: P; p.a = 5; p.b = 9; return p; }\n'
refused r19i "${RA}mk' - it returns struct 'P3', not multiple values" "R19i: a 24-byte struct callee" "${SP3}${F5V}    a, b = mk();${E5}"
refused r19j "${RA}mkp' - it returns struct 'P', not multiple values" "R19j: a 16-byte struct callee" "${P}${SPP}${F5V}    a, b = mkp();${E5}"
refused r19k "${RA}mp' - it returns struct 'P', not multiple values" "R19k: a method returning a struct \`a, b = o.mp();\`" "${P}struct O { k; }\nimpl O { fn mp(self): P { var p: P; p.a = 5; p.b = 9; return p; } }\n${F5V}    var o: O;\n    a, b = o.mp();${E5}"
refused r19l "${RA}vf' - it returns a vector, not multiple values" "R19l: a vector callee" "fn vf(): f64v2 { var v: f64v2; return v; }\n${F5V}    a, b = vf();${E5}"
refused r19n "${RA}mkg' - it returns struct 'P', not multiple values" "R19n: an explicit generic \`mkg<i64>(5)\`" "${P}fn mkg<T>(x: T): P { var p: P; p.a = x; p.b = 9; return p; }\n${F5V}    a, b = mkg<i64>(5);${E5}"
refused r19o "${RA}mkp' - it returns struct 'P', not multiple values" "R19o: a classic-for step" "${P}${SPP}${F5V}    for (var i = 0; i < 2; a, b = mkp()) { i = i + 1; }${E5}"
# R20 — unchanged: `(a, b) = f();` and `var (q, r) = f();` keep their errors.
refused r20a "unexpected '('" "R20a: \`(a, b) = f();\` (unchanged)" "${MK}${F5V}    (a, b) = mk(1);${E5}"
refused r20b "expected identifier, got '('" "R20b: \`var (q, r) = f();\` (unchanged)" "${MK}fn f(): i64 {\n    var (q, r) = mk(1);\n    return 0;\n}\nsyscall(60, f());\n"
# CL (T6) — a closure captures a tuple as it captures a struct: a by-value copy (tuple_values.tcyr's
# `closures`). Re-assigning the WHOLE captured tuple is what any captured assignment is: "undefined
# variable" — the literal and the capture forms too (an element write is the closure's copy).
refused cl1 "'t' is captured by value; a captured name is not assignable in a closure" "CL1: \`t = (3, 4);\` to a captured tuple" 'include "lib/alloc.cyr"\nfn f(): i64 {\n    var t = (1, 2);\n    var c = || { t = (3, 4); return t.0; };\n    return fncall0(c);\n}\nsyscall(60, f());\n'
refused cl2 "'t' is captured by value; a captured name is not assignable in a closure" "CL2: \`t = m2(5);\` to a captured tuple" 'include "lib/alloc.cyr"\nfn m2(x): (i64, i64) { return (x, 1); }\nfn f(): i64 {\n    var t = (1, 2);\n    var c = || { t = m2(5); return t.0; };\n    return fncall0(c);\n}\nsyscall(60, f());\n'
# CS (6.7.11, the returns lane) — ONE MISTAKE, ONE ERROR, at its place (the filed repros of
# issues/archived/2026-10-09-refusal-cascades-tuples-pairs-u128-d19.md verbatim, shapes 1-4 and 8): EXACTLY the errors
# named, and no warning. CS1 `t == u` reports the left operand alone (a chain too; two arguments are two
# mistakes); CS2 a captured tuple's `t = u;` is the captured-assignment error alone, its caret on `t` (the struct
# form's caret too); CS3 no "assigning non-pointer to typed pointer" after the tuple store's refusal nor about a
# refused `*( .. )`; CS4 a literal refused for its shape still declares its name — a local, a global after the
# first statement (annotated or not) — and a > 256 zone literal registers at the cap; CS8 a zone tuple copied
# from a tuple declared below it is `_gci_below`'s error alone, a scalar below is R12 alone.
cascade() {   # <name> <errors> <what> <source> <want>..: exactly <errors> error lines, no warning; each <want> is one
    _cn=$1; _ce=$2; _cw=$3
    printf '%b' "$4" > "$T/$_cn.cyr"
    shift 4
    build "$_cn"
    _ne=$(grep -c '^error' "$T/$_cn.err" || true)
    _nw=$(grep -c '^warning' "$T/$_cn.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$_cw: BUILT (rc 0)"; return; fi
    if [ "$_ne" -ne "$_ce" ] || [ "$_nw" -ne 0 ]; then bad "$_cw: $_ne error / $_nw warning lines (want $_ce / 0): $(grep '^error\|^warning' "$T/$_cn.err" | head -4 | tr '\n' '|')"; return; fi
    for _cx in "$@"; do
        if ! grep -qF "error:<source>:$_cx" "$T/$_cn.err"; then bad "$_cw: no error '$_cx': $(grep '^error' "$T/$_cn.err" | head -3 | tr '\n' '|')"; return; fi
    done
    ok "$_cw: $_ce error(s), each at its place"
}
TUV="tuple 't' used as a value"
cascade cs1 1 "CS1: \`t == u\` (the filed repro): one error, the left operand" 'fn main(): i64 {\n    var t = (1, 2);\n    var u = (3, 4);\n    if (t == u) { return 1; }\n    return 0;\n}\nsyscall(60, main());\n' "4:9: $TUV"
cascade cs1b 1 "CS1b: \`t + u + v\`: one error" 'fn main(): i64 {\n    var t = (1, 2);\n    var u = (3, 4);\n    var v = (5, 6);\n    var k = t + u + v;\n    return k;\n}\nsyscall(60, main());\n' "5:13: $TUV"
cascade cs1c 2 "CS1c: \`(t == u) && (u == t)\`: one per comparison" 'fn main(): i64 {\n    var t = (1, 2);\n    var u = (3, 4);\n    if ((t == u) && (u == t)) { return 1; }\n    return 0;\n}\nsyscall(60, main());\n' "4:10: $TUV" "4:22: tuple 'u' used as a value"
cascade cs1d 2 "CS1d: \`g(t, u)\`: two arguments, two errors (unchanged)" 'fn g(a, b): i64 { return a; }\nfn main(): i64 {\n    var t = (1, 2);\n    var u = (3, 4);\n    return g(t, u);\n}\nsyscall(60, main());\n' "5:14: $TUV" "5:17: tuple 'u' used as a value"
cascade cs2 1 "CS2: \`t = u;\` in a closure, both captured tuples (the filed repro): the captured-assignment error at \`t\`" 'include "lib/alloc.cyr"\nfn main(): i64 {\n    alloc_init();\n    var t = (1, 2);\n    var u = (3, 4);\n    var f = || { t = u; return 0; };\n    return 0;\n}\nsyscall(60, main());\n' "6:18: 't' is captured by value; a captured name is not assignable in a closure"
cascade cs2b 1 "CS2b: the struct form \`s = q;\`: the same error, at \`s\`" 'include "lib/alloc.cyr"\nstruct P2 { a; b; }\nfn main(): i64 {\n    alloc_init();\n    var s = P2 { 1, 2 };\n    var q = P2 { 3, 4 };\n    var f = || { s = q; return 0; };\n    return 0;\n}\nsyscall(60, main());\n' "7:18: 's' is captured by value; a captured name is not assignable in a closure"
cascade cs3 2 "CS3: \`t = 5;\` then \`var p: *(i64, i64) = 0;\` (the filed repro): the two refusals, no warning" 'fn main(): i64 {\n    var t = (1, 2);\n    t = 5;\n    var p: *(i64, i64) = 0;\n    return 0;\n}\nsyscall(60, main());\n' "3:9: cannot assign a value that is not a tuple to tuple 't'" "4:13: a tuple type cannot be a pointer target"
cascade cs3b 1 "CS3b: a refused \`*( .. )\` local read into a \`*i64\`: no warning there either" 'fn main(): i64 {\n    var p: *(i64, i64) = 0;\n    var q: *i64 = p;\n    return 0;\n}\nsyscall(60, main());\n' "2:13: a tuple type cannot be a pointer target"
cascade cs3c 1 "CS3c: a \`*( .. )\` return type, its call into a \`*i64\`" 'fn f(): *(i64, i64) { return 0; }\nfn main(): i64 { var q: *i64 = f(); return 0; }\nsyscall(60, main());\n' "1:10: a tuple type cannot be a pointer target"
cascade cs4 1 "CS4: \`var t = (1, 2, );\` then \`t.0\` (the filed repro): the trailing comma alone" 'fn main(): i64 {\n    var t = (1, 2, );\n    var k = t.0;\n    return k;\n}\nsyscall(60, main());\n' "2:18: a trailing comma in a tuple literal"
cascade cs4b 1 "CS4b: an empty element, then \`t.1 + t.2\`" 'fn main(): i64 {\n    var t = (1, , 2);\n    var k = t.1 + t.2;\n    return k;\n}\nsyscall(60, main());\n' "2:17: an empty element in a tuple literal"
cascade cs4c 1 "CS4c: a global after the first statement, a trailing comma, then \`G.0\`" 'syscall(1, 1, 0, 0);\nvar G = (1, 2, );\nvar k = G.0;\nsyscall(60, k);\n' "2:14: a trailing comma in a tuple literal"
cascade cs4d 1 "CS4d: ... annotated, the wrong arity, then \`G.0\`" 'syscall(1, 1, 0, 0);\nvar G: (i64, i64) = (1, 2, 3);\nvar k = G.0;\nsyscall(60, k);\n' "2:21: tuple (i64, i64) has 2 elements - this literal has 3"
CS4E=$(i=1; while [ $i -le 257 ]; do printf '%s' "$i"; [ $i -lt 257 ] && printf ', '; i=$((i + 1)); done)
cascade cs4e 1 "CS4e: a zone literal of 257 elements, then \`G.0\` (the filed repro): the refusal alone" "var G = ($CS4E);\nfn main(): i64 { return G.0; }\nsyscall(60, main());\n" "1:9: a tuple literal has at most 256 elements"
cascade cs8 1 "CS8: \`var A: (i64, i64) = B;\` above \`var B = (1, 2);\` (the filed repro): the real cause alone" 'var A: (i64, i64) = B;\nvar B = (1, 2);\nfn main(): i64 { return A.0; }\nsyscall(60, main());\n' "1:21: cannot copy-init 'A' from a global declared below it (declare the source first): 'B'"
cascade cs8b 1 "CS8b: ... a scalar \`B\` below: R12 alone" 'var A: (i64, i64) = B;\nvar B = 5;\nfn main(): i64 { return A.0; }\nsyscall(60, main());\n' "1:8: cannot initialize tuple 'A' with a value that is not a tuple"
cascade cs8c 1 "CS8c: ... a 3-tuple \`B\` below: the type mismatch alone" 'var A: (i64, i64) = B;\nvar B = (1, 2, 3);\nfn main(): i64 { return A.0; }\nsyscall(60, main());\n' "1:21: cannot copy 'B' into a variable of a different struct/vector type: 'A'"
# AS2 — a capture and a multi-value assignment in a SUSPENDING `async fn`, across awaits: the block's span
# recorded before the call, every value pushed before any store, the stores addressed (the coroutine's heap
# frame, whose slots ascend, holds the block whole).
CC_SV=$CC; CC="$T/acc5"
exits as2 0 "AS2: \`var t: (i64, i64, i64) = m3(..);\`, \`t = m3(..);\` and \`a, q = m2(a);\` across awaits" 'include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/async.cyr"\nstruct P2 { x; y; }\nfn nopark(): i64 { return 0; }\nfn m3(x, y, z): (i64, i64, i64) { return (x, y, z); }\nfn m2(x): (i64, i64) { return (x, 1); }\nasync fn steps(C): i64 {\n    var a = 3;\n    var t: (i64, i64, i64) = m3(5, 6, 7);\n    var p = P2 { 1, 2 };\n    var b = 4;\n    var s1 = await nopark();\n    t = m3(t.2, t.0, b);\n    var q = 0;\n    var s2 = await nopark();\n    a, q = m2(a);\n    return t.0 * 1000 + t.1 * 100 + t.2 * 10 + a + p.y * 10000 + q * 100000;\n}\nfn main(): i64 {\n    alloc_init();\n    var C = steps(0);\n    var r1 = future_force(C);\n    var r2 = future_force(C);\n    var r3 = future_force(C);\n    if (r3 != 127543) { syscall(60, 1); }\n    syscall(60, 0);\n    return 0;\n}\nvar e = main();\n'
CC=$CC_SV
# AS3 (6.7.9) — a tuple CAPTURED by a closure in a suspending `async fn`, the closure made before the await
# and after it: the capture copied the block by slot index while the coroutine frame orders it from its low
# slot, so every word landed reversed (`(1, 2)` read as `(2, 1)`: 34512 here, silently). Before the fix no row
# could pin this; coroutine_midbody_suspend.sh axis 11 is the full matrix (structs, u128, arrays, slices).
CC_SV=$CC; CC="$T/acc5"
exits as3 0 "AS3: a tuple captured by a closure in a suspending async fn, before and after the await" 'include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/fnptr.cyr"\ninclude "lib/async.cyr"\nfn nopark(): i64 { return 0; }\nasync fn steps(C): i64 {\n    var t = (1, 2);\n    var u: (i64, i64, i64) = (3, 4, 5);\n    var c = || u.2 * 100 + u.1 * 10 + u.0;\n    var s1 = await nopark();\n    var d = || t.1 * 10 + t.0;\n    return fncall0(c) * 100 + fncall0(d);\n}\nfn main(): i64 {\n    alloc_init();\n    var C = steps(0);\n    var r1 = future_force(C);\n    var r2 = future_force(C);\n    if (r2 != 54321) { syscall(60, 1); }\n    syscall(60, 0);\n    return 0;\n}\nvar e = main();\n'
CC=$CC_SV

# ── X: --syntax-only (cyrius lint's pre-pass) ──────────────────────────────────────────────────────
# A fn with a tuple parameter, its call, and calls to a sibling file's fns (unknown here) with a tuple
# argument and a sibling's call as a tuple argument: nothing tuple-related is reported.
printf 'fn take(t: (i64, i64), k): i64 { return t.0 * 10 + t.1 + k; }\nfn f(): i64 {\n    var t: (i64, i64);\n    t.0 = 1;\n    t.1 = 2;\n    return take(t, 3) + sib_take(t, 4) + take(sib_mk(), 5);\n}\nsyscall(60, f());\n' > "$T/x03.cyr"
"$CC" --syntax-only < "$T/x03.cyr" > /dev/null 2> "$T/x03.err" || true
if grep -q "tuple\|^error:<source>" "$T/x03.err"; then bad "X3: --syntax-only reported: $(grep -m1 "tuple\|^error:<source>" "$T/x03.err")"
else ok "X3: --syntax-only: a tuple parameter, a sibling's fn given a tuple, a sibling's call as a tuple argument — silent"; fi
# X4: literals — declared, assigned, stored into a field, passed to a local tuple parameter and to a sibling
# file's fn (unknown here: its literal is skipped quietly, no false accusation).
printf 'struct H { a; p: (i64, i64); }\nfn take(t: (i64, i64), k): i64 { return t.0 + k; }\nfn f(): i64 {\n    var t = (1, 2);\n    var u: (i64, f64) = (3, 0.5);\n    t = (t.1, t.0);\n    var h: H;\n    h.p = ((4, 5));\n    return take((6, 7), 1) + sib_take((8, 9), 2) + u.0 + h.p.1;\n}\nsyscall(60, f());\n' > "$T/x04.cyr"
"$CC" --syntax-only < "$T/x04.cyr" > /dev/null 2> "$T/x04.err" || true
if grep -q "tuple\|^error:<source>" "$T/x04.err"; then bad "X4: --syntax-only reported: $(grep -m1 "tuple\|^error:<source>" "$T/x04.err")"
else ok "X4: --syntax-only: literals declared, assigned, stored, passed (a sibling's fn too) — silent"; fi
# X5 (T5): a sibling file's globals as `a, b = f()` targets (their stores dropped), a sibling's callee
# captured (into a bool element too: an unknown callee is not judged here), `t = f()`, a for step, and
# `return t;` — nothing reported.
printf 'fn f(): i64 {\n    var b = 0;\n    sib_a, b = sib_mk();\n    var t: (i64, i64) = sib_mk2(1);\n    t = sib_mk2(2);\n    var k: (bool, i64) = sib_mk3();\n    b, sib_c, sib_d = sib_mk3();\n    for (var i = 0; i < 2; b, sib_a = sib_mk()) { i = i + 1; }\n    return t.0;\n}\nfn g(): (i64, i64) { var t = (1, 2); return t; }\nsyscall(60, f());\n' > "$T/x05.cyr"
"$CC" --syntax-only < "$T/x05.cyr" > /dev/null 2> "$T/x05.err" || true
if grep -q "tuple\|^error:<source>" "$T/x05.err"; then bad "X5: --syntax-only reported: $(grep -m1 "tuple\|^error:<source>" "$T/x05.err")"
else ok "X5: --syntax-only: sibling targets and callees in captures and multi-value assignments, \`return t;\` — silent"; fi

# X6 (T6): a tuple argument to a generic (a struct-reading one too) and a const fn's tuple parameter — the
# compile refuses both (R4, R5); lint's pre-pass, which judges no type, resolves them as before: silent.
printf 'fn first<T>(x: T): i64 { return 7; }\nfn fld<T>(x: T): i64 { return x.0; }\nconst fn cf(t: (i64, i64)): i64 { return 3; }\nfn f(): i64 {\n    var t = (5, 9);\n    var u: (i64, i64) = first(t);\n    return first(t) + fld(t) + u.0;\n}\nsyscall(60, f());\n' > "$T/x06.cyr"
"$CC" --syntax-only < "$T/x06.cyr" > /dev/null 2> "$T/x06.err" || true
if grep -q "tuple\|^error" "$T/x06.err"; then bad "X6: --syntax-only reported: $(grep -m1 "tuple\|^error" "$T/x06.err")"
else ok "X6: --syntax-only: a tuple given to a generic (a struct-reading one too), a const fn's tuple parameter — silent"; fi
# X7 (T6): ... and a real syntax error later in that statement is still lint's to report — the compile's
# refusal latches the statement (its recovery calls the generic's base), lint's pre-pass must not.
printf 'fn first<T>(x: T): i64 { return 7; }\nfn f(): i64 {\n    var t = (5, 9);\n    var y = first(t) + (2;\n    return y;\n}\nsyscall(60, f());\n' > "$T/x07.cyr"
"$CC" --syntax-only < "$T/x07.cyr" > /dev/null 2> "$T/x07.err" || true
if [ "$(grep -c '^error' "$T/x07.err")" -eq 1 ] && grep -q "expected ')', got ';'" "$T/x07.err"; then ok "X7: --syntax-only: the syntax error after \`first(t)\` in its statement is reported, once"
else bad "X7: --syntax-only: $(grep '^error' "$T/x07.err" | head -2 | tr '\n' '|') (want one \"expected ')', got ';'\")"; fi

# ── T7: the tools that read a signature by hand — `cyrius header` and the LSP (rows T1 / T2) ────────
# Each tool is built from THIS tree with $CC (a build that fails or yields a tiny file is a red row:
# cycc on empty stdin exits 0) and run in a scratch dir with no cyrius.cyml and a throwaway HOME /
# CYRIUS_HOME, so it never re-execs a pinned toolchain nor reads the live store.
mkdir -p "$T/tl" "$T/tl/home" "$T/tl/ch"
tool_build() {   # <out> <source> -> 0 when built
    "$CC" < "$2" > "$1" 2> "$1.err" && [ "$(wc -c < "$1")" -gt 20000 ] && chmod +x "$1"
}
printf 'fn g(t: (i64, i64), x): i64 { return t.0 + x; }\npub fn h(a, w: (f64, i64, bool), z): (i64, i64) { return (a, z); }\nfn k(): (i64, i64) { return (1, 2); }\nfn m(p: (i64, i64)): i64 { return p.1; }\nfn n(a, b: i64): i64 { return a + b; }\n' > "$T/tl/tup.cyr"
if tool_build "$T/tl/cyrius" cbt/cyrius.cyr; then
    rc=0; (cd "$T/tl" && HOME="$T/tl/home" CYRIUS_HOME="$T/tl/ch" timeout 30 ./cyrius header tup.cyr > hdr.out 2> hdr.err) || rc=$?
    # 6.7.11: a two-value RETURN (`h`, `k`) is `cyr_val2` on x86_64 SysV (rax:rdx), with its note — it
    # printed `cyr_val`, the second value lost (issues/archived/2026-10-10-cyrius-header-ignores-struct-returns.md).
    got=$(grep -E '^cyr_val2? ' "$T/tl/hdr.out" | tr '\n' '|')
    want='cyr_val g(cyr_val t, cyr_val x);|cyr_val2 h(cyr_val a, cyr_val w, cyr_val z);   /* returns (i64, i64), 16 B */|cyr_val2 k(void);   /* returns (i64, i64), 16 B */|cyr_val m(cyr_val p);|cyr_val n(cyr_val a, cyr_val b);|'
    if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then ok "T1: \`cyrius header\`: a tuple parameter is one \`cyr_val\`, the parameters after it kept (5 prototypes)"
    else bad "T1: \`cyrius header\` rc $rc: got [$got]"; fi
    # T1b: the list now runs past the first `)`, so a `)` the name scan stops at inside it (malformed source,
    # which the header verb does not compile) must still be stepped: the walk finishes, the fn after it is read.
    printf 'fn bad(a (b), c): i64 { return 0; }\nfn after(z): i64 { return z; }\n' > "$T/tl/bad.cyr"
    rc=0; (cd "$T/tl" && HOME="$T/tl/home" CYRIUS_HOME="$T/tl/ch" timeout 10 ./cyrius header bad.cyr > bad.out 2> bad.err) || rc=$?
    if [ "$rc" -eq 0 ] && grep -qxF 'cyr_val after(cyr_val z);' "$T/tl/bad.out"; then ok "T1b: \`cyrius header\`: a malformed parameter list still ends (the next fn read)"
    else bad "T1b: \`cyrius header\` on a malformed parameter list: rc $rc (124: it never finished)"; fi
else bad "T1: could not build cbt/cyrius.cyr: $(head -1 "$T/tl/cyrius.err")"; fi
# T2: the semantic tokens of a file whose fns take a tuple, decoded to absolute `line:col:len:type` (type 6 is
# `parameter` in the legend; 5 `keyword`). The fixture's parameters are all one letter, so a longer type-6 token is
# a type name taken for a parameter.
printf 'fn g(t: (i64, i64), u): i64 {\n    return t.0 + u;\n}\nfn h(a, w: (f64, i64, bool), z) { return a + w.0 + z; }\n' > "$T/tl/st.cyr"
if tool_build "$T/tl/lsp" programs/cyrius-lsp.cyr; then
    lsp_frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c | tr -d ' ')" "$1"; }
    { lsp_frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
      lsp_frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file://'"$T/tl/st.cyr"'","languageId":"cyrius","version":1,"text":""}}}'
      lsp_frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/semanticTokens/full","params":{"textDocument":{"uri":"file://'"$T/tl/st.cyr"'"}}}'
      lsp_frame '{"jsonrpc":"2.0","id":99,"method":"shutdown"}'; } > "$T/tl/lsp.in"
    # No `cyrius` on the child's PATH: didOpen's diagnostics compile is not what this row tests.
    (cd "$T/tl" && PATH=/usr/bin:/bin HOME="$T/tl/home" timeout 30 ./lsp < lsp.in > lsp.out 2> lsp.run.err) || :
    grep -o '"id":2,"result":{"data":\[[0-9,]*\]' "$T/tl/lsp.out" | sed 's/.*\[//; s/\]$//' | tr ',' '\n' | \
        awk 'NF { a[n++] = $1 } END { l = 0; c = 0; for (i = 0; i + 4 < n; i += 5) { if (a[i] > 0) { l += a[i]; c = a[i + 1] } else { c += a[i + 1] }; print l ":" c ":" a[i + 2] ":" a[i + 3] } }' > "$T/tl/st.tok"
    tk() { if grep -qx "$1" "$T/tl/st.tok"; then echo y; else echo n; fi; }
    got="$(tk 0:5:1:6)$(tk 0:20:1:6)$(tk 1:17:1:6)$(tk 3:29:1:6)$(tk 3:51:1:6)"
    long=$(awk -F: '$4 == 6 && $3 > 1' "$T/tl/st.tok" | tr '\n' ' ')
    if [ "$got" = yyyyy ] && [ -z "$long" ]; then ok "T2: cyrius-lsp: \`u\` / \`z\` after a tuple parameter are parameters, \`i64\` / \`bool\` are not"
    else bad "T2: cyrius-lsp: t,u,u-use,z,z-use as parameters = $got (want yyyyy); type names taken for parameters: [$long]"; fi
else bad "T2: could not build programs/cyrius-lsp.cyr: $(head -1 "$T/tl/lsp.err")"; fi

# ── I: with B6's default and named arguments (the integration rows, b4_plan §9) ─────────────────────
# I1 a tuple parameter beside a defaulted one: `f((1, 2))` filled, `f(u, k: 5)` named, the tuple itself
# named (`f(t: u)`, `f(k: 7, t: u)`: its address, through the named path's parameter gates), and as a
# FORWARD call (pass 1 steps the tuple's type once — a second step took the list's own `,` and counted
# one parameter: "'g' expects 1 argument"); I2 a named argument whose value is a tuple literal, in a
# direct call and a tail call — the value, and (objdump) the tail calls are `call`s, never a `jmp`;
# I3 a tuple parameter takes no default: `= (1, 2)` is a tuple in a const context, `= 0` B6's
# by-type refusal; I4 a named multi-value argument into a tuple parameter is refused as a positional
# one is ("bind it first"), in order and reordered. The runtime rows are tuple_values.tcyr's I1 / I2.
exits i01 42 "I1: \`f((1, 2))\`, \`f(u, k: 5)\` and \`f(k: 7, t: u)\` beside a defaulted parameter, backward and forward" 'fn f(t: (i64, i64), k = 2): i64 { return t.0 * 100 + t.1 * 10 + k; }\nfn main(): i64 {\n    var u: (i64, i64) = (3, 4);\n    if (f((1, 2)) != 122) { return 1; }\n    if (f(u, k: 5) != 345) { return 2; }\n    if (g((1, 2)) != 5122) { return 3; }\n    if (g(u, k: 5) != 5345) { return 4; }\n    if (u.0 * 10 + u.1 != 34) { return 5; }\n    if (f(t: u) != 342) { return 6; }\n    if (f(k: 7, t: u) != 347) { return 7; }\n    return 42;\n}\nfn g(t: (i64, i64), k = 2): i64 {\n    t.0 = t.0 + 50;\n    return t.0 * 100 + t.1 * 10 + k;\n}\nsyscall(60, main());\n'
printf 'fn f(t: (i64, i64), x = 1, y = 9): i64 { return t.0 * 1000 + t.1 * 100 + x * 10 + y; }\nfn tl(n): i64 { return f(t: (n, 2), x: 3); }\nfn tr(n): i64 { return f(y: 4, t: (n, 5), x: 6); }\nfn tend(): i64 { return 0; }\nfn main(): i64 {\n    if (f(t: (1, 2), x: 3) != 1239) { return 1; }\n    if (tl(1) != 1239) { return 2; }\n    if (tr(5) != 5564) { return 3; }\n    return 42 + tend();\n}\nsyscall(60, main());\n' > "$T/i02.cyr"
rc=0; CYRIUS_SYMS="$T/i02.syms" "$CC" < "$T/i02.cyr" > "$T/i02.bin" 2> "$T/i02.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "I2: the probe did not build: $(grep '^error' "$T/i02.err" | head -1)"
else
    chmod +x "$T/i02.bin"; got=0; timeout 10 "$T/i02.bin" || got=$?
    [ "$got" -eq 42 ] && ok "I2: a named tuple literal argument, direct and in two tail calls (in order, reordered): exit 42" || bad "I2: exit $got, want 42"
    if command -v objdump > /dev/null 2>&1; then
        f=$(awk '$2 == "f" { print $1 }' "$T/i02.syms"); a=$(awk '$2 == "tl" { print $1 }' "$T/i02.syms"); e=$(awk '$2 == "tend" { print $1 }' "$T/i02.syms")
        if [ -z "$f" ] || [ -z "$a" ] || [ -z "$e" ]; then bad "I2: the symbol map does not name f / tl / tend"
        else
            fs=$(printf '%x' "0x$f")
            nc=$(objdump -d --start-address=0x"$a" --stop-address=0x"$e" "$T/i02.bin" | grep -cE "call +0x$fs\b" || true)
            nj=$(objdump -d --start-address=0x"$a" --stop-address=0x"$e" "$T/i02.bin" | grep -cE "jmp +0x$fs\b" || true)
            if [ "$nc" -eq 2 ] && [ "$nj" -eq 0 ]; then ok "I2: ... both tail calls are calls (the literal's temp is in the frame a jmp frees)"
            else bad "I2: tl / tr have $nc call(s) and $nj jmp(s) to f, want 2 and 0"; fi
        fi
    else echo "  SKIP I2's objdump row: no objdump"; skips=$((skips + 1)); fi
fi
IU='fn main(): i64 { var u: (i64, i64) = (1, 2); return f(u); }\nsyscall(60, main());\n'
refused i03 "a tuple in a const context" "I3: \`fn f(t: (i64, i64) = (1, 2))\` (a tuple parameter takes no default)" "fn f(t: (i64, i64) = (1, 2)): i64 { return t.0; }\n${IU}"
refused i03b "parameter 't' of 'f' is a tuple: it takes no default" "I3b: \`fn f(t: (i64, i64) = 0)\`" "fn f(t: (i64, i64) = 0): i64 { return t.0; }\n${IU}"
IG='fn p(): (i64, i64) { return (1, 2); }\nfn g(t: (i64, i64), k = 0): i64 { return t.0 + t.1 + k; }\n'
refused i04 "a multi-value call 'p' is not a tuple argument - bind it first" "I4: \`g(t: p())\`, a named multi-value argument into a tuple parameter" "${IG}fn main(): i64 { return g(t: p()); }\nsyscall(60, main());\n"
refused i04b "a multi-value call 'p' is not a tuple argument - bind it first" "I4b: ... reordered, \`g(k: 1, t: p())\`" "${IG}fn main(): i64 { return g(k: 1, t: p()); }\nsyscall(60, main());\n"

# ── A: tests/tcyr/crossos/tuple_values.tcyr on every pipeline and target ───────────────────────────
TV="$ROOT/tests/tcyr/crossos/tuple_values.tcyr"
want=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TV")
[ "$want" -ge 203 ] || bad "A0: only $want assertions derived from $TV (floor 203)"
tcyr_ok() {   # <label> <output file> <exit> <want>
    if [ "$3" -eq 0 ] && grep -q "^$4 passed, 0 failed" "$2"; then ok "$1: $4 passed"
    else bad "$1: exit $3, $(grep -E 'passed|FAIL' "$2" | tr -d '\r' | head -3 | tr '\n' '|')"; fi
}
for mode in plain IR1 IR3 DCE; do
    case $mode in
        plain) env_=""; lbl="A1 x86" ;;
        IR1) env_="CYRIUS_IR=1"; lbl="A2 x86, CYRIUS_IR=1" ;;
        IR3) env_="CYRIUS_IR=3"; lbl="A3 x86, CYRIUS_IR=3" ;;
        DCE) env_="CYRIUS_DCE=1"; lbl="A4 x86, CYRIUS_DCE=1" ;;
    esac
    rc=0; env $env_ "$CC" < "$TV" > "$T/tv.$mode" 2> "$T/tv.$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/tv.$mode.err" | head -1)"; continue; fi
    chmod +x "$T/tv.$mode"; got=0; timeout 60 "$T/tv.$mode" > "$T/tv.$mode.out" 2>&1 || got=$?
    tcyr_ok "$lbl" "$T/tv.$mode.out" "$got" "$want"
done
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2>/dev/null && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        # R19m (B4 review): the aarch64 compiler refuses the 16-byte struct callee of `a, b = f();` too — the
        # target where it ran silently wrong (the second word read from x2, the struct pair's is x1: 50, not 59).
        printf '%b' "${P}${SPP}${F5V}    a, b = mkp();${E5}" > "$T/r19m.cyr"
        rc=0; "$T/cc_a64" < "$T/r19m.cyr" > "$T/r19m.bin" 2> "$T/r19m.err" || rc=$?
        if [ "$rc" -ne 0 ] && [ "$(grep -c '^error' "$T/r19m.err")" -eq 1 ] && grep -qF "${RA}mkp' - it returns struct 'P', not multiple values" "$T/r19m.err"; then ok "R19m (aarch64): a 16-byte struct callee of \`a, b = f();\` refused once"
        else bad "R19m (aarch64): rc $rc: $(grep '^error' "$T/r19m.err" | head -1)"; fi
        if "$T/cc_a64" < "$TV" > "$T/tv.a" 2> "$T/tv.aerr"; then
            chmod +x "$T/tv.a"; got=0; (cd "$T" && timeout 120 qemu-aarch64 ./tv.a > "$T/tv.aout" 2>&1) || got=$?
            tcyr_ok "A5 aarch64 (qemu)" "$T/tv.aout" "$got" "$want"
        else bad "A5 aarch64: the tcyr did not compile: $(grep '^error' "$T/tv.aerr" | head -1)"; fi
    else bad "A5: could not build src/main_aarch64.cyr"; fi
else echo "  SKIP A5 aarch64 — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2>/dev/null && [ -s "$T/cc_cx" ] && \
   "$CC" < programs/cxvm.cyr > "$T/cxvm" 2>/dev/null && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    if "$T/cc_cx" < "$TV" > "$T/tv.cyx" 2> "$T/tv.cxerr" && [ -s "$T/tv.cyx" ]; then
        got=0; timeout 120 "$T/cxvm" < "$T/tv.cyx" > "$T/tv.cxout" 2>&1 || got=$?
        tcyr_ok "A6 cx (cxvm)" "$T/tv.cxout" "$got" "$want"
    else bad "A6 cx: the tcyr did not compile: $(grep '^error' "$T/tv.cxerr" | head -1)"; fi
else bad "A6: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi
if command -v wine > /dev/null 2>&1; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$TV" > "$T/tv.exe" 2> "$T/tv.werr" && [ -s "$T/tv.exe" ]; then
        got=0
        (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine ./tv.exe > "$T/tv.wout" 2>/dev/null) || got=$?
        tcyr_ok "A7 PE (wine)" "$T/tv.wout" "$got" "$want"
    else bad "A7 PE: the tcyr did not compile: $(grep '^error' "$T/tv.werr" | head -1)"; fi
else echo "  SKIP A7 PE — wine not installed"; skips=$((skips + 1)); fi

if [ "$fails" -ne 0 ]; then echo "FAIL: tuple_checked — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: tuple_checked — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: tuple_checked — tuples: the lexer (L); the type in a var, a struct field and a parameter, \`t.N\`, copies (S, P); the literal in its five positions, wrapped, in both zones and a kernel build (C, S1, S4, K1, PW, AS); every open shape refused by name (R1-R13, R17, R21); the bridge — captures, \`return t;\`, \`a, b = f();\` — and its refusals (R14-R20, AS2); a tuple captured by a closure across an await (AS3); the zone's pass 1 reading a generic call by its tokens (ZG); a captured tuple re-assigned whole (CL); one error per mistake after a tuple refusal (CS); \`cyrius header\` and the LSP read a tuple parameter (T1, T2); --syntax-only silent (X); with default and named arguments (I1-I4); tuple_values.tcyr on x86 / IR / DCE / aarch64 / cx / PE (A)"
