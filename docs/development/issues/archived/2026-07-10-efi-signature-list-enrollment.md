# EFI_SIGNATURE_LIST enrollment generation (arc #3 residual B)

**Filed:** 2026-07-10 (roadmap arc #3 bite-1 closeout)
**Status:** FOLLOW-ON — bounded, sigil-side. NOT a release-blocker.
**Priority:** low. The arc's primary deliverable — *signing* EFI binaries for Secure
Boot (`cyrius sign-efi`) — shipped in v6.4.47. This is the *enrollment* half.

## Gap

Arc #3 (UEFI Secure Boot signing) split into:
- **(A) signing** — `cyrius sign-efi` (sovereign `sbsign`). **✅ SHIPPED v6.4.47**, de-risked
  against a real gnoboot `BOOTX64.EFI` (independent PE-hash + RSA verify).
- **(B) enrollment** — generating the key-database artifacts a user installs into UEFI
  firmware (PK / KEK / db). **Not started; 0 files in sigil.**

For (B) a consumer setting up their own Secure Boot keychain needs:
- **`EFI_SIGNATURE_LIST`** (`.esl`) — a header (`EFI_CERT_X509_GUID` signature-type +
  sizes) wrapping one or more `EFI_SIGNATURE_DATA` (a signature-owner GUID + the cert
  DER). Reference: efitools `cert-to-efi-sig-list` (present on this box). ~50 lines in
  sigil; the structure is simple and additive.
- **`.auth`** (signed ESL) — `EFI_VARIABLE_AUTHENTICATION_2`: the ESL prefixed with a
  timestamp + a detached PKCS#7 signature over `(varname ‖ vendor-guid ‖ attrs ‖
  timestamp ‖ ESL)`, signed by the *parent* key (KEK signs db, PK signs KEK). Reuses
  sigil's existing PKCS#7 machinery from `authenticode_pkcs7_sign`; the delta is the
  timestamp + the detached-content shape. Reference: efitools `sign-efi-sig-list`.

## Where

- **sigil** — add `efi_signature_list_from_cert(...)` + `.auth` wrapping (new fns; folds
  back into `lib/sigil.cyr` via `cyrius deps` + api-surface regen). A sigil release.
- **cyrius** — optional `cyrius efi-keys` / `efi-sigdb` driver verbs (dispatch to a
  helper like `sign-efi`), OR leave enrollment as direct sigil-lib calls.

## Also filed under this arc

- **OVMF-secboot QEMU boot** of a `cyrius sign-efi`-signed image — belt-and-suspenders
  over the openssl+PE-hash gate (`scripts/sign-efi-gate.sh`), which already checks
  exactly what a UEFI verifier does. `/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd` is
  present locally.

Consumer (gnoboot) can sign `BOOTX64.EFI` today; sovereign key-enrollment tooling is
this follow-on.
