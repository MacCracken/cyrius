# An undeclared multi-value call (`return (a, b)`, counted by pass 1) passed to a TUPLE parameter is taken as its address — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane (l6711-returns, after unit R2's
named-struct refusal) on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine): both repros build clean and crash.
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Severity:** High — a clean build that crashes, no diagnostic.
**Discovered:** 2026-10-14, the 6.7.11 returns lane (unit R2), while repairing
`2026-10-09-multi-value-call-into-named-struct-slot.md`. That issue's decision (A, 2026-10-13) covers the NAMED
struct destinations; a tuple parameter is R17's (6.7.7 B4), so this is outside its filed surface.

## Summary

R17 refuses a multi-value call as a tuple ARGUMENT by name ("a multi-value call 'mk' is not a tuple argument -
bind it first"), but only when the callee is DECLARED `: (T1, T2)` (`_tup_arg_call` and `_tup_arg_mrc` test
`GFRS == MULTIRET_SID`). An undeclared callee whose every `return` is `(a, b)` — which 6.7.11's pass 1 now counts
(`_fn_ret_arity`, GFLG bits 65536 / 131072) and which the destructure, the tuple capture and the named-struct
destinations all treat as a multi-value call — is not recognised, so its first value is pushed as the tuple's
address. A tuple FIELD (`h.t = mku(3);`) is already refused (R12's "not a tuple").

## Reproduction

```cyrius
fn mku(a) { return (a, a + 1); }
fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }
fn f(): i64 { return take(mku(3)); }
syscall(60, f());
```

```cyrius
struct B { z; }
impl B { fn mku(self, a) { return (a, a + 1); } }
fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }
fn f(): i64 { var b = B { 0 }; return take(b.mku(3)); }
syscall(60, f());
```

| repro | x86_64 | aarch64 (qemu) | cx (cxvm) | PE (wine) |
|---|---|---|---|---|
| free call | rc 139 | rc 139 | guest error 1 | 5 |
| method | rc 139 | rc 139 | guest error 1 | 5 |
| control: `fn mk(a): (i64, i64)` | refused (R17) | refused | refused | refused |

## Root cause

`_tup_arg_call` (src/frontend/parse_fn.cyr) exits at `GFRS(S, cfi) != MULTIRET_SID`; `_tup_arg_mrc` exits at
`GFRS(S, _mrc_fi) != MULTIRET_SID` (6.7.11 R2 added that guard to keep R17 to its declared callee when the method
record `_mrc_note` began recording counted undeclared methods too). Using `_mv_callee(S, fi)` (declared or
counted) in both — the predicate the named-struct refusal uses — would refuse both repros with R17's text.
