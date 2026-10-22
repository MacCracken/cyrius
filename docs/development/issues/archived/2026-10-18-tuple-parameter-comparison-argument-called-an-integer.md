# D36's tuple-parameter refusal calls a comparison or `!x` argument "an integer" — `take(1 == 1)`, `take(!0)` — where the guide counts them boolean values — RESOLVED

> ✅ **RESOLVED in v6.7.16** (RV-1, `9a58ad376`, with RV-3, `994f45cc5` — no decision needed: wording only, refused before and after, once, at the same column; the default extends 6.7.15's D36 "a bool" to guide § bool's boolean value — the issue's one line to the user was not asked, the triage recording none needed. `_tal_kind` reads the literal-only argument at the parser's own levels (`_tty_arg`: `||` / `&&`, one comparison per operand, PEXPR's and PARSE_TERM's operators, the factor prefixes, parenthesised expressions) and answers its class. The filed repro `take(1 == 1)`, verbatim, is now refused once "2:27: cannot pass a bool to tuple parameter 't' (i64, i64) of 'take' - it takes a tuple" on x86_64, aarch64, cx and PE (was "an integer"); `take(!0)`, `take(2 < 3)`, `take((1 != 0))` (2:28), `take(1 < 2 && 3 > 2)`, `take(!(1 + 2))` the same, while an operator applied to a boolean value stays "an integer" (`take((1 == 1) + 1)`, `take(!0 + 1)`, `take(-(1 == 1))`). Met on the way (RV-3): an argument that is no single expression (`take(1 < 2 < 3)`) gives the parse's own error alone. Rows: `tuple_checked.sh` R17x1 (the repro verbatim) – R17x13 (+ R17x10b) and R17z1 – R17z4 on four legs; R17w3 / R17w4 / R17w10 unchanged. Mutations each RED: no `_tal_kind` call (44 rows), `_tal_kind` judging an unreadable argument (16 rows). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 receives lane (140fd4c3e, 6.7.15's D36: an
argument made only of literals and operators is refused into a tuple parameter); measured on the lane after its
review fixes (x86_64; the frontend, every target).
**Placement:** 6.7.16 — Break 2, repair 6 (receives lane, wave 3, unit R1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — wording only; every shape is refused, once, at the right column.
**Kind:** bug (diagnostic wording).

## Reproduction

```cyrius
fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }
fn f(): i64 { return take(1 == 1); }
syscall(60, f());
```

```
error:<source>:2:27: cannot pass an integer to tuple parameter 't' (i64, i64) of 'take' - it takes a tuple
```

The same "an integer" for `take(!0)`, `take(2 < 3)` and `take((1 != 0))`. `take(true)` and `x.take(!true)` say "a
bool" (tuple_checked.sh R17w3 / R17w10). The guide counts a comparison and `!x` as boolean values, so "a bool" would
match `take(true)`'s wording.

## Root cause

`_tal_scan` (src/frontend/parse_fn.cyr, D36's literal-argument reader) gives kind 2 ("a bool") only when every LITERAL in the
argument is `true` / `false`; it does not look at the operators, so a comparison or a `!` over integer literals is
kind 1 ("an integer").

## Fix direction

Kind 2 when the argument's outermost operator is a comparison or `!` (or every literal is `true` / `false`), else
kind 1; rows beside R17w1-R17w13. D36's words are the user's decided text ("an integer", "a bool" for `true` /
`false`), so the choice of "a bool" for a comparison is worth one line to the user when placed.
