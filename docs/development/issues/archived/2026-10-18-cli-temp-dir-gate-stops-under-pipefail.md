# cli_temp_dir_no_leak.sh stops without a verdict under `bash -eo pipefail`: a `kill` of a stand-in that has already exited ends the run — RESOLVED

> ✅ **RESOLVED in v6.7.16** (TL-5, `c43aee514` — no decision needed: gate-only. The filed stop, g8_run's `kill -KILL` of a stand-in the CLI had already stopped (line 847), and the five stops measured behind it — the real-clone row's kill (927), a killed FIFO holder's `wait` returning 143 (1019), `$(ls … | head -1)` of a directory not yet made (1049, rc 2) and the g9p block's wait and kill (1057, 1063) — each carry `|| true`, as do six kill-after-`kill -0` races of the same shape (612, 736, 842, 929, 979, 1151). Under `bash -eo pipefail` the gate reaches PASS, 166 ok, rc 0 (it stopped after 107); under `sh` unchanged. In place of the issue's optional self-re-exec, the gate joins gates_verdict_under_pipefail.sh's GATES, so check.sh runs it under `bash -eo pipefail` too. Mutations, one guard dropped at a time: 847 → STOPPED (107 ok), and 927, 1019, 1049, 1057, 1063 each stop the run; with 847 dropped gates_verdict_under_pipefail goes RED. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 infratools lane (l6715-infratools at 1e298f122, x86_64
Linux) and on the lane base b2e1f4c48, a scratch `git archive` with its build/cyrius rebuilt from its own cbt/. Both
stop at the same row. The defect predates 6.7.15. The lane's g9p block (73249ddb5) adds two more lines of the same
shape. Filed from the 6.7.15 infratools lane's review.
**Placement:** 6.7.16 — Break 2, repair 6 (tools lane, wave 1, unit T1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low. This is a gate defect only. check.sh runs the gate with `sh`, which has no `-e`; the gate sets only
`set -u`. Under `sh` every axis runs and the verdict is right (PASS, 166 ok on the lane tree). Under
`bash -eo pipefail` the gate ends early with rc 1 and prints neither PASS nor FAIL. That is GitHub's `run:` semantics,
and CLAUDE.md asks every CI shell-loop gate to be tested under it. The issue is not the same gate as
`archived/2026-10-16-two-gates-stop-without-a-verdict-under-pipefail.md` (syscall_xlat_generated / removed_symbol_census),
`archived/2026-10-16-lsp-gate-exits-without-a-verdict-under-pipefail.md` (lsp_diagnostics_file_column), or the frontend lane's
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
