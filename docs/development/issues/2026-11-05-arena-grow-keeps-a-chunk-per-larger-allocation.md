# A GROW arena keeps a chunk for each slightly larger allocation — OPEN

**Discovered:** 2026-11-05, by agnostic's 0.2.2 audit. **Severity:** Medium for a server.
**Affects:** `_arena_grow` in `lib/alloc.cyr`, at 6.7.18. **Status:** 🔴 OPEN.
**Repro:** [`repros/arena-grow-rising-needs.cyr`](repros/arena-grow-rising-needs.cyr).

`arena_reset`'s comment says of GROW: "a request loop converges on its high-water mark and then
allocates nothing at all". That holds only while the needs do not keep rising.

`_arena_grow` looks at one chunk, the next. When that chunk is too small it allocates a new one, sized
exactly to the need when the need is over the chunk size, and links it in front. The chunk it passed
over is not looked at again in that position. So a need that rises a little each cycle adds a chunk
each cycle.

Measured in agnostic with a 64 KiB arena, one worker, and 900 KB JSON bodies: 300 identical bodies held
RSS flat, and 300 that each grew by 16 B took it from 75 MB to 340 MB, about 880 KB per request. A
client that can reach a body parser can do this, and each request costs it nothing.

**Ask:** size a chunk made for an oversized need geometrically, at twice the largest so far or the
need, whichever is more, so rising needs make O(log n) chunks. Or walk the chain for a chunk that fits.

**agnostic meanwhile** keeps its chunk size at least its body cap, so no body causes an oversized need
(ADR 0021). That does not cover responses, which have no cap.
