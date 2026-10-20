#!/bin/sh
# type_name_refused.sh — 6.6.16 (C8): every type name is resolved by ONE resolver, by its WHOLE
# name, and a name that is no type is refused BY NAME — once, with no cascade, and no binary.
# tests/tcyr/frontend/type_name_resolver.tcyr runs the sizes; this pins what is refused and what
# must keep compiling.
#
# WHY. sizeof, `#assert sizeof` and each annotation site had a ladder of its own (src/frontend/
# parse_types.cyr `_tn_resolve` replaces them). Most matched a name's PREFIX (`var a: i8x = 300`
# was an i8 and read 44, `var a: f64zz` an f64, `fn f(a: i16q)` compiled) and almost all read an
# unknown name as a silent i64: `var a: Nonexist`, `var p: *Nonexist`, `var s: [Nonexist]`,
# `fn f(a: Nonexist)`, `fn f(): (i64, Nonexist)` all compiled rc 0 with no diagnostic. A return
# type's refusal did not name the type, and `#assert sizeof(Nope)` reported a second error
# (`#assert failed`). Before this, the same refusal in a generic fn's body was printed once per
# instance (the body is re-parsed): each name is now reported once.
#
#   axis 1  a refusal per site, for an unknown name AND a prefix misspelling: exit 1, the message
#           names the type, EXACTLY one error line, no binary. Sites: local, global (declaration
#           block and after the first statement), local and global `*T`, `[T]`, `slice<T>`,
#           `[*T]`, param, return, multi-value return element, sizeof, `#assert sizeof`, struct
#           field, array element; plus `type 'u8' cannot be a fn return type` (a known type the
#           return set does not take; 6.7.11: its note names the whole set — bool, `*T`, a
#           multi-value, `dyn Trait`, a type parameter), a struct declared after a
#           declaration-block global, the generic-body dedupe, four bad names in one fn reported
#           four times, and two or three in ONE statement (a signature, an expression) each
#           reported too.
#   axis 2  ANTI-VACUOUS: every name of the vocabulary compiles at every site that takes it, a
#           `Str` param in a unit without lib/str.cyr (the by-name handle), enums declared on
#           either side, a fn's type parameters (first, second and THIRD, in the default build and
#           CYRIUS_MONOMORPH=0), a struct declared below its use, the prefix-named struct, and
#           `Vec` / `Vec<T>` (the struct-field vocabulary's handle) at every annotation site.
#   axis 3  `--syntax-only` (what `cyrius lint` runs) resolves nothing: every axis-1 shape exits 0
#           with no `unknown type` line — a refused return type's `<..>` included.
#   axis 4  a local `*i8` / `*i16` / `*i32` (an 8-byte slot since 6.6.16) is still a POINTER to the
#           declaration's `assigning non-pointer to typed pointer` check: copied, stepped, or
#           copied across widths into a typed pointer it draws no warning; an integer still does.
#   axis 5  (6.6.17, a3) a vector global owns its 16/32 B and is used through `&g`: each value-form
#           read / write / non-zero initializer is refused naming it (8 rows, all compiling silently
#           before); `&g`, a folded 0 and the routed `*_ptr` form run (anti-vacuous).
#   axis 6  (6.7.14, the user's decision D10 (a), 2026-10-16) a `u128` parameter (a fn, a trait member, a
#           default after it, a generic's and an #inline fn's, once), return type and struct / union field
#           type are each one error by name; the filed repro verbatim gives its two parameter refusals.
#           Anti-vacuous: `*u128`, a `*fn(u128)`'s own list and a u128 local still compile and run; --syntax-only
#           refuses the three shapes too. The capture half runs in tests/tcyr/crossos/u128_closure_capture.tcyr.
#           6.7.15 (the user's D3 (a), 2026-10-18): a trait member's `: u128` return is refused as a fn's is, once, at
#           the member (u128_trait_ret1 alone; u128_trait_ret, the pinned row, with an impl spelled `: i64` — it ran,
#           exit 4; u128_trait_ret2 a default every impl overrides, two impls, the trait below them) and under
#           --syntax-only; `: *u128` and a `*fn( .. ): u128` type's own return still compile (u128_trait_ptr).
#           Mutant (2026-10-18, a scratch copy of src/, CYCC= it): `_trs_ret_refused` without its u128 arm -> RED
#           u128_trait_ret1 / u128_trait_ret / u128_trait_ret2 (each built) and its --syntax-only row; the lane's
#           previous compiler (64c2fc8e) the same.
#           6.7.16: a trait member's `cb: *fn(i64): u128` is a fn pointer's own return, read on as a fn's parameter
#           reads it (u128_trait_fnret, the filed repro verbatim, exit 3): it was refused as a `u128` parameter (3:36).
#           The parameter's own `u128` after it stays refused, at its own token (u128_trait_fnret_own, 2:45; it was
#           reported at the fn pointer's 2:36). (issues/2026-10-18-trait-member-fn-pointer-parameter-u128-return-refused.md)
#           Mutant (2026-10-20): the lane's previous compiler (be7156d69, the return read at the parameter's level)
#           -> RED 2: u128_trait_fnret (refused), u128_trait_fnret_own (at 2:36).
#
# MUTATION LEDGER (6.6.16, built from scratch copies of src/, measured):
#   the slot-open compiler                    -> axis 1 RED on 35 of its 38 rows (all but the
#                                                two struct-field rows and the array-element row,
#                                                which 6.6.10 / 6.6.13 already refused by name);
#                                                axis 2 RED on v_local (`var l: u8pair;`), v_sizeof,
#                                                v_field (bool), both type-parameter rows (sizeof of
#                                                an unbound T) and u8pair_ptr (read 1, not 7);
#                                                axis 3 RED on the three sizeof / #assert rows
#   _tn_refuse without its `_panic = 0`       -> one_signature and one_expression RED (1 error:
#                                                the resync swallowed the rest of the statement)
#   _tn_once always reporting                 -> gen_dedupe RED (the body's names reported again)
#   _tn_sizeof's `#assert` arm not latching   -> as_unknown / as_prefix RED (`#assert failed` too)
#   _tn_param_check ignoring `ptc`            -> str_param RED (`s: Str` without lib/str.cyr)
#   _tn_ann refusing before an array's `[`    -> arr_unknown RED (2 errors for one name)
# and on the srcb-1 review build (02121475, the first cut of this bite), measured:
#   no `Vec` in _tn_scalar                    -> v_local / v_global / v_late / v_ptr / v_slice /
#                                                v_param / v_sizeof / v_mret / vec_forms RED
#                                                (`unknown type 'Vec' ...`), loc_vec_hint RED
#   _tn_ret_refuse not skipping the `<..>`    -> ret_vec_targs RED (3 errors: `expected '{', got
#                                                '<'` and `undefined variable 'i64'` after it),
#                                                and its --syntax-only row RED (rc 1)
#   _sl_load_marks without its SPSC(S, 1)     -> ptr_copy_nowarn RED (4 warnings: every copy and
#                                                step of an 8-byte *iN slot read as a non-pointer)
# and at 6.7.11 (the note, issues/archived/2026-10-12-return-type-refusal-note-incomplete.md), measured:
#   _tn_ret_report's 6.6.17 note string       -> RED the four ret_known note rows naming bool, a
#                                                multi-value, dyn Trait and a type parameter (`*T` green)
# and at 6.7.14 (axis 6, issues/archived/2026-10-08-u128-params-returns-fields-captures.md), measured:
#   the lane's previous compiler (45c06049)   -> RED every u128 refusal row (a parameter compiled; a return /
#                                                field said "expected identifier, got reserved keyword"); the
#                                                four runs rows green
#   `_pty_u128` takes the parameter           -> RED u128_repro / _param / _param_df / _generic / _inline /
#                                                _tr_dflt (an inherited default is the impl's definition)
#   `_trs_u128` takes it                      -> RED u128_trait
#   `_ret_ann_alt` without its u128 arm       -> RED u128_ret (the reserved-keyword text)
#   `_sfield_alt` without its u128 line       -> RED u128_field / u128_ufield
#   `_u128_refuse` without `_tn_once`         -> RED u128_generic, u128_tr_dflt (once per instance / impl)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: type_name_refused: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: type_name_refused: $CC not built"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: type_name_refused: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
rows=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 - expected $2, got $3"; fails=$((fails + 1)); fi
}
# refused <name> <source> <fragment> [<errors, default 1>] [<env assignment>]
refused() {
    rows=$((rows + 1))
    printf '%b' "$2" > "$T/$1.cyr"
    want=1
    if [ $# -ge 4 ]; then want=$4; fi
    rc=0
    if [ $# -ge 5 ]; then env "$5" "$CC" < "$T/$1.cyr" > "$T/$1.out" 2> "$T/$1.err" || rc=$?
    else "$CC" < "$T/$1.cyr" > "$T/$1.out" 2> "$T/$1.err" || rc=$?; fi
    check "$1: exits 1" 1 "$rc"
    check "$1: names it" yes "$(grep -qF -- "$3" "$T/$1.err" && echo yes || echo no)"
    check "$1: error lines" "$want" "$(grep -c '^error' "$T/$1.err")"
    check "$1: emits no binary" 0 "$(wc -c < "$T/$1.out" | tr -d ' ')"
}
# runs <name> <source> <exit> [<env assignment>]
runs() {
    rows=$((rows + 1))
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    if [ $# -ge 4 ]; then env "$4" "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    else "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?; fi
    check "$1: compiles" 0 "$rc"
    if [ "$rc" -ne 0 ]; then echo "       $(grep '^error' "$T/$1.err" | head -2)"; return 0; fi
    chmod +x "$T/$1.bin" 2>/dev/null
    rc=0; "$T/$1.bin" > /dev/null 2>&1 || rc=$?
    check "$1: exits $3" "$3" "$rc"
}

echo "axis 1 - a name that is no type is refused by name, once, at every site:"
FN='fn f(): i64 {\n'
refused loc_unknown   "${FN}    var a: Nonexist = 3;\n    return a;\n}\nsyscall(60, f());\n" "unknown type 'Nonexist' for variable 'a'"
refused loc_prefix    "${FN}    var a: i8x = 300;\n    return a;\n}\nsyscall(60, f());\n" "unknown type 'i8x' for variable 'a'"
refused loc_hint      "${FN}    var a: i8x = 300;\n    return a;\n}\nsyscall(60, f());\n" "note: 'i8x' is not 'i8' - a type name must match whole"
refused dz_unknown    'var a: Nonexist = 3;\nsyscall(60, a);\n' "unknown type 'Nonexist' for variable 'a'"
refused dz_prefix     'var a: u8garbage = 300;\nsyscall(60, a);\n' "unknown type 'u8garbage' for variable 'a'"
refused pp_unknown    'syscall(39);\nvar a: Nonexist = 3;\nsyscall(60, a);\n' "unknown type 'Nonexist' for variable 'a'"
refused pp_prefix     'syscall(39);\nvar a: f64zz = 3;\nsyscall(60, a);\n' "unknown type 'f64zz' for variable 'a'"
refused lptr_unknown  "${FN}    var x = 1;\n    var p: *Nonexist = &x;\n    return 0;\n}\nsyscall(60, f());\n" "unknown type 'Nonexist' as the target of pointer 'p'"
refused lptr_prefix   "${FN}    var x = 1;\n    var p: *i16q = &x;\n    return 0;\n}\nsyscall(60, f());\n" "unknown type 'i16q' as the target of pointer 'p'"
refused gptr_unknown  'var p: *Nonexist = 0;\nsyscall(60, 0);\n' "unknown type 'Nonexist' as the target of pointer 'p'"
refused gptr_prefix   'var p: *u32zz = 0;\nsyscall(60, 0);\n' "unknown type 'u32zz' as the target of pointer 'p'"
refused slice_unknown "${FN}    var s: [Nonexist] = 0;\n    return 0;\n}\nsyscall(60, f());\n" "unknown type 'Nonexist' as the element of slice 's'"
refused slice_prefix  "${FN}    var s: [i8x] = 0;\n    return 0;\n}\nsyscall(60, f());\n" "unknown type 'i8x' as the element of slice 's'"
refused sliceg_unknown "${FN}    var s: slice<Nonexist> = 0;\n    return 0;\n}\nsyscall(60, f());\n" "unknown type 'Nonexist' as the element of slice 's'"
refused sliceg_prefix "${FN}    var s: slice<u16x> = 0;\n    return 0;\n}\nsyscall(60, f());\n" "unknown type 'u16x' as the element of slice 's'"
refused sliceptr      "${FN}    var s: [*Nonexist] = 0;\n    return 0;\n}\nsyscall(60, f());\n" "unknown type 'Nonexist' as the target of pointer 's'"
refused param_unknown 'fn f(a: Nonexist): i64 { return a; }\nsyscall(60, f(3));\n' "unknown type 'Nonexist' for parameter 'a'"
refused param_prefix  'fn f(a: i16q): i64 { return a; }\nsyscall(60, f(3));\n' "unknown type 'i16q' for parameter 'a'"
refused ret_unknown   'fn f(): Nonexist { return 3; }\nsyscall(60, f());\n' "unknown type 'Nonexist' as a fn return type"
refused ret_prefix    'fn f(): i8x { return 3; }\nsyscall(60, f());\n' "unknown type 'i8x' as a fn return type"
refused ret_known     'fn f(): u8 { return 3; }\nsyscall(60, f());\n' "type 'u8' cannot be a fn return type"
# 6.7.11: its note lists the whole accepted set. `bool` (6.7.3), a multi-value (6.5.21), `dyn Tr` (6.7.8) and a generic
# fn's type parameter were accepted but not named (issues/archived/2026-10-12-return-type-refusal-note-incomplete.md).
for frag in "f64, bool, a vector type" "a pointer *T" "a multi-value (T1, T2[, T3])" "dyn Trait" "a generic fn's first or second type parameter"; do
    rows=$((rows + 1))
    check "ret_known: the note names '$frag'" yes "$(grep '^  note: a return type is ' "$T/ret_known.err" | grep -qF -- "$frag" && echo yes || echo no)"
done
refused ret_enum      'enum Color { RED = 0; }\nfn f(): Color { return 0; }\nsyscall(60, f());\n' "type 'Color' cannot be a fn return type"
refused ret_tparam_m0 'fn g<T>(a: T): T { return a; }\nsyscall(60, g(3));\n' "type parameter 'T' cannot be this fn's return type" 1 CYRIUS_MONOMORPH=0
refused mret_unknown  'fn f(): (i64, Nonexist) { return (1, 2); }\nvar a, b = f();\nsyscall(60, a + b);\n' "unknown type 'Nonexist' in a multi-value return type"
refused mret_prefix   'fn f(): (i64, u8x) { return (1, 2); }\nvar a, b = f();\nsyscall(60, a + b);\n' "unknown type 'u8x' in a multi-value return type"
refused sz_unknown    'syscall(60, sizeof(Nonexist));\n' "unknown type 'Nonexist' in sizeof"
refused sz_prefix     'syscall(60, sizeof(i8x));\n' "unknown type 'i8x' in sizeof"
refused sz_ptr        "${FN}    return sizeof(ptr);\n}\nsyscall(60, f());\n" "unknown type 'ptr' in sizeof"
refused as_unknown    '#assert sizeof(Nope) == 8;\nsyscall(60, 0);\n' "unknown type 'Nope' in #assert sizeof"
refused as_prefix     '#assert sizeof(i8zz) == 1, "x";\nsyscall(60, 0);\n' "unknown type 'i8zz' in #assert sizeof"
refused field_unknown 'struct S { a: Nonexist; }\nsyscall(60, 0);\n' "unknown type 'Nonexist' for struct field 'a'"
refused field_prefix  'struct S { a: i8x; }\nsyscall(60, 0);\n' "unknown type 'i8x' for struct field 'a'"
refused arr_unknown   "${FN}    var a: Nonexist[3];\n    return 0;\n}\nsyscall(60, f());\n" "unknown array element type 'Nonexist'"
refused dz_late_struct 'var g: Late = 0;\nstruct Late { a; b; }\nsyscall(60, 0);\n' "type 'Late' is declared after its use"
refused loc_vec_hint  "${FN}    var a: Vecx = 0;\n    return a;\n}\nsyscall(60, f());\n" "note: 'Vecx' is not 'Vec' - a type name must match whole"
# 6.7.14 (the user's decision D15 (a), 2026-10-16): a `var` annotation that is no type at all — a number, an operator,
# a string — is refused by name at its token, once, in a fn, in the declaration zone and after the first statement,
# as a parameter's is (6.7.11); the declaration reads on, so nothing cascades. It compiled as a plain i64, the
# token dropped (issues/archived/2026-10-14-var-annotation-non-type-token-compiles.md). Mutations (scratch trees):
# `_tn_head_var` not reporting -> every va_ row but va_missing / va_ok RED (they compile), the syntax-only row too.
VA="expected a type for variable"
refused va_loc_num  "${FN}    var b: 1 = 0;\n    return b;\n}\nsyscall(60, f());\n" "$VA 'b', got number 1"
refused va_loc_op   "${FN}    var c: + = 2;\n    return c;\n}\nsyscall(60, f());\n" "$VA 'c', got '+'"
refused va_loc_str  "${FN}    var d: \"s\" = 3;\n    return d;\n}\nsyscall(60, f());\n" "$VA 'd', got string"
refused va_dz_num   'var G: 7 = 4;\nsyscall(60, G);\n' "$VA 'G', got number 7"
refused va_dz_op    'var G: % = 4;\nsyscall(60, G);\n' "$VA 'G', got '%'"
refused va_dz_str   'var G: "s" = 4;\nsyscall(60, G);\n' "$VA 'G', got string"
refused va_pp_num   'syscall(39);\nvar H: 7 = 4;\nsyscall(60, H);\n' "$VA 'H', got number 7"
refused va_pp_op    'syscall(39);\nvar H: + = 4;\nsyscall(60, H);\n' "$VA 'H', got '+'"
refused va_pp_str   'syscall(39);\nvar H: "s" = 4;\nsyscall(60, H);\n' "$VA 'H', got string"
refused va_comma    "${FN}    var b: , = 0;\n    return b;\n}\nsyscall(60, f());\n" "$VA 'b', got ','"
refused va_for      "${FN}    for (var i: 3 = 0; i < 2; i = i + 1) { }\n    return 0;\n}\nsyscall(60, f());\n" "$VA 'i', got number 3"
refused va_gen      'fn g<T>(a: T): i64 { var b: 1 = 0; return b + a; }\nsyscall(60, g(1) + g(2));\n' "$VA 'b', got number 1"
# 6.7.15: a `:` with NO type — a `=` or `;` right after it — is refused the same way, once, AT that token, in a fn, in
# the declaration zone and after the first statement; the declaration reads its initializer from the `=`, and a `;` is
# not also "uninitialized variable not allowed". It was "expected '=', got number 0" at the initializer (the `=` stepped
# as the type), and `var c: ; var d = 2;` in the zone compiled, c = 2 (va_miss_next)
# (issues/archived/2026-10-16-var-missing-annotation-reported-as-expected-equals.md). Mutations (measured; scratch trees): the
# 6.7.15 slot-open compiler (`_tn_head_var` not reporting a `=` / `;`) -> every va_miss / va_missing row RED (the old
# "expected '='" at the wrong token; va_miss_next compiles); `_tn_head_var` without its step back -> RED the fn and
# after-the-first-statement rows and the --syntax-only row (2-3 errors: "expected '='" too) — the zone rows are the
# replay's; `_decl_eq_err` without its stand-down -> RED va_miss_lsemi / _ppsemi / _dzsemi / _next ("uninitialized
# variable" too); `_gvi_ann` stepping the `=` / `;` -> RED va_miss_dzcall / _dzsemi / _next (a replayed entry reads its
# initializer where its `=` belongs; a constant one, va_miss_dzeq, is baked, not replayed).
refused va_missing  "${FN}    var b: = 0;\n    return b;\n}\nsyscall(60, f());\n" "2:12: $VA 'b', got '='"
refused va_miss_lsemi  "${FN}    var b: ;\n    return 3;\n}\nsyscall(60, f());\n" "2:12: $VA 'b', got ';'"
refused va_miss_dzeq   'var G: = 4;\nsyscall(60, G);\n' "1:8: $VA 'G', got '='"
refused va_miss_dzcall 'fn k(): i64 { return 4; }\nvar G: = k();\nsyscall(60, G);\n' "2:8: $VA 'G', got '='"
refused va_miss_dzsemi 'var G: ;\nsyscall(60, 0);\n' "1:8: $VA 'G', got ';'"
refused va_miss_ppeq   'syscall(39);\nvar H: = 4;\nsyscall(60, H);\n' "2:8: $VA 'H', got '='"
refused va_miss_ppsemi 'syscall(39);\nvar H: ;\nsyscall(60, 0);\n' "2:8: $VA 'H', got ';'"
refused va_miss_next   'var c: ;\nvar d = 2;\nsyscall(60, c);\n' "1:8: $VA 'c', got ';'"
refused va_miss_gen    'fn g<T>(a: T): i64 { var b: = 0; return b + a; }\nsyscall(60, g(1) + g(2));\n' "1:29: $VA 'b', got '='"
refused va_miss_for    "${FN}    for (var i: = 0; i < 2; i = i + 1) { }\n    return 0;\n}\nsyscall(60, f());\n" "2:17: $VA 'i', got '='"
# The filed repro verbatim: two declarations, two errors (the global first: pass 1 registers it).
refused va_miss_repro 'fn f(): i64 {\n    var b: = 0;\n    return b;\n}\nvar G: = 4;\nsyscall(60, f() + G);\n' "5:8: $VA 'G', got '='" 2
rows=$((rows + 1))
check "va_miss_repro: names 2:12 'b'" yes "$(grep -qF -- "2:12: $VA 'b', got '='" "$T/va_miss_repro.err" && echo yes || echo no)"
# 6.7.16: a bare `var c;` / `var c: ;` in a fn or after the first statement ENDS AT ITS `;` and registers `c` — the
# declaration stepped the `;` and read the next statement as its initializer, so `var d = 9;` was dropped ("undefined
# variable 'd'") and `c = 4;` said "undefined variable 'c'" (issues/2026-10-18-bare-declaration-refusal-reads-next-
# statement-as-initializer.md). The _next rows: the statement after it is no keyword statement, so it is parsed only
# because the refusal is in sync (the resync would skip it, its error with it). MUTATION LEDGER (measured
# (scratch trees, CYCC= the copy's compiler): the slot-open compiler and `_var_eq_step` stepping the `;` (6.7.15's
# behaviour) -> RED bare_repro / _late / _ann / _gen / _ptr (two errors), _reg (three), the three _next rows ("undefined
# variable 'c'", not 'zz'), bare_ptr's warning; `_decl_eq_err` not marking in sync (either arm) -> RED the three _next
# rows (one error: the resync skipped `c = zz;`) — its `uninitialized` arm alone bare_next / _late_next, its
# annotation arm alone bare_ann_next; `_var_value` without its `_tp_refd_at` -> RED bare_ptr (a warning at the `;`);
# `_var_value` running PCMPE on the `;` -> RED bare_ptr only (the factor leaves a latched `;` where it is; the branch
# is the warning's stand-down and a defined 0). The zone's `var c;` (EMIT_GVAR_INITS) was one error already: bare_zone.
UV="uninitialized variable not allowed"
refused bare_repro    'fn f(): i64 {\n    var c;\n    var d = 9;\n    return d;\n}\nsyscall(60, f());\n' "2:10: $UV"
refused bare_late     'syscall(39);\nvar c;\nvar d = 9;\nsyscall(60, d);\n' "2:6: $UV"
refused bare_ann      'fn f(): i64 {\n    var c: ;\n    var d = 9;\n    return d;\n}\nsyscall(60, f());\n' "2:12: $VA 'c', got ';'"
refused bare_reg      'fn f(): i64 {\n    var c;\n    c = 4;\n    return zz;\n}\nsyscall(60, f());\n' "4:14: undefined variable 'zz'" 2
rows=$((rows + 1))
check "bare_reg: names 2:10" yes "$(grep -qF -- "2:10: $UV" "$T/bare_reg.err" && echo yes || echo no)"
refused bare_next     'fn f(): i64 {\n    var c;\n    c = zz;\n    return c;\n}\nsyscall(60, f());\n' "3:11: undefined variable 'zz'" 2
refused bare_late_next 'syscall(39);\nvar c;\nc = zz;\nsyscall(60, c);\n' "3:7: undefined variable 'zz'" 2
refused bare_ann_next 'fn f(): i64 {\n    var c: ;\n    c = zz;\n    return c;\n}\nsyscall(60, f());\n' "3:11: undefined variable 'zz'" 2
refused bare_gen      'fn g<T>(a: T): i64 {\n    var c;\n    var d = 9;\n    return d + a + c;\n}\nsyscall(60, g(1) + g(2));\n' "2:10: $UV"
refused bare_ptr      'fn f(): i64 {\n    var c: *i64;\n    var d = 9;\n    return d;\n}\nsyscall(60, f());\n' "2:16: $UV"
rows=$((rows + 1))
check "bare_ptr: no warning beside it" 0 "$(grep -c '^warning' "$T/bare_ptr.err")"
refused bare_zone     'var c;\nvar d = 9;\nsyscall(60, d);\n' "1:6: $UV"
rows=$((rows + 1))
rc=0; "$CC" --syntax-only < "$T/va_missing.cyr" > /dev/null 2> "$T/va_mso.err" || rc=$?
check "va_missing under --syntax-only: refused" "1 yes 1" "$rc $(grep -qF "$VA 'b', got '='" "$T/va_mso.err" && echo yes || echo no) $(grep -c '^error' "$T/va_mso.err")"
# The filed repro verbatim: four annotations, four errors (the global first: pass 1 registers it).
VR='fn f(): i64 {\n    var b: 1 = 0;\n    var c: + = 2;\n    var d: "s" = 3;\n    return b + c + d;\n}\nvar G: 7 = 4;\nsyscall(60, f() + G);\n'
refused va_repro "$VR" "$VA 'G', got number 7" 4
for frag in "$VA 'b', got number 1" "$VA 'c', got '+'" "$VA 'd', got string"; do
    rows=$((rows + 1))
    check "va_repro: names \"$frag\"" yes "$(grep -qF -- "$frag" "$T/va_repro.err" && echo yes || echo no)"
done
# A token that is no type is a syntax error, refused by --syntax-only too (as a parameter's is).
rows=$((rows + 1))
rc=0; "$CC" --syntax-only < "$T/va_loc_num.cyr" > /dev/null 2> "$T/va_so.err" || rc=$?
check "va_loc_num under --syntax-only: refused" "1 yes" "$rc $(grep -qF "$VA 'b'" "$T/va_so.err" && echo yes || echo no)"
# Every arm of the ladder still compiles: a name, `*T`, `[T]`, `u128`, a tuple, `slice<T>`, a generic, in all three places.
runs va_ok "var A: i64 = 3;\nvar P: *i64 = 0;\nvar W: u128 = 2;\nvar Q: (i64, i64) = (1, 2);\nstruct Bx<T> { v: T; }\nvar B: Bx<i64> = 0;\n${FN}    var a: i64 = 3;\n    var p: *i64 = &a;\n    var s: [u8] = 0;\n    var w: u128 = 2;\n    var t: (i64, i64) = (1, 2);\n    var sl: slice<u8> = 0;\n    return a + w + A + W;\n}\nsyscall(39);\nvar L: i32 = 1;\nsyscall(60, f() + L);\n" 11
# A known type that is no return type, WITH type arguments: one error — the `<i64>` is skipped
# with the name, not parsed as the fn body.
refused ret_vec_targs 'fn f(): Vec<i64> { return 3; }\nsyscall(60, f());\n' "type 'Vec' cannot be a fn return type"
# A generic fn's body is parsed for its base and for each instance: one report per name, not three.
refused gen_dedupe    'fn g<T>(a: T): i64 {\n    var x: Nope = 1;\n    var y: Nope2[2];\n    return 0;\n}\nfn h(): i64 { var a = g<i32>(1); var b = g<i64>(2); return a + b + g(3); }\nsyscall(60, h());\n' "unknown type 'Nope' for variable 'x'" 2
# Each bad name is reported, and the declaration parses on: four names, four errors, no cascade.
refused four_names    "${FN}    var a: Nope = 1;\n    var b: i8x = 2;\n    var c: *u8q = 0;\n    return sizeof(Zz);\n}\nsyscall(60, f());\n" "unknown type 'Zz' in sizeof" 4
# ... and inside ONE statement too: the refusal clears the panic latch it set, so a second bad
# name in the same signature or expression is reported rather than swallowed by the resync.
refused one_signature 'fn f(a: Nope1, b: Nope2): Nope3 { return a + b; }\nsyscall(60, f(1, 2));\n' "unknown type 'Nope3' as a fn return type" 3
refused one_expression "${FN}    return sizeof(Nope1) + sizeof(Nope2);\n}\nsyscall(60, f());\n" "unknown type 'Nope2' in sizeof" 2

echo "axis 2 - every name of the vocabulary still compiles where it is taken:"
PRE='enum Color { RED = 1; BLUE = 2; }\nstruct Pt { x; y; }\nstruct u8pair { a; b; }\n'
SCALARS="i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool cstring Result Option Tagged Vec Color Pt u8pair"
VECS="f64v2 f64v4 f32v4 f32v8 i8v16 u8v16 i16v8 u16v8 i32v4 u32v4 i64v2 u64v2"
loc="" glb="" pp="" ptr="" gptr="" sl="" slg="" par="" szs="" fld="" mret=""
n=0
for t in $SCALARS; do
    n=$((n + 1))
    # 6.7.3 (B2): a bool takes a boolean value — `= false`, never `= 0`.
    z=0; [ "$t" = bool ] && z=false
    case $t in Pt|u8pair) loc="$loc    var l$n: $t;\n" ;; *) loc="$loc    var l$n: $t = $z;\n" ;; esac
    glb="${glb}var g$n: $t = $z;\n"
    pp="${pp}var q$n: $t = $z;\n"
    ptr="$ptr    var p$n: *$t = 0;\n"
    gptr="${gptr}var gp$n: *$t = 0;\n"
    sl="$sl    var s$n: [$t] = 0;\n"
    slg="$slg    var t$n: slice<$t> = 0;\n"
    par="${par}fn pf$n(a: $t): i64 { return 0; }\n"
    szs="$szs    k = k + sizeof($t);\n"
    fld="$fld    f$n: $t;\n"
    case $t in Pt|u8pair|f64|f32) ;; bool) mret="${mret}fn mr$n(): (i64, $t) { return (1, false); }\n" ;; *) mret="${mret}fn mr$n(): (i64, $t) { return (1, 2); }\n" ;; esac
