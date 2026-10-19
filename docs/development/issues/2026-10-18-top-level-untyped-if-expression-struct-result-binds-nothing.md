# A top-level untyped `var G = if (c) { B1 } else { B1 };` with a struct branch binds no struct — `G.a` is "no struct type in scope for 'G'", where in a fn `var g = if (..) { b } else { b };` binds; a 16 B struct branch at top level is refused "cannot be a vector, u128 or slice value" — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 receives lane (unit R4) while landing
issues/archived/2026-10-17-top-level-untyped-method-operator-or-known-callee-struct-result-keeps-word.md (6.7.15's D34 / D35:
an untyped top-level whole method, operator or known `&f` result binds its struct). That issue's filed surface and
decisions name a method, an operator, `fncall0(&f)` and `callptr(&f)`; an if-expression yielding a struct is another
whole struct value and was left as found (D34's `_gu_rec` / `_gu_wsid` skip it: `_sc_fi < 0`, a leading `if`).
Measured on the lane after R4 (14cc28034's tree, x86_64); the frontend is shared, so every target.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 receives lane, wave 3; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — valid code refused at the global's first `.field` (8 B); a misleading refusal (16 B).
**Kind:** language (the reach of decision 12 / 6.7.14's D29 and 6.7.15's D34 at top level).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P1 { a; }
var B1 = P1 { 33 };
var G = if (1 == 1) { B1 } else { B1 };
syscall(60, G.a);
```

```
error:<source>:5:16: no struct type in scope for 'G'; a '.field' access needs its struct declaration (missing include?)
```

The same after a first statement (`var Z = 0; Z = 1;` before it, the condition `Z == 1`): `7:16: no struct type in
scope for 'G'`. In a fn, `var b = P1 { 33 }; var g = if (1 == 1) { b } else { b }; return g.a;` exits 33. With a
16 B struct at top level (`struct P2 { a; b; } var B2 = P2 { 33, 4 }; var G = if (1 == 1) { B2 } else { B2 };`) the
two branches are refused `4:23: an if expression branch cannot be a vector, u128 or slice value - branch on a pointer
(&x)` (and again at 4:35) — the words name no struct.

## Root cause

The untyped top-level typing (`_gu_late` after the first statement, `_gu_sweep` in the declaration zone,
src/frontend/parse_decl.cyr) reads a whole free call (6.7.14's D29 / D30) and a whole method / operator / known `&f`
result (6.7.15's D34 / D35); an if-expression's `-3` record (`_ie_struct_result`, parse_ctrl.cyr, `_sc_fi` -1) and
its token reading (`_gz_ie`, kind 1) are skipped on purpose. The 16 B branch refusal comes from the if-expression's
branch classifier, which has no frame to hold a 9-16 B struct at top level and reports it as a vector / u128 / slice.

## The question

Does an untyped top-level if-expression whose branches are a struct of 8 B or less bind that struct (as in a fn,
and as D34 binds a method result), and is a 9-16 B one refused naming the struct (as D35 refuses the method)?
