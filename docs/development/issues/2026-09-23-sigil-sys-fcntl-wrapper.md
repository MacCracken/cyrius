# Stdlib has no `sys_fcntl` wrapper, so every consumer that sets `O_NONBLOCK` hand-rolls a raw `syscall(SYS_FCNTL, …)` — OPEN

**Status:** 🟡 **OPEN** — stdlib surface recommendation, filed by sigil at its 3.13.0 raw-syscall sweep.
**Placement:** unpinned — 6.6.x-line backlog.
**Discovered:** 2026-09-23, moving every raw `syscall(...)` in sigil onto stdlib helpers. One site has
no helper to move to.
**Severity:** Low — no wrong code in the stdlib. The cost is in consumers: a hand-rolled `fcntl` is a
raw syscall that a "no raw syscalls" rule cannot clear, and it invites hard-coding the Linux
`O_NONBLOCK` value.
**Affects:** cyrius 6.6.6 stdlib (`lib/syscalls_*.cyr`, `lib/net.cyr`, `lib/async.cyr`).

## Summary

`lib/syscalls_*.cyr` wraps nearly every syscall a consumer needs, but not `fcntl(2)`. Every per-target
peer declares `SYS_FCNTL` (x86_64 Linux 72, aarch64 Linux 25, macOS 72), and the stdlib itself calls it
raw in at least six places:

| Site | Call |
|---|---|
| `lib/async.cyr:469-470` | `syscall(SYS_FCNTL, fd, 3, 0)` / `syscall(SYS_FCNTL, fd, 4, fl \| 2048)` |
| `lib/async.cyr:523` | `syscall(SYS_FCNTL, afd, 2, 1)` (F_SETFD FD_CLOEXEC) |
| `lib/async.cyr:960-964` | F_GETFL / F_SETFL / restore |
| `lib/syscalls_linux_common.cyr:842-846` | the Darwin `accept4` composition |
| `lib/net.cyr:730-732` | `sock_set_nonblocking`: `syscall(72, fd, 3, 0)`, literal 72 |
| `lib/net.cyr:743` | `sock_clear_nonblocking`: `syscall(72, fd, 4, saved)` |

The only exported toggle, `lib/net.cyr`'s `sock_set_nonblocking(fd)`, is named for sockets and pulls in
the whole network module. A consumer that wants a non-blocking **pipe** has two options: include
`net.cyr` for one call, or write `syscall(SYS_FCNTL, …)` itself.

## What sigil had to write

`src/sys_util.cyr`'s bounded subprocess capture (`agnosys_run_capture_timeout`) drains the child's
stdout without blocking:

```cyr
var fl = syscall(SYS_FCNTL, rfd, 3, 0);          # F_GETFL
syscall(SYS_FCNTL, rfd, 4, fl | O_NONBLOCK);     # F_SETFL |= O_NONBLOCK
```

Until sigil 3.13.0 the second line read `fl | 2048`. That is Linux's `O_NONBLOCK`, but Darwin's is 4, and
2048 there is `O_EXCL`, which `F_SETFL` ignores. On macOS the pipe therefore stayed **blocking**, and a
silent child could hold the drain in `read(2)` past the deadline the function exists to enforce. The
per-target `O_NONBLOCK` symbol fixes that. The call itself stays raw because nothing wraps it.

## Proposed surface

Something like:

```cyr
fn sys_fcntl(fd, cmd, arg): i64          # per-target SYS_FCNTL; -errno on failure
fn fd_set_nonblocking(fd): i64           # returns the SAVED flags (for restore), or -errno
fn fd_restore_flags(fd, saved): i64
```

Two design points:
- **agnos** has no `fcntl`. Following `sock_set_nonblocking`'s precedent (a no-op returning 0) would
  hide a real difference for a pipe drain. A caller that relies on non-blocking reads needs to know
  they are unavailable, so `-ENOSYS` is the honest return there.
- **Windows** has no `SYS_FCNTL` at all. Its arm should refuse (`-ENOSYS`), never be absent: an
  undefined *variable* in an unguarded arm is a hard compile error for every consumer. That is how
  sigil 3.12.14's missing Windows guard broke mabda's and yukti's PE builds.

`sock_set_nonblocking` / `sock_clear_nonblocking` and the `async.cyr` sites could then route through it,
which would also retire `net.cyr`'s literal `72`.

## Consumer-side state

sigil 3.13.0 keeps the named `syscall(SYS_FCNTL, …)` (no literal) with `O_NONBLOCK` spelled per target.
Its CHANGELOG and `src/sys_util.cyr` point at this issue, and the call moves to the wrapper when one
ships.
