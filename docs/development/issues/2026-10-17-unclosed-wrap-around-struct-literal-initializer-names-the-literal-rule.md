# `var t: P = (P { 5, 6 };` (the wrap's `)` missing) is reported as a struct literal outside an initializer, then "expected ')'" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (unit F6, commit 8d3f7caf, x86_64; the
frontend, every target). Met beside issues/archived/2026-10-11-struct-literal-outside-var-initializer-misdiagnosed.md (the
user's decision D12 (a), 2026-10-16: a struct literal outside an initializer is one named error, and a whole-value
wrap `var q: P = (P { 5, 6 });` IS the initializer). Its fix recognises the wrap only when it is balanced and ends at
the declaration's `;` (`_slit_wrap_k`, src/frontend/parse_decl.cyr); an UNCLOSED wrap falls to the expression path,
whose factor arm (`_slit_stray`, src/frontend/parse_expr.cyr) reports the literal as being outside an initializer —
a rule the user did not break — before the real mistake.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — malformed source, refused either way (through 6.7.13: four errors starting "undefined variable
'P'"; now two). The first of the two names the wrong problem.
**Discovered:** 2026-10-17, probing the wrap transparency of D12 (a).

## Reproduction

```sh
printf 'struct P { a; b; }\nfn run(): i64 { var t: P = (P { 5, 6 }; return t.a; }\nsyscall(60, run());\n' | build/cycc > /dev/null
# error:<source>:2:29: a struct literal is an initializer: declare `var t: P = P { .. };` and assign or pass t
# error:<source>:2:39: expected ')', got ';'
```

Wanted: the one real error, `expected ')', got ';'` (at 2:39), the literal taken as the initializer it was meant to
be (or at least not refused by the initializer rule).

## Root cause

`_lit_head_w` asks `_slit_wrap_k`, which needs `_pwrap_k`'s balanced `( .. )` ending at `;`; an unclosed `(` is no
wrap, so PARSE_VAR parses `(P { 5, 6 }` as an expression and the factor refuses the literal.

## Proposed fix

When the stray literal is the whole inside of an unclosed `(` that directly follows a declaration's `=` (the
token before the literal is `(` and the one before that `=` of a `var`), take it as the wrapped initializer and let
the missing `)` be the one error — or stand the stray refusal down there. Diagnostics only; rows: the repro gives
exactly `expected ')'`, and the balanced wrap (struct_literal_type_refused.sh W1-W7) still compiles.
