# Windows trust store: ProtectedRoots flag 1 against a CurrentUser-added root has never been run end to end — RESOLVED

> ✅ **RESOLVED in v6.7.16** (wave 0, on main, 62d23c679; D27, the user, 2026-10-19: "Yes, this release"): flag 1 is measured end to end on cass, and crypt32 applies it at `CertOpenStore` as W3 reasoned, so the native loader needs no change. The user added a P-256 test root (serial `67160d27f1a90001`, issuing a serverAuth leaf) at cass's desktop, into Administrator's CurrentUser\Root through runas; a PE probe then ran `tls_native_set_ca_system` + `tls_native_client_verify_chain` + the hostname check offline, a fresh process per step: no policy — CurrentUser\ROOT 60 certificates, 48 exported, the leaf ACCEPTED (as Windows' user chain engine, `certutil -user -verify`, builds it); `Flags = 1` — 59 and 47, REFUSED `TLS_ERR_CERT_INVALID`; the policy removed — 60 and 48, ACCEPTED. The bundle control was ACCEPTED in every step, and the ProtectedRoots key was absent before and after. Recorded in docs/development/lib-tls-contract.md's Trust store row beside the 6.7.12 flag-8 figures — the acceptance's second option: no non-interactive session can add a CurrentUser root (`certutil -user -addstore` answers `ERROR_NOT_SUPPORTED` over ssh), so no opt-in row can set the case up. Docs only; no row. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found by the 6.7.12 windows lane's review (2026-10-15) of unit W3
(issues/archived/2026-10-08-windows-trust-store-parity-gaps.md, item 1). Nothing is known to be wrong; one shape of the filed
repro has never been executed.
**Placement:** 6.7.16 — Break 2, repair 6 (on main, run by the session with the user's cass desktop step — D27, "Yes, this release"; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D27 — Yes, this release.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D58 — measure flag 1 end to end (the filed acceptance), when the user can add the test root at cass's desktop: "can't update cass right now".
**Decision (user, 2026-10-18, at the 6.7.15 open):** not this release — the desktop steps are not available during 6.7.15.
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

## Measured (6.7.16, D27, 2026-10-19)

The user added the test root on cass's desktop. It went into `cassiopeia\administrator`'s CurrentUser\Root through
`runas … certutil -user -addstore`, because the ssh session runs as the built-in Administrator. The root is a P-256
test root, `CN=cyrius-pr6716-test-root`, serial `67160d27f1a90001`, SHA-1 `d8b18fdb…aa36`, and it issues a serverAuth
leaf for `pr6716.cyrius.test`.

Over ssh, a PE probe called `tls_native_new_client`, then `tls_native_set_ca_system`, then
`tls_native_client_verify_chain` and the hostname check, offline, in a fresh process per step:

| Step | Policy | CurrentUser\ROOT | Exported (serverAuth) | Verdict |
|---|---|---|---|---|
| A | none | 60 | 48 | **ACCEPTED** |
| B | `Flags = 1` | 59 (root dropped) | 47 | **REFUSED** `TLS_ERR_CERT_INVALID` |
| C | removed | 60 | 48 | **ACCEPTED** |

- **Control:** in every step, the leaf against `t.cer` as the only root (`tls_native_set_ca_bundle`) was ACCEPTED.
- **Baseline:** before the desktop step the store held 59 certificates and the verdict was REFUSED.
- **Windows' user engine:** in state A, `certutil -user -verify leaf.pem` builds the chain, with only revocation
  unknown.
- **The policy:** the ProtectedRoots key was absent before and is absent after.

The figures are recorded in `docs/development/lib-tls-contract.md`'s Trust store row, beside the flag-8 ones. That is
the acceptance's second option: no non-interactive session can add a CurrentUser root, so no opt-in row can set up
this case.
