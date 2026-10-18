# `lib/async.cyr` still hand-gates the epoll_event data offset at its three WRITE sites — the stdlib has no writer for a caller-owned (stack) buffer — RESOLVED

> ✅ **RESOLVED in v6.7.14** (LIB-4, `4992e07d3`. No decision was needed; 6.7.13's D36 is untouched. `fn epoll_event_set(ev, events, data): i64` is added in the x86_64 Linux (data @4), aarch64 Linux (data @8) and x86-macOS (data @4) peers. It stores the events at 0 and the data at the peer's offset, and returns `ev`. `epoll_event_new` is `alloc(16)` plus the writer. `lib/async.cyr`'s three registrations call it: `_async_poll`'s MOD, `_async_wait_events`' ADD / MOD and `async_timeout`'s ADD. The same bytes are written at every site. The filed grep now finds nothing, and no `CYRIUS_ARCH_AARCH64` pair is left in `async.cyr`. The bookkeeping: the api-surface snapshot +3, `docs/stdlib-reference.md`, and `macos_peer_surface_parity.sh` axis B. Rows: `tests/tcyr/crossos/epoll_event_readers.tcyr` — a stack-buffer round trip in every peer, a stack registration reported back by `epoll_wait` on Linux, and the reactor rows — 34 / 34 on x86_64, qemu-aarch64 and pi, 13 / 13 on ecb and ach. Mutations: the offset swapped, or the writer deleted from the x86-macOS peer → RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 stdlib lane (l6712-stdlib @ c667293d).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (stdlib lane, wave 2, unit L2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — a stdlib surface gap, no live defect: the three sites write the right offset today.
**Discovered:** 2026-10-15, the 6.7.12 stdlib lane (unit L1), fixing
`issues/archived/2026-10-12-stdlib-epoll-event-has-a-writer-but-no-reader.md`. That filing asked for READERS
(`epoll_event_events` / `epoll_event_data` / `EPOLL_EVENT_SIZE`, shipped in 6.7.12) and said async.cyr "could then use
them too, so the rule lives in one place per arch". The reactor's read site now does; its writes cannot, because the
only writer, `epoll_event_new`, allocates (the default allocator is a bump allocator with no free, so a per-wait
`epoll_event_new` would leak 16 B per registration).

## Reproduction

```
$ grep -n -E 'store64\(&(ev|rev) \+ (4|8), ' lib/async.cyr
270:            store64(&rev + 8, wfd);
273:            store64(&rev + 4, wfd);
398:    store64(&ev + 8, fd);
401:    store64(&ev + 4, fd);
1238:        store64(&ev + 8, rfd);        # epoll_data @8 on aarch64 (unpacked); @4 on x86 (v6.4.42)
1241:        store64(&ev + 4, rfd);
```
(270 / 273: `_async_poll`'s EPOLL_CTL_MOD of the remainder; 398 / 401: `_async_wait_events`' ADD / MOD;
1238 / 1241: `async_timeout`'s ADD.)

Each is an `#ifdef CYRIUS_ARCH_AARCH64` / `#ifndef` pair writing data @8 / @4 into a 16-byte stack buffer — the
same per-arch rule the peers' `epoll_event_new` and `epoll_event_data` now hold, kept a fourth, fifth and sixth time
in async.cyr (and once more in every consumer that registers from a stack buffer).

## Root cause

The peers offer `epoll_event_new(events, data)` (allocating) and, since 6.7.12, the readers; nothing fills an
epoll_event the caller owns.

## Proposed fix

A writer beside the readers in each peer — e.g. `fn epoll_event_set(ev, events, data): i64` storing `events` @0 and
`data` @4 (x86_64, x86-macOS) / @8 (aarch64), returning `ev` — with `epoll_event_new` reduced to alloc + set, and
async.cyr's three write sites switched to it (value-identical on both arches). Adds a public fn: api-surface
snapshot, a doc comment, macos_peer_surface_parity.sh's axis-B probe, a crossos round-trip row.
