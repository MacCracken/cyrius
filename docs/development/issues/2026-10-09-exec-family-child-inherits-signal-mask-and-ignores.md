# A child the exec family starts keeps its parent's signal mask and ignored dispositions — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against `build/cycc` @ 39bc88ec (6.7.6). The repro's child reports
`SigBlk: 0000000000000002` and `SigIgn: 0000000000001000`, and its `yes | head -1` prints "yes: standard output:
Broken pipe". The same program without the parent's `signal_ignore(SIGPIPE)` and `SIG_BLOCK` reports zeros and ends
quietly. Every fork site in `lib/process.cyr` runs only `_proc_child_guard` (`:147`) between `fork` and `execve`, or
nothing at all (`spawn`).
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*), the stdlib lane — placed 2026-10-09 — never 7.x. (POSIX keeps a blocked mask and SIG_IGN dispositions across `execve`; resetting them in the child — as a `posix_spawn` with SETSIGMASK / SETSIGDEF, or Python's `restore_signals`, does — is the stdlib's call, confirmed at the open.)
**Discovered:** 2026-10-09 by thoth's repair batch 12 (its audit finding E4), which fixed the same defect in thoth's
own capture child. Filed 2026-10-09, for review.
**Severity:** Medium — wrong signal semantics in every program the exec family starts from a parent that ignores
`SIGPIPE` or blocks a signal. The only workaround is to fork yourself.
**Affects:** `lib/process.cyr` on the POSIX targets (Linux, macOS), at least 6.6.6 through 6.7.6.

## Summary

A signal mask and an ignored disposition both survive `fork` and `execve` (a handler does not). The exec family
forks and execs with nothing in between that touches either, so the program it starts runs with whatever its parent
blocked or ignored. Most programs never reset these for themselves:

- **An ignored `SIGPIPE`** turns a pipeline's quiet end into an error. A writer whose reader has gone gets `EPIPE`
  and reports "Broken pipe" instead of dying of the signal (`yes | head -1`, `grep -r … | head`).
- **A blocked `SIGINT`** (a signalfd user blocks the signals it reads) cannot be interrupted. Measured in thoth's
  TUI before its fix: `timeout -s INT 1 sleep 3` ran the full 3 s.

The parents that do this are ordinary, and one is the stdlib's own:
- sandhi's server entry points call `_sandhi_server_ignore_sigpipe` (`lib/sandhi.cyr:14394`), so a handler that
  runs a command through the exec family hands the ignore to it;
- a TUI that reads signals through a signalfd blocks them;
- a launcher that ignores `SIGPIPE` and `SIGXFSZ` for itself (Python, Node) hands both to the Cyrius program it
  starts, and through it to that program's children.

## Reproduction

[`repros/2026-10-09-exec-family-child-inherits-signal-mask-and-ignores.cyr`](repros/2026-10-09-exec-family-child-inherits-signal-mask-and-ignores.cyr):

```
include "lib/process.cyr"
fn main() {
    alloc_init();
    signal_ignore(SIGPIPE);                   # what sandhi's server entry points do
    var set[16];
    store64(&set, 2); store64(&set + 8, 0);   # bit 1 = SIGINT: what a signalfd user blocks
    sys_sigprocmask(SIG_BLOCK, &set, 0);
    var a = vec_new();
    vec_push(a, "/bin/sh"); vec_push(a, "-c");
    vec_push(a, "grep -E 'SigBlk|SigIgn' /proc/self/status; yes | head -1");
    return exec_vec(a);
}
var r = main();
syscall(SYS_EXIT, r);
```

```sh
build/cycc < docs/development/issues/repros/2026-10-09-exec-family-child-inherits-signal-mask-and-ignores.cyr > /tmp/sigrepro
chmod +x /tmp/sigrepro && /tmp/sigrepro
```

Expected: `SigBlk` and `SigIgn` all zeros, then `y`. Actual (6.7.6):

```
SigBlk:	0000000000000002
SigIgn:	0000000000001000
y
yes: standard output: Broken pipe
```

Control: with the `signal_ignore` and `sys_sigprocmask` lines commented out, the child reports zeros and prints only
`y`. The child takes exactly what the parent set.

## Root cause

The fork sites in `lib/process.cyr` (6.7.6):
- `run` `:688`, `run_capture` `:705`, `exec_vec` `:818`, `exec_capture_status` `:883` (and `exec_capture` over it),
  `exec_env` `:948`, `exec_vec_str` `:1009`, `exec_capture_str` `:1043`, `exec_env_str` `:1087` and `exec_cmd`
  `:1180` all call `_proc_child_guard` (`:147`) in the child. It sets `PR_SET_PDEATHSIG` (Linux) and, under a
  deadline, `setsid`; it touches neither the mask nor any disposition.
- `spawn` `:748` calls nothing between `fork` and `_exec3`.

The 2026-08-05 filing ([`archived/2026-08-05-syscalls-has-signal-ignore-but-no-way-back-to-sig-dfl.md`](archived/2026-08-05-syscalls-has-signal-ignore-but-no-way-back-to-sig-dfl.md))
added `signal_default` (6.5.7). That lets a consumer reset a child it forks itself. A child the exec family forks is
not the consumer's to reach.

## Proposed fix

In the child, before `execve`, at one shared place (`_proc_child_guard`, which every fork site but `spawn` already
calls; `spawn` would call it too, or a sibling that does only this):
- restore an empty signal mask: `sys_sigprocmask(SIG_SETMASK, &empty, 0)` with an 8-byte kernel sigset. This is
  Linux; the macOS floor declined `rt_sigprocmask` at 6.6.6, so nothing there blocks anything to inherit.
- set `SIGPIPE` and `SIGXFSZ` back to `SIG_DFL` with `signal_default` (`SIGXFSZ` is 25 on Linux and Darwin; the
  `Signal` enum had no name for it at 6.6.6).

Do not reset every ignored signal. A `SIGHUP` that `nohup` ignored is the operator's choice, and must survive into
the command. This is the established shape: Rust's `std::process::Command` restores an empty mask and `SIGPIPE`'s
default in its child (libstd ignores `SIGPIPE` itself), and Python's `subprocess` restores `SIGPIPE` and `SIGXFSZ`
by default (`restore_signals=True`).

A gate is the repro with its two checks. On Linux, the child's `/proc/self/status` must show both lines all zeros.
On macOS, the disposition half: `yes | head -1` must end with no "Broken pipe".

## Consumer-side workaround

thoth 0.52.8 forks its own capture child (`src/exec.cyr` `_exec_child_signals_reset`: an empty mask, then `SIGPIPE`
and `SIGXFSZ` to `SIG_DFL`), so `/run` in its TUI and window, its `shell` tool, its hooks and `[verify]` are fixed
there. Its line REPL's `/run` still goes through `exec_vec` and keeps a launcher's ignores. Launched from Python,
`/run yes | head -1` printed "Broken pipe".

A consumer that does not fork for itself has no clean workaround. Resetting its own disposition around the call
races every other thread, and a process that ignores `SIGPIPE` to survive dead peers cannot drop the ignore even
briefly.
