# 2026-05-22 — `lib/tls.cyr` native-TLS transport for the cyrius v6.0.x arc

**Status**: Open — substantially landed. Native transport
operational; sandhi runs over `tls_set_backend` since 1.4.2, with
the post-handshake ALPN-read + SPKI-pin `tls_dlsym` callers retired
onto typed wrappers. Remaining before close: typed wrappers for the
pre-handshake `SSL_CTX_*` mTLS / trust-store `tls_dlsym` sites.
**Filed**: sandhi side, against cyrius repo. Sit adoption of
sandhi is gated on this landing.
**Side**: Upstream (cyrius stdlib).
**Sandhi-side surface**: None. Per ADR 0001 and CLAUDE.md
("No FFI"), sandhi's hook-surface contract is unchanged across
any libssl-bridged → native transport swap. This filing exists
so the cross-repo coupling stays visible; the work itself is
purely cyrius-side.

## Why this matters now

`lib/tls.cyr` ships fdlopen-libssl-backed today and has done since
the 2026-04-24 pure-Cyrius-TLS removal. That was the right call at
the time — libssl's correctness is dependable, the
HTTPS-loop / pthread-deadlock / 7-arg-frame-segfault saga (see
`docs/issues/archive/`) cleared by v5.6.41, and sandhi's full
1.3.x TLS arc landed on top of the bridge: policy modes (0.6.0 +
0.9.3), session resumption (1.3.1), 0-RTT (1.3.2), cred-strip
keying (1.3.3), all green against real endpoints
(`programs/_policy_runtime_probe.cyr` ALL GATES PASS).

The 6.0.x cycle opened at cyrius 6.0.0 (2026-05-19) with the
`cc5 → cycc` / `cyrc → cybs` rename ceremony. Going forward, the
arc's character determines what downstream consumers can adopt:

- **sit** has stated it will only adopt sandhi *after* the TLS
  transport is native. Sit-adoption is sandhi's next
  roadmap-reshape trigger (per sandhi memory
  `project_sit_adoption_drives_roadmap`); 1.5.x scope surfaces
  from sit's real-workload friction.
- **AGNOS shipping shape** — fdlopen-libssl works on
  Linux/glibc hosts where libssl is present. Anything moving
  toward smaller-image / UEFI / minimal-stdlib targets needs
  the native path to stop pulling libssl as a runtime
  dependency.

This is the framing for a 6.0.x slot. No specific date — the arc's
own pacing decides — but the framing is that **the swap should
happen *somewhere* in 6.0.x**, not pushed past it.

## What sandhi needs from the swap (contract-only)

Sandhi calls `lib/tls.cyr` through a small set of typed wrappers
+ a `tls_dlsym`-based fallback for the remaining libssl-named
symbols. The contract for sandhi to keep working byte-identically
across the swap:

### Typed wrappers (must keep current shape + semantics)

| Wrapper | Shape | Used by |
|---|---|---|
| `tls_available()` | returns 1/0 | capability gate |
| `tls_connect_alloc(sock, host, hook_fp, hook_ctx)` | staged connect alloc | `_sandhi_conn_finalize_a` (1.3.1) |
| `tls_connect_complete(ctx)` | staged connect complete | same |
| `tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx)` | one-shot (back-compat wrapper) | pre-1.3.1 callers |
| `tls_set_alpn(ctx, protos, len)` | ALPN advertise | `_sandhi_alpn_hook` + `_sandhi_apply_hook` (1.3.0) |
| `tls_set_session(ctx, session)` | install session pre-handshake | session-cache lookup hit (1.3.1) |
| `tls_get_session(ctx)` | refcount-bumped capture | session-cache store (1.3.1) |
| `tls_session_free(session)` | caller-owned release | cache-replace (1.3.1) |
| `tls_supports_session_resumption()` | capability probe | 1.3.1 enable-gate |
| `tls_supports_early_data()` | capability probe | 1.3.2 enable-gate |
| `tls_ctx_set_max_early_data(ctx, max)` | 0-RTT advertise | (server-side, future) |
| `tls_write_early_data(ctx, buf, len)` | 0-RTT send | 1.3.2 client path |
| `tls_read_early_data(ctx, buf, len)` | 0-RTT recv | (server-side, future) |
| `tls_get_early_data_status(ctx)` | post-handshake status | 1.3.2 ACCEPTED/REJECTED/NOT_SENT |
| `tls_session_get_max_early_data(session)` | pre-attempt budget | 1.3.2 length gate |

Cross-swap requirement: **byte-identical observable semantics**.
A sandhi consumer that worked on the libssl-bridge must work on
the native transport with no behavior change. The return values,
the post-conditions, the error classification (per
`SANDHI_ERR_TLS`) — all the same.

### `tls_dlsym` callers (cyrius can either keep or replace)

Sandhi still reaches a few libssl symbols by name via
`tls_dlsym` from `src/tls_policy/apply.cyr` — now only the
pre-handshake `SSL_CTX_*` config set:

