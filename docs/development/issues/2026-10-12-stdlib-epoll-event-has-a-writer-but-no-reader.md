# The stdlib builds an `epoll_event` per arch (`epoll_event_new`) but offers nothing to read one back, so consumers hand-gate the data offset — OPEN

**Status:** 🟡 **OPEN** — checked 2026-10-12 against the published 6.7.9 `lib/`. Found by chakshu's 0.11.0 release, which had read the data field at x86_64's `+4` on aarch64.
**Placement:** 6.7.12 — repair 2: the platform release (stdlib lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-12. chakshu's epoll tag read was wrong on aarch64 (`0x25A5A5A5A` instead of the tag), proven on qemu-aarch64 and on a Raspberry Pi 4.
**Severity:** Low — a stdlib surface gap (recommendation). The defect it causes is the consumer's, but the arch rule lives only in stdlib comments.
**Affects:** 6.7.9 (verified by reading). The write side has been per-arch since v6.4.42.

## Summary

`epoll_event_new(events, data)` already encodes the arch difference:

- `lib/syscalls_x86_64_linux.cyr:587` — `{ u32 events, u64 data }` packed (`EPOLL_PACKED`), data at offset **4**,
  12-byte stride;
- `lib/syscalls_aarch64_linux.cyr:878` — unpacked, data at offset **8**, 16-byte stride ("Must match the reactor's
  data offset in lib/async.cyr", v6.4.42).

But every program that calls `sys_epoll_wait` must read the returned array itself, with its own `load64(ev + 4)` or
`load64(ev + 8)` and its own stride. chakshu read `+4` on both arches. cyim hand-gates the same read with `#ifdef`.
`lib/async.cyr` keeps the rule private to its reactor.

## Proposed fix

Add readers next to `epoll_event_new` in each arch peer:

```
fn epoll_event_events(ev): i64   # load32(ev)
fn epoll_event_data(ev): i64     # load64(ev + 4) on x86_64, load64(ev + 8) on aarch64
var EPOLL_EVENT_SIZE = 12        # 16 on aarch64 — the array stride for sys_epoll_wait
```

`lib/async.cyr` could then use them too, so the rule lives in one place per arch.

## Consumer-side workaround

Gate the read per arch (`#ifdef CYRIUS_ARCH_X86` / `CYRIUS_ARCH_AARCH64`), as chakshu now does in
`src/tui_event.cyr` (`tui_epoll_data`) and cyim already did.
