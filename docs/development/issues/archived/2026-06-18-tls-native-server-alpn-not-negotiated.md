# `tls_native` server-side ALPN is never negotiated — `tls_native_set_alpn` only wires the client offer

**Discovered:** 2026-06-18 during the yeo-cy-test HTTPS bite (serving a SecureYeoman-shaped API over `tls_native`).
**Severity:** Medium — silent no-op: a server calls `tls_native_set_alpn(ctx, "\x08http/1.1", 9)`, it returns `TLS_OK`, yet no protocol is ever negotiated. HTTP/1.1 (the default) works, so no hard failure, but **h2-over-TLS is unreachable with a `tls_native` server** and the silently-ignored setter is a footgun.
**Affects:** `lib/tls_native_*.cyr` (folded from the tls_native source) — server handshake path, cycc 6.2.x (verified 6.2.21).

## Summary

`tls_native` can act as a TLS 1.3 server (handshake, Ed25519 cert, OpenSSL-client
interop, chain+hostname verify all work). But ALPN is **client-only**:
`tls_native_set_alpn` stores the value in `TLS_CTX_OFF_ALPN_OFFER`, which is read
only on the **ClientHello** emit path and matched only when a **client** parses the
server's EncryptedExtensions. There is no server-side path that reads the client's
offered ALPN list and emits a selected protocol in the server's EncryptedExtensions.
So a `tls_native` server configured with ALPN never negotiates it.

## Reproduction

Stand up a `tls_native` server (per `tests/tcyr/tls_native_ed25519.tcyr`) with:

```
tls_native_set_alpn(ctx, "\x08http/1.1", 9);   # 1-byte len prefix + "http/1.1"
tls_native_server_load_creds(ctx);
tls_native_accept(ctx, cfd);
```

then point an ALPN-offering client at it:

```
echo | openssl s_client -connect localhost:8443 -alpn http/1.1 -CAfile cert.pem 2>/dev/null \
  | grep -iE "Protocol|ALPN"
```

- **Expected:** `ALPN protocol: http/1.1`
- **Actual:** `Protocol: TLSv1.3` … `No ALPN negotiated` (handshake otherwise clean, `Verify return code: 0`).

(Surfaced live in yeo-cy-test, which serves HTTPS on `tls_native`; HTTP/1.1 still works because it's the default with no ALPN.)

## Root cause (if known)

`tls_native_set_alpn` (`lib/tls_native_hs12.cyr:1466`) stores the offer at
`TLS_CTX_OFF_ALPN_OFFER`. That field is consumed only on the **client** ClientHello
emit (`lib/tls_native_hs13.cyr:38-91`, `lib/tls_native_hs12.cyr:297-356` — "the
offered protocols") and the **client** reads the server's selection from
EncryptedExtensions (`lib/tls_native_hs13.cyr:352-361`, `_tn_store_alpn_selected`
at `tls_native_hs12.cyr:1487`). The **server** EncryptedExtensions builder has no
ALPN branch: it neither parses the client's `application_layer_protocol_negotiation`
extension nor emits a chosen protocol. (Speculation — verify: the 1.2 ServerHello
path likely has the same omission.)

## Proposed fix

On the server handshake: parse the client's ALPN extension, intersect with the
server's configured `ALPN_OFFER` list (first server-preferred match, RFC 7301),
and emit the single selected protocol in the server's EncryptedExtensions (TLS 1.3)
/ ServerHello (TLS 1.2). Expose the negotiated protocol to the caller (a
`tls_native_alpn_selected(ctx)` accessor) so an HTTP server can branch h1/h2. If no
overlap and the client required ALPN, alert `no_application_protocol` per spec.

## Consumer-side workaround (if any)

None needed for HTTP/1.1 — it's the default when no ALPN is negotiated, so a
plaintext-HTTP-over-TLS server works today. The consumer simply cannot offer h2
over TLS until the server side negotiates ALPN. yeo-cy-test keeps the
`tls_native_set_alpn` call (correct intended usage) and serves HTTP/1.1.

## Resolution — v6.2.22 (2026-06-18)

**RESOLVED.** Added the server-side path. The TLS 1.3 + 1.2 ClientHello parsers
(`_tn_parse_client_hello` / `_tn_12_parse_client_hello`) now call a shared
`_tn_server_negotiate_alpn`: it finds the client's `application_layer_protocol_
negotiation` (ext 16) offer, intersects it with the server's configured list via
`_tn_select_alpn` (**server-preference order**, RFC 7301 §3.2, all reads
bounds-checked against the untrusted client list), and stashes the choice at
`TLS_CTX_OFF_ALPN_SEL`. The EncryptedExtensions builder (`_tn_build_ee`, now
`ctx`-parameterized) emits the selected protocol for 1.3; `_tn_build_server_hello_12`
for 1.2. The **1.2 ServerHello had the same omission** (speculated in this filing) —
confirmed and fixed. The existing `tls_native_get_alpn_selected` accessor already
read `ALPN_SEL` and documented "or that we selected (for servers)" — **reused as-is,
no new ctx offset / LEN change.**

No-overlap → no negotiation (lenient; no `no_application_protocol` alert), matching
the existing client-side leniency. **Verified:** new `tls_native_alpn.tcyr`
(server-preference selects `h2` over the client's first-listed `http/1.1`; no-overlap
negotiates nothing; 9/9) + the filing's exact repro — `openssl s_client -alpn
http/1.1` against a `tls_native` server now reports **`ALPN protocol: http/1.1`**
(OpenSSL 3.6.2). Existing TLS suites unchanged (no-ALPN EE byte-identical).