- `SSL_CTX_set_verify` / `SSL_CTX_set_verify_paths` /
  `SSL_CTX_load_verify_locations`
- `SSL_CTX_use_certificate_file` / `SSL_CTX_use_PrivateKey_file`

The post-handshake reads `SSL_get0_alpn_selected` and
`X509_get_pubkey` / `i2d_PUBKEY` were **retired at 1.4.2** onto the
typed, backend-agnostic `tls_get_alpn_selected` /
`tls_get_peer_spki_der` (option (a) below, applied to the ALPN/SPKI
half). The remaining set was left on dlsym at 1.3.0 because typed
wrappers didn't exist yet. For it, two viable shapes:

- **(a)** ship typed wrappers for these too, retire the dlsym
  callers in sandhi. Smallest cyrius-side delta, but means
  another sandhi slot to swap the callers.
- **(b)** keep `tls_dlsym` working in the native transport as a
  thin compatibility layer that maps the libssl symbol names
  to the equivalent native operations. Larger cyrius-side delta,
  but sandhi needs zero changes.

**Sandhi's preference: (a)**. Long-term it's cleaner to retire
the dlsym callers — the typed-wrapper surface is the
forward-facing API per the `lib/tls.cyr` soft-deprecation note
that landed with v5.10.13. Sandhi commits to the swap in the
slot following the native landing (will be a small 1.4.x slot
or rolls into 1.5.x — depends on timing).

### Hook surface (must preserve the timing windows)

Two hooks that 1.3.0 / 1.3.1 depend on:

1. **`hook_fp(hook_ctx, ssl_ctx)`** — fires on `SSL_CTX*` (or
   its native equivalent), pre-`SSL_new` (or native equivalent).
   Used for ALPN advertise, trust-store override, mTLS cert
   load. Currently invoked from `tls_connect_with_ctx_hook` and
   `tls_connect_alloc`.
2. **Staged connect timing window** — between `tls_connect_alloc`
   and `tls_connect_complete`, sandhi calls `tls_set_session` if
   a cached session exists. This window must exist in the native
   transport too. (The staged-connect filing
   [`archive/2026-05-09-stdlib-tls-staged-connect.md`](archive/2026-05-09-stdlib-tls-staged-connect.md)
   resolved at cyrius v5.10.27 with `tls_connect_alloc` /
   `tls_connect_complete`; the same timing-split must carry
   through the native swap.)

## Acceptance from sandhi side

The cyrius-side acceptance is: **sandhi's existing test suite +
live-network gate pass against the native transport with no
sandhi source change**.

- `cyrius test tests/sandhi.tcyr` — 440 green.
- `cyrius test tests/h2.tcyr` — 167 green.
- `cyrius test tests/alloc.tcyr` — 289+ green (1.4.0 will add
  more under `alloc/134/`).
- `cyrius test tests/rpc.tcyr` — 42 green.
- `programs/_policy_runtime_probe.cyr` — ALL GATES PASS
  against 1.1.1.1:443 / `one.one.one.one` SNI (default policy
  / wrong-SPKI fail-closed / non-existent trust-store soft
  warning).
- Live h2 via ALPN — `programs/h2-probe.cyr` (if available) or
  any TLS endpoint advertising `h2` end-to-end.
- 0-RTT — `tls_get_early_data_status` returns one of
  `NOT_SENT` / `ACCEPTED` / `REJECTED` with the same
  semantics the libssl bridge surfaces today.

Anything that fails on the native transport but passes on the
libssl bridge is a cyrius-side regression. Sandhi will
investigate from its side first (e.g. is sandhi making a
libssl-leaning assumption the contract allows?), but the
expectation is the contract holds across the swap.

## What sandhi does NOT need

- A specific TLS implementation choice. BearSSL / rustls-via-FFI
  / hand-rolled / something else — cyrius's call.
- A specific timeline within 6.0.x. The arc's own pacing
  decides; sandhi tracks the slot when it lands.
- Backward-compat aliases past the swap point. If the typed
  wrappers and timing windows hold, the swap is invisible.

## Why this is filed against cyrius, not embedded in sandhi

Per ADR 0001 (`sandhi composes, doesn't reimplement`), sandhi
never opens its own `dlopen` / `fdlopen` path. Whether the
underlying TLS is libssl-bridged or native is a stdlib
implementation detail. Earlier sandhi roadmap revisions framed
"native-transport prep" as a sandhi slot — that framing was
wrong, and the 1.2.0 closeout corrected it. The audit (if
needed) is a cyrius-side issue against `lib/tls.cyr`. This
filing makes the audit / swap formally cross-repo so the
coupling is tracked without sandhi claiming work it doesn't
own.

## Related

- [`archive/2026-05-09-stdlib-tls-staged-connect.md`](archive/2026-05-09-stdlib-tls-staged-connect.md)
  — staged-connect API; the timing-window split must carry
  through to the native transport.
