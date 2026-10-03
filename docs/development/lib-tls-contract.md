# `lib/tls.cyr` — hook-surface contract

Formal contract for the public surface of `lib/tls.cyr`, **pinned at 6.6.13**.

It was first pinned at v5.10.42, after the surface stabilised across v5.6.40 (ALPN hook),
v5.10.13 (typed wrappers), v5.10.21 (session + 0-RTT) and v5.10.27 (staged connect for
client-side resumption), and was ratified by the sandhi 1.0.0 fold, the 1.1.0 alloc migration and
the 1.3.x session + 0-RTT consumption. It then stayed at v5.10.42 for a whole major while the
surface moved under it: through 6.6.12 it described libssl's defaults only, said `tls_read`
returned "bytes-read or -1", and named none of the trust-store, mTLS or server verbs. 6.6.13
re-pins it to the surface as it is: two backends with the native stack the default (v6.1.21), the
trust-store and mTLS verbs (v6.2.8), the server verbs (v6.2.24 / v6.2.25), and the 6.6.13
additions — the allocator-aware client connect, the server-identity binding on both backends,
thread safety, one error table for every read and write, the per-connection deadline and the
ChangeCipherSpec rule.

This document is the **invariant layer**: changes to the per-fn docstrings in `lib/tls.cyr` MUST
preserve the guarantees listed here unless the contract is explicitly amended in the same patch.
Defensive hardening and internal refactors must not change the observable behaviour described
below. Surface additions are allowed (new `tls_*` verbs) so long as existing verbs keep their
semantics.

## Provenance

- **Filing**: sandhi 1.1.x roadmap-cleanup pass, 2026-05-08 — the v5.10.42 pin.
- **Re-pin**: 6.6.13, issue `2026-09-30-tls-client-memory-and-alert-gaps` (d). The "Server
  identity" section comes from issue `2026-09-30-tls-libssl-backend-no-hostname-verification`,
  "Thread safety" from `2026-09-30-tls-first-use-thread-race`, and the deadline and
  ChangeCipherSpec rules from `2026-10-01-tls-native-no-deadline`.
- **ADR alignment**: sandhi-side ADR-0001 ("sandhi composes, doesn't reimplement"). The TLS hook
  surface is the place where composition happens; this document is the cyrius-side guarantee that
  anchors it.

## Transport model

Since the v6.1.21 native-default flip there are **two** transports behind one contract:

1. **The sovereign native cyrius TLS stack** (`lib/tls_native.cyr`) — the **default** backend.
   No libssl/OpenSSL, no `ld.so`; crypto and X.509 are in-tree (sigil), so it is the only backend
   on agnos and bare metal. TLS 1.3 and 1.2 (AEAD suites only), client and server, ALPN, client
   certificates (TLS 1.3 and 1.2, on both sides — see "Client certificates (mTLS) on a server"),
   the OS trust store with chain building, hostname binding. A hub plus six modules
   (`tls_native_{lowlevel,keysched,ctx,hs13,hs12,conn}.cyr`) and `lib/tls_hostid.cyr`, the host
   classifier both backends share (6.6.13).
2. **libssl 3.x**, loaded through `lib/fdlopen.cyr` (it needs the dlopen-helper and
   `libssl.so.3` + `libcrypto.so.3`). Opt-out: build with `-D CYRIUS_TLS_LIBSSL` for a libssl-only
   program (the native stack is not compiled in), or select it at runtime in a default build with
   `tls_set_backend(TLS_BACKEND_LIBSSL)`. See the `lib/tls.cyr` header for why libssl must be
   loaded through fdlopen (a minimal `%fs` TCB stub deadlocks libssl's pthread init at its first
   `SSL_CTX_new`).

`lib/tls.cyr` dispatches on the process-wide backend; the verb contract below is identical for
both unless a row says otherwise. Consumers MUST treat the transport as **opaque**:

- All handles (`ctx`, `handle` in hooks, `session`) are integer pointers; consumers may store and
  pass them, but MUST NOT dereference them or assume their layout. The hook's `handle` is an
  `SSL_CTX*` on libssl and the native ctx on native — which is why configuration goes through the
  typed `tls_set_*` / `tls_ctx_*` verbs.
- The contract is honoured by **both** backends: verb signatures and semantics survive a
  `tls_set_backend` switch; only the underlying pointer type changes. Where the backends still
  differ, the row says so.
- `tls_dlsym` (see "Escape hatch") is the one place where the contract leaks libssl ABI. It is
  soft-deprecated.

### Backend selection

| Verb | Returns | Contract |
|------|---------|----------|
| `tls_set_backend(b)` | 0 / -1 | Selects `TLS_BACKEND_NATIVE` (1) or `TLS_BACKEND_LIBSSL` (0) for every later verb. -1 when `b` is unknown or not compiled in (native in a libssl-only build). Process-global, a plain store: set it once, before any thread connects (see "Thread safety"). The I/O verbs dispatch on the CURRENT backend, not on the one that made the ctx — do not switch while a ctx is open. |
| `tls_get_backend()` | `TLS_BACKEND_NATIVE` / `TLS_BACKEND_LIBSSL` | The active backend: native by default, libssl in a `-D CYRIUS_TLS_LIBSSL` build. |

## Verb inventory (the contract surface)

### Availability probes

