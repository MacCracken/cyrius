# A zone untyped generic call whose carrying argument is a generic call returning a generic struct's instance — `var x = mkg1(mkg1(P));` — is refused "the declaration zone misread whether the initializer of 'x' is a struct value - please report it" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SS-33, `823b58d77` (with SS-34 `8dc610f8c`, a generic fn's fixed instance return, and SS-36 `0f1f7aea0`, a `.name` past a scalar field, met) — no decision needed (valid source refused). The filing's fix: the sweep reads a carrying argument that is one whole generic call as the instance it makes (`_gu_tpg` / `_gu_cg`), in both readers (`_gu_ircs` → `_gu_icg`; the struct carrier's `_gsc_call` → `_gu_gsc`). The filed repro exits 33 (it was refused "the declaration zone misread ..." and "7:18: expected ')'"); `mkg1(mkg1<i32>(33))`, wrapped, three deep, a second parameter's carrier, `id(mkg1(P))`, annotated and a struct carrier `mkc(mkbx(33))` the same, on x86_64, aarch64, cx and PE. Rows: `struct_receive_inference_checked.sh` GZC1 (the repro verbatim) – GZC13, GZF1 – GZF6; `dx_multi_error.sh` F1 – F14. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone, unit Z2, x86_64; the frontend is
shared), and identical on the lane base (f8139264f's compiler): pre-existing since 6.7.15's `_gu_gen`.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16"; s16 lane, wave 4, unit SZ2) — never 7.x.
**Severity:** Low — valid code refused, loudly (no miscompile: `_gz_agree` catches it).
**Kind:** bug (the zone and after-the-first-statement typings disagree).
**Discovered:** by unit Z2 while landing issues/archived/2026-10-18-zone-untyped-generic-call-instance-argument-shapes-unread.md
(an expression, a call returning a SCALAR, a struct carrier, a bounded G). A carrying call returning a generic
struct's instance is answered first by the pair scans' token reader, not by the classifier Z2 added.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
struct Pt { a; }
fn mkg1<T>(v: T): G1<T> { var g: G1<T>; g.v = v; return g; }
var P = Pt { 33 };
var x = mkg1(mkg1(P));
syscall(60, x.v.v.a);
```

```
error:<source>:6:9: the declaration zone misread whether the initializer of 'x' is a struct value - please report it (declared after the first statement, it is read right)
```

With `var Z0 = 0; Z0 = 1;` before `var x` it builds and exits 33.

## Root cause

`_gu_tp` asks the pair scans' reader first (`_tok_gen_tp_sid` -> `_tok_ta_call` -> `_tok_init_sid`), which types the
inner call `mkg1(P)` by its BASE return `G1` (`GFRS`), not the instance `G1$Pt` the replay's call reaches, so the sweep
mints `G1$G1` for x while the replay's call returns `G1$G1$Pt`. Z2's classifier path (`_gu_ircs`) treats a carrying
generic call returning `: G<..>` as a miss (no fn instance may be made at the sweep); a fix reads the inner call's
instance struct without making it (`_gu_gen` on the inner call: its binding, then `_gu_inst`) in both readers.