- [`archive/2026-05-10-stdlib-tls-early-data-status.md`](archive/2026-05-10-stdlib-tls-early-data-status.md)
  — 0-RTT status accessors; the typed wrappers must preserve
  `NOT_SENT` / `ACCEPTED` / `REJECTED` semantics across swap.
- [`archive/2026-04-24-stdlib-tls-alpn-hook.md`](archive/2026-04-24-stdlib-tls-alpn-hook.md)
  — original hook surface ask; the `hook_fp(hook_ctx, ssl_ctx)`
  timing must hold.
- sandhi `CLAUDE.md` — "**No FFI.** Sandhi imports stdlib
  `lib/tls.cyr` (and other stdlib net primitives) and never
  opens its own dlopen / fdlopen path. Whether stdlib's
  `tls.cyr` is fdlopen-libssl-backed or native is a stdlib
  implementation detail; sandhi's surface is unchanged across
  any swap."
- sandhi `docs/development/roadmap.md` "Cross-repo dependencies"
  — the visibility entry that points here.
- sandhi memory `project_sit_adoption_drives_roadmap` — sit
  adoption is the next roadmap-reshape trigger; this filing
  is the prerequisite for that trigger to fire.

## Log

(append-only; close when the swap lands in 6.0.x)

- **2026-05-22** — filed at sandhi 1.3.5 close, on
  cyrius 6.0.1 pin. Surfaced from the sandhi 1.4.x roadmap
  reshape as the explicit cross-repo dependency for sit
  adoption. No cyrius-side activity yet — opens cleanly when
  the 6.0.x arc pulls it.
- **2026-06-07** — substantial progress. Cyrius's native-TLS
  Mini-arc E landed the sovereign native transport; sandhi 1.4.2
  rewired onto `tls_set_backend` and retired the post-handshake
  ALPN-read + SPKI-pin `tls_dlsym` callers onto typed
  `tls_get_alpn_selected` / `tls_get_peer_spki_der` (option (a),
  ALPN/SPKI half). sandhi 1.4.3 advanced the pin 6.0.82 → 6.0.87,
  picking up full TLS ciphersuite enablement + macOS native-TLS
  fixes (mechanical; no sandhi source change). Test suite (979)
  still green. Remaining before close: typed wrappers for the
  pre-handshake `SSL_CTX_*` mTLS / trust-store dlsym sites — then
  the sit-adoption gate can fire.
- **2026-06-14** — **sit-adoption gate cleared.** Native TLS has been
  the no-flag default since cyrius **6.1.21** / sandhi 1.4.9 (the
  `lib/tls.cyr` polarity flip), and 1.4.7 made TLS-policy enforcement
  backend-aware (native trust/mTLS fails closed rather than faulting).
  The native transport — the core of this filing and the explicit sit
  prerequisite — is fully operational; sit's adoption is no longer
  blocked on cyrius TLS. Sandhi 1.5.0 pins **6.2.6**. The one item still
  open against this filing is the **residual** part: typed native
  `SSL_CTX_*` equivalents so native trust-store / mTLS *enforce* (not
  just fail closed). That residual is tracked as a cross-repo dependency
  in [roadmap.md](../development/roadmap.md) ("Native TLS-policy
  enforcement"); this doc stays open until it lands, but it no longer
  gates downstream adoption.

## Resolution (cyrius 6.2.8, 2026-06-15)

CLOSED cyrius-side — the full residual ("typed native `SSL_CTX_*` equivalents so
native trust-store / mTLS enforce") shipped:

- **Typed wrappers** (`lib/tls.cyr`): `tls_ctx_load_verify_locations`,
  `tls_ctx_set_verify_paths`, `tls_ctx_use_certificate_file`,
  `tls_ctx_use_private_key_file` — backend-agnostic, return 1=success (matching
  sandhi `apply.cyr`'s `!= 1` checks). sandhi can now retire its remaining
  `tls_dlsym("SSL_CTX_*")` callers onto these (option (a)).
- **Trust-store ENFORCES on native** via the existing `tls_native_set_ca_bundle`
  / `set_ca_system` + chain-walk (was already present; now exposed typed).
- **mTLS client-auth implemented end-to-end on native**: new
  `tls_native_set_client_cert` / `set_client_key` + the TLS 1.3 client
  `Certificate` + `CertificateVerify` send path (`tls_native_client_finish`),
  and the server-side receive wired into `tls_native_accept`. ECDSA-P256/P384 +
  Ed25519 (RSA-PSS signing still awaits sigil). Validated by
  `tests/tcyr/tls_native_mtls_client.tcyr` (client↔server loopback, positive +
  strict-`FAIL_IF_NO_PEER_CERT`-rejects-no-cert) — 9/9.
- Adversarial security review: no auth-bypass, no AEAD nonce reuse, transcript
  ordering correct, byte-identical no-mTLS path.

Known limitation (tracked): the native **server** verifies the client
CertificateVerify *signature* (proof-of-possession), not the client cert's
chain-to-CA trust — documented at `tls_native_server_recv_client_certificate`.
sandhi's mTLS use case is client-side (unaffected). See CHANGELOG [6.2.8].
