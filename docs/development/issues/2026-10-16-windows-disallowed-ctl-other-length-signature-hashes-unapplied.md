# Windows disallowed CTL: a signature-hash entry of 20, 32 or 64 bytes is not applied — OPEN

**Status:** 🟡 **OPEN** — filed 2026-10-16 by the 6.7.14 platform lane (unit P4), while applying the CTL's
48-byte entries (issues/archived/2026-10-15-windows-disallowed-ctl-48-byte-entries.md, D57).
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — Windows only, and latent: today's CTL (cass and the public `disallowedcert.stl` of
2025-09-04, sequence 01dc1e14133124bf) holds no entry of these lengths. The day Microsoft lists a certificate
signed with SHA-1, SHA-256 or SHA-512 by its signature hash, the native client keeps trusting it while
Windows' chain engine refuses it — the same "trusts more than Windows" direction as the 48-byte entries
before 6.7.14.
**Affects:** 6.7.12 onward (`lib/tls_native_hs12.cyr`, `_tn_w_ctl_copy` / `_tn_w_ctl_take`).

## Summary

6.7.14 established, against Windows itself, what a disallowed-CTL identifier is: crypt32 matches an entry
against a certificate's public-key MD5 (prop 25, 16 bytes) and against its **signature hash** (prop 15,
`CERT_SIGNATURE_HASH_PROP_ID`): the tbsCertificate hashed with the certificate's OWN signature digest. On cass,
prop 15 is 20 bytes for a SHA-1-signed certificate (DigiNotar Root CA:
`00bbba38b51af4d816e03a4eb309140626879511`), 32 for SHA-256-signed, 48 for SHA-384-signed (the six DarkMatter
intermediates, each `CERT_TRUST_IS_EXPLICIT_DISTRUST`). The library applies the 16-byte and the 48-byte forms
only; `_tn_w_ctl_copy` drops every other length, and `_tn_tbs_sha384` hashes only SHA-384-signed certificates.

## Reproduction

A PE probe hands `_tn_w_ctl_copy` a CTL laid out as crypt32 lays it out, with one 32-byte and one 20-byte
entry (built with the 6.7.14 lane's tree, run under wine):

```
$ cat ctl32.cyr | ./build/cycc_win_cross > ctl32.exe && wine ctl32.exe; echo $?
entries 2 (32 B + 20 B): keys 0, sha-384 tbs 0, rc 0
0
```

Both entries are dropped: neither reaches the trust policy, so no certificate is refused by them.

## Root cause

D57 (the user, 2026-10-16) decided the 48-byte reading, the only form present in the CTL. The general rule —
an entry of length L is the signature hash of a certificate whose signature digest is L bytes long — was not
in that filing's surface.

## Proposed fix

Keep the CTL's 20 / 32 / 64-byte entries in the policy beside the 48-byte ones (or one list keyed by length),
and in `_tn_pol_der_denied` hash the TBS with the certificate's own signature digest (SHA-1 for
sha1WithRSA, SHA-256 for sha256WithRSA / ecdsa-with-SHA256, SHA-512 for sha512WithRSA / ecdsa-with-SHA512) when
a list of that length is non-empty. Rows: the memory-store and policy rows of
tests/tcyr/crossos/tls_system_trust_store.tcyr with a SHA-256-signed certificate's TBS SHA-256 listed (the
P-256 fixture), and the ROOT-store parity row extended to every prop-15 length (cass: 15 SHA-384, the rest
SHA-256 / SHA-1). A SHA-1 match can only distrust, so SHA-1's collisions cannot make anything trusted.
