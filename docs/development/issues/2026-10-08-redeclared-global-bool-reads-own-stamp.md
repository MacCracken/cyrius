# A redeclared global read inside its own `bool` redeclaration reads as boolean (`var G = 5; var G: bool = G;` exits 5) — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the tree's `build/cycc` (x86_64): the repro compiles clean and exits 5, so a `bool` holds 5. With a different integer global on the right (`var H = 5; var G: bool = H;`) it is refused.
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** before 2026-10-08 (carried in roadmap.md's backlog); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — silently breaks 6.7.3's rule that a bool reads as 0 or 1, though only through a self-referential redeclaration.
**Affects:** cycc 6.7.3–6.7.6 (the boolean stamp, B2).

## Summary

A global's bool and integer marks are per SLOT and belong to the LAST declaration
(`src/frontend/parse_types.cyr:325-328`, `_gv_last_marks`). Every declaration-zone initializer is
replayed after all globals are registered. So when the right side of `var G: bool = …` reads `G`, it sees
the redeclaration's own bool mark and is stamped as a boolean. The value is still the earlier `5`.

The same per-slot marking also gives two related shapes:

1. **The reported case.** `var G = 5; var G: bool = G;` compiles and exits 5.
2. **A false refusal.** `var G: bool = true; var X: bool = G; var G = 5;` is refused at line 2
   ("cannot initialize bool 'X' with a value that is not a bool") although `G` is a bool at that point.
   The later integer redeclaration cleared the mark.
3. **A false acceptance.** `var G = 5; var X: bool = G; var G: bool = true;` compiles clean although
   line 2 reads an integer-declared `G`. Without the line-3 redeclaration it is refused.

## Reproduction

```cyr
var G = 5;
var G: bool = G;
syscall(60, G);
```

```sh
cat repro.cyr | build/cycc > /tmp/rb && chmod +x /tmp/rb && /tmp/rb; echo $?
# actual:   compiles clean, exits 5
# expected: refused like `var H = 5; var G: bool = H;`:
#   error:<source>:2:15: cannot initialize bool 'G' with a value that is not a bool
```

## Root cause

- `src/frontend/parse_types.cyr:332` `_gv_last_marks` → `SVBOOL(S, vi, b)` (`src/common/util.cyr:859`):
  one bool byte per global slot, overwritten by each redeclaration.
- `src/frontend/parse_decl.cyr:4444` `_bx_gvi_expr`: the initializer is judged at the replay by `_BX_IS`
  (`src/frontend/parse_expr.cyr:1398`). The read of `G` stamps as boolean because `GVBOOL` of the shared
  slot is the last declaration's.

## Proposed fix — the user's decision

Every option changes what compiles today, so the user picks:

- **(a) Refuse a redeclaration that changes bool-ness** (the roadmap's suggestion). The refusal happens at
  registration, where the previous declaration's mark is still known. This also removes shapes 2 and 3.
  It refuses programs like `var G = 5; var G: bool = true;` that compile today.
- **(b) Judge each initializer against the marks in force at its own declaration.** Record a mark per
  declaration entry (`_gv_ent_base`) instead of per slot for the bool / integer check. This only refuses
  the shapes above that are wrong today (1 and 3) and accepts shape 2.

Add gate rows for all three shapes next to the existing 6.7.3 B2 rows.
