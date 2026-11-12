# `fd_wait_ready` declines on agnos, and `sock_connect`#47 has no caller deadline in the peer — agnos 1.57.18 has both

**Status:** 🟡 **OPEN** — filed by agnos (2026-11-08). agnos built the kernel half in its 1.57.18 cut (no new syscall
number: `#97` channel endpoints become `epoll_wait`#21 targets, and a flag folded into `sock_connect`#47's src_port),
where it is reviewed and gated (`scripts/smoke/pty-backpressure-smoke.sh`). Do not add the constants before agnos's
`1.57.18` tag.
**Placement:** `lib/syscalls_x86_64_agnos.cyr` — `fd_wait_ready` (:919, today `return 0 - 38`), `SYS_SOCK_CONNECT`'s
comment (:551) and `sys_sock_connect` (:2037); `lib/net.cyr` `net_connect_nb` / `net_connect_sa_nb`'s agnos arms
(:1025-:1037, "AGNOS has no non-blocking connect … timeout_ms is advisory here").
**Builds on:** `2026-11-04-agnos-epoll-timeout-epollout-tcp-ids-peer.md` (the `EPW_TIMED` / op-3 SET / `EP_TCP` peer,
still open). This issue needs that one's constants; it does not repeat them.
**Filed:** 2026-11-08, by agnos. agnos owns the ABI (`agnos/docs/development/agnos-userland-abi.md` rows #1, #20, #21,
#47, #97); cyrius owns the peer.
**Affects:** cyrius **6.7.18**. The ABI exists from agnos **1.57.18**.
**Severity:** **Medium for the consumers.** thoth's `[hoosh].timeout_ms` counts frames at sandhi's idle turn, which
comes from `fd_wait_ready`; on agnos that call declines, so the stream loop goes straight into a blocking read: a
2.5 s deadline ran 10.7 s against a keep-alive every 500 ms (agnos issue `2026-11-06-no-readiness-wait-on-one-fd`).
thoth's startup probe asks `net_connect_nb(…, 3000)` and gets #47's own ~8 s (8.7 s measured to a blackholed address).
A surface cannot wait on its `#97` event channel without spinning (thoth F8).

## The kernel ABI (agnos 1.57.18)

- **A `#97` channel endpoint fd is an `epoll_ctl`#20 op-3 target** — only one the caller may USE (its owner, or a PTY
  descendant of the owner; an inherited inert claim is -1). Readiness: `EPOLLIN` = its inbox is non-empty or the peer
  is gone · `EPOLLOUT` = the peer's inbox has a free slot (a display channel always) · peer gone =
  `EPOLLIN | EPOLLOUT | EPOLLHUP` (+ `EPOLLRDHUP` when asked). Authority is re-derived every pass: a claim that turns
  inert later reports nothing.
- **So ONE watch is a readiness wait on ONE fd** with a deadline in ms that consumes nothing — SET it on an instance,
  wait with `EPW_TIMED`, DELETE it — for the fd kinds `epoll_wait`#21 watches: a channel, a signalfd, a timerfd, a
  kernel socket fd (VFS_SOCK), and `EP_TCP | id` for a ring-3 TCP conn or listener (cyrius's tagged socket fds name an
  id, not a kernel fd). ⛔ Keep the instance: agnos never frees an epoll instance's watch list (row 19), so a fresh
  `epoll_create` per wait leaks 128 B of kernel heap per call.
- **`sock_connect`#47 — `SC_TIMED` = bit 32 of src_port** (a3 = `0x100000000 | src_port`) opts in, and then **a4 is
  the timeout in ms**: `> 0` = min(a4, the ~8 s ceiling), measured once from entry; `< 0` = the ceiling alone; **`0` =
  NON-BLOCKING** — the SYN goes out and the id comes back at once; `EPOLLOUT` on `EP_TCP | id` = connected,
  `EPOLLERR | EPOLLHUP` = refused / exhausted (then close it with #50). A spent deadline returns -1 with the slot
  released. Without the bit a4 is never read and a3 means what it did (only `a3 >> 32 == 1` opts in; a negative a3
  still means "auto port").
- **Also new in 1.57.18 and visible to the peer:** `write`#1 on a TERMINAL channel (either end endowed in PTY mode)
  has back-pressure — `a4 == 0` waits for room and takes the whole buffer (it used to take ≤ 64 bytes and drop the
  oldest record of a full inbox), `a4 != 0` takes what fits, 0 when nothing does. `sys_write` (a4 = 0) and
  `sys_write_nb` (a4 = 1) already pass a4 explicitly, so no wrapper change is needed; a caller that looped on 64-byte
  short writes stays correct.

## The ask

```
var SC_TIMED = 0x100000000;          # sock_connect#47 src_port bit 32: a4 is the deadline in ms (agnos 1.57.18)

# fd_wait_ready on agnos: ONE watch on a per-process epoll instance, SET for this wait and DELETED after it.
# 1 ready · 0 timeout · -9 not a waitable fd · -4 EINTR (as Linux).
# ⛔ NOT a fresh instance per call: agnos never frees an epoll instance's watch list (ABI row 19 — a child that
# inherited the fd names the same list), so `epoll_create` per wait leaks 128 B of KERNEL heap per call.
var _agnos_fwr_ep = 0 - 1;
fn fd_wait_ready(fd, want_write, timeout_ms): i64 {
    var tg = fd;
    if (_agnos_is_sock_fd(fd) == 1) {
        # The STASH first: a pre-accepted conn (_agnos_listen_pend) or a peeked byte (_agnos_peek) is READY now —
        # the kernel no longer sees it, so a wait would sleep through it.
        if (want_write == 0) { if (_agnos_sock_stash_ready(fd) == 1) { return 1; } }
        var c = _agnos_fd_conn(fd);                       # a CONN fd; a LISTEN fd maps through _agnos_listen_tbl
        if (c < 0) { c = _agnos_fd_listen_id(fd); }
        if (c < 0) { return 0 - 9; }
        tg = EP_TCP | c;
    }
    var ms = timeout_ms;
    if (ms < 0) { ms = 0 - 1; }
    if (ms > 0x7FFFFFFF) { ms = 0x7FFFFFFF; }
    if (_agnos_fwr_ep < 0) { _agnos_fwr_ep = sys_epoll_create(); }   # once per process (a child re-creates: see below)
    var ep = _agnos_fwr_ep;
    if (ep < 0) { return 0 - 12; }
    var ev = EPOLLIN;
    if (want_write != 0) { ev = EPOLLOUT; }
    if (sys_epoll_set(ep, tg, ev) != 0) { return 0 - 9; }   # not a watchable fd, or not the caller's
    var rec[16];                                        # one {u32 mask; u64 data} record (12 B)
    var r = sys_epoll_wait(ep, &rec, 1, ms);            # the 2026-11-04 peer: max | EPW_TIMED, a4 = ms
    sys_epoll_set(ep, tg, 0);                           # DELETE: the instance holds no watch between calls
    if (r < 0) { return r; }                            # -4 EINTR, -1 bad args
    if (r == 0) { return 0; }
    return 1;                                           # EPOLLERR / EPOLLHUP count as ready: the next call says why
}

# #47 with a caller deadline (ms > 0), the ceiling (ms < 0), or non-blocking (ms == 0: the id at once).
fn sys_sock_connect_dl(dst_ip, dst_port, src_port, ms): i64 {
    var c = syscall(SYS_SOCK_CONNECT, dst_ip, dst_port, SC_TIMED | (src_port & 0xFFFFFFFF), ms);
    _agnos_accept_mark(c, 0);
    _agnos_peek_clear(c);
    return c;
}
```

`net_connect_nb(fd, addr, port, timeout_ms)`'s agnos arm then becomes: `sys_sock_connect_dl(…, timeout_ms)` (the kernel
honours the deadline and releases the slot itself when it is spent) — or, for a caller that wants Linux's shape, the
non-blocking form plus `fd_wait_ready(fd, 1, timeout_ms)` and #50 on a timeout or `EPOLLERR | EPOLLHUP`.
⚠ Three syscalls per wait (SET, wait, DELETE) on one instance per process. ⛔ A child spawned by #43 INHERITS the
parent's fd table, so its copy of `_agnos_fwr_ep` names the parent's instance — the SAME watch list in the kernel
(row 19). Two processes setting and deleting watches on one list would see each other's targets: a peer must
re-create its instance in a child (e.g. remember the pid that created it, `sys_getpid`#2, and create a fresh one when
it differs — the parent's copy is then an fd the child never uses).
⚠ **A kernel before 1.57.18:** op 3 SET of a channel fd is -1 (→ -9 here, the right "cannot wait" answer), and #47
with `SC_TIMED` reads the bit as an auto port, ignores a4 and waits its ~8 s — so a caller that needs the deadline
should probe once (`sys_sock_connect_dl` with ms 0 to a closed loopback port returns an id ≥ 0 at once on 1.57.18 —
close it — and -1 before).

## A self-proving repro (once the peer exists)

On agnos 1.57.18: mint a channel (`#97` CH_MINT), `fd_wait_ready(fa, 0, 300)` returns 0 after ≥ 300 ms; write one
record from `fb`, and it returns 1 at once; `fd_wait_ready(fa, 1, 0)` returns 1 (a display channel is always
writable). A tagged socket connected to a host that sends a byte after 200 ms: `fd_wait_ready(fd, 0, 2000)` returns 1
at ~200 ms. `sys_sock_connect_dl(ip4(127,0,0,1), <a listener whose backlog is full>, 0, 1500)` returns -1 at 1.5 s
(agnos's own fixture: `tests/chan/ptybp.cyr` `fx_up`). agnos's raw-ABI exerciser is `tests/chan/ptybp.cyr`
(`scripts/smoke/pty-backpressure-smoke.sh`, booted at `-smp 1` and `-smp 4`).

## Compatibility

Nothing existing changes for Linux or macOS. On agnos `fd_wait_ready` stops declining, so sandhi's stream loop gets
its idle turn and `http.cyr:218`'s retry loop sees real readiness; `net_connect_nb`'s timeout stops being advisory.
`agnos_abi_doc_parity` gains nothing (no new number).

## Also waiting: taar (added 2026-11-09)

taar is the network substrate under whirl, dig and yo. Its AGNOS arm calls
`sys_sock_connect(dst_ip, dst_port, src_port)` directly (`taar/src/socket.cyr`,
`taar_tcp_connect`), so an AGNOS connect waits the kernel's ~8 s whatever
`taar_tcp_set_timeout_ms` asked for. Its contract records this as an open
target difference (taar ADR 0001, "Connect deadline"); the Linux arm honours
the timeout.

The `sys_sock_connect_dl` proposed above is the exact call taar would use, with
the socket's timeout as `ms`, plus the probe this issue describes for kernels
before 1.57.18. Nothing more is needed from cyrius for taar.
