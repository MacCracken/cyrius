#!/bin/sh
# tests/gates/frontend/const_checked.sh — 6.7.2 (B1, C1)
#
# CONSTS AND `const fn` ARE CHECKED. The user's decisions (2026-10-07): a `const` has no storage
# (int / f64 / string; top level and inside fns); a `const fn` runs at compile time in const
# contexts only; its body is the pure subset, checked at the DEFINITION, called or not. The runtime
# half is tests/tcyr/crossos/const_values.tcyr, const_contexts.tcyr and const_fn_f64.tcyr.
#
#   L  a const is not an lvalue: `N = ..`, `N += ..`, `&N`, a local const `L = ..`, and (6.7.3) a
#      classic-for step `N = N + 1` / `L += 1` — refused once. Before 6.7.3 the step compiled, and
#      a top-level const's size-0 slot let its store overwrite a neighbouring global
#   I  a const initializer is a const context: a global variable, an ordinary fn's call, an unknown
#      name, a fn's runtime local — each refused once, by name; (6.7.11) an ordinary fn's call as an
#      enum value, once — the member loop read the refused `h()` as a constructor (a second error at
#      the link, "refusing to emit binary")
#   D  a const fn's body, checked at its definition (never called): a builtin that touches memory,
#      a global variable in an untaken arm, an array local, an ordinary fn's call, a generic const fn
#   E  an evaluation that cannot finish or has no target-independent answer: a const defined in
#      terms of itself, division by zero, a runaway loop (step budget), runaway recursion (depth),
#      string arithmetic, a NaN (0.0 / 0.0)
#   U  one name, one declaration: a const twice, a const and a var at top level, a local const
#      and a var in one scope (either order); `const` is reserved
#   M  a malformed top-level const is reported, not stepped over; (6.7.7) a value that is not one
#      expression (`sq(3) 4`) is refused once — the end rule `_cst_eval` keeps after `_ce_top_expr`
#   V  a `private` const read in another file's const context is refused (as a read of it is);
#      (6.7.11) V2 another file's `private` const fn CALLED from a const context — a top-level and a
#      local const, a global and a local array size, an enum value, `#assert`, a case label, and the
#      named-argument form — is refused once, at the call, as a run-time call is; a same-file call
#      and a `public const fn` of a private file build; a `#deprecated` const fn warns once per call
#      site in every const context (V2w). All of them built silently before; (6.7.14) V3 the same call
#      in an arm the evaluator SKIPS — `1 || pk()`, `0 && pk() == 3`, an untaken else / elif arm, a
#      local const, an #inline body, an arm re-walked beside a forward const — refused once at the call,
#      and a #deprecated one warns once (V3w), as the run-time `var X = 1 || pk();` (V3r) always was
#   C  ANTI-VACUOUS: consts, a const fn, a local const and every const context build and run; three
#      heavy consts each within its OWN step budget; (6.7.7) an uncalled const fn whose parameter type
#      holds a comma inside `<..>` builds (the definition check's two parameter counts agree)
#   G  (6.7.11) a const fn's arity in a const context is the run time's: `_ce_nparams`,
#      `_ce_bind_params` and `_ce_tup_param` walk the parameter list with the parser's `_pl_next`, so
#      `p: Pair<i64, i64>` is ONE parameter — the filed repro `pick(0, 7)` runs (it was refused) and
#      `pick(0, 1, 7)` is refused (it bound a phantom parameter named `i64`; the user's decision (a),
#      2026-10-13); `*Pair<..>`, the generic parameter last, `Vec<Vec<i64>>` (`>>`), `Pair<i64,
#      Vec<Vec<i64>>>` (`>>>`), a default holding `<`, the default fill and the named form
#   S  (6.7.14) a refused const does not hold the cascade latch: the filed repro and its table — the
#      end-of-pass-1 sweep's next const, a default after a bad const, a const after a bad enum value or
#      global array size, a local const in pass 2 after a pass-1 refusal (it was swallowed, or the
#      statement after it was, so its name read as a FALSE "undefined variable 'L'") — each prints its
#      own error once; two consts not ending at `;`; the two controls that always reported both;
#      a forward if-expression arm's mismatch re-checked at the sweep's end holds no latch either
#   R  (6.7.14) a local const in an `#inline` / generic body ends with its replay: the issue's table —
#      two calls in one expression / two statements, one instance twice, two instances, beside a
#      caller const — builds with its value (each refused "'L' is already declared in this scope"
#      before), a nested-block call and calls in two fns as before; the replay's const stays invisible
#      after the call (R10); the nine values again on aarch64 under qemu (R-a64)
#   B  (6.7.14) a statement or a for step naming a const or an enum constant without `=` / `op =` — `N;`,
#      `N + 1;`, `N == 5;`, `GREEN;`, `Color.GREEN;`, a local const `L;`, a step `N` — is "expected '='", once
#      (it was "cannot assign to const 'N'"); B9 the variable it now matches, B10 / B11 a real assignment's
#      lvalue refusal kept
#   F  (6.7.14) a field access in a const fn, or on a const, is refused once by its own rule: a field store /
#      read on a const fn's local or parameter ("a field is not in a const fn: ...", at the `.`; the run-time
#      compile of the refused body no longer adds "no struct type in scope for 'a'"), a store / read on a
#      top-level or local const ("cannot assign to a field of const 'C'" / "const 'C' has no fields - a
#      const has no storage"; they blamed a missing include, and a local const added "undefined variable
#      'L'"), and `C.x` in a const context (a const's value, a const fn body, an array size, a local
#      const's value). The two filed repros verbatim (F3, F8). Controls: a local const named like a global
#      struct leaves `L.x` the global's field (F14), a struct local beside a const (F15)
#   A  (6.7.13) a refused annotation `const k: i64 = 3;` is ONE error: the const is still bound (its
#      value after the `=`), so no read of it adds "undefined variable 'k'" — a local const (LC1, the
#      filed repro), a closure body (LC2), a top-level const read above and below it (LC3), a const
#      fn body (LC4); a refused value reports its own error beside it and nothing else (LC5); the
#      unannotated const is unchanged (LC6). Before, every read of the name was a second error
#
# Mutations (scratch trees, each RED here — run 2026-10-07): `_cst_lvalue_check` answering 0 ->
# L1-L3 BUILD; (6.7.3) `_for_step_assign` without its `_asg_lvalue_refused` check -> L5, L6 BUILD
# (stock 6.7.2 / 6.7.3 too); `_ce_check_fn` a no-op -> D1-D4 BUILD; `_ce_step` not counting -> E3 hangs (killed
# by the 60 s timeout, RED); `_cst_eval` neither zeroing nor restoring `_ce_steps` (the pre-review
# shared budget) -> C2 refused as an endless loop; `_ce_name`'s local-variable refusal removed -> I4 refused only as an
# unknown name. 6.7.7 (run 2026-10-09, on the `_ce_top_expr` factor): `_ce_top_expr` neither zeroing nor
# restoring `_ce_steps` -> C2 refused; `_cst_eval` without its `;` check -> M2 BUILT; `_ce_bind_params` alone
# stepping with the `<`-aware `_pl_next` -> C3 refused (the count disagreed; 6.7.11 moved all three walkers).
# 6.7.11 (run 2026-10-14): `_cst_ctx_val` without its `_cst_ctx_skip` call -> I5 RED (2 error lines);
# `_ce_call` without its `_ce_site` call -> V2a-V2g, V2n, V2w, V2w2 RED (built, no warning); `_ce_site`
# without its `_panic` -> V2b-V2d, V2f, V2g RED (a second, cascade error); `_ce_bind_params` back on
# `_tok_item_end` -> C3, G1, G3-G5b, G6, G7 RED; `_ce_nparams` back on paren-depth commas -> C3, G1, G3-G5b,
# G6, G7 RED (the definition check counts 3 and binds 2). `_ce_tup_param` back on `_tok_item_end` stays
# GREEN: a type argument is a name, so the old walk re-synced on the split's name and reached every
# tuple parameter anyway — the walker moved with the other two so the three cannot drift apart.
# `_pl_tdepth` without its `>>` / `>>>` closes -> G5, G5b RED.
# 6.7.13 (run 2026-10-15): `_cst_stmt` back to returning at the refused `:` (no step to the `=`, the
# name never bound) -> LC1, LC2, LC4, LC5, LC5n RED (the "undefined variable 'k'" line is back);
# `_cst_pre_at` without its `: T =` arm -> LC3, LC5t RED (each read of K above and below is a second
# error).
# 6.7.14 (run 2026-10-16): the slot-open compiler -> S0-S9 RED (one error each where two or three are
# due; S6 and S8 a false "undefined variable 'L'") and S14 (two identical lines); `_ce_top_expr` without
# its latch save / restore -> S0-S5, S10 RED (`_pd_eval`'s own `pw` rule is gone); keeping the restore
# but not clearing -> S3, S4 RED; `_tl_pass1` without its `_panic = 0` -> S8 RED; `_cst_semi_refuse`
# latching -> S9 RED; `_ce_said` never deduping -> LC4, S12-S14 RED (each token printed twice).
# `_ce_site` back to returning in skip mode -> V3a-V3g RED (built), V3w / V3w2 RED (no warning).
# `_ce_xpend_one` without its latch save / restore -> S15-S17 RED (the second error swallowed; the
# slot-open compiler the same); restoring without clearing -> S17 RED. PARSE_FNCALL's replay ending
# with a bare `SSDEP` (no `_inl_scope_end`) -> R1, R2, R5-R7, R9 RED (refused, as on the slot-open
# compiler; the aarch64 leg is built from the tree's src/, so a mutant there reddens R-a64 the same).
# B12 / B13 (run 2026-10-16): the compiler before the repair (753a8e92) -> B12, B13 RED (3 of 5, 3 of 4: every
# other statement lost); `_cst_skip_sync` without its `_pair_sync_ti` -> B12, B13 RED.
# B (run 2026-10-16): the compiler before the bite (abeb7839) -> B0-B8 RED ("cannot assign to ..."; B6 too);
# `_asg_lvalue_at` without its `_asg_pair_at` test (always the refusal) -> B0-B3, B5, B6 RED; `_asg_lvalue_at`
# falling through to the statement's own `expected '='` (no report, no step-over) -> B6 RED (a second error,
# "undefined variable 'L'"); `_enum_qual_store_refused` without its `_asg_pair_at` test -> B4, B7, B8 RED.
# F (run 2026-10-16): the compiler before the bite (0095e161) -> F1-F13 RED (F14 / F15 green); `_ce_fld_refused`
# answering 0 -> F1-F3, F9-F13 RED; `_cst_fld_at` answering 0 -> F4-F8 RED; `_ce_fld_said` never standing down
# -> F2, F3 RED (the run-time body's "no struct type in scope for 'a'"); the read refused without
# `_pair_sync_ti` -> F8 RED (the statement after `var v = C.x;` skipped: "undefined variable 'L'").
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: const_checked: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: const_checked: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
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
    chmod +x "$T/$1.bin"; got=0; "$T/$1.bin" || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
