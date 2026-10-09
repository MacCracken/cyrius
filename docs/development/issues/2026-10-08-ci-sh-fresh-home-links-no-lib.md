# `scripts/ci.sh` never links `$CYRIUS_HOME/lib` on a fresh home — OPEN

**Status:** 🟡 **OPEN** — reported 2026-10-08 by the 6.7.7 install lane: after a ci.sh install into an empty home, a consumer with no `cyrius =` pin cannot find the stdlib (fallback (c) in `_dep_find_stdlib_dir`). The 6.7.7 review fix re-points `lib` only for an install.sh-shaped (linked) home.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 2026-10-08 by the 6.7.7 install lane (out of its scope); filed 2026-10-08.
**Severity:** Medium — a CI install without a pin finds no stdlib.
**Affects:** scripts/ci.sh ≤ 6.7.7

## Summary

ci.sh links each `versions/<v>/bin/*` into `$CYRIUS_HOME/bin` on a fresh home, but never creates `$CYRIUS_HOME/lib`;
install.sh's `_switch_active` links both. The old (never-working) layout did not link it either.

## Proposed fix

Create `$CYRIUS_HOME/lib -> versions/<v>/lib` on a fresh home as `_switch_active` does, and add the row to
`tests/gates/toolchain/ci_installs_the_release_tarball.sh` (resolve a stdlib include with no pin).
