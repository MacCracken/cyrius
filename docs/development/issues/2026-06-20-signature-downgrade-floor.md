# Client-side signature anti-downgrade floor (rollback protection)

**Filed:** 2026-06-20 (surfaced by the v6.2.31 CVE-13 adversarial review)
**Severity:** P3 (hardening; the v6.2.31 signing is complete for its stated threat)
**Affects:** `scripts/install.sh`, `scripts/ci.sh`, `scripts/install.ps1`

## Summary

v6.2.31 closed CVE-13 (releases are now Ed25519-signed by `cyrsign`; the
installers verify on the upgrade/CI path; the release CI is fail-closed on a
missing key). But the verify is **opportunistic**: it fires only when a
`SHA256SUMS.sig` is present. There is no client-side memory that a release line
was *previously* signed, so an attacker who can MITM / replace release assets can
**strip `SHA256SUMS.sig`** and every client falls back to the HTTPS + `.sha256`
floor with only an info-level "signature check skipped" — a silent downgrade from
signed to unsigned. (`install.sh` `_verify_signature` returns 2 when the `.sig`
fetch fails → the caller treats it as "unsigned release, skip".)

This is the standard TOFU limitation, NOT a logic bug — it is working as designed
(documented in SECURITY.md's trust model). The acute CI-side edge (a typo'd/unset
`CYRIUS_RELEASE_SK` silently publishing unsigned) was **already closed in
v6.2.31** by making the release signing step `exit 1` on a missing secret.

## What's missing

A **key-continuity / anti-rollback** mechanism so a host that has previously
verified a signed Cyrius release refuses a later *unsigned* one without an
explicit override. Options (each needs persistent client state — not a one-liner):

- Record "signed since `<version>`" (or "this install was signature-verified") in
  `~/.cyrius/` and have `cyriusly`/`install.sh` **require** a valid signature for
  any version >= that floor; allow an explicit `CYRIUS_ALLOW_UNSIGNED=1` escape.
- TOFU-pin the release public key on first verified install; warn loudly if a
  later release presents no signature or a different key.

## Why not now

Rollback protection is a distinct threat from CVE-13 (unsigned releases) and
requires persistent per-host state + a UX for first-install vs upgrade vs
intentional-unsigned. Scope it deliberately rather than bolt on a half-mechanism.
Pairs naturally with the dependency-model / `cyrius.lock` work or a future
`cyriusly` hardening pass.