| Verb | Returns | Contract |
|------|---------|----------|
| `tls_available()` | 1 / 0 | Returns 1 once libssl has been successfully bootstrapped via fdlopen and the critical-symbol set has resolved — since 6.6.13 that set includes the five host-binding symbols (see "Server identity" below), so a libssl that cannot bind the leaf to `host` reads 0 rather than connecting unverified. Idempotent; runs `_tls_init` lazily. Returns 0 forever within the process once init has failed (no retry). Safe to call before any other verb. (Native backend: always 1.) |
| `tls_init_main()` | 1 / 0 | **6.6.13.** Warm the stack once — call it on the MAIN thread before spawning TLS workers. Returns `tls_available()`'s verdict. Native: installs the main thread's crypto block and builds every lazy table a handshake reaches (SHA-256/-384/-512, AES-GCM, Ed25519, the P-256 and P-384 sign/verify tables, the X.509 OID, validity-date and PEM tables) plus the system CA bundle cache. Recommended, not required (see "Thread safety"). Idempotent; once warmed a call allocates nothing; harmless on a worker (it installs nothing over the worker's own thread-local block). libssl: runs `_tls_init` — main thread only. |
| `tls_supports_session_resumption()` | 1 / 0 | Returns 1 iff the linked libssl exposes `SSL_get1_session` + `SSL_set_session` + `SSL_SESSION_free` + `SSL_CTX_set_session_cache_mode`. Probe BEFORE installing session callbacks. It reads the symbol cache only: 0 until libssl has been loaded (`tls_available()` or a connect on the libssl backend) — so 0 in a process that only uses the native backend, which has no session resumption through this surface. |
| `tls_supports_early_data()` | 1 / 0 | Returns 1 iff the linked libssl exposes the FULL 0-RTT client-correctness surface (write + read + max_early_data setter + get_early_data_status + SESSION_get_max_early_data). Probe BEFORE attempting any 0-RTT send/recv. Like the resumption probe: 0 until libssl has loaded. |

### Connect — fused (legacy + ALPN-hook)

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_connect(sock, host)` | (i64, i64) → i64 | ctx or 0 | Thin wrapper over `tls_connect_with_ctx_hook(sock, host, 0, 0)`. Preserved verbatim for pre-v5.6.40 consumers; never gains new arguments. |
| `tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx)` | (i64, i64, fnptr, i64) → i64 | ctx or 0 | Fused `tls_connect_alloc` + `tls_connect_complete` with an optional config hook; on a failed handshake it `tls_close`s the ctx itself and returns 0. Hook signature: `int hook_fp(hook_ctx, handle)`; it fires after the stdlib defaults below and before the handshake (libssl: before `SSL_new`). A non-zero hook return aborts the connect and returns 0 (libssl frees its `SSL_CTX`; native leaves the partial ctx in its allocator — see "Memory"). Pass `hook_fp == 0` to skip the hook. The server's leaf is verified against `host` (see "Server identity"); `host == 0` returns 0 unless the hook cleared verification. The socket is the caller's: connected before the call, closed by the caller after `tls_close`. |

**Stdlib-applied defaults, BEFORE the hook fires** (a hook overrides them by calling the
corresponding `tls_set_*` / `tls_ctx_*` verb):

| | libssl | native |
|---|---|---|
| Trust store | `SSL_CTX_set_default_verify_paths` | `tls_native_set_ca_system`: POSIX — the first readable of `/etc/ssl/cert.pem`, `/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`, `/etc/ssl/ca-bundle.pem`; **Windows (6.6.14) — never those paths** (drive-relative there: `C:\etc\ssl\cert.pem`, which any local user can create — CVE-65) **but the CurrentUser `ROOT` store**, through crypt32 loaded from System32, filtered by the root-program properties: a root whose purposes (prop 9) leave out serverAuth is not taken and a certificate in the `Disallowed` store never is; a root with a Disable date (props 104/122) or a NotBefore date (126/127) covering serverAuth, with root-program name constraints (84), or with a property that cannot be read or parsed is **refused whole** — the verifier has no per-root date or name bound, so it fails closed (a leaf issued before a NotBefore date is rejected where SChannel accepts it; cass: 41 roots taken, 12 refused). Read and parsed ONCE per process into a shared, immutable root set — after the first connect a connect costs 0 B for its roots, and `tls_native_ca_skipped(handle)` counts the certificate blocks it could not use (a P-521 root today; since 6.6.14 a malformed block — an unmatched BEGIN, bad base64 — which is skipped while the rest of the bundle installs; on Windows also the refused roots). With no store at all no roots are installed, so a verifying connect fails until the hook installs a trust store (`tls_ctx_load_verify_locations`). ⚠ Not Windows parity, in either direction: the auto-updated disallowed CTL in the registry is not consulted and `Disallowed` is applied to roots only, never to a server's intermediates or leaf; and Windows downloads roots it does not yet hold on demand when its own chain engine meets them, while the native client sees only the roots already in the store (those servers fail `TLS_ERR_CERT_INVALID`). |
| Verification | `SSL_CTX_set_verify(..., SSL_VERIFY_PEER, 0)` | `TLS_VERIFY_PEER`: the chain must reach a trusted, in-window CA root, with keyUsage, extendedKeyUsage and pathLen honoured (CVE-17), and the leaf must match `host` (CVE-18). Both are checked INSIDE the handshake, before it reports success, so the native handshake never yields a connected-but-unverified channel. |
| Protocol versions | libssl's defaults | TLS 1.2 – 1.3 (`tls_native_set_version_range` on the hook's handle narrows it) |

**Applied AFTER the hook** (libssl: post-`SSL_new`, before the handshake; native: inside the
handshake), from the hook's final verify mode:

- The leaf certificate bound to `host` — see "Server identity" below
- SNI set from `host` for a DNS-name host only — never for an IP literal or a host with no
  identity, on both backends (native since 6.6.14) — see the SNI bullet below

#### Server identity (hostname binding) — 6.6.13, CVE-59

Every client connect verifies the chain to a trusted root **and** binds the
leaf certificate to `host`, on **both** backends, with the same answers. Before
6.6.13 the libssl backend checked the chain only (`SSL_VERIFY_PEER` with no
expected identity), so any chain-valid certificate verified any host. The host
is classified once, by the same code on both backends (`lib/tls_hostid.cyr`;
RFC 9525 §6.3):

| `host` | Matched against | Examples |
|---|---|---|
| An IP literal: a dotted-quad IPv4 address with no leading zeros, or an RFC 4291 IPv6 address (`::` compression and a dotted-quad tail allowed) | iPAddress SANs only, octet for octet | `127.0.0.1`, `::1`, `::ffff:1.2.3.4` |
| Any other host without a `:` — a DNS name | dNSName SANs only, RFC 6125 as OpenSSL implements it (`X509_check_host` with `NO_PARTIAL_WILDCARDS`): ASCII case-insensitive; a dNSName is a wildcard only as `*.` followed by two or more labels of `[A-Za-z0-9-]` (none empty or hyphen-edged, no second `*`, no trailing dot), and its star stands for exactly one non-empty label of `[A-Za-z0-9-]` (`*.example.com` matches `a.example.com`, not `example.com`, `a.b.example.com` or `a_b.example.com`); any other dNSName — `*.com`, `*.example.com.`, `f*.example.com` — is compared literally; no fallback to the subject CN; no public-suffix list (`*.co.uk` matches `a.co.uk`) | `localhost`, `LOCALHOST`; `010.0.0.1` and `127.1` are names, as the resolver (`net_parse_ipv4`) treats them |
| `0`, `""`, a `:`-bearing host that is no literal, or a host starting with `.` (6.6.14) | nothing: there is no reference identity (OpenSSL would read `.example.com` as "any subdomain") | `[::1]`, `fe80::1%eth0`, `.example.com` |

- **No identity under `SSL_VERIFY_PEER` (the default) is refused.** On libssl
  `tls_connect_alloc` returns 0 and no handshake runs; on native the handshake
  fails and `tls_connect_complete` returns 0. `tls_connect` /
  `tls_connect_with_ctx_hook` return 0 on both.
- **A mismatch fails the handshake** (`tls_connect_complete` returns 0).
- **A hook that relaxes verification owns the consequence.** After
  `tls_set_verify(handle, 0, 0)` no identity is checked on either backend, and
  `host == 0` connects. On libssl, a hook that keeps `SSL_VERIFY_PEER` but
  installs a verify callback that accepts errors also accepts a wrong identity
  (OpenSSL reports the mismatch through the callback).
- **`host` is the identity; a hook's pin of the same kind is replaced.** The
  binding is made on the per-`SSL` `X509_VERIFY_PARAM`, which inherits the
  `SSL_CTX`'s. `X509_VERIFY_PARAM_set1_host` / `set1_ip_asc` REPLACE what was
  inherited, so a name a hook pinned on the `SSL_CTX` param (via `tls_dlsym`) is
  dropped for a DNS-name `host`, an IP it pinned is dropped for an IP-literal
  `host`, and the hostflags are replaced. A pin of the OTHER kind (an IP under a
  DNS-name `host`, a name under an IP-literal `host`) is kept and must match as
  well. To verify a different name, pass it as `host`. (Measured with OpenSSL
  3.6.5; pinned by the gate's P rows.)
- **SNI — both backends:** sent for a DNS-name host only; an IP-literal host, or
  one with no identity, sends no SNI (RFC 6066 §3). Native followed it from
  6.6.14 (`_tn_sni_len`, the classifier's verdict); until then its ClientHello
  carried an IP literal too.
- **libssl requires the binding symbols** `SSL_get0_param`,
  `SSL_get_verify_mode`, `X509_VERIFY_PARAM_set1_host`,
  `X509_VERIFY_PARAM_set_hostflags` and `X509_VERIFY_PARAM_set1_ip_asc` (every
  libssl.so.3 has them). If one is missing, `tls_available()` is 0 and every
  libssl connect returns 0: the backend fails closed. `SSL_set1_host` is
  deliberately not used, because from OpenSSL 3.0 it re-parses the name as an
  IP address with OpenSSL's own parser, which would let the libssl version
  decide the classification.
- **The backends agree, row for row (6.6.14, CVE-67).** Until 6.6.14 native took
  any `*.` dNSName as a wildcard over the host's first label (`*.com` verified
  `a.com`; `*.example.com.`, `*.a_b.com`, `*.*.example.com` and a non-LDH first
  label matched too), where libssl refuses. `tests/tcyr/crossos/tls_hostname_verdicts.tcyr`
  runs one SAN / host table through the native matcher on every host and through
  OpenSSL's `X509_check_host` / `X509_check_ip_asc` wherever libssl loads.
- Pinned end to end by `tests/gates/platform/tls_libssl_hostname_binding.sh` (both
  backends against OpenSSL's `s_server`).

#### Key exchange (native, 6.6.15)

The native stack does ECDHE on **x25519, secp256r1 and secp384r1**, in TLS 1.3 and TLS 1.2, as
client and as server — sigil's constant-time `ecdh_p256_*` / `ecdh_p384_*` for the NIST curves,
every key drawn through the `tls_native_set_entropy` hook, the peer's point validated by sigil
(0x04 prefix, coordinates below p, on the curve) and an all-zero x25519 secret refused (RFC 8446
§7.4.2, RFC 8422 §5.11), the shared secret the x-coordinate at full field length (RFC 8446 §7.4.2,
RFC 8422 §5.10). `tls_native_get_group` reports the negotiated group (29 / 23 / 24) on both roles.

- **The groups a ctx offers or accepts** are, in preference order, x25519, secp256r1, secp384r1 —
  or the list `tls_native_set_groups(ctx, groups, n)` installed (`groups` points at 1 to 3 i64
  `TLS_GROUP_*` values, none twice; `TLS_ERR_INVALID_PARAM` otherwise, the ctx unchanged). Native
  only — the hook's `handle` is the native ctx — and set before the handshake (a server's in its
  accept hook). The OpenSSL analogue is `SSL_set1_groups`.
- **TLS 1.3 client.** supported_groups lists the ctx's groups and the key_share carries ONE share,
  for the first of them — x25519 by default. A P-256 share up front would cost a second key pair
  on every connection (2.7 ms here against x25519's 2.4 ms; P-384 7.3 ms) to save a round trip only
  to a server without X25519, which is OpenSSL's and the browsers' choice too; a caller whose
  server prefers a NIST curve lists it first and gets that share instead. A server taking none of
  the share's group answers with a **HelloRetryRequest** (RFC 8446 §4.1.4), which the client takes
  ONCE: it sends the same ClientHello with a share on the requested group and the cookie echoed,
  and its transcript starts with message_hash(ClientHello1) (§4.4.1). Refused with RFC 8446's
  alert: a second HelloRetryRequest (unexpected_message, `TLS_ERR_PROTOCOL`); one for a group the
  client did not list, for the group it already shared, or changing nothing, one naming a cipher
  suite or session id it did not send, a non-null compression method, a supported_versions other
  than 0x0304, or any extension twice (illegal_parameter); a cookie whose length disagrees with its
  extension (decode_error); an extension other than supported_versions / key_share / cookie —
  unsupported_extension when the ClientHello did not carry it, illegal_parameter when it did
  (supported_groups, signature_algorithms, server_name after SNI, ALPN when offered: RFC 8446
  §4.1.4 / §4.2); a ServerHello after it on another cipher or group (illegal_parameter). One
  middlebox CCS may come after the HelloRetryRequest — still one per connection. Any ServerHello
  must echo the client's empty session id and carry compression method 0 (illegal_parameter).
- **TLS 1.3 server.** It takes the first of its groups the client sent a usable share for — a
  usable x25519 share is taken over asking for a group it prefers, which would cost a round trip —
  and otherwise sends ONE HelloRetryRequest for the first of its groups the client lists, reads the
  second ClientHello (one middlebox CCS may precede it) and requires there the share it asked for,
  the same legacy_session_id and the same cipher suite (illegal_parameter otherwise — never a
  second HelloRetryRequest). It refuses, with the alert, a key_share without supported_groups
  (missing_extension, RFC 8446 §9.2 — as OpenSSL does), a share for a group the client did not
  list, two shares for one group, a share of the wrong length, a point sigil refuses
  (illegal_parameter), a malformed supported_groups (decode_error), and no shared group
  (handshake_failure). A second ClientHello that no longer offers TLS 1.3 is illegal_parameter.
  **Which version a ClientHello asks for is its supported_versions' alone** (RFC 8446 §4.2.1): one
  listing 0x0304 is TLS 1.3; one without it, or without the extension, is TLS 1.2 — a key_share
  does not make it 1.3 (until 6.6.15 it did, so the server negotiated 1.3 with a client that had
  not offered it). **Middlebox compatibility** (RFC 8446 §D.4): when the client's legacy_session_id
  is not empty, the server sends one dummy ChangeCipherSpec directly after its first handshake
  message — the HelloRetryRequest, else the ServerHello — in the same write; with an empty one,
  none (until 6.6.15 it never sent it; OpenSSL tolerates the absence).
- **TLS 1.2 client.** It offers the ctx's groups — x25519 first by default, with or without a
  client certificate — and does ECDHE on whichever the server's ServerKeyExchange names, which must
  be one of them. A ServerKeyExchange signed with an ECDSA scheme is read as TLS 1.2 defines it —
  the scheme names the hash, the key names the curve — so a P-384 server certificate that signs
  SHA-256 verifies.
- **TLS 1.2 server.** It picks the first of its groups the client's supported_groups lists, its
  own first group when the client sends none (RFC 8422 §4), and refuses a client listing none of
  them with handshake_failure. A ClientKeyExchange point sigil refuses is illegal_parameter. The
  group never depends on the certificate: a P-384 certificate signs a secp256r1 exchange when the
  client lists both. But in TLS 1.2 the client's list also bounds an ECDSA certificate's curve
  (RFC 8422 §5.1), so a client whose supported_groups omits it is refused with handshake_failure
  — the server's refusal, where until 6.6.15 the client refused the certificate ("wrong curve").
  An Ed25519 certificate is not bound by the list. The suite is the first the client offers that
  the server can answer — ECDHE_ECDSA with AES-256-GCM-SHA384 or ChaCha20-Poly1305 (the server's
  key is ECDSA or Ed25519); none of those is handshake_failure. Until 6.6.15 an ECDHE_RSA offer was
  answered with an ECDHE_ECDSA suite the client never offered ("wrong cipher returned") and
  ECDHE-ECDSA-AES128-GCM-SHA256 alone failed with no alert.
- **Ephemeral secrets.** On every side the ephemeral private key is zeroised as soon as the shared
  secret exists (and a 1.3 client's first share's key when a HelloRetryRequest replaces it), the
  shared secret / premaster as soon as the handshake (1.3) or master (1.2) secret is derived — so
  each side's next flight already leaves without them — and every handshake driver
  (`tls_native_connect`, `tls_native_accept`, `tls_native_accept_12`) wipes both again on its way
  out, success or failure.
- **Memory.** A HelloRetryRequest adds about 2.8 KB to a client's handshake and 0.4 KB to a
  server's (measured at 6.6.15 against an Ed25519 server); the capacities under "Memory" hold.

⚠ **Until 6.6.15** only the 1.2 CLIENT (earlier in 6.6.15) did a NIST curve. The 1.3 client offered
x25519 alone and failed every HelloRetryRequest (`s_server -tls1_3 -groups P-256`: an alert,
`TLS_ERR_ALERT`); the 1.3 server took an x25519 share or nothing (a client without one failed
with `TLS_ERR_HANDSHAKE_FAILED` and no alert — even `s_client -groups P-256:X25519`, whose
HelloRetryRequest `tls_native_accept` refused to send); the 1.2 server sent every client an x25519
ServerKeyExchange (`s_client -tls1_2 -groups P-256`: "wrong curve"); neither 1.3 side checked for an
all-zero x25519 secret; and neither 1.3 side nor the 1.2 server ever zeroised its ephemeral key or
shared secret. 6.6.14's listing of a P-256 / P-384 client certificate's curve with x25519 the
only key exchange (a server ranking that curve first failed it) is gone too. Pinned by
`tests/tcyr/crossos/tls_native_ecdhe_groups.tcyr` (native↔native, every host),
`tests/tcyr/crossos/tls12_client_ecdhe.tcyr` and `tests/gates/platform/tls_native_client_auth_openssl.sh`
(its E, H and G legs, against OpenSSL).

### Connect — staged (resumption-aware, allocator-aware)

The v5.10.27 staged-connect surface exists to inject a cached session between `SSL_new` and
`SSL_connect` — the timing window libssl requires for client-side resumption. Since 6.6.13 it is
also where a deadline is set before the handshake (`tls_set_deadline`), and its `_in` form is the
allocator-aware client connect.

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_connect_alloc(sock, host, hook_fp, hook_ctx)` | (i64, i64, fnptr, i64) → i64 | ctx-pre-handshake or 0 | Builds the connection without running the handshake: applies the defaults above, runs the hook, binds the leaf to `host` (libssl: `X509_VERIFY_PARAM` + SNI for a DNS name here; native: inside the handshake — see "Server identity") and records the socket. Returns 0 on libssl for a host with no reference identity (`0`, `""`, `[::1]`) unless the hook cleared verification. On success the caller MUST follow with `tls_connect_complete` (handshake) OR `tls_close` (cleanup). Hook semantics identical to `tls_connect_with_ctx_hook`. The a == 0 form of `tls_connect_alloc_in`: everything lives on the global heap. |
| `tls_connect_alloc_in(a, sock, host, hook_fp, hook_ctx)` | (i64, i64, i64, fnptr, i64) → i64 | ctx-pre-handshake or 0 | **6.6.13.** `tls_connect_alloc` with an Allocator. Native: the ctx, the 40-byte shim, the handshake, a hook's trust store and ALPN list, and the per-ctx record buffers all come from `a`, so `tls_close(c); reset_via(a);` gives the whole connection back. A non-zero `a` MUST be an `arena_allocator` — see "Memory" for its rules and capacity. libssl: `a` does not apply (OpenSSL manages its own memory); the call runs the same libssl body as `tls_connect_alloc`. |
| `tls_connect_complete(ctx)` | (i64) → i64 | 1 / 0 | Runs the client handshake on a ctx from `tls_connect_alloc(_in)` (libssl `SSL_connect`; native `tls_native_connect`, which verifies the chain and the hostname before it returns). 1 on success; 0 on failure, a deadline that passed included. **On failure the ctx is NOT freed** — the caller MUST call `tls_close` (typically after inspecting the error, see "Failure"). Returns 0 on a null ctx without crash. |

