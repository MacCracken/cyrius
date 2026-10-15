# A pointer-annotated local from a by-value struct call: `var x: *P2 = mkp();` (16 B) compiles with only a warning and SIGSEGVs at `x.b`; `var x: *i64 = mkp();` holds the first word — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane tip (l6711-returns, `build/cycc` the fixpoint
of 4288c67f + the review's doc fix) and on the lane base 0f733aea (the slot-open cycc), x86_64.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 returns review) — never 7.x.
**Severity:** Medium — a warning is printed, but the program it lets through crashes (`*P2`) or reads a value as a
pointer (`*i64`).
**Affects:** every compiler with PARSE_VAR's struct receive — pre-existing; outside the 6.7.11 R4 decision
(issues/archived/2026-10-10-struct-receive-inference-paren-call-and-scalar-annotation.md, A: refuse by name for a SCALAR or
handle annotation), which does not name a pointer annotation.
**Discovered:** 2026-10-14, the 6.7.11 returns lane's review (of 92b690cb).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P2 { a; b; }
fn mkp(): P2 { var p: P2; p.a = 333; p.b = 3; return p; }
fn main(): i64 {
    var x: *P2 = mkp();
    return x.b;
}
var rc = main();
syscall(60, rc);
```
```
warning:<source>:5:23: assigning non-pointer to typed pointer
        var x: *P2 = mkp();
                          ^
```
Compile rc 0; exits **139** (lane tip and base).

```cyrius
include "lib/syscalls.cyr"
struct P2 { a; b; }
fn mkp(): P2 { var p: P2; p.a = 333; p.b = 3; return p; }
fn main(): i64 {
    var x: *i64 = mkp();
    return x;
}
var rc = main();
syscall(60, rc);
```
```
warning:<source>:5:24: assigning non-pointer to typed pointer
        var x: *i64 = mkp();
                           ^
```
Compile rc 0; exits **77** (333 & 255: the struct's first word, held as a pointer) — lane tip and base.

## Root cause

PARSE_VAR's struct receive (src/frontend/parse_decl.cyr, the block at `if ((pscale <= 0) && (PEEKT(S) == 4) &&
(GINFN(S) == 1))`) is gated on `pscale <= 0`, so a `*T` annotation (pscale > 0) gets neither the receive nor 6.7.11's
`_rcv_scalar_ann` refusal: the call's value (rax — the first word for a 9-16 B struct, the hidden return pointer's
target never set up for a > 16 B one) is stored as the pointer, and only the typed-pointer warning is said.

## Fix

The user's call on the shape (a decision): refuse by name at the call, as R4 refuses a scalar annotation ("cannot
initialise 'x: *P2' from 'mkp', which returns the struct 'P2' — declare 'x: P2' and take `&x`"), or receive the struct
into a hidden slot and point `x` at it. Rows: `*P2`, `*i64`, `*u8` at 16 B and 24 B, wrapped `(mkp())`, a generic
callee; the 8 B struct as a control.