done
for t in $VECS; do
    n=$((n + 1))
    loc="$loc    var l$n: $t;\n"
    glb="${glb}var g$n: $t = 0;\n"
    pp="${pp}var q$n: $t = 0;\n"
    ptr="$ptr    var p$n: *$t = 0;\n"
    sl="$sl    var s$n: [$t] = 0;\n"
    slg="$slg    var t$n: slice<$t> = 0;\n"
    par="${par}fn pf$n(a: $t): i64 { return 0; }\n"
    szs="$szs    k = k + sizeof($t);\n"
done
runs v_local   "${PRE}fn f(): i64 {\n${loc}    return 0;\n}\nsyscall(60, f());\n" 0
runs v_global  "${PRE}${glb}syscall(60, 0);\n" 0
runs v_late    "${PRE}syscall(39);\n${pp}syscall(60, 0);\n" 0
runs v_ptr     "${PRE}${gptr}fn f(): i64 {\n${ptr}    return 0;\n}\nsyscall(60, f());\n" 0
runs v_slice   "${PRE}fn f(): i64 {\n${sl}${slg}    return 0;\n}\nsyscall(60, f());\n" 0
runs v_param   "${PRE}${par}syscall(60, 0);\n" 0
# u128 16 + i8..u64 30 + f32 4 + f64 8 + seven 8-byte names (Vec among them) 56 + Pt and u8pair
# 32 + the vectors 224 (eight of 16, two of 16 and two of 32 among the float ones) = 370
runs v_sizeof  "${PRE}fn f(): i64 {\n    var k = sizeof(u128);\n${szs}    return k - 370;\n}\nsyscall(60, f());\n" 0
# i8..i64 15 + u8..u64 15 (their widths since 6.7.10; a full word each before) + f32, f64 12 + bool,
# cstring, Result, Option, Tagged, Vec, Color 56 + Pt, u8pair 32 = 130
runs v_field   "${PRE}struct All {\n${fld}}\nsyscall(60, sizeof(All) - 130);\n" 0
runs v_mret    "${PRE}${mret}var a, b = mr1();\nsyscall(60, a + b);\n" 3
runs v_returns "${PRE}fn r1(): i8 { return 1; }\nfn r2(): i16 { return 2; }\nfn r3(): i32 { return 3; }\nfn r4(): i64 { return 4; }\nfn r5(): cstring { return 0; }\nfn r6(): f64 { return 0; }\nsyscall(60, r1() + r2() + r3() + r4());\n" 10
runs str_param 'fn f(s: Str): i64 { return 4; }\nsyscall(60, f(0));\n' 4
# `Vec<T>`, as the struct-field path has always taken it (and vidya documents `var x: Vec<i64>`
# and `fn f<T>(v: Vec<T>)`): both global zones, a local, a param bare and generic, `*Vec<i64>`,
# an array of handles, and sizeof 8. 8 + 1 + 2 = 11.
runs vec_forms 'var g: Vec<i64> = 0;\nsyscall(39);\nvar h: Vec<i64> = 0;\nfn f(v: Vec): i64 { return 1; }\nfn k<T>(v: Vec<T>): i64 { return 2; }\nfn m(): i64 {\n    var x: Vec<i64> = 0;\n    var p: *Vec<i64> = &x;\n    var a: Vec[2];\n    return sizeof(Vec) + f(x) + k<i64>(x) + g + h;\n}\nsyscall(60, m());\n' 11
runs enum_sides 'enum Color { RED = 1; BLUE = 2; }\nvar g: Color = 2;\nvar h: Late = 1;\nfn f(c: Color, d: Late): i64 { var l: Color = c; var m: Late = d; return l + m + g + h; }\nenum Late { A = 1; }\nsyscall(60, f(3, 4));\n' 10
GEN='fn g<T>(a: T): i64 {\n    var y: T = a;\n    var s: [T] = 0;\n    var p: *T = 0;\n    return y + sizeof(T);\n}\nfn h<A, B, C>(a: A, b: B, c: C): i64 {\n    var y: C = c;\n    return y + sizeof(C);\n}\n'
runs tparams       "${GEN}syscall(60, g(3) + h(1, 2, 4));\n" 23
runs tparams_mono0 "${GEN}syscall(60, g(3) + h(1, 2, 4));\n" 23 CYRIUS_MONOMORPH=0
runs fwd_struct 'fn f(p: *Late): i64 {\n    var q: Late;\n    q.a = 5;\n    return q.a;\n}\nstruct Late { a; b; }\nsyscall(60, f(0));\n' 5
runs own_tparam 'struct Box<T> { v: T; n; }\nsyscall(60, sizeof(Box));\n' 16
runs u8pair_ptr 'struct u8pair { a; b; }\nvar buf: i64[2];\nvar p: u8pair = 0;\nfn f(): i64 {\n    p = &buf;\n    p.a = 300;\n    p.b = 7;\n    if (load64(&buf) != 300) { return 1; }\n    return p.a - 300 + p.b;\n}\nsyscall(60, f());\n' 7

