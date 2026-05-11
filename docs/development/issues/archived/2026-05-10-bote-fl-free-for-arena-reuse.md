# Cyrius: bump allocator has no `fl_free` — bote needs arena-per-connection / arena-per-request reuse

**Filed:** 2026-05-10
**Reporter:** bote (MCP core service, v2.7.1)
**Cyrius version at time of report:** 5.10.34 (release tarball + source archive)
**Affected stdlib:** `lib/alloc.cyr`, `lib/freelist.cyr`
**Severity:** **P2** — bote works today; the gap is "the WS / streamable
transports leak memory linearly with connection lifetime under the
current bump-allocator semantics, capped only by the process
restart". For typical request/response workloads this is fine; for
long-lived WS / SSE streams it isn't.
**Status:** open. **Expected target:** **5.11.x arc**.

## Summary

cyrius 5.10.34's `lib/alloc.cyr` is a bump allocator with no
general-purpose free. Each `alloc(n)` advances a high-water mark;
there is no mechanism to reclaim a region once the consumer is done
with it. `lib/freelist.cyr` provides typed freelists for specific
fixed-size allocations (libro audit entries, etc.) but doesn't expose
a general-purpose arena/region-reset primitive.

For bote's HTTP / unix / stdio request/response flow this is fine —
each request is bounded (< 64 KB inbound, < small constant outbound),
the bump pointer advances per request, and the bote process is
typically short-lived enough that the high-water mark stays within
reasonable limits. The 2.7.1 default binary at fn_table 89% allocates
maybe a few MB across a normal workload.

It is **not** fine for two specific paths:

| Path | Allocation pattern | Today's footprint |
|---|---|---|
| **WS transport** (`src/transport_ws.cyr`) | Each inbound frame allocates a fresh frame buffer + decoded payload buffer. Connection lifetime can be hours. | Each WS frame leaks bump-allocator memory; a chatty client over a long-lived ws connection forces a periodic bote restart. |
| **Streamable HTTP** (`src/transport_streamable.cyr`) | Same shape: each progress emission allocates a fresh JSON-RPC notification buffer. SSE streams have no upper bound on emission count. | Same — bump-allocator memory grows linearly with emission count. |

The roadmap entry that flags this:

> **WebSocket arena-per-frame allocator** | stdlib `fl_free` support
> for long-lived connections.

## Proposed shape

bote's preference (speculation — flag for the cyrius agent):

```cyrius
# lib/alloc.cyr — arena/region primitive

# An arena is a sub-allocator that bumps within a pre-reserved region.
# Reset returns all memory to the arena's base; no per-alloc free.
# Matches the lifetime contract bote needs: "I have a logical unit
# of work; allocate everything against this arena; when the unit
# ends, drop the whole arena."
fn arena_new(initial_cap) -> i64        # returns arena handle
fn arena_alloc(a, n) -> i64             # bumps within the arena
fn arena_reset(a) -> i64                # resets bump pointer to base; memory reusable
fn arena_free(a) -> i64                 # returns the arena region to the global heap
```

`arena_reset` is the load-bearing call for bote — at the end of each
WS frame / SSE emission, reset the arena and reuse the same region
for the next iteration. `arena_free` is end-of-connection / end-of-
stream.

Alternative shape — a `fl_free` on the existing freelist surface —
also works for bote if it exposes "free this specific allocation".
The arena shape is cleaner for the WS / SSE case because the consumer
doesn't have to track every sub-allocation; the arena handle is the
single liveness anchor.

## Reproduction

Synthetic reproducer: a WS client that sends 100k 1-byte frames
against a `bote ws` instance and measures RSS growth on the bote
process. Each frame bumps the allocator; with no free, RSS grows
~bytes-per-frame × 100k = ~100 MB over the run. Process restart is
the only reclamation today.

```sh
./build/bote ws 8393 &
# Run a chatty client (any websocket client that sends a small payload in a tight loop):
wsbench -url ws://localhost:8393 -frames 100000 -payload 1
ps -o rss= -p $(pgrep -f 'build/bote ws')   # observe growth
```

This is the bote-side concern. The underlying cyrius behavior is
visible without bote in the picture too — a tight `for i in 0..N do
alloc(64)` loop grows the heap unboundedly. The cyrius agent will
recognize this as "expected for a bump allocator" — that's correct;
the issue is bote needs the *option* of a reset-able arena, not a
change in the global allocator's semantics.

## Consumer-side workaround

**Process restart on a periodic threshold.** bote could expose a
"max frames per connection" / "max emissions per stream" config and
close the connection (forcing the client to reconnect) when the
threshold is hit. The reconnect cost is small (TCP + WS handshake)
relative to the leak prevention.

**Not shipped** because (a) it's an ugly workaround that breaks the
abstraction (transports shouldn't be in the business of managing
heap pressure); (b) it requires a per-connection counter that adds
its own footprint; (c) the right primitive belongs in cyrius and
benefits every consumer with similar patterns
(`mneme` long-running, `daimon` agent supervision, future
sandhi-side streaming).

bote's posture: track here, wait for the arena primitive, fold it in
when it lands.

## Severity rationale

P2 because:

- **bote runs fine in the common case** — short-lived HTTP requests
  and tool calls don't touch this. Default binary, default workload,
  no problem.
- **WS / SSE long-lived flows have an operational workaround** —
  restart on a threshold. Crude but available.
- **No correctness issue, only memory pressure.** Heap growth is
  bounded by RSS; the process won't crash silently, the OOM killer
  surfaces it loudly.

Bumps to P1 if:

- A production AgnosAI / hoosh deployment ships bote-on-WS with
  multi-day connection lifetimes against a chatty model.
- The MCP spec promotes streaming flows from optional to expected
  for server compliance.

## Related issues

- [`2026-05-10-bote-streaming-dispatch-thread-async-primitives.md`](2026-05-10-bote-streaming-dispatch-thread-async-primitives.md) — the threaded-streaming work would also benefit from `arena_reset` per-request; the threading and the arena are independently useful but pair naturally.

## Pointers

- bote roadmap: https://github.com/MacCracken/bote/blob/main/docs/development/roadmap.md
- bote `src/transport_ws.cyr` — the frame-decode loop.
- bote `src/transport_streamable.cyr` — the SSE emission loop.
- cyrius `lib/alloc.cyr` + `lib/freelist.cyr` — the current surface.
