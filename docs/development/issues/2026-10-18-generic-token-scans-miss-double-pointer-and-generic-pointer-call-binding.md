# The stub scan's token binding misses a `pp: **T` argument (6.7.14's D40) and a generic `: *T` call through `p: *T`: `var r = gd2(&GPP); r.pick(t)` in a generic is refused naming the stub method — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 generics lane (unit G4) on the lane's tree at 5bf321ca5
(after the token-scans fix, issues/2026-10-16-generic-token-scans-miss-d8-pointer-binding.md), x86_64; the same before.
**Placement:** unplaced — filed from the 6.7.15 generics lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Discovered:** 2026-10-18, 6.7.15 generics G4, implementing the token-scans fix (`_tok_ta_arg`, src/frontend/parse.cyr):
its filed surface is D8's `p: *T` / `x: T`; two bindings the parser makes are still unread by the scan.
**Severity:** Low — a loud refusal of valid source; workaround: spell the type argument (`gd2<P>(&GPP)`,
`gd<P>(gpi(&GP0))`).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P { n; }
struct Q { a; b; }
impl P { fn pick<V>(self, w: V): i64 { return w.b; } }
var GP0 = P { 1 };
var GPP: *P = &GP0;
fn gd2<T>(pp: **T): T { var t: T = **pp; return t; }
fn o<T>(t: T): i64 { var r = gd2(&GPP); return r.pick(t); }
fn m(): i64 { var q = Q { 3, 4 }; return o(q); }
syscall(60, m());
```

```
rc 1
error:<source>:8:54: generic 'P_pick' has no i64 (or other scalar) instance: it uses its type parameter as a struct (a
'.field' on a T-typed value, directly or in a generic it forwards T to) — pass a struct argument, or name a struct type
argument
expected: exit 4 (the parser binds gd2's T to P through `pp: **T`, 6.7.14's D40 A)
```

The generic `: *T` call, the same program with these two lines in place of `gd2` / `o`:

```cyrius
fn gpi<T>(x: *T): *T { return x; }
fn gd<T>(x: *T): T { var t: T = *x; return t; }
fn o<T>(t: T): i64 { var r = gd(gpi(&GP0)); return r.pick(t); }
```

```
rc 1
error:<source>:8:58: generic 'P_pick' has no i64 (or other scalar) instance: ... (the same text)
expected: exit 4 (the parser binds through `gpi`'s instance's `: *P`, `_ic_call_rs`)
```

## Root cause

`_tok_gen_tp_sid` (src/frontend/parse.cyr): a T carried by no `x: T` / `p: *T` parameter goes to `_tok_gen_sc_sid`,
the struct-carrier reader, which answers 0 when no struct carries T — the parser's next rung, the first `pp: **T`
parameter (`_gen_infer_ind` -> `_pp_tparam` / `_ic_pp_arg`, parse_types.cyr), has no token twin. And `_tok_ta_call`
reads a `: *S` return of a fn that is not generic only; a generic `: *T` callee binds at the instance the call reaches
(`_ic_call_rs`), which the token pass does not instantiate — it would read the callee's own `T` through
`_tok_gen_tp_sid` recursively, as `_tok_sc_call` does for a carrier.
