# An ANNOTATED zone global from a generic method's generic struct result — `var G: G1<Pt> = b.mkg(P);` — is refused "the declaration zone misread whether the initializer of 'G' is a struct value - please report it" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-31, `a051a9768` (with SS-30 `d83d10e9c`, a zone operator's instance marker, met) — no decision needed (valid source refused). The filing's first fix: `_gz_chain`'s method arm sets `_gz_gb` for a generic method's `: G<..>` return (`_gz_mgb`), as `_gz_call_rs` does for a free call. The filed repro exits 33 (it was refused "the declaration zone misread whether the initializer of 'G' is a struct value"), and the explicit `var G: G1<i32> = b.mkg<i32>(33);` 33, on x86_64, aarch64, cx and PE. Rows: `struct_receive_inference_checked.sh` GZM13 (the repro verbatim, zone and after) – GZM21, GOP1 / GOP2; `crossos/struct_receive_paren_call.tcyr` TM10 / TM11 / TN10 / TN11 (green on ecb, ach, pi and cass). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone, unit Z2, x86_64; the frontend is
shared), and identical on the lane base (f8139264f's compiler).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; s16 lane, wave 4, unit SZ2) — never 7.x.
**Severity:** Low — valid code refused, loudly (no miscompile: `_gz_agree` catches the disagreement).
**Kind:** bug (the zone and after-the-first-statement verdicts disagree).
**Discovered:** by unit Z2 while landing issues/archived/2026-10-18-zone-untyped-generic-method-generic-struct-result-binds-nothing.md,
whose surface is the UNTYPED declaration (`var y = b.mkg(P);`, now the instance). The annotated twin is a different
reader: the handle-line walk's `_gz_sval`.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
struct Pt { a; }
struct B1 { a; }
impl B1 { fn mkg<T>(self, v: T): G1<T> { var g: G1<T>; g.v = v; return g; } }
var b = B1 { 1 };
var P = Pt { 33 };
var G: G1<Pt> = b.mkg(P);
syscall(60, G.v.a);
```

```
error:<source>:8:17: the declaration zone misread whether the initializer of 'G' is a struct value - please report it (declared after the first statement, it is read right)
```

With `var Z0 = 0; Z0 = 1;` before `var G` it builds and exits 33. The explicit `var G: G1<i32> = b.mkg<i32>(33);` is
refused the same way (6.7.16's Z2 reads the `.m<..>(` step; before it, the reader took the `<` for a comparison and
the verdict was the same handle).

## Root cause

`_gz_sval` accepts a call result that is an instance of the declared generic struct only through `_gz_gb`, which
`_gz_call_rs` sets for a FREE generic call returning `: G<..>` (6.7.15); `_gz_chain`'s method arm clears it, so a
generic method's base return `G1` is compared with the declared `G1$Pt`, judged no struct value, and the global made a
handle — while the replay's parse records the struct value (`_hl_sval`) and `_gz_agree` refuses the disagreement. A fix
sets `_gz_gb` for a generic method step returning `: G<..>` (as `_gz_call_rs` does), or compares the method's instance
(Z2's `_gu_minst`).
