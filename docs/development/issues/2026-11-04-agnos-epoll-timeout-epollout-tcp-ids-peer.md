# `lib/syscalls_x86_64_agnos.cyr` has no peer for agnos 1.57.17's blocking `epoll_wait`#21, `EPOLLOUT` and TCP-id watches

**Status:** 🟡 **OPEN** — filed by agnos (2026-11-04). agnos built the ABI in its 1.57.17 cut (no new syscall number:
a flag folded into #21's `max`, a new op 3 on #20), where it is reviewed and gated (`scripts/smoke/epoll-smoke.sh`).
Do not add the constants before agnos's `1.57.17` tag.
**Placement:** `lib/syscalls_x86_64_agnos.cyr` — the `SYS_EPOLL_*` comments (:81-:83) and the three wrappers
`sys_epoll_create` / `sys_epoll_ctl` / `sys_epoll_wait` (:1980-:1988); `lib/async_agnos.cyr`, whose comments say
"no epoll parking" (:7, :43, :90, :250, :368), can park on it once the peer exists.
**Filed:** 2026-11-04, by agnos. agnos owns the ABI (`agnos/docs/development/agnos-userland-abi.md` rows #19-#21);
cyrius owns the peer.
**Affects:** cyrius **6.7.18**. The ABI exists from agnos **1.57.17**.
**Severity:** **Low as a defect, blocking for the consumers.** agora (`agora/src/main.cyr:3801-3907`) serves every
session from one process on agnos and sends with `sock_send_dl`#109 no-wait; with nothing to wait on for "the held
segment was ACKed" it yields (`sys_sched_yield`) and moved 276-415 KB/s where agnos's own `#48` moves 2,680 KB/s
(agnos issue `2026-10-31-tcp-send-keeps-one-segment-in-flight`). Measured on agnos 1.57.17 (KVM, `-smp 4`): #109
no-wait + one EPOLLOUT wait per segment **4,363-4,653 KB/s** vs #48 7,636-7,682 KB/s vs #109 + #44 135-136 KB/s; a
bystander's worst steady-state echo beside a client that reads nothing ≤ 1 ms. Consumers that already call the
Linux-shaped 4-argument `sys_epoll_wait(epfd, events, max, timeout)` on agnos — kybernet `src/lib/eventloop.cyr:183`
(PID 1), daimon `src/server.cyr:882`, thoth `src/tui.cyr:2612` — get their 4th argument DROPPED by today's 3-parameter
peer, so their loops poll.

## The kernel ABI (agnos 1.57.17)

- **`epoll_wait`#21(epfd, events, max, timeout_ms)** — the timeout (a4) is read ONLY when `max` carries
  **`EPW_TIMED` = bit 32 (`0x100000000`)**; without it the call is the old poll, byte for byte (a 3-argument call
  leaves a4 = a stale r10, which is why the opt-in exists). `timeout_ms > 0` waits up to that long (never early),
  `< 0` forever, `0` polls. Returns n ≥ 1 records, **0** (timeout), **-4** (Linux's `-EINTR` value: a signal was posted
  during the wait, nothing is ready, and it is neither blocked by `sigprocmask`#17 nor SIGCONT), **-1** bad args (a
  timed call with `max == 0` is -1). `max` clamps to **128** (was 16). Record unchanged: `{u32 mask; u64 data}`, 12 B.
- **`epoll_ctl`#20 op 3 = SET**(epfd, 3, target, events) — `events` (a4): `EPOLLIN` 0x001 · `EPOLLOUT` 0x004 ·
  `EPOLLRDHUP` 0x2000 (other bits ignored; `EPOLLERR` 0x008 / `EPOLLHUP` 0x010 always reported); **`events == 0`
  deletes** (-1 when nothing named the target). SET replaces every watch of the target (add and modify are one call).
  `target`: a VFS fd 0..31 that is a signalfd / timerfd / kernel socket fd, or **`EP_TCP` (`0x10000`) `| id`** — a TCP
  conn or listener id 0..7 the CALLER owns. The record's `data` is the target as given (agnos keeps no user data).
  Ops 1 (ADD, EPOLLIN) and 2 (clear all) are unchanged. Limit 128 watches per instance (was 8).
- Readiness: conn `EPOLLIN` = bytes queued or EOF; **`EPOLLOUT` = no held (unACKed) segment** — the next #48/#109
  commits without waiting; `EPOLLRDHUP` = the peer's FIN; `EPOLLIN|EPOLLERR|EPOLLHUP` = the conn died (RST, retransmit
  exhaustion). Listener `EPOLLIN` = #57 would return a conn now.

## The ask

```
var EPW_TIMED = 0x100000000;          # epoll_wait max bit 32: a4 is the timeout (agnos 1.57.17)
var EP_TCP = 0x10000;                 # epoll_ctl op-3 target: EP_TCP | a kernel conn / listen id (agnos 1.57.17)
enum AgnosEpoll { EPOLL_CTL_SET = 3; EPOLLIN = 0x001; EPOLLOUT = 0x004; EPOLLERR = 0x008; EPOLLHUP = 0x010; EPOLLRDHUP = 0x2000; }

# Linux-shaped: the timeout is a4 under EPW_TIMED (a kernel before 1.57.17 ignores the flag's bit and polls — max
# clamps to 16 there, so a caller passing max <= 16 sees the same records).
fn sys_epoll_wait(epfd, events_ptr, max, timeout): i64 {
    return syscall(SYS_EPOLL_WAIT, epfd, events_ptr, max | EPW_TIMED, timeout);
}
# The native op-3 SET (events 0 = delete).
fn sys_epoll_set(epfd, target, events): i64 { return syscall(SYS_EPOLL_CTL, epfd, EPOLL_CTL_SET, target, events); }
```

⚠ **A kernel before 1.57.17 with `EPW_TIMED`:** its #21 rejected nothing on `max` (a value above 16 clamps to 16), so
`max | EPW_TIMED` reads as 16 — the call polls; the peer's caller then loops as it does today. ⛔ But it then writes up
to **16** records (its instances hold at most 8 watches, so at most 8 = 96 B): a caller whose buffer holds fewer than
`min(8, its watch count)` records can be overrun there. Either size the buffer for 8 records, or probe the kernel once
and pass the flag only on 1.57.17+ (a 1 ms timed wait on an empty instance takes ≥ 1 ms only there).

**The tagged socket fds.** cyrius hands sockets out as `AGNOS_SOCK_TAG | slot`, not as kernel ids. A Linux-shaped
`sys_epoll_ctl(epfd, op, fd, event)` on agnos would map: a tagged CONN fd → `EP_TCP | _agnos_fd_conn(fd)`, a tagged
LISTEN fd → `EP_TCP | (_agnos_listen_tbl[slot] - 1)`, any other fd as itself; `EPOLL_CTL_ADD` / `MOD` → op 3 with
`load32(event)`, `EPOLL_CTL_DEL` → op 3 with 0 (agnos op 2 clears ALL watches — never map Linux DEL to it); and on the
way back translate a record's `EP_TCP | id` data to the tagged fd that holds `id` and replace it with the caller's
`epoll_data` (a side table keyed by target — the kernel reports the target, not user data). ⚠ The readiness STASH
(`_agnos_listen_pend`, `_agnos_peek`, :734) holds items the kernel no longer sees: a peer that waits must first report
any stashed conn / byte as ready itself (as `async_await_readable_ms` already must), or a pre-accepted conn sleeps.

## How to confirm

agnos's `scripts/smoke/epoll-smoke.sh` drives the raw ABI (its `tests/epoll/epw.cyr` uses `syscall(21, …)` directly).
For the peer: a `--agnos` test that `sys_epoll_wait(ep, buf, 4, 200)` on an instance with nothing ready returns 0
after ≥ 200 ms on agnos 1.57.17, and a tagged accepted socket SET for `EPOLLIN` wakes it when the host sends a byte.

## Also waiting: taar (added 2026-11-09)

taar's AGNOS `taar_tcp_recv` reports a reset connection as a clean close (0),
because `sock_recv#49` answers -1 for both. Linux returns -ECONNRESET. The
kernel already tells them apart through this issue's ABI: on `EP_TCP | conn`,
`EPOLLIN | EPOLLERR | EPOLLHUP` means a dead connection and `EPOLLRDHUP` a FIN.

taar would issue `sys_epoll_set(ep, EP_TCP | conn, EPOLLIN | EPOLLRDHUP)` and
then a 0-ms `sys_epoll_wait` when `#49` says -1, so it needs this issue's
`EP_TCP`, `EPOLL_CTL_SET`, the `EPOLL*` bits and the timed wait.

agnos never frees an epoll instance's watch list. So until agnos issue
`2026-11-09-an-epoll-instance-is-never-freed-so-short-lived-ones-run-the-heap-dry`
lands, taar would keep one instance per process rather than one per check. That
issue also asks agnos for a distinct `#49` answer, which would make this
unnecessary for taar. The gap is taar's open target difference "Reset vs clean
close" (taar ADR 0001).
