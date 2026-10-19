# lib/sigil.cyr (fold, sigil 3.13.12): `agnosys_run_capture[_timeout]` and `agnosys_run_checked[_timeout]` run `sys_dup2(fd, N); sys_close(fd)` with no same-fd guard — a caller started with fds 0 + 1 closed gets Err from capturing `/bin/echo hi`, and with fd 1 or 2 closed every checked run starts its child with that fd closed — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 libfix3 lane's review and fix step (branch l6715-libfix3)
with the worktree's `build/cycc` and its vendored `lib/sigil.cyr` (sigil 3.13.12 @ `cf03996`), x86_64 Linux. The
upstream source (`~/Repos/sigil/src/sys_util.cyr`, at the tag `3.13.12`) has the same lines (219-222, 365-370).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 libfix3 review, wave 3; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6 — a fold defect: its fold patch opens 6.7.16) — never 7.x. A fold defect, so
it is always fixed: fix it in the sigil source repo, release a sigil patch, and re-vendor `lib/sigil.cyr` byte-identical
(never patch the vendored copy in place).
**Severity:** Low — a lib / fold defect: a status-checked capture or run fails, or the child starts with a std fd
closed, when the calling process was started with a standard fd closed. No boundary is crossed: the caller's own fd
state drives it.
**Found:** by the 6.7.15 libfix3 lane's review, beside L4 (issues/2026-10-18-process-capture-redirect-closes-its-own-std-fd.md,
which fixed this class in lib/process.cyr, lib/regression.cyr and lib/pam.cyr in 6a1184258). It is the same class in
the folded sigil, which that issue's three files and the lane's staged cbt / programs issue
(2026-10-18-cbt-and-programs-child-redirects-close-their-own-std-fd.md) do not cover.

## Reproduction

Probe 1, the review's (`sg.cyr`): capture `/bin/echo hi` with the fds named by argv[1] closed first (1 = fd 0,
2 = fd 1, 4 = fd 2). Compiled from the cyrius repo root, `cat sg.cyr | build/cycc > sg`:

```cyr
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/syscalls.cyr"
include "lib/io.cyr"
include "lib/fs.cyr"
include "lib/process.cyr"
include "lib/hashmap.cyr"
include "lib/tagged.cyr"
include "lib/args.cyr"
include "lib/result.cyr"
include "lib/chrono.cyr"
include "lib/sys.cyr"
include "lib/sigil.cyr"
alloc_init();
var mask = 0;
args_init();
if (argc() > 1) { mask = load8(argv(1)) - 48; }
var buf = alloc(64);
if ((mask & 1) != 0) { sys_close(0); }
if ((mask & 2) != 0) { sys_close(1); }
if ((mask & 4) != 0) { sys_close(2); }
var a = vec_new();
vec_push(a, "/bin/echo");
vec_push(a, "hi");
var t, n = agnosys_run_capture_timeout(a, buf, 64, 5000, "e");
if (t == Err) { syscall(60, 100); }
syscall(60, n);
```

Probe 2 (`sg2.cyr`, the same 16 includes, then the code below): mode 0 captures a `sh -c` probe of the child's fd 2,
and mode 1 runs a checked `sh -c` that fails unless the child's fds 1 and 2 are both open. `./sg2 <mode> <mask>`:

```cyr
alloc_init();
var mask = 0;
var mode = 0;
args_init();
if (argc() > 2) { mode = load8(argv(1)) - 48; mask = load8(argv(2)) - 48; }
var buf = alloc(64);
if ((mask & 1) != 0) { sys_close(0); }
if ((mask & 2) != 0) { sys_close(1); }
if ((mask & 4) != 0) { sys_close(2); }
var a = vec_new();
vec_push(a, "/bin/sh");
vec_push(a, "-c");
if (mode == 0) {
    vec_push(a, "test -e /proc/self/fd/2 && echo open || echo closed");
    var t, n = agnosys_run_capture_timeout(a, buf, 64, 5000, "e");
    if (t == Err) { syscall(60, 100); }
    syscall(60, n);
}
vec_push(a, "test -e /proc/self/fd/1 && test -e /proc/self/fd/2");
var t2, v2 = agnosys_run_checked_timeout(a, 5000, "e");
if (t2 == Err) { syscall(60, 100); }
syscall(60, 0);
```

Measured (x86_64 Linux; exit codes; 100 = Err):

| closed in the caller | probe 1: capture `echo hi` | probe 2 mode 0: capture, child's fd 2 | probe 2 mode 1: checked run, child's fds 1 + 2 |
|---|---|---|---|
| none (control) | 3 | 5 ("open\n") | 0 (Ok) |
| fd 0 | 3 | 5 | 0 |
| fd 1 | 3 | 5 | **100** (child's stdout closed) |
| fd 2 | 3 | **7** ("closed\n") | **100** (child's stderr closed) |
| fds 0 + 1 | **100** (echo's stdout closed, it exits 1) | **100** | 0 |
| fds 1 + 2 | — | **7** | **100** |

## Root cause

- `agnosys_run_capture_timeout` (lib/sigil.cyr:585-588; upstream src/sys_util.cyr:218-222), which
  `agnosys_run_capture` delegates to: `sys_close(rfd); sys_dup2(wfd, 1); sys_close(wfd);`. With fds 0 + 1 closed in
  the caller, the pipe is (0, 1), so `wfd` IS 1: `dup2(1, 1)` is a no-op and the close closes the child's new stdout.
  Then `devnull = file_open("/dev/null")`, `sys_dup2(devnull, 2); file_close(devnull);`. With fd 2 closed in the
  caller, `devnull` opens AT 2 (or the pipe does, and `devnull` reuses the freed number), and the close closes the
  child's stderr.
- `agnosys_run_checked_timeout` (lib/sigil.cyr:733-735; upstream src/sys_util.cyr:365-370), which
  `agnosys_run_checked` delegates to: `sys_dup2(devnull, 1); sys_dup2(devnull, 2); file_close(devnull);`. One source
  fd feeds two targets, and it is closed even when it IS 1 or 2: with fd 1 closed in the caller the child loses
  stdout, and with fd 2 closed it loses stderr. The run is status-checked, so a child that checks or writes its std
  fds fails, and the call answers Err.

## Fix direction

L4's shape (lib/process.cyr's `_proc_redirect`, lib/regression.cyr's `_regression_redirect`). Close the source fd only
when it is not the target: `if (wfd != 1) { sys_close(wfd); }`, and the same for `devnull` → 2. For the two-target
redirect in `agnosys_run_checked_timeout`, close `devnull` only when it is neither 1 nor 2. Rows in sigil's suite, like
L4's `tests/tcyr/crossos/process_capture_closed_std_fds.tcyr` (each row in a forked copy that closes the named fds
first and answers through its exit code): the measured table's bold cells answer their control's value. Then
re-vendor and add a cyrius-side row in that crossos test for both verbs.
