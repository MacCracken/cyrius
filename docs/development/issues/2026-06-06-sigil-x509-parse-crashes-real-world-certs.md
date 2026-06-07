# sigil `x509_parse` crashes / fails on real-world server certs (CT SCTs leaf → SIGSEGV) — blocks native-TLS real-peer verification

- **Filed**: 2026-06-06 (cycc 6.0.78, sigil 3.7.3 vendored)
- **Reporter**: the `.78` Mini-arc E bite-3 dev-check — verifying a live Cloudflare chain
  (`one.one.one.one:443`) offline against the OS trust store.
- **Affects**: `lib/sigil.cyr` → **`x509_parse`** on real-world end-entity + intermediate certs. The
  native TLS trust-store mechanism (`tls_native_set_ca_bundle` / `_set_ca_system` /
  `_client_verify_chain`, shipped `.78`) is correct, but it relies on `x509_parse`, so this blocks
  verifying any real public server.
- **Severity**: **HIGH** — a SIGSEGV in `x509_parse` driven by an **untrusted TLS server certificate**.
  A malicious or buggy server can crash the native-TLS client (DoS), and the crash is in DER parsing of
  attacker-controlled bytes. Also a hard **blocker for Mini-arc E Release B** (the live
  `one.one.one.one:443` real-peer smoke) and for any sovereign HTTPS consumer (sandhi).

## Evidence (offline, against a freshly-fetched Cloudflare chain)

`openssl s_client -connect one.one.one.one:443 -showcerts` → leaf (1413 B, **carries CT Precertificate
SCTs**) + SSL.com intermediate (894 B). Fed as DER to `x509_parse`:

| Cert | `x509_parse` result |
|---|---|
| OS trust store (~150 root CAs, via `set_ca_system` → `pem_decode_certs`) | ✅ all parse |
| SSL.com **intermediate** (894 B, no SCTs) | ⚠️ **returns 0** (parse failure, no crash) |
| Cloudflare **leaf** (1413 B, **CT SCTs**) | 🔴 **SIGSEGV (139)** |

So root CAs parse, but a real **leaf** (end-entity, with the embedded SCT extension that ~every modern
public cert carries) **crashes**, and at least one real intermediate **fails to parse**. The crash is
isolated to `x509_parse` itself — `set_ca_system` (which parses ~150 system certs) succeeds, and the
crash reproduces with the leaf alone.

## Suspected cause

The Cloudflare leaf's distinguishing feature is the **CT Precertificate SCTs** extension (OID
`1.3.6.1.4.1.11129.2.4.2`) — a large, structurally-unusual `OCTET STRING`-wrapped SCT list. A fixed-size
extension buffer or an unchecked length in the extension walk is the likely culprit (sigil's x509 cert
struct uses fixed regions, e.g. `var extra[256]` at `lib/sigil.cyr:4574`). The intermediate's clean
**0**-return (vs crash) suggests a separate, milder strictness gap.

## Impact on Mini-arc E

- **Release A (`.78`)**: NOT blocked — close_notify, ALPN, and the trust-store *mechanism* are all
  hermetically testable with sigil-generated test certs (cert23) and ship fine.
- **Release B**: **blocked** — the live real-peer smoke + sandhi HTTPS cannot parse real server certs
  until this is fixed. Must be resolved (in the sigil repo, then re-folded) before Release B's
  `one.one.one.one:443` gate can go green.

## Next steps

1. Reproduce in the **sigil repo** (`~/Repos/sigil`, currently 3.7.3) with the Cloudflare leaf DER;
   pin the faulting site in `x509_parse`'s extension/SCT handling (lldb or bisect).
2. Fix in sigil (bounds-check the SCT/extension parse; tolerate or skip unknown large extensions), add
   a real-cert corpus to sigil's x509 tests, re-fold into `lib/sigil.cyr` (a stdlib dep bump — leader
   signal).
3. Then unblock Release B (real-peer smoke + sandhi).
