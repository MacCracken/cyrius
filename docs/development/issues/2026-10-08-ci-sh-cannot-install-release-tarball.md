# `scripts/ci.sh` cannot install a real release tarball ("cycc not found") — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b: `scripts/ci.sh 6.7.6` fed a tarball packed
the way `release.yml` packs it (one top directory, `cyrius-6.7.6-x86_64-linux/`), through a stub `curl` in a scratch
`CYRIUS_HOME`, verifies the checksum, extracts, then exits 1 `error: cycc not found`.
**Placement:** 6.7.7 (being fixed in this release) — never 7.x.
**Discovered:** 6.7.3 docs pass (2026-10-08, roadmap.md Break 2 *Tooling*); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — a hard failure for every CI that installs through `ci.sh`; `install.sh` installs the same tarball.
**Affects:** `scripts/ci.sh` since its `versions/<v>/bin/*` glob (2026-04-06) through 6.7.6 — it is also shipped
in every tarball's `bin/`.

## Summary

`release.yml` stages each tarball under a top directory and packs that directory (`tar czf "${STAGE}.tar.gz"
"$STAGE"`, `.github/workflows/release.yml:154` and `:232`), so the archive holds `cyrius-<v>-<arch>-<os>/bin/…`,
`…/lib/…`, `…/programs/cyrius-init-templates/…`. `ci.sh` extracts straight into `$CYRIUS_HOME` and then symlinks
`$CYRIUS_HOME/versions/$VERSION/bin/*` — a directory the tarball never creates — so nothing is linked, `current` is
written anyway, and the final check fails. Both gates that run `ci.sh` feed it a fabricated `versions/<v>/bin`
tarball (`tests/gates/toolchain/release_verify_private_temp.sh:84-90`; `install_signature_required.sh:160,169`, its
`ci` layout — the `sh` layout there is the real one), so they read green against a layout no release has.

## Reproduction

```sh
S=<scratch>; VER=6.7.6; ST=cyrius-$VER-x86_64-linux
mkdir -p $S/rel/$ST/bin $S/rel/$ST/lib $S/release $S/stub
printf '#!/bin/sh\necho ok\n' > $S/rel/$ST/bin/cycc; cp $S/rel/$ST/bin/cycc $S/rel/$ST/bin/cyrius; chmod +x $S/rel/$ST/bin/*
(cd $S/rel && tar czf ../release/$ST.tar.gz $ST); (cd $S/release && sha256sum $ST.tar.gz > $ST.tar.gz.sha256)
# $S/stub/curl: the stub from release_verify_private_temp.sh:96-111 (serves $STUB_RELEASE/<basename of URL>)
STUB_RELEASE=$S/release PATH="$S/stub:<PATH without cyrsign>" CYRIUS_HOME=$S/home HOME=$S/h sh scripts/ci.sh $VER
```

Expected: `cycc: ok`, `$S/home/bin/cycc` → `versions/6.7.6/bin/cycc`. Actual:

```
  checksum verified
  signature check skipped (no prior cyrsign on this machine)
  error: cycc not found            (rc 1)
```

and `$S/home` holds `cyrius-6.7.6-x86_64-linux/{bin,lib,VERSION}`, an empty `bin/`, and a `current` naming 6.7.6.

## Root cause

`scripts/ci.sh:141` — `tar xzf "$TD/$TARBALL" -C "$CYRIUS_HOME"` extracts the top directory into the home;
`scripts/ci.sh:145-148` globs `"$CYRIUS_HOME"/versions/"$VERSION"/bin/*` (no match → the loop's `[ -f ]` skips it) and
writes `current` before anything is verified; `:151-156` fails. `install.sh` gets this right: it extracts into its
private stage and reads `$TMPDIR/cyrius-${VERSION}-${ARCH}-${OS_SUFFIX}` (`scripts/install.sh:965-966`).

## Proposed fix

Extract into the private `$TD`, move `$TD/cyrius-$VERSION-x86_64-linux/` to `$CYRIUS_HOME/versions/$VERSION/`
(bin, lib, scripts, programs — what `install.sh` installs), then link and write `current` only after `bin/cycc` and
`bin/cyrius` are present. Refuse a tarball without the expected top directory by name. Gate: build the `ci.sh`
tarballs in `release_verify_private_temp.sh` and `install_signature_required.sh` (`mkrel … ci`) in `release.yml`'s
real layout (the `cyrius-<v>-x86_64-linux/` top directory), so both fail against today's `ci.sh`.
