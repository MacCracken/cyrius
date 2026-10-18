# Decision: a redeclared struct / tuple literal keeps declaration order, while 6.7.15's D2 (a) makes every scalar constant redeclaration the value from program start — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend at 6593fbf1d) on x86_64,
aarch64 (qemu) and cx (cxvm), against the slot-open compiler (b2e1f4c48) on the same three.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 frontend review, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — a silent value difference between two spellings of "a constant redeclaration"; no crash.
**Kind:** language — whether 6.7.15's D2 (a) ("every constant redeclaration is the value from program start") and
6.7.14's D11 (b) (a constant initializer leaves no startup store) cover a struct or tuple literal redeclaration is the
user's call.
**Discovered:** by the frontend lane's review (2026-10-18), checking issues/2026-10-16-zone-struct-literal-baked-and-stored.md
(the lane's 8981d679b) beside issues/2026-10-17-named-constant-redeclaration-ordered-unlike-a-literal.md (c31338f42,
D2 (a)). The lane's handoff flagged the same-bytes case for the user (unit F5, item 1).

## What differs

1. **Order.** A scalar constant redeclaration reads the later constant everywhere (D2 (a); a literal pair already did
   through 6.7.14). A struct or tuple literal redeclaration of other bytes keeps declaration order: a read between the
   two sees the earlier literal. The issue that filed the struct literal's stores (F5) pinned
   `var p = P{1,2}; var b = p.a; var p = P{3,4};` to `b == 1` before D2 was decided, and the lane kept it.
2. **A call's write (value change in this lane).** 8981d679b drops a baked literal's startup stores under D11 (b), by
   extension from a scalar constant. As a result a call in an earlier initializer that writes the global keeps its
   write — also between two declarations of the SAME literal — where through 6.7.14 the literal's startup store
   overwrote it. This matches the scalar literal analog (d5 below, 9 on both compilers). The guide's § Global
   Initializers ("So does a struct or tuple literal of constants (6.7.15)") documents both behaviours as the lane built
   them.

## Reproduction

```sh
cd <the tree>
# d1: one zone, a tuple redeclaration beside a scalar one
printf 'var t = (1, 2);\nvar b = t.0;\nvar t = (3, 4);\nvar a = 1;\nvar c = a;\nvar a = 2;\nsyscall(60, b * 10 + c);\n' > d1.cyr
# d2: a struct literal redeclaration (the F5 ordering control)
printf 'struct P { a; b; }\nvar p = P { 1, 2 };\nvar b = p.a;\nvar p = P { 3, 4 };\nsyscall(60, b);\n' > d2.cyr
# d3: an earlier initializer's call writes the global, one literal declaration
printf 'struct P { a; b; }\nfn setp(): i64 { p.a = 9; return 0; }\nvar r = setp();\nvar p = P { 1, 2 };\nsyscall(60, p.a);\n' > d3.cyr
# d4: the same-bytes pair with the call between
printf 'struct P { a; b; }\nvar p = P { 1, 2 };\nfn setp(): i64 { p.a = 9; return 0; }\nvar r = setp();\nvar p = P { 1, 2 };\nsyscall(60, p.a);\n' > d4.cyr
# d5: the scalar analog of d4
printf 'var a = 1;\nfn seta(): i64 { a = 9; return 0; }\nvar r = seta();\nvar a = 1;\nsyscall(60, a);\n' > d5.cyr
for f in d1 d2 d3 d4 d5; do build/cycc < $f.cyr > /tmp/$f && chmod +x /tmp/$f && /tmp/$f; echo "$f $?"; done
```

| row | lane (x86_64 / aarch64 / cx) | slot-open b2e1f4c48 (x86_64 / aarch64 / cx) |
|---|---|---|
| d1 | 12 (b = 1: the earlier tuple; c = 2: the later scalar) | 12 |
| d2 | 1 (declaration order) | 1 |
| d3 | 9 (setp's write kept) | 1 |
| d4 | 9 (setp's write kept) | 1 |
| d5 | 9 | 9 |

d1 also warns once (`duplicate symbol 'a' redefined with conflicting value`), on both compilers.

## Root cause

A struct / tuple literal is baked per declaration (`_spc_try`, src/frontend/parse_decl.cyr); 8981d679b's `_gvs_quiet`
drops a bk-2 entry's stores only when no earlier live writer exists and no later entry may bake other bytes
(`_gvs_later` / `_gvs_lw`), or when the nearest earlier writer is a baked literal of the same bytes (`_gvk_prev` with
`want` 2, `_gvs_same`). A later literal of other bytes is not made to supersede the earlier entries as an integer
constant does (`_gvk_chain` / `_gvk_ik`), so the earlier literal's stores run in order.

## Options (the user's call)

(a) D2 (a) / D11 (b) cover struct and tuple literals: a redeclared literal of constants is the value from program start
— d1 32 (b = 3, c = 2), d2 3, d3 9, d4 9 — an earlier literal leaves no store, as a scalar constant.
(b) Keep the lane's behaviour (d1 12, d2 1, d3 9, d4 9), as the guide now documents.
(c) Keep declaration order AND the same-bytes case's store (d4 back to 1: `_gvs_same` returning 0, the lane's
mutation M3), d3 stays 9.
Rows: d1-d5 on x86_64, aarch64, cx and PE; the guide's § Global Initializers and § Declaring a global twice say which.