echo "axis 3 - --syntax-only resolves nothing (cyrius lint's pre-pass):"
for r in loc_unknown dz_prefix pp_unknown lptr_prefix gptr_unknown slice_unknown sliceg_prefix param_prefix ret_unknown ret_vec_targs mret_unknown sz_prefix as_unknown four_names; do
    rows=$((rows + 1))
    rc=0
    "$CC" --syntax-only < "$T/$r.cyr" > "$T/$r.so" 2> "$T/$r.soerr" || rc=$?
    check "syntax_only $r: exits 0" 0 "$rc"
    check "syntax_only $r: no type refusal" no "$(grep -qF "unknown type" "$T/$r.soerr" && echo yes || echo no)"
done

echo "axis 4 - a local *i8 / *i16 / *i32 is a pointer to the non-pointer check:"
# warns <name> <source> <expected count of the warning>
warns() {
    rows=$((rows + 1))
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    check "$1: compiles" 0 "$rc"
    check "$1: non-pointer warnings" "$3" "$(grep -c 'assigning non-pointer to typed pointer' "$T/$1.err" || true)"
}
warns ptr_copy_nowarn 'var GB: i64[2];\nfn f(): i64 {\n    var a: *i8 = &GB;\n    var b: *i8 = a;\n    var c: *i16 = &GB;\n    var d: *i16 = c + 1;\n    var e: *i32 = &GB;\n    var e2: *i32 = e - 0;\n    var w: *i16 = b;\n    return 0;\n}\nsyscall(60, f());\n' 0
# ANTI-VACUOUS: an integer into those same pointers still warns, so the row above is not a
# warning that was simply switched off.
warns ptr_int_warns 'fn f(): i64 {\n    var x = 5;\n    var q: *i16 = x;\n    var r: *i8 = x + 1;\n    return 0;\n}\nsyscall(60, f());\n' 2

