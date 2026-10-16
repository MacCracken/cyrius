# `bs(n + &x)` with a narrow `n` into a by-value struct parameter of 8 B or less passes the SUM as the struct, where `bs(&x + n)` passes the struct it points at — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.13 structs lane (`l6713-structs` after 74f3100e) and on its
base (aa54fbec): identical — x86_64 78, aarch64 (qemu) 78, PE (wine) 78, cx (cxvm) 14 (another address); 77 is right.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (structs lane; filed from the 6.7.13 structs lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Medium — compiles clean with no diagnostic; the callee reads the address arithmetic's bits as its
fields. Not a security id (the developer's own source).
**Discovered:** 2026-10-15, the 6.7.13 structs lane (unit S2). The deref-of-address-of brief listed
"parse_decl.cyr:8257" (`_hl_rcarry`) among the sites to route through the new `_hl_dpsid`; it is no dereference
consumer — it is `_hl_p1`'s right-carry for a by-value argument — so it was left alone, and this is what it misses.

## Reproduction

```cyrius
struct B8 { v; }
fn bs(b: B8): i64 { return b.v; }
var X[2];
fn go(): i64 {
    store64(&X, 5);
    store64(&X + 8, 7);
    var n: i32 = 8;
    return bs(&X + n) * 10 + bs(n + &X);
}
syscall(60, go());
```

```
$ build/cycc < nx.cyr > nx && ./nx; echo $?
78                     # bs(&X + n) = 7 (the struct at X + 8); bs(n + &X) = 8 (the address X + 8, page-aligned, read as b.v)
```

With an untyped `m` (`var m = 8;`) `bs(m + &X)` is 7, as `bs(&X + n)` is.

## Root cause

6.7.10 decision 7 passes "a typed pointer or an address by the compiler's own pointer typing" into a by-value
struct of 8 B or less as the struct it points at (`_hl_byval_arg` -> `_hl_parg`). `&X` has step 1, so `_hl_parg`
asks `_hl_p1` (parse_decl.cyr), which walks to the last `+` and asks `_hl_rcarry` whether its RIGHT operand is a
`*T` struct pointer — by `_hl_psid`, which answers 0 for `&x` — and otherwise judges the LEFT side, where a narrow
local (`n: i32`) makes the whole a value. 6.7.11 (the user's decision of 2026-10-13, guide § Pointers) says "`&x`,
a byte address, on either side of `+`: `n + &x` is the pointer `&x + n` is" — the declaration and the difference
follow it; the by-value argument does not.

## Proposed fix

`_hl_rcarry` answers 1 for a right operand that is exactly `& IDENT` (any name `&` takes the address of), as for a
`*T` struct pointer — or `_hl_p1` treats `&` like `pb`. It changes what `bs(n + &x)` computes (to the struct, as
6.7.11's rule reads), so the user may want to confirm the reading. Rows: `bs(n + &X)` / `bs(n + &s)` with n i8 /
i16 / i32 / u8 locals and parameters, a right operand `o + (n + &s)`, top level; `bs(n + 5)` stays a value.
