# stdlib — `lib/ws_server.cyr` calls `http_find_header`, which no `6.x` snapshot defines (missed by the `http_*` → `sandhi_server_*` rename)

**Status**: ✅ **RESOLVED (v6.3.19, 2026-06-30)** — the four `http_find_header(` calls in
`lib/ws_server.cyr:ws_server_handshake` (plus the one stale reference in a comment) are renamed to
`sandhi_server_find_header(` — a pure rename, identical `(buf, blen, name)` contract, no logic
change. New regression `tests/tcyr/ws_server_handshake.tcyr` compiles ws_server and reaches the
handshake (a stale name is now a REACHABLE-undefined hard error, proven: reverting the rename fails
the test with "1 reachable undefined function"). cyrius shipped no ws test before — this closes that
gap. bote 2.7.7's forwarding shim can now be dropped (it DCE-prunes to dead once ws_server calls the
real name directly).
> Original filing below.

**Status**: ⏳ **OPEN — surfaced by the base-stack 6.3.15 migration (bote 2.7.7).**
**Date**: 2026-06-30
**Priority**: **Medium** — any consumer that includes `lib/ws_server.cyr` (WebSocket server upgrade path) gets a *reachable-undefined* link error the moment its WS handshake is exercised. Currently worked around consumer-side (a forwarding shim in bote); the stdlib should own the fix.
**Where**: cyrius `lib/ws_server.cyr` (lines ~80–83, `ws_server_handshake`).

## The gap

`lib/ws_server.cyr:ws_server_handshake` calls **`http_find_header`** four times:

```cyrius
var upgrade = http_find_header(req_buf, req_len, "Upgrade");
var conn    = http_find_header(req_buf, req_len, "Connection");
var version = http_find_header(req_buf, req_len, "Sec-WebSocket-Version");
var key     = http_find_header(req_buf, req_len, "Sec-WebSocket-Key");
```

But **`http_find_header` is defined nowhere** in any `6.2.x` or `6.3.x` snapshot — verified across `6.2.11 / 6.3.0 / 6.3.5 / 6.3.10 / 6.3.13 / 6.3.15 / 6.3.17` (0 definitions in each). The only occurrence of the symbol in the whole stdlib is these call sites inside `ws_server.cyr` itself.

This is a **stale name from the `http_*` → `sandhi_server_*` header-helper rename**: the request-header parser now ships as **`sandhi_server_find_header(buf, blen, name)`** in `lib/sandhi.cyr`, and `ws_server.cyr` was missed in the sweep. The two have an **identical contract** — `(buf, blen, name)` → allocated NUL-terminated header value, or `0` if absent; case-insensitive name match, case-preserving value — so this is a pure rename, no logic change:

```cyrius
# lib/sandhi.cyr
fn sandhi_server_find_header(buf, blen, name): i64 { ... }   # exact drop-in
```

## Why it "built" before

At `6.2.x`, consumers' WS test units compiled because DCE treated `ws_server_handshake` (and thus the `http_find_header` calls) as **unreachable** — the undefined symbol was only a warning, not a hard error. Any consumer that actually reaches the handshake at runtime would `ud2`/SIGILL. The `6.3.x` reachability tightening turns the warning into a `refusing to emit binary with N reachable undefined` error once the call site is live, which is how bote 2.7.7's `tests/bote_ws.tcyr` surfaced it.

## The fix (stdlib)

In `lib/ws_server.cyr`, rename the four `http_find_header(` calls to `sandhi_server_find_header(`. That requires `lib/sandhi.cyr` (or at least its `sandhi_server_find_header`) to be in scope wherever `ws_server.cyr` is included — it already is for the WS transport consumers (they include `sandhi`), so no new dependency is introduced.

## Consumer-side workaround in place (remove once fixed)

bote 2.7.7 added a local forwarding shim in `src/transport_ws.cyr`, immediately before its `include "lib/ws_server.cyr"` (single-pass ordering):

```cyrius
fn http_find_header(buf, blen, name): i64 {
    return sandhi_server_find_header(buf, blen, name);
}
```

Once `ws_server.cyr` calls `sandhi_server_find_header` directly, that shim becomes dead (DCE-pruned) and can be dropped from bote.

**Originating record**: AGNOS base-security-stack migration to cyrius 6.3.15 (bote tier); see `agnosticos` memory `project_base_stack_6315_migration`.
