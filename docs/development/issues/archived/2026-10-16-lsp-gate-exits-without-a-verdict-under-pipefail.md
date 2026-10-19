# lsp_diagnostics_file_column.sh exits rc 1 with no verdict under `bash -eo pipefail` (a feeder's write to a server that has exited) — RESOLVED

> ✅ **RESOLVED in v6.7.15** (IT-10, `9476b9be3` — no decision needed (a gate): a feeder's write to a server that has exited takes its own failure (`msg … || true`), and so do `pub` and `serve`, so a late EPIPE is never the verdict and a server that publishes nothing leaves its rows to FAIL by name; the gate re-runs itself under `bash -eo pipefail` when bash is on PATH (`CY_LSP_GATE_INNER=1` keeps the starting shell), so check.sh's `sh` run exercises the semantics CI uses — this file's two proposals. The filed loop now prints PASS with every row run: 5 runs under `bash -eo pipefail`, 3 under `sh`, 3 with `CY_LSP_GATE_INNER=1`, once through `cyrius_check --run-gate` — 22 rows (R0 – R18) each (it stopped after R13 with rc 1 and no verdict). Row: new R0 — a feeder whose reader is gone ends with status 0 in a `bash -eo pipefail` child of its own (deterministic, where the filed stop point is a race); mutation (`msg` without `|| true`) → R0 FAIL 5 / 5, and the filed stop after R13. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — met 2026-10-16 by the 6.7.14 tools lane (unit T3) while adding R16-R18 for
issues/archived/2026-10-15-lsp-loose-file-reports-pin-redirect-of-server-cwd-project.md. Pre-existing: the gate as it stands at
2600f67f (the 6.7.14 plan commit) does the same.
**Placement:** 6.7.15 — repair 5 (infratools lane, wave 1, unit I5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — a gate defect only. check.sh runs the gate with `sh` (no `-e`), where every row runs and the
verdict is right; under `bash -eo pipefail` (GitHub's `run:` semantics, and what the gate's own comment says its
feeders are written for) it stops after R13 with rc 1 and prints neither PASS nor FAIL.
**Affects:** tests/gates/toolchain/lsp_diagnostics_file_column.sh, every `{ trap '' PIPE; start; …; stop; true; } |
serve …` feeder (R1-R18).

## Reproduction

```sh
cd <tree at 2600f67f>
for i in 1 2 3; do bash -eo pipefail tests/gates/toolchain/lsp_diagnostics_file_column.sh > pf$i.log 2>&1
  echo "run $i rc=$? last: $(grep -E '^  (ok|FAIL)' pf$i.log | tail -1 | cut -c1-70) | verdict lines: $(grep -cE '^(PASS|FAIL):' pf$i.log)"; done
```

```
run 1 rc=1 last:   ok: R13 (cycc) the file's own error keeps its own line (1): #@srclin | verdict lines: 0
run 2 rc=1 last:   ok: R13 (cycc) the file's own error keeps its own line (1): #@srclin | verdict lines: 0
run 3 rc=1 last:   ok: R13 (cycc) the file's own error keeps its own line (1): #@srclin | verdict lines: 0
```

The same gate under `sh`: `PASS: lsp_diagnostics_file_column`, rc 0. (With 6.7.14's R16-R18 added, the stop point moved
between runs — once R14, once R18 — so it is timing-dependent, not tied to one row.)

## Root cause

Each feeder is `{ trap '' PIPE; start; open_msg …; stop; true; } | serve …`. The comment above `serve()` says the
`trap ''` and the closing `true` are there so "the server may exit on `shutdown` before the `exit` notification is
written, which is a SIGPIPE the pipeline's status must not read as a failure under `bash -eo pipefail`". Ignoring
SIGPIPE turns the late write into an EPIPE, and under `-e` that failing `printf` ends the brace group with status 1
before `true` runs; `pipefail` then fails the pipeline and `-e` ends the script (its EXIT trap removes `$W`). Minimal
shape:

```sh
bash -eo pipefail -c '{ trap "" PIPE; printf x; sleep 0.2; printf y; true; } | true; echo after'; echo "rc=$?"
# bash: line 1: printf: write error: Broken pipe
# rc=1
bash -o pipefail -c '{ trap "" PIPE; printf x; sleep 0.2; printf y; true; } | true; echo "after (no -e): $?"'
# after (no -e): 0
```

## Proposed fix

Make a feeder's late write non-fatal under `-e` — e.g. `msg … || true` inside the feeders' `stop` (the only writes
that can race the server's exit), or run each feeder as `{ …; } || true` — and add the gate to whatever checks gates
under `bash -eo pipefail`. Row: the gate under `bash -eo pipefail` prints its verdict (PASS) with every row run.
