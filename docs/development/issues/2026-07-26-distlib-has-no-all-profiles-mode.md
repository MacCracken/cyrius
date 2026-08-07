# `cyrius distlib` regenerates ONE bundle per invocation, so multi-profile repos ship stale sub-bundles under a fresh version string — RESOLVED

**Status:** ✅ **RESOLVED — both proposed fixes shipped v6.5.8.** Re-verified against live code on
cycc **6.5.10**, 2026-08-07:

- `cmd_distlib_all(check)` exists at `cbt/commands.cyr:2056`, and it does exactly what fix 1 asked
  for — `_distlib_enum_profiles()` reads the `[lib.<name>]` section headers out of the manifest as
  a set, so the list **cannot drift from `cyrius.cyml`**.
- The CLI dispatch (`cbt/cyrius.cyr:333-370`) now parses `--all` and `--check`, routes both to
  `cmd_distlib_all(dchk)`, and rejects `--all`/`--check` combined with a named profile.
- `cyrius --help` line (`cbt/cyrius.cyr:51`) documents it:
  `distlib [--all|--check] [--modular] [profile]   … (--all = base + every [lib.X]; --check = verify, don't write)`.

Fix 3 (making bare `cyrius distlib` mean `--all`) was **not** taken — it was flagged in this file
as a judgement call, and the single-profile default is preserved. Fix 4 and the "Also worth fixing
while here" profile-list corrections are sibling-repo edits and are not cyrius's to close.
**Follow-on already shipped too:** v6.5.10 fixed `distlib`'s `.deps` sidecar under-reporting, and
`--check` was re-verified not to write (CHANGELOG [6.5.10] Notes).
**Placement:** closed — ready to archive. Any remaining work is in the sibling repos (sankoch's
`zip`/`zipall`, sigil's `argon2`, and re-pointing both CI loops at `--check`), not here.

**Discovered:** 2026-07-26 while cutting sankoch 2.7.6 (the batch-gzip block-boundary corruption fix,
folded into cyrius v6.4.79).
**Severity:** **Medium–High** — no wrong code in cyrius itself, but the failure mode is a *shipped
stale artifact carrying a current version number*, which is indistinguishable from a good one without
grepping the bundle for the fix. The workaround (hand-rolled per-profile loops) exists and has
**provably drifted in 2 of the 6 affected repos** — see Evidence.
**Affects:** `cyrius distlib` in all versions to 6.4.79. Six sibling repos, 36 sub-profiles.

## Summary

`cyrius distlib` regenerates exactly **one** bundle per invocation: bare `cyrius distlib` rebuilds
`dist/<pkg>.cyr` from `[lib].modules`, and `cyrius distlib <profile>` rebuilds
`dist/<pkg>-<profile>.cyr` from `[lib.<profile>].modules`. There is **no "regenerate everything the
manifest declares" mode.**

Every multi-profile repo therefore needs an N+1-invocation ritual that nothing enforces, and the
list of profiles must be maintained by hand in at least two more places (the release procedure and
the CI staleness check) *in addition to* the manifest that already declares them.

## What it cost, concretely

Cutting sankoch 2.7.6 — a **silent-data-corruption** fix — I ran the documented release step,
`cyrius distlib`. It rebuilt `dist/sankoch.cyr` to 2.7.6. **All nine sub-profiles stayed at 2.7.5,
still carrying the buggy encoder.** `dist/sankoch-gzip.cyr` — the profile whose entire purpose is the
codec that was broken — would have shipped the defect.

This was caught only because I swept the version strings across `dist/*.cyr` afterwards. Nothing in
the tool, the release script, or the local workflow would have said a word. And a version sweep alone
is *not sufficient*: once the profiles are regenerated, the version string matches whether or not the
fix is in, so the real check is grepping each bundle for the fix symbol.

The repo's own release script actively points at the incomplete command
(`sankoch/scripts/version-bump.sh`):

```
Next steps:
  1. Update CHANGELOG.md ([Unreleased] → [2.7.6] + release date)
  2. cyrius distlib       # regenerate dist/sankoch.cyr
  3. git commit -am 'release 2.7.6'
  4. git tag 2.7.6 && git push --tags
```

Follow those four steps literally on any multi-profile repo and you tag a release whose sub-bundles
are stale.

## Evidence that the workaround drifts (the part that makes this worth fixing)

Two repos have independently hand-rolled the same loop in CI — itself a signal the tool should own
it — and **both lists have already drifted from their manifests**:

| repo | profiles declared in `cyrius.cyml` | profiles in the CI loop | **never regenerated or verified** |
|---|---|---|---|
| **sankoch** | 9 — `core zlib zstd bzip2 xz gzip zip zipall tar` | 7 | **`zip`, `zipall`** |
| **sigil** | 13 — `aes argon2 authenticode chacha ecdsa ed25519 hkdf hmac mldsa secureboot sha tpm x509` | 12 | **`argon2`** |

`dist/sankoch-zip.cyr` and `dist/sankoch-zipall.cyr` are tracked, shipped bundles. sankoch's CI
neither rebuilds nor diff-checks them, and the bundle list in its staleness check omits them too — so
the check that exists to catch drift is written in the same hand-maintained list that drifted.

Full ecosystem exposure:

| repo | sub-profiles | dist files |
|---|---|---|
| sigil | 13 | 14 |
| sankoch | 9 | 10 |
| bayan | 8 | 9 |
| sandhi | 4 | 5 |
| yukti | 1 | 2 |
| vani | 1 | 2 |

36 sub-profiles across 6 repos, each needing a manual invocation on every release.

## Reproduction

In any multi-profile repo (`~/Repos/sankoch`):

```console
$ sh scripts/version-bump.sh 2.7.6      # or edit VERSION
$ cyrius distlib                        # the documented step
$ for f in dist/*.cyr; do printf '%-26s %s\n' "$(basename $f)" \
      "$(grep -m1 -oE '# Version: *[0-9.]+' $f)"; done
sankoch-bzip2.cyr          # Version: 2.7.5     <- stale
sankoch-core.cyr           # Version: 2.7.5     <- stale
sankoch-gzip.cyr           # Version: 2.7.5     <- stale
...
sankoch.cyr                # Version: 2.7.6     <- only this one rebuilt
```

## Root cause

`cbt/commands.cyr` `cmd_distlib(profile)` takes a single profile and emits a single bundle. The CLI
dispatch (`cbt/cyrius.cyr`, the `distlib` branch) scans args for `--modular` and takes the **first
non-flag arg** as the profile — there is no all-profiles path and no way to ask the manifest what
profiles exist.

The information needed is already in the manifest: the `[lib.<name>]` section headers *are* the
authoritative profile list. Nothing reads them as a set.

## Proposed fix

1. **`cyrius distlib --all`** — enumerate every `[lib.<name>]` section in the manifest and regenerate
   the base bundle plus each profile. Because the list comes from the manifest, it cannot drift; a
   profile added to `cyrius.cyml` is covered the moment it exists. This alone removes the ritual and
   both hand-rolled CI loops.

2. **`cyrius distlib --check`** (pairs with `--all`) — regenerate into a temp location and report any
   bundle that differs from the committed copy, non-zero on drift. This is precisely what sankoch's
   and sigil's CI steps hand-roll today, and it would make those steps a one-liner that cannot omit a
   profile. Worth printing the offending bundle names (the v6.4.78 lesson: a stage that reports a
   verdict without naming what it checked reads as authoritative when it is not).

3. **Consider making bare `cyrius distlib` mean `--all`.** It is the behaviour every caller actually
   wants — no release wants a partially-regenerated `dist/`. The single-profile form stays available
   as `cyrius distlib <profile>`. This is a behaviour change to an existing verb, so it is flagged as
   a judgement call rather than folded into (1); if taken, sibling `version-bump.sh` scripts and the
   two CI loops should be simplified in the same pass.

4. **Update the release-procedure text** in the sibling repos' `version-bump.sh` next-steps once (1)
   lands, so the documented path is the complete one.

Independently of which shape is taken: **`--check` should verify content, not just regenerate.** A
version-string sweep is not sufficient evidence a bundle is current — after any regeneration the
version matches whether or not the intended change is present.

## Consumer-side workaround

Run the loop by hand and verify against the manifest rather than a written-down list:

```sh
cyrius distlib
for p in $(grep -oE '^\[lib\.[a-z0-9_-]+\]' cyrius.cyml | sed 's/\[lib\.//;s/\]//'); do
    cyrius distlib "$p"
done
for f in dist/*.cyr; do printf '%-26s %s\n' "$(basename $f)" "$(grep -m1 -oE '# Version: *[0-9.]+' $f)"; done
```

Deriving the list from `cyrius.cyml` is the important part — that is exactly what the two committed
CI loops failed to do.

## Also worth fixing while here

`sankoch`'s CI staleness check and `sigil`'s "Verify per-primitive distlib profiles are in sync" step
should be re-pointed at `--check` once it exists; until then their profile lists need correcting
(`zip`/`zipall` and `argon2` respectively). Those are sibling-repo edits, not cyrius edits, and are
noted here so the fix lands end-to-end rather than leaving the two drifted lists in place.