### Accept — server (v6.2.24 / v6.2.25)

The symmetric mirror of the client trio, so a TLS server rides the same backend-dispatched
contract. `creds` is one pointer to a 4-slot struct `[cert@0, cert_len@8, key@16, key_len@24]` —
the DER certificate and the DER private key. The buffers are referenced, not copied, until the
handshake: the caller keeps them alive through `tls_accept_complete`.

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_accept_alloc(sock, creds, hook_fp, hook_ctx)` | (i64, i64, fnptr, i64) → i64 | ctx-pre-handshake or 0 | Builds a server ctx from `creds` and loads them (a bad certificate or key fails here, not in the handshake), then runs the hook (ALPN, client-certificate request). libssl: `TLS_server_method`, the DER certificate via `SSL_CTX_use_certificate_ASN1`, the key via `d2i_AutoPrivateKey` (RSA / EC / Ed25519 detected); a client-only libssl returns 0. The a == 0 form of `tls_accept_alloc_in`. |
| `tls_accept_alloc_in(a, sock, creds, hook_fp, hook_ctx)` | (i64, i64, i64, fnptr, i64) → i64 | ctx-pre-handshake or 0 | `tls_accept_alloc` with an Allocator: native draws the ctx, the whole handshake and record footprint and the shim from `a`, so a server loop `reset_via(a)`s each connection and keeps a flat RSS. libssl: `a` does not apply (routes to `tls_accept_alloc`). |
| `tls_accept_complete(ctx)` | (i64) → i64 | 1 / 0 | Runs the server handshake (native: TLS 1.3, or the TLS 1.2 driver for a 1.2 ClientHello or a 1.2-pinned ctx). 1 on success; 0 on failure, and the caller `tls_close`s the ctx. |
| `tls_accept(sock, cert, cert_len, key, key_len)` | (i64, i64, i64, i64, i64) → i64 | ctx or 0 | Convenience: `tls_accept_alloc` (no hook) + `tls_accept_complete`; on a failed handshake it closes the ctx itself and returns 0. |

**Client certificates (mTLS) on a server.** A hook asks for one with `tls_set_verify(handle,
mode, 0)` and a non-zero `mode`, and installs the roots a client certificate must chain to
(`tls_ctx_load_verify_locations`, or `tls_ctx_set_verify_paths` for the OS store). With
`SSL_VERIFY_PEER` (1) in `mode` both backends authenticate the client the same way. Without it they
differ: libssl applies OpenSSL's `SSL_CTX_set_verify`, which ignores `SSL_VERIFY_FAIL_IF_NO_PEER_CERT`
(2), `SSL_VERIFY_CLIENT_ONCE` (4) and `SSL_VERIFY_POST_HANDSHAKE` (8) unless PEER is set — no
CertificateRequest is sent — while native is never looser than asked and requests one:

| `mode` (OpenSSL bits) | native mode | native: an empty client Certificate | native: a presented certificate | libssl |
|---|---|---|---|---|
| `0` | `TLS_VERIFY_NONE` | — (no CertificateRequest is sent) | — | the same |
| `SSL_VERIFY_PEER` (1), alone or with 4 / 8 | `TLS_VERIFY_PEER` | accepted, no identity | MUST verify | the same |
| `SSL_VERIFY_PEER` \| `SSL_VERIFY_FAIL_IF_NO_PEER_CERT` (3), alone or with 4 / 8 | `TLS_VERIFY_FAIL_IF_NO_PEER_CERT` | refused | MUST verify | the same |
| `SSL_VERIFY_FAIL_IF_NO_PEER_CERT` (2) without PEER | `TLS_VERIFY_FAIL_IF_NO_PEER_CERT` | refused | MUST verify | no CertificateRequest |
| `SSL_VERIFY_CLIENT_ONCE` (4) or `SSL_VERIFY_POST_HANDSHAKE` (8) without PEER | `TLS_VERIFY_PEER` | accepted, no identity | MUST verify | no CertificateRequest |

- **What "verify" is (native, 6.6.14 — CVE-64).** The client's certificate_list — its leaf and any
  intermediates it sends — must chain to a trusted, in-window CA root of the server ctx, with
  keyUsage, extendedKeyUsage (clientAuth or anyExtendedKeyUsage) and pathLen honoured, and its
  CertificateVerify must verify under the leaf's key. **A server with no trust roots refuses every
  presented certificate** (fail closed, as OpenSSL does). No hostname is checked. The same rules
  in TLS 1.3 and TLS 1.2: a server ctx accepts 1.2 by default, and the 1.2 server sends a
  CertificateRequest too. The CertificateRequest offers ecdsa_sign certificates signing with
  ecdsa_secp256r1_sha256, ecdsa_secp384r1_sha384 or ed25519, and an empty certificate_authorities
  list — **an RSA client certificate is not accepted natively** (the client answers with an empty
  Certificate; libssl accepts it).
- **The refusal.** `tls_accept_complete` returns 0; `tls_native_get_last_error(handle)` is
  `TLS_ERR_CERT_INVALID` (no certificate under FAIL, or one that does not verify) or
  `TLS_ERR_AUTHN` (its CertificateVerify does not verify). The client is told with a fatal alert:
  certificate_required (1.3) / handshake_failure (1.2) for a missing certificate, bad_certificate,
  decrypt_error, illegal_parameter (a scheme not offered) or decode_error otherwise.
- **The identity.** After a successful handshake `tls_get_peer_spki_der(ctx, …)` (and natively
  `tls_native_get_peer_cert_der`) return the CLIENT's verified leaf on a server ctx; 0 when the
  client presented none, and 0 on a ctx whose handshake did not complete (one that failed after the
  certificate verified — its CertificateVerify, say — included). A connection error AFTER a
  completed handshake (the client gone without close_notify) does not clear it, as on libssl.
- **The `mode` mapping is never looser than asked.** `SSL_VERIFY_FAIL_IF_NO_PEER_CERT` without
  `SSL_VERIFY_PEER` is FAIL natively, and `SSL_VERIFY_CLIENT_ONCE` / `SSL_VERIFY_POST_HANDSHAKE`
  alone are PEER — stricter than OpenSSL, which ignores those bits without PEER (the table's last
  two rows; on libssl they request no certificate).
  ⚠ Until 6.6.13 every non-zero mode became `TLS_VERIFY_PEER` (bit 2 was dropped), the 1.3 server
  checked POSSESSION only (any self-signed, expired or foreign leaf was an identity, and a server
  with no roots accepted every client), the 1.2 server sent no CertificateRequest at all (a client
  offering only TLS 1.2 connected UNAUTHENTICATED), and `tls_get_peer_spki_der` read the server's
  own empty slot on a server ctx. The TLS 1.3 pin that this section used to prescribe is no longer
  needed.
- **The callback.** Native has no verify callback: `callback` is not run. A callback that would
  ACCEPT a peer OpenSSL rejects (a self-signed or pinned peer) does not — the native handshake
  fails closed; install that certificate or its CA as a root instead. A callback that would REJECT
  more (a pin) is not run either: check `tls_get_peer_spki_der` after the handshake, on either
  backend.
- **The client side.** A native client presents the certificate and key a hook installed
  (`tls_ctx_use_certificate_file` / `_private_key_file`) when a TLS 1.3 OR TLS 1.2 server asks,
  and an empty Certificate when it holds none (or none the server's CertificateRequest accepts).
  It presents its leaf alone, not a chain. Until 6.6.13 the 1.2 client failed any server that asked
  (`TLS_ERR_BAD_HANDSHAKE`). A P-256 / P-384 certificate's curve is in the 1.2 client's
  supported_groups because every NIST curve it does ECDHE on is (6.6.15 — "Key exchange" under
  Connect); the 6.6.14 trade-off this paragraph documented, a server ranking that curve above
  X25519 failing the handshake, is gone.
- **Memory.** Measured at 6.6.14 (P-256 server, one-certificate client): an mTLS handshake fits
  88,784 B of a server's arena in TLS 1.3 and 108,480 B in TLS 1.2 — both inside the 131,072 B
  below. A client's three TLS 1.2 messages before its CCS are bounded at 16 KiB on the server, and
  a 1.3 client Certificate at 8 KiB.

### I/O

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_write(ctx, buf, len)` | (i64, i64, i64) → i64 | `len`, 0, or a negative `TLS_ERR_*` | Encrypts and sends `len` bytes. See "What a read or a write returns" below. Native fragments into records of at most 16,384 bytes and returns `len` once every record is out. |
| `tls_read(ctx, buf, maxlen)` | (i64, i64, i64) → i64 | bytes, 0, or a negative `TLS_ERR_*` | Delivers up to `maxlen` (> 0) bytes of application data. See the table below. Native delivers at most one record's plaintext per call and HOLDS the rest of an over-long record for the next calls, so sub-record reads lose nothing; it drains post-handshake NewSessionTicket / KeyUpdate records itself (32 records with no application data in one call fail with `TLS_ERR_PROTOCOL`). |
| `tls_close(ctx)` | (i64) → i64 | 0 | No-op on a null ctx. libssl: `SSL_shutdown` if the symbol resolved (best-effort) and no read or write has failed (6.6.14), then frees the `SSL` and the `SSL_CTX`; safe on a pre- or post-handshake ctx. Native: sends close_notify if the connection is up (best-effort, under the deadline if one is set) and frees NOTHING — the ctx and its shim live in the allocator they came from (see "Memory"). Neither backend waits for the peer's close_notify, and neither closes the socket: that is the caller's, after `tls_close`. |

