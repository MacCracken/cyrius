# A non-tuple word passed to a tuple parameter — `take(5)`, `take(one(3))`, `take(g2(3))` with `g2` declared `: i64` — is dereferenced as the tuple's address (a crash, no diagnostic), where the same value into a tuple variable is refused — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.13 multivalue lane (l6713-multivalue at ade43caa, the
review-fix step) and on the lane base b13d3598: identical, every case crashing on x86_64 / aarch64 (qemu) / cx
(cxvm) / PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R5; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Medium — compiles clean and crashes at run time (x86_64 / aarch64 SIGSEGV 139, cx guest error 1, PE
access violation 5), or reads memory through a small integer.
**Kind:** language — a decision for the user: whether an untyped word may pass as a tuple's address. The source says
it may today (the R17 header in src/frontend/parse_fn.cyr: "`g(f() + 1)` is an integer, which the struct rule passes
as an address as it does any untyped value"), while the tuple VARIABLE refuses the same values.
**Discovered:** 2026-10-15, the 6.7.13 multivalue lane's review (probes review/rev/g/c.cyr, e.cyr, i.cyr), beside
6.7.13's R17 fix (issues/archived/2026-10-14-undeclared-multi-value-call-into-tuple-parameter-crashes.md).

## Reproduction

Each program alone; every one compiles with no diagnostic:

```cyrius
fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }
fn f(): i64 { return take(5); }
syscall(60, f());
```

```cyrius
fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }
fn one(a): i64 { return a; }
fn f(): i64 { return take(one(3)); }
syscall(60, f());
```

```cyrius
fn g2(a): i64 { return (a, a + 1); }
fn take(t: (i64, i64)): i64 { return t.0 * 10 + t.1; }
fn f(): i64 { return take(g2(3)); }
syscall(60, f());
```

| program | x86_64 | aarch64 (qemu) | cx (cxvm) | PE (wine) |
|---|---|---|---|---|
| `take(5)` | 139 | 139 | 1 | 5 |
| `take(one(3))` | 139 | 139 | 1 | 5 |
| `take(g2(3))` (`g2` declared `: i64`, two values — D23 B keeps it) | 139 | 139 | 1 | 5 |

The same values into a tuple VARIABLE are refused by name (lane and base):

```cyrius
fn one(a): i64 { return a; }
fn f(): i64 { var t: (i64, i64) = 3; return t.0; }
syscall(60, f());
```

```
error:<source>:2:22: cannot initialize tuple 't' with a value that is not a tuple
```

(`var t: (i64, i64) = one(1);` — the same text.)

## Root cause

A tuple parameter takes the tuple's ADDRESS. The argument push checks only R17 (`_tup_arg_call` / `_tup_arg_mrc`,
src/frontend/parse_fn.cyr): a WHOLE call to a multi-value callee (`_mv_callee` — declared `: (T1, T2)` or undeclared
and counted by pass 1) is refused "bind it first". Everything else is pushed as an untyped word, which the callee
dereferences as the tuple: an integer literal, a one-value call, and — since `_mv_callee` excludes a scalar-declared
callee (`GFRS != 0`) — a `: i64` fn that returns two values (the shape D23 B keeps), whose first value is pushed as the
address. The tuple variable's initializer has no such pass: `_tup_cap_check` / the R12 value rule refuse a non-tuple.

## Options (the user's call)

- A: a tuple parameter takes a tuple — a tuple variable, a tuple field, a tuple literal where accepted, or a call
  declared to return that tuple — and anything else is refused by name, as the tuple variable refuses it ("cannot
  pass ... to tuple parameter ..."). Code that compiles today stops compiling (every case crashes today, but an
  untyped pointer passed deliberately as a tuple's address would also be refused).
- B: refuse only what cannot be an address — an integer literal, a call whose declared or counted return is a scalar
  value or several values (the D23 B shape) — and keep an untyped name / expression passing as the address (the
  struct rule's today).
- C: leave it: an untyped word is the tuple's address; the guide states it.
