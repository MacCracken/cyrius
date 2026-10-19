# A top-level ASSIGNMENT of a call declared to return a vector to a scalar global (`G = mkv(41, 7);`, `G = s.mv();` after the first statement) stores one word, silently, differently per target — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 vectors lane (its review-fix tree, 2e8b3d14f), x86_64 /
x86_64 `CYRIUS_IR=3` / aarch64 (qemu) / cx (cxvm) / PE (wine). Pre-existing: the lane base (8b4d44602's build/cycc)
gives the same on x86_64.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 vectors review, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Medium — compiles with no diagnostic; the global holds a word whose value differs per target, where the
same assignment inside a fn is refused (6.7.15) and the top-level DECLARATION is refused (6.7.15's D26 / D27).
**Discovered:** 2026-10-18, the review of the 6.7.15 vectors lane — outside the filed surfaces of
`issues/2026-10-17-vector-call-or-method-assigned-to-scalar-global-stores-a-word.md` (assignments in a fn) and
`issues/2026-10-17-top-level-untyped-vector-call-or-method-result-binds-a-word.md` (top-level declarations).

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
var G = 0;
syscall(0 - 1, 0);
G = mkv(41, 7);
syscall(60, G % 256);
```

```
row 1 (above)                x86_64 0   IR=3 0   aarch64 0   cx 41   PE 41   (compile rc 0, no diagnostic)
row 2, the method:
    struct S { k; }
    impl S { fn mv(self): f64v2 { return mkv(41, 7); } }
    var G = 0;
    var s: S = S { 1 };
    syscall(0 - 1, 0);
    G = s.mv();
    syscall(60, G % 256);
                             x86_64 0   IR=3 0   aarch64 0   cx 41   PE 41   (compile rc 0, no diagnostic)
```

The same assignment inside a fn is refused on every target (6.7.15, a9fcfbae7):

```
var G = 0;
fn run(): i64 { G = mkv(41, 7); return G; }
error:<source>:3:21: vector return type does not match the assigned variable
```

and the top-level declaration `var w = mkv(41, 7);` / `var x: i64 = mkv(41, 7);` is refused (6.7.15's D26 / D27).

## Root cause

`_try_vector_call_assign` (src/frontend/parse_decl.cyr) begins `if (GINFN(S) != 1) { return 0; }`, so at top level
neither the by-name check nor the 6.7.15 global-destination arm (`_vasg_mscal` / `_vasg_gnv`) runs, and the statement
falls through to the scalar assignment, which stores the call's result register (the first word on x86_64 / aarch64;
cx's and PE's conventions differ). D26 / D27 (`_vin_top`, `_vtop_ref`) cover only a declaration's initialiser.

## Fix direction

Refuse a call declared to return a vector (any spelling `_vcall_vt` recognises) assigned at top level, as the top-level
declaration is — a vector result needs storage in a fn's frame ("'mkv' returns a vector by value .. call it inside a
fn", `_svc_toplevel_at`) — or, into a scalar global, "vector return type does not match the assigned variable", as in a
fn. Which wording is the integrator's / user's call; the destination must not take a word silently either way.