echo "axis 5 - a vector global is used through its address; a value-form use is refused by name:"
# 6.6.17 (a3): `var g: f64v2 = 0;` owns 16 B (tests/tcyr/crossos/vector_global_storage.tcyr); each
# shape below moved ONE word of it before, silently. The message names the global.
VG='include "lib/alloc.cyr"\ninclude "lib/simd.cyr"\nvar g: f64v2 = 0;\nfn f(): i64 {\n'
VE='    return 0;\n}\nsyscall(60, f());\n'
VM="vector global 'g'"
refused vg_assign_call  "${VG}    g = f64v2_make(3, 4);\n${VE}" "$VM"
refused vg_copy_init    "${VG}    var v: f64v2 = g;\n${VE}" "$VM"
refused vg_from_local   "${VG}    var v: f64v2 = f64v2_make(1, 2);\n    g = v;\n${VE}" "$VM"
refused vg_into_local   "${VG}    var v: f64v2 = f64v2_make(1, 2);\n    v = g;\n${VE}" "$VM"
refused vg_compound     "${VG}    g += 1;\n${VE}" "$VM"
refused vg_untyped_read "${VG}    var x = g;\n    return x;\n}\nsyscall(60, f());\n" "$VM"
refused vg_init_dz      'include "lib/simd.cyr"\nvar g: f64v2 = 5;\nsyscall(60, 0);\n' "vector global 'g' takes no initializer but 0"
refused vg_init_late    'include "lib/simd.cyr"\nvar k = 1;\nk = 2;\nvar g: f64v4 = f64v4_make(1, 2, 3, 4);\nsyscall(60, 0);\n' "vector global 'g' takes no initializer but 0"
# ANTI-VACUOUS: the address, a folded 0 and the routed pointer form all compile and run.
runs vg_addr_ok 'include "lib/alloc.cyr"\ninclude "lib/simd.cyr"\nvar g: f64v2 = 0 + 0;\nvar n: i64 = 5;\nfn f(): i64 {\n    store64(&g + 8, 9);\n    var s: f64v2 = f64v2_add(&g, &g);\n    return n + (&n - &g);\n}\nsyscall(60, f());\n' 21

