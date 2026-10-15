# A pointer passed to a by-value struct parameter of 8 B or less is the struct's VALUE — the callee reads the address as its fields — RESOLVED

> ✅ **RESOLVED in v6.7.10** (B7-1b: a `*T` / `&s` argument into a by-value struct parameter of 8 B or less passes the struct it points at, at every size (the user's decision, 2026-10-12). The repro gives 111. Rows: `struct_arg_type_refused.sh` B1–B5, `crossos/small_struct_pointer_arg.tcyr`. The untyped-pointer edges it leaves are filed (issues/archived/2026-10-12-pointer-into-small-byvalue-param-untyped-edges.md). CHANGELOG [6.7.10])

**Status:** ✅ **RESOLVED in v6.7.10** (see the banner). Was: 🟡 **OPEN** — found 2026-10-11 while fixing
[`2026-10-10-pointer-into-byvalue-generic-carrier-runs-base.md`](2026-10-10-pointer-into-byvalue-generic-carrier-runs-base.md)
(6.7.9, the critical lane's bite 11) and reproduced on that lane's tip with the tree's compiler and its aarch64 / cx
cross compilers, and with the installed 6.6.0, 6.6.4, 6.6.5, 6.6.10, 6.6.20, 6.7.2, 6.7.3 and 6.7.7 compilers. Not
fixed there: either fix (refuse the argument, or copy the struct through the pointer) changes what compiles or what a
program computes, which the 6.7.9 decisions do not cover.
**Placement:** 6.7.10 — B7's bite 1b (roadmap.md § *6.7.10*): decided 2026-10-12 — a `*T` / `&s` argument into a by-value struct parameter copies the struct it points to, at every size (the user, at B7's planning: it ships before the layout change shrinks structs into the broken case). Moved from 6.7.11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9's by-value generic carrier fix: `gw(wp)` with `fn gw<T>(w: W1<T>)` and
`wp: *W1<i32>` now calls `gw$i32` as `gw<i32>(wp)` does, and both read the pointer's bits as `w.v`.
**Severity:** High — a silent wrong value on source that compiles clean, every target measured.
**Affects:** cycc 6.6.0 – 6.7.9 (x86_64, aarch64 under qemu, cx); the 6.7.3 struct-argument check accepts it.

## Summary

A struct parameter over 8 B is address-passed, so a pointer to the struct (`&p`, a `u: *P` name) is the right
argument for it — and 6.7.3's struct-argument check accepts both ("a typed POINTER of another struct converts freely",
the user's decision of 2026-10-08; `&p` has no static struct). A struct of 8 B or less is passed BY VALUE, in a
register: the same pointer argument is passed as the struct's value, so the callee reads the address as its first
field. Nothing is reported. The receive path does the opposite for the same pointer: `var c: S1 = sp;` copies the
struct through it.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct S1 { u; }
struct S4 { a: i32; }
fn bs1(b: S1): i64 { return b.u; }
fn bs4(b: S4): i64 { return b.a; }
fn go(): i64 {
    var s: S1; s.u = 5;
    var t: S4; t.a = 6;
    var sp: *S1 = &s;
    var tp: *S4 = &t;
    var r = 0;
    if (bs1(sp) == 5) { r = r + 1; }      # a `*S1` local into `b: S1` (8 B, passed by value)
    if (bs4(tp) == 6) { r = r + 10; }     # a `*S4` local into `b: S4` (4 B)
    if (bs1(&s) == 5) { r = r + 100; }    # `&s` into `b: S1`
    return r;
}
syscall(60, go());
```

```
expected: exit 111 (each call reads the struct the pointer points at), or a refusal by name
actual:   exit 0 on x86_64, aarch64 (qemu) and cx (cxvm) — each callee reads the address's low bits
control:  `var c: S1 = sp; bs1(c)` reads 5 (the receive path copies through the typed pointer)
```

## Root cause

`_sarg_byval_small` (`src/frontend/parse_fn.cyr:1783`) parses the argument, asks `_sarg_type_err` — which accepts a
typed pointer and `&p` (6.7.3) — and pushes the expression's value (`EPUSHR`); a pointer's value is its address. The
6.7.3 acceptance of typed pointers and `&p` was decided with address-passed parameters in view: rows R4a / R4b / R13b
of `tests/gates/frontend/struct_arg_type_refused.sh` pass a `*Pt` into `b: *Q` and into the 24 B `b: Q`, and no row
covers a by-value parameter of 8 B or less.

## Proposed fix

The user's call: (a) refuse a pointer (`&p`, a typed `*T` name / field / call) passed to a by-value struct parameter of
8 B or less, by name, as a struct of another type is; or (b) load the struct through the pointer, as the receive path
does. Either way rows in `struct_arg_type_refused.sh` (a `*S1` local, `&s`, a `*S1` parameter, a call returning one; a
generic instance `gw<i32>(wp)`) and a crossos row for (b).

## Consumer-side workaround

Pass the struct, not its address: `bs1(s)`, or `var c: S1 = sp; bs1(c)`.
