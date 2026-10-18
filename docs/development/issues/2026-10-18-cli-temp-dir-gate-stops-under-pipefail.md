# cli_temp_dir_no_leak.sh stops without a verdict under `bash -eo pipefail`: a `kill` of a stand-in that has already exited ends the run — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 infratools lane (l6715-infratools at 1e298f122, x86_64
Linux) and on the lane base b2e1f4c48, a scratch `git archive` with its build/cyrius rebuilt from its own cbt/. Both
stop at the same row. The defect predates 6.7.15. The lane's g9p block (73249ddb5) adds two more lines of the same
shape. Filed from the 6.7.15 infratools lane's review.
**Placement:** unplaced — filed from the 6.7.15 infratools review (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low. This is a gate defect only. check.sh runs the gate with `sh`, which has no `-e`; the gate sets only
`set -u`. Under `sh` every axis runs and the verdict is right (PASS, 166 ok on the lane tree). Under
`bash -eo pipefail` the gate ends early with rc 1 and prints neither PASS nor FAIL. That is GitHub's `run:` semantics,
and CLAUDE.md asks every CI shell-loop gate to be tested under it. The issue is not the same gate as
`2026-10-16-two-gates-stop-without-a-verdict-under-pipefail.md` (syscall_xlat_generated / removed_symbol_census),
`2026-10-16-lsp-gate-exits-without-a-verdict-under-pipefail.md` (lsp_diagnostics_file_column), or the frontend lane's
staged `2026-10-18-redefinition-layout-gate-stops-under-pipefail.md`.
**Affects:** tests/gates/toolchain/cli_temp_dir_no_leak.sh. The lines are 847 (`g8_run`), 979 (the g9 helper, inside
an `if`), 1057 and 1063 (the g9p block, new in 6.7.15). The same shape is at b2e1f4c48's line 830.

## Reproduction

```sh
cd <tree>            # the lane tree, or a b2e1f4c48 archive with build/cyrius = cycc(cbt/cyrius.cyr)
sh tests/gates/toolchain/cli_temp_dir_no_leak.sh; echo "rc=$?"
bash -eo pipefail tests/gates/toolchain/cli_temp_dir_no_leak.sh; echo "rc=$?"
```

```text
PASS …                                   (sh: 166 ok rows)
rc=0
…
  ok:   …its private dir is gone (no ls_remote / wt_err left) (0)
  ok:   …the git it was running is stopped (gone)
  ok: a git dep resolves through the stand-in (the real git; anti-vacuous: rc 0, its cache cloned) (0 yes)
rc=1                                     (bash -eo pipefail: 107 ok rows, no PASS / FAIL line; same on b2e1f4c48)
```

`bash -x -eo pipefail` shows the stop, inside the first `g8_run g8f fsck deps`:

```text
+ _gl=2693924
+ '[' -n 2693924 ']'
+ kill -KILL 2693924
+ rm -rf …/tmp.sqGAPXaF29          (the EXIT trap; nothing after it)
```

## Root cause

`g8_run` ends with `[ -n "$_gl" ] && kill -KILL "$_gl" 2>/dev/null`, which kills the stand-in git's `sleep`. By the
time this line runs the stand-in is gone: the CLI's kill handler stopped it, and `g8.cc` already reads `gone`. So the
sleep has usually exited, and `kill` fails with ESRCH. `kill` is the command after the final `&&`, so `-e` does not
exempt it, and the gate ends there. The same unguarded kill or wait of a process that may already have exited appears
at:

- line 979: `echo running > …; kill -KILL "$_g9c" 2>/dev/null` (inside an `if` that has just seen the process
  alive, so it fails only if the process exits in between);
- line 1057: `kill "$k9h" 2>/dev/null; { wait "$k9h"; } 2>/dev/null`. The `wait` returns 143 for the killed holder,
  and nothing guards it;
- line 1063: `[ -n "$_g9c" ] && kill -KILL "$_g9c" 2>/dev/null`.

The gate's other kills already carry `|| true`, for example `[ -n "$_gp" ] && kill -TERM "$_gp" 2>/dev/null || true`.

## Fix

Give each of these lines its own `|| true`, or use an `if … then kill …; fi` form. Then test the gate under
`bash -eo pipefail` as well as `sh`. Optionally the gate can re-run itself under `bash -eo pipefail` when bash is on
PATH, as lsp_diagnostics_file_column.sh does since 6.7.15, so check.sh exercises those semantics too.

The row: the gate prints its verdict under `bash -eo pipefail`, with every row present (166 on the lane tree). A
deterministic row in the style of lsp_diagnostics_file_column's R0 or dce_seed_pass_linear's P0 would run `g8_run`'s
cleanup tail in a `bash -eo pipefail` child against a pid that has already exited, and require the child to go on.
