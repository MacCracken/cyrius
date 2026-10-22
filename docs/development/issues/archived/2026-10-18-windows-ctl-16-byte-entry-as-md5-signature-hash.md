# Windows disallowed CTL: a 16-byte entry is read only as a public-key MD5, never as an MD2 / MD5-signed certificate's signature hash — RESOLVED

> ✅ **RESOLVED in v6.7.16** (PL-10, `07065368d`, and the docs fix PL-10r, `aba3ef544` — no decision of its own: the filing's fix, in 6.7.12's D9 direction; 6.7.16's D51 ("Keep" PL-14's every-length reading) was its ordering dependency. A 16-byte disallowed-CTL entry is applied under both readings: the public-key MD5 it was, and the signature hash of an md5WithRSA / md2WithRSA certificate (`_tn_tbs_sigalg`'s digest ids, `_tn_md5`, a new non-allocating `_tn_md2`). On real cass the library's hash equals crypt32's prop 15 for all six MD2 / MD5-signed ROOT roots, none listed (latent). The measurement the filing asked for is NOT closed: no read-only probe shows whether the chain engine compares a 16-byte entry with prop 15 (`CertFindSubjectInCTL` does not apply the CTL's algorithm, finding not even a listed 48-byte entry), so the reading is labelled unconfirmed, as the other lengths' are. Rows: `tls_system_trust_store.tcyr` — every target, RFC 1319's MD2 vectors and the Thawte / VeriSign PCA prop-15 rows (101 → 128); cass, the ROOT parity row counts the six as judged (`6 MD2 / MD5-signed (16 bytes), 0 not judged`, 274 → 301); seven mutants each RED. lib-tls-contract.md's Trust store row says so (PL-10r). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 platform lane (unit P5), measuring crypt32's signature
hash (prop 15) on cass's ROOT store while applying the CTL's 20 / 32 / 64-byte entries.
**Placement:** 6.7.16 — Break 2, repair 6 (platform lane, wave 1, unit P4; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — Windows only and latent (unmeasured whether crypt32 matches a 16-byte CTL entry against prop 15
at all). If it does, a certificate Microsoft lists by its MD5 (or MD2) signature hash — the TBS hashed with the
certificate's own md5WithRSA / md2WithRSA digest — is distrusted by Windows' chain engine and still trusted by the
native client (the "trusts more than Windows" direction 6.7.14 / 6.7.15 closed for the other lengths).
**Affects:** `lib/tls_native_hs12.cyr` — `_tn_w_ctl_copy` puts every 16-byte entry in the deny-KEY list (the MD5 of
a certificate's subjectPublicKey, crypt32's prop 25); `_tn_tbs_sigalg` answers 0 (not judged) for md2WithRSA /
md5WithRSA, so no 16-byte signature hash is ever computed.

## Measurement

A PE probe over cass's CurrentUser ROOT store (59 certificates; outer signatureAlgorithm OID → prop 15 length):

```
   1 2a864886f70d010102 16      md2WithRSAEncryption
   5 2a864886f70d010104 16      md5WithRSAEncryption
  22 2a864886f70d010105 20      sha1WithRSAEncryption
  16 2a864886f70d01010b 32      sha256WithRSAEncryption
  10 2a864886f70d01010c 48      sha384WithRSAEncryption
   5 2a8648ce3d040303   48      ecdsa-with-SHA384
```

So crypt32 HAS a 16-byte signature hash for MD2 / MD5-signed certificates, the same length as a public-key MD5:
a 16-byte CTL entry is ambiguous by length. Today's CTL (cass, and the public disallowedcert.stl of 2025-09-04) has
82 16-byte entries; 6.7.12 established them as public-key MD5s (DigiNotar Root CA, the eleven Fina 1.1.1.1
certificates). Whether crypt32 also tests them against prop 15 is not measured.

## What to measure / fix

On cass: add an MD5-signed test certificate's prop 15 value to a CTL built in memory (or measure which property
`CertFindCertificateInCTL` / the chain engine compares a 16-byte entry with) and see whether Windows distrusts it. If
it does, judge an md5WithRSA / md2WithRSA certificate by its 16-byte TBS hash against the same 16-byte list (the
library has `_tn_md5`; MD2 would need an implementation). Rows: the ROOT-store parity row in
tests/tcyr/crossos/tls_system_trust_store.tcyr then counts the 6 MD2 / MD5 roots as judged and equal to crypt32's.
