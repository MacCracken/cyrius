# Native TLS chain-verification authn gaps — CVE-17/18

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../../audit/2026-06-10-deep-dive-review.md))
**Severity:** High
**Affects:** cycc / `lib/tls_native.cyr` + `lib/sigil.cyr` 6.1.31. Native TLS is
the **default** backend since v6.1.21 (libssl is opt-out via `-D CYRIUS_TLS_LIBSSL`)
and is slated to go public at ~v7, so these are sovereignty + public-release gates.

## CVE-17 — chain validation ignores pathLen / EKU / keyUsage / revocation (P1)

`tls_native_client_verify_chain`'s path-build loop (`tls_native.cyr:4829-4863`)
tests only `x509_cert_is_ca` + `_x509_in_window` + `_x509_verify_link` per link.
Gaps (authn-bypass class):

- **pathLenConstraint** is fully parsed into the cert struct
  (`sigil.cyr:9942`, accessor `x509_cert_path_len@9465`) but has **zero callers**
  in `tls_native.cyr` — an intermediate with `pathLen=0` can over-issue depth and
  verify clean (RFC 5280 §6.1.4 violation).
- **keyUsage** is parsed but explicitly not enforced (`sigil.cyr:9948-9951`) —
  CA links aren't required to carry `keyCertSign`, nor the leaf `digitalSignature`.
- **EKU** (`id-kp-serverAuth`, OID 2.5.29.37 / `551d25`) is absent from the OID
  table entirely — a leaf with no `serverAuth` EKU (e.g. a code-signing or client
  cert from the same CA) is accepted for a TLS server identity.
- **No revocation** anywhere — zero OCSP/CRL references in `tls_native.cyr`/
  `tls.cyr`; a revoked-but-in-window leaf verifies clean (`verify_chain` checks
  only validity window + signature + CA bit, `:4816-4864`).

**Fix:** track remaining pathLen while ascending and reject when exceeded;
require `keyCertSign` on CA links and `digitalSignature` on the leaf; parse EKU
(new OID + parse) and require `id-kp-serverAuth` (or anyEKU) on the leaf. Data
for pathLen/keyUsage is already parsed; only EKU needs new code. Decide a
revocation policy (OCSP-stapling consumption, or a documented short-lived-cert
posture) before v7.

## CVE-18 — CONNECTED-but-UNVERIFIED context by default; hostname skipped when host==0 (P1)

`tls_native_connect` (`tls_native.cyr:5058-5101`) completes the handshake and
returns `TLS_OK` with **no** chain or hostname verification. A direct consumer
— or the documented bare-metal/AGNOS path that *cannot* use the libssl wrapper —
gets a fully-keyed channel to an unauthenticated peer unless it separately calls
`verify_chain` + `verify_hostname`. Only the `tls.cyr` wrapper enforces them
(`_tls_native_complete`, `tls.cyr:306-310`), and even there **hostname binding
is skipped entirely when `host==0`** (`tls.cyr:308`) — connecting by IP / with
no SNI accepts any CA-valid cert.

**Fix:** make `tls_native_connect` verify by default (verify unless
`TLS_VERIFY_NONE`), or rename/guard it so the unverified path is explicit; treat
`host==0` with `verify != NONE` as an error, not a silent skip; surface an error
when `tls_set_verify` is handed a callback the native backend can't honor.

## Proposed fix

One TLS-hardening release: EKU/keyUsage/pathLen enforcement in `verify_chain`,
verify-by-default in `tls_native_connect`, `host==0` made an error, plus a
revocation-policy decision recorded in `lib-tls-contract.md`. Add negative tcyr
vectors (over-long chain, wrong-EKU leaf, expired-but-in-window-revoked stand-in,
IP connect with verify on). Pairs with the fuzzing ask in
[verification-coverage-gaps](2026-06-10-verification-coverage-gaps.md).

## Status

Filed 2026-06-10. v7-public prerequisite; recommended for the v6.2.x hardening
band (budget freed by the phantom TLS arc — see
[roadmap-drift-and-stale-docs](2026-06-10-roadmap-drift-and-stale-docs.md)).
