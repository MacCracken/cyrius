# agnos: a blocking socket read gives up after about a second when other processes are ready — `_agnos_sock_recv_block`'s spin backstop fires before its RTC deadline — OPEN

**Status:** 🟡 **OPEN**: the backstop documented as being "for when the RTC is unreadable" is applied
whether the RTC reads or not, and it counts pauses, which do not take a fixed time on agnos.
**Placement:** unpinned — 6.6.x-line backlog.
**Discovered:** 2026-09-23 during daimon 2.4.2. daimon's AGNOS guest test failed in CI on a forwarded
MCP call, and in one of three local runs. Timing 6000 pauses in the guest then made the cause
measurable (below).
**Severity:** Medium-high for consumers: a read that waits more than about a second for its peer
returns 0, which callers take for EOF. Nothing tells it apart from a real close. In daimon, a
forwarded MCP call whose server took longer than that was answered 502 (measured). Its `web_fetch`
reads through the same path.
**Affects:** cycc 6.6.6 on the agnos target: `lib/syscalls_x86_64_agnos.cyr`, `_agnos_sock_recv_block`
(`:1659`–`:1675`), with `AGNOS_SOCK_RECV_MAX_SPINS = 6000` (`:584`). It applies on agnos kernels where
`pause`#14 yields to a ready process before it halts. agnos 1.57.5 does (`kernel/arch/x86_64/syscall_hw.cyr`
`:126`–`:136`: "it must YIELD to other ready procs").

## Summary

On agnos, `sys_read` on a socket calls `_agnos_sock_recv_block` (`:673`). That polls `sock_recv`#49
and pauses between polls. Two bounds apply: `sys_time_unix() + AGNOS_SOCK_RECV_TIMEOUT_S` (30 s), and
`AGNOS_SOCK_RECV_MAX_SPINS` (6000) pauses. The comment at `:581` describes the second as *"a
hlt-count backstop for when the RTC is unreadable"*, but it is applied whether or not the RTC reads.
And a pause is not a hlt. agnos's `pause`#14 first yields to any ready process, through
`sys_sched_yield`, and returns as soon as the scheduler comes back. It halts only when nothing else
is ready. With a few processes ready, 6000 pauses pass in about a second, and the read returns 0
though the peer has neither closed nor stopped.

## Reproduction

Measured in daimon's guest test: agnos 1.57.5 and gnoboot 0.7.2 (the released binaries) under QEMU
TCG, with daimon's server loop, its agents, the test's launcher and the test client running.

- 6000 `sys_pause()` calls from the test client took **1084 ms** in one run and **1094 ms** in
  another.
- A request from daimon (sandhi's HTTP client, in a child process) to a server in the guest that
  answers after **3 s**: the read returned 0 about 2 s after the request was sent. sandhi reported
  a transport failure, and daimon answered 502. A second run, with a server answering after 5 s,
  failed the same way.
- The same server answering at once, or daimon with the workaround below and the server answering
  after **5 s**: the whole 9 KB answer arrived.

The shape of it:

```cyrius
# the peer is alive and answers after 3 s
var n = sys_read(sock_fd, buf, 4096);   # 0 after ~1 s, taken for EOF
```

## Root cause

`:1667`–`:1671`:

```cyrius
var now = sys_time_unix();
if (now != 0) { if (now >= deadline) { return 0; } }
spins = spins + 1;
if (spins > AGNOS_SOCK_RECV_MAX_SPINS) { return 0; }
sys_pause();
```

The spin count runs even when `now != 0`. And 6000 pauses are about 60 s only if each is a 10 ms
halt.

## Proposed fix

Count spins only when the RTC is unreadable, which is what the comment says the backstop is for:

```cyrius
var now = sys_time_unix();
if (now != 0) {
    if (now >= deadline) { return 0; }
} else {
    spins = spins + 1;
    if (spins > AGNOS_SOCK_RECV_MAX_SPINS) { return 0; }
}
sys_pause();
```

Better, bound the wait by `uptime_us`#95, falling back to `uptime_ms`#40 when #95 answers -1. That
depends on neither the RTC nor how long a pause lasts. (The RTC's 1 s resolution also makes today's
30 s bound anything from 29 to 30 s.)

A timeout could also be told apart from EOF. Today both are 0: a caller that frames by
Content-Length, as sandhi does, sees a short body, and one that reads to EOF sees a truncated stream.

## Consumer-side workaround

daimon 2.4.2: `daimon_agnos_recv_bound()` in `src/syscalls.cyr`, run at the start of `serve` on
agnos. When `sys_time_unix()` reads, it sets `AGNOS_SOCK_RECV_MAX_SPINS` beyond reach, so the RTC's
30 s decides. daimon's detached calls run in forked children, which inherit it. Where the RTC does
not read, the backstop is left as it is. daimon's guest test now has an MCP server that answers
after 5 s. Without the workaround it failed (502) in both runs made; with it the test passed 9 runs
of 9.
