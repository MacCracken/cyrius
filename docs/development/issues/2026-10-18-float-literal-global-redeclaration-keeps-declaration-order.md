# A float-literal redeclaration of a declaration-zone global keeps declaration order, where an integer constant redeclaration is the value from program start — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend at 50b9a8817, unit F4,
x86_64; the frontend, every target), identical on the lane's previous compiler (79f6ca16d's build/cycc) and so on
the slot-open compiler.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 frontend lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — a read between two declarations of one float global sees the earlier literal, silently; the
guide's rule for redeclarations names integer constants only.
**Kind:** language — whether a float literal redeclaration is "a constant redeclaration" (the value from program
start, as 6.7.15's D2 (a) made every integer one) is the user's call.
**Discovered:** by unit F4 while implementing issues/2026-10-17-named-constant-redeclaration-ordered-unlike-a-literal.md
(the user's decision D2 (a), 2026-10-18: "every constant redeclaration is the value from program start"). That
filing's surface and the decision's examples are integer constants (a literal, `= 0`, a const or enum name); the
float literal, baked since 6.7.14 (`_gvk_flt`), was left in its order.

## Reproduction

```sh
cd <the tree>
# f64 bits: 1.5 = 0x3FF8.., 2.5 = 0x4004..; `(bits >> 48) & 255` is 248 / 4
printf 'var G: f64 = 1.5;\nvar b = load64(&G);\nvar G: f64 = 2.5;\nsyscall(60, (b >> 48) & 255);\n' | build/cycc > /tmp/f1 && chmod +x /tmp/f1 && /tmp/f1; echo $?
# 248   (b read 1.5; no diagnostic)
printf 'var K = 1.5;\nvar b = load64(&K);\nvar K = 2.5;\nsyscall(60, (b >> 48) & 255);\n' | build/cycc > /tmp/f2 && chmod +x /tmp/f2 && /tmp/f2; echo $?
# 248   (untyped, the same)
printf 'var G: f64 = 1.5;\nfn setg(): i64 { G = 0.5; return 1; }\nvar r = setg();\nvar G: f64 = 2.5;\nsyscall(60, (load64(&G) >> 48) & 255);\n' | build/cycc > /tmp/f3 && chmod +x /tmp/f3 && /tmp/f3; echo $?
# 4     (the later literal's store runs after setg: 2.5, not setg's 0.5)
# the integer analog, for comparison:
printf 'var G = 3;\nvar b = G;\nvar G = 5;\nsyscall(60, b);\n' | build/cycc > /tmp/i1 && chmod +x /tmp/i1 && /tmp/i1; echo $?
# warning:<source>:3:7: duplicate symbol 'G' redefined with conflicting value (last definition wins)
# 5     (b reads the later constant: the value from program start)
```

No "redefined with conflicting value" warning is given for the float pair either (the compare is integer-only:
CHKDUPVAL in pass 1, `_gvc_cmp` at the replay).

## Root cause

A float literal does not fold in pass 1 (`_CF_TRY` is integer), so each declaration is a deferred entry. At the replay
`_gvk_one` bakes its bits (`_gvk_flt`, 6.7.14), but 6.7.15's `_gvk_chain` lets only an INTEGER fold (`_gvk_ik`)
supersede the slot's earlier writers (src/frontend/parse_decl.cyr), so `_gvk_quiet` keeps both entries' stores in
declaration order (the nearest earlier writer is a baked entry of another value).

## Proposed fix (after the user's decision)

(a) A float literal redeclaration is the value from program start, as an integer constant's: `_gvk_link` lets a
`_gvk_flt` bake supersede as well (`_gvk_ik` widened to "a constant"), and the conflicting-value compare reads float
bits (a differing pair warns). The rows above: 4, 4, 0.5's bits. Or (b) floats keep declaration order: the guide's
§ Declaring a global twice says so beside the integer rule. Rows: the three repros on x86_64, aarch64, cx and PE.
