# Release signing keys

The **public** trust anchor for Cyrius release signatures (CVE-13, v6.2.31).

- `cyrius-release.ed25519.pub` — the 64-hex Ed25519 **public** key. Committed
  here (and referenced in [`../SECURITY.md`](../SECURITY.md)) as the out-of-band
  anchor that `install.sh` / `ci.sh` / `install.ps1` and `cyrsign verify` use to
  check `SHA256SUMS.sig`.

The **secret** key (the 32-byte seed) is **never** stored in this repo. It lives
only as the GitHub Actions secret `CYRIUS_RELEASE_SK` (64-hex seed), consumed by
the release workflow's signing step. Generate a keypair with:

```
cyrsign keygen
#   seed <64-hex>  -> GitHub Actions secret CYRIUS_RELEASE_SK (keep offline backup; never commit)
#   pub  <64-hex>  -> keys/cyrius-release.ed25519.pub (commit)
```

**Rotation:** run `cyrsign keygen` again, replace the `CYRIUS_RELEASE_SK` secret,
commit the new `.pub`. The new public key takes effect for the next release;
verifiers pin whatever pub is committed at the tag they install.
