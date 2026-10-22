# `*p = mkp();` through a `p: *i64` (and a generic's `p: *T` at a scalar T) keeps the struct's first word in silence, where the sibling stores are refused (D24 / D27 / D32) — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-46, `b86a3cb01`, and the review fix SS-46r, `1fe35ed66` (with SS-47 `a6884ebe9`, the stub scan's struct-result reader, met) — D99 (the user, 2026-10-20: "Refuse it, as its siblings"; in a generic, the issue's option (a), a D1 stub line). `_dsr_sres` judges `*p = <struct result over 8 B>` through a typed pointer to a scalar or a pointer slot; SS-46r the subscript `p[i] = ..` (beyond D99's text). The filed repro is refused once at 6:44, "cannot assign '*p: i64' from 'mkp', which returns the struct 'Q' - store it through a '*Q' or bind a field" (it exited 77); the generic twin's `g(5)` and `g<i32>(5)` are "generic 'g' has no i64 (or other scalar) instance" with the note; `**pp = mkp();` the same; `*p = mk8()` and a `Str` result keep their word, as the acceptance asks; at T = Q it copies. Not changed: `*p = mkp();` through an UNTYPED pointer (reported as the user's call); a scalar field / local array element (staged for a decision). Rows: `struct_result_type_refused.sh` DP0 (the repro verbatim) – DP21, DPK1 – DPK4, TA6 – TA15c, TG23 – TG25c, DS1 – DS11, DSK1 – DSK3, DPX / DSX on aarch64 / cx / PE. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🔴 **OPEN** — found 2026-10-20 by the 6.7.16 genbind review. Measured on the lane head (after the review
fix 710b98b29) and on the lane's base 41ca7d41c: identical.
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 wave-3 genbind lane; placed at the wave-3 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; s16 lane, wave 4, unit SZ5) — never 7.x.
**Decision (user, 2026-10-20, wave 3's round):** D99 — Refuse it, as its siblings (6.7.15's D32 words: a struct result over 8 B cannot be stored through a `*i64`).
**Severity:** Medium. A silent wrong value: a 16-byte struct result is narrowed to its first word.
**Kind:** bug (silent wrong value) — **needs the user's decision** (judging the store stops such programs compiling).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct S8 { v; }
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn g(x: i64): i64 { var p: *i64 = &x; *p = mkp(); return x; }
fn main(): i64 { return g(5); }
syscall(60, main());
```

rc 0, no diagnostic, exit **77** (333 mod 256: Q's first word stored through p).

The sibling stores of the same result are each refused by name: `var y: i64 = mkp();` (6.7.11's D24), `y = mkp();`
into a scalar (6.7.14's D27), `p = mkp();` into a pointer (6.7.15's D32). The store THROUGH a pointer is judged by none.

The generic twin, `fn g<T>(x: T): i64 { var p: *T = &x; *p = mkp(); return 0; }`, compiles at `g(5)` and `g<i32>(5)`
(at 41ca7d41c and again after the review fix 710b98b29, which took the store out of 6.7.16's D1 stub rule — D1 names
`var y: T = E`, `y = E` and `p = E` only); at T = Q it copies the struct (struct_result_type_refused.sh TA6-TA6d).

## Why it is open

Refusing `*p = mkp();` (p a pointer to a scalar) stops such programs compiling, and, for a generic, deciding whether
the deref store is one of D1's stub lines (no scalar instance) changes which of its calls compile — the user's call:
(a) refuse it with D24 / D27's words in a plain fn, and make it a D1 stub line in a generic, or (b) keep the word.

## Acceptance

The verbatim repro and the generic twin give the decided result on x86_64, aarch64, cx and PE; a `*p = mk8();` (a struct
of 8 B or less) and a `Str` result keep their word as D24 does; `**pp = mkp();` the same as `*p`.
