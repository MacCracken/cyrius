# `chan_try_send` does not exist — the channel API is non-blocking on the receive side only

**Status:** ✅ **RESOLVED in cyrius v6.4.84** — `chan_try_send(ch, val)` shipped on all three
backends (`lib/thread.cyr` futex+mutex, `lib/thread_win.cyr` SRW lock, `lib/thread_agnos.cyr` serial),
contract `0` enqueued / `-1` closed / `-2` full, gated by `tests/tcyr/vr01_chan_try_send.tcyr`
(20 assertions, opens with this issue's verbatim repro, mutation-proven, runs on real hardware via
the `vr01_` glob).

> ⚠ **One correction to the proposed fix.** §"Proposed fix" suggested that agnos's `chan_try_send`
> "can just be `chan_send`" since that backend is single-threaded. That would have shipped a
> **divergent contract**: agnos *and* Windows `chan_send` return **`-1` on FULL**, and neither
> inspects `closed` (+48) at all, so a send on a closed channel silently succeeds there. Aliasing
> would have left a portable consumer unable to distinguish "stop producing" from "drop this one" on
> exactly those backends — the distinction this issue exists to create. All three are written out
> properly; the gate asserts closed-beats-full on each.

**Originally filed** against cyrius **6.4.83**: `lib/thread.cyr` exports
exactly five channel fns (`chan_new` :316, `chan_send` :331, `chan_recv` :359, `chan_close` :387,
`chan_try_recv` :409). There is **no `chan_try_send`** in `lib/`, in `src/`, or anywhere in the
cyrius repo — `grep -rn chan_try_send` over the whole tree returns nothing. The gap is identical on
all three backends (`thread.cyr` Linux/macOS, `thread_win.cyr` :87, `thread_agnos.cyr` :95): every
one ships `chan_try_recv` and a blocking-only `chan_send`.
**Placement:** unpinned — **6.x-line stdlib backlog**. It is the exact mirror of the `chan_try_recv`
carve-out already in the tree, so it fits any adjacent stdlib slot; ~20 lines per backend.
**Discovered:** 2026-07-28 while planning the AgnosAI Rust → Cyrius port (v2.0.0), blocker #4 of
`agnosai/docs/development/cyrius-port-plan.md`
**Severity:** Medium — hard blocker for one consumer's port with only unpleasant workarounds, **and**
a live liveness bug in shipped majra code that cannot be fixed from majra's side alone
**Affects:** cyrius 6.4.83 and every earlier version carrying the channel API

## Summary

