# Windows disallowed CTL: its 48-byte entries are not applied (identifier form unknown) — RESOLVED

> ✅ **RESOLVED in v6.7.14** (PL-10, `8e82ea45f` (the user's decision D57, 2026-10-16: "Apply now, marked unconfirmed"; ⚠ it ships labelled CONFIRMED, because the research confirmed the rule). Hashing the CCADB's 10,312 CA certificates in every form matched all six 48-byte entries as SHA-384(tbsCertificate) of the six DarkMatter intermediates QuoVadis issued in 2016-2017 (sha384WithRSA). That is crypt32's signature hash, prop 15. On cass, Windows' chain engine reports each `CERT_TRUST_IS_EXPLICIT_DISTRUST` (`0x04000005`) with both Disallowed stores empty. Each one's prop 15 equals its entry, and none of their key MD5s is listed. `_tn_w_ctl_copy` keeps the 48-byte entries, and the system set's trust policy (`_TN_POL_LEN` 64) carries them. `_tn_pol_der_denied` refuses a certificate anywhere in a path whose TBS SHA-384 is listed. Only sha384WithRSA / ecdsa-with-SHA384 certificates are hashed, and only while the list is non-empty, so POSIX pays nothing. The repro's split line on cass reads `CTL: 88 entries, 82 public-key MD5s + 6 SHA-384 TBS hashes applied, 0 of other lengths not applied` (was `6 of 48 bytes not applied`). Rows: `tests/tcyr/crossos/tls_system_trust_store.tcyr`, 221 on cass (was 192), 75 on Linux (was 55). They include `test_ctl_tbs_row` with DarkMatter Secure CA (2017) embedded (13); six microsoft.com chain-deny rows; a parity row (the library's hash equals crypt32's prop 15 for all 15 SHA-384-signed ROOT certificates); and four memory-store rows. Mutants a – c RED. Filed beside it: CTL signature-hash entries of other lengths (20 / 32 / 64 B, none today; 6.7.15). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on cass (Windows 10, CTL sequence 01dc1e14133124bf, ThisUpdate
2025-09-04) while fixing 2026-10-08-windows-trust-store-parity-gaps item 2 in the 6.7.12 windows lane (unit W3).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (platform lane, wave 1, unit P4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D57 — Apply now, marked unconfirmed.
**Severity:** Low — Windows only; the native client trusts up to six certificates (or keys) Windows' chain engine
distrusts. Fail-open in the "trusts more than Windows" direction, the same direction as before 6.7.12 for the whole
CTL.
**Affects:** 6.7.12 (the CTL is read from 6.7.12; before it no entry was applied).

## Summary

6.7.12 reads the auto-updated disallowed CTL (`HKLM\SOFTWARE\Microsoft\SystemCertificates\AuthRoot\AutoUpdate`,
value `DisallowedCertEncodedCtl`) and applies it to every certificate of a path (`lib/tls_native_hs12.cyr`,
`_tn_w_ctl_keys` / `_tn_w_ctl_copy`, the trust policy `_tn_pol_new`, `_tn_verify_chain`). The CTL's
`SubjectAlgorithm` is `1.3.6.1.4.1.311.10.11.15` (`szOID_DISALLOWED_HASH`, = `szOID_CERT_SIGNATURE_HASH_PROP_ID`),
and its identifiers are NOT certificate hashes:

- **16-byte entries (82 of 88 on cass): the MD5 of the certificate's subjectPublicKey** (the BIT STRING's key bytes,
  crypt32's `CERT_SUBJECT_PUBLIC_KEY_MD5_HASH_PROP_ID`, 25). Established against Windows itself: DigiNotar Root CA's
  prop 25 (`37392e833dc605dd7b38244739939ee3`) is a CTL entry, and `CertGetCertificateChain` reports DigiNotar
  `CERT_TRUST_IS_EXPLICIT_DISTRUST` (error status `0x4000025`) with the Disallowed store empty; the eleven Fina CA
  1.1.1.1 certificates of 2024-2025 (crt.sh ids 12116084225 … 20582951233, sha256WithRSA) match the same way. These
  ARE applied from 6.7.12.
- **48-byte entries (6 on cass): form unknown — NOT applied.** They match none of MD5 / SHA-1 / SHA-256 / SHA-384 /
  SHA-512 over the DER, the TBS, the SubjectPublicKeyInfo or the key bytes of any certificate tried (DigiNotar, the
  Fina set, cass's ROOT store). The leading hypothesis is the CTL's DECLARED identifier, the "signature hash"
  (prop 15) — measured on cass, prop 15 is the TBS hashed with the certificate's own signature digest (SHA-384 for
  12 roots → 48 bytes, SHA-256 for 11 → 32, SHA-1 for 1 → 20), so a 48-byte entry would be a SHA-384-signed
  certificate — but no distrusted certificate was found to confirm it, and `CertFindSubjectInCTL` (which uses
  prop 15) did not match DigiNotar, so the chain engine evidently checks prop 25 at least. Matching an unconfirmed
  rule was not shipped.

## Reproduction

On cass (C:\cyrius-tests), the entries and their lengths:

```
PS> $v = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\SystemCertificates\AuthRoot\AutoUpdate").DisallowedCertEncodedCtl
PS> [IO.File]::WriteAllBytes("dis.stl", $v); certutil -dump dis.stl
...
Subject Algorithm:
    Algorithm ObjectId: 1.3.6.1.4.1.311.10.11.15 disallowedHash
CTL Entries: 88
```

The six 48-byte identifiers (hex):

```
6e5ba5a2e61bd0d3831c2caa33ae7ce5c95e92abf0592ff8038ccdbc6b4be61d3718d1308fe489209d2b283ce4bf8e25
e0204e0f7ba06e1f75608be1bd6267c5e0b61364cc3b4e871f6210547d0bb836da996da1d5496b14b19b4b695eaf6a57
dc820ca48d97355f2802fd38413783c01d3c3b8d02aad00709e66d5b5bee7db02184e6ba2571941f9525f8ab68e93c6d
a1a13d594d27718794367ff3db7100403971f686857d11b811d0be96ba0cc0756a2d3e64aecfe6af08584488b6f96f34
e205022402a5a94315cb9d573bcea9d112f159a55f0c9d26ea79e087b4aa27513e6048b0088eec5e0fe60ac52dc53260
4fc605c322f76f4d655179db89629f3928c36d92b63f609bdd58294387986e121482541b3fc246ab9bfdc1d6e4fef7a3
```

`tests/tcyr/crossos/tls_system_trust_store.tcyr` prints the split on Windows:
`CTL: 88 entries, 82 public-key MD5s applied, 6 of 48 bytes not applied`.

## Root cause

The identifier rule for these entries is Windows-internal and undocumented; nothing on the verification hosts
or in public CT data tried here identifies a certificate behind any of the six.

## Proposed fix

Establish the rule against a certificate Windows distrusts through a 48-byte entry (find the certificate — e.g.
a recently distrusted SHA-384-signed CA or cross-certificate — and confirm `CertGetCertificateChain` reports
`CERT_TRUST_IS_EXPLICIT_DISTRUST` for it with the Disallowed store empty), then add that identifier kind to the trust
policy (`_tn_pol_der_denied`) and a row with that certificate. If the rule is prop 15 for SHA-384-signed
certificates, the verifier needs a SHA-384 over the TBS (sigil has one) keyed by the signature algorithm.