#### What a read or a write returns

One table for both verbs and both backends (6.6.13). The implementation's copies are the block
above `_tn_read_fail` in `lib/tls_native_conn.cyr` (native) and `_tls_ssl_io_ret` in
`lib/tls.cyr` (libssl).

| Result | `tls_read` | `tls_write` |
|---|---|---|
| `> 0` | bytes delivered into `buf`, at most `maxlen` | bytes written: all of `len` on native; `SSL_write`'s count on libssl |
| `0` | the peer's close_notify: the end of the stream. **Sticky**: every later read is 0 as well (native: without touching the socket, so a record appended after the close never reaches the caller) | only for `len == 0`. A failed write is never 0 |
| `-1` | `ctx == 0` (the value of `TLS_ERR_NOT_IMPLEMENTED`) | `ctx == 0` |
| `< 0` otherwise | a `TLS_ERR_*` code below | a `TLS_ERR_*` code below |

| Code | Value | Meaning | Backend |
|---|---|---|---|
| `TLS_ERR_IO` | -12 | The socket failed, or it closed with no close_notify (truncation). An expired `SO_RCVTIMEO` / `SO_SNDTIMEO` is this row: `TLS_ERR_TIMEOUT` is only the caller's own deadline. | both (libssl: `SSL_ERROR_SYSCALL`, and an unexpected EOF) |
| `TLS_ERR_TIMEOUT` | -22 | The deadline set with `tls_set_deadline` passed (see "Deadline"). | both |
| `TLS_ERR_ALERT` | -17 | The peer sent an alert: every alert that is not warning-level (a fatal close_notify included) and every description other than close_notify and user_canceled. A warning-level user_canceled is dropped and the read goes on (RFC 8446 §6.1). | both (libssl: a received alert, reason 1000 + description) |
| `TLS_ERR_PROTOCOL` | -19 | Native: a ChangeCipherSpec after the handshake (see "ChangeCipherSpec"); 32 records with no application data in one read; a read or write on a ctx that was never connected or is closed, and a write on a failed one. libssl: any libssl failure not above — a bad record MAC and a protocol violation included — and a write after the peer shut down. | both |
| `TLS_ERR_DECRYPT` | -15 | A record failed authentication (bad_record_mac: tampered or misdirected). libssl reports it as `TLS_ERR_PROTOCOL`. | native |
| `TLS_ERR_BAD_RECORD` | -3 | A malformed record: a header declaring more than the 16,640-byte ciphertext ceiling (record_overflow), a frame too short to open, an alert that is not exactly 2 bytes. | native |
| `TLS_ERR_WRONG_THREAD` | -23 | The call came from a thread other than the main thread (6.6.14). It was refused without touching libssl and the connection is unchanged: make it on the main thread (see "Thread safety"). Not a connection failure. | libssl |
| `TLS_ERR_WOULD_BLOCK` | -9 | A non-blocking socket had nothing ready (`WANT_READ` / `WANT_WRITE`) and no deadline is set: call again. The native backend needs a BLOCKING socket — there `EAGAIN` reads as `TLS_ERR_IO` and fails the connection; bound a native read with `tls_set_deadline` instead. | libssl |
| `TLS_ERR_OOM` | -11 | The ctx's record buffer could not be allocated (the first read or write, from an exhausted arena). | native |
| `TLS_ERR_INVALID_PARAM` | -10 | `tls_read` with `maxlen <= 0` (does not fail the ctx). | native |
| `TLS_ERR_RECORD_OVERFLOW` | -20 | An authenticated record whose plaintext exceeds 2^14 bytes (RFC 8446 §5.4; `lib/tls_native_lowlevel.cyr`). | native |
| other `TLS_ERR_*` | | Passed through from the record layer. Every `TLS_ERR_*` value is distinct (pinned by `tests/tcyr/crypto/tls_native_scaffold.tcyr`). | native |

