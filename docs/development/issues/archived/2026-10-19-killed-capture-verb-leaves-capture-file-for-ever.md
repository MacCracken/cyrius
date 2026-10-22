# A capture verb killed mid-capture leaves its `<base>/audit_x[ca]_<pid>[.N]` file behind for ever: nothing reaps it, and since CYRIUS-2026-0036's O_EXCL a later process with the same pid skips the name instead of reusing it — RESOLVED

> ✅ **RESOLVED in v6.7.16** (LF-3 `f2132896b`, LF-4 `0c710bda9`, LF-5 `c86336672` — no decision needed (a `lib/` / tooling defect; the triage: none needed); LF-5 edits CYRIUS-2026-0036's open and keeps every 0036 guarantee; not a vulnerability. Both fix directions, plus the root: (a) `check_driver_bounded.sh` runs its harnesses under `TMPDIR="$T/tmp"` inside its trap-removed dir, and axis 5 checks the caller's TMPDIR gained no `audit_x[ca]_` name carrying a harness pid — the filed repro `TMPDIR=<empty> sh tests/gates/toolchain/check_driver_bounded.sh` now leaves `<empty>` empty (it held a 0-byte `audit_xc_<pid>`), and with TMPDIR unset `/tmp` gains nothing; (b) check.sh's `_chk_reap_dead_capture_files` reaps `audit_x[ca]_<digits>[.<digits>]` in the verb's base (an absolute TMPDIR, else `/tmp`) only when it is a regular file (never a link) this user owns, older than `CYRIUS_CHECK_REAP_MINS`, its pid dead — a dry run lists exactly the 58 pre-6.7.15 0644 files in the dev box's `/tmp`; (c) `_regression_capture_open` opens `O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW` 0600, unlinks the name at once and lifts the fd above 2 (the parent holds it through the wait), and the three `_status` verbs read the capture back from that fd (`_regression_capture_read`: lseek 0, a read loop) — no verb names a file, and only the open → unlink window remains. A probe SIGKILLed 1 s into a capture of `sleep 3` leaves `audit_xa_<pid>` with the 6.7.15 lib and nothing with 6.7.16's, on x86_64 Linux, pi, ach and ecb. Rows: `check_driver_bounded.sh` axis 5 (premise, 5a, 5b); `check_stale_home_reaper.sh` axes 17 – 22 (dead + old reaped in each shape and counted; a live pid's, a fresh one, a symlink to a file, a dangling one, a directory, eleven look-alikes and another uid's name kept — the last planted through `sudo -n` or an unprivileged user namespace, a named row SKIP when neither works); `tests/tcyr/crossos/regression_capture_exclusive.tcyr` `_cr_private` (the child fstats its stdout: 0600, and the name is gone while it runs) and `_cr_parent_stderr` (fd 2 closed with a deadline-knob warning: the capture is exactly the child's) — 23 / 23 on x86_64, pi, ach and ecb, cass 2 / 2; `regression_capture_exclusive.sh` 4b (unlink at create, read back from the fd, never by name). Mutations: the reaper call, `-O`, `! -L`, liveness, the shape `case` and the age gate each RED; the unlink dropped → 7 rows and gate axes 1 + 4b RED; the parent lift → 1; the lseek → 19. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-19 on the 6.7.15 libfix4 lane (branch l6715-libfix4, after unit L6 /
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
