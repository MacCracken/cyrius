# A 16 B struct if-expression branch refusal cascades "no struct type in scope" at the variable's `.field` use (`var G = if (c) { B2 } else { B2 }; G.a`) — top level and in a fn — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-24, `90ea8f76e`, and SS-28, `f365b4bf5` (with SS-25 `7095ac7e4`, an uninitialized zone vector global's double error, met) — no decision needed. The filing's fix direction: the declared variable of an if-expression whose branch is refused as over 8 bytes is marked refused (`_ie_decl_mark` → `_ann_refd_mark`), and the zone sweep marks such a global (`_gu_iebig` / `_gu_bwide`; SS-28 makes that read instance nothing). Both filed repros print the two branch refusals alone (the third line, "no struct type in scope for 'G'" / 'g', is gone), in a fn, the zone, after the first statement and in a fn body compiled before the replay, for a 16 B struct, a u128 and a vector, on x86_64, aarch64, cx and PE. Rows: `struct_receive_inference_checked.sh` TI3 (now "no cascade"), TI12 – TI20; mutations N82, N83. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone at aa0d05620, x86_64; the shared
front end, every target); pre-existing — b73e8d5fe's build/cycc prints the same third line (its branch refusals said
"a vector, u128 or slice value", which the lane's D16 (a) commit b2f75e9fd made name the struct).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone review, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; s16 lane, wave 4, unit SZ1) — never 7.x.
**Severity:** Low — the program is refused (rc 1) with the branch refusals first; one invented error follows the one
mistake.
**Kind:** bug (diagnostic cascade).
**Discovered:** by the 6.7.16 zone lane's review of issues/2026-10-18-top-level-untyped-if-expression-struct-result-
binds-nothing.md (D16 (a)), whose gate row struct_receive_inference_checked.sh TI3 pins the 16 B form's cascade "as in
a fn" — the brief's surface. The cascade itself is outside that filing.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P2 { a; b; }
var B2 = P2 { 33, 4 };
var G = if (1 == 1) { B2 } else { B2 };
syscall(60, G.a);
```

```
error:<source>:4:23: an if expression branch cannot be a struct value over 8 bytes: struct 'P2' - branch on a pointer (`&x`, or a `*T` value)
error:<source>:4:35: an if expression branch cannot be a struct value over 8 bytes: struct 'P2' - branch on a pointer (`&x`, or a `*T` value)
error:<source>:5:16: no struct type in scope for 'G'; a '.field' access needs its struct declaration (missing include?)
```

rc 1. After a first statement the same (7:16), and in a fn:

```cyrius
include "lib/syscalls.cyr"
struct P2 { a; b; }
var B2 = P2 { 33, 4 };
fn f(): i64 { var g = if (1 == 1) { B2 } else { B2 }; return g.a; }
syscall(60, f());
```

```
error:<source>:4:37: an if expression branch cannot be a struct value over 8 bytes: struct 'P2' - ...
error:<source>:4:49: an if expression branch cannot be a struct value over 8 bytes: struct 'P2' - ...
error:<source>:4:65: no struct type in scope for 'g'; a '.field' access needs its struct declaration (missing include?)
```

## Root cause

The branch refusal (the if-expression's wide-branch check) leaves the declared variable untyped (sid 0) and unmarked,
so its `.field` use reaches the `sid == 0` reporter (src/frontend/parse_decl.cyr, `no struct type in scope for`).
6.7.15's stand-down for a variable whose ANNOTATION named a refused type (`_ann_refd_mark` / `_ann_refd_said`,
src/frontend/parse_fn_def.cyr, asked by `_fld_sid0_said`) has no counterpart for a variable whose INITIALIZER was
refused.

## Fix direction

Mark the declared variable as refused (`_ann_refd_mark`, or a twin for an initializer) when its if-expression
initializer's branch is refused — in a fn and at top level (the zone's `_gu_ie` and the after-statement record) — so
`G.a` / `g.a` stand down, counted, not printed. Rows: the two repros give the two branch refusals alone (zone, after a
statement, a fn) on x86_64 / aarch64 / cx / PE; TI3's third-line check in struct_receive_inference_checked.sh moves to
"no cascade".