**After a negative result the connection is over.** Native: a failed read, and a write whose
socket I/O failed, leave the ctx FAILED — every later `tls_read` returns the same code (a fatal
alert stays `TLS_ERR_ALERT`), and `tls_write` returns `TLS_ERR_PROTOCOL`. Three negatives leave the
ctx's state as it was: `TLS_ERR_INVALID_PARAM`; the `TLS_ERR_PROTOCOL` a ctx that is not connected
(never connected, closed, or already failed) answers with; and a write whose record could not be
sealed, which returns the sealer's code. None of them makes the connection usable again. libssl
(6.6.14): the same rule — the first negative other than `TLS_ERR_WOULD_BLOCK` is kept on the ctx,
every later `tls_read` returns it, every later `tls_write` returns `TLS_ERR_PROTOCOL`, neither calls
libssl again, and `tls_close` sends no close_notify (OpenSSL forbids `SSL_shutdown` after a fatal
error). Until 6.6.14 a SECOND libssl read after a fatal alert returned 0 — OpenSSL reports
`SSL_ERROR_ZERO_RETURN` once it has seen the peer's shutdown — so the re-read looked like a clean
end. Either way: `tls_close`. A libssl-only build
(`-D CYRIUS_TLS_LIBSSL`) defines only the codes its backend returns — `TLS_ERR_NOT_IMPLEMENTED`,
`_WOULD_BLOCK`, `_INVALID_PARAM`, `_IO`, `_ALERT`, `_PROTOCOL`, `_TIMEOUT`, `_WRONG_THREAD` — with
the same values;
a consumer naming any other code compiles against the default build only.

#### ChangeCipherSpec (native, 6.6.13)

A ChangeCipherSpec is a plaintext, unauthenticated record (`14 03 03 00 01 01`). The native
backend accepts exactly what the RFCs allow, and nothing else:

- TLS 1.3: at most ONE per connection, after the first ClientHello and before the peer's Finished
  (middlebox compatibility, RFC 8446 §5); it is dropped. A HelloRetryRequest opens no second
  window: the peer's one CCS comes after the HelloRetryRequest / before the second ClientHello,
  or after the ServerHello / before its encrypted flight (RFC 8446 §D.4), never both (6.6.15).
- TLS 1.2: exactly one, directly before the peer's Finished (RFC 5246 §7.1).
- The record must be the single byte 1.

What it SENDS: in TLS 1.3 the native server sends one after its first handshake message when the
client's legacy_session_id is not empty (RFC 8446 §D.4 — a MUST in compatibility mode; 6.6.15),
none otherwise; the native client sends an empty legacy_session_id and no CCS.

Anything else — a second CCS, a malformed one, one before the ClientHello or after the handshake, a
1.2 Finished with no CCS before it — fails the connection with `TLS_ERR_PROTOCOL` (from the
handshake, or from `tls_read`) after a best-effort fatal `unexpected_message` alert. Before 6.6.13
any number of CCS records was skipped, during and after the handshake, so anyone on the path could
hold a reader indefinitely. The libssl backend applies OpenSSL's own rules.

#### Deadline (6.6.13)

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_set_deadline(ctx, abs_ns)` | (i64, i64) → i64 | 0 / `TLS_ERR_*` | An absolute deadline for the connection: the handshake and every later `tls_read` / `tls_write` (native: the close_notify `tls_close` sends, too). `abs_ns` is on lib/chrono's monotonic `clock_now_ns()` scale (`clock_now_ns() + 5000000000` is five seconds from now); 0 clears it; it may be changed between reads. Set it between `tls_connect_alloc(_in)` and `tls_connect_complete` (or `tls_accept_alloc(_in)` and `tls_accept_complete`) so it bounds the handshake. Once it passes, reads and writes return `TLS_ERR_TIMEOUT`, `*_complete` returns 0, and the native ctx is failed (a record may be half read: the stream cannot resume). Returns 0, `TLS_ERR_INVALID_PARAM` (ctx 0, `abs_ns` < 0), or on a libssl without `SSL_get_error` `TLS_ERR_NOT_IMPLEMENTED`: a deadline that cannot be honoured is refused, never ignored. With no deadline set, nothing changes and no clock is read. |

On a bare native ctx (no shim) the same verb is `tls_native_set_deadline(ctx, abs_ns)`
(`TLS_OK` / `TLS_ERR_INVALID_PARAM`). How the deadline bounds a call depends on the transport:

| Transport | Bound |
|---|---|
| Native, default transport, Linux, macOS and Windows (6.6.14) | A read waits for readiness with the time left (`fd_wait_ready`: poll, or `WSAPoll` on Windows) and then reads once, so every byte costs a clock check; a write runs the socket non-blocking for the call (`O_NONBLOCK`, or `ioctlsocket(FIONBIO)` on Windows) and waits for writability, and the fd is restored on every exit — its status flags on Linux and macOS; a Windows socket is left **blocking**, the mode `lib/net.cyr` creates it in, because Windows cannot read `FIONBIO` back. |
| Native, agnos, a tagged socket | `sock_recv` / `sock_send` take the time left themselves; a send can overshoot by one `sock_send` stall (~8 s): the kernel waits for each segment's ACK inside the call and `sock_send#48` takes no time bound, so closing it needs a bounded send in agnos. |
| Native, a custom transport (`tls_native_set_transport`), an agnos fd that is not a socket, a Windows HANDLE that is not a socket (a pipe, a file) | Checked BETWEEN calls only: a single call is bounded by the transport itself. |
| libssl | Every `SSL_connect` / `SSL_accept` / `SSL_read` / `SSL_write` runs with the socket non-blocking, driven by `SSL_get_error`'s `WANT_READ` / `WANT_WRITE` and `fd_wait_ready`; the socket's status flags are restored after each call. |

