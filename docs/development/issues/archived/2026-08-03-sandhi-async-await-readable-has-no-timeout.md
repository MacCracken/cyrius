# `async_await_readable` hardcodes an infinite epoll timeout, so a cooperative server cannot be woken

> ✅ **RESOLVED in cyrius 6.5.6 (2026-08-03)** — same day as filing, in the W1 reactive
> window. `async_await_readable_ms(fd, ms)` added exactly as proposed: **1** for readable,
> **0** for timeout, negative `ms` blocks forever; `async_await_readable` kept as a
> wrapper returning `0`, so no existing call site moves. The filing's point that *the
> return value matters as much as the timeout* was the load-bearing one and is pinned by
> two opposing gate axes — a variant hardwired to 1, or to 0 (the old contract), each
> passes one axis and fails the other. EINTR reports 0, the same as a timeout: the
> caller's loop re-checks and waits again, which is correct for both.
>
> sandhi 1.9.9 was folded in the **same release**, so the `SANDHI_SERVER_STOP_POLL_MS`
> workaround this filing describes can now go back to parking in epoll — the idle
> stop-enabled server stops waking ~10×/sec and shutdown latency stops being bounded by
> the poll interval. Gated by `tests/async_await_readable_ms.sh` (6 axes,
> mutation-proven), whose axis 4 is this filing's exact shape: an idle listener whose
> loop must observe a flag set by another thread.

**Status:** ✅ **RESOLVED** — filed 2026-08-03, fixed in 6.5.6 the same day.
**Placement:** shipped in v6.5.6 (W1 reactive window).
**Discovered:** 2026-08-03 while adding a cooperative stop facility to sandhi's five serve loops.
**Severity:** Medium — hard failure with a shipped workaround that costs idle wakeups.
**Affects:** cycc 6.5.5 and every earlier 6.x carrying `lib/async.cyr`.

## Summary

`async_await_readable(fd)` (`lib/async.cyr:808`) parks in `sys_epoll_wait` with
a **hardcoded `-1` timeout** (`:823`) and `lib/async.cyr` exposes no
timeout-carrying variant. A caller that parks there is therefore unwakeable by
anything except data on `fd` — no flag, no deadline, no cancellation.

That is fine for a server whose only job is to serve. It is not fine for one
that must also be able to **stop**: an idle cooperative accept loop blocks in
this call indefinitely, so a shutdown request set by another thread or a signal
handler is never observed. There is no way to express "wait for readable, but no
longer than N ms" with what `lib/async.cyr` exports, even though the underlying
`sys_epoll_wait` takes the timeout as an ordinary argument.

`async_with_timeout(rt, handle, ms)` (`:643`) does **not** cover this: it races
a *spawned task* against a deadline sentinel inside a runtime, whereas this is a
bare fd-readiness wait taken outside any task, on the accept path, before a
runtime is meaningfully in play.

## Reproduction

Any program that parks on an idle fd and expects to observe an external flag:

```cyrius
var STOP = 0;

fn _stopper(arg) { sleep_ms(250); STOP = 1; return 0; }

fn main(): i64 {
    alloc_init();
    var sfd = payload(tcp_socket());
    sock_reuse(sfd);
    sock_bind(sfd, INADDR_LOOPBACK(), 0);
    sock_listen(sfd, 16);
    sock_set_nonblocking(sfd);

    thread_create(&_stopper, 0);

    while (1 == 1) {
        if (STOP != 0) { println("stopped"); return 0; }
        async_await_readable(sfd);   # nothing ever connects -> parks forever
    }
    return 0;
}
```

Saved as
[`repros/2026-08-03-sandhi-await-readable-no-timeout.cyr`](./repros/2026-08-03-sandhi-await-readable-no-timeout.cyr).
Build from a project root (a bare `.cyr` gets no stdlib auto-prepend).

Expected: prints `stopped` after ~250 ms. Actual: **hangs** — the flag is set on
time and never read, because control never leaves `async_await_readable`.
Verified on cycc 6.5.5, x86-64 Linux, 2026-08-03: `timeout 6 ./build/await`
reports `exit=124` and prints nothing.

## Root cause

`lib/async.cyr:808-826`. The helper builds its own epfd, registers `fd`, and
calls:

```cyrius
sys_epoll_wait(epfd, &revents, 1, 0 - 1);
```

The `0 - 1` is the entire issue — `sys_epoll_wait` already takes the timeout as
its fourth argument, so the capability is present one line down and simply not
surfaced. Everything else about the helper (the per-call epfd, the arch-split
`data` offset) is unaffected.

## Proposed fix

Add a timeout-carrying variant and make the existing name a wrapper, so no
caller changes:

```cyrius
# Wait for fd to be readable, or until `ms` elapses. Returns 1 if readable,
# 0 on timeout. `ms` < 0 blocks forever (the async_await_readable behaviour).
fn async_await_readable_ms(fd, ms): i64 { ... sys_epoll_wait(epfd, &revents, 1, ms) ... }

fn async_await_readable(fd): i64 {
    return async_await_readable_ms(fd, 0 - 1);
}
```

The return value matters as much as the timeout: today the helper returns a
constant `0` and discards `sys_epoll_wait`'s result, so even with a timeout a
caller could not distinguish "readable" from "timed out". A variant that
answers that question is what makes it usable; keeping the old function
returning `0` preserves every existing call site.

## Consumer-side workaround

sandhi 1.9.9 ships a bounded sleep in `sandhi_server_run_async`, taken **only**
when a stop flag is configured:

```cyrius
if (stop_ptr == 0) {
    async_await_readable(sfd);            # unchanged pre-1.9.9 behaviour
} else {
    sleep_ms(SANDHI_SERVER_STOP_POLL_MS);  # 100 ms
}
```

This is deliberately **not** a local copy of a timeout-capable
`async_await_readable`: sandhi's CLAUDE.md makes a missing stdlib primitive a
cyrius patch rather than a sandhi feature ("compose, don't reimplement"), so
forking the helper into sandhi was rejected in favour of filing this.

The cost of the workaround is what the fix would remove: an idle stop-enabled
cooperative server wakes ~10×/sec instead of parking in epoll, and shutdown
latency is bounded by the poll interval rather than being immediate. The other
four sandhi serve loops do not need this — they use blocking `accept` and are
handled with `SO_RCVTIMEO` on the listen fd, which has no equivalent gap.
