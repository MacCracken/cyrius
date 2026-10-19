# A capture verb killed mid-capture leaves its `<base>/audit_x[ca]_<pid>[.N]` file behind for ever: nothing reaps it, and since CYRIUS-2026-0036's O_EXCL a later process with the same pid skips the name instead of reusing it — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-19 on the 6.7.15 libfix4 lane (branch l6715-libfix4, after unit L6 /
CYRIUS-2026-0036's fix 7757c8e8f), x86_64 Linux.
**Placement:** 6.7.16 — Break 2, repair 6 (libfix lane, wave 1, unit L2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a leak of empty or partial files in `$TMPDIR` (or `/tmp`), not a security vulnerability: each
file is the victim's own, mode 0600, and holds at most a capture of its own child's output.
**Found:** by the 6.7.15 libfix4 review, while checking what the exclusive open changes for a leftover name.

## Reproduction

`tests/gates/toolchain/check_driver_bounded.sh` kills a check driver in the middle of a capture (that is what the
gate proves: a hung test is killed and no child outlives the driver). Run alone with `TMPDIR` set to an empty
directory, on the lane's lib:

```sh
E=/path/to/scratch/empty && mkdir -p "$E"
TMPDIR=$E sh tests/gates/toolchain/check_driver_bounded.sh
ls -la "$E"
```

```text
PASS: check_driver_bounded — a hung test is killed and reported, and no child outlives the check driver
-rw------- 1 macro macro    0 Oct 19 00:07 audit_xc_193188
```

A full `TMPDIR=<scratch> CYRIUS_CHECK_JOBS=4 sh scripts/check.sh` on the lane (GREEN) leaves the same one file:

```text
-rw------- 1 macro macro 0 Oct 19 00:14 <scratch>/audit_xc_376713
```

The same class predates the fix: the dev box's `/tmp` holds 58 leftover 0-byte `audit_xc_<pid>` files, mode 0644
(the pre-6.7.15 `O_WRONLY|O_CREAT|O_TRUNC` 577 open), from earlier check runs:

```text
$ ls -la /tmp/audit_x[ca]_* | awk '{print $1, $3, $5}' | sort | uniq -c
     58 -rw-r--r-- macro 0
```

## Root cause

`lib/regression.cyr`'s capture verbs (`regression_exec_capture[_status]`,
`regression_exec_with_arg_capture[_status]`, `regression_exec_with_arg_capture_both[_status]`) create
`<base>/audit_xc_<pid>` / `audit_xa_<pid>` (`_regression_capture_open`) and unlink it only after the child is
reaped and the file read back. A process SIGKILLed between the open and the unlink — the check driver killed by
`check_driver_bounded.sh`, or by a deadline, or by the user — never runs the unlink.

Before 6.7.15 that leak was bounded: a later process that got the same pid opened the name `O_TRUNC`, reused it and
then unlinked it. Since CYRIUS-2026-0036 the open is `O_CREAT|O_EXCL|O_NOFOLLOW` (correctly — a planted name must
never be opened), so a leftover name is treated as taken and skipped (the capture uses `.1`, `.2`, …): nothing ever
removes it. Each leak is now permanent, and with enough of them at one pid the verb reaches its 64-name bound and
refuses ("it and every name before it were taken; nothing was run").

`scripts/check.sh`'s reapers cover only `cyrius-check-home.*` (`_chk_reap_stale_homes`) and dead-pid `cyrius-<pid>`
directories (`_chk_reap_dead_cli_tmpdirs`), not `audit_x[ca]_<pid>[.N]`.

## Fix directions

- Have `check_driver_bounded.sh` (and any gate that kills a driver mid-capture) run the driver under a private
  `TMPDIR` it removes, so the gate leaves nothing behind.
- And/or reap dead-pid `audit_x[ca]_<pid>[.N]` names the way `_chk_reap_dead_cli_tmpdirs` reaps `cyrius-<pid>`:
  owned by the current user, a regular file, the pid not alive, older than the same age bound. The reaper must not
  follow a symlink or remove another user's name (the plants CYRIUS-2026-0036 defends against).

## Acceptance

`TMPDIR=<empty> sh tests/gates/toolchain/check_driver_bounded.sh` leaves `<empty>` empty, and a gate row pins it;
a leftover dead-pid capture name owned by the user is reaped by the next check run (a row plants one and checks it
is gone, and that a symlink or another user's file at such a name is left alone).