The bounded MPSC channel is asymmetric. `chan_try_recv` (added for bote's streaming dispatch — "drain
a worker's progress channel without blocking the transport thread", per its own doc comment) gives a
receiver a non-blocking path. Senders have none: `chan_send` blocks on `FUTEX_WAIT` until the buffer
drains or the channel closes.

So a producer cannot express **"deliver this if the consumer is keeping up, otherwise drop it and
carry on."** That is the normal contract for telemetry, progress events, and pub/sub fan-out —
exactly the traffic where one slow consumer must never be able to stall a producer. The blocking
send converts backpressure into head-of-line blocking across unrelated work.

## Consumer context

### AgnosAI — the port has nine call sites with no Cyrius equivalent

AgnosAI is being ported from Rust, where this is spelled `let _ = tx.send(..)` on an unbounded
channel: enqueue, and if nobody is listening, discard. Nine sites do this, all on the
crew-event/telemetry path:

| Site | What it emits |
|---|---|
| `src/orchestrator/crew_runner.rs:115` | crew lifecycle events (`emit()`) |
| `src/orchestrator/crew_runner.rs:787` | streamed completion token |
| `src/orchestrator/pubsub.rs:96` | per-subscriber fan-out |
| `src/server/sse.rs:146`, `:268` | SSE event push |
| `src/fleet/relay.rs:133`, `:207` | relay message forward |
| `src/server/hot_config.rs:42` | config reload broadcast |
| `src/llm/inference_queue.rs:123` | queued inference reply |

Ported onto `chan_send`, every one of these becomes a blocking call **inside crew execution**. An
HTTP client that opens an SSE stream and stops reading would stall the crew producing its events —
a disconnected browser tab wedging a running job.

### majra — shipped code, live head-of-line blocking

`majra/src/pubsub.cyr:136-186` (`pubsub_publish`) takes the hub mutex at `:138` and does **not**
release it until `:184`. Between those lines it calls blocking `chan_send` in two loops — once per
exact subscriber (`:151`) and once per pattern subscriber (`:173`):

```cyrius
mutex_lock(mtx);
...
    if (filter == 0 || fncall1(filter, payload) == 1) {
        chan_send(load64(sub), payload);      # blocks while holding the hub mutex
        delivered = delivered + 1;
    }
...
mutex_unlock(mtx);
```

One subscriber whose channel is full therefore blocks the publisher **while holding the hub lock**,
which stalls publishes to *every other topic* and every other subscriber. majra cannot fix this
properly from its own side: dropping the lock mid-fan-out races the subscriber list, and there is no
non-blocking send to reach for. This is the "someone is working around this in production code right
now" bar — except majra has not worked around it, because there is nothing to work around it with.

## Reproduction

```cyrius
# A bounded channel with no reader. The second send never returns.
var ch = chan_new(1);
chan_send(ch, 42);        # ok — buffer had room
chan_send(ch, 43);        # blocks forever: FUTEX_WAIT, no receiver will ever drain it
println("unreachable");
```

The mirror-image receive case has an answer already:

```cyrius
var ch = chan_new(1);
chan_try_recv(ch);        # returns 0 immediately — empty, no block
```

## Root cause

Not a bug — a missing API. `chan_send` (`lib/thread.cyr:331-357`) is a correct blocking send: on a
full buffer it unlocks and `FUTEX_WAIT`s on the count word at `ch + 32`, using the pre-unlock `count`
as the expected value, so a concurrent drain makes the wait return `EAGAIN` and the loop retries.
That logic is sound; there is simply no variant that returns instead of waiting.

The channel struct already carries everything a try-send needs — `cap` at `+8`, `count` at `+32`,
`mutex` at `+40`, `closed` at `+48` — and `chan_try_recv` (`:409-431`) is a working template for the
lock / test / act / unlock / wake shape.

## Proposed fix

`chan_try_send(ch, val)` as the exact mirror of `chan_try_recv`. Roughly:

```cyrius
# Non-blocking send. Returns:
#    0    → value enqueued
#   -1    → channel closed (mirrors chan_send)
#   -2    → buffer full, nothing enqueued; caller decides to drop, retry, or shed
fn chan_try_send(ch, val): i64 {
    var mtx = load64(ch + 40);
    mutex_lock(mtx);
    if (load64(ch + 48) != 0) { mutex_unlock(mtx); return 0 - 1; }
    var count = load64(ch + 32);
    var cap   = load64(ch + 8);
    if (count >= cap) { mutex_unlock(mtx); return 0 - 2; }
    var buf  = load64(ch);
    var tail = load64(ch + 24);
    store64(buf + tail * 8, val);
    store64(ch + 24, (tail + 1) % cap);
    store64(ch + 32, count + 1);
    mutex_unlock(mtx);
    syscall(SYS_FUTEX, ch + 32, FUTEX_WAKE | FUTEX_PRIVATE_FLAG, 1, 0, 0, 0);
    return 0;
}
```

A distinct `-2` for "full" matters: `-1` already means closed on `chan_send`, and a caller shedding
load needs to tell "nobody is listening any more, stop producing" from "the consumer is briefly
behind, drop this one." (`chan_try_recv` collapses empty and closed into `0`, which its doc comment
concedes forces callers to peek at `*(ch + 48)`. Worth not repeating on the send side.)

Needs the same ~20 lines on `thread_win.cyr` and `thread_agnos.cyr` for backend parity. Note
`thread_agnos.cyr:121` currently aliases `chan_recv` to `chan_try_recv` (single-threaded), so its
`chan_try_send` can just be `chan_send`.

## Consumer-side workaround (if any)

None clean. What is available, and why each is unsatisfying:

1. **Peek the count before sending** — read `count` at `ch + 32` and skip the send if it equals
   `cap`. Racy by construction: the check is outside the mutex, so between the peek and the
   `chan_send` another producer can fill the last slot and the send blocks anyway. Narrows the window
   without closing it, and reaches into the channel's private layout.
2. **Over-size the buffer** — `chan_new(100000)` and hope. Converts a hang into a hang that takes
   longer to reach, at a fixed memory cost, and still fails against a consumer that has stopped
   entirely (a disconnected SSE client).
3. **A drain thread per subscriber** — a thread whose only job is to keep a channel from filling.
   One thread per SSE connection, which is the shape the pooled server exists to avoid.

AgnosAI's port has not picked one; it is filed as blocker #4 against the port plan pending this
issue's triage. majra ships option 0 — the blocking send — today.

## Adjacent note (not part of this ask)

`majra/src/pubsub.cyr` holding the hub mutex across fan-out is worth a separate look on majra's side
regardless of how this is triaged: even with `chan_try_send`, publishing under the lock serialises
all topics. `chan_try_send` removes the *unbounded* stall; the lock scope is majra's own to narrow.
