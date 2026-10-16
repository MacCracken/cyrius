# `(s).a` / `(mk1()).a` — a `.field` after a parenthesised expression is "expected ';', got '.'" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 receives lane (unit R1) with compilers built from that
tree (x86_64, aarch64, cx, PE: refused alike, frontend) and with the lane base (`f59668ad`).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives lane; filed from the 6.7.13 receives lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Low — valid-looking source refused loudly, with a diagnostic that does not name the construct; no wrong
value. Workaround: drop the parentheses (`s.a`, `mk1().a`) or bind first.
**Discovered:** 2026-10-16, the receives lane, probing the 8 B wrapped receive
(`issues/archived/2026-10-14-paren-wrapped-call-untyped-receive-8b-call-and-16b-method.md`): `var x = (mk1()).a;`.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P1 { a; }
fn main(): i64 { var s = P1 { 33 }; return (s).a; }
syscall(60, main());
```

```
$ build/cycc < r.cyr > r
error:<source>:3:47: expected ';', got '.'
```

The same for `var x = (mk1()).a;` with `fn mk1(): P1` (`error:<source>:7:33: expected ';', got '.'`).

## Root cause

The parenthesised-expression factor returns after its `)` with no postfix step: `.field` (and `.method(..)`) after
it is left for the statement, which wants `;`. Guide § Parentheses makes parentheses around a whole struct SOURCE
transparent into its destinations; a postfix field on a parenthesised operand is not covered either way.

## Open question (the user's)

Is `(e).field` valid cyrius? If yes: the factor reads a `.field` / `.method(..)` chain after a wrap whose inside is
a struct value (a name, a call, a field, a dereference), as unwrapped. If no: refuse it by name ("a field of a
parenthesised expression is not read - drop the parentheses") instead of "expected ';'".
