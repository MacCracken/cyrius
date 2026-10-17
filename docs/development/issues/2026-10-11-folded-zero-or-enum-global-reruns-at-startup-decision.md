# A top-level global whose constant initializer folds to ZERO, or folds through an enum constant, re-runs the expression at startup: `var R = INT_MIN % -1;` kills x86 and cx (136) and is 0 on aarch64 — OPEN (a decision)

**Status:** 🟡 **OPEN — a decision for the user.** Raised by the 6.7.9 critical lane (bite 18, the cx folded-global
re-evaluation), which made cx bake what the native targets bake and left these two shapes, documented as kept by
6.6.20. Verified 2026-10-11 against the merged 6.7.9 tree (`build/cycc` @ 27220379, 2,057,736 B, its `cycc_aarch64`
under qemu and its `cycc_cx` under cxvm): repro A exits 136 (SIGFPE) on x86_64 and cx and 5 on aarch64; repro B 136
on x86_64 and cx and 8 on aarch64 (Q = INT_MIN); the non-zero literal control C exits 10 everywhere.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (frontend lane, wave 1, unit F3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D11 — (b) Use the folded value.
**Discovered:** 2026-10-11 during 6.7.9's
[cx folded-global fix](archived/2026-10-09-cx-folded-global-reevaluated-int-min-div.md).
**Severity:** Low — a program must spell a trapping division in a global initializer; but the same source crashes on
two targets and runs on a third.
**Affects:** cycc 6.6.20 (the fold's −1 rewrite; the store kept, documented) – 6.7.9; x86_64 (ELF, Mach-O, PE) and cx
trap, aarch64 does not (`sdiv` does not fault).

## Summary

6.6.20 taught the constant folder that `INT_MIN / -1` is `INT_MIN` and `INT_MIN % -1` is 0, and baked the folded
value into the var image for a literal-only scalar that folds to a NON-ZERO value and for array-initializer elements.
Two shapes keep the run-time store instead: a scalar that folds to ZERO (BSS is already zero, so nothing is baked) and
a scalar whose expression names an enum constant. The deferred initializer replay then RE-EVALUATES the expression at
startup — it does not store the folded value — so the division the folder proved safe runs on the hardware: x86
`idiv` and cxvm's division trap on INT_MIN / −1, aarch64's `sdiv` returns the wrapped result. 6.6.20's CHANGELOG
records it ("a scalar that keeps its runtime store … still runs the division at startup and traps there on x86, as
any runtime INT_MIN / −1 does"). 6.7.9 brought cx's non-zero folds in line with the native targets; these two shapes
trap on cx as on x86.

## Reproduction

```cyrius
# A — folds to zero
var R = (0 - 0x7FFFFFFFFFFFFFFF - 1) % (0 - 1);
syscall(60, R + 5);
```
```cyrius
# B — folds through an enum constant
enum CfMax { CF_MAX = 0x7FFFFFFFFFFFFFFF; }
var Q = (0 - CF_MAX - 1) / (0 - 1);
syscall(60, (Q >> 63) + 7);
```
```cyrius
# C — control: folds to a non-zero literal-only value (baked)
var Q = (0 - 0x7FFFFFFFFFFFFFFF - 1) / (0 - 1);
syscall(60, (Q >> 63) + 9);
```

| | x86_64 | aarch64 (qemu) | cx (cxvm) |
|---|---|---|---|
| A | 136 | 5 | 136 |
| B | 136 | 8 | 136 |
| C | 10 | 10 | 10 |

## The decision

- **(a) Keep it (6.6.20's documented behaviour):** the replay re-runs the expression; a trapping division traps on
  x86 / cx at startup, as the same division in a statement does.
- **(b) Store the folded value:** when the folder produced a value, the replay stores THAT value (or, for a zero,
  stores nothing over the zero BSS), so A is 5 and B is 8 on every target — the one reading in which the three targets
  agree. It is the same lever as the const-init issue's item 1 (skip or replace the replay's store of a baked entry),
  which is why it is asked with it; it changes x86 and cx from a crash to a value. (The lane reported the shape and made
  no recommendation.)

Rows: under (b), A and B (and a `%` twin of B) join `tests/tcyr/crossos/const_fold_int_min_div.tcyr`, which keeps
them out today because they trap, run on x86_64, qemu-aarch64, cxvm (`cx_crossos_rows_run.sh` R12) and PE (wine);
under (a), the guide states the startup trap and a gate pins 136 on x86_64 / cx and the value on aarch64.
