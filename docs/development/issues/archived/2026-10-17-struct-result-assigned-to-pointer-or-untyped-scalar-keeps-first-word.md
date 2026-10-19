# `p = mkp();` into a `*i64` / `x = mkp();` into an untyped scalar — a struct result over 8 B ASSIGNED where D27 does not reach keeps its first word (the `*i64` one SIGSEGVs) — RESOLVED

> ✅ **RESOLVED in v6.7.15** (RC-11, `ae0ccb2c2` (question 1) and RC-12, `326c1b56a` (question 2) — the user's decisions D32 (a) and D33 (a), 2026-10-18: both refused by name. `_asa_judge` (src/frontend/parse.cyr) refuses a `*T` destination (not `*S` of the result's own struct) with 6.7.13 D14's words and an untyped one with 6.7.14 D27's words minus the annotation (`_rcv_unt_refuse`, src/frontend/parse_decl.cyr), on every path `_asa_refuse` serves (the free call, a method, an operator, a known `&f`, a for step, wrapped, in a fn and at top level). Repro 1 (`p = mkp();` into `*i64`), which faulted (139 x86_64 / aarch64, cx 0, PE 5), is refused `6:9: cannot assign 'p: *i64' from 'mkp', which returns the struct 'Q' - declare 'p: Q' and take `&p`` on all four; repro 2 (`x = mkp();` into `var x = 0;`), which exited 77, is refused `6:9: cannot assign 'x' from 'mkp', which returns the struct 'Q' - declare 'x: Q' or bind a field` on all four. The untyped global, the destructure name of `(f64, f64)`, a for-init / for-in name and a closure's parameter are refused too. A `*Q` destination of the same struct copies; 8 B or less and a `Str` keep their word; `var x = mkp(); x = mkp();` copies. Rows: `frontend/struct_result_type_refused.sh` AP0 (repro 1 verbatim) – AP13, APK1 / APK2, AU0 (repro 2 verbatim) – AU14, AUK1 – AUK5, AFK1 / AFK2 flipped to refusals; `crossos/struct_receive_paren_call.tcyr` group "6.7.15 (D32 / D33)" on four legs and on pi, ecb, ach, cass; mutations RED. Filed (6.7.16; pre-existing): inside a generic called with `T = i64` / `u8`, `p = mkp();` into `p: *T` keeps the first word (`2026-10-18-generic-instance-t-annotation-takes-struct-first-word.md`); a closure parameter on an earlier fn's `*Q` slot copies instead of D33's refusal (`2026-10-18-closure-parameter-keeps-an-earlier-fns-slot-type.md`). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 receives lane (unit R3, after the D27 bite) with
`build/cycc` built from that tree (x86_64); the frontend shapes are target-independent.
**Placement:** 6.7.15 — repair 5 (receives lane, wave 3, unit R3; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D32 — (a) refused by name.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D33 — (a) refused by name.
**Severity:** Medium — the `*T` row is a silent wrong pointer (SIGSEGV at its first dereference, no warning); the
untyped row a silent first word, as D27's typed rows were.
**Discovered:** 2026-10-17, the receives lane, D27 (issues/2026-10-16-struct-call-result-assigned-to-scalar-keeps-
first-word.md). D27 (a) (the user, 2026-10-16) refuses a struct result over 8 B assigned to a destination whose
DECLARATION D24 refuses: an annotation naming no struct and no pointer (`: i64`, `: u8`, `: f64`, `: cstring`, an
enum, `u128`). Two destination classes are outside that decided surface and keep the first word.

## Reproduction

A `*T` destination of a scalar `T` (the assignment twin of D14, `var p: *i64 = mkp();`, refused since 6.7.13):

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn main(): i64 {
    var p: *i64 = 0;
    p = mkp();
    return *p;
}
syscall(60, main());
```

```
rc 0, no diagnostic (not even "assigning non-pointer to typed pointer"); the binary SIGSEGVs (exit 139):
p holds 333, the struct's first word, as an address
```

The declaration of the same line is refused:

```
var p: *i64 = mkp();  -> error:<source>:5:19: cannot initialise 'p: *i64' from 'mkp', which returns the struct 'Q' - declare 'p: Q' and take `&p`
```

An UNTYPED destination (no annotation for D24 to judge; its declaration `var x = mkp();` infers the struct):

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn main(): i64 {
    var x = 0;
    x = mkp();
    return x;
}
syscall(60, main());
```

```
rc 0, no diagnostic; exit 77 (333, the first word) — an untyped global (`var GW = 0;`, `GW = mkp();`) the same,
and a destructure binding typed by its callee (`var q, a = two();` with `two(): (f64, f64)`, then `a = mkp();`)
```

## Root cause

`_asa_refuse` (src/frontend/parse.cyr, 6.7.14's D27) judges the destination's DECLARATION annotation with D24's
predicate (`_asa_scalar`: an integer, a float, an 8-byte handle, `u128`); a `*T` annotation (its token `*`) and a
binding with no annotation give it nothing to judge, and the plain store keeps rax. A `*S` destination of a struct
`S` is a copy operand already (6.7.10 B7-1c: the struct is copied through it) and is not this.

## The questions (the user's)

1. Does D14 (a by-value struct over 8 B into a `*T` is refused by name) reach the assignment — `p = mkp();` into a
   `*i64` / `*u8` local, parameter or global refused with D14's words ("... - declare 'p: Q' and take `&p`")?
2. An untyped variable may hold a number or a pointer (ADR-002): is `x = mkp();` into one refused by name (D24's
   words, "cannot assign 'x' from 'mkp' ..."), or does it keep the first word, documented?
