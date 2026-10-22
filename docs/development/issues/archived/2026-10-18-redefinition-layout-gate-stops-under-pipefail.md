# redefinition_layout_and_enum_over_var.sh stops without a verdict under `bash -eo pipefail` (a `grep -c` at a zero count) — RESOLVED

> ✅ **RESOLVED in v6.7.16** (TL-3, `96680cfb9`, with TL-4, `2ffdffa14` — no decision needed: gate-only. `expect()`'s count is `n=$(grep -c "$3" "$T/e" || true)`, the proposed fix, so the filed `bash -eo pipefail` run reaches `PASS … 29 rows`, rc 0 (it stopped at sp_same with no verdict); `sh` is unchanged. TL-4, met in this issue's own mutation row, catches the status of the diagnostic tail, the compile and the line-5 row's pipes, so the red rows reach a verdict too: sp_same expecting 1 → FAIL 2 red, 27 green under both shells (bash stopped after one FAIL row); sp_same made not to compile → FAIL 2 with its error lines (bash printed nothing). The gate joins gates_verdict_under_pipefail.sh's GATES, so check.sh runs it under `bash -eo pipefail` as well as `sh`. Mutations: the `|| true` dropped → gates_verdict_under_pipefail RED ("exited 1 with STOPPED"); sp_same expecting 1 → RED under sh and bash. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 frontend lane (l6715-frontend at 6593fbf1d). Pre-existing:
the lane did not touch the gate (`git log b2e1f4c48..HEAD` over it is empty), and with the slot-open compiler
(`CYCC=<b2e1f4c48's build/cycc>`) it stops the same way.
**Placement:** 6.7.16 — Break 2, repair 6 (tools lane, wave 1, unit T1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a gate defect only. check.sh runs it with `sh`, where all 29 rows run and the verdict is right.
Under `bash -eo pipefail` (GitHub's `run:` semantics, which CLAUDE.md asks every shell gate to be tested under) it
ends with rc 1 and prints neither PASS nor FAIL.
**Affects:** tests/gates/frontend/redefinition_layout_and_enum_over_var.sh, `expect()` (line 88).
**Same class as:** issues/archived/2026-10-17-default-named-args-gate-stops-under-pipefail.md (fixed in this lane, 51cf4b58a)
and issues/archived/2026-10-16-two-gates-stop-without-a-verdict-under-pipefail.md (platform lane) — different gate.

## Reproduction

```sh
cd <the tree>
sh tests/gates/frontend/redefinition_layout_and_enum_over_var.sh; echo "rc=$?"
# PASS redefinition_layout_and_enum_over_var: 29 rows — a re-laid-out struct/union and an enum over a zero/computed global are reported on x86 and aarch64, the benign shapes stay silent
# rc=0
bash -eo pipefail tests/gates/frontend/redefinition_layout_and_enum_over_var.sh; echo "rc=$?"
# (no PASS / FAIL line)
# rc=1
bash -x -eo pipefail tests/gates/frontend/redefinition_layout_and_enum_over_var.sh 2>&1 | tail -4
# ++ grep -c 'redefined with a different layout' .../e
# + n=0
# + rm -rf .../tmp.XXXXXX
```

## Root cause

`expect()` reads its count with `n=$(grep -c "$3" "$T/e")`. At a zero count `grep -c` prints 0 and exits 1; under
`set -e` a failing command substitution in an assignment ends the script, at the first zero-count row (`sp_same`,
`"$LAY" 0`, on the x86 leg). The gate itself sets only `set -u` (line 26), so under `sh` the assignment's status is
ignored.

## Proposed fix

`n=$(grep -c "$3" "$T/e" || true)` — `grep -c` has already printed the count, so the value is unchanged. Rows: the gate
gives the same 29-row PASS under `sh` and under `bash -eo pipefail`; a needle count mutated (e.g. `sp_same` expecting 1)
is RED under both.
