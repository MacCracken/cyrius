# `regression_ssh_remote_exec_capture`'s output-fd lift (6.7.15) is pinned by no row and no static axis: removing it leaves every row and gate green — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-19 on the 6.7.15 libfix4 lane (branch l6715-libfix4, after 2941e7412),
x86_64 Linux.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 libfix4 review; placed at its integration, 2026-10-19 — the user: what 6.7.15 files goes to repair 6; a lib/ defect: with 6.7.16's first items) — never 7.x.
**Severity:** Low — a coverage gap, not a live defect: the lift is in the code today; nothing stops it being lost.
**Found:** by the 6.7.15 libfix4 review of the fix for
`issues/archived/2026-10-18-regression-output-fd-overwritten-by-stdin-redirect.md`.

## Reproduction

2941e7412 made every `lib/regression.cyr` child that redirects a parent-opened `out_fd` call `_regression_lift_fd`
(fcntl `F_DUPFD` 3, the old number closed) before its stdin redirect, so a caller started with fd 0 closed (which
opened `out_fd` AT 0) does not have the redirect overwrite it. In `regression_ssh_remote_exec_capture` that is:

```cyr
        var ofd = _regression_lift_fd(out_fd);   # a closed fd 0 put it AT 0. CHANGELOG [6.7.15]
```

Mutation in a scratch copy of `lib/`: that line replaced by `var ofd = out_fd;`. Every tcyr that touches the verbs
or the lift still passes:

```text
regression_capture_stdin_closed  compile=0 exit=0 62 passed, 0 failed (62 total)
process_capture_closed_std_fds   compile=0 exit=0 44 passed, 0 failed (44 total)
regression_wait_unobserved       compile=0 exit=0 24 passed, 0 failed (24 total)
regression_capture_exclusive     compile=0 exit=0 22 passed, 0 failed (22 total)
```

and (per the review) every gate, including `tests/gates/toolchain/regression_wait_status_checked.sh`, stays green.

## Root cause

The verb execs a hard-coded `/usr/bin/ssh` (then `/bin/ssh`) and needs a reachable host, so
`tests/tcyr/crossos/regression_capture_stdin_closed.tcyr` covers only `regression_exec_in_dir3[_env]` and
`regression_pipe_to_bin_capture` (the filing allows the ssh verb no runtime row). Nothing static checks the shape
either.

## Fix direction

A static axis (in `tests/gates/toolchain/regression_wait_status_checked.sh` or a neighbour): every
`lib/regression.cyr` fork child that redirects a parent-opened `out_fd` calls `_regression_lift_fd` on it before its
first `_regression_redirect(…, 0)`; with a detector self-test and a mutation (the line above removed) that goes RED.

## Acceptance

Removing the lift from `regression_ssh_remote_exec_capture` (or from any of the three children that carry it) turns
a gate RED, naming the verb.
