# Every self-spawning `tests/tcyr` test fails under `qemu-aarch64` on an x86 host without an aarch64 binfmt: the child's `execve` of the test's own aarch64 ELF answers 127, so a local qemu reproduction reads it as an aarch64 defect (e.g. `crossos/exec_capture_status.tcyr`: 13 passed / 14 failed, green on real pi) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 libfix3 lane (review, then fix step) on this dev box
(x86_64 Arch Linux, `qemu-aarch64` 11.1.2, `/proc/sys/fs/binfmt_misc/` = `DOSWin register status`: no qemu-aarch64
entry), with the worktree's `build/cycc_aarch64` (checked equal to its tree's build).
**Placement:** 6.7.16 — Break 2, repair 6 (platform lane, wave 1, unit P4; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — tooling / test environment, pre-existing. No gate runs the corpus under qemu, so nothing is red
today. The risk: CLAUDE.md and `docs/development/dev-tools-linux.md` name `qemu-aarch64` as the local way to reproduce
aarch64 failures, and these rows then report false aarch64 defects.
**Found:** by the lane's review while measuring the L4 row (crossos/process_capture_closed_std_fds.tcyr) under qemu.

## Reproduction

From the repo root (`build/cycc_aarch64` = `cat src/main_aarch64.cyr | build/cycc`):

```sh
cat tests/tcyr/crossos/exec_capture_status.tcyr | build/cycc_aarch64 > ecs.a64 && chmod +x ecs.a64
qemu-aarch64 ./ecs.a64; echo "rc=$?"
cat tests/tcyr/crossos/process_capture_closed_std_fds.tcyr | build/cycc_aarch64 > pcc.a64 && chmod +x pcc.a64
qemu-aarch64 ./pcc.a64; echo "rc=$?"
```

```text
  FAIL: SIGCHLD ignored: the capture itself still works (got 0, expected 22)
13 passed, 14 failed (27 total)          rc=14
  FAIL: regression_pipe_to_bin_capture, fd 2 closed: stderr open (got 127, expected 64)
7 passed, 36 failed (43 total)           rc=36
```

On real pi (aarch64 Linux) both are green: 27 / 27 and 43 / 43 (the lane's `cross-os-selfhost.sh pi crossos` run,
LIBTEST_OK 661 / 661).

## Root cause

These tests spawn themselves (`argv(0)` or `/proc/self/exe`) as a child that reports back through its exit code or
output. Under user-mode qemu without a binfmt_misc entry, the child `execve` of an aarch64 ELF on an x86_64 kernel
fails ENOEXEC, and the spawn answers 127. The tests that name `argv(0)` / `/proc/self/exe` (a superset of the
self-spawners): crossos/ exec_capture_status, process_capture_closed_std_fds, tool_spawn_roundtrip,
exec_child_signal_state, fork_refused_stays_negative, syscall_shm_fd_passing, net_plain_write_peer_reset,
bounds_mode_violation, tls_native_socket_transport, slice_subscript_write, args_smoke, win_self_exe_path; platform/
regression_wait_unobserved, args.

## Fix direction

Either (a) a note in `docs/development/dev-tools-linux.md` (the `qemu-aarch64` row and the "Local self-host repro"
line): self-spawning tests need an aarch64 binfmt_misc registration (`qemu-user-binfmt` / systemd-binfmt with the
`qemu-aarch64` entry) to run under emulation, or (b) a named SKIP in the self-spawning tests: when the self-exec
answers 127 and the test is running under emulation, skip it BY NAME, never silently. (a) is the smaller change. (b)
keeps a local qemu run honest without host setup.
