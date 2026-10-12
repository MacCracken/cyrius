# `scripts/ci.sh` never links `$CYRIUS_HOME/lib` on a fresh home — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 11; CHANGELOG [6.7.9]) ci.sh points `$CYRIUS_HOME/lib` at
> `versions/<v>/lib` in every home, through one `_point_lib` that both branches use (install.sh `_relink_active`'s
> rule: a legacy real directory removed, anything else replaced by `ln -sfn`). The plain-bin branch links lib before
> any bin, so a failure leaves the bins as they were. Reproduced first: on the fresh home `$CYRIUS_HOME/lib` was
> ABSENT, and the installed `cyrius build` of a no-pin project with `[deps] stdlib` failed `error: cannot find cyrius
> stdlib`. The same branch also left a cached plain-bin home on its old stdlib while its bins moved on (a lib link
> into `versions/<old>`, or a real directory): fixed by the same call. `tests/gates/toolchain/
> ci_installs_the_release_tarball.sh` axis 6 (the fresh home, both shells: the link, and the installed CLI building
> that project to a program exiting 6) and axis 7 (a plain-bin home whose lib is a link into an older slot, or a real
> directory: re-pointed, the old slot unchanged). The gate's tarball now carries the CLI built from `cbt/cyrius.cyr`.
> The 6.7.8 ci.sh reddens axes 6 and 7. Mutations m–p are in the gate's ledger.

**Status:** ✅ **RESOLVED in v6.7.9** — reported 2026-10-08 by the 6.7.7 install lane: after a ci.sh install into an empty home, a consumer with no `cyrius =` pin cannot find the stdlib (fallback (c) in `_dep_find_stdlib_dir`). The 6.7.7 review fix re-points `lib` only for an install.sh-shaped (linked) home. Fixed: `$CYRIUS_HOME/lib` is linked in every home.
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-08 by the 6.7.7 install lane (out of its scope); filed 2026-10-08.
**Severity:** Medium — a CI install without a pin finds no stdlib.
**Affects:** scripts/ci.sh 6.7.7 – 6.7.8 (every earlier ci.sh linked nothing that worked; CHANGELOG [6.7.7])

## Summary

ci.sh links each `versions/<v>/bin/*` into `$CYRIUS_HOME/bin` on a fresh home, but never creates `$CYRIUS_HOME/lib`;
install.sh's `_switch_active` links both. The old (never-working) layout did not link it either.

## Proposed fix

Create `$CYRIUS_HOME/lib -> versions/<v>/lib` on a fresh home as `_switch_active` does, and add the row to
`tests/gates/toolchain/ci_installs_the_release_tarball.sh` (resolve a stdlib include with no pin).