LV="a const has no storage"
refused l1 "cannot assign to const 'N'" "L1: N = 4" 'const N = 3;\nfn main(): i64 { N = 4; return N; }\nsyscall(60, main());\n'
refused l2 "cannot assign to const 'N'" "L2: N += 4" 'const N = 3;\nfn main(): i64 { N += 4; return N; }\nsyscall(60, main());\n'
refused l3 "cannot take the address of const 'N'" "L3: &N" 'const N = 3;\nfn main(): i64 { var p = &N; return 0; }\nsyscall(60, main());\n'
refused l4 "cannot assign to const 'L'" "L4: a local const L = 5" 'fn main(): i64 { const L = 3; L = 5; return L; }\nsyscall(60, main());\n'
refused l5 "cannot assign to const 'N'" "L5: a for step N = N + 1" 'const N = 3;\nfn main(): i64 { var n = 0; for (var i = 0; i < 3; N = N + 1) { i = i + 1; n = n + 1; } return n; }\nsyscall(60, main());\n'
refused l6 "cannot assign to const 'L'" "L6: a local const in a for step" 'fn main(): i64 { const L = 3; var n = 0; for (var i = 0; i < 3; L += 1) { i = i + 1; n = n + 1; } return n; }\nsyscall(60, main());\n'

refused i1 "'g' is a variable - a const context takes only constants" "I1: a global variable" 'var g = 5;\nconst N = g + 1;\nsyscall(60, N);\n'
refused i2 "'h' is not a \`const fn\`" "I2: an ordinary fn's call" 'fn h(): i64 { return 2; }\nconst N = h();\nsyscall(60, N);\n'
refused i3 "unknown name 'nosuch' in a const context" "I3: an unknown name" 'const N = nosuch + 1;\nsyscall(60, N);\n'
refused i4 "'x' is a variable" "I4: a runtime local in a local const" 'fn main(): i64 { var x = 3; const L = x + 1; return L; }\nsyscall(60, main());\n'
refused i5 "'h' is not a \`const fn\`" "I5: an ordinary fn's call as an enum value (never read as a member's constructor)" 'fn h(): i64 { return 2; }\nenum E { A = h(), B = 5 }\nsyscall(60, B);\n'

