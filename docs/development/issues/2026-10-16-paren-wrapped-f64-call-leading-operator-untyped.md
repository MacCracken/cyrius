# `var a = (f()) * 2.0;` with `f: f64` binds an untyped word, where `var a = f() * 2.0;` and `var a = (f());` bind an f64 — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.13 receives fix step on the lane tree (l6713-receives at
360a6d05) and the lane base (f59668ad's `build/cycc`): identical on x86_64, aarch64 (qemu), cx (cxvm), PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives lane; filed from the 6.7.13 receives review, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Low — a wrong value, but the line that uses it draws a kind-1 warning ("integer arithmetic with an f64
right operand").
**Discovered:** 2026-10-16, the receives lane's review of the 92b35796 bite (issues/
archived/2026-10-14-paren-wrapped-call-untyped-receive-8b-call-and-16b-method.md), which made a wrapped `: f64` call that is the
WHOLE initialiser (`var x = (f());`) bind an f64. A wrapped leading call followed by an operator is outside that
surface.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn f(): f64 { return f64_from(5) / f64_from(2); }
fn main(): i64 {
    var a = (f()) * 2.0;
    var y = a + 1.5;
    return f64_to(y);
}
syscall(60, main());
```

```
warning:<source>:5:20: integer arithmetic with an f64 right operand
exit 0 on x86_64 / aarch64 / cx / PE
```

`var a = f() * 2.0;` in its place exits 6 with no warning (a is the f64 5.0). `var a = (f());` exits 4 with no warning
on the lane (the base gave 0 and the warning).

## Root cause

An untyped initialiser takes the f64 kind from a LEADING call (`var a = f() * 2.0;`, the 6.7.x leading-call typing) or,
since 6.7.13, from a wrap that is the whole initialiser (`_var_rhs_wsid`, src/frontend/parse_decl.cyr: `_pwrap_name`
then `TOKTYP(_pw_end) == 5`). A wrap followed by an operator is neither, so the binding stays an integer word holding the
product's f64 bits.

## Fix

Let the leading-call typing look through parentheses that wrap the leading call (`(f()) op ..`), with the
comparison / `&&` / bitwise results kept integers as 5d849a22 / 7c29f2e1 left them (`(f()) < 1.0` binds an integer
today). Rows: `(f()) * 2.0`, `((f())) + 1.0`, `(f()) * 2.0 < 1.0` (an integer), on four legs.
