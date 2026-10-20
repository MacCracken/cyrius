# An array-list redeclaration over an untyped float-literal global drops the float's bytes the list does not write — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone at 4bd0d7ae2, unit Z1, x86_64), and
identical on the slot-open compiler (b73e8d5fe's build/cycc).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16") — never 7.x.
**Severity:** Low — a silently different value in a rare shape (an untyped float global redeclared as a bare byte
list); no crash.
**Kind:** bug — the guide's list rule ("over an earlier scalar **constant** it keeps the bytes it does not list") and
its float rule (§ Global Initializers: a float literal is baked "the same way", a constant; 6.7.15's D46 Keep: "a float
literal global behaves as an integer literal global does") together say the float's bytes are kept.
**Discovered:** by unit Z1 while implementing issues/2026-10-18-list-redeclaration-over-named-scalar-constant-loses-
unlisted-bytes.md (a const- / enum-NAMED integer scalar) and issues/2026-10-18-float-literal-global-redeclaration-keeps-
declaration-order.md (D13 (a): a float constant redeclaration is the value from program start). Neither filing's
surface is a LIST over a float constant, so Z1 left it: its list seed (`_gai_seed_ent`) takes integer folds only
(`_gvk_ik` 1), and the float's bits (`_gvk_ik` 2) do not seed.

## Reproduction

```sh
cd <the tree>
printf 'var K = 1.5;\nvar K[1] = {9};\nsyscall(60, (load64(&K) >> 56) & 255);\n' | build/cycc > /tmp/x12 && chmod +x /tmp/x12 && /tmp/x12; echo $?
# 0     (the image holds 0x0000000000000009: 1.5's bytes are gone; no diagnostic)
# the same bits written as an integer literal keep them:
printf 'var K = 0x3FF8000000000000;\nvar K[1] = {9};\nsyscall(60, (load64(&K) >> 56) & 255);\n' | build/cycc > /tmp/x13 && chmod +x /tmp/x13 && /tmp/x13; echo $?
# 63    (0x3FF8000000000009)
# an annotated `var K: f64 = 1.5;` then `var K[1] = {9};` is refused (a type change), so only the untyped spelling reaches this.
```

Added by the zone review's fix (aa0d05620, l6716-zone): over an integer LITERAL the float superseded, the literal's bytes
still read through — the static init seeds (the same on b73e8d5fe's build/cycc):

```sh
printf 'var a = 0x0506;\nvar a = 1.5;\nvar a[1] = {9};\nsyscall(60, (a >> 8) & 255);\n' | build/cycc > /tmp/x14 && chmod +x /tmp/x14 && /tmp/x14; echo $?
# 5     (0x0000000000000509: the superseded literal's 0x05, not 1.5's; without the list `a` is 1.5 — `(a >> 56) & 255` 63)
```

The review fix made a nearer float constant STOP `_gai_seed`'s walk (`_gai_seed_ent` 2 -> the static init), so a
const- or enum-named constant before the float no longer seeds (`var a = C; var a = 1.5; var a[1] = {9};` 0x0009, as
on b73e8d5fe; the lane's first cut gave 0x0509); the static init it returns is this shape's literal.

## Root cause

A float literal does not fold in pass 1 (`_CF_TRY` is integer), so `var K = 1.5;` is a deferred entry; the later list
supersedes it (`_gv_supersede(S, noff, 1)`), `_gvk_one` computes its bits (`_gvk_flt`) but, superseded, does not bake
them (bk 4), and the list's new blob is seeded from the static init (0) — or, since 6.7.16, from the nearest earlier
INTEGER fold (`_gai_seed` / `_gai_seed_ent`, src/frontend/parse_decl.cyr), a float constant stopping the walk at
the static init (since aa0d05620) — so the float's bits never seed, and a pass-1 literal before the float does.

## Proposed fix

`_gai_seed` seeds a float constant's bits (`_gvk_ik` 2, now `_gai_seed_ent`'s 2: the walk's stop) as it does an integer
fold's — `load64(_gvk_v + g * 8)` under the same bit-43 test — instead of the static init: the repro gives 63 on x86_64,
aarch64, cx and PE (a row in tests/tcyr/crossos/global_array_initializer.tcyr and const_init_bake_and_fold.sh's L rows).
Whether an untyped float global may be redeclared as a byte list at all (the annotated form is refused as a type
change) is the alternative question; either answer removes the silent drop.
