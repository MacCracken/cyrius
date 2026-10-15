# agnos: `sock_bind` / `sock_listen` / `sock_accept` / `sock_connect` take ANY fd for socket slot `fd & 7` — a failed open's -1 binds, listens, accepts and connects on slot 7 — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 stdlib lane tree (after the negative-fd fix), by the run below and by reading the four call paths.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 stdlib lane) — never 7.x.
**Discovered:** 2026-10-13, while fixing `issues/2026-10-12-agnos-negative-fd-taken-for-socket-slot-7.md` (6.7.11 stdlib lane, unit L2). That filing's surface is `_agnos_is_sock_fd`, `_agnos_fd_conn`, `sys_close` and the `sys_read` / `sys_write` family; this is the same class in the adapter's OTHER slot helpers, which no `_agnos_is_sock_fd` check guards.
**Severity:** Medium — the same shape as the filed one: a caller's bug (an unchecked `-1`, or a plain file fd) turns into a listener on, an accept from, or a connection planted in an UNRELATED socket's slot, with a success return. On agnos only.
**Affects:** 6.7.10 and the 6.7.11 lane tree (verified); the helpers date from v6.2.22.

## Summary

`lib/net.cyr`'s agnos arms hand their `fd` straight to the adapter's slot helpers in
`lib/syscalls_x86_64_agnos.cyr`, each of which indexes its table by `fd & 7` with no check that
`fd` is a tagged socket fd (`AGNOS_SOCK_TAG + 0..7`):

- `sock_bind(fd, …)` → `_agnos_listen_stash(fd, …)`: writes slot `fd & 7`'s listen port / class / ip.
- `sock_listen(fd, …)` → `_agnos_listen_start(fd)`: issues `sock_listen#56` with slot `fd & 7`'s
  stash and stores the listen id in that slot.
- `sock_accept(fd)` → `_agnos_fd_listen(fd)`: maps `fd` to slot `fd & 7`'s LISTEN id and accepts
  on it (`#57`), handing back a fresh tagged fd — `Ok`, for an fd that was never a socket.
- `sock_connect(fd, …)` → `sys_sock_connect` then `_agnos_sock_bind(fd, conn)`: stores the new
  conn in slot `fd & 7`, overwriting (and leaking) whatever conn that slot held.

A negative fd is slot 7; fd 1 (stdout) is slot 1; `AGNOS_SOCK_TAG + 9` is slot 1. On Linux the
same calls fail with `-EBADF` / `-ENOTSOCK` and touch nothing. The peer's BSD verbs
(`sys_bind` / `sys_listen` / `sys_connect` / `sys_accept4`) are NOT affected: each opens with
`if (_agnos_is_sock_fd(fd) == 0) { return 0 - 88; }`, and since 6.7.11 that test is exact.

## Reproduction

Built for agnos and run on an x86_64 Linux host (no socket syscall is issued: the bind only
stashes, and the other two lines call the helpers `sock_accept` / `sock_connect` reach):

```
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
fn show(label, v) { sys_write(1, label, strlen(label)); fmt_int(v); sys_write(1, "\n", 1); return 0; }
fn main() {
    _agnos_conn_init();
    var b_t, b = sock_bind(0 - 1, INADDR_ANY(), 8080);
    show("sock_bind(-1, 0.0.0.0, 8080) is_err       = ", is_err_result(b_t));
    show("slot 7 listen port after it               = ", load64(&_agnos_listen_port + 7 * 8));
    store64(&_agnos_listen_tbl + 7 * 8, 3);          # slot 7 is a LISTEN socket (listen id 2)
    show("_agnos_fd_listen(-1) (sock_accept's map)  = ", _agnos_fd_listen(0 - 1));
    store64(&_agnos_conn_tbl + 7 * 8, 5);            # slot 7 holds conn #4
    _agnos_sock_bind(0 - 1, 6);                      # sock_connect(-1)'s bind of a new conn #6
    show("slot 7 conn after _agnos_sock_bind(-1, 6) = ", load64(&_agnos_conn_tbl + 7 * 8) - 1);
    return 0;
}
main();
#ifdef CYRIUS_TARGET_AGNOS
var HOST_SYS_EXIT = 60;
#endif
syscall(HOST_SYS_EXIT, 0);
```

```sh
CYRIUS_TARGET_AGNOS=1 build/cycc < repro.cyr > repro && chmod +x repro && ./repro
```

Actual (6.7.11 lane tree):

```
sock_bind(-1, 0.0.0.0, 8080) is_err       = 0
slot 7 listen port after it               = 8080
_agnos_fd_listen(-1) (sock_accept's map)  = 2
slot 7 conn after _agnos_sock_bind(-1, 6) = 6
```

Expected: `sock_bind(-1, …)` is an `Err` (Linux: `EBADF`, 9) and slot 7 keeps port 0;
`_agnos_fd_listen(-1)` is -1, so `sock_accept(-1)` is an `Err` with no `#57`; `sock_connect(-1, …)`
is an `Err` before any `#47`, and slot 7 keeps conn #4.

## Root cause

`lib/syscalls_x86_64_agnos.cyr`: `_agnos_sock_bind`, `_agnos_listen_stash`, `_agnos_listen_start`
and `_agnos_fd_listen` each compute `var slot = fd & 7;` and never test `_agnos_is_sock_fd(fd)`;
`lib/net.cyr`'s agnos arms of `sock_bind` (:630), `sock_listen` (:648), `sock_accept` (:675) and
`sock_connect` (:713-718) call them with the caller's fd as given.

## Proposed fix

Answer a non-socket fd before any table or kernel access, as the BSD verbs already do: either
`if (_agnos_is_sock_fd(fd) == 0) { return 0 - 1; }` at the top of the four helpers (so every
caller is covered), or the same test in the four `net.cyr` arms returning `Err(9)` / `Err(88)`.
⚠ This changes what a program computes (an `Ok` becomes an `Err`) — the error code each arm
answers is the call to make at the fix. Rows: the repro above, verbatim; the fake kernel shows no
`#56` / `#57` / `#47` for a negative fd.
