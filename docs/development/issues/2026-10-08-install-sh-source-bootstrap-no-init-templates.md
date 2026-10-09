# install.sh's source-bootstrap path ships no `cyrius-init-templates` — `cyrius init` / `port` lose their templates — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: the source-bootstrap branch of
`scripts/install.sh` (1046-1188) copies `lib/` and never `programs/cyrius-init-templates/`; a `cyrius-init` built
from `programs/cyrius-init.cyr` by the tree's `build/cycc` into a scratch `versions/6.7.6/bin/` laid out the way that
branch lays it out (bin + lib, no `programs/`) prints 21 `error: missing template '…'` lines for `cyrius-init demo` —
and then `Created demo/` and exit 0. The `git clone` of the tag itself was not run (it needs the network; the
branch's copy list was read).
**Placement:** 6.7.7 (being fixed in this release) — never 7.x.
**Discovered:** 6.7.3 docs pass (2026-10-08, roadmap.md Break 2 *Tooling*); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — a silently broken scaffold on every install that falls back to building from source (no
prebuilt tarball for the tag, or `CYRIUS_INSTALL_TARBALL` unset with downloads failing).
**Affects:** the source-bootstrap path since the templates moved to `versions/<v>/programs/` (v6.0.60 refresh-only,
v6.2.40 tarball) through 6.7.6.

## Summary

`cyrius-init` resolves its templates as `<bin's grandparent>/programs/cyrius-init-templates`
(`programs/cyrius-init.cyr:187-209`), i.e. `versions/<v>/programs/cyrius-init-templates`. Two install paths put them
there — `--refresh-only` (`scripts/install.sh:774-782`) and the tarball path (`:1020-1028`) — and the third, the
source bootstrap, does not: it builds the bins, installs the `[release]` scripts and the cyriusly twin, copies `lib`
(`:1181-1184`) and stops.

## Reproduction

```sh
S=<scratch>; B=$S/home/versions/6.7.6/bin; mkdir -p $B $S/work
cat programs/cyrius-init.cyr | build/cycc > $B/cyrius-init && chmod +x $B/cyrius-init   # as the branch's _build_tool does
cp -r lib $S/home/versions/6.7.6/; echo 6.7.6 > $S/home/versions/6.7.6/VERSION   # what the branch installs
cd $S/work && HOME=$S/h CYRIUS_HOME=$S/home $S/home/versions/6.7.6/bin/cyrius-init demo; echo rc=$?
```

Expected: a scaffold with VERSION, LICENSE, cyrius.cyml, src/main.cyr, CI workflows, docs. Actual:

```
error: missing template 'version'
… (21 templates: gitignore, license, changelog.md, readme-bin, cyrius-cyml-bin, main-cyr-bin, …, claude-md)
Created demo/
rc=0
```

`demo/` holds the vendored `lib/` and empty directories only.

## Root cause

`scripts/install.sh` source-bootstrap branch (`if [ "$installed" -eq 0 ]`, 1046 → `info "bootstrapped from
source"`, 1187): no `programs/cyrius-init-templates` copy. (The exit 0 is `_rw_wia`, `programs/cyrius-init.cyr:519-529`,
which returns -1 on a missing template without counting it in `_rw_fails`, so `_rw_report` passes — a separate
scaffolder bug, noted out of scope.)

## Proposed fix

In the source-bootstrap branch, beside the `lib` copy: `rm -rf` then `cp -r programs/cyrius-init-templates
"$CYRIUS_HOME/versions/$VERSION/programs/"` (the refresh-only form, `:778-782`). Gate row: a static check (the style of
`cyriusly_version_operand_refused.sh` axis 9d) that every install path — refresh-only, tarball, source-bootstrap —
installs `programs/cyrius-init-templates`, so dropping any one turns it red.