**Windows, native (6.6.14):** the default transport reads and writes a Winsock socket with
`ws2_32` `recv` / `send` — it used `ReadFile` / `WriteFile`, which fail on a socket, so until
6.6.14 native TLS did not run over `lib/net.cyr` sockets on Windows at all (roadmap backlog j). A
HANDLE that is not a socket still goes through `ReadFile` / `WriteFile`.

**SIGPIPE, native (6.6.14, CVE-66):** a record write — `tls_write`, a handshake flight, the
close_notify `tls_close` sends, a fatal alert — to a peer that has reset the connection fails with
`TLS_ERR_IO`; it never raises SIGPIPE, so it cannot kill a process that has not ignored the signal.
Linux sends with `MSG_NOSIGNAL`; macOS sets `SO_NOSIGPIPE` on the socket before the connection's
first write (a socket that refuses it — xnu does once the connection is reset — fails the write
with `TLS_ERR_IO` instead of writing); Windows and agnos raise no such signal. The process-wide
signal disposition is never touched. A pipe or a file used as the transport keeps `write(2)`'s
SIGPIPE — neither OS has a per-call flag for one — and so does a custom transport
(`tls_native_set_transport`), whose writes are its own. ⚠ This changes the syscalls a native TLS
writer makes: on Linux a socket is written with `sendto(2)` (44 on x86_64, 206 on aarch64;
`write(2)` only for an fd that is not a socket), and on macOS each connection adds one
`setsockopt(2)`. A seccomp allowlist around a native TLS writer must permit them — one that
permits `write` but not `sendto` kills the process on its first record write. (A deadline adds
`fcntl` and `poll`, as it has since 6.6.13.)

#### SIGPIPE on the libssl backend (6.6.14)

A libssl call that writes to a peer that has closed — `tls_write`, `tls_read` (an alert or a
KeyUpdate answer), the handshake in `tls_connect_complete` / `tls_accept_complete`, the
close_notify in `tls_close`, the 0-RTT pair — fails like any other socket error: `tls_read` /
`tls_write` return `TLS_ERR_IO`, the `*_complete` verbs 0. It does not raise SIGPIPE: around each
such call `lib/tls.cyr` blocks SIGPIPE in the CALLING thread only, consumes a SIGPIPE that call
itself raised (`rt_sigpending`, then a zero-timeout `rt_sigtimedwait`), and restores the caller's
mask — libpq's pattern. The process-wide disposition is never changed, a SIGPIPE the caller already
had pending is left pending, and other threads are untouched. Until 6.6.14 libssl's `write(2)` to a
closed peer raised SIGPIPE, whose default action killed the process (CVE-66, the libssl half).

### Trust store and client certificates (v6.2.8)

