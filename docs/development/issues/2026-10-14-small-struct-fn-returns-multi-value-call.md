# A fn declared `: P1` (a struct of 8 B or less) that says `return mk(..);` of a multi-value call returns its first value as the struct — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane (l6711-returns, after unit R2) on
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
