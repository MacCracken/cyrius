# lib/process.cyr's child redirects run `sys_dup2(fd, N); sys_close(fd)` with no same-fd guard: a parent with fds 0 and 1 closed gets the pipe as (0, 1), the child closes its own stdout, and the capture reads 0 bytes; the `/dev/null` → fd 2 redirect closes stderr the same way — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 libfix lane (branch l6715-libfix, after L1 633f9f4dd)
with the lane's `build/cycc` (x86_64 Linux) and `build/cycc_aarch64` (qemu-aarch64).
**Placement:** 6.7.15 — repair 5 (libfix lane, wave 3, unit L4; placed at the wave-2 integration, 2026-10-18: a lib/ defect is always fixed) — never 7.x.
**Severity:** Low — a defect in lib/: a capture verb returns empty output (and the child's stderr starts closed) when
the calling process was started with standard fds closed. It predates 6.7.15 and the L1 fix does not change it (on
aarch64 the old dup3 answered -22 and the close ran anyway). No boundary is crossed: the parent's own fd state drives
it.
**Found:** in passing, by the 6.7.15 libfix review while checking `sys_dup2`'s callers for the L1 fix
(issues/2026-10-18-aarch64-sys-dup2-same-fd-answers-einval.md).

## Reproduction

stdout — the parent closes fds 0 and 1, so `sys_pipe` answers (0, 1):

```cyr
include "lib/process.cyr"
var buf[64];
sys_close(0);
sys_close(1);
var t, n = run_capture("/bin/echo", "hi", 0, &buf, 64);
if (t == Err) { syscall(60, 100); }
syscall(60, n);
```

The same with `exec_capture` (`exec_capture_status`'s child):

```cyr
include "lib/process.cyr"
var buf[64];
sys_close(0);
sys_close(1);
var a = vec_new();
vec_push(a, "/bin/echo");
vec_push(a, "hi");
syscall(60, exec_capture(a, &buf, 64));
```

stderr — the parent closes fd 2, so the child's `/dev/null` opens at 2:

```cyr
include "lib/process.cyr"
var buf[64];
sys_close(2);
var t, n = run_capture("/bin/sh", "-c", "if [ -e /proc/self/fd/2 ]; then echo open; else echo closed; fi", &buf, 64);
if (t == Err) { syscall(60, 100); }
syscall(60, n);
```

```text
                                      fds closed in parent   control (nothing closed)
run_capture echo, x86_64              exit 0  (0 bytes)      exit 3  ("hi\n")
run_capture echo, qemu-aarch64        exit 0                 exit 3
run_capture echo, only fd 1 closed    —                      exit 3  (pipe is (1, 3): no collision)
exec_capture echo, x86_64             exit 0                 exit 3
run_capture sh -c, fd 2, x86_64       exit 7  ("closed\n")   exit 5  ("open\n")
```

## Root cause

The child side of every capture verb (lib/process.cyr `run_capture` ~750, `exec_capture_status` ~940,
`exec_capture_str` ~1098):

```cyr
sys_close(rfd);
sys_dup2(wfd, 1);
sys_close(wfd);
var devnull = sys_open("/dev/null", 1, 0);
if (devnull >= 0) { sys_dup2(devnull, 2); sys_close(devnull); }
```

When `wfd` is already 1, `dup2(1, 1)` is a no-op answering 1, and `close(1)` then closes the pipe's only write end in
the child: the exec'd program starts with stdout closed, its writes fail EBADF, and the parent reads EOF. When the
parent's fd 2 is closed, `/dev/null` opens at 2 and `dup2(2, 2); close(2)` leaves the exec'd program with fd 2 closed —
its first `open` then lands on fd 2 and its diagnostics write into that file. The two `exec_env*` verbs (~1005, ~1144)
carry the `/dev/null` → 2 half of the shape.

## Fix direction

Guard each close on the target fd: `if (wfd != 1) { sys_close(wfd); }` and `if (devnull != 2) { sys_close(devnull); }`
at all five sites (POSIX arm; the PE and agnos arms do not fork). Rows: the three repros above in a `tests/tcyr/`
process bucket (Linux / macOS; the stdout one also under qemu-aarch64 and on pi), each answering the control's value.
