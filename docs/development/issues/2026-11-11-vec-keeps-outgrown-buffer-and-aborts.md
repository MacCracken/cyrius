# `vec_push_a` keeps every outgrown buffer even through a freeing Allocator, and `vec_get` / `vec_set` abort on a bad index — open

**Status:** 🟡 **OPEN** — verified on cyrius 6.7.18 (x86_64 Linux ELF), 2026-11-11.
**Discovered:** 2026-11-11, by pravash's Rust → Cyrius port (M1 part 3, `ParticleSoa`).
**Reporter:** pravash 2.0.0 port (conversion ledger L13; `pravash/docs/development/pravash-port-plan.md` §8).
**Severity:** **Medium.** Nothing computes wrong. A library that wants a growable array can't use `vec` on a flat heap:
- it can't keep a step loop's memory flat;
- it can't release a vector's storage;
- it can't index without risking an abort, which library code must never do.

## Summary

pravash ports Rust's `ParticleSoa`, whose 18 fields are public `Vec<f64>` / `Vec<u8>`. Callers push to them, index
them and truncate them independently. `vec` would be the natural counterpart: its slots are 8-byte words, so f64
bits fit. Two things stop it.

1. **Growth never frees, even through an Allocator that can.** `vec_push_a(a, v, val)` allocates the doubled buffer
   with `alloc_via(a, ..)`, copies, and never calls `free_via(a, old)`. That is right for the bump and arena
   allocators, whose free is a no-op. It is not right for an Allocator with a real free, such as one over
   `fl_alloc` / `fl_free`. Every outgrown buffer stays allocated: a vector pushed to n elements holds about 2n slots
   of dead buffers. There is no `vec_free` either, so even the live buffer can't be returned.
2. **A bad index aborts.** `vec_get` and `vec_set` exit the process (status 1, "vec: index out of bounds") on an
   index outside the length. Rust's `v[i]` panics there too. But a Cyrius library may not abort: pravash's rule, and
   impetus's, is that every library function returns a value. So a library has to bounds-check every access itself,
   or not use `vec`.

## Reproduction

`docs/development/issues/repros/2026-11-11-vec-keeps-outgrown-buffer-and-aborts.cyr`:

```sh
cyrius build docs/development/issues/repros/2026-11-11-vec-keeps-outgrown-buffer-and-aborts.cyr /tmp/vecgrow
/tmp/vecgrow; echo "exit=$?"
```

It builds an Allocator over the freelist that counts its calls, pushes 4,096 words through `vec_push_a`, and
prints the counts. Then it calls `vec_get` one past the end:

```text
allocs through the Allocator: 10 (header, first buffer, then one per growth step); frees: 0
now vec_get(v, 4096), one past the end:
vec: index out of bounds
exit=1
```

## Ask

1. **Free on growth.** `vec_push_a` (and every other growing path) calls `free_via(a, old_data)` after the copy.
   It is a no-op for bump and arena, so nothing changes for them.
2. **`vec_free_a(a, v)`**, which releases the data buffer and the header through the Allocator.
3. **Non-aborting access.** Either `vec_get` returns a value on a bad index, or there are checked variants
   (`vec_try_get(v, i, out)`: 1 / 0; `vec_try_set`) for library code. The abort can stay the default for
   programs.

Until then pravash uses a 70-line freelist column of its own (`src/column.cyr`: push with doubling that frees the
old buffer, `drop`, and NaN / 0 on a bad index), marked `UPSTREAM(L13)`. It converts when `vec` can do this.
