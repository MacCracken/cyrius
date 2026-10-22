# A top-level `var G: S = *GPP;` (GPP a `**S`) binds G to the struct as a handle, where the same declaration in a fn copies since 6.7.15 — OPEN (decision) — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ZN-11, `cb004c8c8` + `cbb267ab3`, under the user's decision D17 (a), and ZN-12, `62ba267ac`, under D18 (a), both 2026-10-19: G is a copy, at every size, for both questions. A top-level `var G: S = *GPP;` (and `(*GPP)`, `*gpp()`, `*W.pp`) and `var G: S = P;` (P a `*S` global, `(P)` too) copy the struct at every size, in the declaration zone and after the first statement, as in a fn. The filed repro prints `0464646` and exits 9 on x86_64, IR=1, IR=3, DCE, aarch64, cx and PE. It printed `0999996293824` on x86_64; Z / T now read 4, Z8 / T8 6, N 4 and N8 6. Newly refused, beyond the decisions' text: a `**Q`'s `*GQQ` into an S global (it read Q's bytes), and over 8 B a `**S` / `*S` source global declared below G (it faulted at startup). ⚠ At 8 B or less, a `*S8` name declared below G now faults at startup, where it read 0. That is filed as 2026-10-20-small-struct-global-from-pointer-global-declared-below-faults-at-startup.md (the s16 lane's SZ3). The guide's "⚠ Not yet settled" line is gone. Rows: `double_pointer_struct_value.tcyr` d_* (12) and n_* (11) on the four legs; `small_struct_handle_line.sh` R17 (the filed repro verbatim on seven legs), GC9 and GC10; `struct_copy_type_checked.sh` R35 / R36. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S2), landing
issues/archived/2026-10-17-whole-source-copy-from-double-pointer-single-deref-stores-pointer-word.md. That fix makes `*pp` of a
`**S` a `*S` copied through as the WHOLE source of a copy — `l = *pp`, `G = *pp` (in a fn and at top level), `*q =
*pp`, and the declaration `var t: S = *pp;` IN A FN, as its `*S`-name twin `var t: S = p;` copies. A declaration of a
GLOBAL from `*GPP` — in the declaration zone or after the first statement, at 8 B and over — was left as it was: a
handle on the struct. Not the filing's surface (its repro and table are a fn's declaration), and its `*S`-name twin at
top level is itself the guide's unsettled rule, so this needs the user's decision, not a fix.
**Placement:** 6.7.16 — Break 2, repair 6 (zone lane, wave 2, unit Z4; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D17 — (a) G is a copy, at every size.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D18 — (a) G is a copy, at every size.
**Severity:** Low — consistent with every other top-level declaration from a `*S`-typed source (`gp()`, `GW.p`,
`GP + 0` all bind a handle at top level, the handle line); the difference is only against the same spelling in a fn.
No miscompile in the handle's own terms.
**Kind:** decision — joins the guide's "⚠ Not yet settled: a global declared from a `*T` GLOBAL's name (`var G: S8 =
P;`) keeps its 6.7.9 layout — inline, holding the pointer word, at 8 bytes or less; a handle bound to `P`'s object over
8" (src/frontend/parse_decl.cyr `_gz_pname`). No issue file carries that decision today.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fmt.cyr"
struct P { x; y; }
struct P8 { v; }
var GS = P { 3, 4 };
var GP: *P = &GS;
var GPP: **P = &GP;
var GS8 = P8 { 6 };
var GP8: *P8 = &GS8;
var GPP8: **P8 = &GP8;
var Z: P = *GPP;          # the declaration zone
var Z8: P8 = *GPP8;
fmt_int(0);
var T: P = *GPP;          # after the first statement
var T8: P8 = (*GPP8);
var N: P = GP;            # the `*S`-name twin (unsettled at top level)
var N8: P8 = GP8;
GS.y = 9;
GS8.v = 9;
fmt_int(Z.y); fmt_int(Z8.v); fmt_int(T.y); fmt_int(T8.v); fmt_int(N.y); fmt_int(N8.v);
fn main(): i64 { var t: P = *GPP; GS.y = 5; return t.y; }
syscall(60, main());
```

```
$ build/cycc < tl.cyr > tl && ./tl; echo " exit=$?"
0999996293824 exit=9
```

Z, Z8, T, T8 read 9 after `GS.y = 9` / `GS8.v = 9` (handles on GS / GS8; a copy reads 4 / 6); N is a handle too and
N8 holds the pointer word (6293824) — the unsettled 6.7.9 layout; the fn's `var t: P = *GPP;` copies (exit 9: GS.y
was 9 when copied, the later `GS.y = 5` is not seen; the lane base exits 5 — a handle).

## The question

Should a top-level declaration from `*GPP` copy the struct, as the same declaration in a fn does since 6.7.15?
- (a) Copy, at every size, in the declaration zone and after it => `Z.y` / `T.y` read 4, `Z8.v` / `T8.v` 6; the
  global is inline (pass 1 registers it as for `*GP`, `_gz_star`). Decide it together with the `var G: S8 = P;` rule
  so the `*S`-name twin agrees.
- (b) Keep the handle (the top-level handle line for a `*S`-typed source) => unchanged; the guide says so (it does
  since 6.7.15, in the `**pp` paragraph).
