# A fn declared `: P1` (a struct of 8 B or less) that says `return mk(..);` of a multi-value call returns its first value as the struct — RESOLVED

> ✅ **RESOLVED in v6.7.13** (MV-14 (the user's decision D25, 2026-10-15: A, refused by name, 6.7.11's D20 / D21 "a multi-value call is not a struct value"): in a fn returning a struct of 8 B or less, `return mk(..);` of a multi-value call is refused: "a multi-value call 'mk' is not returned as struct 'P1' - bind it first: `var a, b = mk(..);`". The call may be declared, counted, a method or a generic, with parentheses transparent; the new kind is `_mv_struct_err` kind 4. The filed repro exited 3 on x86_64, aarch64, cx and PE and is refused at 3:21 on all four. The issue's undeclared `mku` form (13) is refused too. The 9 – 16 B and over-16 B texts are unchanged. Rows: `frontend/multi_value_into_named_struct.sh` axis RT (RT1 the repro verbatim, RT2 `mku`, RT3 a method, RT4 wrapped, RT7 three values, RT8 a generic, RT9 / RT10 the other classes, RT5 / RT6 the controls), each on x86_64 / aarch64 / cx / PE; mutation N17 RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane (l6711-returns, after unit R2) on
x86_64, aarch64 (qemu), cx (cxvm) and PE (wine): the repro builds clean and exits 3.
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D25 — A.
**Severity:** Medium — silent: the struct is built from the call's first value; nothing crashes.
**Discovered:** 2026-10-14, the 6.7.11 returns lane (unit R2), while repairing
`2026-10-09-multi-value-call-into-named-struct-slot.md`, whose decision (A, 2026-10-13) refuses a multi-value
call where a named struct is expected in an argument, a declaration, a field and an assignment. A `return`
from a struct-returning fn is another such destination, outside that issue's filed surface.

## Reproduction

```cyrius
struct P1 { a; }
fn mk(a): (i64, i64) { return (a, a + 1); }
fn g(): P1 { return mk(3); }
fn f(): i64 { var p: P1 = g(); return p.a; }
syscall(60, f());
```

Exits 3 on x86_64, aarch64, cx and PE (the first value as `p.a`). The undeclared callee `fn mku(a) { return (a,
a + 1); }` the same (`p.a + 10` exits 13). The 9-16 B form is refused by name ("a fn returning the 9-16 byte struct
`P` is returned in two registers, so `return` takes a local of that struct or a call returning it — got `mk`"), and
the > 16 B form too ("struct-return fn: return must be a bare local identifier, or a call to a fn returning the
same struct").

## Root cause

An 8 B struct return is one word in rax, so PARSE_RETURN takes any expression's value for it; nothing asks whether
a whole-call return expression is a multi-value call (`_mv_callee`, parse_fn.cyr). The question for the fix is the
user's: refuse it by name (as the named-struct destinations and the 9-16 B return are), consistent with "a
multi-value call is not a struct value".
