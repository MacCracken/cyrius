# `var x = (mk1());` (an 8 B struct) and `var x = (b.mk());` (a 9–16 B method) still infer nothing — the method's first word crashes through a by-value parameter — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane (l6711-returns, unit R4, after its first
commit, which made `var x = (mk());` transparent for a FREE call returning a struct over 8 B) on x86_64, aarch64
(qemu), cx (cxvm) and PE (wine).
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 returns lane) — never 7.x.
**Severity:** High — the method form builds clean and crashes (SIGSEGV on x86_64 / aarch64, a guest error on cx, an
access violation on PE); the 8 B free-call form is loud (valid code refused at `.field`).
**Discovered:** 2026-10-14, the 6.7.11 returns lane (unit R4), repairing shape (a) of
`2026-10-10-struct-receive-inference-paren-call-and-scalar-annotation.md`, whose filed surface is PARSE_VAR's FREE-call
receive of a struct over 8 B. Related: `2026-10-13-untyped-struct-binding-beyond-operators-decision.md` lists the
parenthesised 9–16 B method (`var e = (a.m());`) as "refused at its first `.field`" (Low); passed to a by-value
parameter instead, the same binding crashes — the severity that row is missing.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
impl Q { fn mk(self): Q { var q: Q; q.a = 3; q.b = 4; return q; } }
fn dq(q: Q): i64 { return q.a * 10 + q.b; }
fn main(): i64 { var b = Q { 1, 2 }; var x = (b.mk()); return dq(x); }
syscall(60, main());
```

```
expected: 34 (as `var x = b.mk();` gives, and `var x: Q = (b.mk());`)
actual:   rc 139 (x86_64), 139 (aarch64 qemu), 1 (cx), 5 (PE wine)
```

The 24 B method (`impl Q3 { fn mk3(self): Q3 }`, `var x = (b.mk3()); dq3(x)`) gives 34 on all four.

```cyrius
include "lib/syscalls.cyr"
struct P1 { a; }
fn mk1(): P1 { var p: P1; p.a = 33; return p; }
fn main(): i64 { var x = (mk1()); return x.a; }
syscall(60, main());
```

```
expected: 33 (as `var x = mk1(); return x.a;` gives on all four)
actual:   error: no struct type in scope for 'x'; a '.field' access needs its struct declaration (all four)
```

(`d1(x)` into a by-value `p: P1` parameter gives the right value: an 8 B struct is its word.)

## Root cause

Two readers of the untyped declaration's initialiser still key on its FIRST token. The 8 B free call is typed by
PARSE_VAR's `_ti_inferred_sid` (`_var_rhs_call(S, GTI(S))`, src/frontend/parse_decl.cyr), which wants `IDENT (`; a
`(` gives 0, so x is untyped. The method is typed by `_var_rhs_msid` (`var u = s.m(..);`, 6.7.0 A5) — also by its
first token — and its 9–16 B temp is not taken by `_sc_var_receive` for the untyped wrapped form, so x holds the
first word, which `dq(x)` passes as the struct's address. 6.7.11's `_rcv_peel` (the free call over 8 B) is the
pattern: step a whole wrap (`_pwrap_k` to the `;`) before the first-token test.
