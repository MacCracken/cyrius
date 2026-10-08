# `lib/hashmap_fast.cyr` — the same-capacity rehash allocates fresh arrays and never releases the old ones

**Status:** ✅ **RESOLVED in 6.7.3** (repair lane hashmap-fast) — the same-capacity rebuild is in place (`_fhm_rebuild_in_place`) and allocates nothing: the reproduction below now allocates 278,528 B (the one doubling), with 3 in-place rebuilds after it and the same three arrays. Rows: `tests/tcyr/stdlib/hashmap_fast_rebuild_in_place.tcyr`. See CHANGELOG [6.7.3].
**Placement:** was unpinned (6.x-line backlog, "Found by the 6.6.20 lanes"); promoted into the 6.7.3 repair lane.
**Discovered:** 2026-10-06 by the 6.6.20 closeout review of lane l-hash (RLM-03). That lane fixed the same leak in `lib/hashmap.cyr`.
**Severity:** Medium. Memory grows without bound in a long-running process that churns an fhm map at a steady size.
**Affects:** cycc 6.6.8 → 6.6.20. 6.6.8 added the same-capacity rehash. Before 6.6.8 the table only ever doubled.

## Summary

6.6.8 fixed the tombstone defect in `lib/hashmap_fast.cyr`. Since then `fhm_set` rebuilds when
live + tombstones reach 87.5%. It doubles only when the live load alone is past 43.75%; otherwise it
rebuilds at the **same** capacity (`lib/hashmap_fast.cyr:214-221`). Both paths go through
`_fhm_rehash` (`:284-313`), which allocates three fresh arrays: `cap` metadata bytes plus two arrays
of `cap * 8`. It never releases the old three. The default allocator is a bump allocator whose free
is a no-op, and fhm calls `alloc()` directly, so each same-capacity rebuild leaks about 17 B per slot
(278,528 B at 16,384 slots). The rebuilds keep coming for as long as the churn does.

A second effect: a same-capacity rebuild is an allocation, so it can fail. `fhm_set` can then return
-1 with the allocator exhausted, even though the insert needed no new memory.

`lib/hashmap.cyr` had this exact leak in its first 6.6.20 cut (27.5 MB over 1M rounds at 5,000
live). 6.6.20 fixed it there with an allocation-free, in-place, same-capacity rebuild
(`_map_rebuild_in_place` / `_map_u64_rebuild_in_place`). hashmap_fast did not get that half.

How fast it leaks depends strongly on the load. `fhm_delete` writes EMPTY instead of a tombstone
whenever the slot's 16-slot group still has an EMPTY slot (`:353-365`). So tombstones collect only in
groups that once filled up, and a same-capacity rebuild is rare at a light live load:

| live keys / slots | delete+insert rounds | same-capacity rebuilds | bytes leaked |
|---|---|---|---|
| 5,000 / 16,384 (30.5 %) | 3,000,000 | 0 | 0 |
| 7,000 / 16,384 (42.7 %) | 3,000,000 | 3 | 835,584 (3 × 278,528) |

Measured with the reproduction below on x86_64 at 6.6.20 (base e696746d). Each run also allocated
one doubling (8,192 → 16,384 slots, 278,528 B), which is not counted in the table.

## Reproduction

Build with `cat fhm_leak.cyr | build/cycc > fhm_leak && ./fhm_leak` from the repo root:

```cyr
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/hashmap_fast.cyr"

var tmpd = 0;
# write "k<digits of i>" into buffer k
fn _wk(k, i): i64 {
    store8(k, 107);
    var n = i;
    var d = 0;
    if (n == 0) { store8(tmpd, 48); d = 1; }
    while (n > 0) { store8(tmpd + d, 48 + (n % 10)); n = n / 10; d = d + 1; }
    var j = 0;
    while (j < d) { store8(k + 1 + j, load8(tmpd + d - 1 - j)); j = j + 1; }
    store8(k + 1 + d, 0);
    return k;
}

fn _say(n, msg, len): i64 { fmt_int(n); syscall(1, 1, msg, len); return 0; }

# Hold `live` keys; each round deletes the oldest and inserts a new one. A ring of live+1 key
# buffers, so the churn itself allocates nothing.
fn run(live, rounds): i64 {
    var ring = live + 1;
    var bufs = alloc(ring * 24);
    var m = fhm_new();
    var i = 0;
    while (i < live) { fhm_set(m, _wk(bufs + i * 24, i), i); i = i + 1; }
    var s = 0;
    var cap0 = fhm_cap(m);
    var u0 = alloc_used();
    var rehashes = 0;
    var meta = load64(m);
    while (s < rounds) {
        fhm_delete(m, bufs + (s % ring) * 24);
        fhm_set(m, _wk(bufs + ((s + live) % ring) * 24, s + live), s);
        if (load64(m) != meta) {
            if (fhm_cap(m) == cap0) { rehashes = rehashes + 1; }
            meta = load64(m);
            cap0 = fhm_cap(m);
        }
        s = s + 1;
    }
    _say(rehashes, " same-capacity rehashes\n", 24);
    _say(alloc_used() - u0, " bytes allocated during the churn\n", 34);
    return 0;
}

fn main(): i64 { alloc_init(); tmpd = alloc(32); run(7000, 3000000); return 0; }
var r = main();
syscall(60, 0);
```

