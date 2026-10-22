# A zone generic call whose type-argument list `_targs_resolvable` passes but the parse refuses (`mkg1<*Pt>(33)`) is parsed at the end of pass 1: its refusal is printed before an earlier line's error — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-29, `5074c7383` — no decision needed. The filing's fix direction: the sweep's `_gu_xlist` reads names, commas and nested `<..>` only (`_gu_xnames`) and parses quietly (`_gu_xq`: the latch held, `_bnd_quiet`), answering "refused" when a report was swallowed, so the replay's call reports it once, in order. The filed repro prints 5:13 then 6:14 (it printed 6:14 first) on x86_64, aarch64, cx and PE; `<1>`, `<[i64]>` behind a name, a nested `Pt<i32>`, a nested failing bound, a method's `.m<..>(` and a carrying argument's call the same. Rows: `struct_receive_inference_checked.sh` GZO0 (the repro verbatim) – GZO10; mutations N84 RED 10 ×4, N85 RED GZO10 ×4. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone, unit Z2, x86_64; the frontend is
shared, so every target), and identical on the lane base (f8139264f's compiler): pre-existing since 6.7.15's `_gu_gen`.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; s16 lane, wave 4, unit SZ2) — never 7.x.
**Severity:** Low — a refused program's diagnostics out of source order (one error, not two); nothing that compiles changes.
**Kind:** bug (diagnostic order).
**Discovered:** by unit Z2 while landing issues/archived/2026-10-18-zone-generic-instance-refused-type-argument-or-negated-literal-unbound.md
(`mkg1<*u8>(33)`): `*u8` fails `_targs_resolvable` (`u8` is no type-argument name), so the sweep never parses it, but
`*Pt` passes it (`_targs_resolvable` checks names and `( { ; EOF` only, never a `*`, a number or a `[`), so the sweep's
`_gu_xlist` (6.7.15's `_gu_gen` explicit arm, moved unchanged) runs `_parse_one_type_arg` over it at the end of pass 1,
which prints the refusal then — before every replayed line's error. Not this unit's filed surface.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
struct Pt { a; }
fn mkg1<T>(v: T): G1<T> { var g: G1<T>; g.v = v; return g; }
var e = nope;
var x = mkg1<*Pt>(33);
syscall(60, x.v);
```

```
error:<source>:6:14: a type argument is a type name, got '*'
error:<source>:5:13: undefined variable 'nope' (missing include or enum?)
```

Line 6's error is printed before line 5's. With `mkg1<*u8>(33)` (or after the first statement) the order is the
source's. The same holds for any list the parse refuses while every name in it resolves (`<1>`, `<[u8]>` behind a
name, a non-generic `Pt<i32>` nested, and a nested bounded struct whose bound fails).

## Root cause

`_gu_xlist` (src/frontend/parse_decl.cyr) guards the parse with `_targs_resolvable` alone, which is the lookahead
guard `_gen_resolve_call` uses but does not mean "the parse reports nothing". A fix reads the list quietly at the sweep
— a token test like Z2's `_gu_xnames` (names, `,`, nested `<..>` only) before parsing, and a quiet `_parse_one_type_arg`
(or `_bnd_quiet` around it) for the nested refusals — answering "refused" (G, as `_gu_hdl` does for `*u8`) otherwise.
