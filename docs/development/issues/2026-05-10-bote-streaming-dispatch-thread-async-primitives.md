# Cyrius: bote needs `lib/thread.cyr` MPSC + `lib/async.cyr` cancellation polling + per-thread request buffers to ship streaming dispatch

**Filed:** 2026-05-10
**Reporter:** bote (MCP core service, v2.7.1)
**Cyrius version at time of report:** 5.10.34 (release tarball + source archive)
**Affected stdlib:** `lib/thread.cyr`, `lib/async.cyr`, allocator/heap surface
**Severity:** **P2** — bote ships fine without it; the streaming-dispatch
backlog item (`dispatcher_dispatch_streaming` + `$/cancelRequest` mid-stream
handling) has been on the bote roadmap since 1.x and is the only major
spec capability bote can't honor without these primitives. There is no
consumer-side workaround that doesn't compromise correctness.
**Status:** open. **Expected target:** **5.11.x arc** (language agent has acknowledged the bote-side needs at the 5.11.x scoping window; this filing is the formal write-up).

## Summary

The bote roadmap has carried two MCP-spec capability items since the
1.x line and neither can land until cyrius firms up its threading +
cancellation surface:

1. **`dispatcher_dispatch_streaming`** — tool handlers that emit
   incremental progress / partial results via JSON-RPC notifications
   while the request is still open. Spec'd as part of the MCP
   2025-11-25 `notifications/progress` flow.
2. **`$/cancelRequest` mid-stream handling** — depends on (1); without
   streaming dispatch in place, there's no in-flight request to cancel.

bote already has the *data* primitives in place — `ProgressUpdate` and
`CancellationToken` types, fp-pointer plumbing through the dispatcher,
end-to-end claims propagation from 2.5.0. What's missing is the
runtime substrate to actually run a handler on a worker thread, hand
the streaming channel back to the transport, and observe cancellation
without busy-waiting.

The three concrete gaps:

| Gap | Where it bites bote |
|---|---|
| `lib/thread.cyr` MPSC primitive | The dispatcher needs to launch a worker (`thread_spawn`) for streaming tools and read from the worker via a multi-producer single-consumer channel. The transport layer reads off the channel and writes JSON-RPC `notifications/progress` frames as they arrive. cyrius 5.10.x has `lib/thread.cyr` with raw thread spawn but no MPSC channel primitive. |
| `lib/async.cyr` cancellation polling | The handler needs a cheap way to check "has the client cancelled?" between progress emissions. Today's options (busy-loop on a shared word, signal handler) are either inefficient or async-signal-unsafe. cyrius 5.10.x has `lib/async.cyr` with futures-style primitives but no documented cancellation polling pattern. |
| Per-thread request buffers (process-global today) | bote's HTTP recv buffer is a process-global `var _http_buf[65536];`. Threaded dispatch would have two requests parsing concurrently into the same buffer. The fix is either a per-thread allocation (cyrius needs a thread-local primitive) or a passed-down arena per request (which would also want `fl_free` — see [`2026-05-10-bote-fl-free-for-arena-reuse.md`](2026-05-10-bote-fl-free-for-arena-reuse.md)). |

## Reproduction

There isn't a reproduction in the bug-report sense — these are
*absences*, not bugs. The reproduction is "open `src/dispatch.cyr` in
bote 2.7.1, find the comment block that flags streaming dispatch as
roadmap-blocked, and confirm `lib/thread.cyr` doesn't expose
`thread_channel_new` / `thread_channel_send` / `thread_channel_recv`
and `lib/async.cyr` doesn't expose `cancel_token_check` or equivalent."

bote-side roadmap entries that wait on this:

- `docs/development/roadmap.md` — "Blocked on cyrius / external" table:
  > **Threaded streaming dispatch** (`dispatcher_dispatch_streaming`) — cyrius `lib/thread.cyr` MPSC + `lib/async.cyr` cancellation polling firming up. Data primitives (`ProgressUpdate`, `CancellationToken`) already in place.
  > **`$/cancelRequest` mid-stream handling** — Streaming dispatch first.

## Proposed shape (speculation — flag for the cyrius agent to verify)

A minimum viable surface that would unblock bote:

