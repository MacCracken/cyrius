# `tls_native_get_version` returns 0 on a connected TLS 1.3 SERVER ctx — RESOLVED

> **RESOLVED v6.4.21 — archived 2026-07-08.** `tls_native_server_respond_hello`'s
> ServerHello path now stores `TLS_VERSION_1_3` into the ctx (mirroring the client's
> `parse_server_hello` + the 1.2 server path). `tls_native_freestanding.tcyr` flipped from
> its `get_cipher==0x1302` workaround back to a direct `get_version` assertion (11/11).
> Lib-only. See CHANGELOG [6.4.21].


**Filed:** 2026-06-28 (surfaced building the v6.3.4 #7 freestanding handshake smoke).
**Severity:** P3 (cosmetic / API-consistency; no security or interop impact — the
negotiated version IS enforced internally, this is only the *reported* value).

## Symptom

After a successful TLS **1.3** handshake, the **server** ctx reports the wrong
negotiated version:

- `tls_native_get_state(srv)` → `TLS_STATE_CONNECTED` ✓
- `tls_native_get_cipher(srv)` → `0x1302` (AES-256-GCM-SHA384, a 1.3-only suite) ✓
- `tls_native_get_version(srv)` → **0** ✗ (expected `TLS_VERSION_1_3` = 0x0304)

The **client** ctx reports `get_version` = `0x0304` correctly. And the **1.2**
server path tracks it (the `tls12_handshake.tcyr` e2e asserts
`tls_native_get_version(srv) == TLS_VERSION_1_2` and passes). So the gap is
specifically the **TLS 1.3 server-side** ctx: it never stores the negotiated
version where `get_version` reads it (`TLS_CTX_OFF_*` version field).

## Why it went unnoticed

The 1.3 socketpair e2e tests (`tls_native_alpn`, `tls_native_mtls_client`,
`tls_native_ed25519`) assert the **client's** version (or don't check the
server's at all). The `tls_native_freestanding.tcyr` smoke (v6.3.4 #7) is the
first to assert the **server's** post-1.3-handshake version — it worked around
this by asserting `get_cipher(srv) == 0x1302` instead (a 1.3-only suite proves a
1.3 handshake reached key agreement just as well).

## Fix (when picked up)

In the TLS 1.3 server accept path (`lib/tls_native_hs13.cyr`, the server-side
ServerHello/Finished completion), store the negotiated `0x0304` into the ctx's
version field — mirroring the 1.2 server path and the 1.3 client path. Add an
assertion to `tls_native_freestanding.tcyr` (flip the cipher check back to a
version check) once landed.
