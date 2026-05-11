# Cyrius: stdlib needs `sys_socket` / `sys_bind` / `sys_recvfrom` wrappers (and friends)

**Filed:** 2026-05-11
**Reporter:** kybernet (AGNOS PID 1 init system, v1.1.5 P(-1) audit)
**Cyrius version at time of report:** 5.10.44 (release tarball)
**Affected stdlib:** `lib/syscalls_x86_64_linux.cyr` + the aarch64 peer
**Severity:** **P2** — kybernet 1.1.5 ships with a local `#ifdef`-arch-dispatched workaround; the upstream filing is to deduplicate raw-syscall surface across consumers and prevent the silent-aarch64-misroute class that the 1.1.5 audit caught.
**Status:** open.

## Summary

The Unix socket-family syscalls used by sd_notify and similar
PID-1 / supervisor IPC paths have **no stdlib wrappers** at cyrius
5.10.44. Each call site has to either:

1. Hardcode the x86_64 syscall number and call `syscall(N, ...)`
   directly (silently invokes a different syscall on aarch64), OR
2. Define a local per-arch enum and `#ifdef`-dispatch the number.

Both are footguns. kybernet's 1.1.5 P(-1) audit caught the first
form in `src/lib/notify.cyr` — three sites where the x86_64 numbers
silently routed to `pipe2` / `setsockopt` / `getsockopt` on
aarch64. Fix shipped at the kybernet layer (option 2 — `#ifdef`
dispatch), but the underlying gap is upstream.

| Syscall | x86_64 nr | aarch64 nr | Use-site |
|---|---:|---:|---|
| `socket` | 41 | 198 | sd_notify dgram socket creation; service supervisor IPC entry |
| `bind` | 49 | 200 | sd_notify socket bind to `/run/<consumer>/notify` |
| `recvfrom` | 45 | 207 | sd_notify message read (with peer cred capture via `recvmsg` follow-up) |
| `listen` | 50 | 201 | Service supervisor's control-socket accept loop (kybernet 1.2.x roadmap) |
| `connect` | 42 | 203 | Service-side sd_notify client (out of scope here, but in argonaut) |
| `accept4` | 288 | 242 | Same as listen — accept loop |

Without wrappers, each consumer rolls its own arch dispatch and
the same off-by-arch bug class re-appears at every consumer that
needs a socket. argonaut's notify.cyr (1.6.x) has its own copy
of these; kavach probably needs them for its sandbox-fd-passing
plumbing; bote already has a more complete socket layer that
probably exposes the same gap differently.

## Detail per syscall

### `sys_socket(domain, sock_type, protocol)`

Three-arg. Returns fd or -errno. `sock_type` carries the flag
bits (`SOCK_NONBLOCK = 2048`, `SOCK_CLOEXEC = 524288`) ORed with
the socket type (`SOCK_DGRAM = 2`, `SOCK_STREAM = 1`). Used by
every consumer that opens a Unix-domain socket.

```cyrius
# x86_64
fn sys_socket(domain, sock_type, protocol) {
    return syscall(41, domain, sock_type, protocol);
}
# aarch64
fn sys_socket(domain, sock_type, protocol) {
    return syscall(198, domain, sock_type, protocol);
}
```

### `sys_bind(fd, sockaddr, addrlen)`

Three-arg. Used immediately after socket() for server-side dgram
sockets. `sockaddr` is a heap pointer to a struct sockaddr_un
(`{ u16 sa_family, char sun_path[108] }`); `addrlen` is `2 + strlen(path) + 1`
for an abstract or pathname socket.

### `sys_recvfrom(fd, buf, buflen, flags, srcaddr, srcaddrlen)`

Six-arg (note: linux's actual recvfrom has six args including the
addrlen-ptr; cyrius wrappers typically pass them all). For sd_notify
we usually pass `srcaddr=0, srcaddrlen=0` since we don't care about
the sender's address (kernel-side peer cred capture via SCM_CREDENTIALS
is what we actually want, which needs `recvmsg`, also missing).

### `sys_listen(fd, backlog)` / `sys_accept4(fd, srcaddr, srcaddrlen, flags)`

Two-arg / four-arg. Needed by stream-socket supervisors. kybernet
1.2.x roadmap (control socket for agnoshi runtime commands) will
consume these — flagging now so the wrappers can land before that
roadmap item picks them up.

### `sys_connect(fd, sockaddr, addrlen)`

Three-arg. Service-side (the process notifying the supervisor).
Out of scope for kybernet's own use; argonaut and any sd_notify
client need it.

## Adjacent: `sys_recvmsg`

Not on the kybernet 1.1.5 critical path, but worth mentioning:
sd_notify peer-cred capture (`SCM_CREDENTIALS`) requires `recvmsg`
(syscall 47 x86_64 / 212 aarch64). argonaut already uses this
in `notify_try_recv_authenticated` from 1.6.2 — same arch-dispatch
gap. If `sys_recvmsg` lands alongside the socket family, argonaut
can drop its own local workaround in the same cycle.

## Severity rationale (P2)

- **Not P1**: kybernet 1.1.5 ships with a local `#ifdef CYRIUS_ARCH_*`
  workaround. aarch64 currently works. No active break.
- **Not P3**: the workaround is footgunny — every new consumer
  that needs a socket has to remember the per-arch numbers, and
  the test infra (qemu-system-x86_64) doesn't surface the bug.
  kybernet's pre-1.1.5 form passed all gates including the aarch64
  cross-build (which compiles fine, just calls the wrong syscall).
- **P2 is right**: visible cliff when a consumer ships an aarch64
  binary without realizing socket calls are misrouted. Fix is low-
  risk (six small wrappers, no API change, mirrors the existing
  `sys_unlink` / `sys_mkdir` / etc. pattern in syscalls_*.cyr).

## What kybernet did in 1.1.5

Local fix in `src/lib/notify.cyr`:

```cyrius
#ifdef CYRIUS_ARCH_X86
enum SockSysNr {
    SYS_SOCKET = 41;
    SYS_BIND = 49;
    SYS_RECVFROM = 45;
}
#endif
#ifdef CYRIUS_ARCH_AARCH64
enum SockSysNr {
    SYS_SOCKET = 198;
    SYS_BIND = 200;
    SYS_RECVFROM = 207;
}
#endif
```

Once `sys_socket` / `sys_bind` / `sys_recvfrom` land in stdlib,
kybernet will fold these out and use the wrappers directly.

## Related

- `2026-05-10-kavach-sandbox-syscall-wrappers.md` is the same
  pattern for post-fork hardening syscalls (`prctl`, `seccomp`,
  `setresuid`, etc.). Pair these in the same release if the
  scheduling pressure aligns — the audit-and-wrap cost is shared.
- `2026-05-11-kybernet-fn-table-identifier-buffer-caps.md` —
  separate issue, same kybernet repo, same release pattern.
