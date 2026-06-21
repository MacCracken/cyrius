# Security Policy

## Reporting Vulnerabilities

Report security issues to: security@agnosticos.org

Do **not** open public issues for security vulnerabilities.

## Scope

Cyrius is a systems language compiler. Security-relevant areas:

- **Compiler correctness**: codegen bugs that produce wrong behavior
- **Bootstrap chain integrity**: the ~29 KB `bootstrap/asm` binary is the
  committed root of trust, backed by **two distinct checks** — don't conflate
  them:
  1. **Independent re-derivation of the asm root** (`bootstrap/verify.sh`):
     rebuilds `bootstrap/asm` from the archived **Rust seed** (`archive/seed/`)
     via a different toolchain and checks byte-identity. This is the diverse leg
     that makes the asm binary itself trustworthy (not self-attesting). It needs
     rustc/cargo, so it is **offline / out-of-band** — run it on a clean machine;
     it is **not** in normal CI (no Rust on the build path).
  2. **Closure from the trusted asm root** (`scripts/seed-derive-cycc.sh`):
     given the committed asm binary, proves `build/cycc` descends from it with
     NO bridge rung — asm assembles `cybs` (`bootstrap/cybs.cyr`); `cybs`
     reproduces the asm binary (closure); `cybs` compiles `src/main.cyr` → gen1;
     gen1 → gen2 == `build/cycc` (self-host fixpoint, gen2 == gen3).
  **CVE-20 (resolved 2026-06-20):** `build/cycc` is now machine-derivable from
  the seed (it used to be a disjoint blob nobody re-derived). The
  `trust-root-attest` CI job runs the **closure** check (`seed-derive-cycc.sh`)
  plus a self-host-fixpoint drift backstop (`build-cycc-verify.sh`) — it does
  **not** run `verify.sh`. Full trusting-trust resistance = **both legs**: a
  backdoor in `build/cycc` would have to live in the committed asm binary
  (caught by `verify.sh` re-deriving asm from the Rust source) or in the
  hand-auditable `cybs.cyr` / `main.cyr` source. (The CVE-20 completing fix was a
  missing NUL-terminator in cybs's string lexer, which had broken the
  preprocessor macro-hash and dropped the Linux `#ifdef` block.)
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
