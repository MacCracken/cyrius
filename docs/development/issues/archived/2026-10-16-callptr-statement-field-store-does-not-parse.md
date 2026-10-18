# `callptr(&gp, 5).b = 40;` — a field store through a known callee's result in statement position — is "expected ';', got '='", where `fncall1(&gp, 5).b = 40;` stores through — RESOLVED

> ✅ **RESOLVED in v6.7.14** (RC-8, `52b11479` — no decision needed: 6.7.13's D16 (a) and D8 (a), which the `fncall1` spelling already had: `callptr(&gp, 5).b = 40;` and `+= 40` as statements store through the `: *T` result (PARSE_STMT's one new call, `_stmt_callptr_field`; `_call_field` routes token 137 to `_icall_stmt_chain`, which reads no arity digit for it). The filed repro exits 40 (it was "expected ';', got '='"; `+=` "unexpected '='") on x86_64, aarch64, cx and PE; `callptr(&mk3, 5).b = 1;` is refused by name, "cannot assign to a field of a call result: the result is a temporary", as the fncall1 form; a callee in a variable is refused by 6.7.11 D31's words. Rows: `frontend/call_ptr_field_store.sh` CP1 (the repro verbatim, `docs/development/issues/repros/2026-10-16-callptr-statement-field-store-does-not-parse.cyr`) – CP10 on four legs; `crossos/fncall_struct_result.tcyr` FC15 / FC16 (also on pi and cass); mutations c0 – c2 RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 by the 6.7.13 receives fix step on the lane tree (l6713-receives at
360a6d05): identical on x86_64, aarch64 (qemu), cx (cxvm), PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — a valid statement is refused with a parse error that does not name the rule; no wrong code.
**Discovered:** 2026-10-16, the receives lane's review of the D16 bite (5a73a702 + 389e715d, issues/
archived/2026-10-13-field-of-indirect-call-struct-result.md). D16's filed surface is READING `.field` / `.method(..)` of a
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
