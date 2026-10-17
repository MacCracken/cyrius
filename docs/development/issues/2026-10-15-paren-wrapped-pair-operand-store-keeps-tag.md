# A store whose whole value is parenthesised and STARTS with a `: stack` pair call — `var v = (f(7) + 1);`, `h.a = (f(7) + 1);`, `x = (f(7) * 2);` — keeps the tag silently, where the unwrapped spelling is refused "bind both" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.13 multivalue lane (l6713-multivalue, unit M2, after the
paren-wrapped pair fix 5ede634e) and on the lane's base compiler (fe98679b): identical on both, x86_64, aarch64 (qemu),
cx (cxvm) and PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R6; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — the payload (an `Err`'s code) is dropped in silence, but only in a spelling the documented operand
rule already reads as the tag (`x = 3 + f();`); the question is which rule a redundant outer wrap selects.
**Kind:** language — a decision for the user: is a parenthesised whole VALUE that starts with a pair call judged by
the 6.7.7 first-call rule ("A store is judged by the call it starts with, so `h.n = f() + 1;` … are refused")?
**Discovered:** 2026-10-15, the 6.7.13 multivalue lane, unit M2, writing the rows for
`issues/archived/2026-10-14-paren-wrapped-stack-pair-call-escapes-every-pair-check.md` (D19 A). D19 made parentheses around a
whole pair CALL transparent (`(f(7))`, `((f(7)))`, `(f(7)) + 1`); a wrap that holds more than the call — `(f(7) + 1)`
— is outside that decision's question and was left as it was.

## Reproduction

```cyrius
enum Res: stack { ROk(v); RErr(e); }
fn f(x) { return ROk(x); }
struct P { a; b; }
fn t1(): i64 { var v = (f(7) + 1); return v; }
fn t2(): i64 { var h: P; h.a = (f(7) + 1); return h.a; }
fn t3(): i64 { var x = 0; x = (f(7) * 2); return x; }
syscall(60, t1() * 100 + t2() * 10 + t3());
```

Compiles clean, exits **110** on all four targets (each value is the tag `ROk` = 0, plus 1 / times 2). The same three
statements unwrapped — `var v = f(7) + 1;`, `h.a = f(7) + 1;`, `x = f(7) * 2;` — are refused, one line each:

```
error:<source>:4:22: a `: stack` enum returns two values — bind both: `var tag, val = f();`
error:<source>:5:32: a `: stack` enum returns two values — bind both: `var tag, val = f();`
error:<source>:6:31: a `: stack` enum returns two values — bind both: `var tag, val = f();`
```

## Root cause

The single-bind and lossy-store refusals (`_refuse_single_pair_bind`, `_refuse_lossy_pair`, src/frontend/parse.cyr)
ask `_callee_returns_pair_at` about the value's FIRST token. Since 6.7.13 `_pair_unwrap` steps over a wrap only when
ONE whole call fills it (D19 A); `(f(7) + 1)` is not that, so the answer is "no pair" and the store keeps the tag, as
an operand that does not start the value does (`x = 3 + f(7);`, the documented operand rule, D22).

## Options (the user's call)

- A: a wrap around the whole value is transparent to the first-call rule too: `var v = (f(7) + 1);` is refused as
  `var v = f(7) + 1;` is (peel `_pwrap_k` parentheses whose close ends the value, then ask about the inside's first
  token). Programs that compile today (they kept the tag) stop compiling.
- B: leave it: only a wrap around the call itself is transparent; the guide says so.

Rows either way: the three statements above (refused under A, 110 under B), a wrapped operand that does not start the
value (`x = (3 + f(7));`, the tag, both), and `?` inside the wrap (`x = (f(7)? + 1);`, propagates, both).
