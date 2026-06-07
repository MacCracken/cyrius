# `lib/tls.cyr` — hook-surface contract

Formal contract for the public surface of `lib/tls.cyr`. Pinned at
v5.10.42 after the surface stabilised across v5.6.40 (ALPN hook),
v5.10.13 (typed wrappers), v5.10.21 (session + 0-RTT), and v5.10.27
(staged connect for client-side resumption); ratified by sandhi 1.0.0
fold + 1.1.0 alloc migration + 1.3.x session + 0-RTT consumption.

This document is the **invariant layer**: changes to the per-fn
docstrings in `lib/tls.cyr` MUST preserve the guarantees listed here
unless the contract is explicitly amended in the same patch. Defensive
hardening / internal refactors should not change observable behavior
described below. Surface additions are allowed (new `tls_*` verbs) so
long as existing verbs keep their semantics.

## Provenance

- **Filing**: sandhi 1.1.x roadmap-cleanup pass, 2026-05-08.
- **Slot**: v5.10.42.
- **ADR alignment**: sandhi-side ADR-0001 ("sandhi composes,
  doesn't reimplement"). The TLS hook surface is the place where
  composition happens; this document is the cyrius-side guarantee
  that anchors it.

## Transport model

As of v6.0.x there are **two** transports behind one contract:

1. **libssl 3.x** loaded via `lib/fdlopen.cyr` — the **default** backend
   (see `lib/tls.cyr` header for the rationale — minimal `%fs` TCB stub
   deadlocks libssl's pthread init at first `SSL_CTX_new`).
2. **The sovereign native cyrius TLS stack** (`lib/tls_native.cyr`) — opt-in,
   selected by building with `-D CYRIUS_TLS_NATIVE`. No libssl/OpenSSL
   dependency; crypto + x509 are in-tree (sigil). Shipped across .74–.83
   (TLS 1.2 + 1.3, ECDSA P-256/P-384 + RSA + Ed25519, AES-128/256-GCM +
   ChaCha20, OS trust-store + SNI verification, live-Cloudflare-proven).

`lib/tls.cyr` dispatches on `_tls_backend`; the verb contract below is
identical for both. Consumers MUST treat the transport as **opaque**:

- All handles (`ctx`, `handle` in hooks, `session`) are integer
  pointers; consumers may store and pass them, but MUST NOT
  dereference or assume layout. The `ctx` struct layout is
  documented in `lib/tls.cyr` for stdlib maintainers, not consumers.
- The contract is honored by **both** backends — verb signatures and
  semantics survive a `tls_set_backend` switch; only the underlying
  pointer type changes.
- `tls_dlsym` (see "Escape hatch" below) is the one place where the
  contract leaks libssl ABI. It is soft-deprecated.

## Verb inventory (the contract surface)

### Availability probes

| Verb | Returns | Contract |
|------|---------|----------|
| `tls_available()` | 1 / 0 | Returns 1 once libssl has been successfully bootstrapped via fdlopen and the critical-symbol set has resolved. Idempotent; runs `_tls_init` lazily. Returns 0 forever within the process once init has failed (no retry). Safe to call before any other verb. |
| `tls_supports_session_resumption()` | 1 / 0 | Returns 1 iff the linked libssl exposes `SSL_get1_session` + `SSL_set_session` + `SSL_SESSION_free` + `SSL_CTX_set_session_cache_mode`. Probe BEFORE installing session callbacks. |
| `tls_supports_early_data()` | 1 / 0 | Returns 1 iff the linked libssl exposes the FULL 0-RTT client-correctness surface (write + read + max_early_data setter + get_early_data_status + SESSION_get_max_early_data). Probe BEFORE attempting any 0-RTT send/recv. |

### Connect — fused (legacy + ALPN-hook)

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_connect(sock, host)` | (i64, i64) → i64 | ctx or 0 | Thin wrapper over `tls_connect_with_ctx_hook(sock, host, 0, 0)`. Preserved verbatim for pre-v5.6.40 consumers; never gains new arguments. |
| `tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx)` | (i64, i64, fnptr, i64) → i64 | ctx or 0 | Fused alloc + complete with optional config hook. Hook fires post-stdlib-defaults, pre-`SSL_new`. Hook signature: `int hook_fp(hook_ctx, handle)`; non-zero return aborts connect (returns 0 and frees the partially-constructed handle). Pass `hook_fp == 0` to skip hook. |

**Stdlib-applied defaults BEFORE the hook fires** (consumers can
override inside the hook by re-calling the corresponding `tls_set_*`):

- System CA trust store loaded (`SSL_CTX_set_default_verify_paths`)
- Peer verification enabled (`SSL_CTX_set_verify(..., SSL_VERIFY_PEER, 0)`)
- SNI hostname set from `host` (post-`SSL_new`, before handshake)

### Connect — staged (resumption-aware)

The v5.10.27 staged-connect surface exists to inject a cached session
between `SSL_new` and `SSL_connect` — the timing window libssl
requires for client-side resumption.

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_connect_alloc(sock, host, hook_fp, hook_ctx)` | (i64, i64, fnptr, i64) → i64 | ctx-pre-handshake or 0 | Allocates SSL_CTX + SSL handle + binds fd + sets SNI + runs hook. Does NOT call `SSL_connect`. On success caller MUST follow with `tls_connect_complete` (handshake) OR `tls_close` (cleanup); the ctx owns kernel resources until then. Hook semantics identical to `tls_connect_with_ctx_hook`. |
| `tls_connect_complete(ctx)` | (i64) → i64 | 1 / 0 | Runs `SSL_connect` on a ctx from `tls_connect_alloc`. Returns 1 on handshake success; 0 on failure. **On failure the ctx is NOT freed** — caller MUST call `tls_close` to release (typically after inspecting error state). Returns 0 on null ctx without crash. |

### I/O

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_write(ctx, buf, len)` | (i64, i64, i64) → i64 | bytes-written or -1 | Calls `SSL_write`. Negative return is error (caller may probe `SSL_get_error` via `tls_dlsym` for now — typed wrapper pending). Returns -1 on null ctx without crash. |
| `tls_read(ctx, buf, maxlen)` | (i64, i64, i64) → i64 | bytes-read or -1 | Calls `SSL_read`. Negative return is error. Returns -1 on null ctx. |
| `tls_close(ctx)` | (i64) → i64 | 0 | Idempotent. No-op on null ctx. Calls `SSL_shutdown` if symbol resolved (best-effort); always frees SSL + SSL_CTX. Safe on both pre-handshake and post-handshake ctxs (libssl's `SSL_free` handles either state). |

### Hook-time configuration (typed wrappers)

These are the **only safe-across-transport-swap** ways to configure
the connection. Each replaces an earlier `tls_dlsym` + `fncall*` call
site. New consumers MUST use these in preference to `tls_dlsym`.

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_set_alpn(handle, protos, protos_len)` | (i64, i64, i64) → i64 | 0 / non-0 | Sets ALPN protocols. **`protos` is OpenSSL wire format**: each protocol length-prefixed (`\x02h2\x07http/1.1` advertises `h2 + http/1.1`). `protos_len` is total bytes. **Return convention inverted from most OpenSSL fns: 0 = success, non-zero = failure** (matches `SSL_CTX_set_alpn_protos` man page). Returns -1 on null handle or unresolved symbol. |
| `tls_set_verify(handle, mode, callback)` | (i64, i64, fnptr) → i64 | 0 / -1 | Overrides stdlib's default `SSL_VERIFY_PEER`. `mode` is an OpenSSL `SSL_VERIFY_*` flags bitmask. `callback == 0` disables the cb (mode-only override). 0 = success; -1 = null handle or unresolved symbol. |

### Session resumption

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_get_session(ctx)` | (i64) → i64 | session or 0 | Returns the post-handshake session pointer (refcount-bumped via `SSL_get1_session`). Caller OWNS the returned ref and MUST call `tls_session_free` when done. 0 means either ctx has no established session yet, libssl missing the symbol, or null ctx. Valid only between successful `tls_connect_complete` and `tls_close`. |
| `tls_set_session(ctx, session)` | (i64, i64) → i64 | 1 / 0 | Installs a previously-cached session. **MUST be called between `tls_connect_alloc` and `tls_connect_complete`** — installing post-handshake is a no-op. Does NOT take ownership of the session pointer; caller still owns the ref. Returns 0 on null ctx / null session / unresolved symbol. |
| `tls_session_free(session)` | (i64) → i64 | 0 | Releases one ref via `SSL_SESSION_free`. Idempotent on null. Safe to call when libssl missing the symbol (no-op). |

### Session cache callbacks (server-side or persistent client cache)

Three callbacks installed on the SSL_CTX (the `handle` arg from
inside the hook). Each is a thin `fncall2` over the libssl
`SSL_CTX_sess_set_*_cb` pair; no return-value translation.

| Verb | CB signature | Contract |
|------|--------------|----------|
| `tls_ctx_set_session_new_cb(handle, cb_fp)` | `int new_cb(SSL*, SSL_SESSION*)` | Fires when a handshake produces a session worth caching. **Return 1 to transfer ownership to the consumer** (consumer's cache impl owns the ref); 0 means libssl retains ownership. |
| `tls_ctx_set_session_remove_cb(handle, cb_fp)` | `void remove_cb(SSL_CTX*, SSL_SESSION*)` | Fires when libssl invalidates a session. Consumer's cache should evict matching entries. |
| `tls_ctx_set_session_get_cb(handle, cb_fp)` | `SSL_SESSION* get_cb(SSL*, unsigned char *id, int len, int *copy)` | Fires during handshake to fetch a cached session by id. **Set `*copy = 1` to bump refcount on the returned session; 0 to transfer ownership** to libssl. |
| `tls_ctx_set_session_cache_mode(handle, mode)` | — | Enables caching at the SSL_CTX level. `mode` ∈ `{SSL_SESS_CACHE_OFF, _CLIENT, _SERVER, _BOTH}`. Returns previous mode, or 0 if libssl missing the symbol. |

**Caveat — leaky abstraction**: The four cb signatures above are
literal libssl types. A future native-TLS transport would either need
to expose identical types in a compatibility shim, or break this
sub-surface explicitly (in which case the contract amendment would
ship in the slot that lands the swap). Consumers writing session
callbacks today are coupled to libssl's session-cache state machine;
this is acknowledged technical debt, not a current bug.

### 0-RTT (TLS 1.3 early data)

| Verb | Signature | Returns | Contract |
|------|-----------|---------|----------|
| `tls_ctx_set_max_early_data(handle, max)` | (i64, i64) → i64 | 1 / 0 | Server-side: max early-data byte budget per session. `max == 0` disables 0-RTT (libssl default). RFC 8446 recommends 16384 as a starting point; consumer cache impl should bound against replay-attack risk. Returns 0 if libssl missing the symbol. |
| `tls_write_early_data(ctx, buf, len)` | (i64, i64, i64) → i64 | bytes-written or -1 | Client-side write of 0-RTT payload BEFORE handshake completes. Valid only when `ctx` has a session installed via `tls_set_session` AND the session's server advertised acceptable 0-RTT (probe with `tls_session_get_max_early_data` first). -1 on error / null ctx / unresolved symbol. |
| `tls_read_early_data(ctx, buf, maxlen)` | (i64, i64, i64) → i64 | bytes / -2 / -1 | Server-side read of 0-RTT payload. **Three return states**: positive = bytes read into buf; -2 = early data exhausted, caller transitions to `tls_read` for the post-handshake stream (libssl `SSL_READ_EARLY_DATA_FINISH`); -1 = error or unresolved symbol. |
| `tls_get_early_data_status(ctx)` | (i64) → i64 | NOT_SENT / REJECTED / ACCEPTED | Client-side post-handshake check. Call AFTER `tls_connect_complete`. Returns one of `TLS_EARLY_DATA_NOT_SENT` (0; no early data attempted, OR null ctx, OR unresolved symbol — safe for consumers to treat as non-rejection), `TLS_EARLY_DATA_REJECTED` (1; server rejected — caller MUST resend over the normal stream via `tls_write`), `TLS_EARLY_DATA_ACCEPTED` (2; response is on the way via `tls_read`). |
| `tls_session_get_max_early_data(session)` | (i64) → i64 | byte budget or 0 | Pre-attempt eligibility probe. Returns the max early-data budget the cached session's server advertised at issue time. 0 means the session does NOT advertise 0-RTT support (don't attempt). 0 on null session / unresolved symbol — same semantic as "session doesn't advertise 0-RTT". |

## Lifecycle invariants

These ordering rules are part of the contract. Verbs called outside
their valid window have defined no-op behavior (return 0 or -1 per
table), but consumer logic SHOULD respect the windows.

```
                  tls_available()
                        |
                        v
       +----- tls_connect_alloc(sock, host, hook, ctx) -----+
       |                       |                            |
       |  hook fires here      |                            |
       |  (typed tls_set_*)    |                            |
       |                       v                            |
       |              [pre-handshake ctx]                   |
       |                       |                            |
       |              tls_set_session?    (resumption only) |
       |                       |                            |
       |                       v                            |
       |              tls_connect_complete  → 1             |
       |                       |              \             |
       |                       v               -> 0  ----+  |
       |               [connected ctx]                   |  |
       |                       |                         |  |
       |              tls_write / tls_read (repeated)    |  |
       |                       |                         |  |
       |              tls_get_session? (cache the ref)   |  |
       |                       |                         |  |
       |                       v                         |  |
       +-------------- tls_close(ctx) <------------------+--+
                          (idempotent;
                           releases SSL_CTX + SSL)
```

`tls_connect` / `tls_connect_with_ctx_hook` collapse alloc + complete
into one call. Consumers that don't need resumption use those; the
staged-connect API exists specifically for the resumption timing
window.

## Failure / partial-state contract

- **`tls_connect_alloc` returns 0** → all kernel resources released
  internally before return. Caller does NOTHING (no `tls_close`).
- **`tls_connect_complete` returns 0** → caller still owns ctx, MUST
  call `tls_close`. Inspecting error state (via `SSL_get_error` for
  now, see escape hatch) is the typical interleave.
- **`tls_close` on already-freed ctx** → undefined; do not call twice.
  No double-free guard. Consumer-side state machine must track ctx
  liveness.
- **`tls_close` on null ctx** → returns 0, no-op.
- **`tls_get_session` between alloc and complete** → returns 0 (no
  established session). Safe to call defensively.
- **`tls_*_early_data` when `tls_supports_early_data() == 0`** →
  returns the documented error sentinel (-1 / -2 / 0 / NOT_SENT) per
  table above. Consumers MUST probe `tls_supports_early_data` before
  attempting an early-data flow.

## Escape hatch (non-contract)

`tls_dlsym(name)` resolves an arbitrary libssl/libcrypto symbol via
the fdlopen-managed handle. **It is soft-deprecated as of v5.10.13.**

- Each direct call binds the consumer to libssl's symbol name + ABI.
- Each direct call only works on the libssl backend; it is a no-op /
  unavailable under `CYRIUS_TLS_NATIVE`. The typed wrappers
  (`tls_set_alpn` / `tls_set_verify` / `tls_get_alpn_selected` /
  `tls_get_peer_spki_der`) work on **both** backends.
- The ALPN-read + SPKI-pin uses that previously needed `tls_dlsym`
  (`SSL_get0_alpn_selected`, `SSL_get1_peer_certificate` +
  `X509_get_pubkey` + `i2d_PUBKEY`) now have typed verbs
  (`tls_get_alpn_selected` @ v6.0.82, `tls_get_peer_spki_der` @ v6.0.82);
  sandhi 1.4.2 migrated onto them (v6.0.83). The remaining `tls_dlsym`
  sites in the ecosystem are the libssl-only mTLS / trust-store config
  fns (`SSL_CTX_load_verify_locations` etc.).
- New consumer code that needs an unwrapped symbol SHOULD file a
  request for a new typed `tls_*` verb instead of calling
  `tls_dlsym` directly.

Returns the fn pointer (callable via `fncall*` from `lib/fnptr.cyr`)
or 0 if `_tls_init` hasn't succeeded or the symbol isn't in
libssl/libcrypto.

## Stability guarantee

The verb names and signatures in the inventory tables above are
stable. The byte-identical-self-host requirement (CLAUDE.md §"Self-
hosting is non-negotiable") includes this surface: a change that
breaks any of the documented return semantics or lifecycle invariants
above is a contract amendment and ships as its own slot with the
amendment described in the CHANGELOG entry.

Internal implementation details — the 24-byte `ctx` struct layout,
the `_fn_*` symbol cache, `_tls_libssl_handle`, the fdlopen
bootstrap sequence — are NOT contract. Stdlib maintainers may
restructure these freely so long as the public behavior table above
is preserved.

## Cross-reference

- Code: `lib/tls.cyr` (~905 LOC at v6.0.83, after the native re-backing) +
  `lib/tls_native.cyr` (the sovereign native backend).
- Heavy consumer: `lib/sandhi.cyr` (HTTPS client, session cache,
  0-RTT retry).
- Filing trail: sandhi 2026-04-24 ALPN hook request →
  `sandhi/docs/issues/2026-04-24-stdlib-tls-alpn-hook.md` →
  cyrius v5.6.40 ALPN hook ship → v5.10.13 typed wrappers →
  v5.10.21 session + 0-RTT primitives → v5.10.27 staged connect →
  v5.10.34 early-data eligibility + acceptance probes →
  v5.10.42 (this contract doc).
- Related CLAUDE.md sections: "Self-hosting is non-negotiable" + the
  doc-canonical-source rule (CHANGELOG = slot history; this file =
  durable invariant; state.md = current cycle only).
