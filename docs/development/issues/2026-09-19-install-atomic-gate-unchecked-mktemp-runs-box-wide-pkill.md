# `install_atomic_over_running_binary.sh`: an unusable TMPDIR gives a vacuous SKIP (rc 0) and an EXIT trap that runs a BOX-WIDE `pkill -f /bin/victim` — OPEN

**Status:** 🟡 open — found during 6.6.6 bite 12 (review of the gate-wide temp-dir audit);
reconfirmed at the bite-12 tree with `pkill` shimmed (the real one was never run).
**Placement:** unpinned — 6.x-line backlog (the next repair batch).
**Discovered:** 2026-09-19
**Severity:** Medium — two defects on one unchecked line: the gate passes vacuously, and it signals
processes it does not own. Two check.sh runs on one box (concurrent worktrees, CI matrix on one
runner) can kill each other's `victim` mid-axis.
**Affects:** `tests/gates/toolchain/install_atomic_over_running_binary.sh` since v6.6.1.

## Reproduction (pkill SHIMMED — do not run this gate with a broken TMPDIR on a shared box)

```sh
P=$(mktemp -d); printf '#!/bin/sh\necho "pkill $*" >> %s/calls.log\n' "$P" > "$P/pkill"; chmod +x "$P/pkill"
PATH="$P:$PATH" TMPDIR=/nonexistent sh tests/gates/toolchain/install_atomic_over_running_binary.sh; echo rc=$?
cat "$P/calls.log"
```

Actual:

```
SKIP install_atomic_over_running_binary: no /bin/sleep
rc=0
pkill -f /bin/victim
```

Expected: `FAIL: … mktemp -d failed`, non-zero exit, and no `pkill` at all (or one scoped to a
directory the gate created).

## Root cause

Line 25: `T=$(mktemp -d); trap 'pkill -f "$T/bin/victim" 2>/dev/null; rm -rf "$T"' EXIT` — with
`T` empty the pattern is `/bin/victim`, which matches every OTHER run's `"$T/bin/victim"`. Then
`cp /bin/sleep "/bin/victim"` fails (not root) and is misreported as `SKIP …: no /bin/sleep`
(line 29), exit 0.

## Proposed fix

Check `mktemp -d` (`T=$(mktemp -d) && [ -d "$T" ] || { echo FAIL…; exit 1; }`) BEFORE installing
the trap; kill the victim by the PID the gate started (`$!`), not by pattern; make the SKIP message
say what actually failed.

## Acceptance criteria

- With `TMPDIR=/nonexistent` the gate FAILs and the shimmed `pkill` log is empty.
- A normal run still reproduces ETXTBSY and passes; the victim is reaped by PID.
