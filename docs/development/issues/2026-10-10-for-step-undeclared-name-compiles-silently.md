# A `for` step assigning an UNDECLARED name compiles and stores nothing (`for (i = 0; i < 5; j = i + 1)` never ends) — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: the repro builds with no diagnostic and loops until its guard returns 99; `for (n = 0; n < 3; zz = 1)`
and `for (..; ..; yy += 1)` with neither name declared anywhere also build (rc 0). The statement `zz = 1;` is refused
"undefined variable 'zz'". The repro behaves the same with the installed 6.6.10, 6.6.20, 6.7.0, 6.7.3, 6.7.5, 6.7.6
and 6.7.7 compilers.
**Placement:** 6.7.10 — repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-10 — never 7.x (the fix
is the user's call, asked at that release's open: a program that compiles today is refused).
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
