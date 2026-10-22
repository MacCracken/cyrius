# In an x86 `kernel;` build a float global whose constant initializer mixes an integer or enum operand into f64 arithmetic (`= 1.5 + 1`, `= 1.5 * E.A`) is still a late store — RESOLVED

> ✅ **RESOLVED in v6.7.16** (ZN-4, `f8139264f`, under the user's decision D15 (a), 2026-10-19: in the image from program start. `_gvk_fscan` now takes an integer literal, an integer const, and an enum constant, bare or qualified. The const evaluator computes the mix as the run-time code does: the integer is its raw bits. The "non-f64 right operand" warning is kept by reparsing the entry where the replay parsed it, with its code taken back. The filed repro under `CYRIUS_ELF64_KERNEL=1` exits 100 (was 1), with exactly the two mix warnings at 3:21 / 4:23 and no late-initializer warning; its host build exits 100 (2:21 / 3:23). An earlier read sees the value, and an earlier call's write is kept. These hold on x86_64, aarch64, cx, PE and IR=3. An integer LEFT operand (`1 + 1.5`) and a NaN stay startup stores. Rows: `kmode_enum_initializer_baked.sh` RM (the filed repro verbatim) and RC; `const_init_bake_and_fold.sh` S33 and T9 – T12 (`zone_float_constant_initializer.tcyr` rows 12 – 18, which include the target's run-time bits). Mutations F1 – F5 are recorded in both gate headers. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend, unit F5, after the fix of
issues/archived/2026-10-16-kernel-float-global-constant-not-a-literal-left-late.md), x86_64 (CYRIUS_ELF64_KERNEL=1, run as a
Linux process).
**Placement:** 6.7.16 — Break 2, repair 6 (zone lane, wave 2, unit Z1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D15 — (a) In the image from program start.
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
