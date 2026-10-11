# A `for` step assigning an UNDECLARED name compiles and stores nothing (`for (i = 0; i < 5; j = i + 1)` never ends) — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 17, l679-crit; CHANGELOG [6.7.9]) `_for_step_assign` (parse_ctrl.cyr) now reports a destination that is neither a local nor a global with the statement's own report (`_asg_undef_report`, parse.cyr, shared by both): `error: <file>:<line>:<col>: undefined variable 'j'` with its excerpt, plain and compound, in a fn and at top level; `--syntax-only` stays silent, as the statement does. The repro exits 1 at compile. Rows U1-U6 / X4 / P7 and a V row in tests/gates/frontend/for_step_terminator_checked.sh, mutation-proven (its ledger). The user's decision 3(b).

**Status:** ✅ **RESOLVED in v6.7.9** — see the banner above and *Resolution* below. Reproduced on the 6.7.9 lane
tip @ 0740aa8c before the fix: the repro builds rc 0 and runs to its guard (99); `yy += 1` the same. As filed:
🟡 OPEN — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: the repro builds with no diagnostic and loops until its guard returns 99; `for (n = 0; n < 3; zz = 1)`
and `for (..; ..; yy += 1)` with neither name declared anywhere also build (rc 0). The statement `zz = 1;` is refused
"undefined variable 'zz'". The repro behaves the same with the installed 6.6.10, 6.6.20, 6.7.0, 6.7.3, 6.7.5, 6.7.6
and 6.7.7 compilers.
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-2b (the for-step work).
**Severity:** High — a typo in a loop step is silently dropped: the loop variable never advances, so the program
spins forever (or computes with a stale index) with no diagnostic.
**Affects:** cycc 6.6.10 – 6.7.8 (every target: the step is parsed in the shared frontend)

## Summary

The classic `for` step is replayed after the body as an assignment. Its plain-variable arm evaluates the right-hand
side, then looks the destination up as a local and, failing that, as a global — and when both lookups fail it does
nothing at all: no store and no error. The same assignment as a statement reports "undefined variable". So a step
whose name is misspelled (`j` for `i`), or a name that was never declared, builds clean and the loop never moves.

## Reproduction

`docs/development/issues/repros/2026-10-10-for-step-undeclared-name-compiles-silently.cyr`:

```cyrius
include "lib/syscalls.cyr"
fn main(): i64 {
    var i = 0;
    var c = 0;
    for (i = 0; i < 5; j = i + 1) {      # `j` is declared nowhere: no diagnostic, the step does nothing
        c = c + 1;
        if (c > 50) { return 99; }       # guard: the loop never ends without it
    }
    return c;                            # want a compile error ("undefined variable 'j'"), as `j = 1;` gets
}
var rc = main();
syscall(60, rc);
```

```
actual:   compile rc 0, no diagnostic; run: exit 99 (the guard)
expected: error: undefined variable 'j' — the statement's diagnostic, at the step
```

## Root cause

`_for_step_assign` (`src/frontend/parse_ctrl.cyr:790`): after the value is parsed, `idx = FINDLOCAL(S, noff)` (in a
fn), then `idx = FINDVAR(S, noff)`; each `if (idx >= 0)` arm stores, and there is no `else`. The compound form
(`yy += 1`) goes through `_asg_compound_load` first and is equally silent. The statement path reports the name
("undefined variable '…'").

## Proposed fix

When neither lookup finds the destination, report it as the statement does (the same `ERR_IDENT` text and
location), for the plain and compound forms. Rows: the repro; `zz = 1` and `zz += 1` as steps; a step naming a
global declared AFTER the loop's fn (stays legal if the statement form accepts it — check against the statement path
first); a step naming a fn or an enum constant (already refused by `_asg_lvalue_refused`); the normal `i = i + 1` /
`i += 1` steps unchanged.

## Consumer-side workaround

None needed beyond care: a step must name a declared variable — the compiler will not catch a misspelling there.

## Resolution (6.7.9)

The statement arm's "undefined variable" report (`_PARSE_STMT_IMPL`, parse.cyr) moved into one helper,
`_asg_undef_report(S, noff)` — "error:", the position, `undefined variable '<name>'`, the excerpt and caret, the
block-scope note, `_had_error` — and the classic-for step calls it in the `else` its FINDVAR lookup lacked. The
statement keeps its own `;` handling and `--syntax-only` skip; the step skips the report under `--syntax-only` (a
sibling module's global, as the statement and the X1 row already require) and checks its `)` after it, as the
statement checks its `;` after its report. The compound form needs nothing more: `_asg_compound_load` loads nothing
for an unknown name and the same `else` reports it.

Premise check: the filing expected "a step naming a fn" to be refused already by `_asg_lvalue_refused`. It was not —
`for (..; g = 1)` with `g` a fn compiled silently too (the statement says `undefined variable 'g'`); it is now the
statement's error. The same holds for a closure's captured name (`t += 1` in a closure body's step: the guide's "a
captured NAME is not an lvalue in the closure"), which stored nothing and left the capture at its old value (measured:
`for (k = 0; k < n; t += 1) { k = k + 1; } return k * 10 + t;` with `t = 0` captured returned 40; the statement
form is refused). A global declared AFTER the loop's fn stays legal
(FINDVAR finds it; the V row `later_global` runs it on every leg), as does a local declared in the loop body (the
for's scope is open at the step).

Rows, in tests/gates/frontend/for_step_terminator_checked.sh: U1 the repro verbatim, U2 `zz = 1`, U3 `yy += 1`, U4 a
top-level step, U5 a fn's name, U6 a captured name in a closure's step — each exactly one error line; X4 a plain step
on a global the file cannot see stays silent under `--syntax-only` (X1 is the compound form); V gains a step on a
global declared after its fn (x86 plain / IR=1 / IR=3 / DCE=1, aarch64 under qemu, cx, PE under wine); P7 the repro
on the aarch64 and cx compilers built from the tree. Mutations (scratch trees, the gate run there): no `else` → RED
U1-U6 P7 (each builds); the report without its `--syntax-only` guard → RED X1 X4; the pre-fix tree → RED U1-U6 P7.
The corpus differential (1,062 sources: the `.tcyr` / `.bcyr` / `.fcyr` corpus, `programs/`, `cbt/`, `lib/`, the
test fixtures — the pre-fix stage-1 compiler against the fixed one) is byte-identical, same exit codes and
diagnostics. The guide's *Known Limitations* bullet on the classic `for` step says it.
