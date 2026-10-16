# The macOS release tarballs ship two of the three `[release] scripts` — `cyrius-watch.sh` is left out — OPEN (a decision) — RESOLVED

> ✅ **RESOLVED in v6.7.12** (DW-6: both macOS tarball builders now stage every `cyrius.cyml` `[release] scripts` entry through the new `scripts/release-scripts.sh`, so `bin/cyrius-watch.sh` ships in the x86_64 and arm64 tarballs (the user's decision D4, 2026-10-15: (a) ship every [release] script). The helper looks in shims/ first, then scripts/. A listed entry found nowhere, or an empty list, fails the build before anything compiles. Installed with install.sh on ecb and ach, the script is present, executable, and runs. Rows: `macos_tarball_ships_release_scripts.sh` (5 axes; the slot-open builders fail axes 1, 4 and 5). Filed beside it (6.7.14): the watcher's raw `cat | cycc` build, unsigned on Apple Silicon, and the aarch64-linux tarball shipping none of the scripts. CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN — a decision for the user** (what the macOS tarballs ship). Raised by the 6.7.9 quick lane
(bite 12, the x86_64 tarball's shim scripts), which judged it no defect and left it to the user. Verified 2026-10-11
against the merged 6.7.9 tree: `cyrius.cyml`'s `[release] scripts = ["cyrius-repl.sh", "cyrius-watch.sh",
"cyrius-prompt-info"]`; `.github/workflows/release.yml` reads that list (`:105`) and ships all three in the Linux
x86_64 tarball (its `scripts/shims/` lookup fixed in 6.7.9); `scripts/build-macos-x86-tarball.sh:64-65` and
`scripts/build-macos-arm64-tarball.sh:66-67` hand-copy `cyriusly`, `cyrius-prompt-info` and
`scripts/shims/cyrius-repl.sh` only.
**Placement:** 6.7.12 — repair 2: the platform release (darwin lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D4 — ship every [release] script.
on ecb and ach) (the user's call, asked at that release's open) — placed 2026-10-11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9's
[release-tarball shim fix](2026-10-08-release-tarball-misses-shim-scripts.md).
**Severity:** Low — a macOS install has no `cyrius-watch.sh`; nothing breaks.
**Affects:** the macOS x86_64 and arm64 tarballs of every release with the hand-listed copy.

## Summary

`cyrius-watch.sh` is portable POSIX sh, so nothing stops it running on macOS; it is neither a shim nor a CLI verb, and
the macOS scripts copy a hand-chosen subset rather than reading `[release] scripts`. Either the subset is deliberate
(and the manifest's list is Linux's) or the macOS tarballs drifted from the manifest.

## The decision

- **(a) Ship it:** both macOS scripts copy every `[release] scripts` entry (read from the manifest, as release.yml
  does, so the next script added cannot drift), and the tarball gate checks each one is present.
- **(b) Keep the subset:** a comment in both scripts names `cyrius-watch.sh` as deliberately Linux-only (and why).
