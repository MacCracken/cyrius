# A top-level `var G: S = *GPP;` (GPP a `**S`) binds G to the struct as a handle, where the same declaration in a fn copies since 6.7.15 — OPEN (decision)

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S2), landing
issues/2026-10-17-whole-source-copy-from-double-pointer-single-deref-stores-pointer-word.md. That fix makes `*pp` of a
`**S` a `*S` copied through as the WHOLE source of a copy — `l = *pp`, `G = *pp` (in a fn and at top level), `*q =
*pp`, and the declaration `var t: S = *pp;` IN A FN, as its `*S`-name twin `var t: S = p;` copies. A declaration of a
GLOBAL from `*GPP` — in the declaration zone or after the first statement, at 8 B and over — was left as it was: a
handle on the struct. Not the filing's surface (its repro and table are a fn's declaration), and its `*S`-name twin at
top level is itself the guide's unsettled rule, so this needs the user's decision, not a fix.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
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
