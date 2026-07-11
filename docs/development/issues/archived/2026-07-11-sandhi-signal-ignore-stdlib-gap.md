# stdlib has no signal-disposition helper (`signal_ignore`) and no `MSG_NOSIGNAL`-aware `sock_send` — every server built on `sock_send` is one disconnected peer away from a SIGPIPE kill

**Discovered:** 2026-07-11 during a sandhi 1.8.x roadmap review (originally surfaced
sandhi 1.6.6, the SIGPIPE server-DoS fix — yeo-cy-test probe finding)
**Severity:** Medium (Linux has a raw-syscall workaround; **macOS has none — a
SIGPIPE server DoS with no clean consumer fix**, so the macOS dimension is
effectively High)
**Affects:** cycc — **re-verified absent through 6.4.49** (grep `lib/net.cyr` /
`lib/syscalls.cyr`)

## Summary

`lib/net.cyr`'s `sock_send(fd, buf, len)` is a **flagsless** `sys_write` — there is
no way to pass `MSG_NOSIGNAL` — and stdlib exposes **no signal-disposition helper**
(no `signal_ignore(signum)`, and `SIGPIPE` isn't even in the `Signal` enum). So when
a peer disconnects mid-response, the next `sock_send` to that socket raises
**SIGPIPE**, whose default disposition **terminates the process**. That is a trivial
**unauthenticated remote DoS** against *any* server built on `sock_send`: a client
that connects, triggers a response, and hangs up mid-write kills the server.

Consumers can't fix this cleanly at the stdlib boundary — they have to reach *past*
the `net.cyr` / `syscalls.cyr` contract and hand-roll a raw `rt_sigaction` to install
`SIG_IGN(SIGPIPE)`. sandhi did exactly that at 1.6.6, but the workaround is
**Linux-only**: on macOS the `ESYSXLAT` whitelist doesn't cover `sigaction`, so a
sandhi server on macOS is still SIGPIPE-vulnerable with no available workaround.

## Reproduction

Any server loop that `sock_send`s a response after the peer has closed:

```
# server: accept, then write a response
var c = sock_accept(listen_fd);
# ... peer connects then closes/RSTs before we finish writing ...
sock_send(c, big_response, big_len);   # → SIGPIPE → process terminated (signal 13)
```

Observed in sandhi's server loops (`sandhi_server_run` / `_run_async` /
`_run_pooled*`) and reproduced by disconnecting a client mid-response: the server
process dies with signal 13 rather than seeing `EPIPE` on the send. The 1.6.6 fix
(below) makes the same send return `EPIPE` (already ignored by the loop) instead of
killing the process.

## Root cause (speculation — flag for the Cyrius agent to confirm)

Two interacting gaps, both in stdlib source (not codegen):

1. `lib/net.cyr` `sock_send` is `fn sock_send(fd, buf, len): Result` — it forwards to
   a plain `sys_write` (or `send` without a flags argument), so there's no seam to
   set `MSG_NOSIGNAL` (Linux) / `SO_NOSIGPIPE` (macOS).
2. `lib/syscalls.cyr` has no `signal_ignore` / `sigaction` wrapper, and `SIGPIPE`
   isn't in the `Signal` enum — so there's no portable way to change SIGPIPE's
   disposition either.

Either one alone would close the hole; today neither exists.

## Proposed fix (either — both let sandhi drop its raw syscall)

1. **Portable `signal_ignore(signum)` in `lib/syscalls.cyr`** — Linux `rt_sigaction`
   (x86_64 syscall 13 / aarch64 134), macOS BSD `sigaction`, agnos no-op/serial.
   Add `SIGPIPE` (13) to the `Signal` enum. This is the cleaner *general* primitive:
   it fixes SIGPIPE for any server on any backend and, in one move, **portably closes
   sandhi's macOS gap** (which the raw-syscall workaround can't reach). Preferred.
2. **`MSG_NOSIGNAL`-aware `sock_send`** — e.g. a `sock_send_flags(fd, buf, len, flags)`
   (or make `sock_send` pass `MSG_NOSIGNAL` on Linux and set `SO_NOSIGPIPE` once at
   socket creation on macOS). Targeted at the socket path; doesn't help non-socket
   SIGPIPE, but is the most direct fix for servers.

Option (1) is the more reusable stdlib surface; (2) is the narrower socket fix. Not
blocking on the choice.

## Consumer-side workaround (shipped in sandhi 1.6.6 — Linux only)

sandhi installs `SIG_IGN` for SIGPIPE once at server startup via a raw syscall,
because it can't pass `MSG_NOSIGNAL` and stdlib has no signal helper:

```
# _sandhi_server_ignore_sigpipe() — raw rt_sigaction(SIGPIPE, SIG_IGN).
# One 32-byte { sa_handler = SIG_IGN, 0, 0, 0 } struct is valid for both ABIs.
#   x86_64:  syscall 13   (SYS_rt_sigaction)
#   aarch64: syscall 134  (SYS_rt_sigaction)
```

A send to a dead peer then fails `EPIPE` on the `sock_send` (which the serve loops
already ignore) instead of killing the process. **Linux only** — macOS is a
documented no-op (`ESYSXLAT` lacks `sigaction`, so the server stays vulnerable),
agnos is moot. This is the single place sandhi's server path reaches past a stdlib
helper; sandhi will drop it the moment either fix above lands
(mirrors the 1.6.1/1.6.2 migrations onto `net_connect_nb` / `sock_set_nonblocking`).

**Consumer version:** sandhi 1.8.1 on cycc **6.4.49**. Recommended minimum for the
fix to deploy: whichever release lands `signal_ignore` (or the `MSG_NOSIGNAL`-aware
`sock_send`). Tracked sandhi-side in `docs/development/roadmap.md`
("Wait-for-stdlib-prerequisite").
