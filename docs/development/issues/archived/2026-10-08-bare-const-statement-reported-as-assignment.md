# A bare const / enum-constant name as a statement is reported as an assignment (`N;` → "cannot assign to const 'N'") — RESOLVED

> ✅ **RESOLVED in v6.7.14** (FE-10, `753a8e92`, with FE-11, `a5b7554a`: the lvalue refusal runs only before `=` / `OP=` (`_asg_lvalue_at`, at the statement's ident arm and in `_for_step_assign`; `_enum_qual_store_refused` for `E.A`); a const or enum constant without one is "expected '='" in place, once, and the statement is stepped over in sync (`_cst_skip_sync`), so the next statement's error is printed too; no decision needed. The filed repro is "4:6: expected '=', got ';'"; `N + 1;`, `N == 5;`, `GREEN;`, `Color.GREEN;` and a step `N` likewise; `N = ..`, `N += ..` and `E.A = ..` keep the refusal. Rows: `frontend/const_checked.sh` B0 (the repro verbatim) – B13, `enum_const_not_lvalue.sh` B1 – B6; RED on the compiler before. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with the tree's `build/cycc`: `N;`, `N + 1;`, `N == 5;`, a for-step `N`, `GREEN;` and `Color.GREEN;` all report "cannot assign to …". A plain variable in the same places reports `expected '=', got …`.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (frontend lane, wave 1, unit F2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** before 2026-10-08 (carried in roadmap.md's backlog; the refusal it mis-fires is 6.7.2's const lvalue rule (B1), extended to enum constants in 6.7.3); filed 2026-10-08 from roadmap.md.
**Severity:** Low — a misleading diagnostic on source that is invalid either way.
**Affects:** cycc 6.7.2–6.7.6 (const); 6.7.3–6.7.6 (enum constant).

## Summary

A statement that starts with a const or an enum-constant name but is not an assignment is refused with
the lvalue diagnostic. The program is invalid either way (cyrius has no expression statements: `x;` with a
variable is `expected '=', got ';'`), but the message tells the author they assigned to a const when they
did not. The roadmap calls this cosmetic. Fixing it changes a 6.7.2 diagnostic.

## Reproduction

```cyr
const N = 5;
enum Color { RED, GREEN }
fn main(): i64 {
    N;              # also: N + 1;  N == 5;  GREEN;  Color.GREEN;  for (i = 0; i < 3; N) { }
    return 0;
}
syscall(60, main());
```

```sh
cat repro.cyr | build/cycc > /tmp/o
# actual:   error:<source>:4:6: cannot assign to const 'N' - a const has no storage (declare it `var` to change it)
#           (GREEN;        -> cannot assign to enum constant 'GREEN' - an enum constant is a fixed value, …)
# expected: the diagnostic a variable gets in the same place — `x;` reports
#           error:<source>:4:6: expected '=', got ';'
```

## Root cause

- `src/frontend/parse.cyr:4298` (in `_PARSE_STMT_IMPL`, `src/frontend/parse.cyr:3861`): the identifier
  statement arm calls `_asg_lvalue_refused` BEFORE `_asg_compound_tok` and the `=` check. Any token after
  the name gets the lvalue refusal.
- `src/frontend/parse_ctrl.cyr:785` (`_for_step_assign`): the same order in the classic-for step.
- `src/frontend/parse_decl.cyr:1846`: `Color.GREEN;` reaches `_enum_qual_store_refused`
  (`src/frontend/parse_fn.cyr:7211`) from `PARSE_FIELD_STORE` before any `=` is seen.
- The refusals are in `src/frontend/parse_fn.cyr:7157` `_cst_lvalue_check` and `:7177` `_asg_lvalue_refused`.

## Proposed fix

At all three sites, run the lvalue refusal only when the next token is `=` or a compound `OP=`
(`_asg_compound_tok` already recognises them). Otherwise fall through to the existing
`ERR_EXPECT(S, 4)`, which a variable gets. Add gate rows for the bare, expression, for-step and
qualified-enum shapes, next to the existing const / enum lvalue rows.
