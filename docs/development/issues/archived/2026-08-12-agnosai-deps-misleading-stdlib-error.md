# `cyrius deps` blames the stdlib for a module that is in the stdlib

> ### ✅ RESOLVED — REPRODUCED and FIXED in v6.5.25
>
> **Reproduced verbatim on the real bote tree**, which is what the v6.5.24 note asked for:
> `4 deps resolved, 3 errors` on `bench`/`test` (via libro) and `patra` (via majra) — the
> exact three the filing names. After the fix: **`4 deps resolved`, 0 errors**, with
> `lib/bench.cyr` (20,668 B), `lib/test.cyr` (2,529 B) and `lib/patra.cyr` (223,641 B)
> copied in — byte-for-byte the sizes this filing recorded from the snapshot. Also verified
> clean on agnosai (8 deps, 0 errors) and majra (1 dep, 0 errors).
>
> ⛔ **THIS WAS A FUNCTIONAL RESOLUTION FAILURE, AND v6.5.24's "FIX" WAS THE WRONG LAYER.**
> The filing is titled as a misleading message, and .24 accordingly rewrote the message —
> which left the resolve broken and merely reworded the false claim. Worse, it made the
> output *look* more authoritative while still saying `not in the cyrius stdlib` about a
> module that ships in the stdlib. This filing's own "Root cause (speculation)" section was
> **exactly right** and should have been believed: *"without checking the version-pinned
> snapshot it would have been synced from."*
>
> **The mechanism.** `_dep_find_stdlib_dir()` (`cbt/deps.cyr`) decided "am I the cyrius
> source repo?" with `file_exists("src/main.cyr")` — which is TRUE for essentially every
> cyrius project, because `src/main.cyr` is the entry the init templates generate. So for
> bote/agnosai/majra that branch fired, found the consumer's OWN `./lib` (already partly
> populated by the earlier `[deps].stdlib` phase), and returned it **as** the stdlib. Branch
> (b), the version-pinned snapshot, was never reached. Any sidecar leaf not yet copied there
> looked absent. Fixed by using `_dep_is_cyrius_source_repo()`, which matches
> `[package].name` exactly.
>
> ⚠ **Third occurrence of this identical conflation** — v6.0.1, then `cyrius audit` at
> v6.4.63, now here. The helper was written for the audit fix and never applied to the
> resolver. A "am I the cyrius repo?" test must never be a filename probe.
>
> **Also fixed:** both new .24 messages had off-by-one declared lengths and truncated
> visibly — `(looked in./lib)` ate its trailing space, and an em-dash literal declared 26
> for 27 BYTES. The v6.5.24 `ERR_MSG` length gate could not see them because it scanned
> `ERR_MSG` under `src/` only; widened at .25 to `sys_write` and `cbt/`, which found **16
> more** wrong lengths across the tree, all now corrected.
>
> Gate `tests/gates/toolchain/deps_stdlib_dir_not_consumer_lib.sh`. ⚠ Its FIRST version
> shipped **vacuous** and passed against the pre-fix CLI: with an empty `./lib` the old code
> fell through to the snapshot on its own, so the fixture needs a non-empty `[deps].stdlib`
> to pre-populate `./lib` before the bug can reproduce at all. Caught only by
> mutation-testing; axis 4b now enforces that precondition.

**Status:** ✅ RESOLVED in v6.5.25 — archive at slot close.
**Discovered:** 2026-08-12, bote CI failing after a libro/majra bump
**Severity:** Medium — diagnostic only, but it points at the wrong fix
**Affects:** cycc 6.5.20 (present at least since the 6.5.10 sidecar union)

## Summary

Run `cyrius deps` against an empty `./lib/` and it fails resolving the stdlib
leaves named in a dep's `dist/<pkg>.deps` sidecar, reporting:

```
error: cannot read ./lib/bench.cyr
error: dep libro requires 'bench' but it is not in the cyrius stdlib
```

The second line is false. `bench` **is** in the stdlib. So are every other
module this has named: `test`, `patra`, `random`, `chrono`, `slice`, `ct`.

The real condition is "`./lib/` has not been synced yet" — `cyrius lib sync
--full` had not run. The first line says so; the second contradicts it and wins,
because it is the one phrased as a conclusion.

**Cost:** the message leads a maintainer to edit `[deps].stdlib` and delete a
declaration that was correct. That is the direction it points and it is wrong.

## Reproduction

Verified against the 6.5.20 snapshot — all seven modules present:

```
bench 20668 B · test 2529 B · patra 223641 B · random 1742 B
chrono 24318 B · slice 11927 B · ct 3397 B
```

```sh
cd ~/Repos/bote            # pin 6.5.20, [deps.libro] 2.8.5, [deps.majra] 2.6.3
rm -rf lib
cyrius deps
# 4 deps resolved, 3 errors  — bench, test (libro), patra (majra)

cyrius lib sync --full && cyrius deps
# 4 deps resolved, 0 errors
```

Same shape in agnosai (1 error, `libro requires 'test'`) and majra (2 errors,
`sigil requires 'random'` / `'chrono'`).

## Root cause (speculation)

The resolver appears to treat "not readable at `./lib/<name>.cyr`" as "not a
stdlib module", without checking the version-pinned snapshot it would have been
synced from. Two facts are conflated: *is this a stdlib module* and *is it
present in the working `lib/`*.

## Suggested fix

Report the actual condition, and the action:

```
error: ./lib/bench.cyr not found — required by dep 'libro'
  'bench' IS in the 6.5.20 stdlib; ./lib/ has not been provisioned.
  run: cyrius lib sync --full   (then re-run cyrius deps)
```

Only claim "not in the cyrius stdlib" after checking the snapshot and finding it
genuinely absent — that is a different error with a different fix.

## Notes

Not a regression in any consumer manifest. It surfaced because libro 2.8.5's
sidecar grew 22 → 26 leaves when its dist was regenerated under 6.5.20 (6.5.10+
folds a dep's declared `[deps].stdlib` into its sidecar), and bote moved majra
2.5.3 → 2.6.3 whose sidecar carries `patra`.
