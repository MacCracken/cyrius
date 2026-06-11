# Release / trust-chain integrity — CVE-20/21 (extends CVE-12/13)

**Discovered:** 2026-06-10 during the deep-dive review ([`docs/audit/2026-06-10-deep-dive-review.md`](../../audit/2026-06-10-deep-dive-review.md))
**Severity:** High
**Affects:** bootstrap + build/install/release infra 6.1.31. Directly undercuts
the "own the trust chain, no external governance" stance and the ~v7 public-release story.

## Summary

The shipped trust root is not what the docs say it is, and the release path has
several advisory-only or mutable links a sovereignty stance is meant to remove.

## CVE-20 — shipped `cycc` is the de-facto trust root, disjoint from the seed (P2)

`SECURITY.md:14` + `README.md:96/128/216` assert the 29 KB seed (`bootstrap/asm`)
is the "root of trust", but `bootstrap.sh:29-53` only produces **cybs + asm** and
verifies the asm↔cybs closure — it never produces cycc. `release.yml:36-38` runs
`bootstrap.sh` then compiles `src/main.cyr` with the **committed `./build/cycc`**
(`:38`), discarding the seed output entirely. No script anywhere rebuilds cycc
from cybs (the cc3 bridge hop dropped at v6.1.0). The only drift guard on the
committed cycc is the heuristic pre-commit hook (foreign-string greps + a
700 K–1.2 M size band, `scripts/hooks/pre-commit:49-64`).

**Fix:** document that the shipped trust root is `build/cycc`, not the seed; add a
periodic CI job that runs `verify.sh` (Rust-seed rebuild) **plus** a cybs→cycc
reconstruction (restore a bridge step or commit the lineage) so the committed
cycc is machine-derivable from the seed. Reframe CVE-12 accordingly.

## CVE-21 — release/dep integrity is advisory or mutable (P2)

- **Tarball checksum non-blocking** — `install.sh:370-373` runs `sha256sum -c`
  and on mismatch prints "checksum mismatch — continuing anyway" and proceeds;
  `scripts/ci.sh:26-32` curls + `tar xzf` with **no** checksum at all;
  `install.ps1:36-40` has no hash check.
- **Installer pulled from `main`, not the tag** — `cyriusly install <v>` curls
  `install.sh` from the **main** branch then runs it with `CYRIUS_VERSION=<v>`
  (`cyriusly:57`); `install.sh`'s source-bootstrap fallback silently falls to
  default HEAD when the tag clone fails (`install.sh:455-456`). A main-branch
  compromise instantly hits all updaters.
- **Mutable git-tag deps, no SHA pin** — dep resolution clones
  `git clone --depth 1 -b <tag>` (`deps.cyr:717-725`); no commit hash is recorded
  or verified; a cached clone dir is reused without re-validation (`:689`). A
  force-pushed tag in any `MacCracken/*` dep silently changes resolved content.
  `cyrius.lock` stores only file hashes (no resolved SHA) and is opt-in-verified.
- **Unsigned releases** — all 5 tarballs get only a `.sha256` sidecar hosted next
  to the artifact (CVE-13, ~13 minors aged).
- **Unpinned GitHub Actions with `contents:write`** — `release.yml:7-8` grants
  `contents: write` and consumes `softprops/action-gh-release@v2` (`:380`),
  `actions/checkout@v4` (`:22`), upload/download-artifact@v4 by **floating major
  tag**. A tag-repoint of any of these runs in the release job with write access
  to publish arbitrary assets — the external-trust surface the no-crates.io stance
  exists to avoid, reintroduced via CI vendor.

**Fix:** flip `install.sh:373` warn→err (abort on mismatch); add `.sha256`
verify to `ci.sh` + `install.ps1`; curl `install.sh` from `/refs/tags/<version>/`
and make the tag-clone failure fatal; record resolved commit SHA per dep in
`cyrius.lock` and verify tag→SHA on re-resolve; add detached signing
(minisign/signify `SHA256SUMS` published out-of-band); pin all GitHub Actions to
full commit SHAs (comment naming the version).

## Status

Filed 2026-06-10. Folds the aging CVE-12/13 from the archived audit. Run the
overdue full audit before v6.2.0 (see
[overdue-security-audit-cve-tail](2026-06-10-overdue-security-audit-cve-tail.md))
and land the signing/attestation as v7 trust-story prerequisites.
