# `ws_server_handshake` keeps the client's headers on the heap, refused upgrades included — open

**Status:** 🟡 **OPEN** — bote bounds the headers before calling it; any other `lib/ws_server.cyr` consumer is exposed.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-02 during bote 3.6.4, measuring what a WebSocket connection leaves on the heap
**Reporter:** bote v3.6.4 (MCP core service)
**Cyrius version at time of report:** 6.7.18
**Affected stdlib:** `lib/ws_server.cyr` (`ws_server_handshake`, `ws_server_new`), through `lib/sandhi.cyr`'s `sandhi_server_find_header`
**Severity:** **High** — memory exhaustion a client can drive with no credentials on a server that takes WebSocket upgrades. `alloc`
never frees, so every byte below is kept for the life of the process. A consumer-side bound exists (below), but each consumer has to
know to write it.

## Summary

`ws_server_handshake(cfd, req_buf, req_len)` reads `Upgrade`, `Connection`, `Sec-WebSocket-Version` and `Sec-WebSocket-Key` with
`sandhi_server_find_header`, which is `sandhi_server_find_header_a(default_alloc(), ...)`: each value is copied to the global heap
**before** any of them is judged. A long header is therefore kept whether the upgrade then succeeds or is refused. On top of that, every
handshake allocates the key/GUID concatenation, the SHA-1 digest, the base64 accept value, the 101 response's `str_builder`, and the
24-byte handle from `ws_server_new`, all from the heap.

Measured on bote 3.6.4 (`tests/bote_ws.tcyr`), per call, after a warm-up call:

| Request | Kept on the heap |
|---|---|
| A refused upgrade: a 60 KB `Upgrade` header, so `streq(upgrade, "websocket")` fails | 60,064 B |
| A completed upgrade with a 60 KB `Connection` header, which nothing bounds | 61,608 B |
| A completed upgrade with ordinary headers | 1,600 B |

A server's request buffer bounds one request, not how many a client sends, so the first two rows grow the heap without limit.

## Reproduction

Against any build that includes `lib/ws_server.cyr`:

```cyrius
var sp[16];
sys_socketpair(1, 1, 0, &sp);
var pad = alloc(60001);
memset(pad, 120, 60000);
store8(pad + 60000, 0);
var sb = str_builder_new();
str_builder_add_cstr(sb, "GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket");
str_builder_add_cstr(sb, pad);     # Upgrade is now "websocket" + 60 KB, so the upgrade is refused
str_builder_add_cstr(sb, "\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n");
var req = str_data(str_builder_build(sb));
ws_server_handshake(load32(&sp), req, strlen(req));
var before = alloc_used();
ws_server_handshake(load32(&sp), req, strlen(req));   # returns 0
println(alloc_used() - before);                        # about 60 KB; 0 expected for a refusal
```

## Root cause

`lib/ws_server.cyr`, `ws_server_handshake`: the four `sandhi_server_find_header` calls at its top, then `alloc(concat_len)`,
`alloc(20)`, `base64_encode`, `str_builder_new()`, and `ws_server_new`'s `alloc(24)`. None of it is needed past the call except the
handle.

## Proposed fix

A variant that takes the caller's arena for what is scratch, and the caller's storage for the handle, e.g.
`ws_server_handshake_a(a, ws_out, cfd, req_buf, req_len)`: headers through `sandhi_server_find_header_a(a, ...)`, the concatenation,
digest and accept value on `a` or the stack, the 101 response through `str_builder_new_a(a)`, and the handle written into `ws_out`
(24 bytes the caller owns for the connection's life). `ws_server_handshake` can stay as the convenience form over it. Until then, the
cheapest fix inside the existing function is to judge the headers before copying them, so a refusal keeps nothing.

## Consumer-side workaround

bote 3.6.4, `src/transport_ws.cyr`, `_ws_upgrade_ok`: before calling `ws_server_handshake`, it reads the same four headers with
`sandhi_server_find_header_a` on its request arena and refuses unless the handshake's own rules hold (`Upgrade` exactly `websocket` or
`WebSocket`, version `13`, a 24-byte key) and `Connection` is at most 256 bytes. A refused upgrade then never reaches the handshake and
keeps nothing, and a completed one keeps the fixed 1,600 B plus at most 256 B. The 1,600 B per connection is what bote cannot remove
from its side without re-implementing the handshake against `ws_server`'s private struct layout, which it will not do.
