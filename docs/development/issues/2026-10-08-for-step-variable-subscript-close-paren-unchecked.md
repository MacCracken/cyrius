# A variable or subscript classic-`for` step never checks its `)` — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc`:
`for (i = 0; i < 3; i += 1 2)` builds and runs 3 iterations; so do a global step, `i = i + 1 2`,
`a[0] += 1 2`, `i += 1 ; junk` and a 24 B struct step `a = b 2` (which also stores one word: `a.y` stays 2).
The field step `c.n += 1 2` reports "expected ')', got number 2".
**Placement:** unpinned — 6.x-line backlog — never 7.x.
**Discovered:** 6.7.5 B8 lane (roadmap commit e95f295d); filed 2026-10-08 from roadmap.md.
**Severity:** Low
**Affects:** cycc ≤ 6.7.6 (field and `*p` steps check since 6.7.5)

## Summary

The step of a classic `for` is skipped (by paren depth) before the body and replayed after it. The field and `*p`
step arms end at the terminator `)` and report anything else; the variable and subscript arms stop after the value
expression and never look, so trailing junk up to the `)` is silently ignored.

## Reproduction

```cyrius
fn main() {
    var s = 0;
    var i = 0;
    for (i = 0; i < 3; i += 1 2) { s = s + 1; }
    return s;
}
var r = main();
syscall(60, r);
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Expected: `expected ')', got number 2`, as for the field step `for (c.n = 0; c.n < 3; c.n += 1 2)`. Actual:
builds, exits 3. With `struct P3 { x; y; z; }`, `a = P3 { 1, 2, 3 }`, `b = P3 { 4, 5, 6 }` and the step
`a = b 2`, the program builds and after the step `a` is `{4, 2, 3}` (`{4, 5, 6}` is right): the junk also defeats the
whole-struct dispatch, which needs the terminator right after the source name
(`_try_aggregate_copy_assign`, `src/frontend/parse.cyr:3375`), so the step falls to the one-word store.

## Root cause

`_for_step_replay` (`src/frontend/parse_ctrl.cyr:822`) dispatches `*p` to `_deref_store(S, 11)` and a field to
`PARSE_FIELD_STORE(S, noff, 11)` — both check the `)` terminator — but `_arr_sub_assign`
(`src/frontend/parse_expr.cyr:2445`) and `_for_step_assign` (`parse_ctrl.cyr:781`) return without checking
`PEEKT(S) == 11`. The statement forms check their `;` in the caller (`_arr_sub_stmt`, `_PARSE_STMT_IMPL`); the step
has no such caller check. PARSE_FOR restores the cursor after the replay, so nothing downstream notices.

## Proposed fix

Check the `)` on every variable / subscript step path that has not already consumed it —
`if (PEEKT(S) != 11) { ERR_EXPECT(S, 11); }`, the check the field and `*p` arms make: after `_arr_sub_assign` in
`_for_step_replay`, and at the end of `_for_step_assign`'s scalar store (the whole-aggregate helpers in
`_for_step_aggregate` take the terminator and return 1 once they have handled it — confirm each before relying on
it). It refuses only malformed steps (source that builds today but is not valid cyrius). Pin with a gate row per
arm (local, global, subscript, whole struct; `=` and `OP=`) beside the 6.7.5 field / `*p` rows.
