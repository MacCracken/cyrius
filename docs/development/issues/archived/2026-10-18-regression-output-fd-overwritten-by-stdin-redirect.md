# lib/regression.cyr opens the output file BEFORE the child's stdin redirect: a caller with fd 0 closed gets the output at fd 0, the stdin redirect overwrites it, and the capture is empty — `regression_exec_in_dir3` / `regression_pipe_to_bin_capture` answer 0 bytes where the control answers 3 — RESOLVED

> ✅ **RESOLVED in v6.7.15** (LF-9, `2941e7412`: in the child, a parent-opened output fd 0..2 is lifted above 2 (`_regression_lift_fd`: `fcntl(F_DUPFD, 3)`, the old number closed) before any redirect, in `regression_exec_in_dir3` (and `regression_exec_in_dir3_env`, which delegates), `regression_pipe_to_bin_capture` and `regression_ssh_remote_exec_capture`; LF-6's same-fd guards are kept. Both filed repros exit 3 with fd 0 closed, where they exited 0, on x86_64 Linux, pi, ecb and ach; the controls give 3. A lift, not an out-first reorder: with fds 0 and 1 closed the pipe verb's output is at 0 and its pipe at 1, and the reorder alone stays RED there (6 rows). No decision needed: a lib/ defect. Rows: `tests/tcyr/crossos/regression_capture_stdin_closed.tcyr` (62: the two repros verbatim with their controls; each verb's capture, and the child's own fd state, under all 8 masks of closed std fds — 62 / 62 on the four hosts, 32 / 62 with the old lib; 1 / 1 under wine and on cass) and a fd-0 row in `process_capture_closed_std_fds.tcyr` (64, where it read 65). The ssh verb takes the same change with no row (no host); filed from the review (6.7.16): nothing pins its lift. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 libfix3 lane (branch l6715-libfix3) with the worktree's
`build/cycc` (x86_64 Linux), both before and after 6a1184258 (the same-fd guard of
issues/archived/2026-10-18-process-capture-redirect-closes-its-own-std-fd.md, which does not touch this shape).
**Placement:** 6.7.15 — repair 5 (libfix4 lane, unit L7; placed at the wave-3 integration, 2026-10-18: a lib/ defect in the same capture verbs as CYRIUS-2026-0036) — never 7.x.
**Severity:** Low — a defect in lib/: a regression verb's capture comes back empty when the calling process was started
with stdin closed. No boundary is crossed: the caller's own fd state drives it.
**Found:** by the 6.7.15 libfix3 lane (unit L4) while fixing the same-fd shape in lib/regression.cyr; its brief files a
different shape rather than fixing it.

## Reproduction

```cyr
include "lib/regression.cyr"
var o = "/path/to/scratch/clob_out.txt";
sys_close(0);
var rc = regression_exec_in_dir3("/", "/bin/echo", "hi", 0, 0, o, 0);
var buf[64];
var n = file_read_all(o, &buf, 64);
syscall(60, n);
```

```cyr
include "lib/regression.cyr"
var o = "/path/to/scratch/clob2_out.txt";
var s = "/path/to/scratch/clob2_src.txt";
file_write_all(s, "hi\n", 3);
sys_close(0);
var rc = regression_pipe_to_bin_capture("/bin/cat", s, o, 0);
var buf[64];
var n = file_read_all(o, &buf, 64);
syscall(60, n);
```

```text
                                       fd 0 closed   control (the sys_close(0) line removed)
regression_exec_in_dir3 echo hi        exit 0        exit 3
regression_pipe_to_bin_capture cat     exit 0        exit 3
```

## Root cause

Both verbs open `out_fd` in the PARENT (lowest free fd: 0 when the caller closed stdin) and the child then redirects
stdin before it redirects stdout:

- `regression_exec_in_dir3` (and `regression_ssh_remote_exec_capture`): `dn0 = open("/dev/null")` (fd 3) →
  `dup2(dn0, 0)` replaces fd 0 — which WAS `out_fd` — with /dev/null; then `dup2(out_fd = 0, 1)` points stdout at
  /dev/null. The child's output goes nowhere and the file stays empty.
- `regression_pipe_to_bin_capture`: `dup2(rfd, 0)` replaces `out_fd` (0) with the pipe's read end; then
  `dup2(0, 1)` makes stdout the pipe's READ end, and the close of fd 0 leaves stdin closed.

(The `regression_exec_capture_status` family redirects stdout first, so it does not have this shape.)

## Fix direction

Redirect the output fd onto 1 before any redirect that can target its number, or move an `out_fd` < 3 above 2 first
(`fcntl(F_DUPFD, 3)`) — in the child, before the stdin redirect. Rows: the two repros answer 3 with fd 0 closed (a
`regression_ssh_remote_exec_capture` row cannot run without a host; it takes the same change). The same ordering
exists outside lib/ (cbt/pulsar.cyr's `sfd` / `ofd`) —
2026-10-18-cbt-and-programs-child-redirects-close-their-own-std-fd.md.
