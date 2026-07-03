# Sovereign UEFI Secure Boot signing — Authenticode PE signing + the RSA / X.509 / PKCS#7 crypto floor

**Filed:** 2026-07-03 (by a **gnoboot** consumer — the sovereign UEFI bootloader's
post-v1.0 Secure Boot chain).
**Severity:** Toolchain sovereignty gap at the boot-trust boundary. cyrius emits a
valid **PE32+ EFI Application** (`CYRIUS_TARGET_EFI=1`), but it cannot **sign** that
PE for UEFI Secure Boot. `sigil` already supplies most of the crypto floor —
native RSA PKCS#1 v1.5 **sign** (`rsa_pkcs1v15_sign_sha256`), X.509 + DER, SHA-256 —
but the **UEFI-specific packaging layer is missing** (PKCS#7/CMS `SignedData`, the
Authenticode `SpcIndirectData` + PE Authenticode hash + attribute-cert-table embed,
and `EFI_SIGNATURE_LIST` generation); sigil's `secureboot_sign_module` currently
shells out to `kmodsign`/`sign-file` (Linux **kernel-module** signing, not UEFI
Authenticode). That gap is filed against sigil:
`sigil/docs/development/issues/2026-07-03-authenticode-pe-signing.md`. So the only
way to Secure-Boot-sign a sovereign AGNOS EFI binary today is **external,
non-sovereign tooling** (`sbsign` from sbsigntools, or hand-rolled openssl). That
breaks the AGNOS
sovereignty pattern (*cyrius replaced gcc/clang/llvm; agnos replaced Linux; gnoboot
replaced GRUB*) at exactly the point where the machine's root of trust is
established.
**Affects:** **gnoboot** (headline — its `BOOTX64.EFI` must be Authenticode-signed
to run under Secure Boot); **agnova** (stages gnoboot to the ESP — the sovereign
installer should provision AGNOS-owned Secure Boot keys, not shell out to
efitools); any future sovereign EFI binary; the whole *"no firmware compromise, no
kernel tampering"* trust story. Downstream, the same PKI floor also unlocks any
sovereign X.509/TLS-server-cert or code-signing need.
**Target slot:** **v6.4.x+**, maintainer-directed. **NOT a release blocker** — Secure
Boot is explicitly *post-v1.0* in gnoboot's roadmap (`gnoboot/docs/development/roadmap.md`
§ *Secure Boot signing chain*), so there is runway. This proposal is the **toolchain
prerequisite** that unblocks it.
**Precedent:** `sigil`'s existing crypto (Ed25519 / AES-GCM / SHA-256, incl. the
SHA-NI/AES-NI hardware banks) is the crypto-home precedent; `cyrsign` / `cyrius
distlib` are the "toolchain post-build step" precedent; the `CYRIUS_TARGET_EFI`
PE-COFF emit is what this signs.

## Trigger

gnoboot is the sovereign UEFI bootloader (replaced GRUB 2026-05-13 after GRUB's
multiboot2-EFI relocator faulted under strict-W^X UEFI). On a machine with **UEFI
Secure Boot enabled**, firmware executes an EFI image **only** if its Authenticode
signature chains to a certificate in the firmware `db` variable. gnoboot's
`BOOTX64.EFI` is currently **unsigned** → Secure Boot firmware rejects it silently.
The sovereign fix is: sign it with a **self-managed** key (AGNOS owns its own
PK/KEK/db — no Microsoft 3rd-party UEFI CA), using the sovereign toolchain. But
cyrius cannot sign a PE, and no ecosystem crate can produce the required artifacts.

Empirically, on this dev host: `cyrius build --target-efi` produces a clean 30 KB
PE32+ (4 sections) — signable in principle — but `sbsign` / `cert-to-efi-sig-list`
/ `sign-efi-sig-list` are absent, and the only present primitive is host `openssl`.
Depending on host openssl for the AGNOS boot root-of-trust is the anti-pattern this
proposal closes.

## Background — this is firmware-mandated X.509/RSA, NOT a sovereign-crypto choice

Important framing so the proposal isn't mis-scoped: **UEFI Secure Boot's crypto is
dictated by firmware**, not by us. A `db`/`KEK`/`PK` entry is an **X.509
certificate**; an accepted image carries a **PKCS#7 / CMS SignedData** over the
**Authenticode SHA-256** of the PE, with an **RSA-2048** (or ECDSA P-256) signature.
Ed25519 is **not** an option — firmware will not verify it. So "sovereign Secure
Boot" means **AGNOS owns the KEYS** (self-managed PK/KEK/db, generated + held by
AGNOS, enrolled by the sovereign installer), *not* that we invent a sovereign
signature scheme (firmware would reject it). This proposal gives the sovereign
toolchain the ability to **produce the firmware-mandated artifacts with keys AGNOS
controls** — the maximal sovereignty actually achievable at this boundary.

## What's needed

Three capabilities, in dependency order:

### 1. The crypto floor — **mostly already in `sigil`**; the gap is the UEFI packaging

Filed in detail as `sigil/docs/development/issues/2026-07-03-authenticode-pe-signing.md`.
Correcting an earlier mis-scope: `sigil` is a deep crypto library, **not** hash-only.
It **already has**: native RSA PKCS#1 v1.5 **sign**+verify+PSS
(`rsa_pkcs1v15_sign_sha256`, blinded+CRT, 3.6.4), X.509 + DER walk/parse
(`der_*`, `x509_cert_*`), SHA-256 (+SHA-NI), PEM, bignum, ECDSA-P256, even ML-DSA.
So RSA/X.509/DER/SHA-256 are **done** — reuse them.