echo "axis 6 - (6.7.14) a u128 parameter, return or field type is refused by name, once:"
# The user's decision D10 (a), 2026-10-16: until u128 is carried as a 16-byte value a `u128` parameter is refused
# ("pass `*u128`"); a return or field type said "expected identifier, got reserved keyword 'u128' (cannot be used as
# an identifier ...)", which named a non-problem. (issues/archived/2026-10-08-u128-params-returns-fields-captures.md)
UP='`u128` is not supported as a parameter type yet - pass `*u128`'
UR='`u128` is not supported as a fn return type yet'
UF='`u128` is not supported as a field type yet'
refused u128_repro 'include "lib/syscalls.cyr"\ninclude "lib/alloc.cyr"\ninclude "lib/fnptr.cyr"\nfn big(v: u128): i64 { if (v > 0xFFFFFFFFFFFFFFFF) { return 1; } return 0; }       # (1)\nfn bigl(): i64 { var v: u128 = 0; if (v > 0xFFFFFFFFFFFFFFFF) { return 1; } return 0; }\nfn hi(v: u128): i64 { return load64(&v + 8); }                                    # (1)\nfn main(): i64 {\n    alloc_init();\n    var e = 0;\n    if (big(0) != 0) { e = e | 1; }           # 0 > 2^64 - 1 is false\n    if (bigl() != 0) { e = e | 2; }           # control: a local is right since 6.7.6\n    var b: u128 = 5;\n    store64(&b + 8, 7);\n    if (hi(b) == 7) { e = e | 4; }            # documented: the parameter holds the low word only\n    var c: u128 = 5;\n    var f = |q| { if (c == 5) { return 1; } return 0; };                          # (4)\n    var g = |q| { return c + 0; };                                                # (4)\n    if (callptr(f, 0) != 1) { e = e | 8; }\n    if (callptr(g, 0) != 5) { e = e | 16; }\n    return e;\n}\nsyscall(60, main());\n' "$UP" 2
refused u128_ret      'fn mk(): u128 { var b: u128 = 5; return b; }\nsyscall(60, 0);\n' "$UR"
refused u128_field    'struct S { n; w: u128; }\nsyscall(60, 0);\n' "$UF"
refused u128_ufield   'union U { n; w: u128; }\nsyscall(60, 0);\n' "$UF"
refused u128_param    'fn big(v: u128): i64 { if (v > 0xFFFFFFFFFFFFFFFF) { return 1; } return 0; }\nsyscall(60, big(0));\n' "$UP"
refused u128_param_df 'fn g(a: u128, b = 7): i64 { return b; }\nsyscall(60, g(5));\n' "$UP"
refused u128_trait    'struct P { x; }\ntrait T { fn m(self, v: u128): i64; }\nimpl T for P { fn m(self, v): i64 { return 1; } }\nsyscall(60, 0);\n' "$UP"
refused u128_generic  'fn g<T>(a: T, v: u128): i64 { return 1; }\nfn f(): i64 { var x: i32 = 1; return g(x, 2) + g<f64>(1.0, 3) + g(5, 3); }\nsyscall(60, f());\n' "$UP"
refused u128_tr_dflt  'struct P { x; }\nstruct Q { y; }\ntrait T { fn m(self, v: u128): i64 { return 1; } }\nimpl T for P { }\nimpl T for Q { }\nsyscall(60, 0);\n' "$UP"
refused u128_inline   '#inline\nfn g(v: u128): i64 { return 1; }\nfn f(): i64 { return g(2) + g(3); }\nsyscall(60, f());\n' "$UP"
# 6.7.15 (D3 (a)): a trait member's `: u128` return is refused as a fn's is, at the member, once.
refused u128_trait_ret1 'struct P { x; }\ntrait T { fn n(self): u128; }\nsyscall(60, 4);\n' "$UR"
refused u128_trait_ret2 'struct P { x; }\nstruct Q { y; }\nimpl T for P { fn c(self): i64 { return 4; } }\nimpl T for Q { fn c(self): i64 { return 5; } }\ntrait T { fn c(self): u128 { return 4; } }\nsyscall(60, 4);\n' "$UR"
# ANTI-VACUOUS: `*u128` (behind a `*`) and a `*fn( .. )`'s own u128 are read as before; a member's `: *u128` return and
# a `*fn( .. ): u128` type's own return still compile; a u128 local is untouched. (6.7.16: that `*fn( .. ): u128` sits in
# a parameter, `cb`, of a member no impl implements — a member's `*fn( .. )` RETURN is refused since 6.7.16's D9.)
runs u128_ptr_param   'fn lo(v: *u128): i64 { return load64(v); }\nfn f(): i64 { var b: u128 = 5; store64(&b + 8, 7); return lo(&b); }\nsyscall(60, f());\n' 5
runs u128_fnptr_inner 'include "lib/fnptr.cyr"\nfn k(x): i64 { return 3; }\nfn ap(cb: *fn(u128): i64): i64 { return fncall1(cb, 0); }\nsyscall(60, ap(&k));\n' 3
refused u128_trait_ret 'struct P { x; }\ntrait T { fn c(self): u128; }\nimpl T for P { fn c(self): i64 { return 4; } }\nfn f(): i64 { var p = P { 1 }; return p.c(); }\nsyscall(60, f());\n' "$UR"
runs u128_trait_ptr   'struct P { x; }\ntrait T { fn c(self): *u128; }\ntrait T2 { fn d(self, cb: *fn(i64): u128): i64; }\nimpl T for P { fn c(self): *u128 { return 0; } }\nfn f(): i64 { var p = P { 1 }; if (p.c() == 0) { return 4; } return 1; }\nsyscall(60, f());\n' 4
runs u128_local       'fn f(): i64 { var b: u128 = 5; store64(&b + 8, 7); if (b > 0xFFFFFFFFFFFFFFFF) { return 9; } return 1; }\nsyscall(60, f());\n' 9
# 6.7.16: a trait member's `*fn( .. ): u128` parameter — the fn pointer's own return, as a fn's parameter reads it.
runs u128_trait_fnret 'include "lib/fnptr.cyr"\nstruct P { x; }\ntrait T { fn e(self, cb: *fn(i64): u128): i64; }\nimpl T for P { fn e(self, cb: *fn(i64): u128): i64 { return fncall1(cb, 0); } }\nfn k(x): i64 { return 3; }\nfn main(): i64 { var p = P { 1 }; return p.e(&k); }\nsyscall(60, main());\n' 3
refused u128_trait_fnret_own 'struct P { x; }\ntrait T { fn e(self, cb: *fn(i64): u128, v: u128): i64; }\nsyscall(60, 4);\n' "2:45: $UP"
# --syntax-only (what `cyrius lint` runs) refuses them too: the return / field forms were its syntax error.
for sx in u128_ret u128_field u128_param u128_trait_ret1; do
    rows=$((rows + 1))
    rc=0; "$CC" --syntax-only < "$T/$sx.cyr" > /dev/null 2> "$T/$sx.sx" || rc=$?
    check "$sx: --syntax-only exits 1" 1 "$rc"
    check "$sx: --syntax-only error lines" 1 "$(grep -c '^error' "$T/$sx.sx")"
