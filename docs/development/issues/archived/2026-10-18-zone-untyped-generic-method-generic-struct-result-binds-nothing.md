# A declaration-zone untyped `var y = b.mkg(P);` / `b.mkg<i32>(33)` — a GENERIC method returning a generic struct's instance (`fn mkg<T>(self, v: T): G1<T>`) — binds nothing (`y.v.a` is "no struct type in scope for 'y'"), where after the first statement it binds the instance — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ZN-7, `7965f3685`. No decision was needed (6.7.15's D34 (a)). The zone's reader reads `.m<..>(` as an operand and as a chain step. `_gu_minst` resolves a generic method's type arguments as the member arm binds them (an explicit list as `_meth_xinst` reads it, otherwise `_mcall_infer` with `self` at parameter 0), then reads the instance's `: G<..>` return. The filed m1 `var y = b.mkg(P);` and m2 `var x = b.mkg<i32>(33);` each exit 33 in the zone, as after the first statement; each was "no struct type in scope". This holds on x86_64, aarch64, cx and PE. `self: V`, an f64, a struct carrier, a nested list and a `*B1` receiver bind. A refused list gives its one error. An explicit generic method returning a plain struct binds too, untyped and annotated. At this commit a generic operator fn's result is its base; the s16 lane's SZ4 changes the operator under D85 (a) in 6.7.16. Rows: `struct_receive_inference_checked.sh` GZM1 (m1 verbatim), GZM2 (m2) and GZM3 – GZM12 on the four legs, and `struct_receive_paren_call.tcyr` TM6 – TM9 / TN*. Mutations N71 – N77. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 receives lane (unit R4) while landing
issues/archived/2026-10-17-top-level-untyped-method-operator-or-known-callee-struct-result-keeps-word.md (6.7.15's D34) and
issues/archived/2026-10-17-zone-untyped-generic-struct-instance-call-binds-nothing.md (a zone FREE generic call's instance).
The zone sweep types a method result from its tokens (`_gu_wsid` -> `_gz_ty`), which name a generic method's BASE
fn and so the generic struct's base; the replay's call reaches the instance (`G1$Pt`), so typing the base would be a
disagreement `_gz_agree` refuses ("the declaration zone misread ... please report it", measured with the guard
removed). R4 leaves a generic method's (or operator's) generic-struct result untyped in the zone (`_gz_mfi` /
`GFTP`), as before; resolving its instance at the end of pass 1 (`_gu_gen`'s reading, for a method) is outside both
filed surfaces. Measured on the lane after R4 (14cc28034's tree, x86_64); the frontend is shared, so every target.
**Placement:** 6.7.16 — Break 2, repair 6 (zone lane, wave 2, unit Z2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — valid code refused (no miscompile); the same line after the first statement works.
**Kind:** bug (the zone and after-the-first-statement typings disagree).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
struct Pt { a; }
struct B1 { a; }
impl B1 { fn mkg<T>(self, v: T): G1<T> { var g: G1<T>; g.v = v; return g; } }
var b = B1 { 1 };
var P = Pt { 33 };
var y = b.mkg(P);
syscall(60, y.v.a);
```

```
error:<source>:9:16: no struct type in scope for 'y'; a '.field' access needs its struct declaration (missing include?)
```

With `var Z0 = 0; Z0 = 1;` after `var P = ...` it builds and exits 33. The explicit spelling `var x =
b.mkg<i32>(33);` in the zone is refused the same way (`x.v`: "no struct type in scope for 'x'"; `_gz_chain` reads no
`.m<..>(` step), and after the first statement exits 33.

## Root cause

`_gu_wsid` (src/frontend/parse_decl.cyr) declines a generic struct's base when the fn that produced it — the last
method step or the operator fn `_gz_ty` read (`_gz_mfi`) — is generic, because `_gz_chain`'s method arm reads the
base method's return (`GFRS` of `_meth_fn_at`), not the instance the call's arguments bind. The fix would resolve the
method's type arguments from the tokens (the receiver's struct, an explicit `<..>` list, the carrying arguments) and
read the instance's return with `_gtype_sid`, as `_gu_gen` / `_gu_inst` do for a free generic call.
