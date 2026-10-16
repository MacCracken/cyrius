# Windows trust store: ProtectedRoots flag 1 against a CurrentUser-added root has never been run end to end — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.12 windows lane's review (2026-10-15) of unit W3
(issues/archived/2026-10-08-windows-trust-store-parity-gaps.md, item 1). Nothing is known to be wrong; one shape of the filed
repro has never been executed.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (windows lane; filed from the 6.7.12 windows lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Severity:** Low — Windows only, a verification gap: if crypt32 did NOT apply flag 1 at `CertOpenStore`, the native
client would trust a CurrentUser-added root that Windows' own chain engine refuses under the policy.
**Affects:** `lib/tls_native_hs12.cyr` (the Windows root loader, `CertOpenStore(CurrentUser\ROOT)`), 6.7.12.

## Summary

W3 concluded that the native loader needs no ProtectedRoots code: crypt32 applies the policy itself when the loader
opens the logical `CurrentUser\ROOT` store, reading it ONLY from
`HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\Root\ProtectedRoots`. The evidence is flag **8**, measured on
cass as administrator (each flip reverted at once): `Flags = 8` took `CurrentUser\ROOT` from 59 roots to 12 at the
next open (the library's own export 47 -> 7), and the same value under the non-Policies key changed nothing. For flag
**1** (`CERT_PROT_ROOT_DISABLE_CURRENT_USER_FLAG` — inhibits the CurrentUser `.Default` physical store) the evidence
is wincrypt.h's own description, which says the same mechanism applies it. The filed repro's step 1 — a test root
added to the CURRENT USER's store, then `Flags = 1`, then the native client must refuse a leaf it issues — was never
run, so flag 1 is reasoned, not measured.

## Why it was not run

- `certutil -user -addstore Root t.cer` from any non-interactive session on cass fails
  `0x80070032 ERROR_NOT_SUPPORTED` — over ssh as administrator, and as SYSTEM through a one-shot scheduled task.
- A certificate written straight into `HKCU\SOFTWARE\Microsoft\SystemCertificates\Root\Certificates\<sha1>` is
  purged by Windows at the next store open.
- The opt-in row in `tests/tcyr/crossos/tls_system_trust_store.tcyr` (`CYRIUS_TLS_TEST_PROTECTED_ROOTS=1`,
  administrator) covers `Flags = 8` only (cass: 47 -> 7 -> 47).

## Reproduction (needs an interactive desktop session on cass, or another way to add a CurrentUser root)

```
REM in an interactive desktop session, as the test user
certutil -user -addstore Root t.cer
REM as administrator
reg add HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\Root\ProtectedRoots /v Flags /t REG_DWORD /d 1 /f
REM run a native-TLS probe that verifies a leaf issued by t.cer against tls_native_set_ca_system
REM expected: TLS_ERR_CERT_INVALID (the CurrentUser root is inhibited); then delete the Flags value
reg delete HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\Root\ProtectedRoots /f
certutil -user -delstore Root <serial>
```

## Acceptance

Flag 1 measured end to end on real Windows (refused under the policy, accepted without it), and either an opt-in
row in `tests/tcyr/crossos/tls_system_trust_store.tcyr` that pins it, or the measurement recorded in
`docs/development/lib-tls-contract.md`'s Trust store row beside the flag-8 figures.
