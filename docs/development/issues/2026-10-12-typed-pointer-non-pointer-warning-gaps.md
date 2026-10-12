# "assigning non-pointer to typed pointer" is missing for a declaration-zone `*T` global and for an assignment to a local or parameter `*T` of a scalar `T` — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the 6.7.10 slot-open tree (`efb6623f`, `build/cycc` 2,057,744
B) on x86_64. Inside a fn, `var x = 3; var q: *i64 = x;` warns "assigning non-pointer to typed pointer". Each shape
below assigns the same kind of untyped value to a `*T` and compiles with no warning. The installed 6.6.0, 6.6.10,
6.7.0 and 6.7.9 compilers give the same answers for the two headline shapes.
**Placement:** 6.7.13 — repair 3 (roadmap.md § *6.7.13*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (the guide's *Pointers* re-verification).
**Severity:** Low. A missing diagnostic: nothing miscompiles, and the stored word is what was written. A wrong
typed-pointer binding then goes unflagged.
**Affects:** cycc 6.6.0 – the 6.7.10 tree (measured at 6.6.0, 6.6.10, 6.7.0, 6.7.9 and the tree; not bisected). The
check is frontend-only, so it is the same on every target.

## Summary

The warning fires on a `*T` declaration inside a fn, on a top-level declaration after the first statement, and on an
assignment to a `*T` global or to a `*Struct` local. It does not fire in two places:

1. **A top-level `var p: *T = x;` in the declaration zone** (before the first top-level statement), for every `T`:
   `*i64`, `*u8`, `*Pt`, `= x + 1`, `= 3`. The same line after one statement warns.
2. **An assignment to a local or parameter `*T` whose `T` is not a struct**: `p = x;` after `var p: *i64 = &x;`,
   likewise `*u8` / `*i32`, `p = 3`, and `p = x` to a parameter `p: *i64`. The same assignment to a `*Pt` local, or
   to a `*i64` global from inside a fn, warns.

Measured (x86_64, the tree; "warns" = count of the message):

| shape | warns |
|---|---|
| fn: `var x = 3; var q: *i64 = x;` | 1 |
| fn: `var q: *i64 = x + 1;` / `= 3` | 1 / 1 |
| top level, declaration zone: `var x = 3; var p: *i64 = x;` | **0** |
| top level, declaration zone: `var p: *u8 = x;` / `var p: *Pt = x;` / `var p: *i64 = x + 1;` / `= 3` | **0** / **0** / **0** / **0** |
| top level after `syscall(39);`: `var p: *i64 = x;` | 1 |
| top level: `var p: *i64 = &x; p = x;` | 1 |
| fn: `var p: *i64 = &x; p = x;` | **0** |
| fn: `var p: *u8 = &x; p = x;` / `*i32` / `p = 3` | **0** / **0** / **0** |
| fn: `fn f(p: *i64) { p = x; }` | **0** |
| fn: `var p: *Pt = &q; p = x;` | 1 |
| fn: `G = x;` with `var G: *i64 = 0;` | 1 |

## Reproduction

```sh
cd /home/macro/Repos/cyrius
printf 'var x = 3;\nvar p: *i64 = x;\nsyscall(60, 0);\n' | build/cycc > /tmp/tp1 2> /tmp/tp1.err
grep -c 'assigning non-pointer' /tmp/tp1.err      # 0 (inside a fn the same line warns)
printf 'fn f(): i64 {\n    var x = 3;\n    var p: *i64 = &x;\n    p = x;\n    return 0;\n}\nsyscall(60, f());\n' \
  | build/cycc > /tmp/tp2 2> /tmp/tp2.err
grep -c 'assigning non-pointer' /tmp/tp2.err      # 0
printf 'fn f(): i64 {\n    var x = 3;\n    var q: *i64 = x;\n    return 0;\n}\nsyscall(60, f());\n' \
  | build/cycc > /tmp/tp3 2> /tmp/tp3.err
grep -c 'assigning non-pointer' /tmp/tp3.err      # 1 (the control)
```

## Root cause

- **The declaration zone.** A declaration-zone initialiser is replayed by `EMIT_GVAR_INITS` through `_gvi_expr`
  (`src/frontend/parse_decl.cyr:5272`), which runs `PCMPE` and never reads `GPSC`. PARSE_VAR's check
  (`if (pscale > 0) { if (expr_ps == 0) { WARN(..) } }`, `src/frontend/parse_decl.cyr:6869–6872`) only runs for a
  declaration after the first statement. An initialiser the folder bakes into the image (`= 3`) is not replayed at
  all, so `PARSE_GVAR_REG` (`:4653`) would need the check for that case.
- **The local assignment.** PARSE_STMT's assignment arm warns for a local only when `lt < 0`
  (`src/frontend/parse.cyr:4845–4847`). That is the `0 - sid` SLTYPE of a struct-typed or `*Struct` local. A `*T`
  local of a non-struct `T` gets SLTYPE 8 (step 8) or 0 with a step mark (`_sl_ptr_type`,
  `src/frontend/parse_types.cyr:2349`). A `p: *T` parameter is marked by `_param_record` with the slot's
  typed-pointer bit 56 (`GLPTRP`, `src/common/util.cyr:1687`). Neither is `< 0`, so the arm never fires for them.
  The global arm (`vt < 0`, `parse.cyr:4875–4877`) works because a `*T` global's GVTYPE is `0 - step`
  (`_gv_ptr_type`, `parse_types.cyr:2439`).

## Proposed fix

1. `_gvi_expr` (and the baked path of `PARSE_GVAR_REG`) warns as PARSE_VAR does when the global's `gps > 0` and the
   initialiser's `GPSC` is 0. One shared helper for both sites.
2. The local arm of the assignment warns when the slot is a typed pointer (`GLPTRP(S, idx) == 1`) as well as when
   `lt < 0`, with the same exemptions it has today (`_asg_ret_sid > 0`: a call declared to return a pointer).
3. This adds warnings where none fired, so first measure the blast radius over `lib/`, `programs/`, `cbt/` and the
   `.tcyr` corpus, as 6.5.28 did for this warning. **One-line question for the user:** *should `= 0` / `p = 0` (a
   null pointer) be exempt?* Today `var p: *i64 = 0;` inside a fn already warns, and the extended assignment arm would
   warn on `p = 0` too.
4. Rows (a gate under `tests/gates/diagnostics/`), mutation-proven: each **0** row in the table above warns once,
   each 1 row stays at 1, and `var p: *i64 = &x;` / `p = &y;` / `p = gp();` (a `: *i64` fn) stay at 0.

## Consumer-side workaround

None needed. Nothing miscompiles. Until the fix, a `*T` initialised or reassigned from an untyped value in those
positions is not flagged.