refused d1 "not a compile-time expression" "D1: load64 in a const fn (never called)" 'const fn f(x) { return load64(x); }\nsyscall(60, 1);\n'
refused d2 "'g' is a variable" "D2: a global in an untaken arm" 'var g = 1;\nconst fn f(x) { if (x > 100) { return g; } return x; }\nsyscall(60, 1);\n'
refused d3 "a local in a const fn needs an initial value" "D3: an array local" 'const fn f(x) { var a[4]; return x; }\nsyscall(60, 1);\n'
refused d4 "'h' is not a \`const fn\`" "D4: an ordinary fn's call" 'fn h(): i64 { return 1; }\nconst fn f(x) { return h(); }\nsyscall(60, 1);\n'
refused d5 "a const fn cannot be generic" "D5: a generic const fn" 'const fn f<T>(x: T) { return 1; }\nsyscall(60, 1);\n'

refused e1 "const 'A' is defined in terms of itself" "E1: a cycle" 'const A = B + 1;\nconst B = A + 1;\nsyscall(60, A);\n'
refused e2 "division by zero in a compile-time evaluation" "E2: 10 / 0" 'const fn d(x) { return 10 / x; }\nconst N = d(0);\nsyscall(60, N);\n'
refused e3 "exceeded 10,000,000 steps" "E3: an endless loop" 'const fn spin(x) { while (1 == 1) { x = x + 1; } return x; }\nconst N = spin(0);\nsyscall(60, N);\n'
refused e4 "nested deeper than 2000 const fn calls" "E4: endless recursion" 'const fn r(x) { return r(x + 1); }\nconst N = r(0);\nsyscall(60, N);\n'
refused e5 "a string in arithmetic" "E5: \"ab\" + 1" 'const S = "ab";\nconst T = S + 1;\nsyscall(60, 1);\n'
refused e6 "a NaN in compile-time f64 arithmetic" "E6: 0.0 / 0.0" 'const Z = 0.0 / 0.0;\nsyscall(60, 1);\n'

refused u1 "const 'N' is declared twice" "U1: a const twice" 'const N = 1;\nconst N = 2;\nsyscall(60, N);\n'
refused u2 "'N' is already declared as a top-level const" "U2: a const and a var" 'const N = 1;\nvar N = 2;\nsyscall(60, N);\n'
refused u3 "'L' is already declared in this scope (a const)" "U3: a local const, then a var" 'fn main(): i64 { const L = 1; var L = 2; return L; }\nsyscall(60, main());\n'
refused u4 "'L' is already declared in this scope" "U4: a var, then a local const" 'fn main(): i64 { var L = 1; const L = 2; return L; }\nsyscall(60, main());\n'
refused u5 "reserved keyword 'const'" "U5: const is reserved" 'var const = 3;\nsyscall(60, 1);\n'

refused m1 "expected '=', got ';'" "M1: a malformed top-level const is reported (not skipped)" 'const X;\nsyscall(60, 1);\n'
refused m2 "expected ';' after a const's value" "M2: a const's value is ONE expression" 'const fn sq(a) { return a * a; }\nconst N = sq(3) 4;\nsyscall(60, N);\n'
# V — a `private` const of another file, read in a const context, is refused as any read of it is
mkdir -p "$T/v"
printf 'private\nconst SECRET = 3;\nfn sec_ok(): i64 { return SECRET; }\n' > "$T/v/priv.cyr"
printf 'include "priv.cyr"\nvar a[SECRET];\nsyscall(60, 1);\n' > "$T/v/usep.cyr"
vrc=0; ( cd "$T/v" && "$CC" < usep.cyr > /dev/null 2> e ) || vrc=$?
if [ "$vrc" -eq 0 ]; then bad "V1: another file's private const as an array size BUILT"
elif [ "$(grep -c "'SECRET' is private to its file" "$T/v/e")" -ne 1 ]; then bad "V1: refused, but not once as private: $(grep '^error' "$T/v/e" | head -1)"
else ok "V1: another file's private const in a const context: refused once"; fi
# V2 (6.7.11) — another file's private const fn CALLED from a const context: refused once, at the call
mkdir -p "$T/v2"
printf 'private\nconst fn pk(): i64 { return 3; }\nconst fn pk2(a, b = 1): i64 { return a + b; }\npublic\nconst fn pp(): i64 { return 5; }\n' > "$T/v2/priv.cyr"
vrefused() {   # <name> <name:line:col fragment> <what> <source after the include line>
    printf 'include "priv.cyr"\n%b' "$4" > "$T/v2/$1.cyr"
    rc=0; ( cd "$T/v2" && timeout 60 "$CC" < "$1.cyr" > "$1.bin" 2> "$1.err" ) || rc=$?
    n=$(grep -c '^error' "$T/v2/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$n" -ne 1 ] || ! grep -q "^error:<source>:$2' is private to its file" "$T/v2/$1.err"; then
        bad "$3: $n error lines (want 1, at $2): $(grep '^error' "$T/v2/$1.err" | head -2 | tr '\n' '|')"
    else ok "$3: refused once, at the call"; fi
}
vrefused v2a "2:11: 'pk" "V2a: a top-level const" 'const X = pk();\nsyscall(60, X);\n'
vrefused v2b "2:28: 'pk" "V2b: a local const" 'fn main(): i64 { const L = pk(); return L; }\nsyscall(60, main());\n'
vrefused v2c "2:12: 'pk" "V2c: a global array size" 'var g: i64[pk()];\nsyscall(60, 1);\n'
vrefused v2d "2:29: 'pk" "V2d: a local array size" 'fn main(): i64 { var a: i64[pk()]; return 1; }\nsyscall(60, main());\n'
vrefused v2e "2:14: 'pk" "V2e: an enum value" 'enum E { A = pk() }\nsyscall(60, A);\n'
vrefused v2f "2:9: 'pk" "V2f: #assert" '#assert pk() == 3, "x";\nsyscall(60, 1);\n'
vrefused v2g "2:34: 'pk" "V2g: a case label" 'fn f(x): i64 { switch (x) { case pk(): return 5; default: return 0; } return 1; }\nsyscall(60, f(3));\n'
vrefused v2n "2:11: 'pk2" "V2n: the named-argument form" 'const X = pk2(a: 2);\nsyscall(60, X);\n'
# V3 (6.7.14) — ... and in an arm the evaluator SKIPS: a short-circuit's right operand, an untaken
# if-expression arm (issues/2026-10-14-const-context-skipped-arm-calls-private-const-fn-unchecked.md)
vrefused v3a "2:16: 'pk" "V3a: const X = 1 || pk(); (built, exit 1)" 'const X = 1 || pk();\nsyscall(60, X);\n'
vrefused v3b "2:16: 'pk" "V3b: const X = 0 && pk() == 3; (built, exit 0)" 'const X = 0 && pk() == 3;\nsyscall(60, X);\n'
vrefused v3c "2:36: 'pk" "V3c: an untaken else arm (built, exit 3)" 'const X = if (1 == 1) { 3 } else { pk() };\nsyscall(60, X);\n'
vrefused v3d "2:45: 'pk" "V3d: an untaken elif arm" 'const X = if (1 == 1) { 3 } elif (2 == 2) { pk() } else { 4 };\nsyscall(60, X);\n'
vrefused v3e "2:33: 'pk" "V3e: a local const's short-circuit" 'fn main(): i64 { const L = 1 || pk(); return L; }\nsyscall(60, main());\n'
vrefused v3f "3:30: 'pk" "V3f: in an #inline body, its definition and its replay" '#inline\nfn w(): i64 { const L = 1 || pk(); return L; }\nfn main(): i64 { return w(); }\nsyscall(60, main());\n'
vrefused v3g "2:36: 'pk" "V3g: an untaken arm beside a forward const (re-walked once every const is known)" 'const X = if (1 == 1) { B } else { pk() };\nconst B = 4;\nsyscall(60, X);\n'
vrefused v3r "2:17: 'pk" "V3r: (control) the run-time var X = 1 || pk();" 'var X = 1 || pk();\nsyscall(60, X);\n'
printf 'include "priv.cyr"\nconst X = pp();\nsyscall(60, X);\n' > "$T/v2/v2p.cyr"
rc=0; ( cd "$T/v2" && timeout 60 "$CC" < v2p.cyr > v2p.bin 2> v2p.err ) || rc=$?
if [ "$rc" -ne 0 ]; then bad "V2p: a public const fn of a private file: rc $rc: $(grep '^error' "$T/v2/v2p.err" | head -1)"
else chmod +x "$T/v2/v2p.bin"; got=0; "$T/v2/v2p.bin" || got=$?
    [ "$got" -eq 5 ] && ok "V2p: a public const fn of a private file: exit 5" || bad "V2p: exit $got, want 5"; fi
