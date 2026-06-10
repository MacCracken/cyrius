# Native TLS (`lib/tls_native.cyr`) handshake fails against some public servers (example.com) while succeeding against others (1.1.1.1)

> **RESOLVED v6.1.19** — root cause was **chain verification**, not the handshake
> (both handshakes complete). example.com's server includes its SSL.com root
> cross-signed by AAA in the wire chain, which sigil's rigid `x509_verify_chain`
> rejected. `tls_native_client_verify_chain` now does RFC 5280 §6.1 path building
> (anchor at any trusted root, ignore extra/cross-signed certs). Verified live
> against example.com + 8 other major hosts on the native backend. See
> CHANGELOG [6.1.19].

**Discovered:** 2026-06-09 during sandhi 1.4.5 native-backend switch (forcing native by default, libssl to an opt-in flag)
**Severity:** High — blocks making native the default TLS backend for real-world consumers; native HTTPS hard-fails against a common public host with no consumer-side workaround other than falling back to libssl (which has its own process-fatal bug, see the brk/fdlopen issue)
**Affects:** cycc 6.1.18, `-D CYRIUS_TLS_NATIVE`

## Summary

Built with `-D CYRIUS_TLS_NATIVE`, the in-tree native TLS stack handshakes
successfully against `1.1.1.1:443` (SNI `one.one.one.one`) but **fails** the
handshake against `example.com:443` (`172.66.147.243`, SNI `example.com`). Both
are Cloudflare-fronted. The **same source built without** `-D CYRIUS_TLS_NATIVE`
(libssl backend) connects to **both** hosts, so this is a native-stack handshake
gap, not a DNS/network/routing problem.

`tls_connect()` returns 0 (failure) for example.com on native; sandhi surfaces it
as `SANDHI_ERR_TLS` (err kind 3) on every request.

This is the one thing standing between sandhi and a clean "deprecate libssl,
default to native" cutover: native removes the brk/fdlopen process-crash entirely
(separate issue), but can't yet reach all the hosts libssl reaches.

## Reproduction

`docs/development/issues/repros/2026-06-09-native-tls-handshake-gap.cyr`
(self-contained; only stdlib includes). `HOST = 1` targets example.com,
`HOST = 0` targets 1.1.1.1.

```sh
# native: example.com FAILS
cyrius build -D CYRIUS_TLS_NATIVE docs/development/issues/repros/2026-06-09-native-tls-handshake-gap.cyr /tmp/native_gap
/tmp/native_gap
#   backend(1=native): 1
#   iter 0
#     conn-fail
#   iter 1
#     conn-fail
#   iter 2
#     conn-fail

# native: 1.1.1.1 SUCCEEDS  (set HOST = 0, rebuild)
#   iter 0..2  conn-ok

# libssl (no -D): BOTH hosts succeed
cyrius build docs/development/issues/repros/2026-06-09-native-tls-handshake-gap.cyr /tmp/libssl_ok
/tmp/libssl_ok   # conn-ok for either host
```

## Root cause

Unknown from the consumer side — flagging as a native-stack handshake gap for the
Cyrius agent to localize. Speculation on where to look, given 1.1.1.1 works and
example.com doesn't (both Cloudflare, so the delta is in the cert/extension
material the edge presents for each property):

- **Certificate chain / signature algorithm** the example.com property serves
  that `lib/tls_native.cyr` + sigil x509 can't verify yet (e.g. a chain or sig
  alg variant not in the native verifier; the meta-issue notes native shipped
  RSA / P-384 — example.com's leaf/intermediate may use something outside that
  set).
- **ServerHello / certificate-message reassembly** across TLS records (the
  `lib/tls.cyr` header comment references "server-flight reassembly (Release B)"
  as pending) — example.com's flight may span record boundaries differently than
  1.1.1.1's.
- **A TLS extension** example.com's edge requires/sends that the native client
  mishandles (ALPN set, SNI, supported_groups, etc.).

Capturing the native client's failure point (which handshake message / alert)
against example.com vs 1.1.1.1 should localize it quickly.

## Proposed fix

None proposed from the consumer side — needs native-stack internals. The
acceptance bar for sandhi to keep native as the hard default: native completes a
live HTTPS GET against the standard public set (example.com + a couple of common
API hosts), not just 1.1.1.1 / the in-tree native test server.

## Consumer-side workaround (sandhi)

sandhi 1.4.5 ships the switch anyway (native hard-default + `sandhi_tls_use_libssl()`
opt-out) per the deprecate-libssl direction, and documents that hosts the native
stack can't yet handshake need the explicit libssl opt-in until this gap closes.
That opt-in re-exposes the brk/fdlopen crash on repeated requests, so this issue
is what actually unblocks the libssl retirement.
