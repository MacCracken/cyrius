# `lib/tls.cyr` libssl backend never verifies the server hostname: any chain-valid cert for any name is accepted

**Status:** 🔴 **OPEN** — found by an abaco 2.4.9 TLS study; not repaired.
**Placement:** **6.6.13**, bite I1 — the next 6.6.x patch, as the filing asked (set by the user
2026-10-01; see `roadmap.md` § 6.6.13). CVE-class: it takes the next CVE id, spent in the commit that
records it.
**Discovered:** 2026-09-30, abaco 2.4.9 TLS study (abaco's currency-cache HTTPS fetch, built
against the libssl backend, accepted a certificate issued for a different host).
**Severity:** High — man-in-the-middle. Anyone holding a certificate that chains to a trusted
root (any public-CA cert for any domain they control) can impersonate every server the client
talks to. Silent: the handshake reports success.
**Affects:** cyrius 6.6.12 `lib/tls.cyr` libssl path: `tls_connect_alloc` (:665),
`tls_connect_complete` (:736), and so `tls_connect` (:753) / `tls_connect_with_ctx_hook` (:763).
Reached by every `-D CYRIUS_TLS_LIBSSL` build, **and by a default (native) build after
`tls_set_backend(TLS_BACKEND_LIBSSL)`** (:81). The native backend is not affected.

## Summary

The libssl client path sets SNI and `SSL_VERIFY_PEER`, but never tells OpenSSL which name the
certificate must match. `SSL_VERIFY_PEER` alone only checks the chain; OpenSSL does no
hostname check unless `SSL_set1_host` (or `X509_VERIFY_PARAM_set1_host` / `_set1_ip_asc`) is
called. So a server cert whose SAN is only `localhost` is accepted when the client connects
as `www.example.com`. The native backend refuses the same handshake (it binds dNSName /
iPAddress SANs, CVE-18, v6.1.36), so the two backends disagree on the security property that
matters most.

Measured with a throwaway P-256 CA and an `openssl s_server` whose cert has
`subjectAltName=DNS:localhost` only:

| client | `localhost` | `www.example.com` | untrusted CA |
|---|---|---|---|
| native (default build) | accepted | **refused** | refused |
| libssl via `tls_set_backend` (default build) | accepted | **accepted** ⛔ | refused |
| libssl (`-D CYRIUS_TLS_LIBSSL` build) | accepted | **accepted** ⛔ | refused |

The "untrusted CA" column is a control: chain verification works, only the name binding is
missing.

## Reproduction

`repros/2026-09-30-tls-libssl-no-hostname-verification.sh` (+ `.cyr`). It makes the CA and
server cert with `openssl`, so no key material is committed. Needs `openssl(1)`,
`libssl.so.3` and `~/.cyrius/dlopen-helper`. The exit code is the number of failing checks
across both builds.

```
docs/development/issues/repros/2026-09-30-tls-libssl-no-hostname-verification.sh; echo "exit=$?"
# -> exit=2 on 6.6.12 (native controls pass; one libssl FAIL per build)
```

## Root cause

`lib/tls.cyr`:

- :684-686 — `SSL_CTX_set_verify(ssl_ctx, SSL_VERIFY_PEER, 0)`: chain check only.
- :708-711 — `SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, …, host)`: this sets **SNI only**
  (what the client asks for), not the name the cert is checked against.
- :743 — `SSL_connect` runs with no expected host in the `X509_VERIFY_PARAM`.
- :207-310 (`_tls_init`) never resolves `SSL_set1_host`, `SSL_get0_param`,
  `X509_VERIFY_PARAM_set1_host` or `X509_VERIFY_PARAM_set1_ip_asc`.

`docs/development/lib-tls-contract.md` (:70-76, "Stdlib-applied defaults") lists the trust
store, `SSL_VERIFY_PEER` and SNI, and never states hostname-verification semantics, so the
gap is not visible from the contract either.

## Proposed fix

1. In `_tls_init`, resolve `SSL_set1_host` through the fdlopen `dlsym` bridge (next to
   `SSL_ctrl`, :250), plus `SSL_get0_param` and `X509_VERIFY_PARAM_set1_ip_asc` for IP
   literals. Treat them as **required**: if any is missing, leave `_tls_ok == 0` so
   `tls_available()` is 0 and connects fail closed, rather than connecting unverified.
2. In `tls_connect_alloc`, after `SSL_new` and before returning the ctx (beside the SNI call,
   :708): if `host` parses as an IPv4/IPv6 literal, call
   `X509_VERIFY_PARAM_set1_ip_asc(SSL_get0_param(ssl), host)` (and skip SNI, RFC 6066 §3);
   otherwise `SSL_set1_host(ssl, host)`. If the call returns != 1, free and return 0.
3. `host == 0` on the libssl path: refuse (return 0) unless the hook explicitly downgraded
   verification, matching the native backend's fail-closed behaviour.
4. Add the repro as a test in the TLS suite, run under both backends.
5. Contract: state in `lib-tls-contract.md` that every client connect verifies the chain
   **and** binds the leaf to `host` (dNSName with RFC 6125 wildcard rules, iPAddress for IP
   literals) on both backends, and that a hook which relaxes `SSL_VERIFY_PEER` owns the
   consequence.

## Consumer-side workaround

Use the native backend (the default) and never call `tls_set_backend(TLS_BACKEND_LIBSSL)`.
A consumer that must use libssl can pin the name itself from the ctx hook by resolving
`SSL_CTX_get0_param` + `X509_VERIFY_PARAM_set1_host` with `tls_dlsym` and applying them to the
`SSL_CTX*` the hook receives (the per-`SSL` param inherits it at `SSL_new`). The abaco HTTPS
currency fetch under study stays on the default native backend and never calls
`tls_set_backend`.
