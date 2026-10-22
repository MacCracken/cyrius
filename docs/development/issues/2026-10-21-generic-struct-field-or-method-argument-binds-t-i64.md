# A generic call's `x: T` argument that is a struct-typed FIELD or a struct-returning METHOD call binds `T = i64`: `sizeof(T)` is 8 for a 16-byte struct, and `.b` on the value is refused — OPEN

**Status:** 🟡 **OPEN** — binding the struct changes what a valid program computes (`sizeof(T)`, the instance called);
the s16 lane stopped on it (its unit SZ2's blocked B2).
**Placement:** 6.7.17 — the cleanup of the remaining issues (genr lane, wave 1, unit GA3; placed at the 6.7.17 open, 2026-10-22 — the user: "cleanup the remaining issues") — never 7.x.
**Decision (user, 2026-10-22, at the 6.7.17 open — "go with Recommended"):** D2 — Yes, as a struct local or a free call does.
**Discovered:** the s16 lane, unit SZ2.
**Severity:** Medium — a silent value: `sizeof(T)` reads 8 for a 16-byte struct argument, the i64 instance runs.
**Kind:** decision.

## Summary

The guide's binding rule: a struct argument — "a struct local or by-value struct parameter, a struct global, a call
returning a struct" — binds `T` to that struct, and "only a WHOLE argument binds `T`: `g(p.y)`, `g(p.x + p.y)` and
`g(p + 1)` infer `i64`". A FIELD whose own type is a struct (`w.p`, `p: P2`) and a METHOD call declared to return a struct
(`b.mp2()`) are whole struct values, but both bind `i64`; the same value through a local binds the struct.

## Reproduction

Measured 2026-10-21 at the 6.7.16 close on the merged compiler (main `4a3c510f3`; `build/cycc` 2,822,280 B) on x86_64,
aarch64 (qemu-aarch64), cx (cxvm) and PE (wine 11.20): the same.

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
struct P2 { a; b; }
struct W { p: P2; n; }
struct B { k; }
impl B { fn mp2(self): P2 { var q: P2; q.a = 1; q.b = 2; return q; } }
fn sz<T>(v: T): i64 { return sizeof(T); }
fn pr(x): i64 { fmt_int(x); syscall(SYS_WRITE, 1, " ", 1); return 0; }
fn main(): i64 { var w: W; w.p.a = 1; w.p.b = 2; var b = B { 0 }; var q = b.mp2(); pr(sz(w.p)); pr(sz(b.mp2())); pr(sz(q)); return 0; }
syscall(60, main());
```

Prints `8 8 16`: `sz(w.p)` and `sz(b.mp2())` run the i64 instance; `sz(q)` (the method's result through a local) the
P2 instance.

```cyrius
include "lib/syscalls.cyr"
struct P2 { a; b; }
struct W { p: P2; n; }
fn rdb<T>(v: T): i64 { return v.b; }
fn main(): i64 { var w: W; w.p.a = 1; w.p.b = 2; return rdb(w.p); }
syscall(60, main());
```

```
error:<source>:5:61: generic 'rdb' has no i64 (or other scalar) instance: it uses its type parameter as a struct (a '.field' on a T-typed value, `&x` of one returned as a struct, or a struct result over 8 bytes stored in one — directly or in a generic it forwards T to) — pass a struct argument, or name a struct type argument
  note: <source>:4:31: 'rdb' takes a field of a value typed by its type parameter
```

The lane also measured `mkg1(b.mp())` binding `G1<i64>`.

## The decision

- (a) A struct-typed field and a method call declared to return a struct bind `T` to that struct, as a struct local or a
  free call does: `sz(w.p)` and `sz(b.mp2())` return 16, `rdb(w.p)` returns 2, `mkg1(b.mp())` is `G1<P>`. Programs that
  compile today compute differently (the instance they call changes), and `rdb(w.p)` newly compiles.
- (b) Keep: the guide gains that a field and a method result bind `i64` (pass a local, or name the type argument).

## Acceptance

With (a): the two repros give 16 16 16 and 2 on x86_64, aarch64, cx and PE, through every call path the guide lists (an
expression, a declaration, an assignment, a field store, a `return`, an argument, a struct receive), a nested field
(`w.v.p`), a field through a pointer (`pw.p`), a chain's method; a scalar field (`g(p.y)`) still binds `i64`.
