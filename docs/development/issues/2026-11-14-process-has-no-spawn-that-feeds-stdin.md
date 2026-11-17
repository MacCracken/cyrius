# lib/process.cyr has no spawn that feeds the child's stdin while reading its stderr — open

**Status:** 🟡 **OPEN** — cyrius 6.7.18, read 2026-11-14.
**Filed:** 2026-11-14, by **selah** (Rust → Cyrius port, M5: the clipboard; ledger L3 in
`selah/docs/development/selah-port-plan.md` §6).
**Affects:** `lib/process.cyr`. Every consumer that pipes data into a tool (`wl-copy`, `xclip`, `gpg`, `zstd`, a
formatter).
**Severity:** Medium for selah: copying a screenshot to the clipboard means writing the image to `wl-copy` or `xclip`
on stdin. selah carries its own spawn (`selah/src/spawn.cyr`) until the stdlib has one.

## Summary

`run`, `spawn`, `exec_capture*` and `exec_env*` cover a child's stdout and exit status, with the deadline and death
signal of 6.6.6–6.6.11. None of them gives the child a stdin to write to. A consumer that needs one rebuilds fork,
pipes, `dup2`, `execve`, PATH lookup, the environment and the child's signal reset, and then has to get four things
right that the stdlib already knows about:

1. **Deadlock.** Writing stdin while the child fills its stderr pipe blocks both. The writes and the stderr reads
   have to be interleaved (a poll loop), or the write done from another thread (Rust's `Command` users do that).
2. **SIGPIPE.** A child that exits before reading all of its input makes the next write raise SIGPIPE, which ends the
   parent. The parent has to block SIGPIPE around the writes and take the one raised off its pending set before
   restoring the mask. On aarch64 a raw `rt_sigtimedwait` (137) inside an `#ifdef CYRIUS_ARCH_AARCH64` region is
   renumbered (the compiler warns: no 1000+N alias for it), so selah takes it off with a `signalfd` through
   `sys_signalfd` instead. There are no `SYS_RT_SIGPENDING` / `SYS_RT_SIGTIMEDWAIT` names or wrappers.
3. **Background children holding the pipes.** `wl-copy` and `xclip` fork a process that keeps serving the selection
   and inherits the pipes, so the parent must not wait for stderr EOF, only for the exit status.
4. **PATH lookup and the environment.** `exec_*` take a full path and an explicit environment; a tool named by its
   bare name, run with this process's environment (`_read_environ_envp` is private), needs both.

## Proposed

A verb in `lib/process.cyr` along the lines of

```cyrius
# Run argv (argv[0] looked up on PATH) with data[0..n) on stdin, stdout to /dev/null or a buffer, stderr kept up to
# err_cap bytes; wait for the exit only. Fills status_out like exec_capture_status.
fn exec_feed(args, data, n, err_buf, err_cap, err_len_out, status_out): i64
```

honouring `proc_set_timeout_ms`, with the four points above handled inside. selah's `_sl_spawn_feed` is one
implementation (a poll loop, SIGPIPE blocked and consumed through a signalfd, no wait for EOF), tested in
`selah/tests/capture.tcyr` on x86_64 and under qemu-aarch64: a 1 MiB input read whole, a 4 MiB input to a child that
exits without reading (the parent survives), a 300 KB stderr flood with 1 MiB of input (no deadlock), a signal death.

## Reproduction

`selah/tests/capture.tcyr`, the `spawn:` groups.
