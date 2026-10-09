# `fhm_set` on a PRESENT key can rebuild (and double) the table — `lib/hashmap.cyr` stopped doing that at 6.6.20 — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b with
`repros/2026-10-08-hashmap-fast-overwrite-rebuilds.cyr`: overwriting one of 14 live keys in a 16-slot map takes the
table to 32 slots, allocates 544 B and counts one rebuild (exit 1; expected exit 0).
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.3 (filed in roadmap.md's backlog by the 6.7.x feature releases; CHANGELOG [6.7.3] "hashmap_fast's
overwrite can rebuild"); filed 2026-10-08 from roadmap.md.
**Severity:** Low — `lib/hashmap_fast.cyr` is experimental with no callers (its header, `:5-12`), and the behaviour
is documented in `fhm_set`'s comment (`:220-222`).
**Affects:** cycc ≤ 6.7.6 (the trigger has preceded the key lookup since at least 6.6.8's tombstone rework).

## Summary

`fhm_set` checks its rebuild trigger — (live + tombstones) at 87.5 % — BEFORE `_fhm_insert` has looked the key up.
So an overwrite of a key that is already present, which adds no entry and needs no room, can:

1. **double the table** (or rebuild it in place) — 544 B at 14 live in 16 slots, 16 → 32;
2. **return -1 and drop the overwrite** when that doubling's allocation is refused (`:232` returns before
   `_fhm_insert` runs), although storing the value needs no memory at all;
3. **move entries under a caller walking the arrays** across an overwrite (the in-place rebuild relocates them),
   which `fhm_set`'s comment concedes (`:220-222`: "an overwrite at the trigger rebuilds too").

Its twin `lib/hashmap.cyr` looks the key up first and returns on an overwrite without touching the trigger
(`map_set_a`, `lib/hashmap.cyr:405-414`: "an overwrite: never rebuilds, so a walk that overwrites as it goes stays
valid"), since 6.6.20.

## Reproduction

```sh
cat docs/development/issues/repros/2026-10-08-hashmap-fast-overwrite-rebuilds.cyr | build/cycc > /tmp/fhm \
  && chmod +x /tmp/fhm && /tmp/fhm; echo $?
```

Actual (6.7.6):

```
count after overwrite: 14
cap before: 16
cap after:  32
bytes allocated by the overwrite: 544
rebuilds: 1
rc: 0
1
```

Expected (hashmap.cyr's rule): cap 16, 0 bytes, 0 rebuilds, exit 0. Item 2 is by code reading (`:226-235`): a
refused `_fhm_rehash` returns -1 before the overwrite is applied.

## Root cause

`lib/hashmap_fast.cyr:223-236`: `fhm_set` evaluates `(count + tombs) * 8 >= cap * 7` and rebuilds, then calls
`_fhm_insert` (`:239`), which is the first code to find out whether `key` is present (`:251-258`).

## Proposed fix

Mirror `map_set_a`: probe for the key first (a find half of `_fhm_insert`); on a hit, store the value and return 0
with no trigger check; only a NEW key runs the trigger and the place. Add rows to
`tests/tcyr/stdlib/hashmap_fast_rebuild_in_place.tcyr` (an overwrite at the trigger allocates nothing, keeps the
arrays, and succeeds with the allocator exhausted). ⚠ This changes WHEN the table rebuilds, which a caller can
observe (`fhm_cap`, `alloc_used`, array identity) — when a rebuild happens is the user's to place.
