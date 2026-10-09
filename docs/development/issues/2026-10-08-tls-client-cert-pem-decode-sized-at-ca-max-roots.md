# `tls_native_set_client_cert` sizes its PEM decode at `TLS_CA_MAX_ROOTS` (300), not from the input — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b with
`repros/2026-10-08-tls-client-cert-pem-scratch.cyr`: a one-block client PEM allocates a 4,800-byte table
(6,152 B in all), and a well-formed leaf followed by 300 more blocks is refused `-6` (`TLS_ERR_CERT_INVALID`).
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.6.14, when `_tn_ca_parse_set` moved to `pem_count_cert_blocks` sizing and left this the last user
of `TLS_CA_MAX_ROOTS` (its comment, `lib/tls_native_hs12.cyr:1987-1988`); filed 2026-10-08 from roadmap.md.
**Severity:** Low — a fixed over-allocation per call, and a spurious refusal only for a pathological (> 300 block)
client PEM.
**Affects:** cycc 6.2.8 (the PEM path of `tls_native_set_client_cert`) – 6.7.6.

## Summary

`tls_native_set_client_cert(ctx, cert, len, 0)` decodes a PEM to take its first block as the client's leaf. It
allocates the decode table as `TLS_CA_MAX_ROOTS * 16` bytes — a trust-bundle cap that has nothing to do with a
client certificate file — and passes `TLS_CA_MAX_ROOTS` as `max_certs` to sigil's STRICT
`pem_decode_certs_into`, which returns -1 when one more well-formed block exists than `max_certs`. So the cost is
4,800 B whatever the input holds, and a PEM with 301+ blocks is reported as an invalid chain although its leaf is
fine. `TLS_CA_MAX_ROOTS` is also a writable public `var`, so a program that lowers it to 0 breaks every PEM
client certificate (`max_certs <= 0` → -1).

## Reproduction

See the header of `docs/development/issues/repros/2026-10-08-tls-client-cert-pem-scratch.cyr` (it builds
`one.pem` / `c300.pem` / `c301.pem` from the Ed25519 leaf in `tests/tcyr/crypto/tls_native_mtls_client.tcyr`).

```
one.pem rc=0 pem_bytes=489 alloc_bytes=6152
c300.pem rc=0 pem_bytes=146700 alloc_bytes=151776
c301.pem rc=-6 pem_bytes=147189 alloc_bytes=151992
```

Expected: the table sized to the input (16 B for one block), and the 301-block file accepted (its leaf is the
same well-formed certificate).

## Root cause

`lib/tls_native_hs12.cyr:2634` `var chain = _tn_alloc(ctx, TLS_CA_MAX_ROOTS * 16);` and `:2638`
`pem_decode_certs_into(cert, cert_len, chain, TLS_CA_MAX_ROOTS, pool, cert_len)`; `TLS_CA_MAX_ROOTS` is
`var … = 300` at `:1989`. sigil's strict decode refuses on `count >= max_certs` with another BEGIN pending
(`lib/sigil.cyr` `pem_decode_certs_into`, the `if (count >= max_certs) { return 0 - 1; }` line).

## Proposed fix

Size it as `_tn_ca_parse_set` does (`lib/tls_native_hs12.cyr:2023-2025`): `blocks = pem_count_cert_blocks(cert,
cert_len)`, refuse `blocks < 1`, allocate `blocks * 16`, pass `blocks` as `max_certs` — the strict decode stays
(a bad first block must fail, not hand back the next certificate; CHANGELOG [6.6.14]). `TLS_CA_MAX_ROOTS` then has
no reader left: retiring the public name is the user's call (`removed_symbol_census.sh`).
