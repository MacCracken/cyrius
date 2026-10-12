# `cyrius init` prints "Created <x>/" and exits 0 when its templates are missing — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 13; CHANGELOG [6.7.9]) `_rw_wia` writes through `_rw`, so a
> template it cannot render or a file it cannot write counts toward `_rw_report`'s exit 1; a greenfield init and a
> port refuse up front, naming the directory and creating nothing, when the template directory is absent (a port
> no longer moves the source aside first); the INCOMPLETE report names the directory the missing templates were
> looked for in; and no success line follows a failure (init's `Created <x>/` and next steps, port's per-file
> `Created` lines and `ready for porting`). Reproduced first on the 6.7.9-open tree: 21 "missing template" lines,
> `Created demo/`, rc 0. `tests/gates/toolchain/init_missing_templates_fails.sh` (9 axes, `sh` and
> `bash -eo pipefail`): empty / absent / partial template trees greenfield, in-place empty, an in-place write
> failure, in-place on a complete project with no templates (exit 0 — the refusal is greenfield-only), the full
> tree (exit 0), port absent / partial. The pre-fix source reddens 26 checks; each of 8 single mutants reddens its
> own axis.

**Status:** ✅ **RESOLVED** in v6.7.9 (the quick lane's bite 13). Filed OPEN 2026-10-08, verified by the 6.7.7 backlog filer (21 "missing template" errors, then `Created demo/`, rc 0) and by reading `programs/cyrius-init.cyr:519-529` at 2fb6ad8b.
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-08 by the backlog filer of `install-sh-source-bootstrap-no-init-templates` (out of its scope); filed 2026-10-08.
**Severity:** Medium — a broken install reports success; the user finds the empty project later.
**Affects:** cyrius-init ≤ 6.7.8 (fixed in 6.7.9)

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
