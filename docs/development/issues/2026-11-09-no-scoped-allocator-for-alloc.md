# A consumer can't contain what the libraries it calls allocate: `alloc` has no scope to route it to an arena, and `alloc_reset` frees the consumer's own blocks too — open

**Status:** 🟡 **OPEN** — verified on 6.7.18 (x86_64), 2026-11-09.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-11-09, by impetus's Rust → Cyrius port (M0 step 9), probing hisab 3.4.1 on a physics step
**Reporter:** impetus 2.0.0 port
**Cyrius version at time of report:** 6.7.18
**Severity:** **High for any long-running consumer of a library that returns allocated values.** Nothing fails;
memory grows without bound, and the one reclaim (`alloc_reset`) corrupts the caller.

## Summary

`alloc` (`lib/alloc.cyr`) is a bump allocator with no free and no redirection: every `alloc(n)` comes from the
process-global heap. A library that returns a fresh value per call allocates there, which is the documented hisab
convention (every `HVec3` / `HQuat` / matrix result, 574 `alloc` sites in the 3.4.1 bundle).

A consumer that calls such a library once per frame, step or request has no way to contain it:
- **Its arena can't receive the library's allocations.** `arena_*` and the `Allocator` vtable (`alloc_via`) exist,
  but the library calls `alloc`, not `alloc_via`, and `alloc` can't be pointed elsewhere.
- **`alloc_reset()` is not an option for a library.** It reclaims the memory, but also every block anyone still
  holds, the consumer's own state included (the repro shows the next allocation landing on a live block).

Measured by impetus (`impetus/docs/development/port-parity.md` §4.1): the global heap per hisab call, never
returned.

| Call | Bytes |
|---|---|
| `hvec3_add`, `hvec3_cross`, `hquat_rotate_vec3` | 24 |
| `m3_mul_vec3` | 48 |
| `gjk_epa_3d`, two overlapping spheres | 105,920 |
| `detect_islands`, 100 bodies / 50 contacts | 10,936 |
| `bvh_build`, 100 boxes | 20,792 |

A 3D physics scene with 100 touching pairs would leak about 10 MB per step through `gjk_epa_3d` alone, 600 MB a
second at 60 Hz. impetus has had to keep hisab off its step path entirely (impetus ADR 0007, amendment), so the
problem blocks the ecosystem's "use hisab" direction for every per-frame consumer (kiran, soorat, impetus), not only
this port.

## Reproduction

[`repros/2026-11-09-no-scoped-allocator-for-alloc.cyr`](repros/2026-11-09-no-scoped-allocator-for-alloc.cyr):

```sh
cyrius build docs/development/issues/repros/2026-11-09-no-scoped-allocator-for-alloc.cyr /tmp/nsa
/tmp/nsa; echo "exit=$?"
# 1000 steps x 100 library calls: global heap grew 2400000 bytes; the step arena received 0 bytes
# after alloc_reset, a new 64-byte block is at the consumer's live `world`: yes
# world[0] was 42, now 7
# exit=1
```

## Proposed fix

**An allocation scope that `alloc` honours.** A stack of allocators, of which the global bump is the bottom:

```cyrius
alloc_push(step_arena_allocator);   # every alloc() below goes to the arena
    hisab_call(..);                 # unchanged library code
alloc_pop();                        # back to the previous allocator
arena_reset(step_arena);            # reclaims exactly the scoped allocations
```

- `alloc(n)` checks one global (the top of the scope stack, null for the bump) and dispatches through
  `alloc_via` when it is set. The common unscoped path costs one compare.
- **No library changes.** hisab's 574 call sites, the stdlib containers, and anything else written against `alloc`
  are contained at once. That is the reason to fix it here rather than threading an `Allocator` parameter through
  every library (impetus's fallback request to hisab, H9).
- Thread safety follows `alloc`'s own lock: the scope can be per thread (`thread_local`) or documented as
  process-wide. impetus's step is single-threaded either way.
- Optional: `alloc_scope_used()` for tests to assert that a scope held every allocation.

## Consumer-side workaround

impetus keeps world storage on `freelist` (`fl_alloc` / `fl_free`, measured flat over 100,000 pairs) and step
scratch on a growable arena reset per step (flat over 1,000 steps). It calls hisab only at setup, never on the step
path or in a query, until this or an allocator-taking hisab lands.

## Another consumer: pravash (2026-11-11)

pravash's Rust → Cyrius port (fluid dynamics: SPH, grids, FLIP, MPM) is in the same position as impetus, with its own
numbers (`pravash/docs/development/port-parity.md` §4.1; its conversion ledger L8):
- **SPH's neighbour search** through hisab's hash: 4.1 MB per step at 1,000 particles, about 41 MB per step at 10⁴.
- **A 64² DST pressure solve** through hisab: about 2.5 MB per step.
- **The MLS 3×3 inverse** through ganita: 248 B per particle per step.

Its stand-ins are the same as impetus's: `freelist` for solver storage (0 B over 100,000 pairs) and a growable arena
reset per step for scratch (flat at 2.4 MB over 300 steps of 10⁴ particles). An allocation scope would put hisab and
ganita back on its step path and retire those stand-ins.
