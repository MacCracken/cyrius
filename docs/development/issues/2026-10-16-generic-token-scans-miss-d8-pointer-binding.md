# The token-level generic binding (`_tok_gen_tp_sid`) does not follow D8's pointer rule: `var r = gd(&G); r.pick(t)` in a generic is refused naming the stub method — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 generics lane (unit G5) on the lane's tree after the D8 (a)
commit (`4e039c6e`), x86_64. On the slot-open compiler the inferred row was refused too, differently ("no struct type
in scope for 'r'", twice: `gd(&GP0)` ran the i64 base).
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-16, 6.7.14 generics G5, implementing D8 (a)
(issues/2026-10-14-generic-pointer-parameter-binds-only-from-pointer-local-decision.md): the parser now binds
`gd(&GP0)`'s T to P, but the scans that type a declaration from its tokens still bind a pointer argument as before.
**Severity:** Low — a loud refusal of valid source; workaround: spell the type argument (`gd<P>(&GP0)`).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P { n; }
struct Q { a; b; }
impl P { fn pick<V>(self, w: V): i64 { return w.b; } }
var GP0 = P { 1 };
fn gd<T>(x: *T): T { var t: T = *x; return t; }
fn o<T>(t: T): i64 { var r = gd(&GP0); return r.pick(t); }
fn o2<T>(t: T): i64 { var r = gd<P>(&GP0); return r.pick(t); }
fn m(): i64 { var q = Q { 3, 4 }; return o(q) * 10 + o2(q); }
syscall(60, m());
```

```
actual:   rc 1
          error:<source>:7:53: generic 'P_pick' has no i64 (or other scalar) instance: it uses its type parameter as a
          struct (a '.field' on a T-typed value, directly or in a generic it forwards T to) — pass a struct argument, or
          name a struct type argument
expected: exit 44 (o and o2 each read q.b = 4)
```

Control: with `o` removed (`return o2(q);`) the program exits 4 — the explicit spelling's receiver is typed P by the
scan (`_tok_gen_tp_sid`'s `<` arm), so `o2` is a stub and `o2(q)` calls `o2$Q`.

## Root cause

The stub scan types `r.pick(t)`'s receiver from the tokens (`_gs_recv_sid` -> `_tok_name_sid` -> `_tok_decl_sid` ->
`_tok_init_sid` -> `_tok_gen_ret_sid` -> `_tok_gen_tp_sid`, src/frontend/parse.cyr). For an inferred call that last
step reads the carrying argument as a NAME (`_tok_name_sid`) or a whole call only: `&GP0` answers 0, so `r` is untyped
there, the forward of T into the stub method `P_pick` is not seen, `o`'s base is not a stub, and its i64 parse meets
`P_pick`'s scalar refusal. The parser binds through `p: *T` since D8 (a) (`_ic_arg`, parse_fn.cyr): `&G` / `&l`, a
`*S` local, global or field chain, a `: *S` call. The same scan answers 0 for a `var p: *S` local (`_tok_decl_sid`
skips the `*` only for a parameter) and S for a `pp: *S` parameter through `x: T` (where the parser binds i64 —
a false answer, since 6.6.10). The pair scans (`_tok_init_sid` for `?` above a wrapper) and the declaration-zone
judgement (`_gz_call_rs`) read the same helper.
