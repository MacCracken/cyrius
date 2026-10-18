# `(s).a` / `(mk1()).a` — a `.field` after a parenthesised expression is "expected ';', got '.'" — RESOLVED

> ✅ **RESOLVED in v6.7.14** (RC-11, `c5c4a165` — the user's decision D24 (a), 2026-10-16: the wrap is transparent: a `.field` / `.m(..)` after parentheses around a struct value reads it as without them — `(s).a`, `((s)).a`, `(p).a` and `(*p).a` for a `*S`, `(s).m()`, `(mk1()).a`, `(mk3(5)).b`, a method / operator / known `&f` result, a struct-typed field, a `: *S` call, chains, and the statements `(s).m();` / `(mk1()).a;` (`_paren_field` in PARSE_FACTOR, `_stmt_paren_field` in PARSE_STMT). The filed repro exits 33 (it was "expected ';', got '.'"), and `var x = (mk1()).a;` reads the field, on x86_64, aarch64, cx and PE. A wrap around a non-struct (`(x + 1).a`) and a store `(s).a = v;` / `+= v` are refused by name; at top level a struct result once. ⚠ Beyond the decision's "exactly as unwrapped": the statement `(s).a;` compiles as a discarded read, where `s.a;` is refused. Rows: NEW `frontend/paren_field_access.sh` R0 (the repro verbatim, `docs/development/issues/repros/2026-10-16-field-of-parenthesised-expression-does-not-parse.cyr`), V1 – V12, A1, N1 – N7 on four legs (FLOOR 21); `crossos/struct_receive_paren_call.tcyr` group "6.7.14 (D24)" (also on pi and cass); mutations RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 receives lane (unit R1) with compilers built from that
tree (x86_64, aarch64, cx, PE: refused alike, frontend) and with the lane base (`f59668ad`).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D24 — (a).
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
