# Replace the GitHub macos-13 x86-macOS CI job with a self-hosted `ach` runner

**Filed:** 2026-06-03
**Severity:** P2 (CI reliability)
**Status:** queued (user-directed 2026-06-03)

## Why

The `macho-x86-native` job (`.github/workflows/ci.yml`, runs-on: macos-13) is
the GitHub-hosted x86-macOS self-host cross-check. It's unreliable for two
reasons:

1. **GitHub's Intel (`macos-13`) fleet is scarce / being deprecated** — jobs
   queue for a long time (looks like a stall) and the supply will only shrink.
2. **Quarantine + Gatekeeper** — `actions/download-artifact` tags the unsigned
   cross-built Mach-O with `com.apple.quarantine`; first-exec of an unsigned,
   quarantined, downloaded binary blocks forever on the headless runner's
   syspolicyd assessment. Worked around in v6.0.45 with `xattr -cr` + a hard
   timeout + `continue-on-error: true` (non-blocking), but it's a workaround.

The **authoritative** x86-macOS gate is already `cyrius audit` →
`scripts/cross-os-selfhost.sh ach` on the real Intel Mac `ach` (macOS 13.7.8),
run before tagging. The binary self-hosts byte-identical there (~0.95 s/pass);
there is no codegen problem — only GitHub-Intel-runner flakiness.

## What

Register `ach` (the real Intel Mac, SSH-wired) as a **self-hosted GitHub
Actions runner** and point the x86-macOS self-host job at it (e.g.
`runs-on: [self-hosted, macOS, X64]`). Then:

- Drop `continue-on-error` / the `macos-13` hosted runner for x86-macOS — the
  self-hosted `ach` runner is always available and is real hardware, so the
  job can be a **real blocking gate** again.
- No quarantine issue: a self-hosted runner's checkout/build path isn't
  download-quarantined the way `actions/download-artifact` is (and `xattr -cr`
  stays as a belt-and-suspenders).
- Same pattern is the long-term answer for any platform GitHub under-serves
  (Intel macOS today; possibly others later).

## Notes

- Self-hosted runners on a personal Mac: scope to this repo, ephemeral/locked
  down, and gate on `push`/`workflow_dispatch` to avoid running untrusted PR
  code. (Security: never auto-run fork PRs on a self-hosted runner.)
- Pairs with the existing real-hardware gate philosophy (CLAUDE.md "Cross-OS
  self-host is non-negotiable, on REAL hardware").
