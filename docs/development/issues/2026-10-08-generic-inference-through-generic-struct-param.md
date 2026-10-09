# Generic inference does not see through a generic struct parameter (`gx(b)` for `b: Box<T>`) — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the tree's `build/cycc`: the repro below is refused at `gx(b)`; the explicit `gx<Pt>(b)` control compiles and exits 8. `_gs_param` still records only a bare `name: T` / `name: *T` parameter as T's carrier.
**Placement:** 6.7.8 — features: checked dyn + C2 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** before 2026-10-08 (carried in roadmap.md's backlog; the refusal is gate row R18b, added in 6.7.3); filed 2026-10-08 from roadmap.md.
**Severity:** Low — a refusal with a documented workaround (`gx<Pt>(b)`), but the message blames a struct mismatch when the real gap is inference.
**Affects:** cycc ≤ 6.7.6 (before 6.7.3 the call compiled and ran the i64 base, reading `b.n` at the wrong offset; since 6.7.3 it is refused).

## Summary

For `fn gx<T>(b: Box<T>)`, a call `gx(b)` with `b: Box<Pt>` does not infer `T = Pt`. T has no carrying
parameter, so inference returns i64 and the call resolves to the base `gx` (`b: Box`). Since 6.7.3
the struct-argument check then refuses it as a struct mismatch. `gx<Pt>(b)` works. The guide documents
the limitation (`docs/guides/cyrius-guide.md:1108-1110`: "does not infer `T` through `Box<T>` … write
`gx<Pt>(b)`").

## Reproduction

`docs/development/issues/repros/2026-10-08-generic-inference-through-generic-struct-param.cyr`:

```sh
cat docs/development/issues/repros/2026-10-08-generic-inference-through-generic-struct-param.cyr | build/cycc > /tmp/gi
# actual:   error:<source>:12:15: cannot pass 'b' to a parameter of a different struct type in a call to 'gx'
# expected: compiles; ./gi exits 8 (the gx$Pt instance)
sed 's/gx(b)/gx<Pt>(b)/' docs/development/issues/repros/2026-10-08-generic-inference-through-generic-struct-param.cyr | build/cycc > /tmp/gie
chmod +x /tmp/gie; /tmp/gie; echo $?    # 8 (control)
```

## Root cause

- `src/frontend/parse_fn.cyr:8300` `_gs_param`: pass 1 records parameter `pc` as T's carrier (GFGM bits
  8–23) only when its type token IS the type parameter (`b: T`, `b: *T`). For `b: Box<T>` the type token
  is `Box`, so nothing is recorded.
- `src/frontend/parse_fn.cyr:8518` `_gen_infer_tp`: with the record present (`m & 4`) and no carrier
  (`k == 0`) it returns `-8` (i64). `_gen_call_head` (8551) and `_gen_resolve_call` (8590) then keep the
  base fi.
- The struct-argument check refuses the `Box<Pt>` local passed to the base's `b: Box` (gate row R18b,
  `tests/gates/frontend/struct_arg_type_refused.sh:256`).

## Proposed fix

1. In `_gs_param`, also record a parameter whose type is a generic struct instance naming the type
   parameter (`Box<T>`, `*Box<T>`): the carrier plus which type-argument slot of the struct holds T.
2. In `_gen_infer_tp`, for such a carrier, infer the argument's struct id (an instance, e.g. `Box$Pt`)
   and map it back to the instance's type argument (Pt). Only a whole argument binds, as today
   (`_gen_arg_whole`).
3. R18b flips from a refusal row to an acceptance row (exit 8, control `gx<Pt>(b)`); the guide sentence
   at 1108–1110 is rewritten.

This only makes a refused program compile; nothing that compiles today changes. It is listed as a
Break 2 candidate, so the user decides whether it ships.
