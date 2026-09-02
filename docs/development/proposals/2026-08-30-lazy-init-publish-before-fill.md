# `lib/chrono.cyr` lazy-init publishes its pointer before filling it

**Filed:** 2026-08-30 (by a samay consumer during its v1.0.4 concurrency audit —
surfaced when threaded harnesses over `epoch_to_date` returned **month 13**)
**Status:** 🟠 **OPTION (a) SHIPPED at v6.5.37 — the MEMORY-ORDERING half remains, pinned to `.38`.** The prescribed fix (fill a local `t`, publish `_chrono_mdays = t` last) is live verbatim in `_chrono_init_mdays`, and the class was swept: chrono was the only site matching `if (_g != 0) { return }` + `_g = alloc(...)` + stores-after-publish across `lib/`, `cbt/` and `src/`. ⛔ **What this proposal asked for and did NOT get** is its own aarch64 note: *"on aarch64's weak model this wants a release fence before the publishing store, matching what `lib/alloc.cyr`'s `_alloc_lock_release` already does — worth deciding explicitly rather than inheriting x86 behaviour."* Verified 2026-09-01: `_alloc_lock_release` does `atomic_fence()` then `atomic_store` on BOTH arches; `_chrono_init_mdays` publishes with a plain store and `lib/chrono.cyr` does not have `atomic_fence` in scope. On a weak model a racing thread can observe the published pointer before the twelve `store64`s that fill it — the same month-13 result, one level down. ⚠ The fence needs `include "lib/atomic.cyr"` in a widely-included module, so the include cost is part of the decision, and the sweep found the same shape in `lib/tls.cyr:211` and `lib/regex.cyr:225` — fix the class. Pinned in `roadmap.md` under `.38`.
**Placement:** `lib/chrono.cyr` only — a self-contained reordering inside one
function; no API, no signature, no behaviour change for single-threaded callers.
**Scope corrected 2026-08-30:** this originally also covered `lib/patra.cyr:453`.
That was misfiled — `lib/patra.cyr` is a **generated bundle** ("Do not edit —
rebuild with: `cyrius distlib`"), so a fix here would be clobbered on the next
regeneration. The same pattern in patra's own source (`src/pcache.cyr:77`) is
filed in **its** repo as
`patra/docs/development/issues/2026-08-30-pcache-publish-before-fill.md`, and is
independent of this proposal — it needs no cyrius change to land. It is
summarised below only as evidence that this is a class rather than an incident.
**Priority:** medium. Not a release-blocker — it needs threads — but it is
silent, and unfixable from outside `lib/`.
**Filed as a proposal, not a patch, deliberately:** the consumer that found this
(samay) is forbidden by its own project rules from modifying vendored `lib/`,
and this is stdlib-wide rather than samay-shaped. Nothing in cyrius was touched.

## The pattern

A lazy initialiser guards on its own output pointer, then **assigns that pointer
before filling the memory behind it**:

```
if (G != 0) { return 0; }     # guard
G = alloc(N);                 # PUBLISHED — G is now non-zero
store64(G, ...);              # ... and only now filled
store64(G + 8, ...);
```

A second thread entering between the assignment and the last store sees `G != 0`,
returns immediately, and reads memory that is still **all zero** — `alloc` is a
bump allocator over kernel-zeroed pages, so there is no garbage to make the bug
loud. The guard is doing exactly what it was written to do; the publish is simply
in the wrong place.

`lib/alloc.cyr` is not at fault and is not implicated: it is properly locked
(CAS + fences, `_threads_active` armed before the clone in `lib/thread.cyr:321`).
Verified separately: 8 threads, 80,000 allocations, 0 overlapping blocks. The
allocation is atomic; the *initialisation* it feeds is not.

## The instance — `lib/chrono.cyr:184-200` (silent wrong result)

```
183  var _chrono_mdays = 0;
184  fn _chrono_init_mdays(): i64 {
185      if (_chrono_mdays != 0) { return 0; }
186      _chrono_mdays = alloc(96);          # <-- published here
187      store64(_chrono_mdays, 31);         # Jan
...      (12 stores)
198      store64(_chrono_mdays + 88, 31);    # Dec
```

`epoch_to_date` (`:212`) calls this on **every** invocation. A racing thread gets
an all-zero month table, so the month loop's `if (days < md) break;` never fires
(`md` is 0, `days` is not negative), it falls out with `m == 12`, and the
function returns:

- **month 13**, and
- **day** = the remaining day-of-year, up to 366.

No crash. `epoch_to_date` is the only calendar decomposition in the stdlib, so any
consumer that turns an epoch into a date across threads can silently get a wrong
date. In samay's case that is a cron expression evaluated against the wrong day.

**Measured** (x86_64, cyrius 6.5.36, 4 threads released from a spin barrier onto
their first `epoch_to_date`):

| shape | wrong dates |
|---|---|
| threads race the first `epoch_to_date` | **14 / 200** process runs |
| same, but one `epoch_to_date(0)` first | **0 / 200** |
| through a real consumer API (samay `cron_expr_matches`) | **1 / 400** |
| same, with the pre-warm | **0 / 400** |

The window is narrow — twelve stores — which is why the realistic rate is ~0.25%
rather than 7%. It does not close on its own; it is simply rare and silent.

## The same pattern elsewhere — patra (filed in patra's repo, not here)

`patra/src/pcache.cyr:77` (bundled into `lib/patra.cyr:453`) has the identical
shape, and worse: **two** globals are involved and only the first is guarded, so
a peer that observes `_pc_keys != 0` can use `_pc_bufs` while it is still `0` — a
null dereference rather than a wrong value.

Not reproduced, not patched, and **not cyrius's to fix** — it belongs to patra
and is filed there. Noted here purely because a five-second mechanical scan found
two instances, which is the argument for treating the pattern rather than the
incident.

## Prior art already in the tree: `lib/bayan.cyr`

`_d_init_tables` (`lib/bayan.cyr:2551-2664`) does it correctly, with a separate
flag published **last**:

```
2552      if (_D_TABLES_INIT == 1) { return 0; }
2553      store64(&_D_POW10_SIG + 0, ...);     # fill first
...
2663      _D_TABLES_INIT = 1;                  # publish last
```

A racing thread either sees `0` and redundantly re-fills with identical constants
(benign — same bytes) or sees `1` and finds the tables complete. There is no
window. So the house already has the right idiom; `chrono` and `patra` just
predate or missed it.

Note `_d_init_tables` also writes into **static** arrays rather than an alloc'd
buffer, which is what makes a benign double-fill possible. That distinction
matters for the fix below.

## Fix shape (described, NOT applied)

Two options, both local to one function:

**(a) Fill a local, publish last.** Preferred where the buffer is alloc'd, because
it keeps a single allocation and needs no extra global:

```
if (_chrono_mdays != 0) { return 0; }
var t = alloc(96);
store64(t, 31);
...
store64(t + 88, 31);
_chrono_mdays = t;        # publish only once fully built
```

A racing thread now sees either `0` (and builds its own — a leaked 96 bytes, once
per process, in a bump allocator that never frees anyway) or a complete table.
Both outcomes are correct. On x86 the store ordering needed is already implied;
on aarch64's weak model this wants a release fence before the publishing store,
matching what `lib/alloc.cyr`'s `_alloc_lock_release` already does — worth
deciding explicitly rather than inheriting x86 behaviour.

**(b) A separate `_INIT` flag published last**, exactly as `_d_init_tables` does.
Needed where more than one global has to become visible together; `chrono` has
only one, so it does not need this.

Either shape works here; (a) is the smaller edit.

## Why it is worth doing

- It cannot be fixed by consumers. `lib/` is vendored, and at least one
  first-party project (samay) has a hard rule against modifying it. The only
  workaround from outside is to force the initialiser to run while still
  single-threaded — samay now ships `samay_init()` doing exactly that, and every
  other threaded consumer would have to invent the same thing independently.
- The `chrono` instance is **silent**. A wrong date is not an obvious failure; it
  surfaces later as a wrong scheduling decision, a wrong log timestamp, or a
  wrong ISO-8601 string.
- It is a **class**, not an incident: a mechanical scan for
  `if (G != 0) { return ... }` followed by `G = alloc(...)` found two instances
  across the vendored tree in a few seconds — this one and patra's. That scan is
  cheap enough to be worth running as a lint, or once across the first-party
  repos, since each project owns its own copy of the idiom.

## Reproduction

The harness that produced the 14/200 figure — four threads on a spin barrier,
each calling `epoch_to_date(1756512000)` once and checking for `month == 8`,
`day == 30` — is trivially reconstructable from the description above and was
built against 6.5.36 with `CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1`. Ask the filer if a
copy is wanted in `tests/` or `fuzz/`.
