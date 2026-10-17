# default_named_args_checked.sh stops without a verdict under `bash -eo pipefail` in its SC-lsp section (a `grep -c` over two files at a zero count) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend at 7b32fd5b) and on a
`git archive` copy of the slot-open tree (2600f67f): both stop at the same line. Pre-existing: the line came in with
50a981eb (6.7.11 tools, 2026-10-13); the frontend lane's edits to this gate (R24c / R24e / U rows) are not involved.
Not one of the gates already staged for the same idiom (the platform lane's
2026-10-16-two-gates-stop-without-a-verdict-under-pipefail.md: syscall_xlat_generated.sh, removed_symbol_census.sh;
the tools lane's 2026-10-16-lsp-gate-exits-without-a-verdict-under-pipefail.md: lsp_diagnostics_file_column.sh).
Met by the 6.7.14 frontend review.
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend review, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** Low — a gate defect only. check.sh runs the gate with `sh` (no pipefail), where every row runs and the
verdict is right. Under `bash -eo pipefail` — GitHub's `run:` semantics, and what CLAUDE.md asks every shell gate to
be tested under — it ends after SC-dpz with rc 1 and prints neither PASS nor FAIL; the SC-lsp, SC-ta and later rows
never run.
**Affects:** tests/gates/frontend/default_named_args_checked.sh line 782 (slot-open: line 775).

## Reproduction

```sh
cd <the tree>
sh tests/gates/frontend/default_named_args_checked.sh > /dev/null 2>&1; echo "rc=$?"
# rc=0   (PASS: default_named_args_checked — ...)
bash -eo pipefail tests/gates/frontend/default_named_args_checked.sh > dn.log 2>&1; echo "rc=$?"; tail -1 dn.log
# rc=1
#   ok   SC-dpz: a poison-mode cyrdoc over the long signature, the long name and 16 fillers: no redzone touched (rc 0 / --check rc 1)
```

`bash -x -eo pipefail` ends at:

```text
++ awk -F: '{ s += $2 } END { print s + 0 }'
+ ni=0
+ _wine_down
```

## Root cause

```sh
ni=$(grep -c '^[0-9]*:i64=6$' "$T/st/sc/doc.tok" "$T/st/sc/shp.tok" | awk -F: '{ s += $2 } END { print s + 0 }')
```

On a passing run no token matches, so `grep -c` over the two files prints `…:0` twice and exits 1; pipefail makes
the pipeline (and the substitution) fail, and `set -e` ends the gate at the assignment (the EXIT trap's `_wine_down`
runs next).

## Proposed fix

`|| true` inside the substitution, as the neighbouring `ntok=$(… | grep -c . || true)` line already has:
`ni=$(grep -c '^[0-9]*:i64=6$' "$T/st/sc/doc.tok" "$T/st/sc/shp.tok" | awk -F: '{ s += $2 } END { print s + 0 }' || true)`
— or `{ grep -c … || true; }` before the awk. Rows: the gate under both `sh` and `bash -eo pipefail`, same verdict.
