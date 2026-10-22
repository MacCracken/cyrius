# Struct and pointer shapes beyond D97 / D99 take a word or another struct's bytes in silence: a pointer of another struct or another depth at a call or a declaration, and a struct value stored through an untyped pointer, into a `*Q` slot, into a scalar field or element, by a compound assignment, or into a `*P` declaration — OPEN

**Status:** 🟡 **OPEN** — each row compiles with rc 0 and no diagnostic and computes a wrong value or crashes; refusing
(or defining) each changes what compiles or computes beyond the decided answers, so the s16 and f16 lanes stopped on
them (the user, 2026-10-21: no new decision round).
**Placement:** unplaced — filed at the 6.7.16 close (2026-10-21); the user places it — never 7.x.
**Discovered:** the s16 lane — unit SZ5 (rows A1, A2, B1 – B3; its Blocked list beside D97 / D99), unit SS2 (row A3), the
s16 review's file_as_issue (row B4; staged as 2026-10-21-struct-result-into-scalar-field-or-array-element-keeps-first-word.md);
the f16 lane, unit FF4 (row B5; the f16 review's file_as_issue, staged as
2026-10-21-pointer-declaration-from-inline-struct-local-binds-first-word-sigsegv.md).
**Severity:** High — silent wrong values and crashes from source the compiler accepts with no diagnostic (rows A2's
second shape and B5 SIGSEGV on every target).
**Kind:** decision (one per row: refuse it as its decided siblings are, or define what it computes).

## Summary

6.7.16 decided two of these shapes: D97 refuses a pointer to another struct passed to a `*S` parameter ("cannot pass 'y'
to a parameter of a different struct type"), and D99 refuses a struct result over 8 B stored through a typed pointer to a
scalar (`*p = mkp();` with `p: *i64`, and the subscript `p[i] = mkp();`). Their neighbours are in no decision: a pointer
meeting a BY-VALUE parameter, a pointer of another DEPTH, and a struct VALUE meeting a word slot the decided readers do
not look at. Each takes a word, or another struct's bytes, silently.

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B) on x86_64,
aarch64 (qemu-aarch64), cx (cxvm) and PE (wine 11.20), each compiler built from that tree; every program compiles rc 0
with no diagnostic. Where four targets agree, one value is given.

### A — a pointer of another struct, or of another depth

**A1. A typed pointer to another struct into a BY-VALUE struct parameter copies that struct's bytes:**

```cyrius
struct Pt { x; y; }
struct Q { a; b; }
fn bq(b: Q): i64 { return b.a * 10 + b.b; }
fn main(): i64 { var p = Pt { 3, 4 }; var u: *Pt = &p; return bq(u) + bq(&p); }
syscall(60, main());
```

