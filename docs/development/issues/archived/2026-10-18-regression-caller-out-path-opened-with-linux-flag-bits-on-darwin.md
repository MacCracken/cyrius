# lib/regression.cyr's verbs that write a CALLER's `out_path` open it with the literal 577 (Linux's O_WRONLY|O_CREAT|O_TRUNC): on Darwin that is O_WRONLY|O_ASYNC|O_CREAT, so an existing file is not truncated and keeps its old tail after a shorter output — RESOLVED

> ✅ **RESOLVED in v6.7.16** (LF-1, `3232553e6` — no decision needed (a `lib/` defect; the triage: none needed). `regression_pipe_to_bin_capture`, `regression_ssh_remote_exec_capture` and `regression_exec_in_dir3` (so `regression_exec_in_dir3_env`) open the caller's `out_path` with `O_WRONLY | O_CREAT | O_TRUNC`, each target's own constants, instead of the literal 577 (on Darwin O_WRONLY | O_ASYNC | O_CREAT, no truncation); lib/regression_agnos.cyr's `file_open(…, 577, …)` is left as is (agnos maps the Linux-shaped bits). The filed repro, verbatim (cross-built from the tree, run in a scratch dir on each host), exits 3 with `trunc_out.txt` = `"hi\n"` on ecb and ach, where it exited 9 (`"hi\ncious\n"`); x86_64 Linux and pi exit 3 as before (Linux's bits are unchanged). Rows: `tests/tcyr/crossos/regression_out_path_truncated.tcyr` (16: the repro's shape in a forked copy; exec_in_dir3, exec_in_dir3_env and pipe_to_bin_capture into a 4096-byte `out_path`; the ssh verb through `ssh -GF/dev/null <name>` — no host, no config file read — into a 16384-byte one; a named SKIP without ssh — 16 / 16 on x86_64, ecb, ach and pi, cass 1 / 1) and `tests/gates/toolchain/regression_child_fd_shapes.sh` rule `flags` (every open in lib/regression.cyr passes 0, 1 or a flag with no numeric literal; the live file with 577 back at each of the three opens RED naming the verb; floor 25 opens). Mutants on ecb and ach: 577 back at the ssh / pipe / exec_in_dir3 site → 2 / 1 / 4 rows RED, all three → 7. The check driver's own 577s (programs/checks/shared.cyr, Linux-only) are respelled with the `O_*` constants by LF-6. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 libfix4 lane (branch l6715-libfix4, unit L6) on ecb
(macOS arm64) and ach (Intel Mac), with compilers built from the lane's tree; x86_64 Linux for the control.
**Placement:** 6.7.16 — Break 2, repair 6 (libfix lane, wave 1, unit L1; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** P2 — a wrong result on macOS from a public stdlib verb (a bug, not a security vulnerability: the
path is the caller's own choice). `regression_exec_in_dir3` / `_env`, `regression_pipe_to_bin_capture` and
`regression_ssh_remote_exec_capture` hand back a file that holds the child's output FOLLOWED BY whatever the file
held before past that length; a caller reading the file whole reads stale bytes as output.
**Found:** in passing by unit L6 (CYRIUS-2026-0036), which replaced the same literal in the three capture verbs
that name their own file (`regression_exec_capture[_status]`, `regression_exec_with_arg_capture[_status]`,
`regression_exec_with_arg_capture_both[_status]` — now O_* constants with O_EXCL); the caller-path verbs were
outside that issue's surface.

## Reproduction

```cyr
include "lib/regression.cyr"
include "lib/args.cyr"
args_init();
if (argc() > 1) { sys_write(1, "hi\n", 3); sys_exit(0); }
var out = "trunc_out.txt";
file_write_all(out, "precious\n", 9);
regression_exec_in_dir3(".", argv(0), "child", 0, 0, out, 0);
var b[64];
syscall(60, file_read_all(out, &b, 64));
```

```text
x86_64 Linux   exit 3   trunc_out.txt = "hi\n"
ecb (arm64)    exit 9   trunc_out.txt = "hi\ncious\n"
ach (x86_64)   exit 9   trunc_out.txt = "hi\ncious\n"
```

## Root cause

`sys_open(out_path, 577, 420)` at lib/regression.cyr `regression_pipe_to_bin_capture`,
`regression_ssh_remote_exec_capture` and `regression_exec_in_dir3` (which `_env` calls). 577 = 0x241 is
O_WRONLY | O_CREAT | O_TRUNC in Linux's bits; Darwin's O_CREAT is 0x200 and O_TRUNC 0x400, so on macOS the same
number is O_WRONLY | 0x40 (O_ASYNC) | O_CREAT — no truncation. lib/syscalls_macos.cyr defines the Darwin O_*
values for exactly this reason. (lib/regression_agnos.cyr's `file_open(out_path, 577, 420)` is right: agnos's
`file_open` maps the neutral Linux-shaped bits.) The check driver (programs/checks/*.cyr) spells 577 too, but it
runs on Linux only.

## Fix direction

`O_WRONLY | O_CREAT | O_TRUNC` (the per-target constants) at the three sites, and a row in
tests/tcyr/crossos/ (ecb, ach): an existing longer `out_path` holds exactly the child's output afterwards.
