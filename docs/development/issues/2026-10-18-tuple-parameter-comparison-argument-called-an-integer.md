# D36's tuple-parameter refusal calls a comparison or `!x` argument "an integer" — `take(1 == 1)`, `take(!0)` — where the guide counts them boolean values — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 receives lane (140fd4c3e, 6.7.15's D36: an
argument made only of literals and operators is refused into a tuple parameter); measured on the lane after its
review fixes (x86_64; the frontend, every target).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 receives review, wave 3; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
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
