# A tuple literal as a struct literal's element (`W { (1, 2) }` with a tuple field) is refused, then "unexpected '}'" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-16, `647bc08c7` — no decision needed (the R9 refusal is by spec; only the cascade changed). `_spi_expr` (src/frontend/parse_decl.cyr) takes an element in which the factor refused a tuple literal as the whole field. The filed repro is R9's one error, "2:27: a tuple `( .. )` is a value only as a `var` initializer, ..." (no "2:37: unexpected '}'"); `W { (1, 2) }`, a struct field, `(1, 2) + 1`, `g((3, 4))`, either zone and an annotated declaration likewise (its next statement reported); under `--syntax-only` rc 0, nothing said (lint called the file unparseable). Rows: tests/gates/frontend/tuple_checked.sh TL1 (the filed repro verbatim) – TL11 on five legs, TL10 / TL11 run on x86_64, wine, qemu and cxvm; floor 95 (TL + CT); mutants RED TL1 – TL8 ×5. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 frontend lane (l6716-frontend at 478e4f6cd, x86_64; the
shared front end), the same on the lane's compiler before F5 (11dfa7bff). Met while probing every `_tup_elems` caller
for issues/archived/2026-10-18-commaless-tuple-literal-named-as-struct-literal.md.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF3) — never 7.x.
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