```cyrius
# lib/thread.cyr — MPSC additions
fn thread_channel_new(capacity) -> i64        # returns ch handle
fn thread_channel_send(ch, msg) -> i64        # 0 on success, -1 if closed
fn thread_channel_recv(ch) -> i64             # blocks until msg or close; 0 = closed
fn thread_channel_try_recv(ch) -> i64         # non-blocking; returns 0 if empty
fn thread_channel_close(ch) -> i64

# lib/async.cyr — cancellation polling
fn cancel_token_new() -> i64
fn cancel_token_signal(tok) -> i64            # caller-side: "client cancelled"
fn cancel_token_check(tok) -> i64             # handler-side: 1 if cancelled

# Per-thread storage — picks one of:
#   (a) lib/thread.cyr: thread_local_alloc(size) / thread_local_get(slot)
#   (b) lib/alloc.cyr: arena_new() / arena_alloc(arena, size) / arena_free(arena)
# bote's preference is (b) — arena per request matches the request-scope
# lifetime, and the same fl_free-shaped need shows up in the WS arena
# work (see the linked issue).
```

`thread_channel_*` shape mirrors Go channels semantically (closable,
recv-on-closed returns sentinel). Specific allocation behavior under
the hood is the cyrius agent's call — bote doesn't care if the
implementation is futex / mutex+condvar / lock-free.

## Consumer-side workaround

**None that preserves correctness.** Options bote has rejected:

- **Block the transport thread on each tool call.** Trivial to implement
  but defeats the point of streaming — a 30-second tool call would
  freeze the bote stdio / HTTP transport for the entire duration. Worse,
  it gives the client no way to cancel.
- **`fork()` per tool call.** Process-per-call would isolate state but
  the JSON-RPC notification channel back to the transport needs IPC
  the consumer-app surface doesn't currently model.
- **Roll a custom MPSC in `src/_streaming_chan.cyr`.** Plausible but
  drops below the cyrius-stdlib-as-floor principle the rest of the
  AGNOS tree follows. If we re-roll the channel here, every other
  consumer that wants threaded handling (mneme, hoosh, future
  AgnosAI-side dispatchers) re-rolls their own.

bote is choosing to wait on the upstream surface. The roadmap notes
explicitly that 2.8.x opens with this work *when cyrius primitives
firm up*; no consumer-side stopgap is shipping.

## Severity rationale

P2 (not P1) because:

1. **No production deployment is blocked.** bote 2.7.1 in stdio /
   HTTP / streamable / ws / bridge / unix mode handles the
   non-streaming MCP surface end-to-end. The streaming flow is
   spec-optional for a server (`notifications/progress` is
   `MAY`-shaped).
2. **The cyrius agent already has this on the roadmap.** Per
   `docs/development/roadmap.md` of cyrius itself (status at 5.10.34),
   threading + async are explicitly listed as candidate themes. This
   filing is to make the bote-side need legible and concrete so the
   upstream design has a real consumer to validate against.

Bump to P1 if any of these change:

- An AGNOS-side consumer (mneme, hoosh, AgnosAI, daimon) needs
  streaming tool dispatch in a release.
- The MCP spec promotes `notifications/progress` from `MAY` to
  `SHOULD` for server implementations.

## Related issues

- [`2026-05-10-bote-fl-free-for-arena-reuse.md`](2026-05-10-bote-fl-free-for-arena-reuse.md) — the per-request-arena option for the per-thread-buffers gap.
- [`2026-05-10-bote-net-stdlib-recv-timeout-and-getaddrinfo.md`](2026-05-10-bote-net-stdlib-recv-timeout-and-getaddrinfo.md) — separate net-stdlib gap, not threading-related, but also "bote-blocked-on-cyrius" surface.

## Pointers

- bote roadmap: https://github.com/MacCracken/bote/blob/main/docs/development/roadmap.md
- bote `src/dispatch.cyr` — the streaming-dispatch comment block.
- bote `src/stream.cyr` — the data primitives already in place
  (`ProgressUpdate`, `CancellationToken`).
- bote `CHANGELOG.md` §2.7.1 "Forward roadmap" — explicit note that
  2.8.x is the next planned arc gated on this work.
