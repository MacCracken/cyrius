# thread-local slot namespace has no allocator — libs hardcode integer slots and collide — RESOLVED

**Filed:** 2026-07-01 (surfaced while root-causing the multiworker-TLS RECORD_LAYER bug)
**Severity:** Medium — a latent silent-corruption class; one instance shipped (sigil/patra).
**Component:** `lib/thread_local.cyr` (the `thread_local_get/set` slot namespace).

> **RESOLVED in v6.4.65** (CHANGELOG [6.4.65]). Added `thread_local_alloc()` — a
> process-global counter **based at 16**, so allocator-managed lib slots (≥ 16)
> can never alias the frozen 0-15 app/legacy range. sigil (3.12.1) and patra
> (1.12.12) were migrated off their hardcoded literals at source and re-vendored;
> each claims its slot(s) once via a CAS-gated ensure helper. The collision class
> is now closed **structurally**, not by convention. `TLOCAL_MAX_SLOTS` 16 → 128
> and the Windows per-thread block grew to match; the macOS/agnos/foreign arrays
> already held 128 slots. Gated by `tests/tcyr/vr01_tls_alloc.tcyr` (real hardware)
> + the rewritten `tests/thread_local_slot_collision.sh`.
>
> **Premise correction:** the "Fix" section below names sandhi as a consumer to
> migrate, and the old registry comment called `_SANDHI_RPC_POLICY_SLOT = 16` a
> latent OOB slot. Checked against live source: **sandhi does not use this
> namespace** — that constant is a 16-byte policy-record stride, never passed to
> `thread_local_get/set`. sandhi needed no change. One consumer the filing did
> *not* name — `hoosh`'s `src/lib/trace.cyr` (`TRACE_SLOT = 1`, a downstream tool,
> not a vendored stdlib) — should adopt `thread_local_alloc()` too; tracked as a
> downstream follow-up (it does not affect the cyrius-side fix).

## Problem

`thread_local_get(slot)` / `thread_local_set(slot, val)` address a SHARED per-thread
integer slot space (`TLOCAL_MAX_SLOTS = 16`, `fs:[slot*8]`). Every library that wants
per-thread state **hardcodes** a slot index. There is no allocator and no registry, so
two libraries linked into one program can pick the same slot and silently clobber each
other's per-thread state.

This already bit production: **sigil** (crypto bank lane, slot 0) collided with **patra**
(SQL-parse scratch, slots 0-4). In a server linking both, a patra query overwrote sigil's
crypto bank → the next `cbank()` indexed the wrong lane of the process-global banked
crypto buffers → TLS handshake key-schedule corruption → `RECORD_LAYER_FAILURE`
(the yeo-cy-test / SecureYeoman bug, fixed v6.3.25 by hand-moving sigil to slot 8 +
documenting a reservation registry in `thread_local.cyr`). The registry is a stop-gap.

## Fix

Add an ALLOCATOR so libs stop hardcoding:

    fn thread_local_alloc(): i64   # atomically hand out the next free slot (process-global counter)

Each lib calls it ONCE at init and stores the returned slot in its own global (as sigil
already does with `_SIGIL_CBANK_SLOT`), instead of `= <literal>`. Migrate patra + sigil +
sandhi + any consumer off hardcoded indices. Bump `TLOCAL_MAX_SLOTS` (and the macOS/agnos
`_tlocal_macos`/`_tlocal_agnos` arrays) if 16 becomes tight — the Linux block is already
4096 B (512 slots), only macOS/agnos cap at 16. Cross-repo (touches vendored patra/sigil/
sandhi), so coordinate a synchronized bump.