The **missing** layer (grep: 0 files) is UEFI-specific:
- **PKCS#7 / CMS `SignedData`** (DER-encode `ContentInfo`→`SignedData`+`SignerInfo`).
- **Authenticode**: `SpcIndirectDataContent` + the PE Authenticode hash + embedding
  the PKCS#7 in the PE Attribute-Certificate Table.
- **`EFI_SIGNATURE_LIST` / `.auth`** generation for PK/KEK/db enrollment.

Note: sigil's existing `secureboot_sign_module` is a wrapper over `kmodsign`/`sign-file`
(Linux kernel-**module** signing) — a different artifact class, and non-sovereign;
it is **not** a starting point for UEFI Authenticode. Home for the new work: a
`sigil` `authenticode`/`pkcs7` module (recommended separate from the Linux-module
wrapper), on the existing RSA/X.509/DER primitives — the crypto lift is small.

### 2. Authenticode PE signing — `cyrius sign-efi`

Compute the **Authenticode hash**: SHA-256 over the PE image **skipping** (a) the
`CheckSum` field in the optional header, (b) the Certificate-Table entry in the Data
Directory, and (c) the attribute-certificate data itself; then hash the trailing
data after the sections in the spec-defined order. Wrap it in a PKCS#7 SignedData
(`SpcIndirectDataContent`), sign with the db RSA key, and append the result to the
PE's **Attribute Certificate Table** (`WIN_CERTIFICATE`,
`WIN_CERT_TYPE_PKCS_SIGNED_DATA`), updating the Security Data Directory
(offset/size) + the PE size. This is the exact job `sbsign` does.

### 3. EFI key-enrollment artifacts — enrollment path

`EFI_SIGNATURE_LIST` (`.esl`) + `EFI_VARIABLE_AUTHENTICATION_2`-wrapped `.auth`
files for `PK` / `KEK` / `db`, so the sovereign installer (agnova) can provision a
machine with AGNOS-owned Secure Boot keys (Setup Mode → enroll PK/KEK/db). This is
what efitools' `cert-to-efi-sig-list` + `sign-efi-sig-list` produce.

## Proposed surface (design space — NOT committed)

| Subcommand | Effect |
|---|---|
| `cyrius sign-efi --key db.key --cert db.crt <pe> [-o out.efi]` | Authenticode-sign a PE (mirrors `sbsign`) — **the headline deliverable** |
| `cyrius efi-keys [--pk\|--kek\|--db]` | generate the sovereign X.509+RSA key trio |
| `cyrius efi-sigdb <cert> --type db\|KEK\|PK` | emit `.esl` / `.auth` enrollment artifacts |

Alternative: keep signing out of the compiler driver and ship a standalone
sovereign `cyrsign-efi` binary (parallels `cyrsign`), with the crypto in `sigil`.

## Phasing (suggested)

- **P1 — sigil crypto layer** (the sigil issue's P1/P2): PKCS#7/CMS `SignedData` +
  Authenticode PE hash, built on sigil's *existing* RSA-sign / X.509 / DER. This is
  the gate; RSA/DER/X.509 already exist, so the lift is the UEFI packaging.
- **P2 — `cyrius sign-efi`.** The toolchain driver: read the PE, call the sigil
  `authenticode_pe_sign`, embed in the attribute-cert table, write the signed PE.
  **Unblocks gnoboot Secure Boot** — provable end-to-end against
  `OVMF_CODE.secboot.fd` with AGNOS-owned keys enrolled in `OVMF_VARS`.
- **P3 — enrollment artifacts.** `.esl` / `.auth` for full self-provisioning (agnova).
- **P4 (optional, high value) — PE signature *verification*.** Lets gnoboot verify
  the **kernel** it loads (the other half of the boot-trust chain, currently a
  hard "no verification" gap) and gives sovereign Authenticode verify generally.
  Plus optional **ECDSA P-256** for firmware that prefers it.

## Scope / non-goals

- **Not** inventing sovereign Secure Boot crypto — firmware mandates X.509/RSA/PKCS#7.
- **Not** the Microsoft 3rd-party UEFI CA path — that cedes the root of trust to
  Microsoft's key; **self-managed PK/KEK/db only**.
- Production **key ownership** (who holds the AGNOS PK/KEK/db, how it's provisioned
  + rotated) is an **AGNOS policy decision**, out of scope for this toolchain proposal.

## Open decisions (maintainer)

- **RSA-2048 vs ECDSA P-256** as the default. RSA-2048 is the safe universal
  firmware default; ECDSA is smaller/faster but not universally accepted in `db`.
- **Crypto home:** grow `sigil` into the PKI home, or a dedicated `pki`/`authenticode`
  crate. (`sigil` keeps it one boundary; the surface add is large.)
- **Driver subcommand vs standalone tool** (`cyrius sign-efi` vs `cyrsign-efi`).
- **Include verification (P4) in the same arc?** It closes the *full* firmware→gnoboot→kernel
  trust chain, and the RSA-verify + Authenticode-hash code is largely shared with signing.

## Interim (until this lands)

gnoboot's Secure Boot proof can be demonstrated with external `sbsign` + `efitools`
using **AGNOS-owned self-managed keys** (own PK/KEK/db, not Microsoft's) against
`OVMF_CODE.secboot.fd` — documented explicitly as a **non-sovereign stopgap for
validation**, not the shipped end-state. The end-state is this proposal: the boot
root-of-trust signed by the sovereign toolchain.
