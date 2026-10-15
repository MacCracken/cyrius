# A generic that reads its struct parameter's `T` field as a struct (`b.v.y`, `b: Box<T>`) does not compile, called or not — RESOLVED

> ✅ **RESOLVED in v6.7.11** (GF-4: the stub scan follows a struct carrier's field — `x.f.g` is a struct use of T when x is a parameter or a `var x` typed `[*]G<.., T, ..>` and G declares `f` with its own type parameter in T's slot, G read from its tokens even when declared below. The filed repro exits 44, inferred and explicit (it failed `expected ';', got '.'`), on x86_64, CYRIUS_IR=3, aarch64, cx and PE; `gy(bi)` / `gy<i32>(bi)` with `bi: Box<i32>` are refused naming gy; the uncalled definition compiles; a `*Box<T>` carrier is followed. Deeper chains (`o.inner.v.y`) stay out of scope, the issue's own option, with the `var t: T = o.inner.v;` workaround documented and pinned. No decision. Rows: `frontend/generic_type_arg_unknown_refused.sh` CF1-CF6, `crossos/generic_struct_inference.tcyr` G12 (every fork). CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-10 against 6.7.8 (the checked-`dyn` lane at bite D3) with the tree's
compiler and its aarch64 / cx / PE cross compilers: `error:<source>:8:38: expected ';', got '.'` on every target.
The installed 6.7.4 and 6.7.7 compilers report the same.
**Placement:** 6.7.11 — Break 2, repair 1, the generics / call-path lane (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-11 — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane's bite D3 (generic inference through a generic struct
parameter), probing a generic whose body uses the inferred `T` through the carrier.
**Severity:** Low — a loud compile error on valid source, with a one-line workaround (below); nothing miscompiles.
**Affects:** cycc 6.7.4 – 6.7.8 measured (the shape predates them: the stub scan has never followed a struct field).

## Summary

`fn gy<T>(b: Box<T>): i64 { return b.v.y; }` uses `T` as a struct — `b.v` is the `T`-typed field of `Box<T>` — so,
like `fn g<T>(p: T) { .. p.y .. }`, it has no i64 instance. But the 6.6.10 stub scan (`_gs_scan` mode 0,
`_gs_use`, src/frontend/parse_fn.cyr) marks a base as the dead stub only when a `T`-typed NAME (a parameter or a
`var x: T` local) is followed by `.field`. `b` is a `Box<T>`, not a `T`, so the base is not a stub: pass 2 parses
the BASE body with `T = i64`, where `b.v` is an i64 and `.y` is a syntax error. The definition alone fails — the
program does not build whether `gy` is called, called as `gy<Pt>(b)`, or (since 6.7.8) as `gy(b)` with `T`
inferred through `Box<T>`.

The workaround compiles and is right on every path: bind the field to a `T`-typed local first —
`fn gy<T>(b: Box<T>): i64 { var t: T = b.v; return t.y; }` (the local makes the base the stub, so a scalar call is
refused by name and `gy(b)` / `gy<Pt>(b)` instantiate `gy$Pt`: the repro then exits 44).

## Reproduction

`docs/development/issues/repros/2026-10-10-generic-base-reads-carrier-field-as-struct.cyr`:

```sh
cat docs/development/issues/repros/2026-10-10-generic-base-reads-carrier-field-as-struct.cyr | build/cycc > /tmp/gy
# actual:   error:<source>:8:38: expected ';', got '.'
# expected: compiles; /tmp/gy exits 44 (gy$Pt reads b.v.y = 4, through inference and explicitly)
sed 's/return b.v.y;/var t: T = b.v; return t.y;/' docs/development/issues/repros/2026-10-10-generic-base-reads-carrier-field-as-struct.cyr \
    | build/cycc > /tmp/gyw && chmod +x /tmp/gyw && /tmp/gyw; echo $?    # 44 (the workaround)
```

## Root cause

- `_gs_use` (mode 0) answers "is this `x.f` a struct use of `T`" by `_gsn_has(x)` — the names collected by
  `_gs_params` / `_gs_var` are those whose type token IS a type parameter (`p: T`, `p: *T`, `var x: T`).
- A struct carrier (`b: Box<T>`, recorded since 6.7.8 by `_gs_carrier` for inference) is never one of them, and the
  scan has no notion of a FIELD's type: `b.v.y` is `b`, `.`, `v`, `.`, `y`, and `b` is not `T`-typed.

## Proposed fix

In the stub scan, treat `x.f.g` as a struct use of `T` when `x` is a struct-carrier name (a parameter or a
`var x: G<..>` local whose generic struct G names `T` as a whole type argument) and G's field `f` is declared with
G's own type parameter in `T`'s slot (read from G's definition tokens, `GSDS`). Deeper chains (`x.f.g.h` through a
nested generic) follow the same rule one level at a time, or stay out of scope with the workaround documented. Rows:
the repro (inferred and explicit), a scalar binding refused by name as a stub (`gy(bi)` / `gy<i32>(bi)` with
`bi: Box<i32>`), an uncalled definition compiling, and a `*Box<T>` carrier (`b.v.y` through the pointer).
