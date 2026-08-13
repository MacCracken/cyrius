# `cyrius deps` blames the stdlib for a module that is in the stdlib

**Status:** 🟡 **OPEN**
**Placement:** unpinned — 6.x-line backlog
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
