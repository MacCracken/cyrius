# An array-list redeclaration over a const- or enum-NAMED scalar constant does not keep the bytes it does not list — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ZN-1, `4bd0d7ae2`, and the ZN-1r review fix `aa0d05620`. No decision was needed: the guide's § Declaring a global twice keeps an earlier scalar constant's unlisted bytes, and since 6.7.15 a const or enum name is a constant. A list's blob is now seeded with the slot's last INTEGER constant before the list (`_gai_seed`), on the replay and on cx's `_gai_cx_blobs` alike. The filed l2 (`const C = 0x0506; var a = C; var a[1] = {9};`) and l3 (an enum name) exit 14, as l1 does; each exited 9. This holds on x86_64, aarch64, cx and PE. `var a = 0x0506; var a = D; var a[1] = {9};` with `D = 0x0708` reads 0x0709; it seeded the stale literal, 0x0509. A computed earlier scalar still seeds nothing (9), and `var a = f(); var a[1] = {0, 4};` reads 0x400. A const between two lists reaches the earlier one (0x0509, was 0x0009). ZN-1r makes a float constant in between stop the walk: `var a = C; var a = 1.5; var a[1] = {9};` reads 0x0009, as before 6.7.16. Whether a float's own bits seed a list is 2026-10-20-list-redeclaration-over-untyped-float-constant-loses-unlisted-bytes.md; the user's D86 (a) decides it, and the s16 lane's SZ3 applies it in 6.7.16. Rows: `const_init_bake_and_fold.sh` L1 – L13 by value on x86_64, aarch64 and cx, and T13 – T16 (`global_array_initializer.tcyr` GRKC – GRKRD, GRKF and GRFK on the four legs, PE under wine). The mutations are recorded in the gate header. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend at 50b9a8817, unit F4,
x86_64; the frontend, every target), identical on the lane's previous compiler (79f6ca16d's build/cycc).
**Placement:** 6.7.16 — Break 2, repair 6 (zone lane, wave 2, unit Z1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a silently different value: the scalar's constant is lost from the bytes the list leaves alone,
where the literal spelling keeps them.
**Kind:** bug (the guide documents the literal behaviour as the rule; the named spelling differs).
**Discovered:** by unit F4 while implementing issues/archived/2026-10-17-named-constant-redeclaration-ordered-unlike-a-literal.md
(the user's decision D2 (a), 2026-10-18). That filing is about a SCALAR redeclaration's order; this is the 6.6.16 list
rule ("over an earlier scalar constant it keeps the bytes it does not list") for a named earlier constant — outside
its surface, and not changed by it.

## Reproduction

```sh
cd <the tree>
printf 'var a = 0x0506;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n' | build/cycc > /tmp/l1 && chmod +x /tmp/l1 && /tmp/l1; echo $?
# 14    (0x0509: the list writes byte 0, byte 1 keeps the scalar's 0x05 — the guide's example)
printf 'const C = 0x0506;\nvar a = C;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n' | build/cycc > /tmp/l2 && chmod +x /tmp/l2 && /tmp/l2; echo $?
# 9     (0x0009: the named constant's bytes are gone; no diagnostic)
printf 'enum E { V = 0x0506; }\nvar a = E.V;\nvar a[1] = {9};\nsyscall(60, (a & 255) + (a >> 8));\n' | build/cycc > /tmp/l3 && chmod +x /tmp/l3 && /tmp/l3; echo $?
# 9     (an enum name, the same)
```

docs/guides/cyrius-guide.md § *Declaring a global twice*: "over an earlier scalar **constant** it keeps the bytes it
does not list (`var a = 0x0506; var a[1] = {9};` reads `0x0509`)".

## Root cause

PARSE_GVAR_ARR (src/frontend/parse_decl.cyr) supersedes the name's earlier non-list entries in pass 1
(`_gv_supersede(S, noff, 1)`). A literal earlier scalar is a static init (`_vgsi_base`), which `_gai_blob` seeds the
list's blob with; a const- / enum-named one is a deferred entry, superseded, so `_gvk_one` folds it but does not bake
it (6.7.15: bk 4, "the later constant's value is the slot's") and the blob is seeded with 0.

## Proposed fix

When the superseding declaration is a list, the superseded scalar constant entry that is the slot's last constant
before it still records its value as the seed (`_vgsi_base`) — as the literal's static init does — so the blob keeps
the unlisted bytes. Rows: the three repros give 14 on x86_64, aarch64, cx and PE; a computed earlier scalar
(`var a = f(); var a[1] = {9};`) still reads 9 (the guide's "over an earlier `= 0` or computed initializer ... the
value from program start").
