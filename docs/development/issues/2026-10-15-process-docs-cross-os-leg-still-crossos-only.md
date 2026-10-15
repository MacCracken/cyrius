# Process docs still describe the release gate's cross-OS leg as the crossos subset, with the full corpus opt-in — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.12 windows lane's review (2026-10-15). The lane could not edit either
file (both are the user's rules / process files).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (windows lane; filed from the 6.7.12 windows lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** Low — documentation drift in the process files; the gate itself is right.
**Affects:** `CLAUDE.md` (Release Gate, step 4), `docs/development/cycle-discipline.md` (closeout checklist item 4
and the paragraph under it).

## Summary

From 6.7.12 (D8, the user, 2026-10-15: "ecb / ach / pi full corpus now, cass when its triage reaches zero") the
release gate's step 4 runs the WHOLE tcyr corpus on every host in `scripts/cross-os-selfhost.sh`'s `CO_FULL_HOSTS`
— `ecb ach pi` after the windows lane's review fix (pi from 279b57fc) — and the `tests/tcyr/crossos/` subset on
cass only. Two process files still say otherwise:

- `CLAUDE.md`, Release Gate step 4: "**Cross-OS self-host** — ecb · ach · cass · pi on REAL hardware (`SELFHOST_OK` +
  the `tests/tcyr/crossos/` suite)."
- `docs/development/cycle-discipline.md:76` (checklist item 4): "each `SELFHOST_OK` **and** `tests/tcyr/crossos/`
  `LIBTEST_OK` on REAL hardware", and `:83-85`: "`CYRIUS_CROSS_OS_FULL=1` runs the whole corpus instead (opt-in: ~75 s
  on ecb, and the blind region still holds known platform gaps, so defaulting to full would wedge every release behind
  a separate arc)."

## Reproduction

```
$ grep -n 'CO_FULL_HOSTS=' scripts/cross-os-selfhost.sh
151:CO_FULL_HOSTS="ecb ach pi"
$ grep -n 'crossos/. suite' CLAUDE.md
117:4. **Cross-OS self-host** — ecb · ach · cass · pi on REAL hardware (`SELFHOST_OK` + the `tests/tcyr/crossos/` suite).
$ sed -n 83,85p docs/development/cycle-discipline.md
`CYRIUS_CROSS_OS_FULL=1` runs the whole corpus instead (opt-in: ~75 s on ecb, and the blind
region still holds known platform gaps, so defaulting to full would wedge every release behind
a separate arc).
```

## Fix

The user's edit (no agent edits a rules file): step 4 names the full corpus on the `CO_FULL_HOSTS` hosts and the
crossos subset elsewhere (or simply "the corpus `cross-os-selfhost.sh` selects for the host"); cycle-discipline's item
4 and paragraph say the same and drop the "opt-in … would wedge every release" rationale, which D8 retired.