Expected: once the table has reached its steady size, the churn allocates nothing. Actual:

```
3 same-capacity rehashes
1114112 bytes allocated during the churn
```

That is one doubling plus three same-capacity rebuilds, each 278,528 B, and none of them released.

## Root cause

`_fhm_rehash(m, new_cap)` is the only rebuild path, and it always rebuilds into fresh arrays. That is
correct for a doubling. For a rebuild at the same capacity the old arrays are already the right size,
and nothing frees them.

## Proposed fix

Rebuild at the same capacity in place, with no allocation, the way 6.6.20 did for `lib/hashmap.cyr`.
Keep `_fhm_rehash` for doubling only.

The group layout makes the in-place walk different from the linear-probe one in hashmap.cyr. Two
invariants must hold afterwards:
- The probe ends at the first group that has an EMPTY slot.
- `fhm_delete` relies on "a group that was full when a later key was placed never regains an EMPTY slot".

The SwissTable answer is abseil's `drop_deletes_without_resize`: turn every tombstone into EMPTY, mark
every live slot as "to be placed", then visit each such slot. If it already sits in the first group on
its probe path that has room, keep it. Otherwise move it to the first free slot there, or swap it with
a still-unplaced entry and re-visit. That description is speculation as far as fhm is concerned; the
implementer verifies it against fhm's own probe and delete rules.

The decision belongs to the fix's own slot. A same-capacity rebuild into a retained spare array is
the cheaper shape, but it doubles the table's resident memory.

Acceptance criteria:
1. Hold a live load just under 43.75% (e.g. 7,000 keys in 16,384 slots) through enough delete+insert
   churn for at least three same-capacity rebuilds, after the one doubling. `alloc_used()` must not
   move, and `load64(m)`, `load64(m + 8)` and `load64(m + 16)` must stay the same arrays.
2. Every live key reads back after each rebuild, deleted keys stay deleted, and a miss stops at the
   first group with an EMPTY slot.
3. A `tests/tcyr/stdlib/` test shaped like `hashmap_tombstones.tcyr`'s `_steady_alloc_rows`, plus
   fixed-layout rows for a chain that crosses a group refilled by the walk. Mutation-check it: an
   allocating rebuild, and a walk that skips re-placement, must each fail a row.

## Consumer-side workaround (if any)

None needed for correctness: answers stay right, only memory grows. A consumer that churns an fhm
map for a long time can rebuild it into a fresh `fhm_new()` itself. That releases nothing under the
bump allocator either, so it only helps with an allocator that frees.

## Resolution (6.7.3)

Not the abseil swap loop: a group version of `lib/hashmap.cyr`'s anchor walk. The anchor is the
first group with an EMPTY slot, picked BEFORE the tombstones become EMPTY (no live probe path
crosses it); every tombstone then becomes EMPTY; the walk visits each group once, from the one after
the anchor round to the anchor ITSELF, and moves each entry to the first group with an EMPTY slot on
its probe path when that group lies before its own. Both differences from hashmap.cyr are
load-bearing — a mutant of each fails rows. With no group holding an EMPTY slot (metadata written
outside the API) it falls back to `_fhm_rehash` at the same capacity.

Acceptance: AC1's steady rows hold 56 live in 128 slots (55 = 42.97% at the trigger; 9 rebuilds in
100,000 rounds, ~25 ms) rather than 7,000 in 16,384, which needs ~3M rounds for 3 rebuilds; the
7,000 / 16,384 figure was measured once for the CHANGELOG (1,114,112 B before, 278,528 B after).
AC2 and AC3 are rows of the same file; the four mutants (allocating rebuild, no re-placement, anchor
picked after the conversion, anchor group skipped) fail 8, 11, 2 and 2 rows.