Exit **68** on all four (34 + 34: Pt's bytes read as a Q). `bq(p)` is refused ("cannot pass 'p' to a parameter of a different struct
type in a call to 'bq'"), and so is `u` into a `*Q` parameter (D97). struct_arg_type_refused.sh R4b accepts the pointer
form today, on 6.7.3's "a typed pointer converts freely" (2026-10-08).

**A2. A pointer of another depth at a call:**

```cyrius
struct Pt { x; y; }
fn nc4(p: *Pt): i64 { return p.x; }
fn main(): i64 { var p = Pt { 3, 4 }; var pq: *Pt = &p; if (nc4(&pq) == &p) { return 1; } return 2; }
syscall(60, main());
```

Exit **1** on all four: the callee reads pq's slot (a `**Pt`) as the Pt, so `p.x` is p's address. The other way:

```cyrius
struct Box<T> { v: T; n; }
fn nc2(pp: **Box<i64>): i64 { var p: *Box<i64> = *pp; return p.v; }
fn main(): i64 { var b: Box<i64>; b.v = 5; b.n = 6; var pz: *Box<i64> = &b; if (nc2(pz) == 5) { return 5; } return 2; }
syscall(60, main());
```

A crash on every target: x86_64 139, aarch64 SIGSEGV (139), cx "guest address out of range: 5", PE an access violation
(exit 5) — the struct is read as a pointer. `nc2(&pz)` exits 5.

**A3. A pointer of another depth into a struct declaration:**

```cyrius
struct P3 { x; y; z; }
fn main(): i64 { var s: P3; s.x = 7; s.y = 8; s.z = 9; var ps: *P3 = &s; var pp: **P3 = &ps; var g: P3 = pp; if (g.x == &s) { return 1; } if (g.x == 7) { return 7; } return 2; }
syscall(60, main());
```

Exit **1** on all four: 24 bytes are copied through the `*P3` slot (g.x is s's address, 16 bytes read past the slot).
The top-level `var G: P3 = GPP;` (GPP a `**P3` global) the same, 1 on all four. `var g: P3 = *pp;` gives 7.

### B — a struct value where a word is stored

Common: `struct Q { a; b; }` and `fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }` (a 16-byte result).

**B1. Through an UNTYPED pointer:**

```cyrius
fn main(): i64 { var x = 0; var p = &x; *p = mkp(); return x; }
```

Exit **77** (333 mod 256: Q's first word) on all four. Through `var p: *i64 = &x;` it is refused (D99): "cannot assign
'*p: i64' from 'mkp', which returns the struct 'Q' - store it through a '*Q' or bind a field".

**B2. Into a `*Q` slot reached through a dereference or a field — the pointer is rebound, q is unchanged:**

```cyrius
fn main(): i64 { var q = Q { 1, 1 }; var pq: *Q = &q; var ppq: **Q = &pq; *ppq = mkp(); if (pq == &q) { return q.a * 10 + q.b; } return 113; }
```

Exit **113** on all four; `*ppq = r;` (r a `Q` local) and `w.pq = r;` (`struct W { pq: *Q; n; }`) the same. The name's own
assignment copies through the pointer: `pq = r;` exits 34 (6.7.10's decision 6), and `GPQ = r` copies. (Not D99's shape:
the slot's pointee IS the value's struct.)

**B3. A compound assignment adds the first word:**

```cyrius
fn mk3(): Q { var q: Q; q.a = 3; q.b = 4; return q; }
fn main(): i64 { var x = 10; var p: *i64 = &x; *p += mk3(); var y = 100; y += mk3(); return x + y; }
```

Exit **116** (13 + 103) on all four. D27 / D33 / D99 judge `=` only.

**B4. Into a scalar FIELD or an array ELEMENT:**

```cyrius
struct W { n; pi: *i64; }
fn g(): i64 { var w = W { 1, 0 }; w.n = mkp(); return w.n; }
```

Exit **77** on all four; `var buf: i64[2]; buf[0] = mkp(); return buf[0];` exits 77; a global's field and a global
array's element (`GW.n = mkp(); GB[1] = mkp(); return GW.n + GB[1];`) exit 154 (666 mod 256). The siblings are decided
and refused: a declaration (`var y: i64 = mkp();`, 6.7.11's D24), a name's assignment (6.7.14's D27 / D33), a `*T`
assignment (6.7.15's D32), and since D99 a store through a pointer (`*p`, `p[0]`, `w.pi[0]`).

**B5. A `*P` declaration from an inline struct local binds its first word:**

```cyrius
include "lib/syscalls.cyr"
struct P { a; b; }
fn main(): i64 { var s: P; s.a = 7; s.b = 2; var p: *P = s; return p.a; }
syscall(60, main());
```

A crash on every target: x86_64 139, aarch64 SIGSEGV, cx "guest address out of range: 7", PE an access violation (exit
5) — p holds 7. The assignment `p = s;` copies s through p (6.7.11), and `var p: *Str = t;` from an inline `Str` takes
`&t` (6.7.15's D16).

## The decision, row by row

| row | refuse (stops compiling) | or define |
|---|---|---|
| A1 | "cannot pass 'u' to a parameter of a different struct type", as D97 refuses it into a `*Q` (R4b re-derived) | keep 6.7.3's "a typed pointer converts freely" (today) |
| A2 | refuse a pointer of another depth at the argument, both ways | keep (today) |
| A3 | refuse `var g: P3 = pp;` with D17 / D87's "cannot copy" words | copy through the pointer it points at, as `*pp` |
| B1 | refuse as D33 refuses `x = mkp()` into an untyped x / D99's words | keep the first word (today) |
| B2 | refuse | copy through the slot (`*ppq = r` copies into `*pq`, as `pq = r` does), or keep the rebind (today) |
| B3 | refuse the compound forms (`*p += mkp();`, `y += mkp();`) | keep the first word (today) |
| B4 | refuse as D27 / D99 do ("cannot assign 'w.n: i64' from 'mkp', which returns the struct 'Q' - … or bind a field") | keep the first word (today) |
| B5 | refuse by name | take the address (`&s`), as D16 does for `*Str`; or warn |

## Acceptance

Each repro gives the decided result on x86_64, aarch64, cx and PE, at a local, a global, at top level (the zone and after
the first statement) and through a generic's `T` (the D1 stub scan reading the generic twin), with a for step and a
method's / an operator's result where the row applies; the decided siblings (D97, D99, D24, D27, D32, D33) unchanged.

## Root cause (as the lanes measured it)

D97's check reads a `*S` parameter's pointee and D99's a typed pointer's; the by-value parameter check judges struct
values only (a pointer converts, 6.7.3); no reader compares pointer depth; the struct-result checks for `=` key on a
declaration, a name, a `*T` name and a store through a typed pointer, so an untyped pointer, a `*Q` slot behind a
dereference or a field, a compound operator, a scalar field / element and a `*P` declaration from a struct value reach
the plain word store.
