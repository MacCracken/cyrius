# A declaration-zone untyped generic call returning a generic struct's instance binds nothing when its type argument comes from an expression, a struct carrier or a bounded struct: `var x = mkg1(30 + 3);`, `mkc(BX)` (`b: Box<T>`), `mkb(P)` (`struct G1<T: Show>`) — `x.v` is "no struct type in scope for 'x'", where after the first statement each binds — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 receives lane (unit R4) while landing
issues/2026-10-17-zone-untyped-generic-struct-instance-call-binds-nothing.md. That fix reads a zone generic call's
type arguments from the tokens (`_gu_gen` / `_gu_tp`, src/frontend/parse_decl.cyr): an explicit list, and for an
inferred one a struct (`_tok_gen_tp_sid`), a lone integer literal or a lone global; "when the tokens cannot bind T,
keep today's answer" (the brief). The shapes below are the ones it leaves untyped, as before. Measured on the lane
after R4 (14cc28034's tree, x86_64); the frontend is shared, so every target.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 receives lane, wave 3; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — valid code refused (no miscompile); the same line after the first statement works.
**Kind:** bug (the zone and after-the-first-statement typings disagree).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
fn mkg1<T>(v: T): G1<T> { var g: G1<T>; g.v = v; return g; }
var x = mkg1(30 + 3);
syscall(60, x.v);
```

```
error:<source>:5:16: no struct type in scope for 'x'; a '.field' access needs its struct declaration (missing include?)
```

With `var Z0 = 0; Z0 = 1;` before `var x` it exits 33. The same for a struct carrier —
`struct Box<T> { v: T; } fn mkc<T>(b: Box<T>): G1<T> { .. } var BX: Box<i32> = Box<i32> { 33 }; var x = mkc(BX);`
(zone: `7:16: no struct type in scope for 'x'`; after: 33) — and for a bounded generic struct —
`trait Show { fn show(self): i64; } struct G1<T: Show> { v: T; } .. impl Show for Pt { .. } fn mkb<T: Show>(v: T):
G1<T> { .. } var P = Pt { 33 }; var x = mkb(P);` (zone: `9:16: no struct type in scope for 'x'`; after: 33). A return
whose list nests (`: G1<Box<T>>`) is also left untyped (`_gu_plain`), but its call is refused for another reason
today (staged beside this: 2026-10-18-generic-nested-instance-field-of-field-judged-a-stub.md).

## Root cause

`_gu_tp` answers 0 ("not read here") for an argument that is not a struct, an integer literal or a lone global name
(an expression, a call returning a scalar, a float literal, `&x` of a scalar, a captured value), and for a struct
carrier parameter (`pk == 0`); `_gu_inst` declines a G with bounds (`GSBND`: minting it would judge the bound at the
sweep, before the call's own judgement) and a return list that is not plain names. Pass 2's `_gen_infer_tp` binds all
of these (an expression as i64; a carrier through `_gen_infer_ind`). A fix reads the same bindings from the tokens
(or defers the global's typing to a point where the parser's reading is available) and judges a bound once.

