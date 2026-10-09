# `cyrius init` prints "Created <x>/" and exits 0 when its templates are missing — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-08 by the 6.7.7 backlog filer (21 "missing template" errors, then `Created demo/`, rc 0) and by reading `programs/cyrius-init.cyr:519-529` at 2fb6ad8b.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 2026-10-08 by the backlog filer of `install-sh-source-bootstrap-no-init-templates` (out of its scope); filed 2026-10-08.
**Severity:** Medium — a broken install reports success; the user finds the empty project later.
**Affects:** cyrius-init ≤ 6.7.6

## Summary

`_rw_wia` (`programs/cyrius-init.cyr:519`) returns -1 when `_render_template` finds no template, but nothing counts
that in `_rw_fails`, so `_rw_report` never sees the failure: with the template directory missing, `cyrius init demo`
prints one "missing template" line per file and then `Created demo/` and exits 0. The install.sh source-bootstrap
bug (fixed in 6.7.7) made this reachable on every source install; any other missing or partial template tree still
reaches it.

## Reproduction

Run a `cyrius-init` binary whose `<root>/programs/cyrius-init-templates` is absent (e.g. built into a scratch
`versions/<v>/bin` with no `programs/`): `cyrius-init demo; echo $?` → 21 errors, `Created demo/`, `0`.

## Proposed fix

Count a -1 from `_rw_wia` (and its siblings) in `_rw_fails`, and exit non-zero naming the template directory it looked
in. A regression row: init against an empty template dir must exit non-zero.
