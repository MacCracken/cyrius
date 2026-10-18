# stdlib_modules_self_sufficient.sh stops after axis 4 with rc 42 under `bash -eo pipefail` (axis 5's probe exit trips `set -e`) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 stdlib lane's tree (l6714-stdlib) and on a `git archive`
copy of its base f133fb2f3 alike. Pre-existing: the stdlib lane's only edit to the gate is axis 7's `NF_LINE` and
comments (D55, 3335e1165); the stop is in axis 5 and reproduces on the base unchanged. Filed from the 6.7.14 stdlib
review.
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P1; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — a gate defect only. The check driver (programs/checks/main.cyr `_gate(…,
"tests/gates/toolchain/stdlib_modules_self_sufficient.sh")`) runs it with `sh` (no `-e`), where all 7 axes run and the
verdict is right. Under `bash -eo pipefail` — GitHub's `run:` semantics, and what CLAUDE.md asks every shell gate to be
tested under — it ends right after the axis-4 line with rc 42 and prints neither PASS nor FAIL, so a CI step running it
that way reads RED with no FAIL line. Not the same gate as the platform lane's staged
`2026-10-16-two-gates-stop-without-a-verdict-under-pipefail.md` (syscall_xlat_generated.sh, removed_symbol_census.sh)
nor the frontend lane's `2026-10-17-default-named-args-gate-stops-under-pipefail.md`.
**Affects:** tests/gates/toolchain/stdlib_modules_self_sufficient.sh:359 (`_run_probe`, axis 5).

## Reproduction

```sh
cd <tree>            # the lane tree, or a git archive of f133fb2f3
sh tests/gates/toolchain/stdlib_modules_self_sufficient.sh; echo "rc=$?"
bash -eo pipefail tests/gates/toolchain/stdlib_modules_self_sufficient.sh; echo "rc=$?"
```

```text
…
  ok: axis 7: cx refuses tls tls_native sigil by name; lib/thread.cyr runs on cxvm (mutex no-op, thread_create fails honestly, thread_join declines, no SYS_FUTEX)
PASS: stdlib_modules_self_sufficient (7 axes; axis 2, PENDING, retired 6.6.19)
rc=0
…
  ok: axis 4: linux 87/113 (floor 87); agnos 88/113 (floor 88); pe 87/113 (floor 87); macho 88/113 (floor 88); cx 80/110 (floor 72; out of scope: tls tls_native sigil); aarch64 87/113 (floor 87);
rc=42
```

`bash -x -eo pipefail` shows where it stops (base f133fb2f3):

```text
+ chmod +x …/p_io
+ cd …
+ ./p_io
+ rm -rf …            (the EXIT trap: -e fired on the subshell's exit 42)
```

## Root cause

`_run_probe` (axis 5) runs each probe as `( cd "$D" && "./p_$1" > "p_$1.out" 2>&1 < /dev/null ); prc=$?`. Every
axis-5 probe exits NON-ZERO on success by design — the exit code is one bit per call through an include (the first,
`io`, must exit 42). A subshell that exits non-zero as a simple command trips `-e` before `prc=$?` reads it, so under
`set -e` the first passing probe ends the script with the probe's own exit code.

## Fix shape

Capture the status in a way `-e` does not act on, as the neighbouring gates do: `prc=0; ( cd "$D" && … ) || prc=$?`.
Then confirm the gate passes all 7 axes under both `sh` and `bash -eo pipefail`.
