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
#      site in every const context (V2w). All of them built silently before
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
#      own error once; two consts not ending at `;`; the two controls that always reported both
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
# ... and a const fn body that a const runs at the end of pass 1 and pass 2 checks at its definition
# is reported once per token (`_ce_said`), not once per walk (S12-S14; LC4 above is the annotation's)
refusedn s12 1 "S12: a global read in a const fn body a const runs" 'var g = 1;\nconst fn h(x) { return g; }\nconst Z = h(1);\nsyscall(60, Z);\n' "2:24: 'g' is a variable"
refusedn s13 1 "S13: a builtin in a const fn body a const runs" 'const fn cf(x) { return load64(x); }\nconst Z = cf(0);\nsyscall(60, Z);\n' "1:25: not a compile-time expression"
refusedn s14 1 "S14: an ordinary fn's call in a const fn body a const runs (twice before 6.7.14)" 'fn hh(): i64 { return 1; }\nconst fn h(x) { return hh(); }\nconst Z = h(1);\nsyscall(60, Z);\n' "2:24: 'hh' is not a \`const fn\`"
exits c1 42 "C1: consts, a const fn, a local const, an array size, #assert, a case label, an enum value" 'const N = 4;\nconst fn twice(x) { return x * 2; }\nenum E { EA = twice(N); }\nvar g[N];\n#assert twice(N) == 8, "twice";\nfn f(v): i64 { const L = 2; switch (v) { case twice(N): return 40 + L; default: return 0; } return 1; }\nsyscall(60, f(EA));\n'

if [ "$fails" -ne 0 ]; then echo "FAIL: const_checked — $fails row(s) red"; exit 1; fi
echo "PASS: const_checked — consts are not lvalues (L), initializers and const fn bodies are const contexts checked by name (I, D), evaluations that cannot finish or have no target-independent answer are refused (E), one name one declaration (U), visibility and #deprecated hold in const contexts (V), a const fn's arity is the run time's (G), a refused annotation is one error, the const still bound (A), and well-formed consts run (C), and a refused const holds no cascade latch (S)"