Backend-agnostic replacements for the `tls_dlsym("SSL_CTX_*")` trust-store and mTLS calls. They
are called from the hook, on its `handle`. Return convention (OpenSSL's): **1 = success**, 0 =
failure, -1 = null handle or an unresolved libssl symbol.

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_ctx_load_verify_locations(handle, cafile, capath)` | (i64, cstr, cstr) → i64 | 1 / 0 / -1 | Trust the PEM bundle at `cafile`. libssl: `SSL_CTX_load_verify_locations`, which ADDS to the store (the system roots stay trusted), `capath` honoured. Native: REPLACES the ctx's roots with the file's (the shared system set itself is never modified), `capath` ignored; the file (at most 16 MiB, `TLS_CAFILE_MAX`) is read into a buffer of exactly its size from the ctx's allocator, so an arena-backed ctx returns it on `reset_via`, and a global-heap ctx retains about twice the file's size plus 272 B per root (6.6.13; it was a megabyte per call). 0 when the file cannot be read or holds no usable certificate. `tls_native_ca_skipped(handle)` (native) then counts the blocks it could not use — a malformed block among them since 6.6.14, skipped while the rest install: after a success, installed + skipped == the bundle's PEM block count. |
| `tls_ctx_set_verify_paths(handle)` | (i64) → i64 | 1 / 0 / -1 | Trust the OS default store: `SSL_CTX_set_default_verify_paths`, or native's shared system root set — on Windows the CurrentUser `ROOT` store since 6.6.14 (0 where there is no store). |
| `tls_ctx_use_certificate_file(handle, path, type)` | (i64, cstr, i64) → i64 | 1 / 0 / -1 | mTLS: the certificate the CLIENT presents when a server asks. `type` 1 = PEM, 2 = DER (`SSL_FILETYPE_*`). Native: client contexts only (0 on a server ctx, before anything is read); the file (at most 1 MiB, `TLS_CREDFILE_MAX`) is read into a buffer of exactly its size from the ctx's allocator, so an arena-backed ctx returns it on `reset_via`; a larger file is refused (0), never cut short. Before 6.6.14 each call kept a 64 KiB global-heap buffer and a longer file was parsed truncated. |
| `tls_ctx_use_private_key_file(handle, path, type)` | (i64, cstr, i64) → i64 | 1 / 0 / -1 | mTLS: the client's private key. Native auto-detects PEM or DER (`type` ignored); client contexts only, and the same read as above (the key stays referenced from that buffer). |

### Hook-time configuration (typed wrappers)

These are the **only safe-across-transport-swap** ways to configure the connection. Each replaces
an earlier `tls_dlsym` + `fncall*` call site. New consumers MUST use these in preference to
`tls_dlsym`.

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_set_alpn(handle, protos, protos_len)` | (i64, i64, i64) → i64 | 0 / non-0 | Sets ALPN protocols. **`protos` is OpenSSL wire format**: each protocol length-prefixed (`\x02h2\x07http/1.1` advertises `h2 + http/1.1`). `protos_len` is total bytes. **Return convention inverted from most OpenSSL fns: 0 = success, non-zero = failure** (matches `SSL_CTX_set_alpn_protos` man page). Returns -1 on null handle or unresolved symbol. Native: `protos_len` must be 1..255 (else `TLS_ERR_INVALID_PARAM`); the list is copied into the ctx's allocator. |
| `tls_set_verify(handle, mode, callback)` | (i64, i64, fnptr) → i64 | 0 / -1 | Overrides stdlib's default `SSL_VERIFY_PEER`. `mode` is an OpenSSL `SSL_VERIFY_*` flags bitmask. `callback == 0` disables the cb (mode-only override). 0 = success; -1 = null handle or unresolved symbol. Native has no verify callback: `callback` is not run (see "Client certificates (mTLS) on a server" for what that means either way). Native mode (6.6.14): `0` is `TLS_VERIFY_NONE` (no chain, no identity); any mode with `SSL_VERIFY_FAIL_IF_NO_PEER_CERT` (2) set is `TLS_VERIFY_FAIL_IF_NO_PEER_CERT` (with PEER or without — never looser than asked); any other non-zero mode is `TLS_VERIFY_PEER`. On a client FAIL and PEER verify alike. On a server it requests a client certificate (see "Accept"). |

### Peer introspection (v6.0.82)

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_get_alpn_selected(ctx, buf, bufmax)` | (i64, i64, i64) → i64 | length / 0 | Copies the negotiated ALPN protocol into `buf`. 0 when none was negotiated, `bufmax` is too small, or ctx is null. Both backends. |
| `tls_get_peer_spki_der(ctx, buf, bufmax)` | (i64, i64, i64) → i64 | length / 0 / `TLS_ERR_BUFFER_FULL` | Copies the PEER leaf's SubjectPublicKeyInfo DER — the HPKP pin target; consumers SHA-256 it. On a client ctx the server's; on a server ctx the client's verified certificate (natively since 6.6.14: it read the server's own empty slot and answered 0; 0 also when the handshake did not complete, and kept through a later connection error). 0 on no certificate, a parse failure or a null ctx. A `bufmax` too small: 0 on libssl, `TLS_ERR_BUFFER_FULL` (-18) on native. |

### Session resumption (libssl only)

These verbs (and the callbacks and 0-RTT verbs below) wrap libssl directly and do not check the
backend. The native backend has no client-side session resumption or 0-RTT through this surface:
probe `tls_supports_session_resumption()` / `tls_supports_early_data()` (both 0 in a process that has never loaded libssl). With a
native ctx or handle they are no-ops only while libssl has never been loaded in the process;
once it has (a libssl connect, `tls_dlsym`), they would hand the native pointer to libssl — call
them on libssl ctxs only.

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_get_session(ctx)` | (i64) → i64 | session or 0 | Returns the post-handshake session pointer (refcount-bumped via `SSL_get1_session`). Caller OWNS the returned ref and MUST call `tls_session_free` when done. 0 means either ctx has no established session yet, libssl missing the symbol, or null ctx. Valid only between successful `tls_connect_complete` and `tls_close`. |
| `tls_set_session(ctx, session)` | (i64, i64) → i64 | 1 / 0 | Installs a previously-cached session. **MUST be called between `tls_connect_alloc` and `tls_connect_complete`** — installing post-handshake is a no-op. Does NOT take ownership of the session pointer; caller still owns the ref. Returns 0 on null ctx / null session / unresolved symbol. |
| `tls_session_free(session)` | (i64) → i64 | 0 | Releases one ref via `SSL_SESSION_free`. Idempotent on null. Safe to call when libssl missing the symbol (no-op). |

### Session cache callbacks (server-side or persistent client cache; libssl only)

Three callbacks installed on the SSL_CTX (the `handle` arg from inside the hook). Each is a thin
`fncall2` over the libssl `SSL_CTX_sess_set_*_cb` pair; no return-value translation.

| Verb | CB signature | Contract |
|------|--------------|----------|
| `tls_ctx_set_session_new_cb(handle, cb_fp)` | `int new_cb(SSL*, SSL_SESSION*)` | Fires when a handshake produces a session worth caching. **Return 1 to transfer ownership to the consumer** (consumer's cache impl owns the ref); 0 means libssl retains ownership. |
| `tls_ctx_set_session_remove_cb(handle, cb_fp)` | `void remove_cb(SSL_CTX*, SSL_SESSION*)` | Fires when libssl invalidates a session. Consumer's cache should evict matching entries. |
| `tls_ctx_set_session_get_cb(handle, cb_fp)` | `SSL_SESSION* get_cb(SSL*, unsigned char *id, int len, int *copy)` | Fires during handshake to fetch a cached session by id. **Set `*copy = 1` to bump refcount on the returned session; 0 to transfer ownership** to libssl. |
| `tls_ctx_set_session_cache_mode(handle, mode)` | — | Enables caching at the SSL_CTX level. `mode` ∈ `{SSL_SESS_CACHE_OFF, _CLIENT, _SERVER, _BOTH}`. Returns previous mode, or 0 if libssl missing the symbol. |

**Caveat — leaky abstraction**: the four callback signatures above are literal libssl types.
The native backend (the default since v6.1.21) implements none of this sub-surface; giving it one
would either expose identical types through a compatibility shim or amend this sub-surface
explicitly, in the patch that lands it. Consumers writing session callbacks are coupled to
libssl's session-cache state machine; this is acknowledged technical debt, not a current bug.

### 0-RTT (TLS 1.3 early data; libssl only)

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_ctx_set_max_early_data(handle, max)` | (i64, i64) → i64 | 1 / 0 | Server-side: max early-data byte budget per session. `max == 0` disables 0-RTT (libssl default). RFC 8446 recommends 16384 as a starting point; consumer cache impl should bound against replay-attack risk. Returns 0 if libssl missing the symbol. |
| `tls_write_early_data(ctx, buf, len)` | (i64, i64, i64) → i64 | bytes-written or -1 | Client-side write of 0-RTT payload BEFORE handshake completes. Valid only when `ctx` has a session installed via `tls_set_session` AND the session's server advertised acceptable 0-RTT (probe with `tls_session_get_max_early_data` first). -1 on error / null ctx / unresolved symbol. |
| `tls_read_early_data(ctx, buf, maxlen)` | (i64, i64, i64) → i64 | bytes / -2 / -1 | Server-side read of 0-RTT payload. **Three return states**: positive = bytes read into buf; -2 = early data exhausted, caller transitions to `tls_read` for the post-handshake stream (libssl `SSL_READ_EARLY_DATA_FINISH`); -1 = error or unresolved symbol. |
| `tls_get_early_data_status(ctx)` | (i64) → i64 | NOT_SENT / REJECTED / ACCEPTED | Client-side post-handshake check. Call AFTER `tls_connect_complete`. Returns one of `TLS_EARLY_DATA_NOT_SENT` (0; no early data attempted, OR null ctx, OR unresolved symbol — safe for consumers to treat as non-rejection), `TLS_EARLY_DATA_REJECTED` (1; server rejected — caller MUST resend over the normal stream via `tls_write`), `TLS_EARLY_DATA_ACCEPTED` (2; response is on the way via `tls_read`). |
| `tls_session_get_max_early_data(session)` | (i64) → i64 | byte budget or 0 | Pre-attempt eligibility probe. Returns the max early-data budget the cached session's server advertised at issue time. 0 means the session does NOT advertise 0-RTT support (don't attempt). 0 on null session / unresolved symbol — same semantic as "session doesn't advertise 0-RTT". |

## Memory: where a connection lives

- **a == 0** (`tls_connect_alloc`, `tls_accept_alloc`, the fused verbs) — native: the global
  no-free heap. `tls_close` frees nothing, so each connection's handshake state stays allocated for
  the life of the process. Since 6.6.13 nothing grows per call: the record buffers are allocated
  once per ctx and the system roots are the shared set, so reads, writes and `tls_close` after the
  first retain 0 B. A long-lived client or server that connects repeatedly uses the `_in` form.
- **An Allocator `a`** (`tls_connect_alloc_in`, `tls_accept_alloc_in`) — native: the ctx, the
  shim, the handshake, a hook's trust store and ALPN list, and the record buffers all come from
  `a`; reads and writes after the first allocate nothing. The rules:
  - `a` MUST be an `arena_allocator` (sigil's X.509 parse takes the raw arena behind it);
  - create it ONCE, not per connection (`arena_free` does not munmap);
  - `tls_close` the ctx FIRST, then `reset_via(a)` — not `alloc_reset` — between connections;
  - its capacity must cover one whole connection, because the reset only runs between
    connections: measured at 6.6.13 against a one-certificate P-256 server, 175,208 B for a TLS 1.3
    client and 153,128 B for TLS 1.2, more for a longer chain; a server's mTLS-1.3 worst case fits
    131,072 B;
  - the shared system root set lives on the global heap, never in `a`, so resetting `a` never
    disturbs another connection's roots.
- **libssl** — OpenSSL's own heap: `tls_close` frees the `SSL` and the `SSL_CTX`; `a` does not
  apply; the 40-byte shim is on the global heap.

```
var a = arena_allocator(262144);              # once
while (serving) {
    var c = tls_connect_alloc_in(a, sock, host, hook, 0);
    if (c != 0) {
        tls_set_deadline(c, clock_now_ns() + 10000000000);   # optional: 10 s for the exchange
        if (tls_connect_complete(c) == 1) { ...tls_write / tls_read...; }
        tls_close(c);
    }
    # close `sock` (the caller's socket)
    reset_via(a);                             # the whole connection, back
}
```

## Lifecycle invariants

These ordering rules are part of the contract. Verbs called outside their valid window have
defined no-op behaviour (return 0 or -1 per table), but consumer logic SHOULD respect the windows.

```
   tls_init_main()   (optional; once, main thread)        tls_available()
                               |
   tls_connect_alloc(_in)(sock, host, hook, hctx)     tls_accept_alloc(_in)(sock, creds, hook, hctx)
        hook fires here: typed tls_set_* / tls_ctx_* verbs
                               |
                  0 --> nothing to close (see "Failure")
                               |
                      [pre-handshake ctx]
                      tls_set_deadline?   (bounds the handshake and all later I/O)
                      tls_set_session?    (libssl resumption only)
                               |
          tls_connect_complete / tls_accept_complete --> 0 --+
                               | 1                          |
                        [connected ctx]                     |
                      tls_write / tls_read (repeated)       |
                      tls_get_session? (libssl)             |
                               |                            |
                        tls_close(ctx) <--------------------+
                               |
                 the caller closes the socket;
                 an `_in` connection: reset_via(a)
```

`tls_connect` / `tls_connect_with_ctx_hook` / `tls_accept` collapse alloc + complete into one
call. Consumers that need neither resumption, a deadline over the handshake nor an allocator use
those.

## Failure / partial-state contract

- **`tls_connect_alloc(_in)` / `tls_accept_alloc(_in)` return 0** → nothing to close: the caller
  does NOTHING (no `tls_close`). libssl freed its `SSL` / `SSL_CTX` before returning; native's
  partial ctx is in its allocator — kept by the global heap, returned by `reset_via(a)`.
- **`tls_connect_complete` / `tls_accept_complete` return 0** → the caller still owns the ctx and
  MUST call `tls_close`. The reason: native — `tls_native_get_last_error(handle)` on the native
  handle the hook received (a `TLS_ERR_*`: `TLS_ERR_TIMEOUT`, `TLS_ERR_ALERT`,
  `TLS_ERR_CERT_HOSTNAME_MISMATCH`, …); libssl — `SSL_get_error` via `tls_dlsym`.
- **A negative `tls_read` / `tls_write`** → the connection is over (see the I/O table); `tls_close`
  it.
- **`tls_close` twice** → do not. libssl double-frees. Native's second call is a no-op only while
  the ctx's memory is intact, i.e. before `reset_via(a)`. Consumer-side state must track ctx
  liveness.
- **`tls_close` on a null ctx** → returns 0, no-op.
- **`tls_close` never closes the socket.**
- **`tls_get_session` between alloc and complete** → returns 0 (no established session). Safe to
  call defensively.
- **`tls_*_early_data` when `tls_supports_early_data() == 0`** → returns the documented error
  sentinel (-1 / -2 / 0 / NOT_SENT) per table above. Consumers MUST probe
  `tls_supports_early_data` before attempting an early-data flow.

## Thread safety

Added 6.6.13 (issue `2026-09-30-tls-first-use-thread-race`). The two backends differ, and the
libssl rule is a limit, not a guarantee.

**Native backend (the default).**

- Client and server verbs may run concurrently on any number of threads, each on its **own**
  ctx. A ctx is single-threaded: one ctx's `tls_read` / `tls_write` / `tls_close` must not run
  on two threads at once unless the caller holds its own lock.
- **First use is race-free from any thread**, with no preparation. sigil ≥ 3.13.6 builds each
  lazy table under a 0 → 1 → 2 once-guard and installs the main thread's crypto block only on a
  thread that has none; the system CA bundle (`tls_native_set_ca_system`, reached by every
  connect) is read once per process and published fenced. Measured with the filed repro on
  x86_64 and natively on aarch64, for P-256, RSA-2048 and Ed25519 chains: two threads whose
  first connects overlap, a later third thread, and a worker-then-main first use all succeed.
  Through 6.6.12 the first two failed every handshake and the third was a SIGSEGV.
- **`tls_init_main()` on the main thread before spawning TLS workers is recommended, not
  required.** It moves the first-use cost (about 1.3 MB of sigil tables, the P-256 / P-384 comb
  among them, and the bundle read) off the first handshake, and it ends the thread-pointer probe
  sigil's `cbank()` makes on every call until the main thread's block exists — two syscalls per
  call on an x86 kernel without FSGSBASE. Idempotent; calling it again, or from a worker, is safe.
  The 6.6.12 workaround (`crypto_tls_main_init(); ecdsa_p256_warm(); ecdsa_p384_warm();`) stays
  valid; `tls_init_main()` covers it and more.
- **Process-global configuration is set once, before any thread connects**: `tls_set_backend`,
  `tls_native_set_transport`, `tls_native_set_entropy`. They are plain stores, not per-ctx state.
- **Lane bound.** sigil hands each crypto-touching thread a scratch lane on its first use and
  never takes it back: after **63 lifetime** crypto threads lanes are shared and
  `crypto_banks_exhausted()` reads 1. Two threads in one lane can corrupt each other's digest or
  handshake — fail-closed noise, not a forged acceptance (the asymmetric stack is stack-local).
  Reuse workers rather than retiring them, or cap the pool.

**libssl backend (`-D CYRIUS_TLS_LIBSSL`, or `tls_set_backend(TLS_BACKEND_LIBSSL)`): MAIN THREAD
ONLY, and it FAILS CLOSED off it (6.6.14).**

- Every libssl call — first use, connect, accept, read, write, close, the hook-time config verbs,
  introspection, sessions and 0-RTT, `tls_dlsym` — must be made on the main thread, and a libssl
  ctx must not migrate to a worker. The glibc that `fdlopen` bootstraps needs a glibc TCB; a cyrius
  `thread_create` worker's thread pointer holds cyrius's own thread-local block instead.
- **Off the main thread every libssl verb refuses, without touching libssl**, with its own failure
  value: `tls_read` / `tls_write` / `tls_set_deadline` return `TLS_ERR_WRONG_THREAD` (-23);
  `tls_available` / `tls_init_main` / `tls_connect_alloc(_in)` / `tls_connect` /
  `tls_accept_alloc(_in)` / `tls_accept` / the `*_complete` verbs / `tls_dlsym` /
  `tls_get_alpn_selected` / `tls_get_peer_spki_der` / the session and cache verbs return 0;
  `tls_set_alpn` / `tls_set_verify` / `tls_ctx_load_verify_locations` / `tls_ctx_set_verify_paths` /
  `tls_ctx_use_*_file` / `tls_write_early_data` / `tls_read_early_data` return -1;
  `tls_get_early_data_status` returns `TLS_EARLY_DATA_NOT_SENT`; `tls_close` returns 0 and frees
  nothing (the `SSL` and `SSL_CTX` leak — close the ctx on the main thread). A refusal changes no
  state: the same call made on the main thread afterwards works, and a worker's first use does not
  claim the one-time initialisation. Through 6.6.13 the call crashed or hung instead (measured on
  x86_64: `tls_available()` on main then one fetch on a worker was a SIGSEGV; a worker's cold first
  use hung).
- "The main thread" is the thread whose id is the process id (`gettid() == getpid()`, two syscalls
  per libssl call, read fresh — a cached pid is wrong in a forked child): a forked child's main
  thread is one. The cost, measured on x86_64 Linux with the kernel's speculation mitigations on
  (~0.3 µs a syscall): 0.6–0.8 µs per libssl call. With the SIGPIPE hold (three more syscalls, see
  "SIGPIPE on the libssl backend") a 16-byte `tls_write` goes from 2.1 to 3.8 µs and a 16 KiB one
  from 7.3 to 9.0 µs; the native backend pays neither.
- `_tls_init` and the introspection-symbol resolution are 0 → 1 → 2 claim / publish latches (one
  caller resolves, the others wait), so a concurrent first use cannot read a half-resolved table.

## Escape hatch (non-contract)

`tls_dlsym(name)` resolves an arbitrary libssl/libcrypto symbol via the fdlopen-managed handle.
**It is soft-deprecated as of v5.10.13.**

- Each direct call binds the consumer to libssl's symbol name + ABI.
- It is libssl-only: it loads libssl through `_tls_init` whatever the active backend (main thread
  only — see "Thread safety"), and nothing it returns can be applied to a native handle. The typed
  verbs (`tls_set_alpn` / `tls_set_verify` / `tls_ctx_*` / `tls_get_alpn_selected` /
  `tls_get_peer_spki_der` / `tls_set_deadline`) work on **both** backends.
- The ALPN-read + SPKI-pin uses that previously needed `tls_dlsym` (`SSL_get0_alpn_selected`,
  `SSL_get1_peer_certificate` + `X509_get_pubkey` + `i2d_PUBKEY`) have typed verbs
  (`tls_get_alpn_selected` and `tls_get_peer_spki_der`, v6.0.82); sandhi 1.4.2 migrated onto them
  (v6.0.83). The trust-store and mTLS configuration it was still used for
  (`SSL_CTX_load_verify_locations` and the like) has typed verbs since v6.2.8 (`tls_ctx_*`).
- New consumer code that needs an unwrapped symbol SHOULD file a request for a new typed `tls_*`
  verb instead of calling `tls_dlsym` directly.

Returns the fn pointer (callable via `fncall*` from `lib/fnptr.cyr`) or 0 if `_tls_init` hasn't
succeeded or the symbol isn't in libssl/libcrypto.

## Stability guarantee

The verb names and signatures in the inventory tables above are stable. The
byte-identical-self-host requirement (CLAUDE.md §"Self-hosting is non-negotiable") includes this
surface: a change that breaks any of the documented return semantics or lifecycle invariants above
is a contract amendment — it amends this file in the same patch and says so in its CHANGELOG
entry.

Internal implementation details — the shim's layout (40 bytes on libssl: `SSL_CTX*`, `SSL*`,
socket, deadline, the sticky error; 40 bytes on native), the native ctx layout (`TLS_CTX_LEN`, 584 bytes at 6.6.14),
the `_fn_*` symbol cache, `_tls_libssl_handle`, the fdlopen bootstrap sequence — are NOT contract.
Stdlib maintainers may restructure them freely so long as the public behaviour above is preserved.

## Cross-reference

- Code: `lib/tls.cyr` (the dispatch layer and the libssl bridge), `lib/tls_native.cyr` (the
  native hub and its six `tls_native_*` modules), `lib/tls_hostid.cyr` (the shared host
  classifier).
- Per-verb reference: `docs/stdlib-reference.md` § `tls.cyr` and `tls_native.cyr`.
- Tests: `tests/tcyr/crypto/tls*.tcyr` (both backends; socketpair + fork against a native peer,
  OpenSSL interop where `openssl` is present), the cross-host set `tests/tcyr/crossos/tls_*.tcyr`
  (run on every release-gate host), and the gates `tests/gates/platform/tls_libssl_hostname_binding.sh`,
  `tests/gates/concurrency/tls_first_use_thread_race.sh` and
  `tests/gates/platform/agnos_tls_deadline.sh`.
- Heavy consumer: `lib/sandhi.cyr` (HTTPS client, session cache, 0-RTT retry).
- Filing trail: sandhi 2026-04-24 ALPN hook request →
  `sandhi/docs/issues/2026-04-24-stdlib-tls-alpn-hook.md` → cyrius v5.6.40 ALPN hook ship →
  v5.10.13 typed wrappers → v5.10.21 session + 0-RTT primitives → v5.10.27 staged connect →
  v5.10.34 early-data eligibility + acceptance probes → v5.10.42 (this contract doc) → v6.0.82
  typed introspection → v6.1.21 native default → v6.2.8 trust-store and mTLS verbs → v6.2.24 /
  v6.2.25 server verbs → 6.6.13 re-pin.
- Related CLAUDE.md sections: "Self-hosting is non-negotiable" + the doc-canonical-source rule
  (CHANGELOG = slot history; this file = durable invariant; state.md = current cycle only).
