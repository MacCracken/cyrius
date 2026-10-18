# In an x86 `kernel;` build a float global whose constant initializer mixes an integer or enum operand into f64 arithmetic (`= 1.5 + 1`, `= 1.5 * E.A`) is still a late store — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F5, after the fix of
issues/2026-10-16-kernel-float-global-constant-not-a-literal-left-late.md), x86_64 (CYRIUS_ELF64_KERNEL=1, run as a
Linux process).
**Placement:** unplaced — filed from the 6.7.15 frontend lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Discovered:** 2026-10-18 by the 6.7.15 frontend lane, unit F5: that issue's surface is "a constant f64 expression (an
f64 const, parentheses, f64 arithmetic of constants)"; F5 bakes exactly those (`_gvk_fx`, its pre-scan `_gvk_fscan`
takes float literals and f64 consts only). An integer or enum operand in the same arithmetic is a kind mix the replay
warns about ("f64 arithmetic with a non-f64 right operand"); baking it would drop that replay — and its warning — under
`_gvk_quiet`, so F5 leaves it to the replay.
**Severity:** Low — a mixed-kind f64 initializer is already warned as suspect; the program reads 0 in a `kernel;` build
and the late-initializer warning names it. The host build (replay before the program) reads the right bits.
**Kind:** platform (x86 kernel builds; the bake is target-independent).

## Reproduction

```cyrius
kernel;
enum E { A = 3; }
var M: f64 = 1.5 + 1;
var N: f64 = 1.5 * E.A;
fn ck(got, want, k): i64 { if (got != want) { syscall(60, k); } return 0; }
ck(load64(&M), 0x3FF8000000000000, 1);
ck(load64(&N), 0x0000000000000004, 2);
syscall(60, 100);
```

```sh
CYRIUS_ELF64_KERNEL=1 build/cycc < r.cyr > r && chmod +x r && ./r; echo $?
# warning:<source>:3:21: f64 arithmetic with a non-f64 right operand
# warning:<source>:3:5: in a kernel build the initializer of 'M' runs after the top-level program: ... (use a constant, ...)
# warning:<source>:4:23: f64 arithmetic with a non-f64 right operand
# warning:<source>:4:5: in a kernel build the initializer of 'N' runs after the top-level program: ...
# exit 1   (M reads 0)
# the same file without `kernel;`: exit 100 (the replay computes 1.5 + the integer's bits as a binary64 subnormal)
```

## Root cause

`_gvk_fscan` (src/frontend/parse_decl.cyr) accepts only float literals and f64 consts as operands, so the mix never
reaches the const evaluator (`_ce_binop` would compute it as the run-time path does: the left operand's kind picks
f64). Baking it is easy; the open question is the warning: `_gvk_quiet` drops a baked entry's replay, and the mix
warning is the replay's (PARSE_TERM / PEXPR). A fix either bakes the value and keeps the replay running for its
warning (a baked entry that is not dropped — no late warning, since `_gvk_left` does not name a baked scalar), or gives
the mix warning from the bake.
