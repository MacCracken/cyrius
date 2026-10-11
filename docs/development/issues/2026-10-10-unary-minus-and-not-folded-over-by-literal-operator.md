# The run-time constant fold folds a literal operator OVER a unary `-` / `~` operand: `-K + 10` is 15, `~5 + 10` is 15 — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: with `enum E { K = 5; }`, `-K + 10` → 15 (want 5), `-E.K + 10` → 15, `-K * 2` → 10 (want -10),
`~5 + 10` → 15 (want 4), `~5 * 2` → 10 (want -12), `~0 + 3` → 3 (want 2), `~K + 1` → 6 (want -5); `var a = -K + 10;`
is 15 too, and so is `-C + 10` with `const C = 5;`. `-5 + 10`, `(~5) + 10` and `(-K) + 10` are right. The repro exits 7 (seven wrong values) with the installed
6.6.10, 6.6.20, 6.7.0, 6.7.3, 6.7.5, 6.7.6 and 6.7.7 compilers as well.
**Placement:** 6.7.11 — repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-10 — never 7.x (the fix
is the user's call, asked at that release's open: what these expressions compute changes — from wrong to right).
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-1b (its probes; the same `_cfo` class as that bite's slice
fix).
**Severity:** High — a silent wrong value on valid, ordinary arithmetic; no diagnostic.
**Affects:** cycc 6.6.10 – 6.7.8 (every target: the fold is in the shared frontend; x86_64 measured)

## Summary

The expression parser folds `K op L` at compile time when its left operand was a constant factor (an integer
literal, an enum constant or a const, 0 – 0xFFFF) and the right is an integer literal: the constant factor arms
`_cfo`, recording its value (`_cfv`) and its code position (`_cfp`), and the next operator, seeing `_cfo` armed and a
literal after it, rewinds the code to `_cfp` and emits the folded constant. Unary `-` (on anything but a
literal) and unary `~` parse their operand as a factor — which arms `_cfo` with the OPERAND's value — then emit the
negation / complement after it, and return with `_cfo` still armed. The following operator folds the operand's
value with the literal and discards the negation: `-K + 10` folds `5 + 10`, `~5 * 2` folds `5 * 2`. A literal
operand (`-5`) takes a separate path that emits the negated constant, which is why `-5 + 10` is right; parentheses
around the unary expression end the factor and disarm the fold.

## Reproduction

`docs/development/issues/repros/2026-10-10-unary-minus-and-not-folded-over-by-literal-operator.cyr`:

```cyrius
include "lib/syscalls.cyr"
enum E { K = 5; }
var fails = 0;
fn chk(got, want): i64 { if (got != want) { fails = fails + 1; } return 0; }
fn main(): i64 {
    chk(-K + 10, 5);                     # 15
    chk(-E.K + 10, 5);                   # 15
    chk(-K * 2, 0 - 10);                 # 10
    chk(~5 + 10, 4);                     # 15
    chk(~5 * 2, 0 - 12);                 # 10
    chk(~0 + 3, 2);                      # 3
    chk(~K + 1, 0 - 5);                  # 6
    chk(-5 + 10, 5);                     # right
    chk((~5) + 10, 4);                   # right
    chk((-K) + 10, 5);                   # right
    return fails;                        # want 0; exits 7
}
var rc = main();
syscall(60, rc);
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?` — exits 7.

## Root cause

`_PARSE_FACTOR_IMPL` (`src/frontend/parse_expr.cyr:3691`):

- unary minus (`:3709`): the general arm pushes 0, calls `PARSE_FACTOR` (which arms `_cfo` for a constant operand)
  and ends in `_neg_int` (`:1343`: `EMOVCA; EPOPR; ESUBR`) — `_cfo` is never cleared. The f64 / f32 arms beside it
  clear it (`_cfo = 0`); the integer arm does not.
- `~` (`:3737`): `STI; PARSE_FACTOR(S); ENOTR(S); return 0;` — `_cfo` is never cleared.

A second `~` arm later in the same fn (`:5198`, the same three calls) is unreachable behind the first.

## Proposed fix

`_cfo = 0;` after the emit in `_neg_int` and in the `~` arm (better: move the `~` arm into a helper that does it, which
also keeps it off the giant fn's cybs reference budget), and delete the unreachable second `~` arm. Default-pipeline
output changes only for these expressions. Rows: the repro's ten shapes; `-K - 1`, `-K << 1`, `~K & 3`, `-(K) * 2`,
`- -K + 1`; a literal (`~5`), a `const` and an enum constant as the operand; IR=3; the four targets; a literal
operand of `-` (`-5 + 10`) unchanged.

## Consumer-side workaround

Parenthesise the unary expression: `(-K) + 10`, `(~5) + 10`.
