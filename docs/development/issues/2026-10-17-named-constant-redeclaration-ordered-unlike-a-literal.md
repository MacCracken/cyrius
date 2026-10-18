# A const- or enum-NAMED (or `= 0`) declaration-zone redeclaration is ordered unlike a literal one: `var a = D; var b = a; var a = C;` gives b == D, though the guide says every read sees the last definition — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend at 7b32fd5b, x86_64; the
same values on the slot-open compiler, 2600f67f's build/cycc, except the one row marked). Pre-existing: the slot-open
compiler gives every row below but one; the lane now pins two of them (tests/gates/frontend/const_init_bake_and_fold.sh
O4 = 57 and O6 = 24, on x86_64, aarch64 and cx). Met by the 6.7.14 frontend review of 735fb3c7
(issues/archived/2026-10-08-const-init-redundant-store-and-unfolded-const-operand.md item 1, the user's decision D11 (b)).
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — a read between two declarations of one global sees a different value depending on how the
earlier constant is SPELLED (`3` or `D`), silently; the guide documents the literal reading as the rule.
**Kind:** language — which reading is cyrius is the user's call; more rows should not pin either before it is made.

## Reproduction

`fn setg(): i64 { G = 9; return 1; }`, `const C = 5;`, `const D = 3;`, `enum E { A = 2; B = 4; }`:

| source (declaration zone) | slot-open | lane |
|---|---|---|
| `var a = 5; var b = a; var a = 7;` (the guide's example) | b == 7 | b == 7 |
| `var G = 3; var b = G; var G = C;` | b == 5 | b == 5 |
| `var a = D; var b = a; var a = C;` | b == 3 | b == 3 |
| `var a = E.A; var b = a; var a = E.B;` (O6: `b * 10 + a`) | 24 | 24 |
| `var G = 0; var b = G; var G = 5;` | b == 5 | b == 5 |
| `var G = 0; var b = G; var G = C;` | b == 0 | b == 0 |
| `var G = 3; var r = setg(); var G = 5;` | 9 | 9 |
| `var G = 3; var r = setg(); var G = C;` | 5 | **9** (735fb3c7, guide-documented) |
| `var G = D; var r = setg(); var G = C;` | 5 | 5 |
| `var G = 0; var r = setg(); var G = C;` | 5 | 5 |
| `var G = 0; var r = setg(); var G = 5;` | 9 | 9 |

```sh
cd <the tree>
printf 'const C = 5;\nconst D = 3;\nvar a = D;\nvar b = a;\nvar a = C;\nsyscall(60, b);\n' | build/cycc > /tmp/e && chmod +x /tmp/e && /tmp/e; echo $?
# 3   (no diagnostic)
printf 'var a = 3;\nvar b = a;\nvar a = 5;\nsyscall(60, b);\n' | build/cycc > /tmp/l && chmod +x /tmp/l && /tmp/l; echo $?
# warning:<source>:3:7: duplicate symbol 'a' redefined with conflicting value (last definition wins)
# 5
printf 'const C = 5;\nconst D = 3;\nvar G = D;\nfn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = C;\nsyscall(60, G);\n' | build/cycc > /tmp/c && chmod +x /tmp/c && /tmp/c; echo $?
# 5
printf 'const C = 5;\nvar G = 3;\nfn setg(): i64 { G = 9; return 1; }\nvar r = setg();\nvar G = C;\nsyscall(60, G);\n' | build/cycc > /tmp/a && chmod +x /tmp/a && /tmp/a; echo $?
# 9   (slot-open: 5)
```

docs/guides/cyrius-guide.md § *Declaring a global twice*: "A redeclaration whose initializer is a compile-time
**constant** (an integer literal or a foldable integer expression, zero included) is the global's value **from
program start**", with `var a = 5; var b = a; var a = 7;` giving `b == 7`. A named constant (`C`, `E.B`) folds the
same way (`_gvk_pre` bakes it into the image), yet the rows above read the EARLIER constant when it is named or `0`.
§ Global Initializers (as corrected by the 6.7.14 review) now describes both behaviours as they are.

## Root cause

PARSE_GVAR_REG (src/frontend/parse_decl.cyr) folds the initializer with `_CF_TRY` in pass 1, where names do not fold
(`_cf_enum` is on only at the replay). A nonzero literal or literal expression (`= 3`, `= -3`, `= 2 + 1`) becomes a
STATIC init (`sit_lit`); a folded zero falls through on purpose (v5.11.64), and a const- / enum-named initializer
cannot fold there — both become DEFERRED entries, baked by `_gvk_pre` and replayed in declaration order at startup.
6.7.14's `_gvk_quiet` drops a baked entry's replay only where the nearest earlier replayed writer of the slot holds
the same value, so an earlier named / zero constant's replayed store still runs before `var b = a;`, and the later
named constant's store after it — the computed-initializer ordering, applied to constants.

## Proposed fix (after the user's decision)

(a) The guide's rule for every constant: a constant redeclaration — literal, folded expression, `0`, const- or
enum-named — is the value from program start; an earlier constant declaration of the slot leaves no startup store
(the image holds the last constant's value; `_gvk_quiet` would drop every baked entry of a slot whose last constant
is baked, computed entries still replayed in order). O4 becomes 77, O6 44, `var G = D; setg; var G = C;` 9. Or
(b) the named-constant order is the rule: the guide's § Declaring a global twice says so, and the literal rows change
instead (a language change either way for one side). Rows: the table above, on x86_64, aarch64, cx and PE.
