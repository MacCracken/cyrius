# `var a, b = (f(7));` — a destructure whose call is parenthesised — is refused "multi-value destructure needs a call on the right-hand side", where `return (g(x));` and the struct / pair checks see through the same wrap — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.13 multivalue lane (l6713-multivalue, unit M2, after the
paren-wrapped pair fix 5ede634e) and on the lane's base compiler (fe98679b): identical, x86_64, aarch64 (qemu), cx
(cxvm) and PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R6; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D45 — Transparent.
**Severity:** Low — refused loudly; the workaround is to drop the parentheses. No wrong value.
**Kind:** language — a decision for the user. The guide states today's rule (§ Tuples: the right-hand side is "one
whole call — `f(..)`, `g<T>(..)` or `x.m(..)` — and nothing around it"), while every other consumer of a whole call
peels a whole-value wrap: a struct source (6.7.6, "parentheses around a whole struct source are transparent"), a
multi-value call into a named struct (6.7.11, "parentheses around it transparent"), a declared multi-value fn's
`return (g(x));` (6.7.11), and, since 6.7.13 (D19 A), every `: stack` pair check (`(f(7))?`, the lossy stores,
`return (f(x));`).
**Discovered:** 2026-10-15, the 6.7.13 multivalue lane, unit M2, probing the shapes around D19's wrap.

## Reproduction

```cyrius
enum Res: stack { ROk(v); RErr(e); }
fn f(x) { return ROk(x); }
fn two(x): (i64, i64) { return (x, x + 1); }
fn t1(): i64 { var a, b = (f(7)); return a * 10 + b; }
fn t2(): i64 { var c, d = (two(3)); return c * 10 + d; }
syscall(60, t1() + t2());
```

```
error:<source>:4:27: multi-value destructure needs a call on the right-hand side
error:<source>:5:27: multi-value destructure needs a call on the right-hand side
```

on all four targets. Unwrapped (`var a, b = f(7);`, `var c, d = two(3);`) the program exits 41.

## Root cause

`_dt_rhs_check_t` (src/frontend/parse_decl.cyr) takes the destructure's call from `_dt_call_open` at the cursor,
which recognises `name(`, `name<..>(`, `x.m(` and (6.7.13) `callptr(` only; a `(` there is no call. The tuple capture
refuses the same wrap by its own text: `var t: (i64, i64) = (two(3));` is `cannot initialize tuple 't' with a value
that is not a tuple` (unwrapped it captures (3, 4)).

## Options (the user's call)

- A: transparent, as the struct and pair checks are: step `_pwrap_k` parentheses whose close ends the right-hand side
  (`_pair_unwrap` in src/frontend/parse.cyr is the token helper the pair checks share) before `_dt_call_open`, in the
  declaration, the assignment `a, b = (f());`, the classic-for step, both top-level zones — and the tuple capture's
  call arm. Nothing that compiles today changes.
- B: leave it: the destructure keeps its "nothing around it" rule; the guide already says so.
