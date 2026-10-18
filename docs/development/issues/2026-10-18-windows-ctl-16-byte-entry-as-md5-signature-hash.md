# Windows disallowed CTL: a 16-byte entry is read only as a public-key MD5, never as an MD2 / MD5-signed certificate's signature hash — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 platform lane (unit P5), measuring crypt32's signature
hash (prop 15) on cass's ROOT store while applying the CTL's 20 / 32 / 64-byte entries.
**Placement:** unplaced — filed from the 6.7.15 platform lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
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
