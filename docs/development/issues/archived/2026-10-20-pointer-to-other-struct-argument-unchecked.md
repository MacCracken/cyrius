# A `*Box<i64>` / `**Box<i64>` parameter (and any `*S` parameter) accepts a pointer to ANOTHER struct unchecked: `nc1(&y)` with `y: Box<Pt>` reads Pt's fields at Box<i64>'s offsets — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-43, `1cfdeb9d1` (with SS-44 `c1226966e`, a gate's pipefail abort, met) — D97 (the user, 2026-10-20: "Refuse it at the argument"). `_pa_chk` compares a `*S` / `**S` / `***S` parameter's struct (`_fnt_pps` records the deeper ones) with the argument's, by the compiler's own typing, at every call path and an operator's right operand. The three filed repros are each refused once — "cannot pass 'y' to a parameter of a different struct type in a call to 'nc1'", '... 'q' ... 'nc2'' and '... 'q' ... 'nc4'' (they exited 2) — on x86_64, aarch64, cx and PE; a pointer to the declared struct, an untyped pointer, `alloc()` and `0` still pass, as the acceptance asks. Not changed (reported as the user's call): a pointer of another depth, and a typed pointer into a BY-VALUE struct parameter (6.7.3's rule). Rows: `struct_arg_type_refused.sh` PD1 – PD3 (the repros verbatim), PD4 – PD17, PDK1 – PDK5; `crossos/struct_arg_type_accepted.tcyr` d97_* (green on ecb, ach, pi and cass); re-pinned R4a, R13b, A6, GK2. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🔴 **OPEN** — found 2026-10-20 by the 6.7.16 genbind review (beside
issues/archived/2026-10-18-generic-double-pointer-generic-struct-parameter-infers-nothing.md, bite 00ea63744, which notes it out
of scope). Measured on the lane head and on the lane's base 41ca7d41c: identical.
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 wave-3 genbind lane; placed at the wave-3 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; s16 lane, wave 4, unit SZ5) — never 7.x.
**Decision (user, 2026-10-20, wave 3's round):** D97 — Refuse it at the argument ("cannot pass 'y' to a parameter of a different struct type"; a `Box<Pt>` is not a `Box<i64>`).
**Severity:** Medium. A silent wrong value: the callee reads the argument's bytes at another struct's field offsets.
**Kind:** bug (silent wrong value) — **needs the user's decision** (refusing it stops such programs compiling).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn nc1(p: *Box<i64>): i64 { return p.n; }
fn main(): i64 { var y: Box<Pt>; y.v.x = 1; y.v.y = 2; y.n = 9; return nc1(&y); }
syscall(60, main());
```

rc 0, no diagnostic, exit **2** (`Pt.y`, read as `Box<i64>.n` at offset 8); `y.n` is 9.

The double pointer behaves the same:

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn nc2(pp: **Box<i64>): i64 { var p: *Box<i64> = *pp; return p.n; }
fn main(): i64 { var y: Box<Pt>; y.v.x = 1; y.v.y = 2; y.n = 9; var q: *Box<Pt> = &y; return nc2(&q); }
syscall(60, main());
```

rc 0, exit 2. And the root is not generic-specific — a plain `*Pt` parameter takes a `&q` of a 3-word `Qd` the same way:

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Qd { a; b; c; }
fn nc4(p: *Pt): i64 { return p.y; }
fn main(): i64 { var q: Qd; q.a = 1; q.b = 2; q.c = 3; return nc4(&q); }
syscall(60, main());
```

rc 0, exit 2.

The BY-VALUE mismatch is refused (6.7.3): `fn nc3(p: Box<i64>)` called `nc3(y)` with `y: Box<Pt>` is "cannot pass 'y' to
a parameter of a different struct type in a call to 'nc3'". Behind a pointer nothing compares the pointee.

## Why it is open

Refusing a `*U` argument into a `*S` parameter (and `**U` into `**S`) stops programs compiling that pass a pointer of
one struct where another is declared — today they compile and read at the declared struct's offsets. That is a
language change: the user's call — (a) refuse a pointer to a different struct (by name, as the by-value pass is), or
(b) keep pointers unchecked. A generic instance (`Box<Pt>` vs `Box<i64>`) is a different struct under (a).

## Acceptance

The three repros give the decided result on x86_64, aarch64, cx and PE; under (a), `&y` of the declared struct,
an untyped pointer and `0` still pass.
