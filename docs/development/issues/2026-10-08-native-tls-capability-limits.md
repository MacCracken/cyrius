# Native TLS capability limits: no RSA client/server keys, leaf-only Certificate, empty certificate_authorities, 8 KiB one-record client Certificate (1.3), no libssl `tls_set_groups`, no X448 / secp521r1 — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: an RSA-2048 PKCS#8 key is refused by
`tls_native_set_client_key` with `-21` (`TLS_ERR_KEY_UNSUPPORTED`, live run); items 2–6 by reading the live code
(pointers below). One premise in the tree is STALE: the comments blame sigil for RSA, but sigil now ships the
signers (`rsa_privkey_from_der`, `rsa_pss_sign_sha256/384`, `rsa_pkcs1v15_sign_sha256/384`) — the RSA gap is
cyrius's TLS wiring.
**Placement:** open by design — a feature / arc, not a bug: roadmap_6.md § *Native TLS capability arc* (items 1–5) and roadmap-future.md (item 6) (placed 2026-10-09) — never 7.x.
**Discovered:** 6.6.14, CYRIUS-2026-0019's *Not covered* (`docs/audit/2026-09-03-security-audit.md:1295`); filed
2026-10-08 from roadmap.md.
**Severity:** Medium — hard interop failures (an RSA client identity; a client leaf issued by an intermediate the
server does not hold) with a workaround only where the libssl backend runs (x86_64 Linux).
**Affects:** cycc 6.2.8 (native mTLS) – 6.7.6.

## Summary

None of these is a security defect (CYRIUS-2026-0019's fix stands); each is a capability the native stack lacks:

1. **No RSA private keys.** `_tn_load_privkey` returns `TLS_ERR_KEY_UNSUPPORTED` for `SIG_PRIVKEY_RSA`
   (`lib/tls_native_hs13.cyr:1354`) and the shared signer `_tn_sign` refuses RSA (`:2153`; its comment says "no
   key, or RSA"). So a native client cannot present an RSA client certificate, and a
   native server cannot run on an RSA certificate (`tls_native_new_server` only stores refs; its credential load,
   `tls_native_server_load_creds`, goes through the same `_tn_load_privkey` — by code reading). The 1.3 / 1.2 CertificateRequest builders offer only
   ECDSA P-256 / P-384 and Ed25519 (`lib/tls_native_hs13.cyr:2325`, `lib/tls_native_hs12.cyr:819`).
   Stale comments to correct with the fix: `lib/tls_native_hs12.cyr:2654` ("RSA-PSS signing is not yet wired in
   sigil") and `lib/tls_native_hs13.cyr:473` ("P-384 + RSA are sigil gaps").
2. **Leaf only.** Both Certificate builders emit a single entry: 1.3 `_tn_build_certificate`
   (`lib/tls_native_hs13.cyr:2105`, "a single-entry certificate_list") and 1.2 `_tn_build_certificate_12`
   (`lib/tls_native_hs12.cyr:579`, "Single-leaf scope"); `tls_native_set_client_cert` keeps one certificate
   (`lib/tls_native_hs12.cyr:2625`). A peer that holds only the root cannot build a path to a leaf issued by an
   intermediate.
3. **Empty certificate_authorities.** The 1.2 CertificateRequest writes it empty (`lib/tls_native_hs12.cyr:831`);
   the 1.3 one carries no `certificate_authorities` extension (`lib/tls_native_hs13.cyr:2325-2343`). A client
   holding several certificates cannot pick by issuer.
4. **1.3 server: one record per client message, Certificate ≤ 8 KiB.** `lib/tls_native_conn.cyr:1298-1305` reads
   ONE record and opens it into an 8,192-byte buffer; a client Certificate split across records, coalesced with
   CertificateVerify, or over 8 KiB fails. (The 1.2 server reassembles up to 16 KiB — `lib/tls_native_hs12.cyr:1736`.)
5. **No libssl-backend `tls_set_groups`.** The native `tls_native_set_groups` exists since 6.6.15
   (`lib/tls_native_ctx.cyr:279`); `lib/tls.cyr` has no group-setting entry for the libssl backend
   (`grep -n set_groups lib/tls.cyr` is empty).
6. **No X448 / secp521r1 key exchange.** `tls_native_set_groups` accepts x25519 / P-256 / P-384 only; sigil has
   neither ECDH (`grep -ni "x448\|p521\|secp521" lib/sigil.cyr` is empty).

## Reproduction

Item 1, live (from the repo root, in an empty scratch dir `<d>`):

```sh
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out <d>/rsa.pem
openssl pkey -in <d>/rsa.pem -outform DER -out <d>/rsa.der
```

```
#define CYRIUS_TLS_NATIVE
include "lib/fdlopen.cyr"
include "lib/str.cyr"
include "lib/chrono.cyr"
include "lib/random.cyr"
include "lib/dynlib.cyr"
include "lib/tls_native.cyr"
include "lib/tls.cyr"
include "lib/io.cyr"
fn main(): i64 {
    alloc_init();
    var len = 0;
    var der = file_read_whole("rsa.der", &len);
    var ctx = tls_native_new_client("127.0.0.1", 9);
    print_num(tls_native_set_client_key(ctx, der, len));
    return 0;
}
var r = main();
syscall(60, r);
```

`cat k.cyr | build/cycc > <d>/k && (cd <d> && ./k)` prints `-21`. Expected: `0` (TLS_OK) — an RSA-2048 key is the
most common client identity.

Items 2–6: read the cited lines; a wire repro for 2 / 4 is `openssl s_server -Verify 1` with a CA file holding only
the root, against a native client whose leaf comes from an intermediate (needs a 3-level test PKI; not built here).

## Root cause

As listed per item. Items 1 and 6 need crypto plumbing (1: sigil already has it), 2 and 3 need ctx storage for a
chain and a CA-name list, 4 needs handshake-message reassembly on the 1.3 server's client-auth path.

## Proposed fix

1. Route `SIG_PRIVKEY_RSA` through `rsa_privkey_from_der` + `rsa_pss_sign_sha256/384` (1.3 CertificateVerify,
   rsa_pss_rsae_*) and PKCS#1 v1.5 where 1.2 allows it; offer the RSA schemes in both CertificateRequests.
   ⚠ Check sigil's RSA signer is constant-time / blinded before wiring it to a network-reachable server key
   (`_rsa_raw_sign` says "blinded/CRT").
2. Let `tls_native_set_client_cert` / `tls_native_new_server` keep every PEM block as the chain and emit them in order.
3. Emit `certificate_authorities` from the server's trust set (1.3 extension; the 1.2 field).
4. Reassemble the client's second flight across records (the 1.2 server's 16 KiB path is the model).
5. A libssl `SSL_set1_groups` route behind `tls_set_groups`.
6. Only if sigil gains constant-time X448 / P-521 ECDH (that is sigil work first — fix the source repo).
