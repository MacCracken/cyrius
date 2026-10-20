# tests/gates/frontend/stack_enum_lossy_context.sh exits 33 with no output under `bash -eo pipefail` — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs review while running the lane's touched gates under
`bash -eo pipefail` (CLAUDE.md § Verification habits: shell-loop gates must hold under it). Pre-existing: the same rc 33
and empty log with the slot-open compiler (480de63eb's build/cycc as `CYCC=`) and with the lane's. The structs lane does
not touch this gate. `sh` (how check.sh drives it, `_chk_gate`) passes, so check.sh is green. Not repaired in the lane:
the fix-up was tried and is not one line (two bare status captures, then six `$(grep -c ..)` captures each trip
`set -e` in turn), so filed.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs review, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16") — never 7.x.
**Severity:** Low — gate hygiene. The gate is `sh`-driven by check.sh, so no red row is hidden today; under
`bash -eo pipefail` (a CI-style shell) it aborts at its first row whose program exits non-zero by design, printing
nothing, which reads as a silent failure, not a named one. Not a security id (the project's own test script).
**Kind:** tooling (test gate).

## Reproduction

```
$ cd <tree> && bash -eo pipefail tests/gates/frontend/stack_enum_lossy_context.sh; echo "rc=$?"
rc=33
# no output at all
$ sh tests/gates/frontend/stack_enum_lossy_context.sh; echo "rc=$?"
PASS stack_enum_lossy_context: lossy binds refused on stack enums (bare ctor, forwarding wrapper) · ...
rc=0
$ CYCC=<480de63eb's build/cycc> bash -eo pipefail tests/gates/frontend/stack_enum_lossy_context.sh; echo "rc=$?"
rc=33
```

`bash -x` shows the abort at axis 3, `accept "SOk/SErr propagate through ? with the payload intact" axis3 33` (line
101): the program exits 33 by design and the helper runs it as a bare command.

## Root cause

The gate's status captures are not `set -e`-safe:

- line 72 (`accept`): `chmod +x "$T/p"; "$T/p"; got=$?` — a row whose program exits non-zero by design (33 at axis 3)
  aborts the script before `got=$?` runs. Line 1039 has the same shape (`"$T/w16"; got=$?`).
- with both of those made `got=0; "$T/p" || got=$?` (tried in the lane tree, then reverted), the next abort is line 401,
  `UNDEF=$(grep -c "undefined function" "$T/w.err")`: `grep -c` exits 1 on a zero count, which is the row's expected
  answer. The same shape is at lines 613, 860, 1258 and 1761 (`_n=$(grep -c '^error' ..)`); line 1401 already has
  `|| true`.

## Fix shape

Make each capture `set -e`-safe (`got=0; prog || got=$?`; `$(grep -c .. || true)`), then run the gate under
`bash -eo pipefail` to the end and under `sh`, both PASS, with the same row count; a mutation (one row's expected value
changed) must still go RED with its row named under both shells.
