# agnos: a negative fd is taken for a tagged socket — `sys_write(-1, …)` sends on socket slot 7's connection, and `sys_close(-1)` returns 0 after freeing slot 7 — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-12 against the published 6.7.9 (`~/.cyrius/versions/6.7.9/lib/syscalls_x86_64_agnos.cyr`), by the run below and by reading the four call paths.
**Placement:** Unplaced — filed from darshana 1.3.0 (2026-10-12). Only the user places it.
**Discovered:** 2026-10-12, darshana's 1.1.4 audit: its AGNOS `tty_close_signalfd(-1, …)` (the teardown after a failed `tty_open_signalfd`) freed socket slot 7. darshana has guarded since; this is the stdlib half.
**Severity:** Medium — a caller's bug (an unchecked `-1` from a failed open) turns into bytes sent to an unrelated network peer, or into a live connection silently torn down, with a success return. Not Critical only because it needs that caller bug to trigger.
**Affects:** 6.7.9, verified. The adapter dates from the `v6.2.3` notes in `sys_read` / `sys_close`; earlier releases were not checked.

## Summary

The agnos socket adapter hands out tagged fds `AGNOS_SOCK_TAG | slot` (`0x40000000 | 0..7`) and recognizes one with
`_agnos_is_sock_fd`, which tests only `fd & AGNOS_SOCK_TAG`. **Every negative i64 has that bit set**, so `-1` — the
value every failed open returns — is taken for socket slot `-1 & 7 = 7`:

- `sys_write(-1, buf, n)` → `_agnos_fd_conn(-1)` → slot 7's connection → `_agnos_sock_send_all`: the bytes go to
  whatever peer slot 7 is connected to.
- `sys_read(-1, buf, n)` reads from that connection.
- `sys_close(-1)` (and so `file_close(-1)`) clears all of slot 7's state, sends FIN on its connection if one is live,
  and returns 0 — success, for an fd that was never open.

On Linux the same calls fail with `-EBADF` and touch nothing.

## Reproduction

Built `--agnos` and run on an x86_64 Linux host, which works because the probe issues no socket syscall: it fakes a
live connection in slot 7's table entry, then clears it before the close so that close returns without a kernel call.

```
# cyrius.cyml: cyrius = "6.7.9", [deps] stdlib = ["syscalls", "string", "fmt", "io"]
fn show(label, v) { sys_write(1, label, strlen(label)); fmt_int(v); sys_write(1, "\n", 1); return 0; }
fn main() {
    _agnos_conn_init();
    show("_agnos_is_sock_fd(-1)       = ", _agnos_is_sock_fd(0 - 1));
    show("_agnos_is_sock_fd(-9)       = ", _agnos_is_sock_fd(0 - 9));
    store64(&_agnos_conn_tbl + 7 * 8, 5);            # slot 7 holds conn #4 (stored +1)
    show("_agnos_fd_conn(-1)          = ", _agnos_fd_conn(0 - 1));
    store64(&_agnos_conn_tbl + 7 * 8, 0);            # no kernel close below
    store64(&_agnos_sock_rcvto_us + 7 * 8, 12345);
    show("sys_close(-1) returns       = ", sys_close(0 - 1));
    show("slot 7 rcvto after close(-1) = ", load64(&_agnos_sock_rcvto_us + 7 * 8));
    return 0;
}
main();
#ifdef CYRIUS_TARGET_AGNOS
var HOST_SYS_EXIT = 60;   # the Linux host's exit(2)
#endif
syscall(HOST_SYS_EXIT, 0);
```

```sh
cyrius deps && cyrius build --agnos repro.cyr build/repro && ./build/repro
```

Actual (6.7.9):

```
_agnos_is_sock_fd(-1)       = 1
_agnos_is_sock_fd(-9)       = 1
_agnos_fd_conn(-1)          = 4
sys_close(-1) returns       = 0
slot 7 rcvto after close(-1) = 0
```

Expected: `_agnos_is_sock_fd` is 0 for a negative fd, `_agnos_fd_conn(-1)` is -1, and `sys_close(-1)` is -1 with
slot 7 untouched.

## Root cause

`lib/syscalls_x86_64_agnos.cyr` at 6.7.9:

- `_agnos_is_sock_fd` (:2393) — `if ((fd & AGNOS_SOCK_TAG) != 0) { return 1; }`. The only producer of a tagged fd
  is `return AGNOS_SOCK_TAG | i;` (:2407), with `i` in 0..7, so a tagged fd is always positive and at most
  `AGNOS_SOCK_TAG + 7`.
- `_agnos_fd_conn` (:2459) and `sys_close` (:971) then index the tables by `fd & 7`.
- Callers that take the socket branch on a negative fd: `sys_write` (:920), `sys_write_nb` (:933), `sys_read`
  (:953), `sys_read_nb` (:965), `sys_close` (:972).

## Proposed fix

Recognize exactly the values the adapter hands out:

```
fn _agnos_is_sock_fd(fd): i64 {
    if (fd >= AGNOS_SOCK_TAG && fd <= AGNOS_SOCK_TAG + 7) { return 1; }
    return 0;
}
```

A negative fd then falls through to the kernel call, which rejects it. Every `== 0` caller (:2011 onward, the
socket-only entry points) keeps returning its error for a negative fd as before.

## Consumer-side workaround

Never pass a negative fd to `sys_close` / `file_close` / `sys_read` / `sys_write` on agnos. darshana's AGNOS
`tty_close_signalfd` does `if (fd >= 0) { file_close(fd); }` since 1.1.4.
