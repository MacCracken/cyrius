# `var t = (1 2);` is "expected ')'" and then `t.1` adds "no struct type in scope for 't'" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-17, `9af62f08a` — no decision needed (diagnostics). `_var_value` (src/frontend/parse_decl.cyr) marks an untyped `var NAME =` whose parenthesised initializer was refused, and the name's uses stand down as a refused annotation's. The filed repro is "1:26: expected ')', got number 2" alone (no "no struct type in scope for 't'"); after the first statement, `(1 + )` and `((1 2))` likewise; `t.0 = 5`, `t.m()`, `t.1 += 1` add nothing; `var t = zz;` keeps both errors. Rows: tuple_checked.sh CT1 (the filed repro verbatim) – CT10 on five legs; mutants RED CT1 – CT6 CT8 CT9 ×5. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-19 on the 6.7.16 frontend lane (l6716-frontend at 478e4f6cd, x86_64; the
shared front end), the same on the lane's compiler before F5 (11dfa7bff). Met while fixing
issues/archived/2026-10-18-commaless-tuple-literal-named-as-struct-literal.md (whose filing notes the two-element shape's first
error as unchanged; its second was outside that surface).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF3) — never 7.x.
**Severity:** Low — refused (rc 1); a second, invented error.
**Kind:** bug (diagnostics: a refusal cascade).

## Reproduction

```cyrius
fn f(): i64 { var t = (1 2); return t.1; }
```

```
error:<source>:1:26: expected ')', got number 2
error:<source>:1:40: no struct type in scope for 't'; a '.field' access needs its struct declaration (missing include?)
```

`var t = (1 2); return 0;` is the one error; `(1, 2 3)` is one error since 7315613d4 ("expected ',' between tuple
literal elements"), its `t` declared a tuple.

## Root cause

With no `,` in it, `(1 2)` is not taken as a tuple literal (the tuple shape needs a `,`), so the initializer is the
parenthesised expression `(1`, refused at `2`; `t` is declared a scalar, and `t.1` meets the scalar's field refusal.
A refused parenthesised initializer whose next token could open a second element is the tuple's missing `,` — or the
name could stand down after its initializer's refusal (the refused-annotation stand-down's shape).
