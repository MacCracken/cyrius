# Security Policy

## Reporting Vulnerabilities

Report security issues to: security@agnosticos.org

Do **not** open public issues for security vulnerabilities.

## Scope

Cyrius is a systems language compiler. Security-relevant areas:

- **Compiler correctness**: codegen bugs that produce wrong behavior
- **Bootstrap chain integrity**: the 29 KB seed (`bootstrap/asm`) is the
  *source-level* root of trust — `bootstrap/bootstrap.sh` rebuilds `cybs` from
  the seed and verifies the asm↔cybs closure. **Note (CVE-20):** the trust root
  for **binary releases** is the *committed* `build/cycc` — release builds
  compile `src/main.cyr` with it, and `cybs` (an assembler) cannot rebuild
  `cycc`, so the seed does not derive it. **v6.2.31** adds an interim, scope-honest
  attestation — the `trust-root-attest` CI job asserts the committed `build/cycc`
  is a byte-identical **self-host fixpoint** (it compiles its own source, that
  output recompiles to itself, and equals the committed binary). That catches
  accidental **artifact drift** and non-self-reproducing tampering. It does **not**
  defeat a self-reproducing (Thompson "trusting-trust") tamper — the committed
  binary is its own root, so a self-perpetuating backdoor is a stable fixpoint
  that passes. **Full** trusting-trust resistance needs an *independent* root
  (diverse double compilation from the seed/cybs bridge or another compiler) —
  the *literal* `seed → cybs → bridge → cycc` derivation that makes `cycc`
  seed-*derivable*, which is the separately-tracked bridge-restoration arc. Until
  it lands, `build/cycc` is the de-facto trust root, attested only against drift.
- **Kernel code**: AGNOS kernel memory safety, interrupt handling, syscall validation
- **Build tool (cyrius)**: fork/exec security, path handling
- **Package manager (ark)**: package verification, database integrity

## Supported Versions

Cyrius releases follow semver. Security fixes land on the latest minor and
the prior minor; older lines are best-effort. Per CLAUDE.md, **v5.0.0+ is
the recommended minimum** (cycc IR + cyrius.cyml manifest). v5.0.1+ adds
alloc/vec overflow guards. v5.1.0+ adds macOS Mach-O.

| Version | Supported |
|---------|-----------|
| 6.2.x | Yes (current) |
| 6.1.x | Yes |
| 6.0.x | Best-effort |
| 5.x.x (5.0.0+) | Best-effort |
| < 5.0.0 | No |

## Release Integrity & Signing (v6.2.31, CVE-13)

Releases are protected by a **sovereign** signing chain — cyrius's own crypto,
no external `minisign` / `gpg`:

1. **Per-artifact checksums.** Every release tarball ships a `.sha256` sidecar.
   The installers ([`scripts/install.sh`](scripts/install.sh),
   [`scripts/ci.sh`](scripts/ci.sh), [`scripts/install.ps1`](scripts/install.ps1))
   verify it **fail-closed** before extracting (CVE-21, v6.2.30) — HTTPS +
   checksum is the first-install floor.
2. **Detached Ed25519 signature.** When the signing key (`CYRIUS_RELEASE_SK`) is
   configured, the release also publishes `SHA256SUMS` (the aggregate of all
   per-tarball hashes) and `SHA256SUMS.sig`, an **Ed25519** signature produced by
   [`cyrsign`](programs/cyrsign.cyr) over sigil's in-tree curve. (A release built
   without the key publishes `SHA256SUMS` only; installers fall back to the
   checksum floor.) The public key is committed at
   [`keys/cyrius-release.ed25519.pub`](keys/cyrius-release.ed25519.pub) and
   embedded in the installers as the trust anchor; the secret key lives only as
   the CI secret `CYRIUS_RELEASE_SK` and never touches the repo.

**Verify a release manually** (the always-available, fully-sovereign path):

```sh
cyrsign verify SHA256SUMS SHA256SUMS.sig keys/cyrius-release.ed25519.pub   # exit 0 = authentic
sha256sum -c SHA256SUMS                                                    # then check the tarball
```

**Trust model.** The signature guards every **signed upgrade** (`cyriusly`/CI verify the
new download with a trusted prior `cyrsign` before installing) and all **manual**
verification. A very first `curl | sh` has no prior verifier, so its floor is
HTTPS + the `.sha256` (trust-on-first-use); the signature applies from the next
upgrade on. Key rotation: `cyrsign keygen` → replace `CYRIUS_RELEASE_SK` + commit
the new `.pub` (see [`keys/README.md`](keys/README.md)).

## Response

We aim to respond to security reports within 48 hours and provide fixes within 7 days for critical issues.
