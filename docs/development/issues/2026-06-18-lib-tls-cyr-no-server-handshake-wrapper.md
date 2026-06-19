# `lib/tls.cyr` has no server-side handshake wrapper (`tls_accept` / `tls_new_server`) — only the client side is on the contract

**Discovered:** 2026-06-18 during sandhi 1.6.8 server-side TLS (sandhi can now serve HTTPS).
**Severity:** Low/Medium — no functional gap (server TLS works), but an **asymmetry in the `tls_*` contract**: consumers must reach past `lib/tls.cyr` into the `tls_native_*` backend to do a server handshake, which couples them to the native backend and breaks the backend-swap transparency the contract exists to provide.
**Affects:** `lib/tls.cyr` at 6.2.22. Client role unaffected.

## Summary

`lib/tls.cyr` exposes a clean, backend-dispatched **client** handshake —
`tls_connect_alloc` → (`tls_set_session`) → `tls_connect_complete`, plus
`tls_connect` / `tls_connect_with_ctx_hook`. There is **no symmetric server
side**: no `tls_accept`, no `tls_new_server`. The I/O verbs (`tls_write` /
`tls_read` / `tls_close`) already operate on the 24-byte ctx shim
`[inner_ctx, 0, fd]` and work for either role — only the handshake bootstrap is
client-only.

So a Cyrius TLS **server** consumer (sandhi, sit `serve --tls`, daimon, …) has to
call the native backend directly:

```cyrius
var nctx = tls_native_new_server(cert, cert_len, key, key_len);
tls_native_set_alpn(nctx, alpn, alpn_len);
tls_native_server_load_creds(nctx);
tls_native_accept(nctx, fd);
# then hand-roll the lib/tls.cyr shim so tls_write/read/close work:
var shim = alloc(24); store64(shim, nctx); store64(shim + 8, 0); store64(shim + 16, fd);
```

This is the exact bootstrap sandhi 1.6.8 ships (`_sandhi_server_tls_handshake`
in `src/server/mod.cyr`). It works, but it hard-codes the **native** backend on
the server path: a consumer that selected the libssl backend via
`tls_set_backend` would still get a native server (or, if it hand-rolled the
libssl `SSL_accept` path, a fork of the contract). The whole point of the
`tls_*` contract is that consumers don't know or care which backend is live.

## Proposed fix

Add the server mirror of the client staged-connect, backend-dispatched exactly
like `tls_connect_alloc` / `tls_connect_complete`:

```cyrius
# Allocate a server ctx from cert/key (+ optional ALPN/verify hooks),
# returns the standard [inner_ctx, 0, sock] shim or 0.
fn tls_accept_alloc(sock, cert, cert_len, key, key_len): i64
# Drive the server handshake over the shim's socket. 1 on success.
fn tls_accept_complete(ctx): i64
# Convenience wrapper (mirrors tls_connect): alloc + complete.
fn tls_accept(sock, cert, cert_len, key, key_len): i64
```

- **Native branch:** `tls_native_new_server` + `tls_native_server_load_creds` +
  `tls_native_accept`, wrapped in the 24-byte shim (what consumers hand-roll today).
- **libssl branch:** `SSL_CTX_new(TLS_server_method)` + cert/key load +
  `SSL_accept` (symmetric to the existing client path), behind
  `#ifndef CYRIUS_TLS_LIBSSL` / `_tls_backend` like the rest of the file.

ALPN/verify config can ride the existing `tls_set_alpn` / `tls_set_verify`
hooks on the returned ctx (as the client side does), so the server signature
stays small. Once this lands, the native-only bootstrap consumers carry today
collapses to a single `tls_accept*` call — sandhi will migrate
`_sandhi_server_tls_handshake` onto it (exactly as sandhi 1.6.1/1.6.2 migrated
`conn.cyr`'s raw socket syscalls onto `net.cyr` helpers once they landed).

## Consumer-side workaround (in place)

sandhi 1.6.8 composes the native server primitives directly and wraps the result
in the `lib/tls.cyr` shim so all *I/O* still rides the contract
(`tls_write`/`tls_read`/`tls_close`); only the handshake bootstrap reaches past
it. Documented there as a known cyrius-side residual; no functional gap.

## Related

- `archived/2026-06-18-tls-native-server-alpn-not-negotiated.md` (RESOLVED 6.2.22)
  — server ALPN, the sibling server-side gap, now works; the `tls_accept` wrapper
  is the remaining server-side contract asymmetry.
- `archived/2026-06-10-tls-native-ed25519-server-cert-accept-fails.md` (RESOLVED
  6.1.31) — Ed25519 server certs.
- `2026-06-18-tls-native-server-ctx-not-arena-aware.md` — the other open
  server-TLS residual (per-connection ctx allocation).
