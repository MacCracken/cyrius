# `callptr(&gp, 5).b = 40;` — a field store through a known callee's result in statement position — is "expected ';', got '='", where `fncall1(&gp, 5).b = 40;` stores through — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.13 receives fix step on the lane tree (l6713-receives at
360a6d05): identical on x86_64, aarch64 (qemu), cx (cxvm), PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives lane; filed from the 6.7.13 receives review, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Low — a valid statement is refused with a parse error that does not name the rule; no wrong code.
**Discovered:** 2026-10-16, the receives lane's review of the D16 bite (5a73a702 + 389e715d, issues/
2026-10-13-field-of-indirect-call-struct-result.md). D16's filed surface is READING `.field` / `.method(..)` of a
known callee's result; a store through it in statement position is outside it.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
struct P3 { a; b; c; }
var G: P3 = P3 { 0, 0, 0 };
fn gp(a): *P3 { G.a = a; return &G; }
fn main(): i64 {
    callptr(&gp, 5).b = 40;
    return G.b;
}
syscall(60, main());
```

```
lane:  error:<source>:8:23: expected ';', got '='          (all four legs)
base:  error:<source>:8:20: expected ';', got '.'
```

The same program with `fncall1(&gp, 5).b = 40;` builds and exits 40 on all four (lane; the base refused it "cannot
take a field of the result of 'fncall1': it does not return a struct"). `fncall1(&gp, 5).b += 40;` also exits 40;
`callptr(&gp, 5).b += 40;` is "unexpected '='".

A by-value callee: `callptr(&mk3, 5).b = 1;` (mk3: `P3`) is "expected ';', got '='", where `fncall1(&mk3, 5).b = 1;`
is refused by name: "cannot assign to a field of a call result: the result is a temporary".

`callptr(&mk3, 5).tot();` (a method statement) works.

## Root cause

A statement that starts with `fncallN` reaches the call-statement path, where `_call_field` / `_icall_stmt_chain`
(src/frontend/parse_expr.cyr) take the `.field = v` store. `callptr` is token 137, not an identifier, so its statement
goes through the expression-statement route: PCMPE parses `callptr(&gp, 5).b` as a value and the `=` is left over.

## Fix

Route a statement beginning with token 137 whose call is followed by `.` through the same chain the `fncallN`
statement takes (`_icall_stmt_chain` with the callptr argument offset — parse_expr.cyr already maps `t == 137` to
`o = ti + 1`). Rows: `callptr(&gp, 5).b = 40;` → 40, `+= 40` → 40, `callptr(&mk3, 5).b = 1;` refused by name as the
`fncall1` form is, on four legs.
