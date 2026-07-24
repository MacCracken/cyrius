# `cyrius audit` and `cyrius capacity` skip the manifest dep-prepend — RESOLVED

> **✅ RESOLVED in v6.4.73** (`cbt/cyrius.cyr`, `cbt/build.cyr`, `cbt/commands.cyr`, `src/main.cyr`,
> `src/main_win.cyr`; CHANGELOG [6.4.73]).

**Discovered:** 2026-07-23, reported by the **stiva** agent ("cyrius audit is broken for this project").
**Severity:** **High** — `audit` produced a categorically wrong verdict on a healthy project, and
`capacity --check` was a **green placebo** (reported "ok" for a project sitting at 90 % / 92 %).
**Affects:** cycc/cyrius **≤ 6.4.72**. `capacity`'s placebo leg dates to the command's introduction.

## Summary

Two of the three tools a consumer reaches for to ask *"is my project healthy?"* were compiling
project sources **without the manifest's stdlib includes**, because neither command was in the
`_auto_deps()` gate in `cbt/cyrius.cyr`.

Measured on stiva 3.0.6 (10 deps, 83 locked), same tree, same moment:

| Command | Result |
|---|---|
| `cyrius test` | **202 passed, 0 failed** (exit 0) |
| `cyrius audit` → tests stage | **0 passed, 5 failed** — every test a "compile error" |
| `cyrius capacity --check` | **"ok (all caps under 85%)"** (exit 0) — actual: fn_table 90 %, identifiers 92 % |

The audit failures were a wall of `warning: undefined function 'alloc' / 'strlen' / 'sys_write' /
'vec_new' / 'str_from' / 'json_v_obj_new'` — i.e. the entire stdlib and every dep bundle.

## Root cause

`cbt/cyrius.cyr` gates dep resolution on a hard-coded command list. `_auto_deps()` is what populates
`_dep_includes`, which `compile()` reads to prepend `include "lib/…"` lines to a temp source. The list
covered `build/run/test/tests/bench/fuzz/soak/smoke/check` — **`audit` and `capacity` were never
added**. `_audit_sweep()` calls `cmd_tests()` and `cmd_bench()` internally, both of which assume the
prepend already happened.

**This is the third instance of the same bug class**, and the comment block right above the gate
documents the first two: `fuzz` was added at **v5.7.21** for exactly this reason ("downstream fuzz
harnesses had to declare every stdlib include by hand or fail with `undefined function`"), and
`soak`/`smoke` at **v5.7.38** citing the v5.7.21 fix.

`capacity` had a **second, independent** defect: `cmd_capacity` forks cycc directly (it needs
`CYRIUS_STATS=1` in the child env) rather than going through `compile()`, so adding it to the gate
alone would not have helped — it never consulted `_dep_includes` at all.

### Why it stayed invisible in-repo for a year

**250 of cyrius's own 251 `tests/tcyr/*.tcyr` files self-declare their includes**, so the in-repo
corpus never needed the auto-prepend and `cyrius audit` looked fine here. A textbook "found by ports"
gap — the same shape as the macOS self-host rot: the check we trusted was not exercising the path
that mattered.

## The `capacity` placebo (the more dangerous half)

`cyrius capacity --check` is the tool whose *entire purpose* is to warn before a compiler table fills.
Three compounding defects made it certify the opposite:

1. **No dep prepend** (above) → the compile aborted with `undefined variable 'Backend'`.
2. **The child's exit status was never checked.** `sys_waitpid` wrote into `status_buf` and the result
   was discarded.
3. **Zero parsed stats lines was treated as zero tables over threshold.** The compile died before the
   stats block, `hits` stayed 0, and the fall-through printed `ok (all caps under 85%)` and returned 0.

A fourth latent defect would have bitten as soon as (1) was fixed: the stderr capture buffer was
**8 KiB**, and the stats block prints at the *end* of a compile. stiva emits ~20 KB of duplicate-fn
warnings first, so the stats lines were the first thing truncated away.

## Fix

- **`cbt/cyrius.cyr`** — `audit` and `capacity` join the `_auto_deps()` gate.
- **`cbt/build.cyr`** — the prepend block factored out of `compile()` into `_materialize_source(source)`
  so there is exactly ONE implementation; `capacity` calls it instead of duplicating it (duplication
  would just have set the two copies up to drift).
- **`cbt/commands.cyr`** — `cmd_capacity` now compiles the materialized source, **checks
  `WIFEXITED`/`WEXITSTATUS`** and fails loud on a failed compile, **hard-fails when zero stats lines
  were parsed** ("cannot certify caps" — not a pass), and reads **1 MiB** of stderr instead of 8 KiB.
- **`src/main.cyr` / `src/main_win.cyr`** — the `CYRIUS_STATS=1` meter's `code_size` denominator was a
  stale `1048576`; the code buffer became the 64 MiB growable off-heap region at v6.4.49 and
  `_capacity_warnings` was updated but this meter was not, so a healthy stiva build reported
  `code_size: 2822736 / 1048576` = **269 %** — and `capacity --json` published that ratio.

## Verification

- stiva `cyrius audit` tests stage: `0 passed, 5 failed` → **`5 passed, 0 failed`** (202 + 116 asserts).
  Audit still exits 1, now on stiva's *genuine* fmt/lint/docs findings — real signal instead of noise.
- stiva `cyrius capacity --check`: `ok (all caps under 85%)` → **`3 table(s) at >=85% -- failing`**.
- Self-host fixpoint + `seed-derive-cycc.sh` green (the `src/` change is in the seed chain).

## Residual (not fixed here)

**Only 2 of the 7 compiler forks emit the `CYRIUS_STATS=1` block at all** — `src/main.cyr` and
`src/main_win.cyr`. The aarch64, Mach-O and cx forks emit no stats, so `cyrius capacity` cannot report
on them. This is the same gap `_capacity_warnings` closed for *warnings* at v6.4.50, one layer up. With
the placebo guard in place these now fail loud ("no capacity lines parsed") rather than certifying
falsely, which is the correct interim behavior.
