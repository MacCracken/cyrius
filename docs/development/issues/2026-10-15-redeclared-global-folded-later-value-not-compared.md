# A redeclared global whose LATER initializer is a folded constant (`= 2 + 1`, `= -5`, `= (7)`) is never compared — a conflicting value compiles silently — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-15 by the 6.7.12 fixfirst lane (unit X2) while landing D30 (a prior `= 0` is
compared), measured on the lane tree (01a77b61, x86_64; frontend, every target alike).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (frontend lane; filed from the 6.7.12 fixfirst lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** Low — a diagnostic gap (the program's value is right: the last definition wins); it is the same class as
the D30 gap (two files' same-name globals merging unseen) for a later constant spelled as an expression.
**Kind:** bug (diagnostic).

## Repro

```sh
printf 'var a = 5;\nvar a = 2 + 1;\nsyscall(60, a);\n' | build/cycc > /dev/null   # NOTHING (runs: exit 3)
printf 'var a = 5;\nvar a = -5;\nsyscall(60, a & 255);\n' | build/cycc > /dev/null  # NOTHING (exit 251)
printf 'var a = 5;\nvar a = (7);\nsyscall(60, a);\n' | build/cycc > /dev/null    # NOTHING (exit 7)
printf 'var a = 5;\nvar a = 0x7;\nsyscall(60, a);\n' | build/cycc > /dev/null    # warning: duplicate symbol 'a' redefined with conflicting value (last definition wins)
```

## What the guide says

docs/guides/cyrius-guide.md § *Declaring a global twice*: a redeclaration whose initializer is a compile-time constant
("an integer literal or a foldable integer expression, zero included") is the global's value from program start; "a
later integer literal that differs from the earlier constant warns". A folded later constant is the same kind of
definition as a literal (it is baked the same way) but is not compared.

## Root cause

PARSE_GVAR_REG (src/frontend/parse_decl.cyr) captures the NEW value for CHKDUPVAL only for the exact shape
`= NUM ;` (`chk_lit` / `chk_has`, v6.2.11), while the PRIOR side compares any folded constant (`_vgsi_base`, and since
6.7.12 `_gv_has_lit` for a zero). The `_CF_TRY` fold result (`cf_has` / `cf_val`) computed a few lines later is not
fed to CHKDUPVAL.

## Proposed fix

Compare `cf_val` when `cf_has == 1` (and the global is not a struct), as the prior side does: `var a = 5; var a = -5;`
warns, a same folded value (`var a = 5; var a = 2 + 3;`) stays silent. Census as D30's: the self-host, check.sh and
every lib/ include set print no new warning (any that appears is a real collision, fixed in the fold's source).
Rows beside tests/gates/frontend/global_redeclaration_one_definition.sh W1-W9.
