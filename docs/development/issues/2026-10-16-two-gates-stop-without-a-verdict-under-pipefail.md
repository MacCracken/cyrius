# syscall_xlat_generated.sh and removed_symbol_census.sh stop without a verdict under `bash -eo pipefail` (a `grep -c` at a zero count; a `git tag … | head -1` taking SIGPIPE) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.14 platform lane's tree (l6714-platform). Pre-existing: the
lane touched neither file (`git log 2600f67f..HEAD` over both is empty). Filed from the platform lane's review.
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P1; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — a gate defect only. check.sh runs both with `sh` (no pipefail; syscall_xlat_generated.sh has no
`set -e` at all), where every axis runs and the verdict is right; no workflow runs either directly. Under
`bash -eo pipefail` — GitHub's `run:` semantics, and what CLAUDE.md asks every shell gate to be tested under — each
ends early with a non-zero rc and prints neither PASS nor FAIL. Not the same gate as the tools lane's staged
`2026-10-16-lsp-gate-exits-without-a-verdict-under-pipefail.md` (lsp_diagnostics_file_column.sh).
**Affects:** tests/gates/platform/syscall_xlat_generated.sh (line 115 and the same `grep -c` idiom at 147, 160, 173,
195, 204, 266, 308 inside `[ "$(…)" ]`); tests/gates/toolchain/removed_symbol_census.sh (line 54).

## Reproduction

```sh
cd <tree>
sh tests/gates/platform/syscall_xlat_generated.sh; echo "rc=$?"
bash -eo pipefail tests/gates/platform/syscall_xlat_generated.sh; echo "rc=$?"
sh tests/gates/toolchain/removed_symbol_census.sh; echo "rc=$?"
bash -eo pipefail tests/gates/toolchain/removed_symbol_census.sh; echo "rc=$?"
```

```text
PASS syscall_xlat_generated (table re-derives; 0 false positives; catches real ones)
rc=0
  ok: the committed table re-derives byte-identically from the stdlib peers (regenerated under $D, tree untouched)
  ok: axis 1b: `gen_syscall_xlat --help` and a second operand are refused (rc 2, by name), nothing written
rc=1
PASS: removed_symbol_census (0 removed vs 6.7.13, 5 accounted in the ledger, census probe 400 files)
rc=0
rc=141
```

`bash -x` shows where each stops:

```text
# syscall_xlat_generated.sh (axis 2)
++ grep -c 'raw syscall' …/self.err
+ fp=0
+ rm -rf …                                 (the EXIT trap; -e fired on the assignment)
# removed_symbol_census.sh
++ git -C … tag --list '[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname
++ head -1
+ BASE_TAG=6.7.13
+ rm -rf …                                 (the EXIT trap; rc 141, SIGPIPE through pipefail)
```

(The review measured removed_symbol_census at rc 1 on the same tree; whether git dies of SIGPIPE or is still writing
when `head` exits depends on timing — either way the gate ends silent.)

## Root cause

- syscall_xlat_generated.sh:115 — `fp=$(grep -c 'raw syscall' "$D/self.err")`: `grep -c` prints `0` AND exits 1
  when nothing matches, which is the PASSING case, and a plain assignment's status is the command substitution's, so
  `-e` ends the script on success. The `[ "$(grep -c …)" != 0 ]` sites are inside a test, where the substitution's rc
  is discarded — safe as written, but the same idiom.
- removed_symbol_census.sh:54 — `BASE_TAG=$(git tag --list … --sort=-v:refname | head -1)`: `head -1` exits after the
  first line, git is killed by SIGPIPE (141) on its next write, and `pipefail` makes the pipeline (so the assignment)
  fail; the file's own `set -eu` then ends it.

## Proposed fix

`fp=$(grep -c 'raw syscall' "$D/self.err" || true)`; take the newest tag without a pipe (`git tag --list …
--sort=-v:refname | sed -n 1p` still pipes — use `git for-each-ref --count=1 --sort=-v:refname --format='%(refname:short)'
'refs/tags/[0-9]*.[0-9]*.[0-9]*'`, or `|| true` on the pipeline). Row: both gates PASS under `bash -eo pipefail` as
well as `sh`; a mutant that re-introduces a raw-syscall false positive still turns axis 2 RED under both.
