# 2026-10-04 — the native TLS server decodes a PEM private key on every accept, on the global heap

**Status:** 🟡 **OPEN** — cyrius-side (stdlib `lib/tls_native_hs13.cyr` + sigil `pem_decode_privkey`).
**Filed in:** `sandhi/docs/development/issues/2026-10-04-cyrius-tls-server-pem-key-decoded-per-accept.md` (copied here 2026-10-04, unedited below this header).
**Placement:** **6.6.16** (2026-10-04, with the sandhi 1.10.7 fold).
**Severity:** **P3** — unbounded but slow heap growth in a long-running HTTPS server; no correctness or
security impact. A DER key avoids it entirely.
**Reporter:** sandhi (found while measuring the 1.10.7 pooled-TLS per-request arena fix).
**Toolchain:** cyrius 6.6.15 (sigil 3.13.9 in its snapshot).
**Affects:** every server that hands `tls_accept_alloc_in` (or `tls_accept_alloc`) a **PEM** key. In sandhi
that is `sandhi_server_run_tls` / `sandhi_server_run_pooled_tls` with a PEM key in
`sandhi_server_options_tls`.

## What happens

The server credentials are passed to the handshake on every accept. For each one:

1. `lib/tls.cyr:1214` calls `tls_native_server_load_creds(nctx)`.
2. `lib/tls_native_hs13.cyr:1221` (`_tn_load_privkey`) calls sigil's auto-detecting
   `pem_decode_privkey(key, key_len, kmat, 48, &ao)` for any key that is not raw DER.
3. `lib/sigil.cyr:20456` (`pem_decode_privkey`): `var pool = alloc(pem_len);` — from the **global** bump
   allocator, which never frees, and not from the arena the server passed to `tls_accept_alloc_in`.

So every TLS accept leaves `pem_len` bytes (rounded to 8) on the global heap.

## Measured (sandhi 1.10.7, cyrius 6.6.15)

`programs/_server_tls_probe.cyr` check [8] reads the server process's `alloc_used()` before and after 40
HTTPS requests to `sandhi_server_run_pooled_tls` with a per-request arena configured, so every sandhi-side
allocation is rewound:

- Ed25519 `key.pem` (119 bytes): **120 B per request**, all of it this decode.
- The same key as DER: **0 B per request**.

## Workaround (consumer side, today)

Pass the private key as DER (`openssl pkey -in key.pem -outform DER -out key.der`). The native loader takes
raw DER (0x30) without calling the PEM decoder.

## Proposed fix (cyrius-side)

Either:

- decode into the allocator the handshake was given (the per-connection arena that
  `tls_accept_alloc_in` already threads), so the bytes are reclaimed with the connection; or
- decode the key once per server credential set and reuse the DER, since the PEM never changes between
  accepts.

Post-fold note: sandhi composes `tls_accept_alloc_in` and does not decode keys itself (ADR 0001), so this
is not patched in sandhi; the guide (`docs/guides/server.md`, Options) recommends a DER key meanwhile.