done

echo "axis 7 - a \`*T\` global whose T is no struct names none at \`.field\` (6.7.16):"
# 6.7.16 (issues/2026-10-18-global-pointer-to-unknown-type-reads-first-struct.md) — a `*T` GLOBAL's var type is 0 - its
# step (6.6.17), and `_gv_recv_sid` handed it to the field arms as a struct id: any negative id was the program's FIRST
# struct. `var x: *Foo = 0; x.y` (Foo refused) added "unknown field 'y' on struct 'var'" (the first lexed word), beside
# `struct P { a; }` `x.a` was resolved as P's `a`, a refused late struct's pointer the same; and a SCALAR `*i64` global's
# `x.a` COMPILED (rc 0) and read through P, its store said "unknown field 'a' on struct 'struct'", `x.m()` "undefined
# function 'P.m'". Now the `*T` step band answers no struct (0): the refused annotation stands down (one error), and a
# `*i64` global's `.a` / store / `.m()` is "no struct type in scope for 'x'", the local's words. A `*P` global still
# reads through P (gp_P / gp_P_late). MUTATION (measured: the lane's compiler before the fix, whose `_gv_recv_sid`
# returns GVTYPE for the step band as the slot-open one does): RED 9 — gp_repro1 / gp_repro3 / gp_late (2 errors:
# "unknown field 'y' on struct 'var'"), gp_uses ("undefined function 'P.m'"), gp_i64_read / gp_i64_fn (compiled, rc 0),
# gp_i64_store / gp_i64_late ("unknown field 'a' on struct 'struct'"), gp_i64_meth; green gp_repro2 (one error either
# way: x.a was resolved as P's, silently), gp_i64_local, gp_P, gp_P_late.
NS="no struct type in scope for 'x'"
refused gp_repro1     'var x: *Foo = 0;\nsyscall(60, x.y);\n' "1:9: unknown type 'Foo' as the target of pointer 'x'"
refused gp_repro2     'struct P { a; }\nvar x: *Foo = 0;\nsyscall(60, x.a);\n' "2:9: unknown type 'Foo' as the target of pointer 'x'"
refused gp_repro3     'var a = 1;\na = 2;\nstruct Q { y; }\nvar x: *Q = 0;\nsyscall(60, x.y);\n' "3:1: a \`struct\` declaration must come before the first top-level statement (line 2)"
refused gp_late       'var a = 1;\na = 2;\nvar x: *Foo = 0;\nsyscall(60, x.y);\n' "3:9: unknown type 'Foo' as the target of pointer 'x'"
refused gp_uses       'struct P { a; }\nvar x: *Foo = 0;\nx.a = 3;\nfn g(): i64 { x.a = 1; return x.a + x.m(); }\nsyscall(60, x.a + x.m() + g());\n' "2:9: unknown type 'Foo' as the target of pointer 'x'"
refused gp_i64_read   'struct P { a; }\nvar g = 7;\nvar x: *i64 = &g;\nsyscall(60, x.a);\n' "4:16: $NS; a '.field' access"
refused gp_i64_store  'struct P { a; }\nvar g = 7;\nvar x: *i64 = &g;\nx.a = 3;\nsyscall(60, g);\n' "4:5: $NS; a '.field' assignment"
refused gp_i64_meth   'struct P { a; }\nvar g = 7;\nvar x: *i64 = &g;\nsyscall(60, x.m());\n' "4:16: $NS; a method call"
refused gp_i64_late   'struct P { a; }\nvar g = 7;\ng = 8;\nvar x: *i64 = &g;\nx.a = 3;\nsyscall(60, x.a);\n' "6:16: $NS; a '.field' access" 2
rows=$((rows + 1))
check "gp_i64_late: names the store 5:5" yes "$(grep -qF -- "5:5: $NS; a '.field' assignment" "$T/gp_i64_late.err" && echo yes || echo no)"
refused gp_i64_fn     'struct P { a; }\nvar g = 7;\nvar x: *i64 = &g;\nfn h(): i64 { return x.a; }\nsyscall(60, h());\n' "4:25: $NS; a '.field' access"
refused gp_i64_local  'struct P { a; }\nfn f(): i64 { var g = 7; var x: *i64 = &g; x.a = 3; return x.a; }\nsyscall(60, f());\n' "2:63: $NS; a '.field' access" 2
runs gp_P             'struct P { a; b; }\nvar q = P { 7, 9 };\nvar x: *P = &q;\nsyscall(60, x.b);\n' 9
runs gp_P_late        'struct P { a; b; }\nvar q = P { 7, 9 };\nvar y = 1;\ny = 2;\nvar x: *P = &q;\nx.a = 3;\nsyscall(60, x.b + x.a);\n' 12

if [ "$rows" -lt 140 ]; then echo "FAIL: type_name_refused: only $rows rows ran (floor 140)"; exit 1; fi
if [ "$fails" -ne 0 ]; then echo "FAIL: type_name_refused: $fails check(s) failed"; exit 1; fi
echo "PASS: type_name_refused ($rows rows)"
exit 0