exits v2s 9 "V2s: a private file calls its own private const fn in its const contexts" 'private\nconst fn pk(): i64 { return 3; }\nconst X = pk();\nfn main(): i64 { const L = pk(); var a: i64[pk()]; return L; }\nsyscall(60, X + main() + pk());\n'
# V2w — a #deprecated const fn warns once per call site from a const context, as a run-time call does
DK='#deprecated("old")\nconst fn dk(): i64 { return 6; }\n'
exits v2w 6 "V2w: a #deprecated const fn in a top-level const" "${DK}const X = dk();\nsyscall(60, X);\n"
w=$(grep -c "^warning:<source>:3:11: 'dk' is deprecated: old" "$T/v2w.err"); a=$(grep -c "deprecated" "$T/v2w.err")
[ "$w" -eq 1 ] && [ "$a" -eq 1 ] && ok "V2w: ... warned once, at the call" || bad "V2w: $a deprecation warnings, $w at 3:11 (want 1 / 1)"
exits v2w2 6 "V2w2: a #deprecated const fn in all seven const contexts" "${DK}const X = dk();\nvar g: i64[dk()];\nenum E { A = dk() }\n#assert dk() == 6, \"x\";\nfn f(v): i64 { const L = dk(); var a: i64[dk()]; switch (v) { case dk(): return L; default: return 0; } return 1; }\nsyscall(60, f(A) + X - 6);\n"
w=$(grep -c "' is deprecated: old" "$T/v2w2.err"); u=$(grep "' is deprecated: old" "$T/v2w2.err" | sort | uniq -d | wc -l)
[ "$w" -eq 7 ] && [ "$u" -eq 0 ] && ok "V2w2: ... seven warnings, one per call site" || bad "V2w2: $w deprecation warnings ($u repeated), want 7 distinct"
exits v3w 1 "V3w: a #deprecated const fn in a short-circuit's skipped operand" "${DK}const X = 1 || dk();\nsyscall(60, X);\n"
w=$(grep -c "^warning:<source>:3:16: 'dk' is deprecated: old" "$T/v3w.err"); a=$(grep -c "deprecated" "$T/v3w.err")
[ "$w" -eq 1 ] && [ "$a" -eq 1 ] && ok "V3w: ... warned once, at the call (it was silent)" || bad "V3w: $a deprecation warnings, $w at 3:16 (want 1 / 1)"
exits v3w2 3 "V3w2: ... in an untaken arm beside a forward const (no second warning from the re-walk)" "${DK}const X = if (1 == 1) { 3 } else { B + dk() };\nconst B = 4;\nsyscall(60, X);\n"
w=$(grep -c "^warning:<source>:3:40: 'dk' is deprecated: old" "$T/v3w2.err"); a=$(grep -c "deprecated" "$T/v3w2.err")
[ "$w" -eq 1 ] && [ "$a" -eq 1 ] && ok "V3w2: ... warned once" || bad "V3w2: $a deprecation warnings, $w at 3:40 (want 1 / 1)"
# C2 — each top-level const has its OWN step budget: three of ~3.6 M steps each (10.8 M together, past the 10 M budget)
exits c2 192 "C2: three heavy consts, each within its own budget" 'const fn burn(n) { var s = 0; var i = 0; while (i < n) { s = s + i; i = i + 1; } return s; }\nconst B1 = burn(1200000);\nconst B2 = burn(1200000);\nconst B3 = burn(1200000);\nsyscall(60, (B1 + B2 + B3) & 255);\n'
# C3 (6.7.7) — the definition check's two parameter counts agree, so an uncalled const fn whose
# parameter type holds a comma inside `<..>` builds (6.7.11: both walk with `_pl_next`; one alone
# refused it, 3 counted against 2)
exits c3 3 "C3: an uncalled const fn with a Pair<i64, i64> parameter" 'struct Pair<A, B> { a: A; b: B; }\nconst fn pick(p: Pair<i64, i64>, b) { return b; }\nsyscall(60, 3);\n'
# G (6.7.11) — a const fn's arity in a const context is the run time's (`_pl_next`)
PR='struct Pair<A, B> { a: A; b: B; }\n'
exits g1 7 "G1: the filed repro, pick(0, 7) with p: Pair<i64, i64>" "${PR}const fn pick(p: Pair<i64, i64>, b) { return b; }\nconst N = pick(0, 7);\nsyscall(60, N);\n"
refused g2 "a const fn called with the wrong number of arguments" "G2: pick(0, 1, 7) — one argument too many, as at run time" "${PR}const fn pick(p: Pair<i64, i64>, b) { return b; }\nconst N = pick(0, 1, 7);\nsyscall(60, N);\n"
exits g3 7 "G3: a p: *Pair<i64, i64> parameter" "${PR}const fn pick(p: *Pair<i64, i64>, b) { return b; }\nconst N = pick(0, 7);\nsyscall(60, N);\n"
exits g4 7 "G4: the generic parameter in last place" "${PR}const fn pick(b, p: Pair<i64, i64>) { return b; }\nconst N = pick(7, 0);\nsyscall(60, N);\n"
exits g5 7 "G5: a Vec<Vec<i64>> parameter (the \`>>\` close)" 'include "lib/vec.cyr"\nconst fn pick(v: Vec<Vec<i64>>, b) { return b; }\nconst N = pick(0, 7);\nsyscall(60, N);\n'
exits g5b 7 "G5b: a Pair<i64, Vec<Vec<i64>>> parameter (the \`>>>\` close)" "${PR}include \"lib/vec.cyr\"\nconst fn pick(p: Pair<i64, Vec<Vec<i64>>>, b) { return b; }\nconst N = pick(0, 7);\nsyscall(60, N);\n"
exits g6 47 "G6: a default holding \`<\` (c = 1 < 2) is one parameter" "${PR}const fn pick(p: Pair<i64, i64>, c = 1 < 2, b = 5) { return c * 10 + b; }\nconst N = pick(0);\nconst M = pick(0, 0, 2);\nsyscall(60, N * 3 + M);\n"
exits g7 49 "G7: the default fill and the named form after a Pair<i64, i64> parameter" "${PR}const fn pick(p: Pair<i64, i64>, b = 4) { return b; }\nconst N = pick(0);\nconst M = pick(b: 9, p: 0);\nsyscall(60, N * 10 + M);\n"
# A (6.7.13) — a refused annotation is one error, the const still bound
AN="a const takes no type annotation: its type is its value's"
refused lc1 "1:22: $AN" "LC1: the filed repro, a local const k: i64 = 3 then return k" 'fn f(): i64 { const k: i64 = 3; return k; }\nsyscall(60, f());\n'
refused lc2 "2:48: $AN" "LC2: in a closure body (the enclosing fn has a k)" 'include "lib/fnptr.cyr"\nfn f(): i64 { var k = 5; var cl = |n| { const k: i64 = 3; return k + n; }; return fncall1(cl, 1) + k; }\nsyscall(60, f());\n'
refused lc3 "2:8: $AN" "LC3: a top-level const K: i64 = 3 read above and below it" 'fn f(): i64 { return K; }\nconst K: i64 = 3;\nfn g(): i64 { return K + 1; }\nvar a[K];\nsyscall(60, f() + g());\n'
refused lc4 "1:29: $AN" "LC4: in a const fn body, the const fn called at run time and in a const" 'const fn cf(): i64 { const k: i64 = 3; return k; }\nconst Z = cf();\nfn g(): i64 { return cf(); }\nsyscall(60, g() + Z);\n'
refusedn() {   # <name> <want error lines> <what> <source> <fragment>... : exactly n lines, each fragment present
    nm=$1; want=$2; what=$3; printf '%b' "$4" > "$T/$nm.cyr"; shift 4
    build "$nm"
    n=$(grep -c '^error' "$T/$nm.err")
    if [ "$rc" -eq 0 ]; then bad "$what: BUILT (rc 0)"; return; fi
    if [ "$n" -ne "$want" ]; then bad "$what: $n error lines (want $want): $(grep '^error' "$T/$nm.err" | head -3 | tr '\n' '|')"; return; fi
    for fr in "$@"; do grep -qF "$fr" "$T/$nm.err" || { bad "$what: no \"$fr\": $(grep '^error' "$T/$nm.err" | tr '\n' '|')"; return; }; done
    ok "$what: refused, $want error lines, each its own"
}
refusedn lc5 2 "LC5: a refused value beside the annotation: its own error, no undefined variable" 'fn f(): i64 { const k: i64 = zz + 1; return k; }\nsyscall(60, f());\n' "1:22: $AN" "1:30: unknown name 'zz' in a const context"
refusedn lc5t 2 "LC5t: the top-level form, read above and below" 'fn f(): i64 { return K; }\nconst K: i64 = zz + 1;\nfn g(): i64 { return K + 1; }\nsyscall(60, f() + g());\n' "2:8: $AN" "2:16: unknown name 'zz' in a const context"
refusedn lc5n 2 "LC5n: the next statement still reports its own error" 'fn f(): i64 { const k: i64 = 3; var y = nope; return k; }\nsyscall(60, f());\n' "1:22: $AN" "1:45: undefined variable 'nope'"
exits lc6 3 "LC6: the unannotated local const, unchanged" 'fn f(): i64 { const k = 3; return k; }\nsyscall(60, f());\n'
exits lc6t 7 "LC6t: the unannotated top-level const read above and below, unchanged" 'fn f(): i64 { return K; }\nconst K = 3;\nfn g(): i64 { return K + 1; }\nsyscall(60, f() + g());\n'
# S (6.7.14) — a refused const does not hold the cascade latch: each evaluation prints its own error,
# and pass 2 starts unlatched (issues/2026-10-09-const-sweep-swallows-later-const-errors.md's table)
cp "$ROOT/docs/development/issues/repros/2026-10-09-const-sweep-swallows-later-const-errors.cyr" "$T/s0.cyr"
build s0
n=$(grep -c '^error' "$T/s0.err")
if [ "$rc" -eq 0 ]; then bad "S0: the filed repro BUILT"
elif [ "$n" -ne 3 ] || ! grep -qF "3:11: unknown name 'xx'" "$T/s0.err" || ! grep -qF "4:11: unknown name 'yy'" "$T/s0.err" || ! grep -qF "5:24: undefined variable 'zz'" "$T/s0.err"; then
    bad "S0: the filed repro: $n error lines (want xx 3:11, yy 4:11, zz 5:24): $(grep '^error' "$T/s0.err" | tr '\n' '|')"
