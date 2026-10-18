#!/bin/sh
# generic_type_arg_unknown_refused.sh — 6.6.8 bite 1b: an explicit type argument that names no
# type (`id<Nope>(4)`) is refused by name, and a forwarded type parameter (`inner<T>(p)` inside a
# generic) resolves to its binding.
#
# ⛔ WHY. `_parse_one_type_arg` classified a type-arg as a TYPE NAME only. A name that was none
# came back 0 — which the instantiation machinery reads as "unbound", i.e. the BASE emission — so
#   * `id<Nope>(4)` compiled clean and ran the i64 base (measured: exit 5), and
#   * `inner<T>(p)` inside `fn outer<T>` hit the same 0: a callee that uses T as a struct became
#     the `rax = 0` dead stub (`outer<Pt>(p)` returned 2, want 16), or — for a body small enough
#     to inline — a compile error raised from outer's own base emission, which nothing calls.
# A bound type parameter now resolves to its binding, and 0 is never a type. The runtime values
# are pinned cross-host by tests/tcyr/crossos/generic_forward_tparam.tcyr; this gate pins the
# compile-time halves the .tcyr runner cannot (a refusal, and exit codes of tiny programs).
#
#   A  id<Nope>(4)                                 -> refused, message names 'Nope'
#   B  a type-arg that is a VARIABLE, not a type    -> refused, message names it
#   C  outer<Pt>(p) forwarding to a looping inner<T> -> 16 (was 2)
#   D  the same with an inlinable inner<T>           -> 16 (was a compile error)
#   E  control: id<i64>(4) / id<i32>(4) / id<Pt>     -> build and run
#   F  id<Color>(4), Color a declared enum            -> refused, message says it is an enum
#   G  id<u64> / <u8> / <bool> / <ptr> / <f32>        -> refused by name (not in the type-arg
#      vocabulary, which is the return-type vocabulary: a struct, i8/i16/i32/i64, f64, or a bound
#      type parameter — an alias would silently pick a width; these all used to run the i64 base)
#
# ⛔ 6.6.10 (bite 7) — A GENERIC THAT USES T AS A STRUCT HAS NO SCALAR INSTANCE. Its base is the
# `rax = 0` dead stub, and whether it was one was known only while that base was being emitted —
# so every row below BUILT on 6.6.9 and returned 0 (or failed with a misleading "no struct type in
# scope for 'p'"). Each is now refused by name, 'g' (or the forwarding 'outer'):
#   H  g<i64>(5), g(5), `return g<i64>(5)`, `return g(5)`, g<i32>(5), and an inlinable body
#   I  TRANSITIVE: outer<T> forwarding `g<T>(p)` / `g(p)`, called outer<i64>(5) / outer(5) —
#      and with the three fns defined in REVERSE order (the facts are recorded in pass 1)
#   J  `&g` (the address is the stub's)
#   K  two struct type args inferred, or a struct beside a scalar: refused by name 6.6.10 → 6.7.0
#      (it was 0 silently before). ⭐ 6.7.1 (C3) LIFTED the refusal — these build and RUN now,
#      with the right value; the full matrix is tests/tcyr/crossos/generic_two_param_struct.tcyr
#   L  a stub generic returning a struct, received as `var r: Box<i64> = mkb(5)` (its own call path)
#   N  a bad type argument in a `var x = f<..>(..)` receive is reported ONCE (the receive now
#      resolves the instance ahead of the call's own parse, and must not report it a second time)
#   K  (review) the same on every path that emits its OWN call — `var r = mk3(p, q)`,
#      `var r = mk2(p, 1)`, a struct argument, `r = mk2(p, 6)`, and the explicit `mk2<Pt, i64>(p, ..)`
#      receive and assignment: `_gen_resolve_call` swallowed the failed instantiation and the BASE
#      ran with T = i64, silently (6.6.10 refused them once each). Since 6.7.1 each RUNS with the
#      right value; receiving the `Box<Pt>` result into a plain `Box` is refused as a type mismatch,
#      once, as the one-parameter `mk1(p)` is.
#   O  (review) a `pp: *Pt` parameter binds T to i64 (it is a pointer), not to the pointee:
#      `g(pp)` is refused like `g(5)`, `f(pp) - pp` runs the base (exit 1)
#   P  (review) at top level, `w1s(mkw(gp))` — a register-pair INSTANCE result as a struct
#      argument — is refused by name (the class was read from the 8 B base: SIGSEGV)
#   CF (6.7.11) a generic that reads its STRUCT CARRIER's T field as a struct (`b.v.y`, `b: Box<T>`)
#      has no i64 instance: the filed repro builds and exits 44 (CF1; it failed "expected ';', got '.'"
#      at the definition, called or not), `gy(bi)` / `gy<i32>(bi)` with `bi: Box<i32>` and `gy(bf)`
#      with `bf: Box<f64>` are refused naming 'gy' (CF2-CF4), an uncalled definition builds (CF5), and
#      a field typed `Box<T>` one hop down (`o.inner.v.y`, out of the scan's reach) builds through the
#      documented `var t: T = o.inner.v;` (CF6). The runtime rows are generic_struct_inference.tcyr G12.
#      Filed: docs/development/issues/archived/2026-10-10-generic-base-reads-carrier-field-as-struct.md
#      CF7-CF8 (6.7.14) the stub scan's tables grow: the struct-carrier table (`_gcr`) and the T-typed
#      names (`_gsn`) held 64 entries per generic and dropped the 65th without a word, so a later carrier's
#      `z.v.y` failed "expected ';', got '.'" and a later T-typed local's `z.y` "no struct type in scope
#      for 'z'". CF7 the filed repro (a parameter, 63 `var cN: Box<T>;`, then `z`): exit 44; CF7b 130
#      carriers (two growths): 44; CF8 a parameter, 65 `var cN: T = b;`, then `z.y`: 44; CF8b 130: 44.
#      The bounded receivers' table (`_bnr_tab`) is trait_bounds_checked.sh's B1.
#      Filed: docs/development/issues/archived/2026-10-14-generic-carrier-table-caps-at-64-silently.md
#   FC (6.7.14) a generic forwarding its T INSIDE A STRUCT CARRIER into a stub generic is a stub too: the scan's
#      forwarding mode followed a T-typed name only in the callee's direct carrying position, so `gx(mk1(x))` and
#      `gx(b)` (`b: Box<T>`) into `fn gx<T>(b: Box<T>)` (whose `b.v.y` makes it a stub) left the forwarder an i64
#      base, refused at its definition naming 'gx', called or not. The callee's struct-carrier positions are
#      followed now, given a carrier's name or a generic call carrying T (`_gs_fwd_carr` / `_gs_carries`). FC0 the
#      filed repro verbatim (12); FC1 the local form; FC2 `outer<Pt>(p)`; FC3 / FC3b `outer(5)` refused naming
#      'outer'; FC4 a control into a non-stub carrier generic (its base runs); FC5 the method spelling; FC6
#      `mk1<T>(x)`, a nested `wrap(b)`, two levels; FC7 the definition alone. The runtime rows on every target are
#      generic_forward_tparam.tcyr. Filed: docs/development/issues/2026-10-14-generic-forwarding-carrier-into-stub-
#      generic-refused.md
#      Mutants (2026-10-16, a one-edit scratch copy of the tree each, its 2-stage cycc, this gate run from it):
#      MFC1 no carrier positions (the bite reverted) -> RED 8: FC0-FC3b, FC5-FC7 (each refused naming 'gx');
#      MFC2 `_gs_carries` without its call arm (carrier names only) -> RED 6: FC0 FC2 FC3 FC5 FC6 FC7; MFC3 `_gs_mfwd`
#      without `_gs_fwd_carr` -> RED 1: FC5
#   NN (6.7.14) a type argument that is NO NAME — `Box<1 + 2>`, `Box<u128>`, `id<1 + 2>(3)`, `Box<"s">`, `id<*Pt>`,
#      `Box<>`, `Box<true>`: its token's VALUE was read as a name-pool offset ("unknown type 'truct'" / "'struct'" /
#      "'num'" / "'enum'", a string SIGSEGV'd the compiler), the caret one token late, the call's `+ 2>(3)` left to the
#      statement ("expected ';'", "expected '}'" at EOF), a signature's twice (pass 1 and pass 2). `_targ_not_name`
#      refuses it once at the token ("a type argument is a type name, got number 1"; "u128 cannot be a type
#      argument ..."), steps the argument to its `,` / `>` and reads it as i64. NN0 the filed repro verbatim; NN1-NN8
#      the other tokens and positions; a control. Filed: docs/development/issues/2026-10-14-type-argument-non-name-
#      reported-with-garbage-name.md
#      Mutants (2026-10-16, a one-edit scratch copy of the tree each, its 2-stage cycc, this gate run from it):
#      MNN1 `_parse_one_type_arg` without the non-name arm -> RED 9: NN0-NN8 (the garbage names, the cascade, a
#      signature's twice); MNN2 `_targ_skip_arg` stepping one token -> RED 5: NN0 NN4-NN7 (the cascade); MNN3
#      `_targ_skip_arg` reading a `>` inside `( .. )` as a close -> RED 1: NN5 ("expected '=', got ')'")
#   UG (6.7.14, the user's D2 (a), 2026-10-16) `Name<..>` AS A TYPE ARGUMENT, Name no type: the `<` arm of
#      `_parse_one_type_arg` skipped the list and read class 0, "unbound" — the i64 base: `g<Nonexist<u8>>(0)` ran the
#      base and `var c: Box<Nonexist<u8>>;` declared the base Box (the filed repro exited 11), while `g<Nonexist>(0)`
#      was refused; `h<T<u8>>` inside a generic reached h's base. `_targ_bad_gen` refuses each once, at the name —
#      "unknown type 'Nonexist' as a type argument (...)", "a type parameter takes no type arguments: 'T'" — skips the
#      list and reads i64. UG0 the filed repro verbatim; UG1-UG8 the positions (nested, a type parameter in a call /
#      a field / a local, Two<..>'s either argument, sizeof, a field, a global, two calls, a generic body with three
#      instances); a control (Vec<..>, a generic struct declared below, a forwarded Box<T>, Box<Box<Pt>>). The built-in
#      slice's word form is slice_position_refused.sh's K3 (D3 (a)).
#      Filed: docs/development/issues/archived/2026-10-10-unknown-generic-name-accepted-as-type-argument.md
#      Mutants (2026-10-16, a one-edit scratch copy of the tree each, its 2-stage cycc, this gate run from it):
#      MUG1 `_parse_one_type_arg` without the `_targ_bad_gen` call -> RED 9: UG0-UG8 (each BUILT); MUG2
#      `_targ_bad_gen` without its type-parameter arm -> RED 2: UG2 UG3 ("unknown type 'T'"); MUG3
#      `_targ_bad_gen` reporting without `_tn_once` -> RED 1: UG8 (three lines, one per instance)
#   SG (6.7.14, the user's D6 (a), 2026-10-16) A SIGNATURE'S GENERIC STRUCT READS ITS TYPE ARGUMENTS AT THE DEFINITION:
#      `_gtype_sid` kept the base when an argument did not resolve, so `fn gm(m: Mp<K, V>, b)` (K / V declared nowhere)
#      compiled as the base `Mp`, `m: Box<Zork>` took a `Box<i64>`, while `var m: Mp<K, V>;` was refused. PARSE_FN_DEF's
#      pass 2 reads a parameter's and a return's list as a local's annotation does, minting nothing (`_gtype_sid_def`
#      -> `_targ_chk`). SG0 the filed repro verbatim (once, naming 'K'); SG1-SG7 Mp<Nonexist, i64>, *Mp<K, V>, : Mp<K, V>,
#      m: Box<Zork> called with a Box<i64>, nested and a method's, a generic's own signature with three instances (once),
#      a fn called above its definition; a control (a generic's own K, V; a struct declared below the fns).
#      Filed: docs/development/issues/archived/2026-10-09-undeclared-generic-type-arguments-accepted.md
#      Mutant (2026-10-16, a one-edit scratch copy of the tree, its 2-stage cycc, this gate run from it): MSG1
#      `_gtype_sid_def` without its `_targ_chk` call -> RED 8: SG0-SG7 (each BUILT, as on the compiler before it)
#   NG (6.7.15, the user's D6 (a), 2026-10-18) `Name<..>` ON A NON-GENERIC STRUCT OR A SCALAR: the list was skipped
#      unread — `var c: Pt<i64>;`, `g<Pt<i32>>(0)`, `g<i64<u8>>(0)`, `var b: Box<Pt<nosuch>>;`, `fn f(p: Pt<i64>)`, a
#      `: Pt<i64>` return and `Vec<Pt<nosuch>>` compiled (the filed repro exited 31) and a name inside was never checked.
#      `_ngt_refuse` refuses each once, at the name — "'Pt' is not a generic struct: it takes no type arguments", "'i64'
#      takes no type arguments" — the list skipped and the name's own type read, so nothing cascades. NG0 the filed repro
#      verbatim; NG1-NG8 the positions (a Vec element's in a local and a field; a parameter, a return, `*Pt<..>` both
#      ways, a scalar parameter; local annotations; a literal head, `Box<i32<u8>>`, sizeof, `g<f64<u8>>`; globals; a
#      generic body with three instances; `Box<Result<..>>` keeping its own refusal alone; a pointer return in source
#      order, not pass 1's); a control (Box<Pt>, Box<Box<Pt>>, Vec<i64>, Vec<Box<Pt>>, Vec<Vec<i64>>, g<Box<Pt>>).
#      Filed: docs/development/issues/2026-10-16-non-generic-type-given-type-arguments-compiles.md
#      Mutants (2026-10-18, a one-edit scratch copy of src/ each, its cycc built from it, this gate run with CYCC= it):
#      MNG1 `_ngt_refuse` answering 0 (the bite off) -> RED 8: NG0-NG6, NG8 (each BUILT); MNG2 `_gen_ann_sid`'s
#      non-generic arm without it -> RED 7: NG0 NG2-NG6 NG8; MNG3 its scalar arm without it -> RED 2: NG3 NG5; MNG4 the
#      parameter site without it -> RED 1: NG2; MNG5 `_parse_one_type_arg`'s `<` arm without it -> RED 2: NG0 NG4; MNG6
#      `_vec_el_args` without it -> RED 1: NG1; MNG7 `_ptr_step_peek`'s pass-1 early return gone -> RED 1: NG8 (pass 1
#      reported first); MNG8 `_ptr_tok_sid`'s early return gone -> RED 1: NG8; MNG9 the struct-return site without it
#      -> RED 1: NG2. Defensive, no killing row (named):
#      `_ngt_refuse`'s `_tn_once` — `ERR_IDENT`'s own repeat check (`_err_dup`, 6.7.14) already prints a report at one
#      token once; kept so the latch matches `_tn_refuse`'s.
#   SR (6.7.15, the user's D7 (a), 2026-10-18) THREE MORE SIGNATURE POSITIONS READ A GENERIC STRUCT'S TYPE ARGUMENTS AT
#      THE DEFINITION, as SG's parameter and return do: a multi-value return element `(Box<Zork>, i64)` (`_mret_elem`
#      took `_gtype_sid`, which keeps the base), a trait member's `b: Box<nosuch>` (`_trs_type` skipped the list) and a
#      `*fn(Box<Zork>): i64` parameter type (`_pty_name` skipped it) compiled as the base `Box` (the filed repro exited
#      1). Each is read by `_targ_chk` — every refusal once at its token, nothing instantiated — the fn's and the trait
#      member's own type parameters names. SR0 the filed repro verbatim (three lines); SR1 the element in a generic with
#      two instances (once); SR2 a member's `*Box<Box<Zork>>` parameter and `(Box<Zork>, i64)` return; SR2b a member's
#      walk ends at its first refusal (one report per member, as the reader's others); SR3 `*fn(Box<Zork>)` in a generic
#      with three instances (once); SR4 `**Box<Zork>` (refused before too) still once; a control ((Box<Pt>, i64),
#      `b: Box<i64>` / `Box<U>` / `*fn(Box<U>)` in a member, `*fn(Box<Pt>)`, a generic's own `*fn(Box<U>)`, Box<Later>
#      with Later declared below, in each position).
#      Filed: docs/development/issues/2026-10-16-generic-type-args-unread-in-mret-trait-and-fn-pointer-signatures.md
#      Mutants (2026-10-18, a one-edit scratch copy of src/ each, its cycc built from it, this gate run with CYCC= it):
#      the lane's previous compiler (373ab3d29) -> RED 6: SR0-SR4 (each built; SR4's `**Box<Zork>` alone was refused); MSR1 `_mret_elem`
#      on `_gtype_sid` again -> RED 2: SR0 SR1; MSR2 `_trs_targs` answering 0 -> RED 3: SR0 SR2 SR2b; MSR3 `_pty_targs`
#      answering 0 -> RED 3: SR0 SR3 SR4; MSR4 `_targ_is_tp` without the member's `_trs_fn` arm -> RED 1: the SR control
#      ("unknown type 'U'"); MSR5 `_trs_targs` not ending the walk -> RED 1: SR2b (two lines)
#   M  CONTROLS that must still build and run: a 20,000,001-deep scalar generic TAIL recursion
#      (exit 1; the prototype that diverted every generic off the tail path made it rc 139), a
#      stub generic nobody calls with a scalar (exit 3), a vector local as an inferred argument
#      (exit 10; its descriptor read as "struct 2093"), and the struct call of every H/I shape
#      (exit 12 / 14)
#
# Mutations: drop the `_tp_resolve` consult in _type_arg_leaf -> C, D RED (refused as unknown
# `T`). Drop the refusal -> A, B, F, G RED (rc 0). Drop the `_is_enum_name` arm -> F RED
# (refused, but as an "unknown type"). (6.6.8's third mutation, "let _call_forwarded_base inline
# -> D RED", went GREEN at 6.6.10 and that fn was retired: outer's base is now a transitive stub
# whose body is skipped, so no replay of the inlinable inner<T> is left for it to suppress.)
# 6.6.10 (src/frontend/parse_fn.cyr; each run on a scratch tree, never the repo):
#   `_gen_call_head` never calls _refuse_gen_stub     -> H, I RED (rc 0, the stub's 0)
#   drop `_tc_generic_divert` from _tc_must_divert     -> H's `return g(5)` RED (rc 0)
#   _tc_generic_divert returns 1 for EVERY generic      -> M's tail recursion RED (rc 139)
#   `_gen_close` returns at once (no transitive half)   -> I RED (rc 0)
#   drop the `_gen_addr_check` call (parse_expr.cyr)    -> J RED (rc 0)
#   6.7.1: `_instantiate_generic_fn` refusing a struct beside a second type argument again (the
#   pre-6.7.1 `-3`) -> K RED (refused, rc 1)
#   drop the `_gen_own_call_check` in the asv_pair receive (parse_decl.cyr) -> L RED (rc 0)
#   drop the vector guard in _infer_conc_at_cursor      -> M's vector row RED
#   drop the `_targs_resolvable` early-out in _gen_resolve_call -> N RED (reported twice)
#   6.7.11: `_gs_use` mode 0 without `_gs_cfield` -> CF1 / CF5 RED (the definition fails), CF2-CF4
#   RED (refused, but by the parse error, not by name)
#   6.7.14 (a one-edit scratch copy of the tree each, its 2-stage mutant cycc, this gate run from it):
#   `_gcr_add` dropping at 64 again -> CF7 / CF7b RED ("expected ';', got '.'"), CF8 green;
#   `_gsn_add` dropping at 64 again -> CF8 / CF8b RED ("no struct type in scope for 'z'"), CF7 green
#   (review) `_is_ptr_param` / `_mark_ptr_param` inert -> O RED;
#   `_refuse_toplevel_pair_arg` on FINDFN -> P RED (BUILT)
# The runtime halves (inference on every path, signature types) are mutation-proven by
# tests/tcyr/crossos/generic_struct_inference.tcyr — its header lists them.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: generic_type_arg_unknown_refused: no compiler at $CC"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "SKIP: generic_type_arg_unknown_refused: mktemp -d failed"; exit 77; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
build() { rc=0; "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; }
refused() { # <name> <ident> <what>
    build "$1"
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -q "unknown type '$2' as a type argument" "$T/$1.err"; then
        bad "$3: refused, but not by name: $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$3: refused, naming '$2'"; fi
}
exits() {   # <name> <want> <what>
    build "$1"
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}

printf 'fn id<T>(v: T): i64 { return v + 1; }\nfn main(): i64 { return id<Nope>(4); }\nsyscall(60, main());\n' > "$T/a.cyr"
refused a Nope "A: an unknown type name as a type argument"
printf 'fn id<T>(v: T): i64 { return v + 1; }\nfn main(): i64 { var k = 3; return id<k>(4); }\nsyscall(60, main());\n' > "$T/b.cyr"
refused b k "B: a variable as a type argument"

printf 'struct Pt { x; y; }\nfn inner<T>(p: T): i64 { var s = 0; var i = 0; while (i < 4) { s = s + p.y; i = i + 1; } return s + p.x; }\nfn outer<T>(p: T): i64 { var r = inner<T>(p); return r + 2; }\nfn top(a): i64 { var p: Pt; p.x = a; p.y = 3; var r = outer<Pt>(p); return r; }\nsyscall(60, top(2));\n' > "$T/c.cyr"
exits c 16 "C: a forwarded T reaches the looping struct instance"
printf 'struct Pt { x; y; }\nfn inner<T>(p: T): i64 { return p.y * 4 + p.x; }\nfn outer<T>(p: T): i64 { var r = inner<T>(p); return r + 2; }\nfn top(a): i64 { var p: Pt; p.x = a; p.y = 3; return outer<Pt>(p); }\nsyscall(60, top(2));\n' > "$T/d.cyr"
exits d 16 "D: a forwarded T reaches the inlinable struct instance"

printf 'struct Pt { x; y; }\nfn id<T>(v: T): i64 { return v + 1; }\nfn gx<T>(p: T): i64 { return p.x; }\nfn main(): i64 { var p: Pt; p.x = 30; p.y = 1; return id<i64>(4) + id<i32>(4) + gx<Pt>(p); }\nsyscall(60, main());\n' > "$T/e.cyr"
exits e 40 "E: control: i64 / i32 / struct type arguments"

printf 'enum Color { RED; GREEN; }\nfn id<T>(v: T): i64 { return v + 1; }\nfn main(): i64 { return id<Color>(4); }\nsyscall(60, main());\n' > "$T/f.cyr"
build f
if [ "$rc" -eq 0 ]; then bad "F: an enum name as a type argument: BUILT (rc 0)"
elif ! grep -q "'Color' is an enum, not a type argument" "$T/f.err"; then
    bad "F: an enum name as a type argument: refused, but not as an enum: $(grep '^error' "$T/f.err" | head -1)"
else ok "F: an enum name as a type argument: refused as an enum"; fi

for w in u64 u8 bool ptr f32; do
    printf 'fn id<T>(v: T): i64 { return v + 1; }\nfn main(): i64 { return id<%s>(4); }\nsyscall(60, main());\n' "$w" > "$T/g_$w.cyr"
    refused "g_$w" "$w" "G: '$w' as a type argument"
done

# ── 6.6.10 (bite 7): a generic that uses T as a struct has no scalar instance ──────────────────
stubref() {   # <name> <fn-named> <what> — refused, naming <fn-named>, as having no i64 instance
    build "$1"
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -q "generic '$2' has no i64 (or other scalar) instance" "$T/$1.err"; then
        bad "$3: refused, but not by name: $(grep '^error' "$T/$1.err" | head -1)"
    elif grep -q "no struct type in scope" "$T/$1.err"; then
        bad "$3: refused, but ALSO with the misleading 'no struct type in scope'"
    else ok "$3: refused, naming '$2'"; fi
}
GL='fn g<T>(p: T): i64 { var s = 0; var i = 0; while (i < 2) { s = s + p.y; i = i + 1; } return s + p.x; }'
GF='fn g<T>(p: T): i64 { return p.y * 2 + p.x; }'
PT='struct Pt { x; y; }'
MKP='var p: Pt; p.x = 2; p.y = 5;'
n=0
for call in 'g<i64>(5) + 7' 'g(5) + 7' 'g<i32>(5)'; do
    n=$((n + 1))
    printf '%s\n%s\nfn main(): i64 { return %s; }\nsyscall(60, main());\n' "$PT" "$GL" "$call" > "$T/h$n.cyr"
    stubref "h$n" g "H: $call"
done
for call in 'g<i64>(5)' 'g(5)'; do
    n=$((n + 1))
    printf '%s\n%s\nfn main(): i64 { return %s; }\nsyscall(60, main());\n' "$PT" "$GL" "$call" > "$T/h$n.cyr"
    stubref "h$n" g "H: return $call (tail position)"
done
for call in 'g<i64>(5) + 7' 'g(5) + 7'; do
    n=$((n + 1))
    printf '%s\n%s\nfn main(): i64 { return %s; }\nsyscall(60, main());\n' "$PT" "$GF" "$call" > "$T/h$n.cyr"
    stubref "h$n" g "H: $call, an inlinable body"
done

OE='fn outer<T>(p: T): i64 { var r = g<T>(p); return r + 2; }'
OI='fn outer<T>(p: T): i64 { var r = g(p); return r + 2; }'
printf '%s\n%s\n%s\nfn main(): i64 { return outer<i64>(5) + 7; }\nsyscall(60, main());\n' "$PT" "$GL" "$OE" > "$T/i1.cyr"
stubref i1 outer "I: outer<i64>(5), outer forwarding g<T>(p)"
printf '%s\n%s\n%s\nfn main(): i64 { return outer(5) + 7; }\nsyscall(60, main());\n' "$PT" "$GL" "$OI" > "$T/i2.cyr"
stubref i2 outer "I: outer(5), outer forwarding g(p) by inference"
printf '%s\nfn main(): i64 { return outer(5) + 7; }\n%s\n%s\nsyscall(60, main());\n' "$PT" "$OI" "$GL" > "$T/i3.cyr"
stubref i3 outer "I: the same, main -> outer -> g defined in REVERSE order"
printf '%s\nfn outer2<T>(p: T): i64 { return outer(p) + 1; }\n%s\n%s\nfn main(): i64 { return outer2(5); }\nsyscall(60, main());\n' "$PT" "$OI" "$GL" > "$T/i4.cyr"
stubref i4 outer2 "I: two levels of forwarding"

printf 'include "lib/fnptr.cyr"\n%s\n%s\nfn main(): i64 { %s var f = &g; return fncall1(f, &p) + 7; }\nsyscall(60, main());\n' "$PT" "$GL" "$MKP" > "$T/j.cyr"
stubref j g "J: &g"

build_refused_by() {   # <name> <grep> <what>
    build "$1"
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif ! grep -q "$2" "$T/$1.err"; then bad "$3: refused, but not as expected: $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$3: refused"; fi
}
# K (6.7.1, C3) — a struct beside a second type argument RUNS (refused 6.6.10 → 6.7.0).
printf '%s\nstruct Q { a; b; c; }\nfn g2<T, U>(p: T, q: U): i64 { var s = 0; var i = 0; while (i < 1) { s = s + p.y + q.c; i = i + 1; } return s; }\nfn main(): i64 { %s var q: Q; q.a = 1; q.b = 1; q.c = 9; return g2(p, q); }\nsyscall(60, main());\n' "$PT" "$MKP" > "$T/k1.cyr"
exits k1 14 "K: g2(p, q), two struct type args inferred"
printf '%s\nfn g2<T, U>(p: T, n: U): i64 { var s = 0; var i = 0; while (i < n) { s = s + p.y; i = i + 1; } return s; }\nfn main(): i64 { %s return g2(p, 2); }\nsyscall(60, main());\n' "$PT" "$MKP" > "$T/k2.cyr"
exits k2 10 "K: g2(p, 2), a struct beside a scalar"

# ...and on every path that emits its OWN call. Receiving the `Box<Pt>` result into a plain `Box`
# (the base, a different layout) is a type mismatch, refused ONCE as `mk1(p)`'s is.
mismatch_once() {   # <name> <what>
    build "$1"
    k=$(grep -c "cannot copy 'mk[123]' into a variable of a different struct" "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$2: BUILT (rc 0)"
    elif [ "$k" -ne 1 ]; then bad "$2: refused $k times as a mismatch, want 1: $(grep '^error' "$T/$1.err" | head -1)"
    else ok "$2: refused once, as a type mismatch"; fi
}
BX='struct Box<T> { v: T; n; }
struct Q { a; b; c; }
fn mk1<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn mk2<T, U>(x: T, n: U): Box<T> { var b: Box<T>; b.v = x; b.n = n; return b; }
fn mk3<T, U>(x: T, y: U): Box<T> { var b: Box<T>; b.v = x; b.n = 7; return b; }
fn bsp(b: Box<Pt>): i64 { return b.n + b.v.y; }'
n=0
for row in '7|var q: Q; q.c = 1; var r = mk3(p, q); return r.n;' '1|var r = mk2(p, 1); return r.n;' \
        '9|return bsp(mk2(p, 4));' '8|var r: Box<Pt>; r = mk2(p, 6); return r.n + r.v.x;' \
        '1|var r: Box<Pt> = mk2<Pt, i64>(p, 1); return r.n;' '8|var r: Box<Pt>; r = mk2<Pt, i64>(p, 6); return r.n + r.v.x;' \
        'X|var r: Box; r = mk2(p, 6); return r.n;' 'X|var r: Box; r = mk2<Pt, i64>(p, 6); return r.n;' \
        'X|var r: Box; r = mk1(p); return r.n;'; do
    n=$((n + 1))
    want=${row%%|*}
    body=${row#*|}
    printf '%s\n%s\nfn main(): i64 { %s %s }\nsyscall(60, main());\n' "$PT" "$BX" "$MKP" "$body" > "$T/ko$n.cyr"
    if [ "$want" = X ]; then mismatch_once "ko$n" "K: $body"
    else exits "ko$n" "$want" "K: $body"; fi
done

printf '%s\nstruct Box<T> { v: T; n; }\nfn mkb<T>(p: T): Box<T> { var b: Box<T>; b.n = p.x; return b; }\nfn main(): i64 { var r: Box<i64> = mkb(5); return r.n; }\nsyscall(60, main());\n' "$PT" > "$T/l.cyr"
stubref l mkb "L: var r: Box<i64> = mkb(5), a stub generic on the struct-receive path"

# O (review) — a `pp: *Pt` parameter is a POINTER: it binds T to i64, like a `var q: *Pt` local,
# not to the pointee (the parameter loop skips the `*`, so its slot is typed `Pt`). A struct-using
# generic is then refused by name; an arithmetic one runs the base.
printf '%s\n%s\nfn h(pp: *Pt): i64 { return g(pp); }\nfn main(): i64 { %s return h(&p); }\nsyscall(60, main());\n' "$PT" "$GL" "$MKP" > "$T/o1.cyr"
stubref o1 g "O: g(pp) for a \`pp: *Pt\` parameter binds i64"
printf '%s\nfn f<T>(v: T): i64 { return v + 1; }\nfn h(pp: *Pt): i64 { return f(pp) - pp; }\nfn main(): i64 { %s return h(&p); }\nsyscall(60, main());\n' "$PT" "$MKP" > "$T/o2.cyr"
exits o2 1 "O: f(pp) - pp for a \`pp: *Pt\` parameter runs the i64 base"

# P (review) — at top level a register-pair INSTANCE result as a struct argument has no frame to
# land in: refused by name like a plain fn's (the class was read from the 8 B base: SIGSEGV).
printf '%s\nstruct W1<T> { v: T; }\nfn mkw<T>(x: T): W1<T> { var w: W1<T>; w.v = x; return w; }\nfn w1s(w: W1<Pt>): i64 { return w.v.x + w.v.y * 10; }\nvar gp: Pt = Pt { 2, 5 };\nsyscall(60, w1s(mkw(gp)));\n' "$PT" > "$T/p1.cyr"
build_refused_by p1 "'mkw' returns a struct by value, and a struct result needs storage in a fn's frame" "P: w1s(mkw(gp)) at top level, a W1<Pt> pair instance"

# Q (6.6.11, L9) — A GLOBAL TYPED WITH A GENERIC STRUCT INSTANCE. A declaration-zone global
# (before the first top-level statement) is registered by PARSE_GVAR_REG, which took `W1<Pt>` as
# the 8 B BASE: `G.v.x` did not parse and `w1s(G)` read the wrong storage (204, want 52). Its
# initialiser is replayed by EMIT_GVAR_INITS, which never reached the rax:rdx refusal, so even a
# NON-generic `var G: Pt = mkp(2);` there built and SIGSEGV'd on `G.x`; after a statement the
# refusal resolved the callee with FINDFN (the 8 B base's class 0), so the generic form built too.
MKW='struct W1<T> { v: T; }
fn mkw<T>(x: T): W1<T> { var w: W1<T>; w.v = x; return w; }
fn w1s(w: W1<Pt>): i64 { return w.v.x + w.v.y * 10; }
var gp: Pt = Pt { 2, 5 };'
MKPP='fn mkp(a): Pt { var w: Pt; w.x = a; w.y = 5; return w; }'
PAIR="returns a struct by value, and a struct result needs storage in a fn's frame"
printf '%s\n%s\nvar G: W1<Pt> = mkw(gp);\nsyscall(60, w1s(G));\n' "$PT" "$MKW" > "$T/q1.cyr"
build_refused_by q1 "'mkw' $PAIR" "Q: var G: W1<Pt> = mkw(gp) before the first statement (was 204)"
printf '%s\n%s\nvar k = 0;\nk = 1;\nvar G: W1<Pt> = mkw(gp);\nsyscall(60, w1s(G));\n' "$PT" "$MKW" > "$T/q2.cyr"
build_refused_by q2 "'mkw' $PAIR" "Q: the same after a statement (was rc 139)"
printf '%s\n%s\nvar G: W1<Pt> = mkw<Pt>(gp);\nsyscall(60, w1s(G));\n' "$PT" "$MKW" > "$T/q3.cyr"
build_refused_by q3 "'mkw' $PAIR" "Q: the explicit mkw<Pt>(gp) before the first statement"
printf '%s\n%s\nvar G: Pt = mkp(2);\nsyscall(60, G.x + G.y * 10);\n' "$PT" "$MKPP" > "$T/q4.cyr"
build_refused_by q4 "'mkp' $PAIR" "Q: a NON-generic var G: Pt = mkp(2) before the first statement (was SIGSEGV)"
printf '%s\n%s\nvar gr: W1<Pt>;\nfn f(): i64 { gr.v.x = 2; return gr.v.x; }\nsyscall(60, f());\n' "$PT" "$MKW" > "$T/q5.cyr"
build_refused_by q5 "uninitialized variable not allowed" "Q: a bare var gr: W1<Pt>; is the uninitialised refusal"
grep -q "expected '=', got '.'" "$T/q5.err" && bad "Q: gr.v.x on a bare var gr: W1<Pt>; did not parse (the global was the 8 B base)"
printf 'include "lib/alloc.cyr"\n%s\n%s\nvar G: W1<Pt> = alloc(16);\nfn f(): i64 { G.v.x = 2; G.v.y = 5; return w1s(G); }\nvar r = f();\nsyscall(60, r + G.v.x);\n' "$PT" "$MKW" > "$T/q6.cyr"
exits q6 54 "Q: a W1<Pt> global holding an address: G.v.x written in a fn, read at top level, w1s(G)"
printf 'include "lib/alloc.cyr"\n%s\n%s\nvar k = 0;\nk = 1;\nvar G: W1<Pt> = alloc(16);\nG.v.x = 3; G.v.y = 4;\nsyscall(60, w1s(G) + G.v.y);\n' "$PT" "$MKW" > "$T/q7.cyr"
exits q7 47 "Q: control: the same after a statement (PARSE_VAR already instantiated)"
printf 'struct B1<T> { v: T; }\nfn mkb<T>(x: T): B1<T> { var b: B1<T>; b.v = x; return b; }\nvar B: B1<i32> = mkb<i32>(7);\nsyscall(60, B.v);\n' > "$T/q8.cyr"
exits q8 7 "Q: control: an 8 B instance global from its call (rax, no pair)"

printf 'fn cnt<T>(n: T, acc: T): T { if (n == 0) { return acc; } return cnt(n - 1, acc + 1); }\nfn main(): i64 { return cnt(20000001, 0) & 127; }\nsyscall(60, main());\n' > "$T/m1.cyr"
exits m1 1 "M: a 20,000,001-deep scalar generic tail recursion"
printf '%s\n%s\nfn main(): i64 { return 3; }\nsyscall(60, main());\n' "$PT" "$GL" > "$T/m2.cyr"
exits m2 3 "M: a stub generic nobody calls with a scalar"
printf 'include "lib/simd.cyr"\nfn tw<T>(v: T): i64 { return 5; }\nfn tl<T>(v: T): i64 { var s = 0; var i = 0; while (i < 2) { s = s + 1; i = i + 1; } return s + 3; }\nfn main(): i64 { var a: f64v2; return tw(a) + tl(a); }\nsyscall(60, main());\n' > "$T/m3.cyr"
exits m3 10 "M: a vector local as an inferred argument"
# ...and it is the BASE call: byte-identical to the explicit `<i64>` spelling. Read as "struct
# 2093" the inference minted an instance named from out-of-table memory — invisible in the exit
# code, visible here as a different binary.
sed 's/tw(a) + tl(a)/tw<i64>(a) + tl<i64>(a)/' "$T/m3.cyr" > "$T/m3x.cyr"
build m3x
if [ "$rc" -ne 0 ]; then bad "M: the explicit vector control: rc $rc"
elif cmp -s "$T/m3.bin" "$T/m3x.bin"; then ok "M: a vector argument infers the base, byte-identical to tw<i64>(a)"
else bad "M: a vector argument minted an instance (differs from tw<i64>(a))"; fi
printf '%s\n%s\nfn tail(a): i64 { var p: Pt; p.x = a; p.y = 5; return g(p); }\nfn main(): i64 { %s var r = g(p); return r * 0 + tail(2); }\nsyscall(60, main());\n' "$PT" "$GL" "$MKP" > "$T/m4.cyr"
exits m4 12 "M: the struct call of the H shapes (var r = g(p); return g(p))"
printf '%s\n%s\nfn main(): i64 { %s return outer(p); }\n%s\nsyscall(60, main());\n' "$PT" "$OI" "$MKP" "$GL" > "$T/m5.cyr"
exits m5 14 "M: the struct call of the I shape, reverse order (outer(p) -> g(p))"

printf 'fn idv<T>(a: T): T { return a; }\nfn main(): i64 { var v: f64v2; var a = idv<f64v2>(v); return 42; }\nsyscall(60, main());\n' > "$T/n.cyr"
build n
nerr=$(grep -c "generic type-args must be a scalar" "$T/n.err" || true)
if [ "$rc" -eq 0 ]; then bad "N: var a = idv<f64v2>(v): BUILT (rc 0)"
elif [ "$nerr" -ne 1 ]; then bad "N: var a = idv<f64v2>(v): the refusal printed $nerr times, want 1"
else ok "N: var a = idv<f64v2>(v): refused once"; fi

# ── 6.7.11: a struct carrier's T field read as a struct ────────────────────────────────────────
cp docs/development/issues/repros/2026-10-10-generic-base-reads-carrier-field-as-struct.cyr "$T/cf1.cyr" 2> /dev/null \
    || { bad "CF1: the filed repro is missing"; : > "$T/cf1.cyr"; }
exits cf1 44 "CF1: the filed repro, verbatim (gy(b) * 10 + gy<Pt>(b))"
CFH='struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn gy<T>(b: Box<T>): i64 { return b.v.y; }'
printf '%s\nfn go(): i64 { var bi: Box<i32>; bi.v = 3; bi.n = 8; return gy(bi); }\nsyscall(60, go());\n' "$CFH" > "$T/cf2.cyr"
stubref cf2 gy "CF2: gy(bi), bi: Box<i32>"
printf '%s\nfn go(): i64 { var bi: Box<i32>; bi.v = 3; bi.n = 8; return gy<i32>(bi); }\nsyscall(60, go());\n' "$CFH" > "$T/cf3.cyr"
stubref cf3 gy "CF3: gy<i32>(bi)"
printf '%s\nfn go(): i64 { var bf: Box<f64>; bf.v = 1.5; bf.n = 8; return gy(bf); }\nsyscall(60, go());\n' "$CFH" > "$T/cf4.cyr"
stubref cf4 gy "CF4: gy(bf), bf: Box<f64>"
printf '%s\nsyscall(60, 5);\n' "$CFH" > "$T/cf5.cyr"
exits cf5 5 "CF5: the definition alone, never called"
printf 'struct Pt { x; y; }\nstruct Box<T> { v: T; n; }\nstruct Out<T> { inner: Box<T>; k; }\nfn gd<T>(o: Out<T>): i64 { var t: T = o.inner.v; return t.y; }\nfn go(): i64 { var o: Out<Pt>; o.inner.v.x = 1; o.inner.v.y = 6; o.k = 2; return gd(o); }\nsyscall(60, go());\n' > "$T/cf6.cyr"
exits cf6 6 "CF6: one hop down (o.inner.v), through the documented T-typed local"

# CF7-CF8 (6.7.14): more than 64 carriers / T-typed names in one generic. `cfgen <name> <n> <decl>`:
# `gy<T>(b: <param>)` with <n> locals `var cN<decl>`, then `var z<decl> = b;`; the body's last line is $CFR.
cfgen() {
    { printf 'include "lib/syscalls.cyr"\nstruct Pt { x; y; }\nstruct Box<T> { v: T; n; }\nfn gy<T>(b: %s): i64 {\n' "$CFP"
      k=1; while [ "$k" -le "$2" ]; do printf '    var c%d%s;\n' "$k" "$3"; k=$((k + 1)); done
      printf '    var z%s = b;\n    %s\n}\n%s\nsyscall(60, main());\n' "$CFZ" "$CFR" "$CFM"; } > "$T/$1.cyr"
}
CFP='Box<T>'; CFZ=': Box<T>'; CFR='return z.v.y;'
CFM='fn main(): i64 { var b: Box<Pt>; b.v.x = 3; b.v.y = 44; b.n = 1; return gy(b); }'
cfgen cf7 63 ': Box<T>'
exits cf7 44 "CF7: the filed repro — a parameter, 63 \`var cN: Box<T>;\` carriers, then \`z.v.y\` (the 65th was dropped)"
cfgen cf7b 130 ': Box<T>'
exits cf7b 44 "CF7b: 130 carriers (the table grows twice)"
CFP='T'; CFZ=': T'; CFR='return z.y;'
CFM='fn main(): i64 { var p: Pt; p.x = 3; p.y = 44; return gy(p); }'
cfgen cf8 65 ': T = b'
exits cf8 44 "CF8: a parameter, 65 \`var cN: T = b;\` T-typed locals, then \`z.y\`"
cfgen cf8b 130 ': T = b'
exits cf8b 44 "CF8b: 130 T-typed locals (the table grows twice)"

# ── 6.7.14: a generic forwarding its T inside a struct carrier into a stub generic ─────────────────
cat > "$T/fc0.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn mk1<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn gx<T>(b: Box<T>): i64 { return b.n + b.v.y; }
fn outer<T>(x: T): i64 { return gx(mk1(x)); }
fn go(): i64 {
    var p: Pt; p.x = 3; p.y = 4;
    return outer(p);
}
syscall(60, go());
EOF
exits fc0 12 "FC0: the filed repro, verbatim (outer(p) -> gx(mk1(x)), 8 + 4)"
FCH='include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn mk1<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn gx<T>(b: Box<T>): i64 { return b.n + b.v.y; }'
FCP='var p: Pt; p.x = 3; p.y = 4;'
fcmk() {   # <name> <decls> <go body>
    printf '%s\n%s\nfn go(): i64 { %s }\nsyscall(60, go());\n' "$FCH" "$2" "$3" > "$T/$1.cyr"
}
FCL='fn outer<T>(x: T): i64 { var b: Box<T> = mk1(x); return gx(b); }'
fcmk fc1 "$FCL" "$FCP return outer(p);"
exits fc1 12 "FC1: the carrier spelled as a local, \`var b: Box<T> = mk1(x); return gx(b);\`"
fcmk fc2 'fn outer<T>(x: T): i64 { return gx(mk1(x)); }' "$FCP return outer<Pt>(p);"
exits fc2 12 "FC2: outer<Pt>(p), explicit"
fcmk fc3 'fn outer<T>(x: T): i64 { return gx(mk1(x)); }' 'return outer(5);'
stubref fc3 outer "FC3: outer(5) — the forwarder is a stub, refused naming it"
fcmk fc3b "$FCL" 'return outer(5);'
stubref fc3b outer "FC3b: the local form, outer(5)"
fcmk fc4 'fn gn<T>(b: Box<T>): i64 { return b.n + 1; }
fn outer<T>(x: T): i64 { return gn(mk1(x)); }' "$FCP return outer(p) * 10 + outer(5);"
exits fc4 99 "FC4: control — a forwarder into a NON-stub carrier generic keeps its i64 base (outer(5) runs)"
fcmk fc5 'struct P { a; }
impl P { fn pick<T>(self, b: Box<T>): i64 { return self.a + b.v.y; } }
fn om<T>(q: P, x: T): i64 { var b: Box<T> = mk1(x); return q.pick(b); }
fn om2<T>(q: P, x: T): i64 { return q.pick(mk1(x)); }' "$FCP var q: P = P { 10 }; return om(q, p) + om2(q, p);"
exits fc5 28 "FC5: the method spelling, q.pick(b) / q.pick(mk1(x)) into a stub generic method"
fcmk fc6 'fn wrap<T>(b: Box<T>): Box<T> { var c: Box<T> = b; c.n = 9; return c; }
fn o1<T>(x: T): i64 { return gx(mk1<T>(x)); }
fn o2<T>(x: T): i64 { var b: Box<T> = mk1(x); return gx(wrap(b)); }
fn o3<T>(x: T): i64 { return o1(x) + 100; }' "$FCP return o1(p) + o2(p) + o3(p);"
exits fc6 137 "FC6: gx(mk1<T>(x)) 12 + gx(wrap(b)) 13 + a two-level o3 -> o1 112"
fcmk fc7 'fn outer<T>(x: T): i64 { return gx(mk1(x)); }' 'return 7;'
exits fc7 7 "FC7: the definition alone, never called (it was refused there)"

# ── 6.7.14: a type argument that is no name ────────────────────────────────────────────────────
# `errs <name> <n> <what> <line>...`: refused with exactly <n> `^error` lines, each <line> among them (grep -F).
errs() {
    nm=$1; want=$2; what=$3; shift 3
    build "$nm"
    k=$(grep -c '^error' "$T/$nm.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$what: BUILT (rc 0)"; return; fi
    if [ "$rc" -ne 1 ]; then bad "$what: the compiler died (rc $rc)"; return; fi
    if [ "$k" -ne "$want" ]; then bad "$what: $k error lines (want $want): $(grep '^error' "$T/$nm.err" | head -3 | tr '\n' ' ')"; return; fi
    for l in "$@"; do
        if ! grep -qF -- "$l" "$T/$nm.err"; then bad "$what: no line '$l': $(grep '^error' "$T/$nm.err" | head -3 | tr '\n' ' ')"; return; fi
    done
    ok "$what: refused, $k error line(s) as wanted"
}
NM="a type argument is a type name, got"
U1="u128 cannot be a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)"
cat > "$T/nn0.cyr" <<'EOF'
struct Box<T> { v: T; }
fn id<T>(x: T): T { return x; }
fn main(): i64 {
    var a: Box<1 + 2>;
    var b: Box<u128>;
    return id<1 + 2>(3);
}
syscall(60, main());
EOF
errs nn0 3 "NN0: the filed repro verbatim — one error per argument, at its token, no cascade (was 'truct' / 'struct' x3 + 2)" \
    "error:<source>:4:16: $NM number 1" "error:<source>:5:16: $U1" "error:<source>:6:15: $NM number 1"
NNH='struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct Two<A, B> { a: A; b: B; }
fn id<T>(x: T): T { return x; }'
nn() { printf '%s\n%s\nsyscall(60, 7);\n' "$NNH" "$2" > "$T/$1.cyr"; }
nn nn1 'fn f(): i64 { var a: Box<"s">; return 0; }'
errs nn1 1 "NN1: Box<\"s\"> (its string offset read as a name: a garbage name, or the compiler died, rc 139)" "$NM string"
nn nn2 'fn f(x: Box<1>): i64 { return 0; }'
errs nn2 1 "NN2: a parameter's Box<1>, once (twice: pass 1 and pass 2)" "error:<source>:5:13: $NM number 1"
nn nn3 'fn g<T>(x: T): *Box<1> { return 0; }
fn h(): i64 { var a = g(1); var b = g<i32>(2); return 0; }'
errs nn3 1 "NN3: a generic's *Box<1> return with two instances, once (three times)" "$NM number 1"
nn nn4 'fn f(): i64 { var a: Two<1 + 2, 3>; var b: Two<i32, 1>; return 0; }'
errs nn4 3 "NN4: Two<1 + 2, 3> and Two<i32, 1> — each argument once" \
    "error:<source>:5:26: $NM number 1" "error:<source>:5:33: $NM number 3" "error:<source>:5:53: $NM number 1"
nn nn5 'fn f(): i64 { var a: Box<1 + (2 > 1)>; var b: Box<Box<1>>; var c: Two<Box<1>, i32>; return sizeof(Two<Box<1>, i32>); }'
errs nn5 4 "NN5: a comparison inside parentheses, a nested Box<Box<1>> (its >>), Two<Box<1>, i32>, sizeof(..) — no cascade" \
    "error:<source>:5:26: $NM number 1"
nn nn6 'fn f(): i64 { var p: Pt; return id<1 + 2>(3) + id<i32>(3) + id<*Pt>(p) + id<>(4); }'
errs nn6 3 "NN6: id<1 + 2>(3), id<*Pt>(p), id<>(4) in one expression" "$NM number 1" "$NM '*'" "$NM '>'"
nn nn7 'fn f(): i64 { var a: Box<true>; var b: Box<fn>; var c: Box<-1>; return 0; }'
errs nn7 3 "NN7: Box<true>, Box<fn>, Box<-1>" "$NM true" "$NM fn" "$NM '-'"
nn nn8 'fn f(): i64 { return id<u128>(3); }'
errs nn8 1 "NN8: id<u128>(3), by its text, once (twice)" "$U1"
printf '%s\nfn main(): i64 { var a: Box<i64>; a.n = 3; var b: Two<Pt, i32>; b.b = 4; return a.n + b.b + id<i32>(3) + sizeof(Box<i16>) - 20; }\nsyscall(60, main());\n' "$NNH" > "$T/nnk.cyr"
exits nnk 0 "NN control: Box<i64>, Two<Pt, i32>, id<i32>(3), sizeof(Box<i16>) (10) unchanged"

# ── 6.7.14: `Name<..>` as a type argument, Name no type (the user's D2 (a), 2026-10-16) ──────────
UK="unknown type 'Nonexist' as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)"
TPA="a type parameter takes no type arguments: 'T'"
cp docs/development/issues/repros/2026-10-10-unknown-generic-name-accepted-as-type-argument.cyr "$T/ug0.cyr" 2> /dev/null \
    || { bad "UG0: the filed repro is missing"; : > "$T/ug0.cyr"; }
errs ug0 2 "UG0: the filed repro verbatim — both lines refused by name, once each, at the name (it ran the i64 base: exit 11)" \
    "error:<source>:6:16: $UK" "error:<source>:8:14: $UK"
UGH='include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct Two<A, B> { a: A; b: B; }'
ug() { printf '%s\n%s\nsyscall(60, 7);\n' "$UGH" "$2" > "$T/$1.cyr"; }
ug ug1 'fn f(): i64 { var c: Box<Box<Nonexist<u8>>>; c.n = 3; return c.n; }'
errs ug1 1 "UG1: nested, Box<Box<Nonexist<u8>>> (its >>> closes three lists)" "error:<source>:5:30: $UK"
ug ug2 'fn h<T>(x): i64 { return sizeof(T); }
fn g<T>(x): i64 { return h<T<u8>>(0); }
fn f(): i64 { return g<Pt>(0) + g<i32>(0) + g(1); }'
errs ug2 1 "UG2: h<T<u8>>(0) inside a generic, with three instances — once (g\$Pt reached h's base)" "error:<source>:6:28: $TPA"
ug ug3 'struct W<T> { b: Box<T<u8>>; k; }
fn g<T>(x): i64 { var q: Box<T<i32>>; return 0; }
fn f(): i64 { var w: W<Pt>; return g<Pt>(0) + sizeof(W<Pt>); }'
errs ug3 2 "UG3: a type parameter given arguments in a generic struct's field and a generic's local — once each" \
    "error:<source>:5:22: $TPA" "error:<source>:6:30: $TPA"
ug ug4 'fn f(): i64 { var t: Two<Nonexist<u8>, i32>; var u: Two<i32, Nonexist<Box<i64>>>; return sizeof(Box<Nonexist<u8>>); }'
errs ug4 3 "UG4: either argument of Two<..>, a nested list inside the skipped one, sizeof(..)" \
    "error:<source>:5:26: $UK" "error:<source>:5:62: $UK" "error:<source>:5:101: $UK"
ug ug5 'struct H { b: Box<Nonexist<u8>>; n; }'
errs ug5 1 "UG5: a struct field's Box<Nonexist<u8>>" "error:<source>:5:19: $UK"
ug ug6 'fn f(): i64 { return 0; }
var GB: Box<Nonexist<u8>> = 0;'
errs ug6 1 "UG6: a global's Box<Nonexist<u8>>" "error:<source>:6:13: $UK"
ug ug7 'fn g<T>(x): i64 { return sizeof(T); }
fn f(): i64 { var a = g<Nonexist<u8>>(0); return a + g<Nonexist<i64>>(1); }'
errs ug7 2 "UG7: two explicit calls in two statements — once each, no instance minted, no cascade" \
    "error:<source>:6:25: $UK" "error:<source>:6:56: $UK"
ug ug8 'fn g<T>(x): i64 { var c: Box<Nonexist<T>>; return sizeof(T); }
fn f(): i64 { return g<Pt>(0) + g<i32>(0) + g(1); }'
errs ug8 1 "UG8: a generic body's Box<Nonexist<T>> with three instances — once (the base and each instance re-read it)" "error:<source>:5:30: $UK"
cat > "$T/ugk.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/vec.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn g<T>(x): i64 { return sizeof(T); }
fn h<T>(x): i64 { return g<Box<T>>(0); }
fn main(): i64 {
    var b: Box<Box<Pt>>;
    b.v.v.y = 2;
    return g<Vec<i64>>(0) + g<Later<i32>>(0) * 10 + h<Pt>(0) * 100 + b.v.v.y * 1000 + sizeof(Box<Box<Pt>>) * 10000;
}
struct Later<T> { a: T; b: T; }
syscall(60, (main() - 322168) / 100000);
EOF
exits ugk 0 "UG control: g<Vec<i64>>(0) 8, g<Later<i32>> (declared below) 16, h<Pt> forwarding g<Box<T>> 32, Box<Box<Pt>> 32 B, unchanged"

# ── 6.7.14: a signature's generic struct reads its type arguments at the definition (the user's D6 (a)) ─────
TA="as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)"
cat > "$T/sg0.cyr" <<'EOF'
struct Mp<K, V> { k: K; v: V; }
fn gm(m: Mp<K, V>, b) { return b; }
syscall(60, 0);
EOF
errs sg0 1 "SG0: the filed repro verbatim — refused once, naming 'K' (it compiled, rc 0)" "error:<source>:2:14: unknown type 'K' $TA"
SGH='include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct Mp<K, V> { k: K; v: V; }'
sg() { printf '%s\n%s\nsyscall(60, 0);\n' "$SGH" "$2" > "$T/$1.cyr"; }
sg sg1 'fn gm(m: Mp<Nonexist, i64>, b) { return b; }'
errs sg1 1 "SG1: a parameter's Mp<Nonexist, i64>" "error:<source>:5:21: unknown type 'Nonexist' $TA"
sg sg2 'fn gm(m: *Mp<K, V>, b) { return b; }'
errs sg2 1 "SG2: a parameter's *Mp<K, V>" "error:<source>:5:15: unknown type 'K' $TA"
sg sg3 'fn gm(b): Mp<K, V> { var m: Mp<i64, i64>; return m; }'
errs sg3 1 "SG3: a return's : Mp<K, V>" "error:<source>:5:15: unknown type 'K' $TA"
sg sg4 'fn gm(m: Box<Zork>): i64 { return m.n; }
fn f(): i64 { var b: Box<i64>; b.n = 3; return gm(b); }'
errs sg4 1 "SG4: m: Box<Zork>, called with a Box<i64> (it took it)" "error:<source>:5:18: unknown type 'Zork' $TA"
sg sg5 'fn ga(m: Box<Box<Zork>>): i64 { return 0; }
fn gb(m: Mp<Box<Zork>, i64>): i64 { return 0; }
impl Pt { fn mm(self, m: Box<Zork>): i64 { return 0; } }'
errs sg5 3 "SG5: nested Box<Box<Zork>>, Mp<Box<Zork>, i64>, a method's Box<Zork> — once each" \
    "error:<source>:5:22: unknown type 'Zork' $TA" "error:<source>:6:21: unknown type 'Zork' $TA" "error:<source>:7:34: unknown type 'Zork' $TA"
sg sg6 'fn gm<T>(m: *Box<T>, n: *Mp<T, Zork>): i64 { return sizeof(T); }
fn f(): i64 { return gm<Pt>(0, 0) + gm<i32>(0, 0) + gm(0, 0); }'
errs sg6 1 "SG6: a generic's own signature, Zork not its type parameter, three instances — once" "error:<source>:5:36: unknown type 'Zork' $TA"
sg sg7 'fn f(): i64 { return gm(0); }
fn gm(m: *Box<Zork>): i64 { return 0; }'
errs sg7 1 "SG7: a fn called above its definition (pass 1 read the signature first)" "error:<source>:6:19: unknown type 'Zork' $TA"
cat > "$T/sgk.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct Mp<K, V> { k: K; v: V; }
fn gm<K, V>(m: Mp<K, V>, b): i64 { return m.v + b + sizeof(K); }
fn gk(m: Box<Later>): i64 { return m.v.a + m.n; }
fn gr(a): Box<Later> { var r: Box<Later>; r.v.a = a; r.n = 1; return r; }
fn gp(m: *Box<Later>): i64 { return m.n; }
fn main(): i64 {
    var m: Mp<Pt, i64>;
    m.v = 3;
    var b: Box<Later>;
    b.v.a = 5; b.n = 7;
    var r = gr(9);
    return gm(m, 2) + gk(b) + gp(&b) + r.v.a;
}
struct Later { a; }
syscall(60, main());
EOF
exits sgk 49 "SG control: a generic's own fn gm<K, V>(m: Mp<K, V>, b) (21), Box<Later> / *Box<Later> parameters and a : Box<Later> return with Later declared below the fns (12 + 7 + 9)"

# ── 6.7.15: `Name<..>` on a non-generic struct or a scalar (the user's D6 (a), 2026-10-18) ──────────
NGS="'Pt' is not a generic struct: it takes no type arguments"
NGI="takes no type arguments"
cat > "$T/ng0.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn g<T>(x): i64 { return sizeof(T); }
fn main(): i64 {
    var c: Pt<i64>;
    c.x = 3;
    var b: Box<Pt<nosuch>>;
    b.n = 4;
    return c.x + b.n + g<Pt<i32>>(0) + g<i64<u8>>(0);
}
syscall(60, main());
EOF
errs ng0 4 "NG0: the filed repro verbatim — each shape refused once, at the name (it compiled: exit 31)" \
    "error:<source>:6:12: $NGS" "error:<source>:8:16: $NGS" "error:<source>:10:26: $NGS" "error:<source>:10:42: 'i64' $NGI"
NGH='include "lib/syscalls.cyr"
include "lib/vec.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn g<T>(x): i64 { return sizeof(T); }'
ng() { printf '%s\n%s\nsyscall(60, 7);\n' "$NGH" "$2" > "$T/$1.cyr"; }
ng ng1 'fn f(): i64 { var w: Vec<Pt<nosuch>> = 0; return 0; }
struct H { items: Vec<Pt<i64>>; k; }'
errs ng1 2 "NG1: a Vec element, a local's and a field's (Vec<Pt<nosuch>>, Vec<Pt<i64>>)" \
    "error:<source>:6:26: $NGS" "error:<source>:7:23: $NGS"
ng ng2 'fn f(p: Pt<i64>): i64 { return 7; }
fn h(): Pt<i64> { var p: Pt; return p; }
fn k(p: *Pt<i64>, q: i32<u8>): *Pt<i64> { return p; }'
errs ng2 5 "NG2: a parameter, a return, a pointer parameter, a scalar parameter, a pointer return — at the definition, called or not" \
    "error:<source>:6:9: $NGS" "error:<source>:7:9: $NGS" "error:<source>:8:10: $NGS" "error:<source>:8:22: 'i32' $NGI" "error:<source>:8:33: $NGS"
ng ng3 'fn f(): i64 { var x: i64<u8> = 5; var y: f64<i32> = 1.5; var p: *Pt<i64> = 0; var q: Pt<i64> = Pt { 1, 2 }; return x; }'
errs ng3 4 "NG3: local annotations — a scalar, f64, a pointer, a struct with its initialiser" \
    "error:<source>:6:22: 'i64' $NGI" "error:<source>:6:42: 'f64' $NGI" "error:<source>:6:66: $NGS" "error:<source>:6:86: $NGS"
ng ng4 'fn f(): i64 { var p = Pt<i64> { 1, 2 }; var b: Box<i32<u8>>; return sizeof(Pt<i64>) + g<f64<u8>>(0) + p.y; }'
errs ng4 4 "NG4: a struct literal head, a scalar inside Box<..>, sizeof(..), an explicit f64<u8>" \
    "error:<source>:6:23: $NGS" "error:<source>:6:52: 'i32' $NGI" "error:<source>:6:76: $NGS" "error:<source>:6:89: 'f64' $NGI"
ng ng5 'var G: Pt<i64> = Pt { 1, 2 };
var X: i64<u8> = 3;'
errs ng5 2 "NG5: globals — a struct with its initialiser, a scalar" "error:<source>:6:8: $NGS" "error:<source>:7:8: 'i64' $NGI"
ng ng6 'fn h<T>(x: T): i64 { var c: Pt<T>; c.x = 1; return c.x + sizeof(T); }
fn f(): i64 { var b: Box<Pt>; return h(1) + h(b) + h<i32>(2); }'
errs ng6 1 "NG6: a generic body's Pt<T> with three instances — once" "error:<source>:6:29: $NGS"
ng ng7 'fn f(): i64 { var r: Box<Result<i64>>; return 0; }'
errs ng7 1 "NG7: Box<Result<..>> keeps its own refusal, alone" "generic type-args must be a scalar (i8/i16/i32/i64) or a struct"
# NG8: in source order — a fn's `*Pt<..>` return is refused where pass 2 reads the definition, not by pass 1's scan
# (which ran ahead of every earlier fn's errors).
ng ng8 'fn a(): i64 { var q: i64 = 1 2; return q; }
fn k(): *Pt<i64> { return 0; }
fn m(p: i64): *Pt<i64> { return 0; }'
errs ng8 3 "NG8: a pointer return's refusal in source order" "error:<source>:7:10: $NGS" "error:<source>:8:16: $NGS"
if [ "$(grep '^error' "$T/ng8.err" | head -1 | cut -d: -f2-3)" != "<source>:6" ]; then
    bad "NG8: the first error is not line 6's (pass 1 reported ahead): $(grep '^error' "$T/ng8.err" | head -1)"
else ok "NG8: line 6's error first (pass 2 reports the pointer returns)"; fi
printf '%s\nfn main(): i64 { var b: Box<Pt>; b.n = 1; var c: Box<Box<Pt>>; c.n = 2; var w: Vec<i64> = 0; var v: Vec<Box<Pt>> = 0; var u: Vec<Vec<i64>> = 0; var p: Pt; p.y = 3; return b.n + c.n + p.y + g<Pt>(0) + g<Box<Pt>>(0) + g<Vec<i64>>(0) - 54; }\nsyscall(60, main());\n' "$NGH" > "$T/ngk.cyr"
exits ngk 0 "NG control: Box<Pt>, Box<Box<Pt>>, Vec<i64>, Vec<Box<Pt>>, Vec<Vec<i64>>, g<Pt> 16, g<Box<Pt>> 24, g<Vec<i64>> 8, unchanged"

# ── 6.7.15: a multi-value element, a trait member's signature and a `*fn(..)` parameter (the user's D7 (a)) ───────
cat > "$T/sr0.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Box<T> { v: T; n; }
fn mv(): (Box<Zork>, i64) { return (0, 1); }
trait Sh { fn a(self, b: Box<nosuch>): i64; }
fn ap(cb: *fn(Box<Zork>): i64): i64 { return 0; }
fn main(): i64 { var a, c = mv(); return c + ap(0); }
syscall(60, main());
EOF
errs sr0 3 "SR0: the filed repro verbatim — each position refused once, at its argument (it compiled: exit 1)" \
    "error:<source>:3:19: unknown type 'Zork' $TA" "error:<source>:4:36: unknown type 'nosuch' $TA" "error:<source>:5:23: unknown type 'Zork' $TA"
SRH='include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct P { k; }'
sr() { printf '%s\n%s\nsyscall(60, 7);\n' "$SRH" "$2" > "$T/$1.cyr"; }
sr sr1 'fn mv<T>(x: T): (Box<Zork>, T) { return (0, x); }
fn f(): i64 { var a, c = mv(1); var d, e = mv<i32>(2); return c + e; }'
errs sr1 1 "SR1: a multi-value element in a generic with two instances — once" "error:<source>:5:26: unknown type 'Zork' $TA"
sr sr2 'trait Sh { fn a(self, q: *Box<Box<Zork>>): i64; fn b(self): (Box<Zork2>, i64); }'
errs sr2 2 "SR2: a member's *Box<Box<Zork>> parameter and (Box<Zork2>, i64) return" \
    "error:<source>:5:39: unknown type 'Zork' $TA" "error:<source>:5:71: unknown type 'Zork2' $TA"
sr sr2b 'trait Sh { fn a(self, b: Box<nosuch>, c: Nope): i64; }'
errs sr2b 1 "SR2b: a member's walk ends at its first refusal (one report per member)" "error:<source>:5:36: unknown type 'nosuch' $TA"
sr sr3 'fn gp<U>(cb: *fn(Box<Zork>, U): i64, u: U): i64 { return 2; }
fn f(): i64 { var p: Pt; return gp(0, 1) + gp<i32>(0, 2) + gp(0, p); }'
errs sr3 1 "SR3: *fn(Box<Zork>, U) in a generic with three instances — once" "error:<source>:5:26: unknown type 'Zork' $TA"
sr sr4 'fn ap(p: **Box<Zork>): i64 { return 0; }
fn aq(cb: *fn(i64): Box<Zork2>): i64 { return 0; }'
errs sr4 2 "SR4: **Box<Zork> (refused before) and a *fn(..)'s Box<Zork2> return — once each" \
    "error:<source>:5:20: unknown type 'Zork' $TA" "error:<source>:6:30: unknown type 'Zork2' $TA"
cat > "$T/srk.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct P { k; }
fn mv(): (Box<Pt>, i64) { return (0, 1); }
fn ml(): (Box<Later>, i64) { return (0, 2); }
trait Sh { fn a(self, b: Box<i64>): i64; fn g<U>(self, b: Box<U>): U; fn g2<U>(self, c: *fn(Box<U>): i64): i64; fn h(self, l: *Box<Later>): (Box<Later>, i64); }
impl Sh for P { fn a(self, b: Box<i64>): i64 { return 3; } fn g<U>(self, b: Box<U>): U { return 0; } fn g2<U>(self, c: *fn(Box<U>): i64): i64 { return 0; } fn h(self, l: *Box<Later>): (Box<Later>, i64) { return (0, 4); } }
fn ap(cb: *fn(Box<Pt>): i64, cl: *fn(Box<Later>): i64): i64 { return 5; }
fn gp<U>(cb: *fn(Box<U>): i64, u: U): i64 { return 6; }
fn main(): i64 {
    var a, c = mv();
    var d, e = ml();
    var p = P { 1 };
    var b: Box<i64>;
    var f, g = p.h(0);
    return c + e + p.a(b) + g + ap(0, 0) + gp(0, 1) + gp<i32>(0, 2) - 27;
}
struct Later { z; }
syscall(60, main());
EOF
exits srk 0 "SR control: (Box<Pt>, i64), a member's Box<i64> / own Box<U> / *fn(Box<U>), *fn(Box<Pt>), a generic's own *fn(Box<U>), Box<Later> (declared below) in each position, unchanged"

if [ "$fails" -ne 0 ]; then echo "FAIL: generic_type_arg_unknown_refused — $fails axis(es) red"; exit 1; fi
echo "PASS: generic_type_arg_unknown_refused — a type-arg naming no type is refused by name (A-B); a forwarded type parameter resolves to its binding (C-D); scalar and struct type-args unchanged (E); an enum or an unlisted scalar name is refused by name (F-G); a generic using T as a struct is refused at every scalar call, tail call, forwarding generic and &g (H-J, L), a struct beside a second type argument runs on every path and a mismatched receive is refused once (K, 6.7.1), a \`*Pt\` parameter binds i64 (O), a top-level pair instance argument is refused (P), a global typed with a generic instance is the instance and a top-level pair initialiser is refused in either zone (Q), scalar tail recursion and the struct calls still run (M), a bad type argument in a receive is reported once (N), and a struct carrier's T field read as a struct makes the base the stub (CF, 6.7.11), past 64 carriers and T-typed names too (CF7-CF8, 6.7.14), and a forwarder passing its T inside a carrier into a stub is a stub (FC, 6.7.14); a type argument that is no name is refused once at its token, by what it is, with no cascade (NN, 6.7.14); \`Name<..>\` whose Name is no type, or a type parameter, is refused once by name (UG, 6.7.14); a signature's generic struct reads its type arguments at the definition (SG, 6.7.14); \`Name<..>\` on a non-generic struct or a scalar is refused once at the name (NG, 6.7.15); a multi-value element, a trait member's signature and a \`*fn(..)\` parameter read theirs too (SR, 6.7.15)"
