# A generic's `ppp: ***T` called with no `<..>` runs the i64 base: `**ppp + 1` steps 8 and `take(***ppp)` faults, where `t3<P3>(ppps)` is right — DECISION — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 vectors lane (unit V5) on its tree after the D40 bite
(3a122cb2b) and on the lane's base compiler (3478087aa's build/cycc): identical.
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D24 — A: yes, at any depth of 2 or more.
**Severity:** Low — a silent wrong step and a fault, but only through a three-star generic parameter with no other
carrier of T; the explicit `t3<P3>(..)` is the workaround.
**Kind:** language question — D40 (A, the user, 2026-10-16) decided `pp: **T` binds T from a `**S` argument
(issues/archived/2026-10-16-generic-double-pointer-parameter-pointee-unbound.md); whether `***T` (and deeper) carries T the same
way is beyond that filing's surface. The guide (§ Generic Functions, "Through a pointer-to-pointer parameter") says a
`***S` binds nothing.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn s3<T>(ppp: ***T): i64 { var a = **ppp + 1; var b = **ppp; return a - b; }
fn main(): i64 { var s: P3; var ps: *P3 = &s; var pps: **P3 = &ps; var ppps: ***P3 = &pps; return s3(ppps) * 10 + s3<P3>(ppps) / 24; }
syscall(60, main());
```

```
x86_64 81, x86_64 CYRIUS_IR=3 81, aarch64 (qemu) 81, cx 81, PE (wine) 81      (8 * 10 + 1; 241 if s3(ppps) bound P3)
```

```cyrius
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn t3<T>(ppp: ***T): i64 { return take(***ppp); }
fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; var ppps: ***P3 = &pps; return t3(ppps); }
syscall(60, main());
```

```
x86_64 139, IR=3 139, aarch64 139, cx 254, PE 5          `t3<P3>(ppps)`: 42 on every leg
```

## Root cause

`_gen_infer_ind` (src/frontend/parse_types.cyr, 6.7.14) consults the first parameter declared exactly `**T`
(`_pp_is_tp`: three tokens `* * T`); a `***T` parameter carries nothing, so T infers i64 and the call reaches the i64
base, where `**ppp` is a `*i64` (step 8) and `***ppp` an i64 word passed as the address.

## Fix direction (if the answer is "yes, as `**T`")

Accept `* .. * T` of any depth >= 2 in `_pp_is_tp` and follow the argument's pin chain one level per extra star
(`_pp_tab`'s pointee word carries its own pin: `_ps_pin(L64(_pp_tab + pin * 16))`) before `_pp_sid`. Rows beside
tests/tcyr/crossos/double_pointer_deref_step.tcyr's GI group.