else ok "S0: the filed repro: xx, yy and zz, once each"; fi
CU="unknown name"
refusedn s1 3 "S1: three bad consts" 'const A = xx;\nconst B = yy;\nconst D = ww;\nsyscall(60, 0);\n' "1:11: $CU 'xx'" "2:11: $CU 'yy'" "3:11: $CU 'ww'"
refusedn s2 2 "S2: two divisions by zero" 'const A = 10 / 0;\nconst B = 1 / 0;\nsyscall(60, 0);\n' "1:17: division by zero" "2:16: division by zero"
refusedn s3 2 "S3: a bad enum value, then a bad const" 'enum E { Q = yy }\nconst A = xx;\nsyscall(60, 0);\n' "1:14: $CU 'yy'" "2:11: $CU 'xx'"
refusedn s4 2 "S4: a bad global array size, then a bad const" 'var g: i64[yy];\nconst A = xx;\nsyscall(60, 0);\n' "1:12: $CU 'yy'" "2:11: $CU 'xx'"
refusedn s5 2 "S5: a bad const, then a bad default (no 'expects 1 argument' cascade)" 'const A = xx;\nfn g(a = yy): i64 { return a; }\nsyscall(60, g());\n' "1:11: $CU 'xx'" "2:10: $CU 'yy'"
refusedn s6 2 "S6: a bad const, then a bad local const after a var (no false undefined 'L')" 'const A = xx;\nfn main(): i64 { var q = 1; const L = yy; return L + q; }\nsyscall(60, main());\n' "1:11: $CU 'xx'" "2:39: $CU 'yy'"
refusedn s7 2 "S7: a bad const, then a bad local const" 'const A = xx;\nfn main(): i64 { const L = yy; return L; }\nsyscall(60, main());\n' "1:11: $CU 'xx'" "2:28: $CU 'yy'"
refusedn s8 2 "S8: a bad enum value, then a bad local const after a var (no false undefined 'L')" 'enum E { Q = yy }\nfn main(): i64 { var q = 1; const L = ww; return L + q; }\nsyscall(60, main());\n' "1:14: $CU 'yy'" "2:39: $CU 'ww'"
refusedn s9 2 "S9: two consts that do not end at their ';'" 'const A = 1 2;\nconst B = 3 4;\nsyscall(60, 0);\n' "1:13: expected ';' after a const's value" "2:13: expected ';' after a const's value"
refusedn s10 2 "S10: (control) two bad defaults" 'fn g(a = yy, b = ww): i64 { return a; }\nsyscall(60, g());\n' "1:10: $CU 'yy'" "1:18: $CU 'ww'"
refusedn s11 2 "S11: (control) a bad local const in each of two fns" 'fn f(): i64 { const L = yy; return L; }\nfn h(): i64 { const M = ww; return M; }\nsyscall(60, f() + h());\n' "1:25: $CU 'yy'" "2:25: $CU 'ww'"
# ... nor does the re-walk of an if-expression arm that named a forward const (`_ce_xpend_one`): its
# mismatch held the latch past the sweep (found beside the filed table, 6.7.14)
XM="if expression branches differ in type"
refusedn s15 2 "S15: two consts whose forward arms mismatch" 'const X = if (1 == 1) { 3 } else { B };\nconst B = "s";\nconst Y = if (1 == 1) { 3 } else { C };\nconst C = 1.5;\nsyscall(60, 0);\n' "1:36: $XM: a string here" "3:36: $XM: an f64 here"
refusedn s16 2 "S16: a forward arm's mismatch, then a default that is not one expression" 'const X = if (1 == 1) { 3 } else { B };\nconst B = "s";\nfn g(a = 1 2): i64 { return a; }\nsyscall(60, g());\n' "1:36: $XM" "3:12: a parameter default is one constant expression"
refusedn s17 2 "S17: a bad enum value, then a forward arm's mismatch" 'enum E { Q = yy }\nconst X = if (1 == 1) { 3 } else { B };\nconst B = "s";\nsyscall(60, 0);\n' "1:14: $CU 'yy'" "2:36: $XM"
# ... and a const fn body that a const runs at the end of pass 1 and pass 2 checks at its definition
# is reported once per token (`_ce_said`), not once per walk (S12-S14; LC4 above is the annotation's)
refusedn s12 1 "S12: a global read in a const fn body a const runs" 'var g = 1;\nconst fn h(x) { return g; }\nconst Z = h(1);\nsyscall(60, Z);\n' "2:24: 'g' is a variable"
refusedn s13 1 "S13: a builtin in a const fn body a const runs" 'const fn cf(x) { return load64(x); }\nconst Z = cf(0);\nsyscall(60, Z);\n' "1:25: not a compile-time expression"
refusedn s14 1 "S14: an ordinary fn's call in a const fn body a const runs (twice before 6.7.14)" 'fn hh(): i64 { return 1; }\nconst fn h(x) { return hh(); }\nconst Z = h(1);\nsyscall(60, Z);\n' "2:24: 'hh' is not a \`const fn\`"
# R (6.7.14) — a local const in an `#inline` / generic body ends with its replay: the second call in
# one scope was refused "'L' is already declared in this scope"
# (issues/2026-10-14-local-const-in-inline-or-generic-body-refused-at-second-call.md's table)
IW='#inline\nfn w(): i64 { const L = 3; return L; }\n'
GG='fn gg<T>(x: T): i64 { const L = 3; return L; }\n'
R1="${IW}fn main(): i64 { return w() + w(); }\nsyscall(60, main());\n"
R2="${IW}fn main(): i64 { var a = w(); var b = w(); return a + b; }\nsyscall(60, main());\n"
R3="${IW}fn main(): i64 { var a = w(); if (a == 3) { a = a + w(); } return a; }\nsyscall(60, main());\n"
R4="${IW}fn main(): i64 { var a = w(); return a; }\nsyscall(60, main());\n"
R5="${GG}fn main(): i64 { return gg(1) + gg(2); }\nsyscall(60, main());\n"
R6="${GG}fn main(): i64 { var a: i32 = 2; return gg(1) + gg(a); }\nsyscall(60, main());\n"
R7="${GG}fn main(): i64 { var a: i32 = 2; var r = gg(a); var s = gg(a); return r + s; }\nsyscall(60, main());\n"
R8="${GG}fn f(): i64 { return gg(1); }\nfn main(): i64 { return f() + gg(2); }\nsyscall(60, main());\n"
R9="${IW}fn main(): i64 { const L = 10; var a = w(); var b = w(); return a + b + L; }\nsyscall(60, main());\n"
exits r1 6 "R1: #inline w() + w() (refused 2:21)" "$R1"
exits r2 6 "R2: #inline, var a = w(); var b = w(); (refused 2:21)" "$R2"
exits r3 6 "R3: #inline, the second call in a nested block" "$R3"
exits r4 3 "R4: #inline, one call" "$R4"
exits r5 6 "R5: gg(1) + gg(2), one instance twice (refused 1:29)" "$R5"
exits r6 6 "R6: gg(1) + gg(a: i32), two instances (refused 1:29)" "$R6"
exits r7 6 "R7: var r = gg(a); var s = gg(a); (refused 1:29)" "$R7"
exits r8 6 "R8: the generic calls in two fns" "$R8"
exits r9 16 "R9: beside a caller const L (refused 2:21)" "$R9"
refused r10 "undefined variable 'L'" "R10: a replay's const stays invisible after the call (w(); return L;)" "${IW}fn main(): i64 { w(); return L; }\nsyscall(60, main());\n"
# ... and the same rows on aarch64 (qemu): the replay is the frontend's, the values the backend's
skips=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < "$ROOT/src/main_aarch64.cyr" > "$T/xa64" 2> /dev/null && chmod +x "$T/xa64"; then
        for row in "r1 6 $R1" "r2 6 $R2" "r3 6 $R3" "r4 3 $R4" "r5 6 $R5" "r6 6 $R6" "r7 6 $R7" "r8 6 $R8" "r9 16 $R9"; do
            nm=${row%% *}; rest=${row#* }; want=${rest%% *}; src=${rest#* }
            printf '%b' "$src" > "$T/${nm}a.cyr"
            rc=0; timeout 60 "$T/xa64" < "$T/${nm}a.cyr" > "$T/${nm}a.bin" 2> "$T/${nm}a.err" || rc=$?
            if [ "$rc" -ne 0 ]; then bad "R-a64 $nm: rc $rc: $(grep '^error' "$T/${nm}a.err" | head -1)"; continue; fi
            chmod +x "$T/${nm}a.bin"; got=0; timeout 60 qemu-aarch64 "$T/${nm}a.bin" || got=$?
            if [ "$got" -eq "$want" ]; then ok "R-a64 $nm: exit $got (qemu-aarch64)"; else bad "R-a64 $nm: exit $got, want $want"; fi
        done
    else bad "R-a64: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP R-a64: aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
# F (6.7.14) — a field access in a const fn, or on a const, names its own refusal, once
# (issues/2026-10-08-const-field-access-diagnostics-misname-refusal.md). The filed repros verbatim (F3, F8).
refusedf() {   # <name> <want error lines> <what> <fragment>... : $T/<name>.cyr already written
    nm=$1; want=$2; what=$3; shift 3
    build "$nm"
    n=$(grep -c '^error' "$T/$nm.err")
    if [ "$rc" -eq 0 ]; then bad "$what: BUILT (rc 0)"; return; fi
    if [ "$n" -ne "$want" ]; then bad "$what: $n error lines (want $want): $(grep '^error' "$T/$nm.err" | head -4 | tr '\n' '|')"; return; fi
    for fr in "$@"; do grep -qF "$fr" "$T/$nm.err" || { bad "$what: no \"$fr\": $(grep '^error' "$T/$nm.err" | tr '\n' '|')"; return; }; done
    ok "$what: refused, $want error line(s), each its own"
}
FC="a field is not in a const fn: its body takes no memory (fields, arrays, load64, &x)"
FS="a const has no storage"
FM='fn main() { return 0; }\nvar r = main();\n'
refusedn f1 1 "F1: a field store in a const fn (was \"expected ';', got '.'\")" "const fn f(n) {\n    var a = n;\n    a.x = n;\n    return a;\n}\n$FM" "3:6: $FC"
refusedn f2 1 "F2: a field read in a const fn (+ the run-time body's \"no struct type in scope for 'a'\")" "const fn f(n) {\n    var a = n;\n    var b = a.x;\n    return b;\n}\n$FM" "3:14: $FC"
cat > "$T/f3.cyr" <<'EOF'
# 1 / 2 — const fn body
const fn f(n) {
    var a = n;
    a.x = n;          # 1: expected ';', got '.'
    var b = a.x;      # 2: expected ';', got '.'  + no struct type in scope for 'a'
    return b;
}
EOF
refusedf f3 1 "F3: the filed repro 1 / 2, verbatim (the check stops at its first refusal; the body's run-time field errors stand down)" "4:6: $FC"
refusedn f4 1 "F4: C.x = 1 on a top-level const (was \"no struct type in scope for 'C'\")" "struct P { x; y; }\nconst C = 5;\nfn main() {\n    C.x = 1;\n    return 0;\n}\nvar r = main();\n" "4:6: cannot assign to a field of const 'C' - $FS"
refusedn f5 1 "F5: var v = C.x; on a top-level const" "struct P { x; y; }\nconst C = 5;\nfn main() {\n    var v = C.x;\n    return v;\n}\nvar r = main();\n" "4:14: const 'C' has no fields - $FS"
refusedn f6 1 "F6: L.x = 1 on a local const (was \"undefined variable 'L'\" + \"no struct type in scope for 'L'\")" "struct P { x; y; }\nfn main() {\n    const L = 5;\n    L.x = 1;\n    return 0;\n}\nvar r = main();\n" "4:6: cannot assign to a field of const 'L' - $FS"
refusedn f7 1 "F7: var v = L.x; on a local const" "struct P { x; y; }\nfn main() {\n    const L = 5;\n    var v = L.x;\n    return v;\n}\nvar r = main();\n" "4:14: const 'L' has no fields - $FS"
cat > "$T/f8.cyr" <<'EOF'
# 3 / 4 — const receivers
struct P { x; y; }
const C = 5;
fn main() {
    C.x = 1;          # 3: no struct type in scope for 'C'; a '.field' assignment needs ...
    var v = C.x;      # 3: no struct type in scope for 'C'; a '.field' access needs ...
    const L = 5;
    L.x = 1;          # 4: undefined variable 'L'  +  no struct type in scope for 'L'
    return v;
}
var r = main();
EOF
refusedf f8 3 "F8: the filed repro 3 / 4, verbatim (the read is refused in sync: the const L after it is still declared)" "5:6: cannot assign to a field of const 'C' - $FS" "6:14: const 'C' has no fields - $FS" "8:6: cannot assign to a field of const 'L' - $FS"
refusedn f9 1 "F9: a const context, const K = C.x; (was \"expected ';' after a const's value\")" "const C = 5;\nconst K = C.x;\nsyscall(60, K);\n" "2:12: const 'C' has no fields - $FS"
refusedn f10 1 "F10: C.x in a const fn body" "const C = 5;\nconst fn f(n) {\n    return C.x;\n}\n$FM" "3:13: const 'C' has no fields - $FS"
refusedn f11 1 "F11: an array size, i64[C.x] (was \"expected ']', got '.'\")" "struct P { x; }\nconst C = 5;\nfn main() {\n    var a: i64[C.x];\n    return 0;\n}\nvar r = main();\n" "4:17: const 'C' has no fields - $FS"
refusedn f12 1 "F12: a const fn's parameter, p.x" "const fn f(p) {\n    return p.x;\n}\n$FM" "2:13: $FC"
refusedn f13 1 "F13: a local const in a local const's value, const M = L.x;" "fn main() {\n    const L = 5;\n    const M = L.x;\n    return M;\n}\nvar r = main();\n" "3:16: const 'L' has no fields - $FS"
exits f14 12 "F14: control — a local const L beside a global struct L: L.x stores and reads the global's field, as before" 'struct P { x; y; }\nvar L = P { 0, 0 };\nfn main() {\n    const L = 5;\n    L.x = 7;\n    return L.x + L;\n}\nsyscall(60, main());\n'
exits f15 7 "F15: control — a struct local's field beside a local const" 'struct P { x; y; }\nfn main() {\n    var p: P;\n    p.x = 3;\n    const K = 4;\n    return p.x + K;\n}\nsyscall(60, main());\n'
# B (6.7.14) — a statement or a for step that names a const or an enum constant WITHOUT assigning is the
# syntax error a variable gets there, "expected '='", once — not "cannot assign to const 'N'"
# (issues/2026-10-08-bare-const-statement-reported-as-assignment.md; the filed repro verbatim, B0). L1 / L2 /
# L5 / L6 above keep the lvalue refusal for a real `N = ..` / `N += ..`; enum_const_not_lvalue.sh N1-N9 too.
cat > "$T/b0.cyr" <<'EOF'
const N = 5;
enum Color { RED, GREEN }
fn main(): i64 {
    N;              # also: N + 1;  N == 5;  GREEN;  Color.GREEN;  for (i = 0; i < 3; N) { }
    return 0;
}
syscall(60, main());
EOF
refusedf b0 1 "B0: the filed repro, N; (was \"cannot assign to const 'N'\")" "4:6: expected '=', got ';'"
BH='const N = 5;\nenum Color { RED, GREEN }\nfn main(): i64 {\n    '
BT='\n    return 0;\n}\nsyscall(60, main());\n'
refusedn b1 1 "B1: N + 1;" "${BH}N + 1;${BT}" "4:7: expected '=', got '+'"
refusedn b2 1 "B2: N == 5;" "${BH}N == 5;${BT}" "4:7: expected '=', got '=='"
refusedn b3 1 "B3: GREEN; (was \"cannot assign to enum constant\")" "${BH}GREEN;${BT}" "4:10: expected '=', got ';'"
refusedn b4 1 "B4: Color.GREEN;" "${BH}Color.GREEN;${BT}" "4:16: expected '=', got ';'"
refusedn b5 1 "B5: a for step N" "${BH}var i = 0; for (i = 0; i < 3; N) { }${BT}" "4:36: expected '=', got ')'"
refusedn b6 1 "B6: a local const, const L = 3; L; (no \"undefined variable 'L'\" after it)" "${BH}const L = 3; L;${BT}" "4:19: expected '=', got ';'"
refusedn b7 1 "B7: Color.GREEN + 1;" "${BH}Color.GREEN + 1;${BT}" "4:17: expected '=', got '+'"
refusedn b8 1 "B8: a for step Color.GREEN" "${BH}var i = 0; for (i = 0; i < 3; Color.GREEN) { }${BT}" "4:46: expected '=', got ')'"
refusedn b9 1 "B9: control — a variable, var x = 1; x;" "${BH}var x = 1; x;${BT}" "4:17: expected '=', got ';'"
refusedn b10 1 "B10: control — Color.GREEN = 1 keeps the lvalue refusal" "${BH}Color.GREEN = 1;${BT}" "4:17: cannot assign to enum constant 'GREEN'"
refusedn b11 1 "B11: control — a for step N += 1 keeps the lvalue refusal" "${BH}var i = 0; for (i = 0; i < 3; N += 1) { }${BT}" "4:37: cannot assign to const 'N'"
# B12 / B13 (6.7.14, found beside the bare-const fix) — a statement refused at its first name ends in sync, so
# the NEXT statement is parsed and reports its own error: `N = 1; GREEN = 2;` printed only N's (the resync
# skipped every other statement in a row), in a fn and at top level.
refusedn b12 5 "B12: five refused statements in a row, each reported" "${BH}N = 1;\n    GREEN = 2;\n    Color.RED = 3;\n    N;\n    GREEN;${BT}" "4:7: cannot assign to const 'N'" "5:11: cannot assign to enum constant 'GREEN'" "6:15: cannot assign to enum constant 'RED'" "7:6: expected '=', got ';'" "8:10: expected '=', got ';'"
refusedn b13 4 "B13: the same at top level" 'const N = 5;\nenum Color { RED, GREEN }\nN;\nGREEN;\nColor.GREEN;\nvar x = 1;\nx;\nsyscall(60, 0);\n' "3:2: expected '=', got ';'" "4:6: expected '=', got ';'" "5:12: expected '=', got ';'" "7:2: expected '=', got ';'"
exits c1 42 "C1: consts, a const fn, a local const, an array size, #assert, a case label, an enum value" 'const N = 4;\nconst fn twice(x) { return x * 2; }\nenum E { EA = twice(N); }\nvar g[N];\n#assert twice(N) == 8, "twice";\nfn f(v): i64 { const L = 2; switch (v) { case twice(N): return 40 + L; default: return 0; } return 1; }\nsyscall(60, f(EA));\n'

if [ "$fails" -ne 0 ]; then echo "FAIL: const_checked — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: const_checked — $skips leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: const_checked — consts are not lvalues (L), initializers and const fn bodies are const contexts checked by name (I, D), evaluations that cannot finish or have no target-independent answer are refused (E), one name one declaration (U), visibility and #deprecated hold in const contexts (V), a const fn's arity is the run time's (G), a refused annotation is one error, the const still bound (A), and well-formed consts run (C), a refused const holds no cascade latch (S), an #inline / generic body's local const ends with its replay (R, x86 + aarch64), a field on a const fn's local or on a const names its rule once (F), and a bare const statement is expected '=' (B)"
