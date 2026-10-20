# A tuple literal as a struct literal's element (`W { (1, 2) }` with a tuple field) is refused, then "unexpected '}'" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 frontend lane (l6716-frontend at 478e4f6cd, x86_64; the
shared front end), the same on the lane's compiler before F5 (11dfa7bff). Met while probing every `_tup_elems` caller
for issues/2026-10-18-commaless-tuple-literal-named-as-struct-literal.md.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — refused (rc 1); a second, invented error.
**Kind:** bug (diagnostics: a refusal cascade).

## Reproduction

```cyrius
struct W { p: (i64, i64); q; }
fn f(): i64 { var w = W { (1, 2), 3 }; return w.q; }
syscall(60, f());
```

```
error:<source>:2:27: a tuple `( .. )` is a value only as a `var` initializer, assigned to a tuple variable or field, as a tuple argument, or after `return` - here one value is expected
error:<source>:2:37: unexpected '}'
```

`struct W { p: (i64, i64); }` with `W { (1, 2) }` the same (2:34 "unexpected '}'").

## Root cause

The struct literal's walk descends into the tuple field's two leaves (a tuple is a struct of its elements): the
refused `(1, 2)` is consumed as the first leaf's value, so the walk wants one value more than the literal has and meets
the `}`. As 6.6.12's kind-4 value ("a struct call already refused ... the whole field is consumed"), a refused whole
value for a nested field should end that field.
