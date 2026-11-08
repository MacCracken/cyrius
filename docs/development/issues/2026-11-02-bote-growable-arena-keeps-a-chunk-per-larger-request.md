# A growable arena keeps a chunk for every request a little larger than the last — open

**Status:** 🟡 **OPEN** — verified against `lib/alloc.cyr` `_arena_grow` on the 6.7.18 snapshot, 2026-11-02. bote 3.7.0 stopped using the growable arena for its request arena; every other consumer of `arena_allocator_growable` / `arena_new_growable` is exposed.
**Placement:** unpinned — 6.x-line backlog, never 7.x.
**Discovered:** 2026-11-02 by an unanchored review of bote 3.6.6
**Reporter:** bote v3.7.0 (MCP core service)
**Cyrius version at time of report:** 6.7.18
**Affected stdlib:** `lib/alloc.cyr` (`_arena_grow`, reached through `arena_alloc` under `ARENA_FULL_GROW`)
**Severity:** **High** — memory exhaustion a client can drive on any server that rewinds a growable arena per request, which is what the
arena is for. `alloc` never frees, so every chunk is kept for the life of the process.

## Summary

When the chunk in use cannot serve a request, `_arena_grow` looks at the **next** chunk only. If that one is too small, it allocates a
fresh chunk and links it **between** the current chunk and the too-small one, keeping both. `arena_reset` rewinds to the first chunk, so
the next request walks the same chain. A request whose largest allocation is a little larger than any before it therefore adds a chunk,
and the too-small chunks behind it are never used again. A client that sends each message a little larger than the last adds a chunk per
message, for good.

Measured on bote 3.6.6, end to end: 300 refused `resources/read` calls for an unknown URI, its length rising from 12 KB to 42 KB in
100-byte steps (inside the HTTP transport's 60 KB cap), kept **105,138,568 B**. The longest of those messages, sent 300 times, kept 0.

## Reproduction

`repros/2026-11-02-growable-arena-ramp.cyr`, the arena alone:

```cyr
var a = arena_allocator_growable(65536);
reset_via(a); alloc_via(a, 60000); alloc_via(a, 70000);     # warm: one round at the smallest size
var base = alloc_used();
var i = 0;
while (i < 200) {
    reset_via(a);
    alloc_via(a, 60000);            # fills most of the first chunk
    alloc_via(a, 70000 + i * 512);  # a little larger than last time
    i = i + 1;
}
# alloc_used() - base == 24,121,984 on 6.7.18; the same 200 rounds at one size keep 0
```

## Root cause

`_arena_grow` (lib/alloc.cyr):

```cyr
var nxt = load64(cur);
if (nxt != 0) {
    if (load64(nxt + 8) >= need) { ...use nxt...; return 1; }
}
var want = load64(a + 48);
if (need > want) { want = need; }     # exactly `need`, so the next larger request misses it too
var ch = alloc(want + 16);
store64(ch, nxt);                      # inserted in front of the chunk that was too small
store64(cur, ch);
```

Two things combine: only the immediate next chunk is considered, and a new chunk is sized to exactly the request, so a ramp never finds a
chunk that fits.

## Proposed fix

What bote 3.7.0 ships in its own arena (`src/protocol.cyr`, `_bote_ar_alloc`), which keeps the ramp above to one 256 KB chunk:

1. When the chunk in use cannot serve a request, take the **first chunk ahead** in the chain that can, skipping smaller ones for this
   cycle only.
2. Only when none can, **append** a chunk at the end of the chain, sized to the chunk size **doubled until the request fits**.

A chunk is then added only when a request needs more room than every chunk ahead of it has, and the doubling means a ramp of sizes adds
one chunk per power of two, so what a client can make the arena keep is bounded by the largest request it sends. Measured with bote's
version: the ramp above keeps 262,160 B; a sawtooth of 2,000 rounds keeps 524,304 B; 5,000 rounds of six random allocations up to
200 KB each keep 786,480 B.

## Consumer-side workaround

bote 3.7.0 has its own request arena (`bote_req_arena_new` in `src/protocol.cyr`, built on `allocator_new`), and its tests hold the ramp to
under 1 MB end to end and the arena alone to one chunk. A consumer that cannot write its own has none: sizing the first chunk large only
moves the threshold.

## Severity rationale

High, not Critical: the server must rewind a growable arena per request, and the client must control the size of one allocation. Both
hold for an HTTP server that copies or escapes a client's value onto its request arena, which is the arena's documented use ("a route
handler or a task runner wants... allocation scales with request size").

## Related

- [`2026-11-02-bote-ws-server-handshake-keeps-client-headers-on-heap.md`](./2026-11-02-bote-ws-server-handshake-keeps-client-headers-on-heap.md) — the same class: heap a client can grow.

## Pointers

- bote: `src/protocol.cyr` (`_bote_ar_alloc`, `bote_req_arena_new`); `tests/bote.tcyr` (the arena rows, "300 messages, each needing a little more").
