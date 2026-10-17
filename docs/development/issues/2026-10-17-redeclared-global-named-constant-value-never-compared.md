# A redeclared global whose initializer is a const- or enum-NAMED constant of another value is never compared — `var a = 3; var a = C;` compiles silently — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend at 7b32fd5b, x86_64; the
frontend, every target alike) and identical on the slot-open compiler (2600f67f's build/cycc). Beyond the filed surface
of issues/2026-10-15-redeclared-global-folded-later-value-not-compared.md (fixed in the lane by 27c6ff70: a later
`= 2 + 1`, `= -5`, `= (7)` is compared), which named literal expressions only. Met by the 6.7.14 frontend review.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — a diagnostic gap (the value is the last definition's, or see the companion ordering issue
2026-10-17-named-constant-redeclaration-ordered-unlike-a-literal.md); the same class as 6.7.12's D30 (two files'
same-name globals merging unseen), for a constant spelled by name.
**Kind:** bug (diagnostic).

## Reproduction

```sh
cd <the tree>
printf 'const C = 5;\nvar a = 3;\nvar a = C;\nsyscall(60, a);\n' | build/cycc > /dev/null        # NOTHING (runs: exit 5)
printf 'const C = 5;\nvar a = C;\nvar a = 3;\nsyscall(60, a);\n' | build/cycc > /dev/null        # NOTHING (exit 3)
printf 'enum E { A = 3; B = 5; }\nvar a = 3;\nvar a = E.B;\nsyscall(60, a);\n' | build/cycc > /dev/null   # NOTHING (exit 5)
printf 'const C = 5;\nconst D = 3;\nvar a = D;\nvar a = C;\nsyscall(60, a);\n' | build/cycc > /dev/null   # NOTHING (exit 5)
# the literal controls warn:
printf 'var a = 3;\nvar a = 5;\nsyscall(60, a);\n' | build/cycc > /dev/null
# warning:<source>:2:7: duplicate symbol 'a' redefined with conflicting value (last definition wins)
printf 'var a = 3;\nvar a = 2 + 3;\nsyscall(60, a);\n' | build/cycc > /dev/null      # lane (27c6ff70); slot-open: nothing
# warning:<source>:2:7: duplicate symbol 'a' redefined with conflicting value (last definition wins)
```

docs/guides/cyrius-guide.md § *Declaring a global twice*: "A later constant that **differs** from the earlier constant
warns, whatever that constant was"; "The later constant is any initializer that folds". `C` and `E.B` fold (`_gvk_pre`
bakes them into the image), but are not compared on either side.

## Root cause

PARSE_GVAR_REG (src/frontend/parse_decl.cyr) compares in pass 1: the new value is `chk_lit` (`= NUM ;`) or, since
6.7.14, `_CF_TRY`'s `cf_val` (`_gv_dup_folded`), and the prior value is the slot's static init. `_CF_TRY` folds no
names in pass 1 (`_cf_enum` is on only at the replay, `_gvk_pre` / `_gvi_expr`), so a named later constant has no
`cf_has`, and a named EARLIER constant records no static value for a later literal's CHKDUPVAL to compare.

## Proposed fix

Compare where names fold: in `_gvk_pre`, after each deferred scalar entry's value is known (`_gvk_v`), check it
against the slot's earlier constant (its static init, or the previous baked entry's value) and give the same warning
where the literal pair gives it — once, and silent for a same value. Rows: the four repros warn once (3:7 / 3:7 /
3:7 / 4:7); same-value pairs (`var a = 5; var a = C;`) silent; a computed earlier initializer silent; the enum
shadow error (`var A = ..` over an enum constant) unchanged.
