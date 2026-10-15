# A const context's skipped arm (`1 || pk()`, an untaken if-expression arm) names another file's `private` const fn with no visibility check and no `#deprecated` warning — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe) after unit F2's fix of
`issues/archived/2026-10-09-const-context-calls-private-const-fn.md` (commit b8fc9526): the evaluated call is refused; a call in an
arm the evaluator skips still builds silently.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 genfe lane) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit F2 (the issue's fix plan checks a const context's call only
when `_ce_skip == 0`; this is the shape that leaves out), outside the filed surface.
**Severity:** Low — the documented `private` boundary ("covers every way of reaching a fn") is not held for a call the
evaluator never runs. The run-time path refuses the same text (`var X = 1 || pk();`), so the two paths disagree.
**Affects:** cycc 6.7.2 (`const fn`) through the 6.7.11 genfe lane tree.

## Reproduction

`priv.cyr`:

```cyrius
private
const fn pk(): i64 { return 3; }
```

Each file below sits beside it and starts `include "priv.cyr"`:

| the rest of the file | lane tree after F2 | expected |
|---|---|---|
| `const X = 1 \|\| pk();` `syscall(60, X);` | builds, exits 1 | refused, `'pk' is private to its file` |
| `const X = 0 && pk() == 3;` `syscall(60, X);` | builds, exits 0 | refused |
| `const X = if (1 == 1) { 3 } else { pk() };` `syscall(60, X);` | builds, exits 3 | refused |
| `var X = 1 \|\| pk();` `syscall(60, X);` (run time) | refused at 2:17 | (control) |

`#deprecated("old") const fn dk()` in one file: `const X = 1 || dk();` is silent, while `var y = 1 || dk();` in a fn
warns `'dk' is deprecated: old`.

## Root cause

`src/frontend/parse_fn.cyr` at the lane tree (after unit F2): `_ce_site` (:8594) runs `_callee_site_checks` only when
`_ce_infn == 0` and `_ce_skip == 0`. Skip mode is set for four different walks: the definition check of a const fn
(`_ce_check_fn`, which also sets `_ce_infn`), the right operand of a short-circuit `||` / `&&` (`_ce_expr` :8215 /
`_ce_land` :8230), an if-expression's untaken arm, and `_ce_xpend_one` (:9145), which re-walks a top-level const's arm
after every const is known. Only the last must stay unchecked (it re-walks an expression already checked, and
`_vis_check` keeps no per-site memory — see the staged `2026-10-14-private-call-reported-once-per-body-replay.md`).

## Proposed fix

Check in skip mode too, except in a const fn's body (`_ce_infn`) and in the `_ce_xpend_one` re-walk (a flag it sets),
or after `_vis_check` reports once per site. Rows: the table above, each refused once at the call; the `#deprecated`
form warns once; `const_checked.sh` V2a-V2g stay green.
